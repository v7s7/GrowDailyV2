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

// The one implementation of "is this day short", shared with check_rooms.js
// and the nightly roomsHealthSweep, so all three agree about what is wrong.
const { undercountedDays } = require(
    path.join(__dirname, '..', '..', 'functions', 'room_health.js'));

/// The first day this member's room rule for [id] applies: the earliest
/// `from` across their habitRules periods, or null when none is recorded
/// (fail open, exactly as the client does). Same rule as room_health.js.
function floorOf(part, id) {
  const rules = (part && part.habitRules) || {};
  const periods = Array.isArray(rules[id]) ? rules[id] : [];
  let floor = null;
  for (const r of periods) {
    const from = r && typeof r.from === 'string' ? r.from : null;
    if (from && (floor === null || from < floor)) floor = from;
  }
  return floor;
}

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
  // No cutoff shift. The day rolls at MIDNIGHT (datetime_ext.dart:143, and
  // the doc at :47 says outright that effectiveDay no longer respects the
  // cutoff), and RoomModel.lastCountedDay is DateTime.now().effectiveDay, so
  // the app's last counted day is simply today's calendar date at every
  // hour. This used to subtract 6 hours, quoting a kDayCutoffHour that was
  // 6 and is now 10, and the subtraction dropped the newest day from every
  // table between midnight and 6am: the exact "one day out from what the app
  // shows" confusion the shift was added to prevent, inverted.
  const todayMid = new Date();
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
  // The one field that explains a blank run of days on the strip: while a
  // span covers a day, nobody is graded on it and the app draws it stood
  // down. PBYAS5 (2026-09-08) kept a 3-6 September span after its pause was
  // clipped, and without this line the table below looked complete.
  const spans = Array.isArray(room.pausedSpans) ? room.pausedSpans : [];
  console.log(`  pausedSpans : ${spans.length ? JSON.stringify(spans) : 'none'}`);
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
    // A departed member's record is kept (RoomParticipant.leftAt) so a
    // rejoin cannot reset it; say so rather than grading them as present.
    const left = p.leftAt && p.leftAt.toDate
      ? `   LEFT ${p.leftAt.toDate().toISOString().slice(0, 10)}` : '';
    const away = Array.isArray(p.awaySpans) && p.awaySpans.length
      ? `   away: ${p.awaySpans.map((s) => `${s.from}..${s.to}`).join(', ')}` : '';
    console.log(`${p.displayName || uid}   (${uid})${left}${away}`);
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
      // The day this member's room rule for the habit starts. The app never
      // grades a day before it (RoomParticipant.slotOpenBy), so printing
      // those days against the slot drew them as misses on a habit the room
      // had not asked for yet, and understated every ratio in the counts
      // column. Same floor room_health.js applies, same fail-open when no
      // rule is recorded.
      const floor = floorOf(p, id);
      if (!isDeclined && !removed) {
        if (floor) console.log(`          counts from: ${floor}`);
        counting.push({ id, label, floor });
      }
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
    const squaresByDay = {};
    for (let i = 0; i < days.length; i++) {
      const dk = keyOf(days[i]);
      const raw = dailySnaps[i].exists
          ? (dailySnaps[i].data() || {}).squareStates || {} : {};
      // A slot the room had not asked for on this day is drawn as "n/a" and
      // left out of the denominator, so the counts column reads 1/2 the way
      // the app graded it rather than 1/3.
      const asked = counting.filter((c) => !c.floor || dk >= c.floor);
      const cells = counting.map((c) => {
        if (c.floor && dk < c.floor) return 'n/a'.padEnd(16);
        const st = raw[c.id] === undefined ? '-' : String(raw[c.id]);
        return (GREEN.has(st) ? `${st} OK` : st).padEnd(16);
      });
      const nGreen = asked.filter((c) => GREEN.has(String(raw[c.id]))).length;
      if (nGreen > 0) greenDays++;
      squaresByDay[dk] = raw;
      console.log(`  ${dk}   ${cells.join('')}${nGreen}/${asked.length}`);
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
        `${p.habitRules ? Object.keys(p.habitRules).length : 0}` +
        `${counting.some((c) => c.floor) ?
            `  (${counting.filter((c) => c.floor)
                .map((c) => `${c.label}: from ${c.floor}`).join(', ')})` : ''}`);
    // The four fields that most often ARE the explanation for a number, and
    // none of which this report used to print. A stand-down leaves both
    // sides of the ratio, a stale lastSyncedDay means every day since is
    // graded from nothing, an unresolved slot is a phantom in the room
    // score, and an undated decline is charged from the room's first day.
    const stood = Array.isArray(p.standDownDays) ? p.standDownDays : [];
    console.log(`  STORED standDownDays       : ` +
        `${stood.length ? stood.join(', ') : 'none'}`);
    console.log(`  STORED restAllowanceFrom   : ${p.restAllowanceFrom || 'none'}`);
    console.log(`  Last synced                : ` +
        `${p.lastSyncedDay || '(never)'}` +
        `${p.lastSyncedDay && p.lastSyncedDay < keyOf(last) ?
            '   << STALE: every day since is graded from nothing' : ''}`);
    const sharedCount = Array.isArray(room.sharedHabits) ?
        room.sharedHabits.length : 0;
    if (room.habitMode === 'shared') {
      const declinedFrom = p.slotDeclinedFrom || {};
      console.log(`  Plan slots                 : ` +
          `${linked.length} of ${sharedCount} resolved` +
          `${linked.length < sharedCount ?
              '   << unresolved slots are phantoms in the room score' : ''}`);
      linked.forEach((id, i) => {
        if (id !== DECLINED) return;
        const from = declinedFrom[String(i)] || declinedFrom[i];
        // A WITHDRAWN slot is skipped by every scoring reader (isRemoved),
        // so a decline stamp on it costs nothing and an undated one is not
        // a fault. Saying "charged from the room's first day" about a slot
        // that is charged to nobody is the same kind of false alarm the
        // MISMATCH line used to be.
        const gone = Array.isArray(room.sharedHabits) &&
            i < room.sharedHabits.length && !!room.sharedHabits[i].removedAt;
        if (gone) {
          console.log(`      slot[${i}] declined, and withdrawn from the ` +
              'plan: counts for nobody');
          return;
        }
        console.log(`      slot[${i}] declined ${from ? `from ${from}` :
            '<< NO DATE: charged from the room\'s first day'}`);
      });
    }
    console.log(`\n  Days with a GREEN square   : ${greenDays} of ${days.length}`);
    // The member's OWN stored fraction. The board ranks by the room score
    // (every day against the whole plan, phantoms for unlinked slots), which
    // this script does not compute - so this is not "what the app shows".
    console.log(`  Own days, from stored      : ` +
        `${Math.round(storedTotal * 10) / 10} of ${days.length}` +
        `  = ${Math.round(storedTotal / days.length * 100)}%`);
    // The REAL check, per day, the same one check_rooms.js and the nightly
    // sweep use. What used to be here compared greenDays (a count of days
    // with at least one green square) against storedTotal (a sum of
    // fractional per-day credit, in which a rest day scores a full 1 with no
    // green square behind it). They are different quantities, so the warning
    // fired on healthy data: 12 of the 14 member rows across all seven live
    // rooms, including both members of A8GEL7 whose stored numbers are
    // exactly right. A red MISMATCH on correct data is worse than no check,
    // because the next step is a set_room_day.js write that breaks it.
    const short = undercountedDays({
      days: days.map(keyOf),
      countingIds: counting.map((c) => c.id),
      squaresByDay,
      part: p,
    });
    if (short.length) {
      console.log(`  >> ${short.length} day(s) where the squares beat the ` +
          `stored count:`);
      for (const s of short) {
        console.log(`     ${s.day}: stored ${s.stored}, squares say ${s.real}`);
        console.log(`       fix: node set_room_day.js --room=${roomCode} ` +
            `--user=${uid} --date=${s.day} --done=${s.real} --confirm`);
      }
    }
    console.log(`  This week (${keyOf(weekStart(last))}) starts Saturday.`);
  }
  console.log('');
  process.exit(0);
})().catch((e) => fail(e.message));
