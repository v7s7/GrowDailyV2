'use strict';

/**
 * Tests for the admin tool's day view: the reconstruction that lets the
 * report show any past day, not just today.
 *
 * Run with `npm test` in scripts/admin_lookup (node --test, same runner
 * functions/ uses, no extra dependency).
 *
 * These cover triageTasksForDay specifically because it is the one piece of
 * this tool that INFERS rather than reads: every other section prints a
 * stored field, but the Matrix board for an old day has to be rebuilt from
 * each task's created/completed timestamps, and a wrong rule there produces
 * a page that looks authoritative and is quietly false.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  triageTasksForDay,
  triageTasks,
  dayKeyParts,
  calendarTodayParts,
  habitScheduledOnParts,
  earliestReminder,
  dayHeatLevel,
} = require('../lib/render');

// Local-time constructors throughout: triageTasksForDay buckets by local
// calendar day (getFullYear/getMonth/getDate), matching how the app writes
// and how an admin reads.
const at = (y, m, d, h = 12, min = 0) => new Date(y, m - 1, d, h, min);

/** A task doc in the plain shape triageTasksForDay accepts alongside real snapshots. */
function task(id, fields) {
  return { id, ...fields };
}

const DAY = '2026-08-20';
const parts = dayKeyParts(DAY);

test('a task created after the day being viewed is invisible on it', () => {
  const out = triageTasksForDay([
    task('later', { title: 'Made tomorrow', createdAt: at(2026, 8, 21), isDone: false }),
  ], parts);
  assert.deepStrictEqual(
    [out.today.length, out.late.length, out.upcoming.length, out.done.length, out.noDate.length],
    [0, 0, 0, 0, 0]);
});

test('a task finished before the day being viewed was already off the board', () => {
  const out = triageTasksForDay([
    task('old', {
      title: 'Done last week', createdAt: at(2026, 8, 10),
      isDone: true, completedAt: at(2026, 8, 12),
    }),
  ], parts);
  assert.strictEqual(out.done.length, 0);
  assert.strictEqual(out.late.length, 0);
});

test('a task finished ON the day lands in Done', () => {
  const out = triageTasksForDay([
    task('hit', {
      title: 'Finished that day', createdAt: at(2026, 8, 18),
      isDone: true, completedAt: at(2026, 8, 20, 9),
    }),
  ], parts);
  assert.strictEqual(out.done.length, 1);
  assert.strictEqual(out.done[0].data.title, 'Finished that day');
});

test('a task finished AFTER the day was still open on it, and reads as late', () => {
  // The case a naive "isDone means gone" rule gets wrong: on 20 Aug this
  // task was an overdue item sitting on the board, and it stayed one for
  // another week. Filing it as done would rewrite that day's history.
  const out = triageTasksForDay([
    task('later-done', {
      title: 'Dragged on', createdAt: at(2026, 8, 15),
      isDone: true, completedAt: at(2026, 8, 27),
    }),
  ], parts);
  assert.strictEqual(out.done.length, 0);
  assert.strictEqual(out.late.length, 1);
  assert.strictEqual(out.late[0].data.title, 'Dragged on');
});

test('created that day is Today, created earlier and still open is Late', () => {
  const out = triageTasksForDay([
    task('fresh', { title: 'Added that morning', createdAt: at(2026, 8, 20, 8), isDone: false }),
    task('carried', { title: 'Carried over', createdAt: at(2026, 8, 11), isDone: false }),
  ], parts);
  assert.deepStrictEqual(out.today.map((r) => r.data.title), ['Added that morning']);
  assert.deepStrictEqual(out.late.map((r) => r.data.title), ['Carried over']);
});

test('a reminder dated after the day wins over its creation day', () => {
  // Mirrors matrix_screen.dart: a task you dated two weeks out should not
  // sit in Today shouting at you every morning until then.
  const out = triageTasksForDay([
    task('planned', {
      title: 'Dated ahead', createdAt: at(2026, 8, 3), isDone: false,
      reminderAts: [at(2026, 8, 29, 8)],
    }),
  ], parts);
  assert.strictEqual(out.late.length, 0);
  assert.deepStrictEqual(out.upcoming.map((r) => r.data.title), ['Dated ahead']);
});

test('the four open buckets are a clean partition, with no task counted twice', () => {
  const docs = [
    task('a', { title: 'a', createdAt: at(2026, 8, 20, 7), isDone: false }),
    task('b', { title: 'b', createdAt: at(2026, 8, 1), isDone: false }),
    task('c', { title: 'c', createdAt: at(2026, 8, 2), isDone: false, reminderAts: [at(2026, 9, 1)] }),
    task('d', { title: 'd', createdAt: at(2026, 8, 5), isDone: true, completedAt: at(2026, 8, 20, 22) }),
    task('e', { title: 'e', createdAt: at(2026, 8, 25), isDone: false }),          // not born yet
    task('f', { title: 'f', createdAt: at(2026, 8, 5), isDone: true, completedAt: at(2026, 8, 6) }), // long gone
    task('g', { title: 'g', isDone: false }),                                       // no dates at all
  ];
  const out = triageTasksForDay(docs, parts);
  const seen = []
    .concat(out.today, out.late, out.upcoming, out.done, out.noDate)
    .map((r) => r.data.title);
  assert.deepStrictEqual(seen.slice().sort(), ['a', 'b', 'c', 'd', 'g']);
  assert.strictEqual(new Set(seen).size, seen.length, 'a task appeared in two buckets');
  assert.deepStrictEqual(out.noDate.map((r) => r.data.title), ['g']);
});

test('a stale completedAt on a task that is not done is ignored', () => {
  // MatrixTask.toFirestore deletes completedAt on restore, but a doc written
  // by an older client can still carry one. Reading it regardless would file
  // a live open task as finished.
  const out = triageTasksForDay([
    task('restored', {
      title: 'Reopened', createdAt: at(2026, 8, 4),
      isDone: false, completedAt: at(2026, 8, 20, 10),
    }),
  ], parts);
  assert.strictEqual(out.done.length, 0);
  assert.deepStrictEqual(out.late.map((r) => r.data.title), ['Reopened']);
});

test('a task marked done with no completedAt is left out rather than guessed at', () => {
  const out = triageTasksForDay([
    task('unknown', { title: 'When?', createdAt: at(2026, 8, 4), isDone: true }),
  ], parts);
  const all = [].concat(out.today, out.late, out.upcoming, out.done, out.noDate);
  assert.strictEqual(all.length, 0);
});

test('today still behaves exactly as it did before the day view existed', () => {
  // The refactor that generalised this to any day must not have changed
  // what the live board shows.
  const now = new Date();
  const todayParts = calendarTodayParts(null);
  const y = now.getFullYear(), m = now.getMonth() + 1, d = now.getDate();
  const yesterday = new Date(now.getTime() - 86400000);

  const docs = [
    task('t1', { title: 'made today', createdAt: at(y, m, d, 1), isDone: false }),
    task('t2', {
      title: 'carried over',
      createdAt: at(yesterday.getFullYear(), yesterday.getMonth() + 1, yesterday.getDate()),
      isDone: false,
    }),
    task('t3', { title: 'finished today', createdAt: at(y, m, d, 2), isDone: true, completedAt: at(y, m, d, 3) }),
  ];
  const out = triageTasks(docs, todayParts);
  assert.deepStrictEqual(out.today.map((r) => r.data.title), ['made today']);
  assert.deepStrictEqual(out.late.map((r) => r.data.title), ['carried over']);
  assert.deepStrictEqual(out.done.map((r) => r.data.title), ['finished today']);
});

test('earliestReminder prefers the earliest across the array and the legacy field', () => {
  assert.strictEqual(earliestReminder({}), null);
  const r = earliestReminder({
    reminderAts: [at(2026, 8, 22, 9), at(2026, 8, 21, 9)],
    reminderAt: at(2026, 8, 23, 9),
  });
  assert.strictEqual(r.getTime(), at(2026, 8, 21, 9).getTime());
  // A doc written only by an older client still resolves.
  const legacyOnly = earliestReminder({ reminderAt: at(2026, 8, 23, 9) });
  assert.strictEqual(legacyOnly.getTime(), at(2026, 8, 23, 9).getTime());
});

test('habit scheduling on an old day honours creation, archiving and weekdays', () => {
  // 2026-08-20 is a Thursday (weekday 4 in Dart's 1=Mon..7=Sun convention).
  assert.strictEqual(parts.weekday, 4);

  const everyDay = { createdAt: '2026-08-01T00:00:00.000' };
  assert.strictEqual(habitScheduledOnParts(everyDay, parts), true);

  const notBornYet = { createdAt: '2026-08-21T00:00:00.000' };
  assert.strictEqual(habitScheduledOnParts(notBornYet, parts), false);

  // The archive day itself still counts; the day after does not.
  const archivedThatDay = { createdAt: '2026-08-01T00:00:00.000', archivedAt: '2026-08-20T00:00:00.000' };
  assert.strictEqual(habitScheduledOnParts(archivedThatDay, parts), true);
  const archivedBefore = { createdAt: '2026-08-01T00:00:00.000', archivedAt: '2026-08-19T00:00:00.000' };
  assert.strictEqual(habitScheduledOnParts(archivedBefore, parts), false);

  const thursdays = { createdAt: '2026-08-01T00:00:00.000', scheduledWeekdays: [4] };
  assert.strictEqual(habitScheduledOnParts(thursdays, parts), true);
  const mondays = { createdAt: '2026-08-01T00:00:00.000', scheduledWeekdays: [1] };
  assert.strictEqual(habitScheduledOnParts(mondays, parts), false);
});

test('a day with nothing scheduled reads as empty, never as a false full', () => {
  assert.strictEqual(dayHeatLevel(0, 0), 0);
  assert.strictEqual(dayHeatLevel(0, 5), 0);
  assert.strictEqual(dayHeatLevel(5, 5), 4);
  assert.ok(dayHeatLevel(1, 5) < dayHeatLevel(4, 5));
});
