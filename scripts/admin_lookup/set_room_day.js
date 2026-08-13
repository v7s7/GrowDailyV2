#!/usr/bin/env node
/**
 * Manually correct one participant's room progress for one day.
 *
 * An escape hatch, not a feature. The app recomputes room progress from each
 * person's real habit history, so this is only for repairing a value that got
 * stored wrong by an older build and won't self-correct.
 *
 * READ THIS BEFORE USING - whether an edit survives is not a guess:
 *
 *   - A PAST day sticks, as long as you don't set it HIGHER than that day's
 *     real Grid squares support. The app caps a past day at whatever was
 *     already stored (the anti-backdating rule - see
 *     syncLinkedHabitsProgress), so a manual value that's at or below the
 *     real one is preserved, and a manual value above it gets pulled back
 *     down to reality on the next sync.
 *   - TODAY never sticks. Today is deliberately never capped, so it always
 *     recomputes from the live square. Editing today is pointless.
 *   - Both devices must already be running the build that has that cap.
 *     On an older build there is no cap at all, so any edit here is wiped by
 *     the next sync from either phone.
 *
 * So: update the apps first, then repair, then it holds.
 *
 * Usage (prints what it WOULD do and changes nothing):
 *   node set_room_day.js --room=ABC123 --user=someone@example.com \
 *        --date=2026-07-29 --done=1
 *
 * Add --confirm to actually write:
 *   node set_room_day.js --room=ABC123 --user=someone@example.com \
 *        --date=2026-07-29 --done=1 --confirm
 *
 * Optional --scheduled=N overrides how many habits counted as due that day.
 * Leave it off unless you know you need it; the app maintains it itself.
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
  fail(
    'Missing scripts/admin_lookup/service-account.json.\n' +
    'See the comment at the top of lookup_user.js for how to get one.'
  );
}

// ---- Args -----------------------------------------------------------------
const args = {};
for (const raw of process.argv.slice(2)) {
  const m = raw.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) args[m[1]] = m[2] === undefined ? true : m[2];
}

const roomCode = args.room && String(args.room).trim().toUpperCase();
const userRef = args.user && String(args.user).trim();
const dateKey = args.date && String(args.date).trim();
const doneRaw = args.done;

if (!roomCode || !userRef || !dateKey || doneRaw === undefined) {
  fail(
    'Usage:\n' +
    '  node set_room_day.js --room=CODE --user=<email or uid> \\\n' +
    '       --date=YYYY-MM-DD --done=N [--scheduled=N] [--confirm]\n\n' +
    'Runs as a dry run unless --confirm is passed.'
  );
}
if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
  fail(`--date must be YYYY-MM-DD, got "${dateKey}".`);
}
const done = Number(doneRaw);
if (!Number.isInteger(done) || done < 0) {
  fail(`--done must be a whole number 0 or greater, got "${doneRaw}".`);
}
const scheduled = args.scheduled === undefined ? null : Number(args.scheduled);
if (scheduled !== null && (!Number.isInteger(scheduled) || scheduled < 0)) {
  fail(`--scheduled must be a whole number 0 or greater, got "${args.scheduled}".`);
}

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

const { resolveAccount } = require('./lib/fetchAccount');

/** Local YYYY-MM-DD for "today", matching the app's own date keys. */
function todayKey() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

(async () => {
  const { uid } = await resolveAccount(userRef);
  const db = admin.firestore();
  const ref = db.collection('rooms').doc(roomCode)
      .collection('participants').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    // Rather than just saying "wrong code", list the rooms this person IS in
    // with their real codes - the code is the room document's own id, which
    // isn't guessable, and hunting for it in the app or the web UI is the
    // slow part of fixing a typo here.
    let hint = '';
    try {
      const mine = await db.collectionGroup('participants')
          .where('uid', '==', uid).get();
      if (mine.empty) {
        hint = '\n\nThat account is not a participant in any room.';
      } else {
        const rows = await Promise.all(mine.docs.map(async (p) => {
          const roomRef = p.ref.parent.parent; // rooms/{code}
          const r = await roomRef.get();
          const d = r.data() || {};
          return `  --room=${roomRef.id}` +
                 `${d.name ? `   (${d.name})` : ''}` +
                 `${d.status ? `   [${d.status}]` : ''}`;
        }));
        hint = `\n\nRooms this account is actually in:\n${rows.join('\n')}`;
      }
    } catch (_) {
      // Needs the participants.uid collection-group index; if it's missing
      // just fall back to the plain message rather than failing differently.
    }
    fail(`No participant ${uid} in room "${roomCode}".${hint}`);
  }
  const d = snap.data() || {};
  const doneMap = d.dailyDoneCount || {};
  const schedMap = d.dailyScheduledCount || {};
  const linked = Array.isArray(d.linkedHabitIds) ? d.linkedHabitIds : [];
  const counted = linked.filter((id) => id !== '__declined__').length;

  console.log(`\nRoom ${roomCode} - ${d.displayName || uid}`);
  console.log(`  uid                : ${uid}`);
  console.log(`  linked habits      : ${counted} counting (${linked.length} slots)`);
  console.log(`\n  ${dateKey} now     : done=${doneMap[dateKey] ?? 0}` +
              `  scheduled=${schedMap[dateKey] ?? `(default ${counted})`}`);
  console.log(`  ${dateKey} after   : done=${done}` +
              `  scheduled=${scheduled === null ? `(unchanged)` : scheduled}`);

  if (dateKey === todayKey()) {
    console.log(
      '\n  WARNING: that is TODAY. Today is never capped by the ' +
      'anti-backdating rule,\n  so the next sync from that phone will ' +
      'recompute it from the live square\n  and this edit will vanish. ' +
      'Edit a past day, or just fix the square in the app.'
    );
  }
  if (done > counted) {
    console.log(
      `\n  WARNING: done=${done} is higher than the ${counted} habit(s) ` +
      `this person\n  actually has linked. The app will pull it back down.`
    );
  }

  if (!args.confirm) {
    console.log('\nDry run. Nothing written. Re-run with --confirm to apply.\n');
    process.exit(0);
  }

  // Sparse maps, same convention the app itself writes: a zero is stored by
  // REMOVING the key, never by writing 0, so reads fall through to the
  // "nothing recorded" default instead of seeing a real zero.
  const update = {};
  if (done > 0) {
    update[`dailyDoneCount.${dateKey}`] = done;
  } else {
    update[`dailyDoneCount.${dateKey}`] = admin.firestore.FieldValue.delete();
  }
  if (scheduled !== null) {
    if (scheduled === counted) {
      update[`dailyScheduledCount.${dateKey}`] =
          admin.firestore.FieldValue.delete();
    } else {
      update[`dailyScheduledCount.${dateKey}`] = scheduled;
    }
  }
  // update(), not set(merge:true): dotted keys are real nested field paths
  // here, which is only true for update - see BUILD_LESSONS.md #10.
  await ref.update(update);
  console.log('\nWritten.\n');
  process.exit(0);
})().catch((e) => fail(e.message));
