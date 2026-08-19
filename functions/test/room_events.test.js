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
const {roomEventFor} = require("../room_events");

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
