'use strict';

/**
 * Tests for the habit-day classifier: the cross-read that lets this tool
 * tell "completed", "completed then un-marked" and "marked on the Grid but
 * never completed" apart.
 *
 * These exist because the tool read only habitCompletions, and the last two
 * of those three are invisible in that field. Room ELQVF8 credited a member
 * for a day this report drew as 0/2, and both were faithfully reporting the
 * one field they looked at. Every case below is a shape that really occurred
 * or that the app's own write paths can produce.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  readHabitDay,
  readUndoneReceipts,
  summarizeHabitDay,
  habitIdsTouchedOn,
  fmtMinutes,
  renderDailyDetail,
  renderUndoneSection,
  dayWriteContext,
  DAY_CUTOFF_HOUR,
} = require('../lib/render');

const WITR = '64954035-f900-4891-90cd-62e861e3155b';
const GYM = '93bfae4a-8c6c-4a53-8bd9-bf41f0efe1c7';

test('a normal completion is rewarded and counts in a room', () => {
  const day = {
    habitCompletions: { [GYM]: 1 },
    completedAtMinutes: { [GYM]: 908 },
    squareStates: { [GYM]: 'complete' },
  };
  const r = readHabitDay(day, GYM, null);
  assert.equal(r.verdict, 'completed');
  assert.equal(r.rewarded, true);
  assert.equal(r.roomCounts, true);
});

test("a square painted with no completion behind it is 'grid_only', not empty", () => {
  // Hoor's 2026-09-05 verbatim: squareStates and nothing else, which is all
  // WeeklyGridNotifier.setSquare's anti-backdating branch writes.
  const day = { squareStates: { [WITR]: 'complete' } };
  const r = readHabitDay(day, WITR, null);
  assert.equal(r.verdict, 'grid_only');
  assert.equal(r.rewarded, false, 'no XP, gold or streak was paid');
  assert.equal(r.roomCounts, true, 'but a Room grades off the square, so it counts there');
});

test('a completion timestamp with no completion is the durable un-marked fingerprint', () => {
  // uncompleteHabit deletes habitCompletions and never touches
  // completedAtMinutes, so this shape outlives the receipt by design.
  const day = {
    completedAtMinutes: { [GYM]: 1286 },
    squareStates: { [GYM]: 'none' },
    date: 'whenever',
  };
  const r = readHabitDay(day, GYM, null);
  assert.equal(r.verdict, 'undone');
  assert.equal(r.rewarded, false);
  assert.equal(r.roomCounts, false);
  assert.equal(fmtMinutes(r.stampedAt), '21:26');
});

test('an un-marked day whose square stayed green is flagged as still counting', () => {
  const day = {
    completedAtMinutes: { [GYM]: 600 },
    squareStates: { [GYM]: 'complete' },
  };
  const r = readHabitDay(day, GYM, null);
  assert.equal(r.verdict, 'undone');
  assert.equal(r.roomCounts, true);
});

test('a receipt alone is enough to call it un-marked, even with no timestamp', () => {
  const receipt = { habitId: GYM, dateKey: '2026-09-02', xp: 20, gold: 8, undoneOn: '2026-09-02' };
  const r = readHabitDay({}, GYM, receipt);
  assert.equal(r.verdict, 'undone');
  assert.equal(r.receipt.xp, 20);
});

test('a non-green deliberate mark is neither done nor invisible', () => {
  for (const state of ['partial', 'failed', 'skipped']) {
    const r = readHabitDay({ squareStates: { [GYM]: state } }, GYM, null);
    assert.equal(r.verdict, 'marked', `${state} should read as a mark`);
    assert.equal(r.roomCounts, false, `${state} must not count as green`);
  }
});

test("a cleared square reads as empty, and a stored 'none' equals an absent key", () => {
  assert.equal(readHabitDay({ squareStates: { [GYM]: 'none' } }, GYM, null).verdict, 'none');
  assert.equal(readHabitDay({}, GYM, null).verdict, 'none');
});

test('an unknown square value degrades to empty rather than throwing', () => {
  const r = readHabitDay({ squareStates: { [GYM]: 'lolwhat' } }, GYM, null);
  assert.equal(r.verdict, 'none');
  assert.equal(r.square, 'none');
});

test('habitIdsTouchedOn finds a habit that only ever left a square', () => {
  const ids = habitIdsTouchedOn({ squareStates: { [WITR]: 'complete' } });
  assert.ok(ids.has(WITR));
});

test("the day rollup separates what was paid from what a room credits", () => {
  // Hoor's 2026-09-05, with both linked habits scheduled.
  const sum = summarizeHabitDay({ squareStates: { [WITR]: 'complete' } }, [WITR, GYM], {}, '2026-09-05');
  assert.equal(sum.done, 0, 'nothing was actually paid for');
  assert.equal(sum.greens, 1, 'but one green square is there, which is what the room counted');
  assert.equal(sum.gridOnly, 1);
  assert.equal(sum.undone, 0);
});

test('readUndoneReceipts keys the way UndoneCompletion.keyFor does', () => {
  const receipts = readUndoneReceipts({
    undoneCompletions: {
      [`${GYM}|2026-09-02`]: {
        habitId: GYM, dateKey: '2026-09-02', xp: 20, gold: 8,
        streak: 2, longest: 2, undoneOn: '2026-09-03', finished: true,
      },
    },
  });
  assert.ok(receipts[`${GYM}|2026-09-02`]);
  assert.equal(receipts[`${GYM}|2026-09-02`].undoneOn, '2026-09-03');
});

test('a malformed receipt is dropped without costing the rest of the map', () => {
  const receipts = readUndoneReceipts({
    undoneCompletions: {
      junk: { nope: true },
      alsoJunk: 7,
      [`${GYM}|2026-09-02`]: { habitId: GYM, dateKey: '2026-09-02', xp: 1, gold: 0 },
    },
  });
  assert.equal(Object.keys(receipts).length, 1);
});

test('a missing undoneCompletions field is an empty map, never a throw', () => {
  assert.deepEqual(readUndoneReceipts(null), {});
  assert.deepEqual(readUndoneReceipts({}), {});
  assert.deepEqual(readUndoneReceipts({ undoneCompletions: 'nope' }), {});
});

test('the day panel names a Grid-only mark instead of calling the day empty', () => {
  const html = renderDailyDetail('2026-09-05',
    { squareStates: { [WITR]: 'complete' } },
    { habitCtx: { [WITR]: { name: 'صلاة الوتر' } } });
  assert.ok(html.includes('green square, no completion'), 'must say what it really is');
  assert.ok(!html.includes('No habit activity logged'), 'must not claim the day was empty');
  assert.ok(html.includes('square and the completion disagree'), 'must warn about the mismatch');
});

test('a pre-cutoff mark is named as such, not as an ordinary backfill', () => {
  // Hoor's real write: 2026-09-04T23:18:45Z at UTC+3 is 02:18 on 2026-09-05,
  // its own calendar date but hours before the 10:00 reward-day rollover.
  const html = renderDailyDetail('2026-09-05',
    {
      squareStates: { [WITR]: 'complete' },
      lastUpdated: new Date('2026-09-04T23:18:45Z'),
    },
    { habitCtx: { [WITR]: { name: 'صلاة الوتر' } }, tzOffsetMinutes: 180 });
  assert.ok(html.includes('02:18'), 'names the wall-clock time it was written');
  assert.ok(html.includes('pre-cutoff case'), 'says which of the two causes this is');
  assert.ok(!html.includes('filled in after the fact'));
});

test('a genuinely backfilled day says so instead of crying bug', () => {
  const html = renderDailyDetail('2026-07-14',
    {
      squareStates: { [GYM]: 'complete' },
      lastUpdated: new Date('2026-07-20T15:00:00Z'),
    },
    { habitCtx: { [GYM]: { name: 'تمرين' } }, tzOffsetMinutes: 180 });
  assert.ok(html.includes('filled in after the fact'));
  assert.ok(html.includes('day-warn calm'), 'a designed behaviour gets the calm banner');
  assert.ok(!html.includes('pre-cutoff case'));
});

test('a day with no usable timestamp explains neither cause rather than guessing', () => {
  const html = renderDailyDetail('2026-09-05',
    { squareStates: { [WITR]: 'complete' } },
    { habitCtx: {} });
  assert.ok(html.includes('green square, no completion'));
  assert.ok(!html.includes('pre-cutoff case'));
  assert.ok(!html.includes('filled in after the fact'));
});

test("the admin tool's day cutoff matches the app's kDayCutoffHour", () => {
  // This constant was 6 while the app was on 10 for long enough that the Day
  // tab was a day ahead of the phone every morning. Read the Dart file, not
  // this file's own history.
  const fs = require('node:fs');
  const path = require('node:path');
  const dart = fs.readFileSync(
    path.join(__dirname, '..', '..', '..', 'lib', 'core', 'extensions', 'datetime_ext.dart'), 'utf8');
  const m = dart.match(/const int kDayCutoffHour = (\d+);/);
  assert.ok(m, 'kDayCutoffHour must still be declared where this test looks');
  assert.equal(DAY_CUTOFF_HOUR, Number(m[1]));
});

test('the day panel names an un-marked completion and the XP it took back', () => {
  const receipts = readUndoneReceipts({
    undoneCompletions: {
      [`${GYM}|2026-09-02`]: {
        habitId: GYM, dateKey: '2026-09-02', xp: 20, gold: 8, undoneOn: '2026-09-02',
      },
    },
  });
  const html = renderDailyDetail('2026-09-02',
    { completedAtMinutes: { [GYM]: 1286 }, squareStates: { [GYM]: 'none' } },
    { habitCtx: { [GYM]: { name: 'تمرين' } }, receiptsByKey: receipts });
  assert.ok(html.includes('un-marked'));
  assert.ok(html.includes('20 XP'));
  assert.ok(html.includes('21:26'), 'the original completion time still shows');
});

test('an empty undo list says what that does and does not prove', () => {
  const html = renderUndoneSection({}, {});
  assert.ok(html.includes('three things'));
});

test('the undo section escapes a habit name it does not control', () => {
  const html = renderUndoneSection(
    { undoneCompletions: { 'x|2026-09-02': { habitId: 'x', dateKey: '2026-09-02', xp: 1, gold: 0 } } },
    { x: { name: '<img src=x onerror=alert(1)>' } });
  assert.ok(!html.includes('<img'), 'a stored habit name must never render as markup');
  assert.ok(html.includes('&lt;img'));
});

test('a habit the account no longer has is named, not printed as a bare uuid', () => {
  const { habitLabel } = require('../lib/render');
  const label = habitLabel('92acf394-58e5-4a2a-a249-1dd4e2abb8be', {}, 'faith');
  assert.ok(label.includes('no longer in this account'));
  assert.ok(label.includes('92acf394'), 'the id is still there for an admin who needs it');
  assert.ok(!/^92acf394-58e5/.test(label), 'but it is no longer the whole label');
});

test('a habit the account still has keeps its real name and category emoji', () => {
  const { habitLabel } = require('../lib/render');
  const label = habitLabel(GYM, { [GYM]: { name: 'تمرين', category: 'health' } }, null);
  assert.ok(label.includes('تمرين'));
  assert.ok(!label.includes('no longer'));
});
