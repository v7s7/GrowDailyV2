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
 *   HELD   the same arithmetic, but the app is holding that day ON PURPOSE:
 *          the square was painted after the day closed, on a day the room
 *          had already graded, so it earned nothing in the app either. Not
 *          a fault, and deliberately printed WITHOUT a repair command. This
 *          report used to print one, and running it on room ELQVF8 for
 *          Aziz's 2026-09-10 would have moved him 65.9% to 68.9% on a
 *          ranked board for a day he did not train.
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
// The app's own close rule, rather than a day-count guess. See day_rules.js.
const { localNowMs, newestClosedKey } = require('./lib/day_rules');
const { offsetOf } = require('./lib/day_key');

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
// The calendar a room's own keys are written on: +180, no daylight saving.
// A MEMBER's days are closed on their own recorded offset instead (see the
// offsetOf call below), which is what a day's close has to be measured
// against when the evidence is a server timestamp.
const ROOM_OFFSET_MINUTES = 180;

function keyOfTs(v) {
  if (!v || typeof v.toDate !== 'function') return null;
  return todayKeyIn(v.toDate().getTime(), TZ);
}

(async () => {
  const nowMs = Date.now();
  const todayKey = todayKeyIn(nowMs, TZ);
  // The newest day that has FULLY closed, on the app's own rule: a day is
  // open until kDayCutoffHour the next morning, so before 10:00 that is the
  // day before yesterday and from 10:00 onward it is yesterday.
  //
  // This used to be a flat `now - 2 days`, which is right for the ten hours
  // before the cutoff and a day short for the other fourteen: run at noon
  // and the newest closed day went unchecked entirely.
  const lastClosed = newestClosedKey(localNowMs(nowMs, ROOM_OFFSET_MINUTES));

  let roomsSnap;
  if (onlyRoom) {
    const one = await db.collection('rooms').doc(onlyRoom).get();
    if (!one.exists) fail(`No room "${onlyRoom}".`);
    roomsSnap = { size: 1, docs: [one] };
  } else {
    // Every room, filtered here rather than by the query. RoomModel
    // .fromFirestore treats a MISSING status as active (rooms predate the
    // lobby era), and a `where('status','==','active')` query cannot match a
    // document that has no such field: on 2026-09-12 that hid ZCNGFT and
    // 5S84CL plus five empty room docs from this check entirely.
    const all = await db.collection('rooms').get();
    const docs = all.docs.filter((d) => {
      const status = (d.data() || {}).status;
      return status === undefined || status === null || status === 'active';
    });
    roomsSnap = { size: docs.length, docs };
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
          // Departed (RoomParticipant.leftAt): the record is kept so a rejoin
          // cannot reset it, but nothing is graded for them while out.
          if (part.leftAt) continue;
          const countingIds = countingHabitIds(room, part);
          if (countingIds.length === 0) continue;
          const [daySnaps, userSnap] = await Promise.all([
            Promise.all(days.map((day) => db
                .collection('users').doc(partDoc.id)
                .collection('daily').doc(day).get())),
            db.collection('users').doc(partDoc.id).get(),
          ]);
          const squaresByDay = {};
          // The write times are the evidence that separates a day the room
          // is holding on purpose from one it genuinely missed. Without them
          // this script printed a set_room_day.js line for the clamp doing
          // its job. createTime never changes a verdict; it only lets the
          // HELD line say the day was first opened on time.
          const lastUpdatedByDay = {};
          const createdByDay = {};
          days.forEach((day, i) => {
            if (!daySnaps[i].exists) return;
            squaresByDay[day] = (daySnaps[i].data() || {}).squareStates || {};
            lastUpdatedByDay[day] = (daySnaps[i].data() || {}).lastUpdated;
            createdByDay[day] = daySnaps[i].createTime;
          });
          const tz = offsetOf(userSnap.exists ? userSnap.data() : null);
          const short = undercountedDays({ days, countingIds, squaresByDay,
            part, lastUpdatedByDay, createdByDay, offsetMinutes: tz.minutes });
          for (const u of short) {
            const who = part.displayName || partDoc.id;
            if (u.held) {
              lines.push(`  HELD   ${who}  ${u.day}: stored ${u.stored}, ` +
                  `squares say ${u.real}, and that is correct`);
              lines.push(`         ${u.why}`);
              lines.push('         no fix: writing this day would pay for a ' +
                  'square the app itself refused to pay for.');
              continue;
            }
            checks++;
            lines.push(`  CHECK  ${who}  ` +
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
