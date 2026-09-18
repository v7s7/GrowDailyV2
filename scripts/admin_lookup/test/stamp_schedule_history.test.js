'use strict';

/**
 * The rules stamp_schedule_history.js writes by: a habit's old schedule,
 * recorded by hand for a change saved before the app kept the record itself.
 *
 * What it writes has to be exactly what the app would have written
 * (pastCadencesAfterChange in lib/features/habits/models/habit_cadence.dart):
 * the old schedule, ending the day BEFORE the change, because the change day
 * follows the new schedule. And it must refuse every stamp that would move a
 * day it has no business moving.
 */

const test = require('node:test');
const assert = require('node:assert');

const S = require('../lib/schedule_history');

const daily = { frequencyType: 'daily', frequencyTarget: 1, scheduledWeekdays: [] };
const monThu = { frequencyType: 'weekly', frequencyTarget: 2, scheduledWeekdays: [1, 4] };

test('a schedule is read the way Add Habit stores it', () => {
  assert.deepEqual(S.parseSchedule('daily'), daily);
  assert.deepEqual(S.parseSchedule('daily:3'),
    { frequencyType: 'daily', frequencyTarget: 3, scheduledWeekdays: [] });
  assert.deepEqual(S.parseSchedule('weekly:4'),
    { frequencyType: 'weekly', frequencyTarget: 4, scheduledWeekdays: [] });
  // Specific days: weekly, the set, and a target of how many there are.
  assert.deepEqual(S.parseSchedule('thu,mon'), monThu);
  assert.deepEqual(S.parseSchedule('Monday, Thursday'), monThu);
  for (const bad of ['', 'weekly:9', 'daily:0', 'mon,funday', 'weekly']) {
    assert.throws(() => S.parseSchedule(bad), `${bad} must be refused`);
  }
});

test("Aziz's case: Monday and Thursday until the day before daily began", () => {
  const next = S.historyWithPeriod({
    history: [],
    current: daily,
    was: monThu,
    changedKey: '2026-09-16',
    bornKey: '2026-08-01',
    todayKey: '2026-09-18',
  });
  assert.deepEqual(next, [
    { until: '2026-09-15', frequencyType: 'weekly', frequencyTarget: 2, scheduledWeekdays: [1, 4] },
  ]);
});

test('a daily schedule stores no weekday list, as the app stores it', () => {
  const next = S.historyWithPeriod({
    history: [],
    current: monThu,
    was: daily,
    changedKey: '2026-09-16',
    bornKey: '2026-08-01',
    todayKey: '2026-09-18',
  });
  assert.deepEqual(next, [{ until: '2026-09-15', frequencyType: 'daily', frequencyTarget: 1 }]);
});

test('every stamp that would move the wrong days is refused', () => {
  const base = {
    history: [],
    current: daily,
    was: monThu,
    changedKey: '2026-09-16',
    bornKey: '2026-08-01',
    todayKey: '2026-09-18',
  };
  assert.throws(() => S.historyWithPeriod({ ...base, changedKey: '2026-09-19' }),
    /after today/);
  assert.throws(() => S.historyWithPeriod({ ...base, changedKey: '16/09/2026' }),
    /YYYY-MM-DD/);
  assert.throws(() => S.historyWithPeriod({ ...base, changedKey: '2026-08-01' }),
    /governed none of its days/);
  assert.throws(() => S.historyWithPeriod({ ...base, was: daily }),
    /the schedule it has now/);
  assert.throws(() => S.historyWithPeriod({
    ...base,
    history: [{ until: '2026-09-20', frequencyType: 'daily', frequencyTarget: 1 }],
  }), /already runs to/);
});

test('a second stamp goes after the first, never before it', () => {
  const next = S.historyWithPeriod({
    history: [{ until: '2026-08-20', frequencyType: 'daily', frequencyTarget: 1 }],
    current: daily,
    was: monThu,
    changedKey: '2026-09-16',
    bornKey: '2026-08-01',
    todayKey: '2026-09-18',
  });
  assert.equal(next.length, 2);
  assert.equal(next[0].until, '2026-08-20');
  assert.equal(next[1].until, '2026-09-15');
});

test('a preset still on its catalog schedule skips only the same-as-now check', () => {
  const next = S.historyWithPeriod({
    history: [],
    current: null,
    was: monThu,
    changedKey: '2026-09-16',
    bornKey: null,
    todayKey: '2026-09-18',
  });
  assert.equal(next[0].until, '2026-09-15');
});

test('the dry run lists which days each schedule asked for', () => {
  // Tuesday 1 to Tuesday 15 September 2026.
  const then = S.askedDaysIn({ fromKey: '2026-09-01', untilKey: '2026-09-15', schedule: monThu });
  assert.deepEqual(then, ['2026-09-03', '2026-09-07', '2026-09-10', '2026-09-14']);
  const now = S.askedDaysIn({ fromKey: '2026-09-01', untilKey: '2026-09-15', schedule: daily });
  assert.equal(now.length, 15);
  // A quota's owed days depend on its sessions, so they are not listed.
  assert.equal(
    S.askedDaysIn({ fromKey: '2026-09-01', untilKey: '2026-09-15', schedule: S.parseSchedule('weekly:4') }),
    null,
  );
});

test('a schedule reads out loud the way the admin pages print one', () => {
  assert.equal(S.describeSchedule(monThu), 'Mon, Thu');
  assert.equal(S.describeSchedule(daily), 'every day');
  assert.equal(S.describeSchedule(S.parseSchedule('weekly:4')), '4x a week, any days');
  assert.equal(S.describeSchedule(S.parseSchedule('daily:3')), 'every day, 3x');
});
