/**
 * The entitlement mirror's rules, written against the ways it can pay the
 * wrong person or stop paying the right one.
 *
 * The mirror exists because Flutter web has no RevenueCat SDK, so someone
 * who bought Premium on their iPhone read as free on the web app. Every
 * case here is a way that mirror could have handed out Premium for free, or
 * revoked Premium somebody paid for. Money, so each is pinned rather than
 * reasoned about once.
 */

const test = require("node:test");
const assert = require("node:assert");
const {
  ENTITLEMENT_ID,
  entitlementFrom,
  isProduction,
  isRealUid,
  shouldApply,
  targetsFor,
} = require("../revenuecat_webhook");

const NOW = 1788000000000; // A fixed "now", so nothing here depends on the clock.
const UID_A = "5rLsgWgriLa7qaRDeZ3wdPfHgQl2"; // Aziz's real uid shape.
const UID_B = "Z0FndO3iFYgrzWzkwJ4QlOPBLPr2";

/** A production RENEWAL granting Premium until [expiresMs]. */
function ev(over) {
  return Object.assign({
    id: "evt-1",
    type: "RENEWAL",
    environment: "PRODUCTION",
    app_user_id: UID_A,
    entitlement_ids: [ENTITLEMENT_ID],
    event_timestamp_ms: NOW,
    expiration_at_ms: NOW + 86400000,
  }, over);
}

test("a real uid is accepted and an anonymous RevenueCat id is not", () => {
  assert.equal(isRealUid(UID_A), true);
  // A guest who buys before signing in. There is no account to mirror onto.
  assert.equal(isRealUid("$RCAnonymousID:9f8e7d"), false);
  assert.equal(isRealUid(""), false);
  assert.equal(isRealUid(null), false);
  // Never let an id escape its document: these would be a path traversal.
  assert.equal(isRealUid("../admin"), false);
  assert.equal(isRealUid("a/b"), false);
  assert.equal(isRealUid("__proto__"), false);
});

test("only PRODUCTION events are mirrored", () => {
  assert.equal(isProduction(ev()), true);
  // Every TestFlight tester can make one of these.
  assert.equal(isProduction(ev({environment: "SANDBOX"})), false);
  // The dashboard's own "send test webhook" button.
  assert.equal(isProduction({type: "TEST"}), false);
  assert.equal(isProduction({}), false);
});

test("a lifetime purchase has no expiry and stays active", () => {
  const v = entitlementFrom(ev({expiration_at_ms: null}), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: null});
});

test("CANCELLATION keeps the time already paid for", () => {
  // Cancelling means "do not renew", not "end it now". Treating it as off
  // would cut short a period the person has already been charged for.
  const v = entitlementFrom(
      ev({type: "CANCELLATION", expiration_at_ms: NOW + 86400000}), NOW);
  assert.equal(v.active, true);
});

test("a REFUND revokes immediately, whatever the expiry says", () => {
  const v = entitlementFrom(
      ev({type: "REFUND", expiration_at_ms: NOW + 999999999}), NOW);
  assert.deepEqual(v, {active: false, expiresAtMs: null});
});

test("an expiry in the past is not active", () => {
  const v = entitlementFrom(ev({expiration_at_ms: NOW - 1}), NOW);
  assert.equal(v.active, false);
});

test("an event about some other entitlement leaves the mirror alone", () => {
  assert.equal(entitlementFrom(ev({entitlement_ids: ["Something Else"]}), NOW),
      null);
});

test("TRANSFER revokes the account that LOST the purchase", () => {
  // The exploit this closes: buy growdaily_lifetime once, move it to a
  // fresh account, repeat. RevenueCat sends ONE event, whose app_user_id is
  // the account RECEIVING it, so writing only that id left every previous
  // account reading Premium forever.
  const targets = targetsFor(ev({
    type: "TRANSFER",
    app_user_id: UID_B,
    transferred_from: [UID_A],
    transferred_to: [UID_B],
    expiration_at_ms: null,
  }), NOW);
  const loser = targets.find((t) => t.uid === UID_A);
  const gainer = targets.find((t) => t.uid === UID_B);
  assert.ok(loser, "the losing account must be written");
  assert.equal(loser.active, false);
  assert.ok(gainer);
  assert.equal(gainer.active, true);
});

test("an anonymous buyer produces no write at all", () => {
  assert.deepEqual(targetsFor(ev({app_user_id: "$RCAnonymousID:1"}), NOW), []);
});

test("a duplicate delivery of the same event is a no-op", () => {
  const e = ev();
  const stored = {premiumEventId: e.id, premiumEventMs: e.event_timestamp_ms};
  assert.equal(shouldApply(e, stored), false);
});

test("a retried OLD event cannot undo a newer one", () => {
  // RevenueCat retries until it gets a 2xx, so a stale CANCELLATION can
  // land after the RENEWAL that superseded it.
  const stale = ev({id: "old", type: "CANCELLATION",
    event_timestamp_ms: NOW - 60000});
  const stored = {premiumEventId: "new", premiumEventMs: NOW};
  assert.equal(shouldApply(stale, stored), false);
});

test("a newer event applies over an older stored one", () => {
  const fresh = ev({id: "new2", event_timestamp_ms: NOW + 1000});
  assert.equal(shouldApply(fresh, {premiumEventId: "a", premiumEventMs: NOW}),
      true);
});

test("an event with no timestamp is refused rather than guessed at", () => {
  assert.equal(shouldApply(ev({event_timestamp_ms: null}), null), false);
});

test("two distinct events stamped the same millisecond both apply", () => {
  const second = ev({id: "evt-2"});
  assert.equal(shouldApply(second,
      {premiumEventId: "evt-1", premiumEventMs: NOW}), true);
});
