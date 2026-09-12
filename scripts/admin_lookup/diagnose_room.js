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
 * (yellow) rather than `complete` (green). SquareState.isGreen is
 * `complete || bonus` only, so a yellow square is not a done day.
 *
 * It is NOT worth nothing, though, and this comment used to say it was. A
 * جزئي habit is half a habit everywhere in the app: SquareState.xpValue pays
 * it 5 against complete's 10, the reports credit it 0.5, and
 * RoomParticipant.creditFor counts it as half (`done + partialCount * 0.5`).
 * The room stores the count in `dailyPartialCount`. Aziz's تمرين on
 * 2026-09-03 is one, and ELQVF8 scored that day 0.75, not 0.5 and not 0,
 * while this script printed 1/2 for it.
 *
 * Also note the tap cycle is none -> complete now, not none -> partial ->
 * complete; yellow is reachable from the long-press palette and from a
 * counted habit that is part way through its target.
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
const { shiftKey, undercountedDays } = require(
    path.join(__dirname, '..', '..', 'functions', 'room_health.js'));
const {
  APP_FALLBACK_OFFSET_MINUTES,
  keyAtOffset,
  offsetOf,
  storedDateKey,
  tsKey,
} = require('./lib/day_key');
// creditFor and its denominator, ported from room_model.dart. See
// lib/day_rules.js for why this tool now has one copy of the app's rules
// instead of a fresh guess per surface.
const { roomDayCounts, isOpenDayAt, localNowMs } = require('./lib/day_rules');

// The room's days are keyed on Asia/Bahrain, +180 with no daylight saving,
// the basis check_rooms.js uses, never on this machine's own timezone: the
// getDate() arithmetic this replaces keyed a room that starts at Bahrain
// midnight a day early on any machine west of +180. A member's own date
// (leftAt below) uses their users/{uid}.tzOffsetMinutes. See lib/day_key.js.
const ROOM_OFFSET_MINUTES = APP_FALLBACK_OFFSET_MINUTES;
const KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

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

/**
 * Saturday-start week, matching DateTimeGameExt.startOfDisplayWeek. Works on
 * the key's own digits, so it never depends on this machine's timezone.
 */
function weekStartKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=Sun..6=Sat
  const iso = dow === 0 ? 7 : dow; // 1=Mon..7=Sun
  return shiftKey(key, -((iso - 6 + 7) % 7));
}

(async () => {
  const roomSnap = await db.collection('rooms').doc(roomCode).get();
  if (!roomSnap.exists) fail(`No room "${roomCode}".`);
  const room = roomSnap.data() || {};

  const startKey = storedDateKey(room.startDate, ROOM_OFFSET_MINUTES);
  if (!startKey || !KEY_RE.test(startKey)) fail('Room has no startDate.');
  const rawEndKey = storedDateKey(room.endDate, ROOM_OFFSET_MINUTES);
  const endKey = rawEndKey && KEY_RE.test(rawEndKey) ? rawEndKey : null;
  // No cutoff shift. The day rolls at MIDNIGHT (datetime_ext.dart:143, and
  // the doc at :47 says outright that effectiveDay no longer respects the
  // cutoff), and RoomModel.lastCountedDay is DateTime.now().effectiveDay, so
  // the app's last counted day is simply today's calendar date at every
  // hour. This used to subtract 6 hours, quoting a kDayCutoffHour that was
  // 6 and is now 10, and the subtraction dropped the newest day from every
  // table between midnight and 6am: the exact "one day out from what the app
  // shows" confusion the shift was added to prevent, inverted.
  const todayKey = keyAtOffset(Date.now(), ROOM_OFFSET_MINUTES);
  const lastKey = endKey && endKey < todayKey ? endKey : todayKey;
  // The clock in the room's own calendar, for the open-day test below.
  const nowLocal = localNowMs(Date.now(), ROOM_OFFSET_MINUTES);

  // Whole calendar days, stepped on the keys themselves. This lists two days
  // the old loop over instants could drop, both only for a room whose start
  // is not midnight at +180 (no room on 2026-09-11): today while the room
  // runs, and the end day of an ended room whose endDate time of day is
  // earlier than its startDate's.
  const days = [];
  for (let dk = startKey; dk <= lastKey; dk = shiftKey(dk, 1)) days.push(dk);

  console.log(`\n${'='.repeat(74)}`);
  console.log(`ROOM ${roomCode}  ${room.name || ''}`);
  console.log(`${'='.repeat(74)}`);
  console.log(`  status      : ${room.status || '(none)'}   mode: ${room.habitMode || '?'}`);
  console.log(`  startDate   : ${startKey}`);
  console.log(`  counts thru : ${lastKey}   -> ${days.length} day(s) elapsed`);
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
    // The day is the one on THEIR phone (users/{uid}.tzOffsetMinutes). The
    // UTC date this used to print is a day early for a +180 member who left
    // between midnight and 03:00.
    let left = '';
    if (p.leftAt && typeof p.leftAt.toDate === 'function') {
      const userSnap = await db.collection('users').doc(uid).get();
      const tz = offsetOf(userSnap.exists ? userSnap.data() : null);
      left = `   LEFT ${tsKey(p.leftAt, tz.minutes)}` +
          `${tz.assumed ? ` (offset not recorded, +${tz.minutes} assumed)` : ''}`;
    }
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
      days.map((dk) => db.collection('users').doc(uid)
          .collection('daily').doc(dk).get()),
    );

    console.log('\n  day          ' + counting.map((c) =>
        c.label.slice(0, 14).padEnd(16)).join('') + 'room stored');
    let greenDays = 0;
    let storedTotal = 0;
    let gradedDays = 0;
    const squaresByDay = {};
    const lastUpdatedByDay = {};
    const createdByDay = {};
    // 1.5 stays 1.5, 2 prints as 2 rather than 2.0. Latin digits, always.
    const num = (v) => String(Math.round(v * 100) / 100);
    for (let i = 0; i < days.length; i++) {
      const dk = days[i];
      const data = dailySnaps[i].exists ? (dailySnaps[i].data() || {}) : {};
      const raw = data.squareStates || {};
      // A slot the room had not asked for on this day is drawn as "n/a", so
      // the row reads the way the app graded it rather than counting a habit
      // the room had not yet asked for.
      const cells = counting.map((c) => {
        if (c.floor && dk < c.floor) return 'n/a'.padEnd(16);
        const st = raw[c.id] === undefined ? '-' : String(raw[c.id]);
        return (GREEN.has(st) ? `${st} OK` : st).padEnd(16);
      });
      const nGreen = counting.filter((c) => (!c.floor || dk >= c.floor) &&
          GREEN.has(String(raw[c.id]))).length;
      if (nGreen > 0) greenDays++;
      squaresByDay[dk] = raw;
      lastUpdatedByDay[dk] = data.lastUpdated;
      createdByDay[dk] = dailySnaps[i].exists ? dailySnaps[i].createTime : undefined;

      // ── The counts column, from what the ROOM stored ──────────────────
      // It used to print greens/asked, counted off the squares, which is a
      // different quantity from the one the app scores and disagreed with it
      // twice over: it ignored the floors on the denominator and scored a
      // جزئي as nothing. Hoor's 2026-09-10 printed 2/3 where the app has
      // 2/2 (her تمرين week was already bought), and Aziz's 2026-09-03
      // printed 1/2 where the app credits 0.75. Both now read from
      // dailyDoneCount / dailyPartialCount / dailyScheduledCount, which is
      // what creditFor itself reads.
      const stored = roomDayCounts({
        room, participant: p, dayKey: dk, offsetMinutes: ROOM_OFFSET_MINUTES,
      });
      const credited = stored.done + stored.partial * 0.5;
      let countsCell;
      if (!stored.running) {
        countsCell = 'paused, not graded';
      } else if (isOpenDayAt(dk, nowLocal)) {
        // A day still open cannot be judged yet: it stays markable until
        // kDayCutoffHour the next morning, and anything stored for it so far
        // is progress, not a verdict. Counting today as a zero-credit day is
        // the same mistake that had the report calling an unfinished today a
        // miss. Shown, and left out of the total below.
        countsCell = `${num(credited)}/${stored.scheduled}  still open`;
      } else if (stored.stoodDown) {
        countsCell = 'stood down, not graded';
      } else if (stored.isRest) {
        countsCell = 'rest, full credit';
        storedTotal += 1;
        gradedDays++;
      } else {
        countsCell = `${num(credited)}/${stored.scheduled}` +
            (stored.partial > 0 ? `  (${stored.partial} جزئي)` : '');
        storedTotal += stored.credit;
        gradedDays++;
      }
      console.log(`  ${dk}   ${cells.join('')}${countsCell}`);
    }

    const doneMap = p.dailyDoneCount || {};
    const schedMap = p.dailyScheduledCount || {};
    const okWeeks = Array.isArray(p.quotaOkWeeks) ? p.quotaOkWeeks : [];

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
        `${p.lastSyncedDay && p.lastSyncedDay < lastKey ?
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
    // The member's OWN stored fraction, summed from creditFor day by day.
    //
    // It used to divide every day by ALL counting slots and score a جزئي as
    // nothing, so it disagreed with the app twice: a slot the room had not
    // asked for yet still sat in the denominator, and half a habit counted
    // as none. Paused and stood-down days now leave both sides, the way
    // daysCompleted and daysElapsedIn skip them, instead of being scored as
    // zero-credit days.
    console.log(`  Own days, from stored      : ` +
        `${Math.round(storedTotal * 100) / 100} of ${gradedDays} graded` +
        `${gradedDays ? `  = ${Math.round(storedTotal / gradedDays * 100)}%` : ''}` +
        `${gradedDays === days.length ? '' :
            `   (${days.length - gradedDays} day(s) not graded: still open, ` +
            'paused, or stood down)'}`);
    // Said plainly, because the number above is the closest this script gets
    // and is still not the one on the board. The room score grades every day
    // against the WHOLE plan and carries phantoms for unresolved slots, and
    // its rules are being changed in lib right now, so this script
    // deliberately does not compute it.
    console.log('  The app is the authority for the room percentage; the ' +
        'line above is this member\'s own stored credit, not the board.');
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
      days,
      countingIds: counting.map((c) => c.id),
      squaresByDay,
      part: p,
      // Without these a day the anti-backdating clamp is holding on purpose
      // reads as an undercount and gets a repair command. See room_health.js.
      lastUpdatedByDay,
      createdByDay,
      offsetMinutes: ROOM_OFFSET_MINUTES,
    });
    const real = short.filter((s) => !s.held);
    const held = short.filter((s) => s.held);
    if (real.length) {
      console.log(`  >> ${real.length} day(s) where the squares beat the ` +
          `stored count:`);
      for (const s of real) {
        console.log(`     ${s.day}: stored ${s.stored}, squares say ${s.real}`);
        console.log(`       fix: node set_room_day.js --room=${roomCode} ` +
            `--user=${uid} --date=${s.day} --done=${s.real} --confirm`);
      }
    }
    if (held.length) {
      console.log(`  >> ${held.length} day(s) the room is HOLDING on ` +
          `purpose, no action:`);
      for (const s of held) {
        console.log(`     ${s.day}: stored ${s.stored}, squares say ` +
            `${s.real}, and the stored number is the correct one`);
        console.log(`       ${s.why}`);
      }
    }
    console.log(`  This week (${weekStartKey(lastKey)}) starts Saturday.`);
  }
  console.log('');
  process.exit(0);
})().catch((e) => fail(e.message));
