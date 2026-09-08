#!/usr/bin/env node
/**
 * Rooms health check, from a terminal. Read-only: writes nothing, ever.
 *
 * The same two rules the daily Cloud Function sweep applies
 * (functions/room_health.js, functions/index.js roomsHealthSweep), printed
 * for every active room with the exact command that fixes each finding:
 *
 *   ALERT  a pause span that reaches today or later. Nothing in the current
 *          app can write one; it stops every member's days from counting
 *          (PBYAS5, 2026-09-04, read موقوف for three days). Fix with
 *          resume_room.js, or wait for the sweep, which clips it at 04:00.
 *   CHECK  a member whose stored count on a closed day trails their own
 *          squares. Their phone regrades it on its next open; if it has
 *          not, set_room_day.js writes the number. Look at
 *          diagnose_room.js --room=CODE first for a day you do not expect,
 *          because a habit done on a day it was not scheduled can also
 *          show here and is not a fault.
 *   note   a room that carries spans, or was extended: the places where the
 *          two faults above come from.
 *
 * Usage:
 *   node check_rooms.js                 every active room, last 10 closed days
 *   node check_rooms.js --days=30       look further back
 *   node check_rooms.js --room=PBYAS5   one room only
 *
 * Exit code 0 when nothing is wrong, 1 when there is at least one ALERT or
 * CHECK, so it can sit in a cron line or a launchd job and be noticed.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, 'service-account.json');
const {
  clipSpansToPast,
  closedDaysToCheck,
  countingHabitIds,
  todayKeyIn,
  undercountedDays,
} = require(path.join(__dirname, '..', '..', 'functions', 'room_health.js'));

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
const onlyRoom = args.room ? String(args.room).trim().toUpperCase() : null;
const lookback = Math.max(1, parseInt(args.days, 10) || 10);

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(KEY_PATH)) });
const db = admin.firestore();

const TZ = 'Asia/Bahrain';
const DAY_MS = 24 * 60 * 60 * 1000;

function keyOfTs(v) {
  if (!v || typeof v.toDate !== 'function') return null;
  return todayKeyIn(v.toDate().getTime(), TZ);
}

(async () => {
  const nowMs = Date.now();
  const todayKey = todayKeyIn(nowMs, TZ);
  // Yesterday is still payable until 10:00, so the newest fully closed day
  // is the day before yesterday.
  const lastClosed = todayKeyIn(nowMs - 2 * DAY_MS, TZ);

  let roomsSnap;
  if (onlyRoom) {
    const one = await db.collection('rooms').doc(onlyRoom).get();
    if (!one.exists) fail(`No room "${onlyRoom}".`);
    roomsSnap = { size: 1, docs: [one] };
  } else {
    roomsSnap = await db.collection('rooms')
        .where('status', '==', 'active').get();
  }

  console.log(`\nRooms health check   today ${todayKey} (${TZ})   ` +
      `closed days checked: last ${lookback} up to ${lastClosed}`);
  console.log('='.repeat(74));

  let alerts = 0;
  let checks = 0;
  for (const roomDoc of roomsSnap.docs) {
    const room = roomDoc.data() || {};
    const code = roomDoc.id;
    const startKey = keyOfTs(room.startDate);
    const endKey = keyOfTs(room.endDate);
    const lines = [];

    const stored = Array.isArray(room.pausedSpans) ? room.pausedSpans : [];
    const { spans, clipped } = clipSpansToPast(stored, todayKey);
    for (const c of clipped) {
      alerts++;
      lines.push(`  ALERT  pause span ${c.from}..${c.to} reaches today or ` +
          `later: nobody's days count inside it.`);
      lines.push(`         fix: node resume_room.js --room=${code} ` +
          `--from=${todayKey} --confirm   (the 04:00 sweep does the same)`);
    }
    if (clipped.length === 0 && stored.length > 0) {
      lines.push(`  note   pausedSpans ${JSON.stringify(stored)} (dead ` +
          `days between an end and an extension; drawn as dashes)`);
    }
    if (room.lengthDays && startKey && endKey) {
      // startKey + lengthDays - 1 is where the end would be without an
      // extension; a later end means the leader extended.
      const [y, m, d] = startKey.split('-').map(Number);
      const plain = new Date(Date.UTC(y, m - 1, d + room.lengthDays - 1))
          .toISOString().slice(0, 10);
      if (endKey > plain) {
        lines.push(`  note   extended: ends ${endKey}, ${room.lengthDays} ` +
            `days from ${startKey} would have ended ${plain}`);
      }
    }

    if (startKey) {
      const days = closedDaysToCheck({ startKey, endKey, pausedSpans: spans },
          lastClosed, lookback);
      if (days.length > 0) {
        const partsSnap = await roomDoc.ref.collection('participants').get();
        for (const partDoc of partsSnap.docs) {
          const part = partDoc.data() || {};
          const countingIds = countingHabitIds(room, part);
          if (countingIds.length === 0) continue;
          const daySnaps = await Promise.all(days.map((day) => db
              .collection('users').doc(partDoc.id)
              .collection('daily').doc(day).get()));
          const squaresByDay = {};
          days.forEach((day, i) => {
            if (daySnaps[i].exists) {
              squaresByDay[day] =
                  (daySnaps[i].data() || {}).squareStates || {};
            }
          });
          const short = undercountedDays({ days, countingIds, squaresByDay,
            part });
          for (const u of short) {
            checks++;
            lines.push(`  CHECK  ${part.displayName || partDoc.id}  ` +
                `${u.day}: stored ${u.stored}, squares say ${u.real}`);
            lines.push(`         fix: node set_room_day.js --room=${code} ` +
                `--user=${partDoc.id} --date=${u.day} --done=${u.real} ` +
                `--confirm`);
          }
        }
      }
    }

    const status = lines.some((l) => l.startsWith('  ALERT')) ? 'ALERT' :
      lines.some((l) => l.startsWith('  CHECK')) ? 'CHECK' : 'ok';
    console.log(`\n${code}  ${room.name || ''}   ${startKey || '?'} -> ` +
        `${endKey || 'open'}   ${status}`);
    for (const l of lines) console.log(l);
  }

  console.log(`\n${'='.repeat(74)}`);
  console.log(`${roomsSnap.size} room(s) checked: ${alerts} alert(s), ` +
      `${checks} day(s) to check.\n`);
  process.exit(alerts + checks > 0 ? 1 : 0);
})().catch((e) => fail(e.stack || e.message));
