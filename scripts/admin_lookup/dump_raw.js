#!/usr/bin/env node
/**
 * Dump the exact raw Firestore fields behind one room participant and their
 * linked habit(s) — every field, unfiltered, exactly as stored. Read-only,
 * writes nothing.
 *
 * Built for the one question diagnose_room.js can't answer: WHY a sync
 * never wrote anything, as opposed to what it wrote. diagnose_room.js
 * already tells you a participant's stored totals don't match their real
 * Grid squares; this tells you the raw shape of everything
 * syncLinkedHabitsProgress reads before it decides what to write — the
 * participant doc's own fields (down to their exact JS type, not just
 * value — Timestamp vs string vs undefined all print differently below)
 * and the full custom_habits doc for every habit they've linked into this
 * room, which is what createdAt/archivedAt/frequencyType/frequencyTarget/
 * scheduledWeekdays actually look like on their account right now, not
 * what a working account's habit is assumed to look like.
 *
 * Usage:
 *   node dump_raw.js --room=A8GEL7
 *   node dump_raw.js --room=A8GEL7 --user=sevend7@gmail.com
 *
 * Without --user, dumps every participant in the room. With --user, dumps
 * just that one (email or uid).
 */

'use strict';

const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, 'service-account.json');

function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}

if (!fs.existsSync(KEY_PATH)) {
  fail('Missing scripts/admin_lookup/service-account.json.');
}

const args = {};
for (const raw of process.argv.slice(2)) {
  const m = raw.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) args[m[1]] = m[2] === undefined ? true : m[2];
}
const roomCode = args.room && String(args.room).trim().toUpperCase();
if (!roomCode) fail('Usage: node dump_raw.js --room=CODE [--user=<email or uid>]');

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(KEY_PATH)) });
const db = admin.firestore();

/** Prints every field with its JS type in brackets — the whole point is
 * telling a Firestore Timestamp apart from a plain string, a number apart
 * from a numeric string, and a present-but-null field apart from a field
 * that's simply absent, none of which a plain console.log(JSON) makes
 * obvious (Timestamps in particular print as an opaque object unless
 * you ask for .toDate(), and JSON.stringify silently drops undefined
 * keys, which is exactly the difference that matters here). */
function dumpFields(obj, indent = '    ') {
  if (obj === null || obj === undefined) {
    console.log(`${indent}(document does not exist / has no data)`);
    return;
  }
  const keys = Object.keys(obj).sort();
  if (keys.length === 0) {
    console.log(`${indent}(empty — no fields at all)`);
    return;
  }
  for (const k of keys) {
    const v = obj[k];
    let shown, type;
    if (v && typeof v.toDate === 'function') {
      type = 'Timestamp';
      shown = v.toDate().toISOString();
    } else if (Array.isArray(v)) {
      type = `Array(${v.length})`;
      shown = JSON.stringify(v);
    } else if (v && typeof v === 'object') {
      type = 'Map';
      shown = JSON.stringify(v);
    } else {
      type = v === null ? 'null' : typeof v;
      shown = JSON.stringify(v);
    }
    console.log(`${indent}${k.padEnd(24)} [${type}]  ${shown}`);
  }
}

(async () => {
  const roomSnap = await db.collection('rooms').doc(roomCode).get();
  if (!roomSnap.exists) fail(`No room "${roomCode}".`);
  const room = roomSnap.data() || {};

  console.log(`\n${'='.repeat(74)}`);
  console.log(`ROOM ${roomCode}`);
  console.log(`${'='.repeat(74)}`);
  dumpFields(room);

  let parts = await db.collection('rooms').doc(roomCode)
      .collection('participants').orderBy('joinedAt').get();
  let docs = parts.docs;

  if (args.user) {
    const { resolveAccount } = require('./lib/fetchAccount');
    const { uid } = await resolveAccount(String(args.user).trim());
    docs = docs.filter((d) => d.id === uid);
    if (docs.length === 0) fail(`"${args.user}" resolved to ${uid}, who isn't in room ${roomCode}.`);
  }

  for (const pDoc of docs) {
    const p = pDoc.data() || {};
    const uid = pDoc.id;

    console.log(`\n${'-'.repeat(74)}`);
    console.log(`PARTICIPANT  ${p.displayName || '(no name)'}   uid=${uid}`);
    console.log(`${'-'.repeat(74)}`);

    let authRecord = null;
    try {
      authRecord = await admin.auth().getUser(uid);
    } catch (_) {
      // No Auth record — fine, just note it below.
    }
    console.log('  Auth account:');
    if (authRecord) {
      console.log(`    email                    [string]  "${authRecord.email || ''}"`);
      console.log(`    created                  [string]  "${authRecord.metadata.creationTime}"`);
      console.log(`    last sign-in             [string]  "${authRecord.metadata.lastSignInTime}"`);
      console.log(`    disabled                 [bool]    ${authRecord.disabled}`);
    } else {
      console.log('    (no Firebase Auth record for this uid)');
    }

    console.log('\n  Raw participant doc fields:');
    dumpFields(p);

    const linked = Array.isArray(p.linkedHabitIds) ? p.linkedHabitIds : [];
    const habitIds = linked.filter((id) => id && id !== '__declined__');
    if (habitIds.length === 0) {
      console.log('\n  No linked (non-declined) habits — nothing else to dump.');
      continue;
    }

    for (const habitId of habitIds) {
      const hSnap = await db.collection('users').doc(uid)
          .collection('custom_habits').doc(habitId).get();
      console.log(`\n  custom_habits/${habitId}${hSnap.exists ? '' : '  << DOES NOT EXIST'}:`);
      dumpFields(hSnap.exists ? hSnap.data() : null);
    }
  }
  console.log('');
  process.exit(0);
})().catch((e) => fail(e.stack || e.message));
