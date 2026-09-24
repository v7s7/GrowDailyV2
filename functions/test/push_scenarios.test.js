/**
 * Whole-system simulation of the room push feature, every rule at once.
 *
 * room_events.test.js proves the EVENT model in isolation: three events per
 * room per day, linear in members. push_policy.test.js proves the per-person
 * RULES in isolation: quiet hours and one push of each kind per day. Neither
 * says what a real day feels like when they compose: a person in five rooms,
 * a room of a hundred where most members arrived muted, a finisher at Fajr,
 * two time zones in one room, the same finish reported twice, a push held
 * past someone's quiet hours, and a day finished after midnight.
 *
 * So this file rebuilds the callable's and the sweep's orchestration over
 * an in-memory world (users, rooms, participant docs, quota maps), calling
 * the SAME pure functions index.js calls and claiming in the SAME order, and
 * plays whole days out at every room size that matters: 2, 3, 5, 10, 12, 13,
 * 50, 100 and 200. Anything the real functions do that is not modelled here
 * is I/O: Firestore reads, FCM sends, logging.
 *
 * Mirrored from the app, not imported (functions cannot see Dart):
 * kRoomAutoMuteMemberLimit = 12, meaning whoever joins a room that already
 * has more than twelve members arrives with the room's bell muted.
 */

const test = require("node:test");
const assert = require("node:assert");
const {roomEventFor} = require("../room_events");
const {
  KIND_CAPS,
  claimQuota,
  heldUntilMs,
  isQuietHoursNow,
  localDayKey,
  pushKindFor,
  roomPushPlan,
} = require("../push_policy");

const AUTO_MUTE_LIMIT = 12;
const BAHRAIN = 180;
const LOS_ANGELES = -420;
const DAY_MS = 24 * 60 * 60 * 1000;

/** A moment on 2026-09-05, given as Bahrain wall-clock hours. */
const bahrain = (hour, minute = 0) =>
  Date.UTC(2026, 8, 5, hour - 3, minute);

function makeWorld() {
  return {users: new Map(), rooms: new Map(), sent: [], held: []};
}

/**
 * @param {object} world
 * @param {string} uid
 * @param {object} [opts] tz (minutes, or undefined for "never reported"),
 *     settings (mirrored notificationSettings, or undefined), token (bool).
 */
function addUser(world, uid, opts = {}) {
  world.users.set(uid, {
    tz: "tz" in opts ? opts.tz : BAHRAIN,
    settings: opts.settings,
    token: opts.token !== false,
    quota: undefined,
    eveningNudgeDate: undefined,
  });
}

/**
 * @param {object} world
 * @param {string} code
 * @param {Array<string>} uids In join order.
 * @param {object} [opts] autoMute (default true): members past the twelfth
 *     arrive muted, as the app does.
 */
function addRoom(world, code, uids, opts = {}) {
  const autoMute = opts.autoMute !== false;
  const participants = new Map();
  uids.forEach((uid, i) => {
    participants.set(uid, {
      allDoneToday: false,
      allDoneDate: null,
      lastFinishNotifiedDate: null,
      notificationsMuted: autoMute && i >= AUTO_MUTE_LIMIT,
    });
  });
  world.rooms.set(code, {participants, pushEventDays: {}});
}

/**
 * One member finishes their habits in one room: the client's own write,
 * then exactly what notifyRoomFinish does with it.
 * @param {object} [opts] dayKey: the day finished, when it is not the
 *     finisher's calendar day (a day finished after midnight, in the app's
 *     00:00 to 10:00 window, is yesterday's).
 * @return {object} What happened, in the callable's own terms.
 */
function finish(world, code, uid, nowMs, opts = {}) {
  const room = world.rooms.get(code);
  const me = world.users.get(uid);
  const dayKey = opts.dayKey || localDayKey(me.tz, nowMs);
  const mine = room.participants.get(uid);
  // RoomsController writes allDoneToday/allDoneDate, then calls.
  mine.allDoneToday = true;
  mine.allDoneDate = dayKey;

  if (mine.lastFinishNotifiedDate === dayKey) {
    return {suppressed: "alreadyNotified"};
  }
  mine.lastFinishNotifiedDate = dayKey;

  const others = [...room.participants.entries()]
      .filter(([id]) => id !== uid)
      .map(([id, data]) => ({id, data: () => data}));
  const decision = roomEventFor(others, dayKey);
  if (!decision) return {suppressed: "solo-room"};
  if (room.pushEventDays[decision.event] === dayKey) {
    return {suppressed: decision.event + "-already-sent-today"};
  }
  room.pushEventDays[decision.event] = dayKey;

  const kind = pushKindFor(decision.event);
  const out = {
    event: decision.event,
    sent: [],
    held: [],
    skipped: {muted: 0, pastDay: 0, noToken: 0, capped: 0},
    reads: 0,
  };
  for (const doc of decision.recipients) {
    const part = doc.data();
    const u = world.users.get(doc.id);
    if (part.notificationsMuted) {
      out.skipped.muted++;
      continue;
    }
    out.reads++; // isEligible: the user doc
    const quiet = isQuietHoursNow(u.settings, u.tz, nowMs);
    const atMs = quiet ? heldUntilMs(u.settings, u.tz, nowMs) : null;
    const plan = roomPushPlan({
      event: decision.event,
      dayKey,
      readerToday: localDayKey(u.tz, nowMs),
      quiet,
      heldUntilDay: quiet ? localDayKey(u.tz, atMs) : undefined,
    });
    if (plan.action === "drop") {
      out.skipped.pastDay++;
      continue;
    }
    if (plan.action === "hold") {
      out.held.push(doc.id);
      world.held.push(
          {uid: doc.id, code, event: decision.event, dayKey, finisher: uid,
            atMs});
      continue;
    }
    out.reads++; // the tokens subcollection
    if (!u.token) {
      out.skipped.noToken++;
      continue;
    }
    out.reads++; // the quota transaction
    const claim = claimQuota(u.quota, plan.quotaDay, kind);
    if (!claim.allowed) {
      out.skipped.capped++;
      continue;
    }
    u.quota = claim.next;
    out.sent.push(doc.id);
    world.sent.push({uid: doc.id, code, event: decision.event, kind, nowMs,
      yesterday: plan.yesterday});
  }
  return out;
}

/**
 * Cloud Tasks firing every held push due by [nowMs]: what
 * deliverDeferredRoomPush does with each, over the in-memory world. The
 * push is decided afresh, the way the real one is: the reader's day now,
 * and the room's own decision for the day the push is about, run again.
 * @return {Array<object>} One entry per push that came due, with `sent` or
 *     `dropped` (the reason).
 */
function deliverHeld(world, nowMs) {
  const due = world.held.filter((h) => h.atMs <= nowMs);
  world.held = world.held.filter((h) => h.atMs > nowMs);
  const out = [];
  for (const h of due) {
    const u = world.users.get(h.uid);
    const room = world.rooms.get(h.code);
    if (isQuietHoursNow(u.settings, u.tz, nowMs)) {
      out.push({...h, dropped: "still-quiet"});
      continue;
    }
    const plan = roomPushPlan(
        {event: h.event, dayKey: h.dayKey, readerToday: localDayKey(u.tz, nowMs)});
    if (plan.action !== "send") {
      out.push({...h, dropped: plan.reason});
      continue;
    }
    const others = [...room.participants.entries()]
        .filter(([id]) => id !== h.finisher)
        .map(([id, data]) => ({id, data: () => data}));
    // The room's own decision, run again, for the finish events. (A held
    // "habit was added" is checked against its slot instead, which this
    // world does not model.)
    const decision = h.event === "habitAdded" ?
      null : roomEventFor(others, h.dayKey);
    if (h.event !== "habitAdded" && (!decision ||
        decision.event !== h.event ||
        !decision.recipients.some((d) => d.id === h.uid))) {
      out.push({...h, dropped: "no-longer-true"});
      continue;
    }
    if (!u.token) {
      out.push({...h, dropped: "no-token"});
      continue;
    }
    const kind = pushKindFor(h.event);
    const claim = claimQuota(u.quota, plan.quotaDay, kind);
    if (!claim.allowed) {
      out.push({...h, dropped: "capped"});
      continue;
    }
    u.quota = claim.next;
    world.sent.push({uid: h.uid, code: h.code, event: h.event, kind, nowMs,
      yesterday: plan.yesterday});
    out.push({...h, sent: true, yesterday: plan.yesterday});
  }
  return out;
}

// The hourly evening sweep (roomEveningReminder) was simulated here until
// it was removed on 2026-09-16. Every push this file still models is
// caused by a person finishing; nothing here fires from inactivity.

/** Deterministic shuffle so a failure reproduces. */
function shuffled(items, seed) {
  const out = [...items];
  let s = seed;
  for (let i = out.length - 1; i > 0; i--) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    const j = s % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

const uids = (n, prefix = "u") =>
  Array.from({length: n}, (_, i) => `${prefix}${i}`);

/** Per-user counts of what they received, by kind and in total. */
function tally(world) {
  const byUser = new Map();
  for (const s of world.sent) {
    const t = byUser.get(s.uid) || {total: 0};
    t.total++;
    t[s.kind] = (t[s.kind] || 0) + 1;
    byUser.set(s.uid, t);
  }
  return byUser;
}

/**
 * A whole day in one room of [n]: everyone finishes, in a shuffled order,
 * mid-afternoon. Returns everything a test could want to assert on.
 */
function playRoomDay(n, {autoMute = true, seed = 7} = {}) {
  const world = makeWorld();
  const members = uids(n);
  members.forEach((u) => addUser(world, u));
  addRoom(world, "R", members, {autoMute});
  const order = shuffled(members, seed);
  const events = [];
  let reads = 0;
  order.forEach((uid, i) => {
    const r = finish(world, "R", uid, bahrain(15, i));
    if (r.event) {
      events.push(r.event);
      reads = Math.max(reads, r.reads);
    }
  });
  return {world, order, events, tally: tally(world), maxReadsPerEvent: reads};
}

// ── Room size ────────────────────────────────────────────────────────────

test("every room size claims the same events: two for a pair, three otherwise",
    () => {
      for (const n of [2, 3, 5, 10, 12, 13, 50, 100, 200]) {
        const {events} = playRoomDay(n);
        if (n === 2) {
          // The first finish in a pair IS the last-one moment.
          assert.deepEqual(events, ["lastOne", "perfect"], `room of ${n}`);
        } else {
          assert.deepEqual(events, ["firstToday", "lastOne", "perfect"],
              `room of ${n}`);
        }
      }
    });

test("nobody, at any size, receives more than one push of any kind", () => {
  for (const n of [2, 3, 5, 10, 12, 13, 50, 100, 200]) {
    for (const autoMute of [true, false]) {
      const {tally: t} = playRoomDay(n, {autoMute});
      for (const [uid, counts] of t) {
        for (const kind of Object.keys(KIND_CAPS)) {
          assert.ok((counts[kind] || 0) <= KIND_CAPS[kind],
              `room of ${n}: ${uid} got ${counts[kind]} ${kind}`);
        }
        assert.ok(counts.total <= 3, `room of ${n}: ${uid} got ${counts.total}`);
      }
    }
  }
});

test("a full day is: first finisher hears the celebration, last hears the nudge",
    () => {
      for (const n of [3, 5, 10, 12]) {
        const {order, tally: t} = playRoomDay(n);
        const first = order[0];
        const last = order[n - 1];
        // The first finisher caused firstToday, so did not receive it, and
        // was done long before lastOne. Their one push is the perfect day.
        assert.deepEqual(t.get(first), {total: 1, celebrate: 1},
            `room of ${n}: first finisher`);
        // The last finisher was told someone started, then that everyone
        // else was done. They caused the perfect day, so do not hear it.
        assert.deepEqual(t.get(last), {total: 2, info: 1, nudge: 1},
            `room of ${n}: last finisher`);
        // Everyone in between: the heads-up and the celebration.
        for (const uid of order.slice(1, -1)) {
          assert.deepEqual(t.get(uid), {total: 2, info: 1, celebrate: 1},
              `room of ${n}: ${uid}`);
        }
      }
    });

test("a pair: each hears exactly one thing", () => {
  const {order, tally: t} = playRoomDay(2);
  assert.deepEqual(t.get(order[1]), {total: 1, nudge: 1},
      "the second is told they are the last one");
  assert.deepEqual(t.get(order[0]), {total: 1, celebrate: 1},
      "the first is told the day was perfect");
});

test("the perfect day reaches every unmuted member who did not cause it", () => {
  // This is the case a shared heads-up/celebration slot would have broken:
  // by the last finish everyone else has already had 'first to finish'.
  const {world, order} = playRoomDay(5);
  const perfect = world.sent.filter((s) => s.event === "perfect");
  assert.deepEqual(new Set(perfect.map((s) => s.uid)),
      new Set(order.slice(0, 4)));
});

test("a big room only ever reaches the members who arrived unmuted", () => {
  for (const n of [13, 50, 100, 200]) {
    const {world, tally: t} = playRoomDay(n);
    const mutedIds = new Set(uids(n).slice(AUTO_MUTE_LIMIT));
    for (const uid of mutedIds) {
      assert.equal(t.has(uid), false, `room of ${n}: muted ${uid} was pushed`);
    }
    // And the unmuted twelve are treated exactly like a room of twelve:
    // the cap is on the person, so the room's size never leaks through.
    const loudest = Math.max(...[...t.values()].map((c) => c.total));
    assert.ok(loudest <= 3);
    assert.ok(world.sent.length <= 3 * AUTO_MUTE_LIMIT,
        `room of ${n} sent ${world.sent.length}`);
  }
});

test("a legacy big room with nobody muted still sends linearly, never more",
    () => {
      for (const n of [50, 100, 200]) {
        const {world, maxReadsPerEvent} = playRoomDay(n, {autoMute: false});
        // 2n-1 sends: n-1 heads-ups, one nudge, n-1 celebrations.
        assert.equal(world.sent.length, 2 * n - 1, `room of ${n}`);
        // The callable's Firestore work per event is three reads per
        // recipient, so a 200-person event is ~600 reads and a few seconds,
        // well inside a callable's 60s. Nothing here is quadratic.
        assert.ok(maxReadsPerEvent <= 3 * (n - 1), `room of ${n} reads`);
      }
    });

test("finish order changes who is first and last, never what the room hears",
    () => {
      const seeds = [1, 2, 3, 4, 5];
      const totals = seeds.map((seed) => {
        const {world, events, tally: t} = playRoomDay(6, {seed});
        return {
          events: events.join(","),
          sent: world.sent.length,
          shape: [...t.values()].map((c) => c.total).sort().join(""),
        };
      });
      for (const r of totals) assert.deepEqual(r, totals[0]);
    });

test("a finisher never receives the push their own finish caused", () => {
  const {world, order} = playRoomDay(7);
  // Replay: the event a finish caused is recorded against that moment; no
  // send at that moment may name the finisher.
  const byMoment = new Map();
  for (const s of world.sent) {
    byMoment.set(s.nowMs, (byMoment.get(s.nowMs) || new Set()).add(s.uid));
  }
  order.forEach((uid, i) => {
    const recipients = byMoment.get(bahrain(15, i));
    if (recipients) assert.equal(recipients.has(uid), false);
  });
});

// ── One person, many rooms ───────────────────────────────────────────────

test("five rooms starting the day: one heads-up, not five", () => {
  const world = makeWorld();
  addUser(world, "aziz");
  for (let r = 0; r < 5; r++) {
    const others = uids(3, `r${r}m`);
    others.forEach((u) => addUser(world, u));
    addRoom(world, `R${r}`, ["aziz", ...others]);
    finish(world, `R${r}`, others[0], bahrain(9, r));
  }
  const mine = world.sent.filter((s) => s.uid === "aziz");
  assert.equal(mine.length, 1);
  assert.equal(mine[0].event, "firstToday");
  // The other rooms' events were still claimed (they are per room), and
  // the other members still heard them: only THIS person was capped.
  for (let r = 0; r < 5; r++) {
    assert.equal(world.rooms.get(`R${r}`).pushEventDays.firstToday,
        "2026-09-05");
  }
});

test("last one standing in five rooms is one nudge for the whole day",
    () => {
      const world = makeWorld();
      addUser(world, "aziz");
      for (let r = 0; r < 5; r++) {
        const others = uids(3, `r${r}m`);
        others.forEach((u) => addUser(world, u));
        addRoom(world, `R${r}`, ["aziz", ...others]);
        others.forEach((u, i) => finish(world, `R${r}`, u, bahrain(10 + r, i)));
      }
      // A sixth room where nothing happened all day, which nothing in the
      // server now reacts to: a quiet room is quiet.
      const quiet = uids(3, "qm");
      quiet.forEach((u) => addUser(world, u));
      addRoom(world, "Q", ["aziz", ...quiet]);

      const mine = world.sent.filter((s) => s.uid === "aziz");
      assert.deepEqual(mine.map((s) => s.event), ["firstToday", "lastOne"],
          "one heads-up from the first room to start, one nudge from the " +
          "first room to reach last-one; the other four lastOnes were capped");
      assert.equal(world.sent.filter((s) => s.uid.startsWith("qm")).length, 0,
          "the silent room's members hear nothing at all");
    });

// ── Clocks ───────────────────────────────────────────────────────────────

test("a Fajr finish wakes nobody with default settings: held to 07:02",
    () => {
      const world = makeWorld();
      const members = uids(5);
      members.forEach((u) => addUser(world, u));
      // One member has switched quiet hours off in the app.
      world.users.get("u4").settings = {quietHoursEnabled: false};
      addRoom(world, "R", members);

      const r = finish(world, "R", "u0", bahrain(4, 30));
      assert.equal(r.event, "firstToday");
      assert.deepEqual(r.sent, ["u4"]);
      assert.deepEqual(r.held.sort(), ["u1", "u2", "u3"],
          "still the same day when their quiet hours end, so it waits");
      // 07:02: the day is still the one the heads-up is about, and none of
      // the three has finished, so each hears it then.
      const morning = deliverHeld(world, bahrain(7, 2));
      assert.deepEqual(morning.map((h) => h.sent), [true, true, true]);

      // A second finisher at 08:00 does not re-fire the heads-up for the
      // three who slept through it: the event was claimed.
      const again = finish(world, "R", "u1", bahrain(8));
      assert.equal(again.suppressed, "firstToday-already-sent-today");
      // They do still hear the later events of the day, in the daytime.
      finish(world, "R", "u2", bahrain(9));
      const lastOne = finish(world, "R", "u3", bahrain(10));
      assert.equal(lastOne.event, "lastOne");
      assert.deepEqual(lastOne.sent, ["u4"]);
    });

test("two time zones in one room are judged on their own clocks", () => {
  const world = makeWorld();
  addUser(world, "bh0");
  addUser(world, "bh1");
  addUser(world, "la0", {tz: LOS_ANGELES});
  addUser(world, "la1", {tz: LOS_ANGELES});
  addRoom(world, "R", ["bh0", "bh1", "la0", "la1"]);
  // 01:00 UTC: 04:00 in Bahrain (quiet by default), 18:00 in Los Angeles.
  const nowMs = Date.UTC(2026, 8, 5, 1, 0);
  const r = finish(world, "R", "bh0", nowMs);
  assert.equal(r.event, "firstToday");
  assert.deepEqual(r.sent.sort(), ["la0", "la1"]);
  assert.deepEqual(r.held, ["bh1"]);
  // Their quota is charged to THEIR day, which is still the 4th.
  assert.equal(world.users.get("la0").quota.date, "2026-09-04");
});

test("a member whose offset was never reported still gets pushes", () => {
  const world = makeWorld();
  addUser(world, "known");
  addUser(world, "unknown", {tz: undefined});
  addUser(world, "third");
  addRoom(world, "R", ["known", "unknown", "third"]);
  // The unknown-offset member cannot be judged quiet, so hears it rather
  // than being silenced for a guess (push_policy rule 1).
  const r = finish(world, "R", "third", bahrain(15));
  assert.deepEqual(r.sent.sort(), ["known", "unknown"]);
});

// ── Repeats and days ─────────────────────────────────────────────────────

test("the same finish reported twice, or resynced later, sends once", () => {
  const world = makeWorld();
  uids(3).forEach((u) => addUser(world, u));
  addRoom(world, "R", uids(3));
  const first = finish(world, "R", "u0", bahrain(15));
  assert.equal(first.event, "firstToday");
  assert.equal(finish(world, "R", "u0", bahrain(15, 1)).suppressed,
      "alreadyNotified");
  assert.equal(finish(world, "R", "u0", bahrain(22)).suppressed,
      "alreadyNotified", "a room-open resync at night is not a new finish");
  assert.equal(world.sent.length, 2);
});

test("a member with no device is skipped without spending their slot", () => {
  const world = makeWorld();
  addUser(world, "u0");
  addUser(world, "u1", {token: false});
  addUser(world, "u2");
  addRoom(world, "R", uids(3));
  const r = finish(world, "R", "u0", bahrain(15));
  assert.deepEqual(r.sent, ["u2"]);
  assert.equal(r.skipped.noToken, 1);
  assert.equal(world.users.get("u1").quota, undefined,
      "no quota row is ever written for someone who could not receive");
});

test("tomorrow starts clean: events fire again and quotas reset", () => {
  const world = makeWorld();
  uids(3).forEach((u) => addUser(world, u));
  addRoom(world, "R", uids(3));
  uids(3).forEach((u, i) => finish(world, "R", u, bahrain(15, i)));
  const day1 = world.sent.length;
  assert.equal(day1, 5);
  // Next day, same room, same order.
  uids(3).forEach((u, i) => finish(world, "R", u, bahrain(15, i) + DAY_MS));
  assert.equal(world.sent.length, 2 * day1);
  for (const u of uids(3)) {
    assert.equal(world.users.get(u).quota.date, "2026-09-06");
  }
});

test("yesterday's finish does not make today's room look started", () => {
  const world = makeWorld();
  uids(3).forEach((u) => addUser(world, u));
  addRoom(world, "R", uids(3));
  finish(world, "R", "u0", bahrain(15) - DAY_MS);
  world.sent.length = 0;
  const r = finish(world, "R", "u1", bahrain(15));
  assert.equal(r.event, "firstToday",
      "u0's stale allDoneToday from yesterday is not counted as done today");
  assert.deepEqual(r.sent.sort(), ["u0", "u2"]);
});

test("a solo room and a room where nothing happens send nothing", () => {
  const world = makeWorld();
  addUser(world, "solo");
  addRoom(world, "S", ["solo"]);
  assert.equal(finish(world, "S", "solo", bahrain(15)).suppressed,
      "solo-room");
  uids(4).forEach((u) => addUser(world, u));
  addRoom(world, "R", uids(4));
  // Nobody finishes, so nothing is sent — at any hour. The evening sweep
  // used to be the exception here; it was removed on 2026-09-16, and a
  // room that stays quiet now stays quiet.
  assert.equal(world.sent.length, 0);
});

// ── A push about a day that is over (Aziz, 2026-09-24) ──────────────────

test("23 Sep in PBYAS5: no stale morning push, and today's slot stays free",
    () => {
      const world = makeWorld();
      addUser(world, "aziz", {settings: {quietHoursEnabled: false}});
      // نور never mirrored her settings: the default 22:00 to 07:00 window.
      addUser(world, "noor");
      addRoom(world, "PBYAS5", ["aziz", "noor"]);

      const r1 = finish(world, "PBYAS5", "aziz", bahrain(22, 39));
      assert.equal(r1.event, "lastOne");
      assert.equal(r1.skipped.pastDay, 1,
          "held to 07:02 it would be about yesterday, so it is not held");
      assert.equal(world.held.length, 0);

      const r2 = finish(world, "PBYAS5", "noor", bahrain(23, 47));
      assert.equal(r2.event, "perfect");
      assert.deepEqual(r2.sent, ["aziz"]);

      // The next morning brings her nothing. It used to bring «سوي عادتك
      // الحين» at 07:02 about the day she had finished at 23:47.
      assert.deepEqual(deliverHeld(world, bahrain(7, 2) + DAY_MS), []);
      assert.equal(world.sent.filter((s) => s.uid === "noor").length, 0);

      // And the next evening's real last one reaches her. The held push
      // used to claim this day's nudge slot at 07:02 and cap it.
      const r3 = finish(world, "PBYAS5", "aziz", bahrain(18) + DAY_MS);
      assert.equal(r3.event, "lastOne");
      assert.deepEqual(r3.sent, ["noor"]);
    });

test("a perfect day finished in someone's quiet hours is not saved for " +
    "the morning", () => {
  // Aziz, 2026-09-24: a celebration of yesterday arriving the next morning
  // has no benefit.
  const world = makeWorld();
  addUser(world, "a");
  addUser(world, "b", {settings: {quietHoursEnabled: false}});
  addRoom(world, "R", ["a", "b"]);
  finish(world, "R", "a", bahrain(21));
  const r = finish(world, "R", "b", bahrain(23, 10));
  assert.equal(r.event, "perfect");
  assert.deepEqual(r.held, []);
  assert.equal(r.skipped.pastDay, 1);
  assert.deepEqual(deliverHeld(world, bahrain(7, 2) + DAY_MS), []);
  assert.equal(world.users.get("a").quota, undefined,
      "nothing was sent, so nothing was counted");
});

test("a day finished after midnight sends nothing about yesterday", () => {
  const world = makeWorld();
  addUser(world, "a", {settings: {quietHoursEnabled: false}});
  addUser(world, "b", {settings: {quietHoursEnabled: false}});
  addRoom(world, "R", ["a", "b"]);
  // a finishes the 5th at 00:33 on the 6th, inside the app's window for
  // finishing yesterday (rooms_notifier.dart finishDayKey).
  const r1 = finish(world, "R", "a", bahrain(0, 33) + DAY_MS,
      {dayKey: "2026-09-05"});
  assert.equal(r1.event, "lastOne");
  assert.deepEqual(r1.sent, []);
  assert.equal(r1.skipped.pastDay, 1,
      "«سوي عادتك الحين» after midnight would point at the wrong day");

  const r2 = finish(world, "R", "b", bahrain(0, 50) + DAY_MS,
      {dayKey: "2026-09-05"});
  assert.equal(r2.event, "perfect");
  assert.deepEqual(r2.sent, []);
  assert.equal(r2.skipped.pastDay, 1);
  assert.equal(world.sent.length, 0);
});

test("a held same-day push is dropped when its reader finished meanwhile",
    () => {
      const world = makeWorld();
      // A daytime window: quiet 13:00 to 15:00, so a hold stays same-day.
      const nap = {quietHoursEnabled: true, quietHoursStart: "13:0",
        quietHoursEnd: "15:0"};
      addUser(world, "a");
      addUser(world, "b", {settings: nap});
      addRoom(world, "R", ["a", "b"]);
      const r = finish(world, "R", "a", bahrain(13, 30));
      assert.equal(r.event, "lastOne");
      assert.deepEqual(r.held, ["b"]);
      finish(world, "R", "b", bahrain(14, 10));
      const due = deliverHeld(world, bahrain(15, 2));
      assert.equal(due.length, 1);
      assert.equal(due[0].dropped, "no-longer-true",
          "b finished at 14:10: the ask is moot, so it is never delivered");
    });

test("nothing held is ever delivered about the day before yesterday", () => {
  const world = makeWorld();
  addUser(world, "a");
  addUser(world, "b");
  addRoom(world, "R", ["a", "b"]);
  // A new habit added at 23:00, held for a's morning, and Cloud Tasks
  // running a full day late.
  world.held.push({uid: "a", code: "R", event: "habitAdded",
    dayKey: "2026-09-05", finisher: null, atMs: bahrain(7, 2) + DAY_MS});
  const late = deliverHeld(world, bahrain(7, 2) + 2 * DAY_MS);
  assert.equal(late[0].dropped, "too-old");
  const onTime = [{uid: "a", code: "R", event: "habitAdded",
    dayKey: "2026-09-05", finisher: null, atMs: bahrain(7, 2) + DAY_MS}];
  world.held.push(...onTime);
  assert.equal(deliverHeld(world, bahrain(7, 2) + DAY_MS)[0].sent, true,
      "the morning after it was added, it still goes");
});
