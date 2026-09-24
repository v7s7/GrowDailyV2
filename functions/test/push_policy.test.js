/**
 * The two "no spam" rules, pinned.
 *
 * Both exist because of something that actually happened in the data: 108
 * of 113 accounts had never mirrored their notification settings, so the
 * function read them as having no quiet hours at all, and the daily cap was
 * three of anything, so a person in five rooms could have every slot spent
 * on morning heads-ups before the one push that needed them in the evening.
 */

const test = require("node:test");
const assert = require("node:assert");
const {
  HELD_BROADCAST_MAX_MS,
  HOLD_BUFFER_MS,
  STALE_TOKEN_GAP_MS,
  claimQuota,
  heldBroadcastPlan,
  heldUntilMs,
  isQuietAtLocalMinute,
  isQuietHoursNow,
  liveTokens,
  localDayKey,
  localMinutes,
  msUntilQuietHoursEnd,
  pushKindFor,
  roomPushPlan,
  shiftDay,
} = require("../push_policy");

const min = (h, m = 0) => h * 60 + m;

test("an account that never wrote settings gets the app's default window", () => {
  // 22:00 to 07:00, exactly what NotificationSettings defaults to.
  assert.equal(isQuietAtLocalMinute(undefined, min(4, 30)), true,
      "a Fajr-time push used to go out to everyone with no settings");
  assert.equal(isQuietAtLocalMinute(undefined, min(23)), true);
  assert.equal(isQuietAtLocalMinute(undefined, min(6, 59)), true);
  assert.equal(isQuietAtLocalMinute(undefined, min(7)), false,
      "the end is exclusive, like the app's own check");
  assert.equal(isQuietAtLocalMinute(undefined, min(13)), false);
});

test("a person who switched quiet hours off is not quiet at any hour", () => {
  const off = {quietHoursEnabled: false};
  assert.equal(isQuietAtLocalMinute(off, min(3)), false);
});

test("a same-day window and a zero-width window behave like the app's", () => {
  const afternoon =
    {quietHoursEnabled: true, quietHoursStart: "13:0", quietHoursEnd: "14:0"};
  assert.equal(isQuietAtLocalMinute(afternoon, min(13, 30)), true);
  assert.equal(isQuietAtLocalMinute(afternoon, min(14)), false);
  const zero =
    {quietHoursEnabled: true, quietHoursStart: "9:0", quietHoursEnd: "9:0"};
  assert.equal(isQuietAtLocalMinute(zero, min(9)), false);
});

test("garbage in the stored window fails open, never silently quiet", () => {
  const bad = {quietHoursEnabled: true, quietHoursStart: "late", quietHoursEnd: 7};
  assert.equal(isQuietAtLocalMinute(bad, min(3)), false);
});

test("the recipient's clock is their offset, not the server's", () => {
  // 01:00 UTC is 04:00 in Bahrain (+180) and 20:00 in Los Angeles (-300).
  const nowMs = Date.UTC(2026, 8, 5, 1, 0);
  assert.equal(localMinutes(180, nowMs), min(4));
  assert.equal(localMinutes(-300, nowMs), min(20));
  assert.equal(isQuietHoursNow(undefined, 180, nowMs), true);
  assert.equal(isQuietHoursNow(undefined, -300, nowMs), false);
});

test("no reported offset means nothing can be judged, so it is not quiet", () => {
  assert.equal(isQuietHoursNow(undefined, undefined, Date.UTC(2026, 8, 5, 1)),
      false);
});

test("the three pushes split into a heads-up, a nudge and a celebration", () => {
  assert.equal(pushKindFor("firstToday"), "info");
  assert.equal(pushKindFor("perfect"), "celebrate");
  assert.equal(pushKindFor("lastOne"), "nudge");
  assert.equal(pushKindFor("somethingNew"), "info",
      "an event nobody classified gets the plain heads-up slot");
  assert.equal(pushKindFor("eveningReminder"), "info",
      "the evening reminder was removed on 2026-09-16; an event this file " +
      "no longer knows falls back to the heads-up slot like any other");
});

test("one of each kind a day, and none crowds out another", () => {
  const day = "2026-09-05";
  let q;
  // Three rooms' "first to finish" in one morning: only the first lands.
  let r = claimQuota(q, day, "info");
  assert.equal(r.allowed, true);
  q = r.next;
  r = claimQuota(q, day, "info");
  assert.equal(r.allowed, false);
  r = claimQuota(q, day, "info");
  assert.equal(r.allowed, false);
  // The evening nudge still gets through: its slot is its own.
  r = claimQuota(q, day, "nudge");
  assert.equal(r.allowed, true);
  q = r.next;
  assert.deepEqual(q, {date: day, info: 1, nudge: 1, celebrate: 0});
  // And a second nudge does not.
  assert.equal(claimQuota(q, day, "nudge").allowed, false);
  // A perfect day is still heard after both, once.
  r = claimQuota(q, day, "celebrate");
  assert.equal(r.allowed, true);
  q = r.next;
  assert.equal(claimQuota(q, day, "celebrate").allowed, false);
  assert.deepEqual(q, {date: day, info: 1, nudge: 1, celebrate: 1});
});

test("a new day starts from zero, and the old {date, count} shape is ignored",
    () => {
      const yesterday = {date: "2026-09-04", info: 1, nudge: 1, celebrate: 1};
      assert.equal(claimQuota(yesterday, "2026-09-05", "info").allowed, true);
      const legacy = {date: "2026-09-05", count: 3};
      const r = claimQuota(legacy, "2026-09-05", "nudge");
      assert.equal(r.allowed, true);
      assert.deepEqual(r.next,
          {date: "2026-09-05", info: 0, nudge: 1, celebrate: 0});
    });

test("a refused claim leaves the stored counts exactly as they were", () => {
  const q = {date: "2026-09-05", info: 1, nudge: 0, celebrate: 0};
  const r = claimQuota(q, "2026-09-05", "info");
  assert.equal(r.allowed, false);
  assert.deepEqual(r.next, q);
});

test("a held push waits exactly until the default window's 07:00", () => {
  // 04:30 local, default 22:00-07:00 window: 2h30m left.
  assert.equal(
      msUntilQuietHoursEnd(undefined, 0, Date.UTC(2026, 8, 5, 4, 30)),
      (2 * 60 + 30) * 60 * 1000);
  // 23:00 local: 8 hours left, crossing midnight.
  assert.equal(
      msUntilQuietHoursEnd(undefined, 0, Date.UTC(2026, 8, 5, 23, 0)),
      8 * 60 * 60 * 1000);
});

test("a held push uses the recipient's own offset, not the server's", () => {
  // 01:00 UTC is 04:00 in Bahrain (+180): 3 hours left until 07:00.
  assert.equal(
      msUntilQuietHoursEnd(undefined, 180, Date.UTC(2026, 8, 5, 1, 0)),
      3 * 60 * 60 * 1000);
});

test("right at the boundary minute waits a full day, never zero", () => {
  const afternoon =
    {quietHoursEnabled: true, quietHoursStart: "13:0", quietHoursEnd: "14:0"};
  assert.equal(
      msUntilQuietHoursEnd(afternoon, 0, Date.UTC(2026, 8, 5, 14, 0)),
      24 * 60 * 60 * 1000);
});

test("a malformed end time waits a full day rather than never or now", () => {
  const bad = {quietHoursEnabled: true, quietHoursStart: "22:0",
    quietHoursEnd: "late"};
  assert.equal(msUntilQuietHoursEnd(bad, 0, Date.UTC(2026, 8, 5, 4)),
      24 * 60 * 60 * 1000);
});

test("an unknown kind is charged to the heads-up slot", () => {
  const r = claimQuota(undefined, "2026-09-05", "mystery");
  assert.equal(r.allowed, true);
  assert.deepEqual(r.next,
      {date: "2026-09-05", info: 1, nudge: 0, celebrate: 0});
});

// ── Rule 2 and 3: the day a push is about (2026-09-24) ──────────────────

test("a quota already counting a later day refuses an older push, untouched",
    () => {
      // نور on 24 Sep: a push about the 23rd must not reset the 24th.
      const q = {date: "2026-09-24", info: 0, nudge: 1, celebrate: 0};
      const r = claimQuota(q, "2026-09-23", "nudge");
      assert.equal(r.allowed, false);
      assert.deepEqual(r.next, q);
      assert.equal(claimQuota(q, "2026-09-23", "celebrate").allowed, false);
    });

test("a last one or first to finish is never sent about a past day", () => {
  for (const event of ["lastOne", "firstToday"]) {
    const plan = roomPushPlan(
        {event, dayKey: "2026-09-23", readerToday: "2026-09-24"});
    assert.equal(plan.action, "drop", event);
    assert.equal(plan.reason, "past-day");
  }
});

test("a perfect day about yesterday is never sent either", () => {
  // Aziz, 2026-09-24: «الكل خلّص عاداته أمس.» the next morning gives the
  // reader nothing. Every notification has to be useful and kind.
  const plan = roomPushPlan(
      {event: "perfect", dayKey: "2026-09-23", readerToday: "2026-09-24"});
  assert.equal(plan.action, "drop");
  assert.equal(plan.reason, "past-day");
});

test("a new habit still reaches them the next morning, never later", () => {
  const morning = roomPushPlan(
      {event: "habitAdded", dayKey: "2026-09-23", readerToday: "2026-09-24"});
  assert.equal(morning.action, "send");
  assert.equal(morning.quotaDay, "2026-09-23",
      "it counts against the day it was added");
  const late = roomPushPlan(
      {event: "habitAdded", dayKey: "2026-09-22", readerToday: "2026-09-24"});
  assert.equal(late.action, "drop");
  assert.equal(late.reason, "too-old");
});

test("quiet hours: a hold that would land on a later day drops a last one",
    () => {
      // 22:39 on the 23rd, quiet until 07:00 on the 24th.
      const lastOne = roomPushPlan({event: "lastOne", dayKey: "2026-09-23",
        readerToday: "2026-09-23", quiet: true, heldUntilDay: "2026-09-24"});
      assert.equal(lastOne.action, "drop");
      assert.equal(lastOne.reason, "quiet-past-its-day");
      // A perfect day in the same spot is dropped too; only a new habit
      // waits for the morning.
      const perfect = roomPushPlan({event: "perfect", dayKey: "2026-09-23",
        readerToday: "2026-09-23", quiet: true, heldUntilDay: "2026-09-24"});
      assert.equal(perfect.action, "drop");
      const added = roomPushPlan({event: "habitAdded", dayKey: "2026-09-23",
        readerToday: "2026-09-23", quiet: true, heldUntilDay: "2026-09-24"});
      assert.equal(added.action, "hold");
      // And a last one whose quiet hours end the same day is held too.
      const nap = roomPushPlan({event: "lastOne", dayKey: "2026-09-23",
        readerToday: "2026-09-23", quiet: true, heldUntilDay: "2026-09-23"});
      assert.equal(nap.action, "hold");
    });

test("a reader whose clock is behind the finisher's is on their own day",
    () => {
      // Los Angeles on the 4th, the Bahrain finisher on the 5th.
      const plan = roomPushPlan(
          {event: "lastOne", dayKey: "2026-09-05", readerToday: "2026-09-04"});
      assert.equal(plan.action, "send");
      assert.equal(plan.yesterday, false);
      assert.equal(plan.quotaDay, "2026-09-04");
    });

test("a push on its own day is just sent, counted on that day", () => {
  const plan = roomPushPlan(
      {event: "lastOne", dayKey: "2026-09-24", readerToday: "2026-09-24"});
  assert.deepEqual(plan, {action: "send", yesterday: false,
    quotaDay: "2026-09-24", reason: undefined});
});

test("a held push lands two minutes after quiet hours end", () => {
  const now = Date.UTC(2026, 8, 23, 19, 39); // 22:39 in Bahrain
  const at = heldUntilMs(undefined, 180, now);
  assert.equal(at, Date.UTC(2026, 8, 24, 4, 0) + HOLD_BUFFER_MS);
  assert.equal(localDayKey(180, at), "2026-09-24");
});

test("a day key is the person's own calendar day", () => {
  const t = Date.UTC(2026, 8, 23, 21, 30); // 00:30 on the 24th in Bahrain
  assert.equal(localDayKey(180, t), "2026-09-24");
  assert.equal(localDayKey(undefined, t), "2026-09-23", "no offset is UTC");
  assert.equal(shiftDay("2026-09-01", -1), "2026-08-31");
  assert.equal(shiftDay("2026-12-31", 1), "2027-01-01");
});

// ── One person, one banner (2026-09-24) ─────────────────────────────────

test("a token a week behind the account's freshest is stale", () => {
  const day = 24 * 60 * 60 * 1000;
  const today = Date.UTC(2026, 8, 24, 2, 38);
  // نور: one token from today, one not refreshed since 13 Sep.
  const {live, stale} = liveTokens([
    {id: "dGKDax2i", updatedAtMs: today},
    {id: "fF8Zm2Ui", updatedAtMs: Date.UTC(2026, 8, 13, 2, 27)},
  ]);
  assert.deepEqual(live.map((t) => t.id), ["dGKDax2i"]);
  assert.deepEqual(stale.map((t) => t.id), ["fF8Zm2Ui"]);
  // Two devices both in use this week both stay.
  const both = liveTokens([
    {id: "phone", updatedAtMs: today},
    {id: "ipad", updatedAtMs: today - 6 * day},
  ]);
  assert.equal(both.live.length, 2);
  assert.equal(STALE_TOKEN_GAP_MS, 7 * day);
});

test("an account using none of its devices lately keeps them all", () => {
  // Relative to the freshest, never to now: a room push may be what brings
  // someone back, so a quiet account is not pruned.
  const old = Date.UTC(2026, 5, 1);
  const {live, stale} = liveTokens([{id: "a", updatedAtMs: old}]);
  assert.equal(live.length, 1);
  assert.equal(stale.length, 0);
  const none = liveTokens([
    {id: "a", updatedAtMs: null},
    {id: "b", updatedAtMs: undefined},
  ]);
  assert.equal(none.live.length, 2, "no dates means nothing to compare");
});

// Page item 6 (Aziz, 2026-09-24): the admin's message to everyone, held for
// someone's quiet hours instead of skipped. index.js deliverHeldBroadcast asks
// this when the hold ends; test/held_broadcast.test.js runs the handler.
test("a held message goes out when quiet hours end, decided afresh", () => {
  const sent = Date.UTC(2026, 8, 24, 20, 30); // 23:30 in Bahrain
  const sevenOhTwo = Date.UTC(2026, 8, 25, 4, 2);
  const at = (nowMs, settings) => heldBroadcastPlan({
    sentAtMs: sent, settings, tzOffsetMinutes: 180, nowMs,
  });
  assert.deepEqual(at(sevenOhTwo), {action: "send"});
  assert.deepEqual(at(sevenOhTwo, {masterEnabled: false}),
      {action: "drop", reason: "master-off"});
  // Their window moved to end at 09:00 after it was held: not chased.
  assert.deepEqual(
      at(sevenOhTwo, {
        quietHoursEnabled: true, quietHoursStart: "22:0", quietHoursEnd: "9:0",
      }),
      {action: "drop", reason: "still-quiet"});
});

test("a held message never lands a day late", () => {
  // Noon in Bahrain, so a day later is noon too, clear of quiet hours.
  const sent = Date.UTC(2026, 8, 24, 9, 0);
  const plan = (nowMs) => heldBroadcastPlan({
    sentAtMs: sent, settings: undefined, tzOffsetMinutes: 180, nowMs,
  });
  assert.equal(HELD_BROADCAST_MAX_MS, 24 * 60 * 60 * 1000);
  assert.equal(plan(sent + HELD_BROADCAST_MAX_MS).action, "send");
  assert.deepEqual(plan(sent + HELD_BROADCAST_MAX_MS + 1),
      {action: "drop", reason: "too-late"});
  assert.deepEqual(
      heldBroadcastPlan({sentAtMs: null, tzOffsetMinutes: 180, nowMs: sent}),
      {action: "drop", reason: "too-late"});
});
