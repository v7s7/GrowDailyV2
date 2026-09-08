/**
 * The rooms health sweep's two rules, on the shapes that actually occurred.
 *
 * PBYAS5, September 2026: the leader extended a finished room on the 4th
 * and the old build's resume calendar paused it through the 29th. Nobody
 * noticed for three days, then a clipped span (3rd to 6th) still hid four
 * days as blank squares, and both members' stored counts for those days
 * stayed at zero while their Grids said done. Every case here is one of
 * those shapes or a neighbour of one.
 */

const test = require("node:test");
const assert = require("node:assert");
const {
  clipSpansToPast,
  closedDaysToCheck,
  countingHabitIds,
  shiftKey,
  todayKeyIn,
  undercountedDays,
} = require("../room_health");

const TODAY = "2026-09-07";

test("shiftKey does plain calendar arithmetic across month and year ends",
    () => {
      assert.strictEqual(shiftKey("2026-09-07", -1), "2026-09-06");
      assert.strictEqual(shiftKey("2026-09-01", -1), "2026-08-31");
      assert.strictEqual(shiftKey("2026-01-01", -1), "2025-12-31");
      assert.strictEqual(shiftKey("2026-08-31", 1), "2026-09-01");
    });

test("todayKeyIn reads the day in the app's timezone, not the server's",
    () => {
      // 22:30 UTC on the 6th is already the 7th in Bahrain (+03:00).
      const ms = Date.UTC(2026, 8, 6, 22, 30);
      assert.strictEqual(todayKeyIn(ms, "Asia/Bahrain"), "2026-09-07");
      assert.strictEqual(todayKeyIn(ms, "UTC"), "2026-09-06");
    });

test("a span that reaches the future is cut to yesterday and reported",
    () => {
      // PBYAS5 as the old build left it.
      const r = clipSpansToPast([{from: "2026-09-03", to: "2026-09-29"}],
          TODAY);
      assert.deepStrictEqual(r.spans, [{from: "2026-09-03", to: "2026-09-06"}]);
      assert.deepStrictEqual(r.clipped, [{from: "2026-09-03", to: "2026-09-29"}]);
    });

test("a span ending today is wrong too: the gap rule stops at yesterday",
    () => {
      const r = clipSpansToPast([{from: "2026-09-05", to: TODAY}], TODAY);
      assert.deepStrictEqual(r.spans, [{from: "2026-09-05", to: "2026-09-06"}]);
      assert.strictEqual(r.clipped.length, 1);
    });

test("a span wholly in the future is dropped", () => {
  const r = clipSpansToPast([{from: "2026-09-10", to: "2026-09-20"}], TODAY);
  assert.deepStrictEqual(r.spans, []);
  assert.strictEqual(r.clipped.length, 1);
});

test("spans that ended in the past are kept as they are", () => {
  const spans = [
    {from: "2026-08-20", to: "2026-08-22"},
    {from: "2026-09-03", to: "2026-09-06"},
  ];
  const r = clipSpansToPast(spans, TODAY);
  assert.deepStrictEqual(r.spans, spans);
  assert.deepStrictEqual(r.clipped, []);
});

test("malformed or missing spans never throw", () => {
  assert.deepStrictEqual(clipSpansToPast(undefined, TODAY),
      {spans: [], clipped: []});
  assert.deepStrictEqual(clipSpansToPast([null, {from: 3}], TODAY),
      {spans: [], clipped: []});
});

test("counting habits leave out a declined slot and a removed shared one",
    () => {
      const room = {
        habitMode: "shared",
        sharedHabits: [{name: "a"}, {name: "b", removedAt: "x"}, {name: "c"}],
      };
      const part = {linkedHabitIds: ["h1", "h2", "__declined__"]};
      assert.deepStrictEqual(countingHabitIds(room, part), ["h1"]);
      // In an own-habits room nothing is ever "removed by the leader".
      assert.deepStrictEqual(
          countingHabitIds({habitMode: "own"}, {linkedHabitIds: ["h1", "h2"]}),
          ["h1", "h2"]);
    });

test("closed days to check skip paused days and stop at the room's start",
    () => {
      const days = closedDaysToCheck({
        startKey: "2026-09-01",
        endKey: null,
        pausedSpans: [{from: "2026-09-03", to: "2026-09-04"}],
      }, "2026-09-06", 10);
      assert.deepStrictEqual(days,
          ["2026-09-01", "2026-09-02", "2026-09-05", "2026-09-06"]);
    });

test("closed days to check honour a room that already ended", () => {
  const days = closedDaysToCheck(
      {startKey: "2026-08-01", endKey: "2026-08-03", pausedSpans: []},
      "2026-09-06", 10);
  assert.deepStrictEqual(days, ["2026-08-01", "2026-08-02", "2026-08-03"]);
  assert.deepStrictEqual(closedDaysToCheck(
      {startKey: "2026-09-10", endKey: null, pausedSpans: []},
      "2026-09-06", 10), [], "not started yet");
});

test("a closed day whose squares say done but whose count is zero is " +
    "reported, with the real number", () => {
  // Aziz on PBYAS5: both habits green on the 3rd, one on the 5th and 6th,
  // nothing stored for any of them.
  const out = undercountedDays({
    days: ["2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06"],
    countingIds: ["a", "b"],
    squaresByDay: {
      "2026-09-03": {a: "complete", b: "complete"},
      "2026-09-05": {b: "complete"},
      "2026-09-06": {b: "bonus", a: "partial"},
    },
    part: {dailyDoneCount: {"2026-09-07": 2}},
  });
  assert.deepStrictEqual(out, [
    {day: "2026-09-03", real: 2, stored: 0},
    {day: "2026-09-05", real: 1, stored: 0},
    {day: "2026-09-06", real: 1, stored: 0},
  ]);
});

test("a day whose count already matches, or exceeds, is not reported",
    () => {
      const out = undercountedDays({
        days: ["2026-09-03"],
        countingIds: ["a", "b"],
        squaresByDay: {"2026-09-03": {a: "complete"}},
        part: {dailyDoneCount: {"2026-09-03": 1}},
      });
      assert.deepStrictEqual(out, []);
    });

test("yellow is not green: a partial square is not an undercount", () => {
  const out = undercountedDays({
    days: ["2026-09-03"],
    countingIds: ["a"],
    squaresByDay: {"2026-09-03": {a: "partial"}},
    part: {},
  });
  assert.deepStrictEqual(out, []);
});

test("a stood-down day and a rest day are never short", () => {
  const out = undercountedDays({
    days: ["2026-09-03", "2026-09-04"],
    countingIds: ["a"],
    squaresByDay: {
      "2026-09-03": {a: "complete"},
      "2026-09-04": {a: "complete"},
    },
    part: {
      standDownDays: ["2026-09-03"],
      dailyScheduledCount: {"2026-09-04": 0},
    },
  });
  assert.deepStrictEqual(out, []);
});
