#!/usr/bin/env node
/**
 * End a room's pause early: counting resumes on the day you name, and the
 * room's finish line stays where it is.
 *
 * Why this exists. When a leader extends a room that has already finished,
 * the app asks "when do we pick up?" and records every day between the old
 * ending and that date as paused (rooms/{code}.pausedSpans), so nobody is
 * charged for days the room was dead. On 2026-09-04 the leader of PBYAS5
 * picked 30 days and then tapped the 30th on the calendar, which paused the
 * room for the whole of September: members saw "موقوف" for weeks and no day
 * they did counted. Only the leader can undo that in the app, and only by
 * extending again. This clips the pause from outside instead.
 *
 * What it changes: pausedSpans only. Any span that reaches --from or later
 * is cut to end the day before --from; a span that starts on or after --from
 * is removed. endDate, lengthDays and every participant's progress are left
 * alone; the app regrades the newly live days from each person's real
 * squares on its next sync (syncLinkedHabitsProgress).
 *
 * Usage (dry run, prints what it WOULD do and changes nothing):
 *   node resume_room.js --room=PBYAS5 --from=2026-09-07
 *
 * Add --confirm to actually write:
 *   node resume_room.js --room=PBYAS5 --from=2026-09-07 --confirm
 *
 * --from may not be later than today: resuming on a future date is exactly
 * the trap this script exists to undo.
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
const from = args.from && String(args.from).trim();

if (!roomCode || !from) {
  fail(
    'Usage:\n' +
    '  node resume_room.js --room=CODE --from=YYYY-MM-DD [--confirm]\n\n' +
    'Runs as a dry run unless --confirm is passed.'
  );
}
if (!/^\d{4}-\d{2}-\d{2}$/.test(from)) {
  fail(`--from must be YYYY-MM-DD, got "${from}".`);
}

// The room's days are keyed on Asia/Bahrain, +180 with no daylight saving,
// the basis check_rooms.js uses, never on this machine's own timezone.
// shiftKey works on the key's own digits. See lib/day_key.js.
const { shiftKey } = require(
    path.join(__dirname, '..', '..', 'functions', 'room_health.js'));
const {
  APP_FALLBACK_OFFSET_MINUTES,
  keyAtOffset,
  tsKey,
} = require('./lib/day_key');
const ROOM_OFFSET_MINUTES = APP_FALLBACK_OFFSET_MINUTES;

function dayBefore(key) {
  return shiftKey(key, -1);
}

if (from > keyAtOffset(Date.now(), ROOM_OFFSET_MINUTES)) {
  fail(`--from=${from} is in the future. Resume today or earlier.`);
}

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

(async () => {
  const db = admin.firestore();
  const ref = db.collection('rooms').doc(roomCode);
  const snap = await ref.get();
  if (!snap.exists) fail(`No room "${roomCode}".`);
  const room = snap.data();
  const spans = Array.isArray(room.pausedSpans) ? room.pausedSpans : [];
  const endDate = tsKey(room.endDate, ROOM_OFFSET_MINUTES) || '(open)';

  console.log(`\nRoom ${roomCode} "${room.name}" by ${room.createdByName}`);
  console.log(`  endDate      ${endDate}   (unchanged)`);
  console.log(`  pausedSpans  ${JSON.stringify(spans)}`);

  const cutTo = dayBefore(from);
  const next = [];
  for (const s of spans) {
    if (!s || typeof s.from !== 'string' || typeof s.to !== 'string') continue;
    if (s.from >= from) continue;                    // wholly on or after: gone
    const to = s.to >= from ? cutTo : s.to;          // reaches the resume: cut
    if (s.from <= to) next.push({ from: s.from, to });
  }
  const same = JSON.stringify(next) === JSON.stringify(spans);

  console.log(`\n  resume from  ${from}`);
  console.log(`  new spans    ${JSON.stringify(next)}${same ? '   (no change)' : ''}`);
  if (same) {
    console.log('\nNothing to do.\n');
    process.exit(0);
  }

  if (!args.confirm) {
    console.log('\nDry run. Add --confirm to write this.\n');
    process.exit(0);
  }

  await ref.update({
    pausedSpans: next.length ? next : admin.firestore.FieldValue.delete(),
  });
  console.log(`\nWritten. ${roomCode} counts again from ${from}.\n`);
  process.exit(0);
})().catch((e) => fail(e.stack || String(e)));
