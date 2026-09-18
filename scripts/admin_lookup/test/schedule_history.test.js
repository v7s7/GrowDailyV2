'use strict';

/**
 * A habit's schedule history, read the way the app reads it.
 *
 * Since 2026-09-18 a habit document can carry `scheduleHistory`: the
 * schedules it ran on before its current one, each with the last day it
 * governed (habit_cadence.dart). Aziz: "it should still for the previous days
 * that is spec days, like rest rest days and the other, and the days after
 * are daily." The app judges each past day by the schedule it had then; a
 * tool that judged it by today's schedule would call his old rest days
 * misses, and this tool is read to judge people.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const R = require('../lib/day_rules');
const { habitScheduledOnParts, whyNotScheduled, dayKeyParts } = require('../lib/render');

// Monday and Thursday until Tuesday 15 September 2026, daily since.
const madeDaily = {
  name: 'Sadaqah',
  frequencyType: 'daily',
  frequencyTarget: 1,
  createdAt: '2026-08-01T00:00:00.000',
  scheduleHistory: [
    { until: '2026-09-15', frequencyType: 'weekly', frequencyTarget: 2, scheduledWeekdays: [1, 4] },
  ],
};

test('a day finds the schedule it had, and the change day the new one', () => {
  assert.deepEqual(R.habitAsOf(madeDaily, '2026-09-08').scheduledWeekdays, [1, 4]);
  assert.deepEqual(R.habitAsOf(madeDaily, '2026-09-15').scheduledWeekdays, [1, 4],
    'until is inclusive');
  const after = R.habitAsOf(madeDaily, '2026-09-16');
  assert.equal(after.frequencyType, 'daily');
  assert.deepEqual(after.scheduledWeekdays || [], []);
  // No history: the habit itself, untouched.
  const plain = { frequencyType: 'daily', frequencyTarget: 1 };
  assert.equal(R.habitAsOf(plain, '2026-09-08'), plain);
});

test('periods are read oldest first whatever order they were stored in', () => {
  const h = {
    frequencyType: 'daily',
    frequencyTarget: 1,
    scheduleHistory: [
      { until: '2026-09-15', frequencyType: 'weekly', frequencyTarget: 4 },
      { until: '2026-09-05', frequencyType: 'weekly', frequencyTarget: 2, scheduledWeekdays: [1, 4] },
      { until: 'garbage' },
      null,
    ],
  };
  assert.deepEqual(R.habitAsOf(h, '2026-09-01').scheduledWeekdays, [1, 4]);
  assert.equal(R.habitAsOf(h, '2026-09-10').frequencyTarget, 4);
  assert.equal(R.habitAsOf(h, '2026-09-20').frequencyType, 'daily');
});

test('an old off-day is not owed and paints as rest; a new day is owed', () => {
  const habits = [{ id: 'h', data: madeDaily }];
  const closed = Date.UTC(2026, 8, 30, 12); // long after every day closed
  const tuesdayBefore = R.scoreDay({
    habits, dayData: {}, dayKey: '2026-09-08', nowLocalMs: closed, todayKey: '2026-09-30',
  });
  assert.equal(tuesdayBefore.owed, 0);
  assert.equal(tuesdayBefore.covered, 1);
  assert.equal(tuesdayBefore.rate, null, 'a day that asked nothing is not 0%');

  const tuesdayAfter = R.scoreDay({
    habits, dayData: {}, dayKey: '2026-09-22', nowLocalMs: closed, todayKey: '2026-09-30',
  });
  assert.equal(tuesdayAfter.owed, 1);
  assert.equal(tuesdayAfter.rate, 0);
});

test('the day cards agree: scheduled, and the reason when not', () => {
  assert.equal(habitScheduledOnParts(madeDaily, dayKeyParts('2026-09-08')), false);
  assert.equal(habitScheduledOnParts(madeDaily, dayKeyParts('2026-09-07')), true);
  assert.equal(habitScheduledOnParts(madeDaily, dayKeyParts('2026-09-22')), true);
  assert.match(whyNotScheduled(madeDaily, dayKeyParts('2026-09-08')), /Mon, Thu only/);
  assert.equal(whyNotScheduled(madeDaily, dayKeyParts('2026-09-22')), '');
});

test('a quota cut short by a change owes by the week it had', () => {
  // Four a week until Monday 14 September, daily from Tuesday the 15th.
  const h = {
    frequencyType: 'daily',
    frequencyTarget: 1,
    createdAt: '2026-08-01T00:00:00.000',
    scheduleHistory: [{ until: '2026-09-14', frequencyType: 'weekly', frequencyTarget: 4 }],
  };
  const closed = Date.UTC(2026, 8, 30, 12);
  // Saturday the 12th: four in seven still in reach, so a spare day.
  const sat = R.scoreDay({
    habits: [{ id: 'h', data: h, isGreenOn: () => false }],
    dayData: {},
    dayKey: '2026-09-12',
    nowLocalMs: closed,
    todayKey: '2026-09-30',
  });
  assert.equal(sat.owed, 0);
  assert.equal(sat.covered, 1);
});

test('the app still stores the history under the name this tool reads', () => {
  const dart = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'lib',
    'features', 'habits', 'catalog', 'islamic_habit_catalog.dart'), 'utf8');
  assert.match(dart, /'scheduleHistory': pastCadencesToRaw\(pastCadences\)/);
  const cadence = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'lib',
    'features', 'habits', 'models', 'habit_cadence.dart'), 'utf8');
  assert.match(cadence, /'until': until\.toDateKey\(\)/);
});
