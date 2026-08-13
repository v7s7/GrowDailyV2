#!/usr/bin/env node
/**
 * Explain, day by day, exactly why every participant in a room has the number
 * they have. Read-only - writes nothing, ever.
 *
 * Built because reasoning about room progress from screenshots kept going
 * wrong. Everything the app's own sync looks at is printed here side by side:
 * which habit each person linked, the RAW square state for that habit on each
 * day of the room, whether that state actually counts, and what the stored
 * totals say. If a number looks wrong, the reason is on this page.
 *
 * The single most common surprise it surfaces: a square can be `partial`
 * (yellow) rather than `complete` (green). The Grid's tap cycle is
 * none -> partial -> complete, so ONE tap leaves a yellow square that reads
 * as "done" to a person but does not count anywhere in the app -
 * SquareState.isGreen is `complete || bonus` only.
 *
 * Usage:
 *   node diagnose_room.js --room=A8GEL7
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
if (!roomCode) fail('Usage: node diagnose_room.js --room=CODE');

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(KEY_PATH)) });
const db = admin.firestore();

const GREEN = new Set(['complete', 'bonus']); // SquareState.isGreen
const DECLINED = '__declined__';

function toDate(v) {
  if (!v) return null;
  if (typeof v.toDate === 'function') return v.toDate();
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}
function keyOf(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function addDays(d, n) {
  const c = new Date(d);
  c.setDate(c.getDate() + n);
  return c;
}
/** Saturday-start week, matching DateTimeGameExt.startOfDisplayWeek. */
function weekStart(d) {
  const iso = d.getDay() === 0 ? 7 : d.getDay(); // 1=Mon..7=Sun
  return addDays(d, -((iso - 6 + 7) % 7));
}

(async () => {
  const roomSnap = await db.collection('rooms').doc(roomCode).get();
  if (!roomSnap.exists) fail(`No room "${roomCode}".`);
  const room = roomSnap.data() || {};

  const start = toDate(room.startDate);
  if (!start) fail('Room has no startDate.');
  const end = toDate(room.endDate);
  // The app's "today" is its EFFECTIVE day, not the wall clock one: the
  // boundary sits at kDayCutoffHour (6am), so before 6am the app is still
  // counting yesterday. Without this shift the report said "3 days elapsed"
  // while the app showed "of 2", which reads like a counting bug and isn't.
  const DAY_CUTOFF_HOUR = 6;
  const todayMid = new Date(Date.now() - DAY_CUTOFF_HOUR * 3600 * 1000);
  todayMid.setHours(0, 0, 0, 0);
  const last = end && end < todayMid ? end : todayMid;

  const days = [];
  for (let d = new Date(start); d <= last; d = addDays(d, 1)) days.push(new Date(d));

  console.log(`\n${'='.repeat(74)}`);
  console.log(`ROOM ${roomCode}  ${room.name || ''}`);
  console.log(`${'='.repeat(74)}`);
  console.log(`  status      : ${room.status || '(none)'}   mode: ${room.habitMode || '?'}`);
  console.log(`  startDate   : ${keyOf(start)}`);
  console.log(`  counts thru : ${keyOf(last)}   -> ${days.length} day(s) elapsed`);
  if (Array.isArray(room.sharedHabits) && room.sharedHabits.length) {
    console.log('  shared plan :');
    room.sharedHabits.forEach((h, i) => {
      console.log(`      [${i}] ${h.name}  ${h.frequencyType}/${h.frequencyTarget}` +
                  `${h.removedAt ? '  REMOVED' : ''}`);
    });
  }

  const parts = await db.collection('rooms').doc(roomCode)
      .collection('participants').orderBy('joinedAt').get();

  for (const pDoc of parts.docs) {
    const p = pDoc.data() || {};
    const uid = pDoc.id;
    console.log(`\n${'-'.repeat(74)}`);
    console.log(`${p.displayName || uid}   (${uid})`);
    console.log(`${'-'.repeat(74)}`);

    // Their own habit definitions, for names + cadence.
    const habitsSnap = await db.collection('users').doc(uid)
        .collection('custom_habits').get();
    const habits = {};
    habitsSnap.forEach((h) => { habits[h.id] = h.data() || {}; });

    const linked = Array.isArray(p.linkedHabitIds) ? p.linkedHabitIds : [];
    const names = Array.isArray(p.linkedHabitNames) ? p.linkedHabitNames : [];
    if (linked.length === 0) {
      console.log('  NO LINKED HABITS - nothing can ever count here.');
      continue;
    }

    const counting = [];
    linked.forEach((id, i) => {
      const isDeclined = id === DECLINED;
      const removed = room.habitMode === 'shared' &&
          Array.isArray(room.sharedHabits) &&
          i < room.sharedHabits.length && !!room.sharedHabits[i].removedAt;
      const h = habits[id];
      const label = names[i] || (h && h.name) || '(unnamed)';
      let note = '';
      if (isDeclined) note = 'SKIPPED by this person';
      else if (removed) note = 'REMOVED from plan by leader';
      else if (!h) note = 'NOT in their custom_habits (catalog habit, or deleted)';
      console.log(`  slot[${i}] ${label}` +
                  `${h ? `   ${h.frequencyType}/${h.frequencyTarget}` : ''}` +
                  `${note ? `   << ${note}` : ''}`);
      console.log(`          id: ${id}`);
      if (!isDeclined && !removed) counting.push({ id, label });
    });
    if (counting.length === 0) {
      console.log('  Nothing counting -> 0% is correct.');
      continue;
    }

    // Raw square state per room day, per counting habit.
    const dailySnaps = await Promise.all(
      days.map((d) => db.collection('users').doc(uid)
          .collection('daily').doc(keyOf(d)).get()),
    );

    console.log('\n  day          ' + counting.map((c) =>
        c.label.slice(0, 14).padEnd(16)).join('') + 'counts');
    let greenDays = 0;
    for (let i = 0; i < days.length; i++) {
      const dk = keyOf(days[i]);
      const raw = dailySnaps[i].exists
          ? (dailySnaps[i].data() || {}).squareStates || {} : {};
      const cells = counting.map((c) => {
        const st = raw[c.id] === undefined ? '-' : String(raw[c.id]);
        return (GREEN.has(st) ? `${st} OK` : st).padEnd(16);
      });
      const nGreen = counting.filter((c) => GREEN.has(String(raw[c.id]))).length;
      if (nGreen > 0) greenDays++;
      console.log(`  ${dk}   ${cells.join('')}${nGreen}/${counting.length}`);
    }

    const doneMap = p.dailyDoneCount || {};
    const schedMap = p.dailyScheduledCount || {};
    const okWeeks = Array.isArray(p.quotaOkWeeks) ? p.quotaOkWeeks : [];
    const storedTotal = days.reduce((s, d) => {
      const dk = keyOf(d);
      const sch = schedMap[dk] === undefined ? counting.length : schedMap[dk];
      const dn = doneMap[dk] || 0;
      return s + (sch === 0 ? 1 : Math.min(1, dn / sch));
    }, 0);

    console.log(`\n  STORED dailyDoneCount      : ` +
        `${Object.keys(doneMap).length ? JSON.stringify(doneMap) : 'empty'}`);
    console.log(`  STORED dailyScheduledCount : ` +
        `${Object.keys(schedMap).length ? JSON.stringify(schedMap) : 'empty'}`);
    console.log(`  STORED quotaOkWeeks        : ` +
        `${okWeeks.length ? okWeeks.join(', ') : 'empty (no rest day is excused)'}`);
    console.log(`  habitRules recorded        : ` +
        `${p.habitRules ? Object.keys(p.habitRules).length : 0}`);
    console.log(`\n  Days with a GREEN square   : ${greenDays} of ${days.length}`);
    console.log(`  App shows (from stored)    : ` +
        `${Math.round(storedTotal * 10) / 10} of ${days.length}` +
        `  = ${Math.round(storedTotal / days.length * 100)}%`);
    if (greenDays !== Math.round(storedTotal)) {
      console.log(`  >> MISMATCH: real squares say ${greenDays}, stored says ` +
          `${Math.round(storedTotal * 10) / 10}. Either their app has not ` +
          `synced\n     since, or a past day is being held down by the ` +
          `anti-backdating cap.`);
    }
    console.log(`  This week (${keyOf(weekStart(last))}) starts Saturday.`);
  }
  console.log('');
  process.exit(0);
})().catch((e) => fail(e.message));
