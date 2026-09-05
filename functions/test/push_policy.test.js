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
  claimQuota,
  isQuietAtLocalMinute,
  isQuietHoursNow,
  localMinutes,
  pushKindFor,
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

test("the four pushes split into a heads-up, a nudge and a celebration", () => {
  assert.equal(pushKindFor("firstToday"), "info");
  assert.equal(pushKindFor("perfect"), "celebrate");
  assert.equal(pushKindFor("lastOne"), "nudge");
  assert.equal(pushKindFor("eveningReminder"), "nudge");
  assert.equal(pushKindFor("somethingNew"), "info",
      "an event nobody classified gets the plain heads-up slot");
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

test("an unknown kind is charged to the heads-up slot", () => {
  const r = claimQuota(undefined, "2026-09-05", "mystery");
  assert.equal(r.allowed, true);
  assert.deepEqual(r.next,
      {date: "2026-09-05", info: 1, nudge: 0, celebrate: 0});
});
