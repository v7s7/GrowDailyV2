'use strict';

/**
 * The Overview's numbers (lib/overview.js), pinned against a scan written
 * here, at a fixed clock.
 *
 * The clock is 2026-09-18 01:30 in Bahrain (22:30 UTC on the 17th), on
 * purpose: a UTC day and a Bahrain day disagree for three hours every night,
 * and that is exactly where a "today" computed in the wrong zone would show.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const { buildOverview, CATEGORIES, TREND_DAYS } = require('../lib/overview');

const NOW = Date.UTC(2026, 8, 17, 22, 30); // 2026-09-18 01:30 Bahrain
const MIN = 60000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

const iso = (ms) => new Date(ms).toISOString();

function scan() {
  return {
    onlineWindowMinutes: 15,
    accounts: [
      // Did something five minutes ago: online, active today, a 10-day streak.
      { uid: 'a', displayName: 'Aziz', lastActiveAt: iso(NOW - 5 * MIN), createdAt: iso(NOW - 400 * DAY),
        currentStreak: 10, level: 20, todayKey: '2026-09-18', todayDone: 2, todayScheduled: 4 },
      // Active yesterday (Bahrain), new this week.
      { uid: 'b', displayName: '', email: 'b@x.com', lastActiveAt: iso(NOW - 3 * HOUR), createdAt: iso(NOW - 2 * DAY),
        currentStreak: 3, level: 2, todayKey: '2026-09-18', todayDone: 3, todayScheduled: 3 },
      // Twenty days quiet, created last week (8 days ago).
      { uid: 'c', displayName: 'C', lastActiveAt: iso(NOW - 20 * DAY), createdAt: iso(NOW - 8 * DAY),
        currentStreak: 0, level: 1, todayKey: '2026-09-17', todayDone: 1, todayScheduled: 1 },
      // Never did anything, and no Auth record left to date it.
      { uid: 'd', displayName: 'D', lastActiveAt: null, createdAt: null, currentStreak: null, level: null },
    ],
    events: [
      { uid: 'a', type: 'habits', at: NOW - 5 * MIN },            // today 01:25
      { uid: 'a', type: 'task_done', at: NOW - 10 * MIN },        // today 01:20
      { uid: 'b', type: 'habits', at: NOW - 3 * HOUR },           // yesterday 22:30 Bahrain
      { uid: 'b', type: 'signup', at: NOW - 2 * DAY },            // new account, not "activity"
      { uid: 'c', type: 'signin', at: NOW - 1 * HOUR },           // a background restore: counts nowhere
      { uid: 'c', type: 'milestone', at: NOW - 20 * DAY },        // outside the 14-day window
      { uid: 'a', type: 'focus', at: NOW - 1 * DAY },             // folds into Other
      { uid: 'a', type: 'habits', at: NOW + 5 * MIN },            // from the future: ignored
    ],
  };
}

test('the window is 14 Bahrain days ending on the Bahrain today', () => {
  const o = buildOverview(scan(), NOW);
  assert.strictEqual(TREND_DAYS, 14);
  assert.strictEqual(o.today, '2026-09-18', 'UTC still says the 17th at this hour');
  assert.strictEqual(o.yesterday, '2026-09-17');
  assert.strictEqual(o.days.length, 14);
  assert.strictEqual(o.days[0], '2026-09-05');
  assert.strictEqual(o.days[13], '2026-09-18');
});

test('tiles', () => {
  const k = buildOverview(scan(), NOW).kpis;
  assert.strictEqual(k.onlineNow, 1, 'only the write five minutes ago');
  assert.strictEqual(k.activeToday, 1, 'a acted today; b acted before Bahrain midnight');
  assert.strictEqual(k.activeYesterday, 2, 'b logged at 22:30, a had a focus session');
  assert.strictEqual(k.activeWeek, 2);
  assert.strictEqual(k.newWeek, 1);
  assert.strictEqual(k.newPrevWeek, 1);
  assert.strictEqual(k.accountsTotal, 4);
  assert.strictEqual(k.undatedAccounts, 1);
  // Only accounts whose today IS today: c's numbers are yesterday's.
  assert.deepStrictEqual([k.squaresDone, k.squaresScheduled, k.peopleScheduledToday], [5, 7, 2]);
});

test('a sign-in counts nowhere and a sign-up is never "activity"', () => {
  const o = buildOverview(scan(), NOW);
  const total = (id) => o.series.byCategory.find((c) => c.id === id).counts.reduce((x, y) => x + y, 0);
  assert.strictEqual(total('signups'), 1, 'the sign-up is charted as a new account');
  const hoursTotal = o.series.hours.reduce((x, y) => x + y, 0);
  assert.strictEqual(hoursTotal, 5, 'habits x2, task, sign-up, focus; not the sign-in, not the future');
  // b's only event two days ago is the sign-up: b is not active that day.
  const twoDaysAgo = o.days.indexOf('2026-09-16');
  assert.strictEqual(o.series.activeByDay[twoDaysAgo], 0);
});

test('the chart categories fold the small types into Other', () => {
  const o = buildOverview(scan(), NOW);
  assert.deepStrictEqual(o.series.byCategory.map((c) => c.id), CATEGORIES.map((c) => c.id));
  const today = o.days.length - 1;
  const at = (id, i) => o.series.byCategory.find((c) => c.id === id).counts[i];
  assert.strictEqual(at('habits', today), 1);
  assert.strictEqual(at('tasks', today), 1);
  assert.strictEqual(at('other', today - 1), 1, 'the focus session');
  assert.strictEqual(at('milestones', today), 0, 'the milestone is 20 days old');
});

test('events land in the Bahrain hour they happened', () => {
  const o = buildOverview(scan(), NOW);
  // Hour 1: the habit (01:25) and task (01:20) today, plus the focus session
  // one day back and the sign-up two days back, both at 01:30.
  assert.strictEqual(o.series.hours[1], 4);
  assert.strictEqual(o.series.hours[22], 1, 'b at 22:30, the evening before');
});

test('growth counts every dated account, week by week, up to today', () => {
  const g = buildOverview(scan(), NOW).series.growth;
  assert.strictEqual(g[g.length - 1].day, '2026-09-18');
  assert.strictEqual(g[g.length - 1].total, 3, 'd has no date');
  assert.strictEqual(g[0].total, 0, 'the line starts from nothing');
  for (let i = 1; i < g.length; i++) assert.ok(g[i].total >= g[i - 1].total, 'never goes down');
});

test('panels', () => {
  const p = buildOverview(scan(), NOW).panels;
  assert.deepStrictEqual(p.streakLeaders.map((x) => [x.name, x.streak]), [['Aziz', 10], ['b@x.com', 3]]);
  // b finished everything; Aziz is halfway; c is not on today's board.
  assert.deepStrictEqual(p.todayBoard.map((x) => [x.uid, x.done, x.scheduled]), [['b', 3, 3], ['a', 2, 4]]);
  assert.strictEqual(p.todayBoardTotal, 2);
  assert.deepStrictEqual(p.recency.map((r) => r.count), [2, 1, 0, 1]);
});

test('an empty scan is all zeros, never a throw', () => {
  const o = buildOverview({ accounts: [], events: [] }, NOW);
  assert.strictEqual(o.kpis.accountsTotal, 0);
  assert.deepStrictEqual(o.series.growth, []);
  assert.strictEqual(o.series.activeByDay.length, 14);
  assert.doesNotThrow(() => buildOverview(null, NOW));
});
