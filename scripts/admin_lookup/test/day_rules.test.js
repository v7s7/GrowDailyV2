'use strict';

/**
 * The app's rules, pinned against the app.
 *
 * Every case here is a rule this tool got wrong on a real account, and the
 * three fixtures at the bottom are verbatim documents from 2026-09-12: Aziz
 * 5rLsgWgriLa7qaRDeZ3wdPfHgQl2 and Hoor PfEu8y09LdYlxXS1ZswnNQKuPQl1, room
 * ELQVF8, both phones at +180.
 *
 * The point of pinning them is that this tool is read to JUDGE people. A
 * wrong number here is not a cosmetic bug: it already pointed at a
 * set_room_day.js write that would have paid a member for a day the app had
 * deliberately refused to pay for.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const R = require('../lib/day_rules');

const DART = (...p) => fs.readFileSync(
  path.join(__dirname, '..', '..', '..', 'lib', ...p), 'utf8');

// ── The squares ──────────────────────────────────────────────────────────

test('isGreen is complete or bonus, and the Dart still says so', () => {
  assert.equal(R.isGreen('complete'), true);
  assert.equal(R.isGreen('bonus'), true);
  for (const s of ['partial', 'failed', 'skipped', 'none', undefined, 'junk']) {
    assert.equal(R.isGreen(s), false, `${s} must not be green`);
  }
  // Read the rule from the app rather than trusting this file's history.
  const dart = DART('features', 'grid', 'models', 'square_state.dart');
  assert.match(dart, /bool get isGreen => this == complete \|\| this == bonus;/);
});

test('جزئي is worth exactly half, everywhere', () => {
  assert.equal(R.markCredit('partial'), 0.5);
  assert.equal(R.markCredit('complete'), 1);
  assert.equal(R.markCredit('bonus'), 1);
  for (const s of ['none', 'failed', 'skipped']) assert.equal(R.markCredit(s), 0);
  const dart = DART('features', 'milestones', 'reports', 'habit_day_marks.dart');
  assert.match(dart, /SquareState\.partial => 0\.5,/);
  // And the room weighs it the same. Since the weekly-share ruling that
  // arithmetic lives in doneWeightFor, the fallback creditFor uses on every
  // day the grader recorded no weight for.
  const room = DART('features', 'rooms', 'models', 'room_model.dart');
  assert.match(
    room,
    /\(dailyDoneCount\[dateKey\] \?\? 0\) \+ partialCountFor\(dateKey\) \* 0\.5/,
  );
});

test('a stored weight outranks the counts, and absent means use them', () => {
  // The weekly-share ruling (Aziz, 2026-09-12): a flexible quota carries
  // target/D of a CLOSED week on every day of it, so the day's demand stops
  // being a whole number of habits and the counts can no longer express it.
  //
  // Aziz's own 2026-09-11 is the worked case: all three habits done, in a
  // week that banked 2 of its 4 تمرين sessions, so the day demands 18/7 and
  // earns 16/7. That is 8/9, not the full day the counts alone would claim.
  const weighted = R.creditForStored({
    done: 3, partial: 0, scheduled: 3, demand: 18 / 7, credit: 16 / 7,
  });
  assert.ok(Math.abs(weighted - 8 / 9) < 1e-12, `got ${weighted}`);

  // Absent weights fall back to the whole-habit counts, which is every day
  // graded before the ruling and every plan with no quota in it.
  assert.equal(R.creditForStored({ done: 3, partial: 0, scheduled: 3 }), 1);
  assert.equal(R.creditForStored({ done: 1, partial: 1, scheduled: 4 }), 0.375);
  // A day that asked nothing is a whole day either way.
  assert.equal(R.creditForStored({ done: 0, partial: 0, scheduled: 0 }), 1);
});

test('answersDay is a finished square or an explicit فشل, nothing else', () => {
  assert.equal(R.answersDay('complete'), true);
  assert.equal(R.answersDay('bonus'), true);
  assert.equal(R.answersDay('failed'), true);
  // A blank, a جزئي and a تخطّي are all still finishable, so they wait.
  for (const s of ['none', 'partial', 'skipped']) {
    assert.equal(R.answersDay(s), false, `${s} must not settle its day`);
  }
});

// ── The day window ───────────────────────────────────────────────────────

test('the cutoff matches the app\'s kDayCutoffHour', () => {
  const dart = DART('core', 'extensions', 'datetime_ext.dart');
  const m = dart.match(/const int kDayCutoffHour = (\d+);/);
  assert.ok(m, 'kDayCutoffHour must still be declared where this test looks');
  assert.equal(R.DAY_CUTOFF_HOUR, Number(m[1]));
});

test('a day is open from its own midnight until 10:00 the NEXT morning', () => {
  const at = (iso) => R.localNowMs(Date.parse(iso), 180);
  const day = '2026-09-11';
  // Its own midnight, its own evening, and the tail past midnight.
  assert.equal(R.isOpenDayAt(day, at('2026-09-10T21:00:00Z')), true, '00:00 on the 11th');
  assert.equal(R.isOpenDayAt(day, at('2026-09-11T20:00:00Z')), true, '23:00 on the 11th');
  assert.equal(R.isOpenDayAt(day, at('2026-09-11T23:11:00Z')), true, '02:11 on the 12th');
  assert.equal(R.isOpenDayAt(day, at('2026-09-12T06:59:00Z')), true, '09:59 on the 12th');
  // And shut at exactly 10:00.
  assert.equal(R.isOpenDayAt(day, at('2026-09-12T07:00:00Z')), false, '10:00 on the 12th');
  // Tomorrow is never open, so nothing can be marked ahead of its day.
  assert.equal(R.isOpenDayAt('2026-09-13', at('2026-09-11T20:00:00Z')), false);
});

test('an unanswered habit on an open day is NOT yet missed', () => {
  const now = R.localNowMs(Date.parse('2026-09-11T23:11:00Z'), 180); // 02:11 on the 12th
  // Aziz read his own 2026-09-11 at this exact hour and the tool called four
  // habits missed. The day was still open, so it owed nothing yet.
  assert.equal(R.isSettledAt('2026-09-11', now, { answered: false }), false);
  // Unless it was answered, which settles it at once even while open.
  assert.equal(R.isSettledAt('2026-09-11', now, { answered: true }), true);
  // A closed day is settled either way.
  assert.equal(R.isSettledAt('2026-09-10', now, { answered: false }), true);
  // A future day never counts, answered or not.
  assert.equal(R.isSettledAt('2026-09-13', now, { answered: true }), false);
});

test('the newest fully closed day follows the cutoff, not a day count', () => {
  const at = (iso) => R.localNowMs(Date.parse(iso), 180);
  // 02:11 on the 12th: the 11th is still payable, so the 10th is the newest
  // closed day. This is the only window the old `now - 2 days` got right.
  assert.equal(R.newestClosedKey(at('2026-09-11T23:11:00Z')), '2026-09-10');
  // 12:00 on the 12th: the 11th has closed and must be checked. The old rule
  // still said the 10th and skipped a whole day.
  assert.equal(R.newestClosedKey(at('2026-09-12T09:00:00Z')), '2026-09-11');
  // Exactly at the cutoff it flips.
  assert.equal(R.newestClosedKey(at('2026-09-12T07:00:00Z')), '2026-09-11');
  assert.equal(R.newestClosedKey(at('2026-09-12T06:59:00Z')), '2026-09-10');
});

test('a day closes 34 hours after its own midnight on the phone\'s clock', () => {
  // Aziz's 2026-09-10 at +180 closes at 10:00 on the 11th, his time.
  assert.equal(new Date(R.closesAtInstantMs('2026-09-10', 180)).toISOString(),
    '2026-09-11T07:00:00.000Z');
});

// ── Counted habits ───────────────────────────────────────────────────────

test('a counted habit is done at its target, not at the first tap', () => {
  // Hoor's «Take ur pills», 2 a day, tapped once on 2026-09-11. The app had
  // already written جزئي on the square; the tool counted a completion.
  const day = {
    habitCompletions: { pills: 1 },
    habitTargets: { pills: 2 },
    squareStates: { pills: 'partial' },
  };
  assert.equal(R.dayTargetOf(day, 'pills'), 2);
  assert.equal(R.dayMark(day, 'pills'), 'partial');
  assert.equal(R.markCredit(R.dayMark(day, 'pills')), 0.5);
  // The second tap finishes it.
  assert.equal(R.dayMark({ ...day, habitCompletions: { pills: 2 } }, 'pills'), 'complete');
  // The target is read off the DAY, never off the habit's current settings,
  // so changing a habit later cannot re-grade last month.
  assert.equal(R.dayTargetOf({ habitCompletions: { pills: 1 } }, 'pills'), 1);
  assert.equal(R.dayMark({ habitCompletions: { pills: 1 } }, 'pills'), 'complete');
});

test('a green square wins over the count, and an absent key is empty', () => {
  // setSquare's backdating branch writes squareStates and nothing else.
  assert.equal(R.dayMark({ squareStates: { h: 'complete' } }, 'h'), 'complete');
  assert.equal(R.dayMark({}, 'h'), 'none');
  assert.equal(R.dayMark({ squareStates: { h: 'none' } }, 'h'), 'none');
});

// ── Weekly quotas ────────────────────────────────────────────────────────

test('a weekly quota owes only its load-bearing days', () => {
  // Four a week, done on the first four days: the rest are earned, not
  // missed. Hoor's تمرين week of 2026-09-05 is exactly this.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [0, 1, 2, 3], target: 4 }),
    ['done', 'done', 'done', 'done', 'earned', 'earned', 'earned']);
  // Nothing done all week: the last four days are the ones that break it.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [], target: 4 }),
    ['spare', 'spare', 'spare', 'owed', 'owed', 'owed', 'owed']);
  // The target is clamped into the week's length, so a short week cannot ask
  // for more days than it contains.
  assert.deepEqual(R.weeklyQuotaDemand({ dayCount: 2, doneDays: [], target: 7 }),
    ['owed', 'owed']);
});

test('a جزئي is a session holding a place at half credit (2026-09-26)', () => {
  // Aziz's week of 19 September, تمرين 4x: half on Saturday and Sunday, then
  // nothing. Three rest days, two misses, 1 of 4.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [], halfDays: [0, 1], target: 4 }),
    ['half', 'half', 'spare', 'spare', 'spare', 'owed', 'owed']);
  assert.equal(
    R.quotaWeekCredit({ dayCount: 7, doneDays: [], halfDays: [0, 1], target: 4 }), 1);
  // Two halves, then four whole sessions: the whole ones take the places.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [2, 3, 4, 5], halfDays: [0, 1], target: 4 }),
    ['earned', 'earned', 'done', 'done', 'done', 'done', 'earned']);
  assert.equal(
    R.quotaWeekCredit({ dayCount: 7, doneDays: [2, 3, 4, 5], halfDays: [0, 1], target: 4 }), 4);
  // Two whole and two halves: 3 of 4.
  assert.equal(
    R.quotaWeekCredit({ dayCount: 7, doneDays: [0, 1], halfDays: [2, 3], target: 4 }), 3);
  // Three whole and two halves add up (2026-10-03, "3 + 0.5 + 0.5 = 4"):
  // both halves count, sharing the place the wholes left.
  assert.deepEqual(
    [...R.quotaWeekPlaces({ dayCount: 7, doneDays: [2, 3, 4], halfDays: [0, 1], target: 4 })]
      .sort(),
    [0, 1, 2, 3, 4]);
  assert.deepEqual(
    [...R.quotaWeekSharedHalves({ dayCount: 7, doneDays: [2, 3, 4], halfDays: [0, 1], target: 4 })]
      .sort(),
    [0, 1]);
  assert.equal(
    R.quotaWeekCredit({ dayCount: 7, doneDays: [2, 3, 4], halfDays: [0, 1], target: 4 }), 4);
  // Aziz's own 26 September: W W - half half W -, 4 of 4, the 30th not a rest.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [0, 1, 5], halfDays: [3, 4], target: 4 }),
    ['done', 'done', 'spare', 'half', 'half', 'done', 'earned']);
  // No halves: exactly the old answer.
  assert.deepEqual(
    R.weeklyQuotaDemand({ dayCount: 7, doneDays: [1, 3], target: 3 }),
    ['spare', 'done', 'spare', 'done', 'spare', 'spare', 'owed']);
});

test('the quota week is the SATURDAY week the Grid draws', () => {
  // 2026-09-10 is a Thursday; its week opened on Saturday the 5th.
  assert.equal(R.displayWeekStartKey('2026-09-10'), '2026-09-05');
  assert.equal(R.displayWeekStartKey('2026-09-05'), '2026-09-05');
  assert.equal(R.displayWeekStartKey('2026-09-11'), '2026-09-05');
  assert.equal(R.displayWeekStartKey('2026-09-12'), '2026-09-12');
});

test('"specific days" is stored as weekly and is NOT a flexible quota', () => {
  assert.equal(R.isFlexibleQuota({ frequencyType: 'weekly', frequencyTarget: 4 }), true);
  assert.equal(R.isFlexibleQuota(
    { frequencyType: 'weekly', frequencyTarget: 2, scheduledWeekdays: [1, 4] }), false);
  assert.equal(R.isFlexibleQuota({ frequencyType: 'daily' }), false);
  // Only a flexible quota escapes a per-day denominator.
  assert.equal(R.missIsAttributable({ frequencyType: 'weekly', frequencyTarget: 4 }), false);
  assert.equal(R.missIsAttributable({ frequencyType: 'daily', frequencyTarget: 1 }), true);
});

test('a spare day that has passed is covered, and today is not', () => {
  const habit = { frequencyType: 'weekly', frequencyTarget: 4, createdAt: '2026-09-01T00:00:00.000' };
  const covered = (dayKey, todayKey, demand) =>
    R.isCoveredDay({ habitData: habit, dayKey, todayKey, square: 'none', demand });
  assert.equal(covered('2026-09-10', '2026-09-12', 'earned'), true, 'target already met');
  assert.equal(covered('2026-09-10', '2026-09-12', 'spare'), true, 'spare and passed');
  assert.equal(covered('2026-09-12', '2026-09-12', 'spare'), false, 'today is still open');
  assert.equal(covered('2026-09-10', '2026-09-12', 'owed'), false, 'owed is a real miss');
  // A marked day is a record and stays what it is.
  assert.equal(R.isCoveredDay({
    habitData: habit, dayKey: '2026-09-10', todayKey: '2026-09-12',
    square: 'failed', demand: 'earned',
  }), false);
});

// ── The 2x room boost ────────────────────────────────────────────────────

const ELQVF8 = {
  habitMode: 'shared',
  status: 'active',
  startDate: '2026-08-31T21:00:00.000Z',
  endDate: '2026-09-29T21:00:00.000Z',
  sharedHabits: [
    { name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4 },
    { name: 'صلاة الوتر', frequencyType: 'daily', frequencyTarget: 1 },
    { name: 'قراءة القرآن', frequencyType: 'daily', frequencyTarget: 1,
      addedAt: new Date('2026-09-08T21:48:29.651Z') },
  ],
};
// The room's dates arrive as Timestamps in production; day_rules reads either.
ELQVF8.startDate = new Date(ELQVF8.startDate);
ELQVF8.endDate = new Date(ELQVF8.endDate);

const AZIZ_PART = {
  displayName: 'Aziz',
  linkedHabitIds: ['tamreen', 'witr', 'quran'],
  habitRules: {
    tamreen: [{ from: '2026-09-01', frequencyType: 'weekly', frequencyTarget: 4 }],
    witr: [{ from: '2026-09-01', frequencyType: 'daily', frequencyTarget: 1 }],
    quran: [{ from: '2026-09-09', frequencyType: 'daily', frequencyTarget: 1 }],
  },
  dailyDoneCount: {
    '2026-09-01': 1, '2026-09-02': 2, '2026-09-03': 1, '2026-09-04': 1,
    '2026-09-05': 1, '2026-09-06': 1, '2026-09-07': 1, '2026-09-08': 2,
    '2026-09-09': 2, '2026-09-10': 2, '2026-09-11': 3,
  },
  dailyPartialCount: { '2026-09-03': 1 },
  dailyScheduledCount: { '2026-09-05': 1, '2026-09-06': 1, '2026-09-07': 1 },
  standDownDays: [],
  quotaOkWeeks: [],
  lastSyncedDay: '2026-09-12',
  lastSyncedAt: new Date('2026-09-11T22:29:19Z'),
};

test('a habit linked in a running room is paid 2x, and the room is named', () => {
  const rows = [{ code: 'ELQVF8', room: ELQVF8, participant: AZIZ_PART }];
  assert.deepEqual(
    R.boostRoomsFor({ roomRows: rows, habitId: 'witr', dayKey: '2026-09-10' }),
    ['ELQVF8']);
  // A slot is not boosted before its own rule starts: قراءة القرآن joined the
  // plan on the 9th, so the 8th earns nothing extra.
  assert.deepEqual(
    R.boostRoomsFor({ roomRows: rows, habitId: 'quran', dayKey: '2026-09-08' }), []);
  assert.deepEqual(
    R.boostRoomsFor({ roomRows: rows, habitId: 'quran', dayKey: '2026-09-09' }), ['ELQVF8']);
  // Nor after the room is over, nor for a habit no room links.
  assert.deepEqual(
    R.boostRoomsFor({ roomRows: rows, habitId: 'witr', dayKey: '2026-10-05' }), []);
  assert.deepEqual(
    R.boostRoomsFor({ roomRows: rows, habitId: 'walking', dayKey: '2026-09-10' }), []);
  // The Dart this mirrors.
  const dart = DART('features', 'rooms', 'notifiers', 'rooms_notifier.dart');
  assert.match(dart, /contains\(habitId\) \? base \* 2 : base;/);
});

test('a habit no room links never reads as counting in one', () => {
  // Hoor's المشي 10 دقائق on 2026-09-05 was tagged "Rooms count it" purely
  // because the square was green. She links three habits, and that is not
  // one of them.
  const hoor = { linkedHabitIds: ['tamreen', 'witr', 'quran'], habitRules: {} };
  assert.equal(R.roomCountsHabitOn(
    { room: ELQVF8, participant: hoor, habitId: 'walking', dayKey: '2026-09-05' }), false);
  assert.equal(R.roomCountsHabitOn(
    { room: ELQVF8, participant: hoor, habitId: 'witr', dayKey: '2026-09-05' }), true);
});

test('a habit the leader removed counts through its removal day, not after', () => {
  // 2026-09-22: removal stamps stopsOn, the first day it no longer counts.
  // A removal with no stopsOn is a legacy one and counts on no day, which is
  // what the A8GEL7 and BKWVN9 duplicate repairs rely on.
  const room = {
    habitMode: 'shared',
    sharedHabits: [
      { name: 'quran' },
      { name: 'train', removedAt: 'x', stopsOn: '2026-09-23' },
      { name: 'walk', removedAt: 'x' },
    ],
  };
  const member = { linkedHabitIds: ['q', 't', 'w'], habitRules: {} };
  const on = (habitId, dayKey) =>
    R.roomCountsHabitOn({ room, participant: member, habitId, dayKey });
  assert.equal(on('t', '2026-09-22'), true);
  assert.equal(on('t', '2026-09-23'), false);
  assert.equal(on('w', '2026-09-01'), false);
  assert.equal(on('q', '2026-09-23'), true);
});

// ── The three real shapes ────────────────────────────────────────────────

test('FIXTURE Aziz 2026-09-10: the day really paid 235 XP and 80 gold', () => {
  // Verbatim habitPaidXp / habitPaidGold off users/{aziz}/daily/2026-09-10.
  // The tool printed +0 XP for this day, because it read totalXpEarned,
  // which is dead and which nothing has written since the ledger landed.
  const day = {
    habitPaidXp: { fajr: 30, witr: 40, sadaqa: 20, creatine: 45, mulk: 60, quran: 40 },
    habitPaidGold: { fajr: 8, witr: 16, sadaqa: 8, creatine: 8, mulk: 24, quran: 16 },
    dayEarnedXp: 120,
    dayEarnedGold: 48,
  };
  const paid = R.dayPayout(day);
  assert.equal(paid.xp, 235);
  assert.equal(paid.gold, 80);
  assert.equal(paid.hasLedger, true);
  // dayEarnedXp is a running total for the grace window, not a delta, so it
  // is reported beside the receipt and never folded into it. Folding would
  // have printed 355.
  assert.equal(paid.graceXp, 120);
  // The dead fields must not resurrect: a day carrying only those pays 0 and
  // says it has no ledger, so the page can print "not recorded".
  const dead = R.dayPayout({ totalXpEarned: 999, totalGoldEarned: 999 });
  assert.equal(dead.xp, 0);
  assert.equal(dead.hasLedger, false);
});

test('FIXTURE Aziz 2026-09-03: a جزئي square pays flat XP and scores 0.75', () => {
  // squareFlatXp is the other live payout path, and the only one this day
  // has: the تمرين square was painted جزئي and paid 5.
  const day = {
    squareFlatXp: { tamreen: 5 },
    habitCompletions: { witr: 1, mulk: 1 },
    squareStates: { azkar: 'complete', witr: 'complete', tamreen: 'partial', mulk: 'complete' },
  };
  assert.equal(R.dayPayout(day).xp, 5);
  assert.equal(R.dayMark(day, 'tamreen'), 'partial');
  // And the room scored the day 0.75, not 0.5 and not 0: one done, one
  // جزئي, over the two slots that had joined the plan by then.
  const stored = R.roomDayCounts({
    room: ELQVF8, participant: AZIZ_PART, dayKey: '2026-09-03', offsetMinutes: 180,
  });
  assert.equal(stored.done, 1);
  assert.equal(stored.partial, 1);
  assert.equal(stored.scheduled, 2, 'قراءة القرآن had not joined the plan yet');
  assert.equal(stored.credit, 0.75);
});

const HOOR_PART = {
  displayName: 'Hoor',
  linkedHabitIds: ['tamreen', 'witr', 'quran'],
  habitRules: {
    tamreen: [{ from: '2026-09-01', frequencyType: 'weekly', frequencyTarget: 4 }],
    witr: [{ from: '2026-09-01', frequencyType: 'daily', frequencyTarget: 1 }],
    quran: [{ from: '2026-09-08', frequencyType: 'daily', frequencyTarget: 1 }],
  },
  dailyDoneCount: {
    '2026-09-01': 1, '2026-09-02': 1, '2026-09-05': 2, '2026-09-06': 2,
    '2026-09-07': 2, '2026-09-08': 3, '2026-09-09': 3, '2026-09-10': 2,
    '2026-09-11': 2,
  },
  dailyPartialCount: {},
  dailyScheduledCount: { '2026-09-10': 2 },
  standDownDays: [],
  quotaOkWeeks: ['2026-09-05'],
  lastSyncedDay: '2026-09-11',
  lastSyncedAt: new Date('2026-09-11T18:10:20Z'),
};

test('FIXTURE Hoor 2026-09-10: the room asked for 2, not 3', () => {
  // diagnose_room.js printed 2/3 here by counting every linked slot. Her
  // تمرين week was already at its target of 4, so the quota had bought her
  // that day and the sync wrote a scheduled count of 2.
  const stored = R.roomDayCounts({
    room: ELQVF8, participant: HOOR_PART, dayKey: '2026-09-10', offsetMinutes: 180,
  });
  assert.equal(stored.scheduled, 2);
  assert.equal(stored.done, 2);
  assert.equal(stored.credit, 1, 'a full day, not two thirds of one');
  // The stored entry always wins over the fallback, which would have said 3.
  assert.equal(R.countedHabitCountOn({ participant: HOOR_PART, dayKey: '2026-09-10' }), 3);
});

const HOOR_HABITS = [
  { id: 'pills', data: { name: 'Take ur pills', frequencyType: 'daily', frequencyTarget: 2, createdAt: '2026-09-05T00:00:00.000' } },
  { id: 'walking', data: { name: 'المشي 10 دقائق', frequencyType: 'daily', frequencyTarget: 1, createdAt: '2026-09-05T00:00:00.000' } },
  { id: 'witr', data: { name: 'صلاة الوتر', frequencyType: 'daily', frequencyTarget: 1, createdAt: '2026-09-01T00:00:00.000' } },
  { id: 'tamreen', data: { name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4, createdAt: '2026-09-01T00:00:00.000' } },
  { id: 'quran', data: { name: 'قراءة القرآن', frequencyType: 'daily', frequencyTarget: 1, createdAt: '2026-09-08T00:00:00.000' } },
];

test('FIXTURE Hoor 2026-09-11: 3 green of 5, and the report reads 3.5', () => {
  // Verbatim users/{hoor}/daily/2026-09-11. The tool called this 4
  // completions and 4 of 5, because habitCompletions holds a 1 for the
  // 2-a-day pills habit and it never looked at the target.
  const day = {
    habitTargets: { pills: 2 },
    habitCompletions: { walking: 1, tamreen: 1, pills: 1, witr: 1 },
    squareStates: { walking: 'complete', tamreen: 'complete', pills: 'partial', witr: 'complete' },
  };
  const now = R.localNowMs(Date.parse('2026-09-11T23:11:00Z'), 180); // 02:11 on the 12th
  const s = R.scoreDay({
    habits: HOOR_HABITS, dayData: day, dayKey: '2026-09-11',
    nowLocalMs: now, todayKey: '2026-09-12',
  });
  assert.equal(s.done, 3, 'three green squares, not four completions');
  assert.equal(s.credit, 3.5, 'the جزئي pills add half');
  assert.equal(s.owed, 5);
  // The day was still open at 02:11, so the unanswered قراءة is in progress
  // rather than missed, and only the answered habits may be judged.
  assert.equal(s.isOpen, true);
  assert.equal(s.isPending, true);
  assert.equal(s.settledOwed, 3);
  assert.equal(s.settledCredit, 3);
});

test('FIXTURE Aziz 2026-09-01: a deleted habit leaves BOTH sides', () => {
  // The day carries a green square for 1c26d34d, an id no longer in
  // custom_habits. The tool counted it and printed 2 of 5; the app cannot
  // see it at all, because allHabitsEver has no template for a hard-deleted
  // habit, so it leaves the numerator and the denominator together.
  const day = {
    habitCompletions: { witr: 1, '1c26d34d': 1 },
    squareStates: { witr: 'complete', '1c26d34d': 'complete', azkar: 'none' },
  };
  const habits = [
    { id: 'witr', data: { frequencyType: 'daily', createdAt: '2026-07-20T00:00:00.000' } },
    { id: 'azkar', data: { frequencyType: 'daily', createdAt: '2026-08-14T00:00:00.000' } },
    { id: 'mulk', data: { frequencyType: 'daily' } },
  ];
  const now = R.localNowMs(Date.parse('2026-09-11T23:11:00Z'), 180);
  const s = R.scoreDay({
    habits, dayData: day, dayKey: '2026-09-01', nowLocalMs: now, todayKey: '2026-09-12',
  });
  assert.equal(s.done, 1, 'only the habit the account still has');
  assert.equal(s.owed, 3);
  assert.ok(!s.rows.some((r) => r.habitId === '1c26d34d'));
});

test('a flexible quota keeps a day it was DONE on, and skips a blank one', () => {
  // The asymmetry is deliberate: a quota habit that was done adds 1 to both
  // sides and can only pull a day up, while a blank quota day belongs to
  // nobody in particular, so it enters neither side.
  const habits = [{ id: 'tamreen', data: { frequencyType: 'weekly', frequencyTarget: 4, createdAt: '2026-09-01T00:00:00.000' } }];
  const now = R.localNowMs(Date.parse('2026-09-12T09:00:00Z'), 180);
  const done = R.scoreDay({
    habits, dayData: { squareStates: { tamreen: 'complete' } },
    dayKey: '2026-09-08', nowLocalMs: now, todayKey: '2026-09-12',
  });
  assert.equal(done.owed, 1);
  assert.equal(done.done, 1);
  const blank = R.scoreDay({
    habits, dayData: {}, dayKey: '2026-09-08', nowLocalMs: now, todayKey: '2026-09-12',
  });
  assert.equal(blank.owed, 0, 'nobody owed this particular day');
  assert.equal(blank.rate, null, 'which is not the same as 0%');
});

test('a تخطّي habit leaves the denominator rather than scoring zero', () => {
  const habits = [{ id: 'witr', data: { frequencyType: 'daily', createdAt: '2026-09-01T00:00:00.000' } }];
  const now = R.localNowMs(Date.parse('2026-09-12T09:00:00Z'), 180);
  const s = R.scoreDay({
    habits, dayData: { squareStates: { witr: 'skipped' } },
    dayKey: '2026-09-08', nowLocalMs: now, todayKey: '2026-09-12',
  });
  assert.equal(s.rested, 1);
  assert.equal(s.owed, 0);
});

test('heat follows weighted credit, so a 7-of-9 day is not a perfect one', () => {
  // Aziz's 2026-09-10 was painted the same solid colour as a spotless day,
  // because the old rule was ceil(ratio * 4) and everything from 0.76 up
  // landed on the top tier. The app reserves 4 for a day that discharged
  // everything, and steps down at 0.8 and 0.5.
  assert.equal(R.heatLevel(9, 9), 4);
  assert.equal(R.heatLevel(7, 9), 2, '0.78 is two tiers below perfect');
  assert.ok(R.heatLevel(7, 9) < R.heatLevel(9, 9), '7 of 9 must read lighter than 9 of 9');
  assert.equal(R.heatLevel(8, 10), 3);
  assert.equal(R.heatLevel(5, 10), 2);
  assert.equal(R.heatLevel(1, 10), 1);
  // A day that owed nothing is absence, never a false full.
  assert.equal(R.heatLevel(0, 0), 0);
  assert.equal(R.heatLevel(0, 5), 0);
  // Half credit still registers rather than rounding away to nothing.
  assert.equal(R.heatLevel(0.5, 5), 1);
  // The tiers are the app's, read from the app.
  const dart = DART('features', 'grid', 'screens', 'monthly_heatmap_screen.dart');
  assert.match(dart, /if \(pct >= 1\.0\) return 4;/);
  assert.match(dart, /if \(pct >= 0\.8\) return 3;/);
  assert.match(dart, /if \(pct >= 0\.5\) return 2;/);
});

// ── Rooms the app treats as live ─────────────────────────────────────────

test('a room with no status field is ACTIVE, the way the app reads it', () => {
  const dart = DART('features', 'rooms', 'models', 'room_model.dart');
  assert.match(dart, /status: \(d\['status'\] as String\?\) \?\? 'active',/);
});

test('a stood-down day is worth nothing and never reads as finished', () => {
  const part = { ...AZIZ_PART, standDownDays: ['2026-09-04'] };
  const s = R.roomDayCounts({ room: ELQVF8, participant: part, dayKey: '2026-09-04', offsetMinutes: 180 });
  assert.equal(s.stoodDown, true);
  assert.equal(s.credit, 0, 'a paused day must not fall through to a rest day\'s 1.0');
});

test('a day nothing was scheduled on is full credit, not zero', () => {
  assert.equal(R.creditForStored({ done: 0, partial: 0, scheduled: 0 }), 1);
  assert.equal(R.creditForStored({ done: 1, partial: 0, scheduled: 2 }), 0.5);
  assert.equal(R.creditForStored({ done: 1, partial: 1, scheduled: 2 }), 0.75);
  // Never above 1, however generous the stored numbers are.
  assert.equal(R.creditForStored({ done: 5, partial: 2, scheduled: 2 }), 1);
});

test('a relinked slot counts each habit only on the days it filled the slot', () => {
  // RoomsController.relinkPlanHabit: «تمرين» filled slot 0 until 07-10,
  // «صلاة الضحى» from 07-11. The ledger's "Counts where" asks this.
  const room = {
    habitMode: 'shared',
    sharedHabits: [{ name: 'الضحى' }, { name: 'قراءة القرآن' }],
  };
  const member = {
    linkedHabitIds: ['m-duha', 'm-q'],
    slotHabitHistory: { 0: [{ habitId: 'm-wrong', until: '2026-07-10' }] },
  };
  const counts = (habitId, dayKey) =>
    R.roomCountsHabitOn({ room, participant: member, habitId, dayKey });
  assert.equal(counts('m-wrong', '2026-07-06'), true);
  assert.equal(counts('m-wrong', '2026-07-11'), false);
  assert.equal(counts('m-duha', '2026-07-06'), false, 'not in the slot yet');
  assert.equal(counts('m-duha', '2026-07-11'), true);
  assert.equal(counts('m-q', '2026-07-06'), true, 'other slots untouched');
});

test('a rest day is OUT of the score, though creditForStored says 1.0', () => {
  // Aziz, 2026-09-21: a spare day of a met quota week in A8GEL7 and YW68B9.
  // The day card printed ✅ "counts in full" beside it, and diagnose_room.js
  // paid it a whole day in its own-days line (58% where the app said 39%).
  const rest = { done: 0, partial: 0, scheduled: 0, stoodDown: false, running: true, isRest: true, credit: 1 };
  assert.equal(R.creditForStored({ done: 0, partial: 0, scheduled: 0 }), 1,
      'the per-day credit keeps its 1.0: the Grid paints the day calm');
  assert.deepStrictEqual(R.roomDayVerdict(rest), { counts: false, why: 'rest', credit: 0 });

  const stood = { ...rest, isRest: false, stoodDown: true, credit: 0 };
  assert.equal(R.roomDayVerdict(stood).counts, false);
  const idle = { ...rest, isRest: false, running: false };
  assert.equal(R.roomDayVerdict(idle).counts, false);

  const graded = { done: 2, partial: 1, scheduled: 3, stoodDown: false, running: true, isRest: false, credit: 2.5 / 3 };
  assert.deepStrictEqual(R.roomDayVerdict(graded), { counts: true, why: null, credit: 2.5 / 3 });

  // And the app still leaves it out of both sides.
  const dart = DART('features', 'rooms', 'models', 'room_model.dart');
  assert.match(dart, /if \(!room\.isPausedOn\(key\) && !isStoodDownOn\(key\) && !isRestDay\(key\)\) \{\n\s+total \+= creditFor\(key\);/,
      'daysCompleted: a rest day adds nothing to the numerator');
  assert.match(dart, /final resting = isRestDay\(key\);[\s\S]{0,200}resting \|\|/,
      '_liveDaysIn: and nothing to the denominator');
});

// ── A day no sync has written, after the leader removed a habit ──────────

const { removedHabitRoom, removedHabitMember } = require('./support/removed_habit_room');

test('an unsynced day after a removal reads the plan, as the board does', () => {
  // PBYAS5, 2026-09-28: the app's day card said «0 من 7 عادات» until
  // unsyncedPlanInference, and this tool's day card and diagnose_room.js
  // kept saying 0 of 7. The record alone still counts the removed habits.
  const room = removedHabitRoom();
  const part = removedHabitMember();
  for (const dayKey of ['2026-09-27', '2026-09-28']) {
    const c = R.roomDayCounts({ room, participant: part, dayKey, offsetMinutes: 180 });
    assert.equal(c.scheduled, 5, `${dayKey}: the plan without the two removed habits`);
    assert.equal(c.recorded, 7, `${dayKey}: what the document falls back to`);
    assert.equal(c.planInferred, true);
    assert.equal(c.credit, 0);
    assert.equal(R.storedScheduledOn({ room, participant: part, dayKey, offsetMinutes: 180 }), 7,
        'the record itself is untouched: the clamp compares against it');
  }
  // The removal day still counts for everyone.
  const removalDay = R.roomDayCounts({
    room, participant: part, dayKey: '2026-09-26', offsetMinutes: 180,
  });
  assert.equal(removalDay.scheduled, 7);
  assert.equal(removalDay.planInferred, false);
});

test('the plan inference moves no score: its days are 0 whichever count they read', () => {
  // Why the own-days line in diagnose_room.js still equals the board: a day
  // the inference answers has nothing done, so it is in the score at 0.
  const room = removedHabitRoom();
  const part = removedHabitMember();
  const inferred = R.roomDayCounts({ room, participant: part, dayKey: '2026-09-28', offsetMinutes: 180 });
  const plain = R.roomDayCounts({ room: { ...room, sharedHabits: room.sharedHabits.map(
    ({ removedAt, stopsOn, ...t }) => t) }, participant: part, dayKey: '2026-09-28', offsetMinutes: 180 });
  assert.equal(plain.scheduled, 7);
  assert.deepStrictEqual(R.roomDayVerdict(inferred), R.roomDayVerdict(plain));
  assert.deepStrictEqual(R.roomDayVerdict(inferred), { counts: true, why: null, credit: 0 });
});

test('the plan inference steps aside wherever the record has something to say', () => {
  const room = removedHabitRoom();
  const at = (edit, dayKey = '2026-09-28') => {
    const part = removedHabitMember();
    edit(part);
    return R.roomDayCounts({ room, participant: part, dayKey, offsetMinutes: 180 });
  };
  // Something done, half done, rested, marked or weighted: the sync decided
  // that day's count in the same write, so it is the sync's to answer. This
  // is the day a done-only set_room_day.js repair leaves behind, and why the
  // script now writes the key itself (test/set_room_day.test.js).
  for (const [what, edit] of [
    ['done', (p) => { p.dailyDoneCount['2026-09-28'] = 3; }],
    ['half done', (p) => { p.dailyPartialCount = { '2026-09-28': 1 }; }],
    ['rested', (p) => { p.dailyRestedCount = { '2026-09-28': 1 }; }],
    ['marked', (p) => { p.dailyHabitMarks = { '2026-09-28': { fajr: 'rest' } }; }],
    ['weighted', (p) => { p.dailyDoneWeight = { '2026-09-28': 0 }; }],
    ['a stored count', (p) => { p.dailyScheduledCount = { '2026-09-28': 4 }; }],
  ]) {
    const c = at(edit);
    assert.equal(c.planInferred, false, what);
  }
  assert.equal(at((p) => { p.dailyScheduledCount = { '2026-09-28': 4 }; }).scheduled, 4);
  // A day a sync observed keeps its record: the clamp compares against it.
  const observed = at((p) => { p.lastSyncedAt = new Date('2026-09-29T08:00:00Z'); });
  assert.equal(observed.scheduled, 7);
  assert.equal(observed.planInferred, false);
  // A day before the member joined is none of their business on the board.
  const early = at((p) => { p.joinedAt = new Date('2026-09-28T09:00:00Z'); }, '2026-09-27');
  assert.equal(early.planInferred, false);
  // A lobby has no days yet.
  const lobby = R.roomDayCounts({
    room: { ...room, status: 'lobby' }, participant: removedHabitMember(),
    dayKey: '2026-09-28', offsetMinutes: 180,
  });
  assert.equal(lobby.planInferred, false);
});

test('the plan inference never reaches zero, and leaves a legacy removal alone', () => {
  const room = removedHabitRoom();
  // Every link this member holds is a removed slot: the fallback stands, as
  // the sync stores it (planTotal), because a zero is full credit.
  const onlyRemoved = removedHabitMember();
  onlyRemoved.linkedHabitIds = onlyRemoved.linkedHabitIds.map(
    (id, i) => (i === 3 || i === 6 ? id : R.DECLINED_SLOT));
  const c = R.roomDayCounts({ room, participant: onlyRemoved, dayKey: '2026-09-28', offsetMinutes: 180 });
  assert.equal(c.scheduled, 2);
  assert.equal(c.planInferred, false);
  assert.equal(R.liveHabitCountOn({ room, participant: onlyRemoved, dayKey: '2026-09-28' }), 2);

  // A8GEL7 / BKWVN9: a removal with no stopsOn counts on no day, and every
  // member declined that slot, so both counts already leave it out.
  const legacy = {
    habitMode: 'shared', status: 'active',
    startDate: new Date('2026-08-31T21:00:00Z'),
    sharedHabits: [{ name: 'تمرين' }, { name: 'تمرين', removedAt: new Date('2026-09-09T10:00:00Z') }],
  };
  const member = {
    linkedHabitIds: ['tamreen', R.DECLINED_SLOT],
    joinedAt: new Date('2026-08-31T21:00:00Z'),
    lastSyncedAt: new Date('2026-09-20T08:00:00Z'),
  };
  assert.equal(R.planInferredScheduledOn({
    room: legacy, participant: member, dayKey: '2026-09-28', offsetMinutes: 180,
  }), null);
  assert.equal(R.roomDayCounts({
    room: legacy, participant: member, dayKey: '2026-09-28', offsetMinutes: 180,
  }).scheduled, 1);
});

test('a met quota week keeps its own excuse over the plan inference', () => {
  // storedScheduledOn reads a blank day of a met, purely weekly week as 0,
  // a rest day. The inference must not turn it into a 0-of-1 miss.
  const room = removedHabitRoom();
  room.sharedHabits = [room.sharedHabits[0], room.sharedHabits[3]];
  const part = {
    joinedAt: new Date('2026-09-13T21:00:00Z'),
    linkedHabitIds: ['run', 'walk'],
    habitRules: {
      run: [{ from: '2026-09-14', frequencyType: 'weekly', frequencyTarget: 3 }],
      walk: [{ from: '2026-09-14', frequencyType: 'weekly', frequencyTarget: 3 }],
    },
    quotaOkWeeks: ['2026-09-26'],
    lastSyncedAt: new Date('2026-09-26T17:00:00Z'),
  };
  const c = R.roomDayCounts({ room, participant: part, dayKey: '2026-09-28', offsetMinutes: 180 });
  assert.equal(c.scheduled, 0);
  assert.equal(c.isRest, true);
  assert.equal(c.planInferred, false);
  // Without the banked week the same day reads the plan: 1, not 2.
  const unmet = R.roomDayCounts({
    room, participant: { ...part, quotaOkWeeks: [] }, dayKey: '2026-09-28', offsetMinutes: 180,
  });
  assert.equal(unmet.scheduled, 1);
  assert.equal(unmet.planInferred, true);
});

test('a week whose recorded sessions hold every place rests the days no '
  + 'phone has graded, met or not', () => {
  // Two whole sessions and two halves of a 4x week: every place held, worth
  // 3, so the week never reaches quotaOkWeeks. The phone rests the rest of
  // it the moment the fourth lands (weeklyQuotaScheduledDays), and the
  // app's record now says so too (RoomParticipant._quotaWeekPlacesHeld).
  const room = {
    habitMode: 'shared',
    sharedHabits: [{ name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4 }],
  };
  const part = {
    joinedAt: new Date('2026-09-18T21:00:00Z'),
    linkedHabitIds: ['gym'],
    habitRules: {
      gym: [{ from: '2026-09-19', frequencyType: 'weekly', frequencyTarget: 4 }],
    },
    dailyDoneCount: { '2026-09-19': 1, '2026-09-20': 1 },
    dailyPartialCount: { '2026-09-21': 1, '2026-09-22': 1 },
    quotaOkWeeks: [],
    lastSyncedAt: new Date('2026-09-22T18:00:00Z'),
  };
  for (const dayKey of ['2026-09-23', '2026-09-24', '2026-09-25']) {
    assert.equal(R.quotaWeekPlacesHeld({ room, participant: part, dayKey }), true, dayKey);
    assert.equal(R.storedScheduledOn({ room, participant: part, dayKey, offsetMinutes: 180 }), 0, dayKey);
  }
  // Three sessions are not every place: still due.
  const short = { ...part, dailyPartialCount: { '2026-09-21': 1 } };
  assert.equal(R.storedScheduledOn({ room, participant: short, dayKey: '2026-09-23', offsetMinutes: 180 }), 1);
  // A second habit in the plan: dailyDoneCount cannot say whose sessions.
  const two = {
    ...part,
    linkedHabitIds: ['gym', 'run'],
    habitRules: { ...part.habitRules, run: part.habitRules.gym },
  };
  const twoRoom = { ...room, sharedHabits: [room.sharedHabits[0], room.sharedHabits[0]] };
  assert.equal(R.quotaWeekPlacesHeld({ room: twoRoom, participant: two, dayKey: '2026-09-23' }), false);
});

test('the places-held rest asks what the app asks', () => {
  const dart = DART('features', 'rooms', 'models', 'room_model.dart');
  assert.match(dart, /\(quotaWeekWasMet\(dateKey\) \|\| _quotaWeekPlacesHeld\(dateKey\)\)/);
  const body = dart.match(/bool _quotaWeekPlacesHeld\(String dateKey, \{RoomModel\? room\}\) \{([\s\S]*?)\n  \}\n/);
  assert.ok(body, 'RoomParticipant._quotaWeekPlacesHeld is still there');
  assert.match(body[1], /if \(habits\.length != 1\) return false;/);
  assert.match(body[1], /if \(isStoodDownOn\(k\)\) continue;/);
  assert.match(body[1], /return sessions >= rule\.frequencyTarget;/);
});

test('a stretch out of the plan (offSpans) is inferred the same way', () => {
  const room = removedHabitRoom();
  room.sharedHabits = room.sharedHabits.map(({ removedAt, stopsOn, ...t }) => t);
  room.sharedHabits[2] = { ...room.sharedHabits[2], offSpans: [{ from: '2026-09-27', to: '2026-09-27' }] };
  const part = removedHabitMember();
  assert.equal(R.roomDayCounts({ room, participant: part, dayKey: '2026-09-27', offsetMinutes: 180 }).scheduled, 6);
  assert.equal(R.roomDayCounts({ room, participant: part, dayKey: '2026-09-28', offsetMinutes: 180 }).scheduled, 7);
});

test('the plan inference asks what the app asks', () => {
  // Read from main's room_model.dart: if these lines move, the port above
  // has to be read against them again.
  const dart = DART('features', 'rooms', 'models', 'room_model.dart');
  const body = dart.match(/Map<String, int> unsyncedPlanInference\(RoomModel room, \{DateTime\? now\}\) \{([\s\S]*?)\n  \}\n/);
  assert.ok(body, 'RoomParticipant.unsyncedPlanInference is still there');
  const src = body[1];
  assert.match(src, /room\.habitMode != RoomHabitMode\.shared \|\| room\.isLobby/);
  assert.match(src, /shared\[i\]\.isRemoved \|\| shared\[i\]\.offSpans\.isNotEmpty/);
  assert.match(src, /if \(wasObservedOn\(key\)\) break;/);
  for (const field of ['dailyScheduledCount', 'dailyScheduledWeight', 'dailyDoneWeight', 'dailyHabitMarks']) {
    assert.match(src, new RegExp(`${field}\\.containsKey\\(key\\)`), field);
  }
  for (const field of ['dailyDoneCount', 'dailyPartialCount', 'dailyRestedCount']) {
    assert.match(src, new RegExp(`\\(${field}\\[key\\] \\?\\? 0\\) != 0`), field);
  }
  assert.match(src, /if \(recordedScheduledCountFor\(key\) != fallback\) continue;/);
  assert.match(src, /if \(!room\.slotLiveOn\(i, key\)\) continue;/);
  assert.match(src, /if \(live == 0 \|\| live >= fallback\) continue;/);
  // And the board reads it before the record, after a met week's rest the
  // plan as the leader left it gives (unsyncedQuotaRestDays), which this
  // tool reads through storedScheduledOn.
  assert.match(dart, /inferredScheduledCount\[dateKey\] \?\?\n\s+\(unsyncedQuotaRestDays\.contains\(dateKey\) \? 0 : null\) \?\?\n\s+planInferredScheduledCount\[dateKey\] \?\?\n\s+recordedScheduledCountFor\(dateKey\);/);
});

// ── A daily habit the leader removed, and a met quota week ───────────────

test('a removed daily habit no longer keeps a met quota week from resting '
  + 'the days no phone has graded', () => {
  // قراءة القرآن removed on Tuesday 14 July, so from the 15th the plan is
  // تمرين 4x a week alone. The member met the week of the 18th by the 21st
  // and last synced at 11:00 on the 22nd; the 23rd has nothing on it. The
  // app's board rests it (RoomParticipant.unsyncedQuotaRestInference) and so
  // does the phone when it next grades it (it writes 0).
  const room = {
    habitMode: 'shared',
    sharedHabits: [
      { name: 'قراءة القرآن', frequencyType: 'daily', frequencyTarget: 1,
        removedAt: 'x', stopsOn: '2026-07-15' },
      { name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4 },
    ],
  };
  const part = {
    linkedHabitIds: ['q', 'e'],
    habitRules: {
      q: [{ from: '2026-07-04', frequencyType: 'daily', frequencyTarget: 1 }],
      e: [{ from: '2026-07-04', frequencyType: 'weekly', frequencyTarget: 4 }],
    },
    dailyDoneCount: { '2026-07-18': 1, '2026-07-19': 1, '2026-07-20': 1, '2026-07-21': 1 },
    dailyScheduledCount: { '2026-07-22': 0 },
    quotaOkWeeks: ['2026-07-04', '2026-07-11', '2026-07-18'],
    lastSyncedDay: '2026-07-22',
    lastSyncedAt: new Date('2026-07-22T08:00:00Z'),
  };
  const at = (dayKey, p = part, r = room) =>
    R.storedScheduledOn({ room: r, participant: p, dayKey, offsetMinutes: 180 });
  assert.equal(at('2026-07-23'), 0);
  assert.equal(at('2026-07-24'), 0);
  // The same member in a room that never removed it: the daily habit is
  // still owed, so the week's rest cannot speak for the day.
  const unedited = {
    ...room,
    sharedHabits: [{ ...room.sharedHabits[0], removedAt: undefined, stopsOn: undefined },
      room.sharedHabits[1]],
  };
  assert.equal(at('2026-07-23', part, unedited), 2);
  // A week not met is owed as before, unless its sessions hold every place
  // (the phone rests the rest of the week then, met or not).
  const threeDone = {
    ...part,
    quotaOkWeeks: ['2026-07-11'],
    dailyDoneCount: { '2026-07-18': 1, '2026-07-19': 1, '2026-07-20': 1 },
  };
  assert.equal(at('2026-07-23', threeDone), 2);
  assert.equal(at('2026-07-23', { ...part, quotaOkWeeks: ['2026-07-11'] }), 0);
  // A day a sync observed keeps the fallback: the arm is for unseen days.
  assert.equal(
    at('2026-07-23', { ...part, lastSyncedAt: new Date('2026-07-25T08:00:00Z') }),
    2,
  );
  // A legacy removal (removedAt, no stopsOn) counts on no day at all.
  const legacy = {
    ...room,
    sharedHabits: [{ ...room.sharedHabits[0], stopsOn: undefined }, room.sharedHabits[1]],
  };
  assert.equal(at('2026-07-23', part, legacy), 0);
});

test('a quota the leader removed beside a daily habit: the daily habit '
  + 'still owes the day', () => {
  const room = {
    habitMode: 'shared',
    sharedHabits: [
      { name: 'قراءة القرآن', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4,
        removedAt: 'x', stopsOn: '2026-07-12' },
    ],
  };
  const part = {
    linkedHabitIds: ['q', 'e'],
    habitRules: {
      q: [{ from: '2026-07-04', frequencyType: 'daily', frequencyTarget: 1 }],
      e: [{ from: '2026-07-04', frequencyType: 'weekly', frequencyTarget: 4 }],
    },
    dailyDoneCount: {},
    dailyScheduledCount: {},
    quotaOkWeeks: ['2026-07-11'],
    lastSyncedDay: '2026-07-12',
    lastSyncedAt: new Date('2026-07-12T08:00:00Z'),
  };
  assert.equal(
    R.storedScheduledOn({ room, participant: part, dayKey: '2026-07-14', offsetMinutes: 180 }),
    2,
  );
});

test('the repair never writes a key on a met week\'s blank day the removal '
  + 'left to rest', () => {
  // set_room_day.js with a done count of 0 on the day above: the board rests
  // it and the phone will write 0, so a key of the plan's count (1) would
  // turn that rest into a miss the next sync then has to undo.
  const { scheduledKeyPlan } = require('../lib/room_day_repair');
  const room = {
    habitMode: 'shared',
    sharedHabits: [
      { name: 'قراءة القرآن', frequencyType: 'daily', frequencyTarget: 1,
        removedAt: 'x', stopsOn: '2026-07-15' },
      { name: 'تمرين', frequencyType: 'weekly', frequencyTarget: 4 },
    ],
  };
  const part = {
    linkedHabitIds: ['q', 'e'],
    habitRules: {
      q: [{ from: '2026-07-04', frequencyType: 'daily', frequencyTarget: 1 }],
      e: [{ from: '2026-07-04', frequencyType: 'weekly', frequencyTarget: 4 }],
    },
    dailyDoneCount: { '2026-07-18': 1, '2026-07-19': 1, '2026-07-20': 1, '2026-07-21': 1 },
    dailyScheduledCount: { '2026-07-22': 0 },
    quotaOkWeeks: ['2026-07-18'],
    lastSyncedDay: '2026-07-22',
    lastSyncedAt: new Date('2026-07-22T08:00:00Z'),
  };
  const plan = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-07-23', done: 0, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(plan.action, 'keep');
  assert.equal(plan.reads, 0);
});

test('every quota week is exact: asked equals the target, given equals its worth', () => {
  // The same property the app proves in weekly_quota_plan_test.dart, so this
  // copy cannot drift from it: places ask a day each (half a day for a shared
  // half), owed empty days a day each, and together that is the target;
  // whole sessions plus half of every half, capped, is what the week gives.
  for (let target = 1; target <= 7; target++) {
    for (let code = 0; code < 3 ** 7; code++) {
      const done = [];
      const half = [];
      let c = code;
      for (let i = 0; i < 7; i++) {
        const v = c % 3;
        c = Math.floor(c / 3);
        if (v === 1) done.push(i);
        if (v === 2) half.push(i);
      }
      const args = { dayCount: 7, doneDays: done, halfDays: half, target };
      const demand = R.weeklyQuotaDemand(args);
      const places = R.quotaWeekPlaces(args);
      const shared = R.quotaWeekSharedHalves(args);
      let asked = demand.filter((d) => d === 'owed').length;
      for (const i of places) asked += shared.has(i) ? 0.5 : 1;
      assert.equal(asked, target, `target ${target}, code ${code}`);
      const worth = Math.min(target, Math.min(done.length, target) + 0.5 * half.length);
      assert.equal(R.quotaWeekCredit(args), worth, `target ${target}, code ${code}`);
    }
  }
});
