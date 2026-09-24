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
  slotLiveOn,
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
      {startKey: "2026-08-24", endKey: "2026-08-27", pausedSpans: []},
      "2026-09-06", 10);
  assert.deepStrictEqual(days,
      ["2026-08-24", "2026-08-25", "2026-08-26", "2026-08-27"]);
  assert.deepStrictEqual(closedDaysToCheck(
      {startKey: "2026-09-10", endKey: null, pausedSpans: []},
      "2026-09-06", 10), [], "not started yet");
});

test("a room that ended over two weeks ago is not re-read every Monday",
    () => {
      // Its last days were checked by at least two earlier weekly runs.
      assert.deepStrictEqual(closedDaysToCheck(
          {startKey: "2026-08-01", endKey: "2026-08-03", pausedSpans: []},
          "2026-09-06", 10), []);
      // The edge: fourteen days before the last closed day is still checked,
      // fifteen is not.
      assert.deepStrictEqual(closedDaysToCheck(
          {startKey: "2026-08-20", endKey: "2026-08-23", pausedSpans: []},
          "2026-09-06", 10),
      ["2026-08-20", "2026-08-21", "2026-08-22", "2026-08-23"]);
      assert.deepStrictEqual(closedDaysToCheck(
          {startKey: "2026-08-19", endKey: "2026-08-22", pausedSpans: []},
          "2026-09-06", 10), []);
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
  // Every row now carries the HELD verdict alongside the numbers, so a
  // caller cannot print a repair command without having looked at it.
  assert.deepStrictEqual(out.map((u) => ({day: u.day, real: u.real, stored: u.stored})), [
    {day: "2026-09-03", real: 2, stored: 0},
    {day: "2026-09-05", real: 1, stored: 0},
    {day: "2026-09-06", real: 1, stored: 0},
  ]);
  assert.ok(out.every((u) => u.held === false), "no write times, so nothing is held");
});

test("a habit the weekly quota already bought is not an undercount", () => {
  // Hoor on ELQVF8, 2026-09-09 to 09-11: her 4x-a-week تمرين had banked all
  // four sessions by the 8th, so her own device marked it REST on the days
  // after, and a green square there earns nothing in the app. Reporting it
  // printed a set_room_day command that would have paid her for a day the
  // room never asked for.
  const out = undercountedDays({
    days: ["2026-09-09", "2026-09-10", "2026-09-11"],
    countingIds: ["tamreen", "witr", "quran"],
    squaresByDay: {
      "2026-09-09": {tamreen: "complete", witr: "complete", quran: "complete"},
      "2026-09-10": {tamreen: "complete", witr: "complete", quran: "complete"},
      "2026-09-11": {tamreen: "complete", witr: "complete"},
    },
    part: {
      dailyDoneCount: {"2026-09-09": 2, "2026-09-10": 2, "2026-09-11": 1},
      dailyHabitMarks: {
        "2026-09-09": {tamreen: "r", witr: "d", quran: "d"},
        "2026-09-10": {tamreen: "r", witr: "d", quran: "d"},
        "2026-09-11": {tamreen: "r", witr: "d", quran: "m"},
      },
    },
  });
  assert.deepStrictEqual(out, [], "every one of those days is already paid");
});

test("a rest mark excuses only its own habit, on its own day", () => {
  // The same member, with one habit rested and another genuinely missing
  // from the stored count: the day is still short by the second one.
  const out = undercountedDays({
    days: ["2026-09-09"],
    countingIds: ["tamreen", "witr", "quran"],
    squaresByDay: {
      "2026-09-09": {tamreen: "complete", witr: "complete", quran: "complete"},
    },
    part: {
      dailyDoneCount: {"2026-09-09": 1},
      dailyHabitMarks: {"2026-09-09": {tamreen: "r", witr: "d", quran: "d"}},
    },
  });
  assert.deepStrictEqual(
      out.map((u) => ({day: u.day, real: u.real, stored: u.stored})),
      [{day: "2026-09-09", real: 2, stored: 1}]);
});

test("a member whose device never wrote marks is checked as before", () => {
  const out = undercountedDays({
    days: ["2026-09-03"],
    countingIds: ["a", "b"],
    squaresByDay: {"2026-09-03": {a: "complete", b: "complete"}},
    part: {dailyDoneCount: {"2026-09-03": 0}},
  });
  assert.deepStrictEqual(
      out.map((u) => ({day: u.day, real: u.real, stored: u.stored})),
      [{day: "2026-09-03", real: 2, stored: 0}]);
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

test("a day the clamp is holding is reported as HELD, with no repair", () => {
  // Room ELQVF8, Aziz, 2026-09-10, verbatim from square_audit: the تمرين
  // square went none -> complete and back after the day had closed (the
  // audit row is stamped dateKey 2026-09-10, appDayKey 2026-09-11, at
  // 2026-09-11T20:56:26Z, which is 23:56 on his own +180 clock). The day
  // closed at 2026-09-11T07:00Z and his lastSyncedAt is later still, so the
  // room had already graded it. Reporting this as an undercount printed a
  // set_room_day.js --confirm line that would have moved him 65.9% -> 68.9%.
  const out = undercountedDays({
    days: ["2026-09-10"],
    countingIds: ["tamreen", "witr", "quran"],
    squaresByDay: {
      "2026-09-10": {tamreen: "complete", witr: "complete", quran: "complete"},
    },
    part: {
      dailyDoneCount: {"2026-09-10": 2},
      lastSyncedAt: new Date("2026-09-11T22:29:19Z"),
      lastSyncedDay: "2026-09-12",
    },
    lastUpdatedByDay: {"2026-09-10": new Date("2026-09-11T20:56:26Z")},
    createdByDay: {"2026-09-10": new Date("2026-09-10T02:07:50Z")},
  });
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].held, true, "the clamp is holding this day");
  assert.strictEqual(out[0].real, 3);
  assert.strictEqual(out[0].stored, 2);
  assert.match(out[0].why, /holding this day on purpose/);
  // The day document was opened on time, which the report is allowed to say
  // without it changing the verdict.
  assert.match(out[0].why, /first written while the day was still open/);
});

test("a late write the room never graded is still a real undercount", () => {
  // Same shape, except the member's phone has not synced since before the
  // day closed: the room simply missed the day, so the clamp never applied
  // and this one genuinely needs a hand.
  const out = undercountedDays({
    days: ["2026-09-10"],
    countingIds: ["a", "b"],
    squaresByDay: {"2026-09-10": {a: "complete", b: "complete"}},
    part: {
      dailyDoneCount: {"2026-09-10": 1},
      lastSyncedAt: new Date("2026-09-10T18:00:00Z"),
    },
    lastUpdatedByDay: {"2026-09-10": new Date("2026-09-11T20:00:00Z")},
  });
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].held, false);
});

test("a mark made inside the grace tail is never held: the room missed it",
    () => {
      // Aziz's الوتر on 2026-09-06, the day roomDayMarkedWhileOpen is named
      // after: marked at 02:13 in the grace window, paid in full by the Grid,
      // and held at zero by both rooms because the first sync after midnight
      // had already stamped the day observed. The write landed BEFORE the
      // 10:00 close, so the clamp stands aside and this is a real undercount.
      const out = undercountedDays({
        days: ["2026-09-06"],
        countingIds: ["witr"],
        squaresByDay: {"2026-09-06": {witr: "complete"}},
        part: {
          dailyDoneCount: {},
          lastSyncedAt: new Date("2026-09-08T09:00:00Z"),
        },
        // 2026-09-06 closes 2026-09-07T07:00Z; this is 02:13 on the 7th at
        // +180, comfortably inside the tail.
        lastUpdatedByDay: {"2026-09-06": new Date("2026-09-06T23:13:00Z")},
      });
      assert.strictEqual(out.length, 1);
      assert.strictEqual(out[0].held, false, "an on-time mark is not backdating");
    });

test("with no write times the check behaves exactly as it always did", () => {
  // Absent evidence must never produce a HELD verdict: claiming the app is
  // holding a day we cannot see the write time for would hide a real
  // undercount, and nothing here writes, so reporting is the safe side.
  const out = undercountedDays({
    days: ["2026-09-03"],
    countingIds: ["a"],
    squaresByDay: {"2026-09-03": {a: "complete"}},
    part: {dailyDoneCount: {}, lastSyncedAt: new Date("2026-09-30T00:00:00Z")},
  });
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].held, false);
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

// ── The leader removing a habit, 2026-09-22 ────────────────────────────────
// Aziz's rule: it still counts on the day it is removed, and from the next
// day it counts for nobody. The app stamps `stopsOn` (the first day it no
// longer counts); a removal with no stopsOn is a legacy one and counts on no
// day, which is what keeps the A8GEL7 and BKWVN9 duplicate repairs as they
// are.

test("a removed slot counts through its removal day, and not after", () => {
  const room = {
    habitMode: "shared",
    sharedHabits: [
      {name: "quran"},
      {name: "train", removedAt: "x", stopsOn: "2026-09-23"},
      {name: "walk", removedAt: "x"},
      {name: "adhkar", offSpans: [{from: "2026-09-10", to: "2026-09-12"}]},
    ],
  };
  assert.strictEqual(slotLiveOn(room, 1, "2026-09-22"), true);
  assert.strictEqual(slotLiveOn(room, 1, "2026-09-23"), false);
  assert.strictEqual(slotLiveOn(room, 2, "2026-09-01"), false, "legacy");
  assert.strictEqual(slotLiveOn(room, 3, "2026-09-09"), true);
  assert.strictEqual(slotLiveOn(room, 3, "2026-09-11"), false);
  assert.strictEqual(slotLiveOn(room, 3, "2026-09-13"), true);

  const part = {linkedHabitIds: ["h1", "h2", "h3", "h4"]};
  // Graded on SOME day: all but the legacy removal.
  assert.deepStrictEqual(countingHabitIds(room, part), ["h1", "h2", "h4"]);
  assert.deepStrictEqual(
      countingHabitIds(room, part, "2026-09-22"), ["h1", "h2", "h4"]);
  assert.deepStrictEqual(
      countingHabitIds(room, part, "2026-09-23"), ["h1", "h4"]);
  assert.deepStrictEqual(
      countingHabitIds(room, part, "2026-09-11"), ["h1", "h2"]);
});

test("after its removal day a removed habit's green square is not an " +
    "undercount", () => {
  const room = {
    habitMode: "shared",
    sharedHabits: [
      {name: "quran"},
      {name: "train", removedAt: "x", stopsOn: "2026-09-21"},
    ],
  };
  const part = {
    linkedHabitIds: ["q", "t"],
    dailyDoneCount: {"2026-09-20": 1, "2026-09-21": 1},
  };
  const out = undercountedDays({
    days: ["2026-09-20", "2026-09-21"],
    countingIds: countingHabitIds(room, part),
    squaresByDay: {
      // The removal day still asked for both, and only one was stored.
      "2026-09-20": {q: "complete", t: "complete"},
      // Trained after the removal: the member's own business.
      "2026-09-21": {q: "complete", t: "complete"},
    },
    part,
    room,
  });
  assert.deepStrictEqual(
      out.map((u) => ({day: u.day, real: u.real, stored: u.stored})),
      [{day: "2026-09-20", real: 2, stored: 1}]);
});

// ── A slot the member relinked (RoomsController.relinkPlanHabit) ────────
//
// «تمرين» filled the «الضحى» slot until 2026-07-10 by mistake; «صلاة الضحى»
// fills it from the 11th. The member did «صلاة الضحى» on the 6th to the
// 10th as well, but it was not in the slot then, so those days are not
// short. Reading the current link back over them used to report them, with
// a set_room_day.js command that would have re-scored them.
const relinkedRoom = {
  habitMode: "shared",
  sharedHabits: [{name: "الضحى"}, {name: "قراءة القرآن"}],
};
const relinkedPart = {
  linkedHabitIds: ["m-duha", "m-q"],
  slotHabitHistory: {"0": [{habitId: "m-wrong", until: "2026-07-10"}]},
  dailyDoneCount: {"2026-07-06": 1, "2026-07-11": 2},
  dailyScheduledCount: {"2026-07-06": 2, "2026-07-11": 2},
};

test("a relinked slot names the habit that filled it each day", () => {
  assert.deepStrictEqual(
      countingHabitIds(relinkedRoom, relinkedPart, "2026-07-06"),
      ["m-wrong", "m-q"]);
  assert.deepStrictEqual(
      countingHabitIds(relinkedRoom, relinkedPart, "2026-07-10"),
      ["m-wrong", "m-q"]);
  assert.deepStrictEqual(
      countingHabitIds(relinkedRoom, relinkedPart, "2026-07-11"),
      ["m-duha", "m-q"]);
  // Every habit graded on some day, the earlier one included, once.
  assert.deepStrictEqual(countingHabitIds(relinkedRoom, relinkedPart),
      ["m-duha", "m-q", "m-wrong"]);
});

test("the new habit's squares before the change are not an undercount; " +
    "the old habit's still are", () => {
  const days = ["2026-07-06", "2026-07-11"];
  const quiet = undercountedDays({
    days,
    countingIds: countingHabitIds(relinkedRoom, relinkedPart),
    squaresByDay: {
      "2026-07-06": {"m-duha": "complete", "m-q": "complete"},
      "2026-07-11": {"m-duha": "complete", "m-q": "complete"},
    },
    part: relinkedPart,
    room: relinkedRoom,
  });
  assert.deepStrictEqual(quiet, []);
  // Had «تمرين» really been done on the 6th, the stored 1 WOULD be short.
  const short = undercountedDays({
    days,
    countingIds: countingHabitIds(relinkedRoom, relinkedPart),
    squaresByDay: {"2026-07-06": {"m-wrong": "complete", "m-q": "complete"}},
    part: relinkedPart,
    room: relinkedRoom,
  });
  assert.deepStrictEqual(short.map((u) => [u.day, u.real, u.stored]),
      [["2026-07-06", 2, 1]]);
});

test("malformed history entries are ignored, as the app ignores them", () => {
  const part = {
    linkedHabitIds: ["a", "b"],
    slotHabitHistory: {"0": [{habitId: ""}, "junk", {until: "2026-07-01"}]},
  };
  assert.deepStrictEqual(
      countingHabitIds(relinkedRoom, part, "2026-06-30"), ["a", "b"]);
  assert.deepStrictEqual(countingHabitIds(relinkedRoom, part), ["a", "b"]);
});
