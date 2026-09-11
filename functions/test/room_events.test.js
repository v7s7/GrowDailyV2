/**
 * The three-event notification model, simulated over a whole room-day.
 *
 * These tests exist because the model's whole justification is a claim
 * about numbers - that a room emits a bounded, size-independent amount of
 * push - and that claim is easy to state and easy to quietly break. The
 * per-finisher model this replaced sent N x (N-1) pushes a day; capping it
 * by room size only moved the cliff. Both regressions would look fine in
 * any single-finish test, so every test here plays a full day out.
 */

const test = require("node:test");
const assert = require("node:assert");
const {isRoomPausedOn, roomEventFor} = require("../room_events");

const DAY = "2026-08-18";

/**
 * Play a full day: every member finishes, in [order], each finish running
 * the real decision through the same once-per-room-per-day claim the
 * callable applies.
 * @param {number} n Members in the room.
 * @param {Array<number>|undefined} order Finish order, default 0..n-1.
 * @return {object} Per-member receive counts, the event log, and the total.
 */
function simulateDay(n, order) {
  const docs = Array.from({length: n}, (_, i) => ({
    id: "u" + i,
    done: false,
    data() {
      return this.done ? {allDoneToday: true, allDoneDate: DAY} : {};
    },
  }));
  const claimed = new Set();
  const received = new Map(docs.map((d) => [d.id, 0]));
  const log = [];
  for (const i of order || docs.map((_, k) => k)) {
    const finisher = docs[i];
    // The client writes allDoneToday BEFORE calling, and the callable
    // re-reads it - so the finisher is already done at decision time.
    finisher.done = true;
    const others = docs.filter((d) => d.id !== finisher.id);
    const decision = roomEventFor(others, DAY);
    if (!decision) continue;
    if (claimed.has(decision.event)) {
      log.push([finisher.id, "suppressed"]);
      continue;
    }
    claimed.add(decision.event);
    log.push([finisher.id, decision.event]);
    for (const r of decision.recipients) {
      received.set(r.id, received.get(r.id) + 1);
    }
  }
  const counts = [...received.values()];
  return {
    received,
    log,
    total: counts.reduce((a, b) => a + b, 0),
    max: Math.max(...counts),
  };
}

test("a solo room notifies nobody", () => {
  assert.strictEqual(roomEventFor([], DAY), null);
});

test("no member ever gets more than two pushes, at any room size", () => {
  for (const n of [2, 3, 4, 5, 6, 7, 10, 25, 50, 200]) {
    const {max} = simulateDay(n);
    assert.ok(max <= 2, `room of ${n} gave someone ${max} pushes`);
  }
});

test("total sends are linear in members, not quadratic", () => {
  // 2n-1: (n-1) for firstToday, 1 for lastOne, (n-1) for perfect. A room
  // of two is the one exception - its first finish IS its last-one moment,
  // so firstToday never fires and it sends 2.
  assert.strictEqual(simulateDay(2).total, 2);
  for (const n of [3, 5, 6, 10, 50, 200]) {
    assert.strictEqual(simulateDay(n).total, 2 * n - 1, `room of ${n}`);
  }
  // The model this replaced sent n x (n-1): 39,800 for a 200-person room
  // against 399 here.
  assert.ok(simulateDay(200).total < 200 * 199 / 50);
});

test("adding one member never causes a cliff", () => {
  // The regression this guards: any "small rooms fan out, large rooms send
  // once" rule makes one person joining drop a room from n-1 pushes to 1.
  // A room of two is the one step that is not +2: it sends 2 rather than
  // the 5 the formula would give, because its first finish is also its
  // last-one moment and firstToday never fires. That is a floor, not a
  // cliff - the direction that matters is a DROP as members are added.
  assert.ok(simulateDay(3).total > simulateDay(2).total);
  let prev = simulateDay(3).total;
  for (let n = 4; n <= 40; n++) {
    const total = simulateDay(n).total;
    assert.ok(total >= prev, `room of ${n} sends fewer than ${n - 1} does`);
    assert.ok(total - prev <= 2, `cliff between ${n - 1} and ${n}`);
    prev = total;
  }
});

test("a day plays out as first, then last-one, then perfect", () => {
  const {log} = simulateDay(5);
  assert.deepStrictEqual(log.map((e) => e[1]), [
    "firstToday", "suppressed", "suppressed", "lastOne", "perfect",
  ]);
});

test("last-one goes to the one person left and nobody else", () => {
  const docs = ["u0", "u1", "u2"].map((id, i) => ({
    id,
    data: () => (i < 1 ? {allDoneToday: true, allDoneDate: DAY} : {}),
  }));
  // u0 done, u1 and u2 not: two left, so this is not the last-one moment.
  assert.strictEqual(roomEventFor(docs, DAY).event, "firstToday");

  const nearlyDone = ["u0", "u1", "u2"].map((id, i) => ({
    id,
    data: () => (i < 2 ? {allDoneToday: true, allDoneDate: DAY} : {}),
  }));
  const decision = roomEventFor(nearlyDone, DAY);
  assert.strictEqual(decision.event, "lastOne");
  assert.deepStrictEqual(decision.recipients.map((d) => d.id), ["u2"]);
});

test("yesterday's finish does not count as today's", () => {
  // allDoneToday stays true overnight; only allDoneDate distinguishes.
  // Reading the flag alone would report a stale room as perfect.
  const docs = ["u0", "u1"].map((id) => ({
    id,
    data: () => ({allDoneToday: true, allDoneDate: "2026-08-17"}),
  }));
  assert.strictEqual(roomEventFor(docs, DAY).event, "firstToday");
});

test("finish order does not change what the room hears", () => {
  const forward = simulateDay(6);
  const reverse = simulateDay(6, [5, 4, 3, 2, 1, 0]);
  const shuffled = simulateDay(6, [3, 0, 5, 1, 4, 2]);
  assert.strictEqual(reverse.total, forward.total);
  assert.strictEqual(shuffled.total, forward.total);
  assert.strictEqual(reverse.max, forward.max);
  assert.strictEqual(shuffled.max, forward.max);
});

test("a member standing down today is never the last one left", () => {
  const docs = [
    {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
    {id: "u1", data: () => ({standDownDays: [DAY]})},
    {id: "u2", data: () => ({})},
  ];
  // u1 is excused today, so u2 is the only one the room is waiting on.
  const decision = roomEventFor(docs, DAY);
  assert.strictEqual(decision.event, "lastOne");
  assert.deepStrictEqual(decision.recipients.map((d) => d.id), ["u2"]);
});

test("nobody standing down is told anything about the day", () => {
  const docs = [
    {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
    {id: "u1", data: () => ({standDownDays: ["2026-08-17", DAY]})},
  ];
  // Everyone else is done and u1 stands down: no last-one push to u1, and
  // no perfect day either, since not everyone took part.
  assert.strictEqual(roomEventFor(docs, DAY), null);
  // Two left and one of them standing down: first-to-finish skips them too.
  const three = [
    {id: "u1", data: () => ({standDownDays: [DAY]})},
    {id: "u2", data: () => ({})},
    {id: "u3", data: () => ({})},
  ];
  const first = roomEventFor(three, DAY);
  assert.strictEqual(first.event, "firstToday");
  assert.deepStrictEqual(first.recipients.map((d) => d.id), ["u2", "u3"]);
});

test("standing down on another day changes nothing today", () => {
  const docs = [
    {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
    {id: "u1", data: () => ({standDownDays: ["2026-08-17"]})},
  ];
  const decision = roomEventFor(docs, DAY);
  assert.strictEqual(decision.event, "lastOne");
  assert.deepStrictEqual(decision.recipients.map((d) => d.id), ["u1"]);
});

test("a pause from before today stands until the phone syncs again", () => {
  // u1 paused every habit on the 15th and has not opened the app since, so
  // no phone has written a key for today. The last day it synced was the
  // stand-down itself.
  const paused = {standDownDays: ["2026-08-15"], lastSyncedDay: "2026-08-15"};
  const docs = [
    {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
    {id: "u1", data: () => paused},
    {id: "u2", data: () => ({lastSyncedDay: DAY})},
  ];
  const decision = roomEventFor(docs, DAY);
  assert.strictEqual(decision.event, "lastOne");
  assert.deepStrictEqual(decision.recipients.map((d) => d.id), ["u2"]);
  // Nobody else left: the paused member is not asked, and it is no perfect
  // day either.
  const pair = [
    {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
    {id: "u1", data: () => paused},
  ];
  assert.strictEqual(roomEventFor(pair, DAY), null);
});

test("a phone that synced after the pause is asked again", () => {
  // Synced today, or on an ordinary day since: the pause was taken back,
  // because the sync that ran on that day would have kept its key.
  for (const lastSyncedDay of [DAY, "2026-08-16"]) {
    const docs = [
      {id: "u0", data: () => ({allDoneToday: true, allDoneDate: DAY})},
      {id: "u1", data: () => ({standDownDays: ["2026-08-15"], lastSyncedDay})},
    ];
    const decision = roomEventFor(docs, DAY);
    assert.strictEqual(decision.event, "lastOne", lastSyncedDay);
    assert.deepStrictEqual(decision.recipients.map((d) => d.id), ["u1"]);
  }
});

test("a day the room is paused on sends no last-one or perfect push", () => {
  // The dead days between a room ending and its leader extending it
  // (RoomModel.pausedSpans). The room does not count them, so the complete
  // day the last-one push promises, and the perfect push announces, never
  // comes.
  const spans = [{from: "2026-08-15", to: "2026-08-20"}];
  const finished = {allDoneToday: true, allDoneDate: DAY};
  const lastOne = [
    {id: "u0", data: () => finished},
    {id: "u1", data: () => ({})},
  ];
  assert.strictEqual(roomEventFor(lastOne, DAY).event, "lastOne");
  assert.strictEqual(roomEventFor(lastOne, DAY, spans), null);
  const perfect = [{id: "u0", data: () => finished}];
  assert.strictEqual(roomEventFor(perfect, DAY).event, "perfect");
  assert.strictEqual(roomEventFor(perfect, DAY, spans), null);
  // First to finish still goes: it promises nothing about the room's day.
  const open = [{id: "u1", data: () => ({})}, {id: "u2", data: () => ({})}];
  const first = roomEventFor(open, DAY, spans);
  assert.strictEqual(first.event, "firstToday");
  assert.deepStrictEqual(first.recipients.map((d) => d.id), ["u1", "u2"]);
});

test("a pause holds on both of its ends and on no day outside them", () => {
  const spans = [{from: "2026-08-17", to: "2026-08-19"}];
  const oneLeft = [{id: "u1", data: () => ({})}];
  const cases = [
    ["2026-08-16", false],
    ["2026-08-17", true],
    ["2026-08-18", true],
    ["2026-08-19", true],
    ["2026-08-20", false],
  ];
  for (const [day, paused] of cases) {
    assert.strictEqual(isRoomPausedOn(spans, day), paused, day);
    const decision = roomEventFor(oneLeft, day, spans);
    assert.strictEqual(
        decision && decision.event, paused ? null : "lastOne", day);
  }
  // A one-day span, and two spans stored oldest first.
  assert.strictEqual(isRoomPausedOn([{from: DAY, to: DAY}], DAY), true);
  const two = [
    {from: "2026-08-01", to: "2026-08-03"},
    {from: "2026-08-18", to: "2026-08-25"},
  ];
  assert.strictEqual(isRoomPausedOn(two, DAY), true);
  assert.strictEqual(isRoomPausedOn(two, "2026-08-10"), false);
});

test("a pause is read the way the room model reads it", () => {
  // RoomModel.spansFrom keeps only {from, to} pairs of strings with from on
  // or before to, and a room with no pausedSpans field has no pause.
  const unreadable = [
    undefined,
    null,
    DAY,
    {from: DAY, to: DAY},
    [],
    [null],
    [DAY],
    [{from: DAY}],
    [{to: DAY}],
    [{from: 20260818, to: 20260818}],
    [{from: "2026-08-19", to: "2026-08-17"}],
  ];
  const oneLeft = [{id: "u1", data: () => ({})}];
  for (const spans of unreadable) {
    const label = JSON.stringify(spans) || String(spans);
    assert.strictEqual(isRoomPausedOn(spans, DAY), false, label);
    assert.strictEqual(
        roomEventFor(oneLeft, DAY, spans).event, "lastOne", label);
  }
  // An entry the model drops does not hide a good one beside it.
  assert.strictEqual(isRoomPausedOn(
      [{from: "2026-08-19", to: "2026-08-17"}, {from: "2026-08-10", to: DAY}],
      DAY), true);
});
