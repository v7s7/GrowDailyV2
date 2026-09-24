/**
 * The entitlement mirror's rules, written against the ways it can pay the
 * wrong person or stop paying the right one.
 *
 * The mirror exists because Flutter web has no RevenueCat SDK, so someone
 * who bought Premium on their iPhone read as free on the web app. Every
 * case here is a way that mirror could have handed out Premium for free, or
 * revoked Premium somebody paid for. Money, so each is pinned rather than
 * reasoned about once.
 *
 * Event payloads below follow RevenueCat's documented shapes (Event Types
 * and Fields, Sample Events), NOT a convenient superset: the old TRANSFER
 * test passed on a payload with app_user_id and entitlement_ids that
 * RevenueCat never sends, and so never caught that a real transfer granted
 * the receiving account nothing.
 */

const test = require("node:test");
const assert = require("node:assert");
const {
  ENTITLEMENT_ID,
  LIFETIME_PRODUCT_IDS,
  isLifetimeProduct,
  isProduction,
  isRealUid,
  premiumFromCustomerInfo,
  shouldWrite,
  uidsToRefresh,
} = require("../revenuecat_webhook");

const NOW = 1788000000000; // A fixed "now", so nothing here depends on the clock.
const DAY = 86400000;
const UID_A = "5rLsgWgriLa7qaRDeZ3wdPfHgQl2"; // Aziz's real uid shape.
const UID_B = "Z0FndO3iFYgrzWzkwJ4QlOPBLPr2";
const iso = (ms) => new Date(ms).toISOString();

/** A production lifecycle event for UID_A. */
function ev(over) {
  return Object.assign({
    id: "evt-1",
    type: "RENEWAL",
    environment: "PRODUCTION",
    app_user_id: UID_A,
    original_app_user_id: UID_A,
    aliases: [UID_A],
    entitlement_ids: [ENTITLEMENT_ID],
    event_timestamp_ms: NOW,
    expiration_at_ms: NOW + DAY,
  }, over);
}

/** A GET /v1/subscribers body with [entitlement] under Premium, if given. */
function info({entitlement, subscriptions = {}, nonSubscriptions = {}} = {}) {
  return {
    request_date_ms: NOW,
    subscriber: {
      entitlements: entitlement ? {[ENTITLEMENT_ID]: entitlement} : {},
      subscriptions,
      non_subscriptions: nonSubscriptions,
    },
  };
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

test("an ordinary event re-reads its own account, once", () => {
  assert.deepEqual(uidsToRefresh(ev()), [UID_A]);
});

test("the event type never decides who is re-read", () => {
  // EXPIRATION, a refund (CANCELLATION + CUSTOMER_SUPPORT) and a RENEWAL
  // all just ring the doorbell for the same account.
  for (const over of [
    {type: "EXPIRATION", expiration_reason: "UNSUBSCRIBE"},
    {type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", price: -29.99},
    {type: "PRODUCT_CHANGE", new_product_id: "growdaily_lifetime"},
    {type: "SOMETHING_REVENUECAT_ADDS_LATER", entitlement_ids: null},
  ]) {
    assert.deepEqual(uidsToRefresh(ev(over)), [UID_A], over.type);
  }
});

test("a guest's purchase reaches the real uid through aliases", () => {
  // app_user_id is only the LAST id seen; logIn merged the guest into A.
  const e = ev({app_user_id: "$RCAnonymousID:1",
    original_app_user_id: "$RCAnonymousID:1",
    aliases: ["$RCAnonymousID:1", UID_A]});
  assert.deepEqual(uidsToRefresh(e), [UID_A]);
});

test("an anonymous buyer produces no re-read at all", () => {
  assert.deepEqual(uidsToRefresh(ev({app_user_id: "$RCAnonymousID:1",
    original_app_user_id: "$RCAnonymousID:1",
    aliases: ["$RCAnonymousID:1"]})), []);
});

test("a real TRANSFER re-reads the losing AND the gaining account", () => {
  // RevenueCat's documented TRANSFER: no app_user_id, no entitlement_ids,
  // no expiry. The old verdict revoked A and never granted B.
  const transfer = {
    id: "CD489E0E", type: "TRANSFER", environment: "PRODUCTION",
    event_timestamp_ms: NOW, store: "APP_STORE",
    transferred_from: [UID_A, "$RCAnonymousID:x"], transferred_to: [UID_B],
  };
  assert.deepEqual(uidsToRefresh(transfer).sort(), [UID_A, UID_B].sort());
});

test("a lifetime owner whose monthly expired stays Premium", () => {
  // The bug this rewrite exists for. RevenueCat reports the purchase with
  // the furthest-out expiry, so the lifetime's null wins over the dead
  // monthly, whatever EXPIRATION the webhook just delivered.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    subscriptions: {growdaily_monthly: {is_sandbox: false,
      expires_date: iso(NOW - DAY), refunded_at: null}},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: false}]},
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: null, checkedAtMs: NOW});
});

test("a monthly in its paid period is active until its expiry", () => {
  const exp = NOW + 10 * DAY;
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: iso(exp), grace_period_expires_date: null,
      product_identifier: "growdaily_monthly"},
    subscriptions: {growdaily_monthly: {is_sandbox: false}},
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: exp, checkedAtMs: NOW});
});

test("a lapsed or refunded purchase is not active", () => {
  // Both read the same way on the record: an expiry in the past.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: iso(NOW - 1000),
      grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: false}]},
  }), NOW);
  assert.equal(v.active, false);
});

test("no Premium entitlement on the record at all reads as free", () => {
  assert.deepEqual(premiumFromCustomerInfo(info(), NOW),
      {active: false, expiresAtMs: null, checkedAtMs: NOW});
});

test("a billing grace period keeps Premium, and its end is stored", () => {
  // The phone keeps Premium through grace; the web must not drop it first.
  const graceEnd = NOW + 6 * DAY;
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: iso(NOW - DAY),
      grace_period_expires_date: iso(graceEnd),
      product_identifier: "growdaily_monthly"},
    subscriptions: {growdaily_monthly: {is_sandbox: false}},
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: graceEnd, checkedAtMs: NOW});
});

test("a sandbox-backed entitlement is never mirrored as Premium", () => {
  // A TestFlight tester's sandbox lifetime, on a real uid that just got one
  // production event. RevenueCat grants it by default; the web must not.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: true}]},
  }), NOW);
  assert.equal(v.active, false);
  const monthly = premiumFromCustomerInfo(info({
    entitlement: {expires_date: iso(NOW + DAY),
      product_identifier: "growdaily_monthly"},
    subscriptions: {growdaily_monthly: {is_sandbox: true}},
  }), NOW);
  assert.equal(monthly.active, false);
});

test("one real lifetime purchase among sandbox ones is real", () => {
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [
      {is_sandbox: true}, {is_sandbox: false}]},
  }), NOW);
  assert.equal(v.active, true);
});

test("a product missing from the purchase lists is trusted, not revoked", () => {
  // RevenueCat documents product_identifier as briefly unavailable at times.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, product_identifier: "growdaily_lifetime"},
  }), NOW);
  assert.equal(v.active, true);
});

test("a response it cannot read is refused, so RevenueCat retries", () => {
  assert.equal(premiumFromCustomerInfo(null, NOW), null);
  assert.equal(premiumFromCustomerInfo({subscriber: {}}, NOW), null);
  assert.equal(premiumFromCustomerInfo({request_date_ms: NOW}, NOW), null);
  // An expiry that is neither null nor a date must not quietly mean "free".
  assert.equal(premiumFromCustomerInfo(info({
    entitlement: {expires_date: "soon", product_identifier: "x"}}), NOW), null);
  assert.equal(premiumFromCustomerInfo(info({
    entitlement: {product_identifier: "x"}}), NOW), null);
});

test("an older snapshot cannot overwrite a newer one", () => {
  // Two deliveries racing: the one that read first commits last.
  assert.equal(shouldWrite(NOW - 1, {premiumEventMs: NOW}), false);
});

test("a newer or same-instant snapshot writes", () => {
  assert.equal(shouldWrite(NOW + 1, {premiumEventMs: NOW}), true);
  assert.equal(shouldWrite(NOW, {premiumEventMs: NOW}), true);
  assert.equal(shouldWrite(NOW, {}), true);
  assert.equal(shouldWrite(NOW, undefined), true);
});

test("a snapshot with no timestamp is refused rather than guessed at", () => {
  assert.equal(shouldWrite(null, {}), false);
  assert.equal(shouldWrite(undefined, undefined), false);
});

test("a sandbox lifetime never hides a real monthly", () => {
  // The entitlement names the sandbox lifetime (null expiry wins), but the
  // same account pays for a production monthly. Review, 2026-09-17.
  const end = NOW + 10 * 24 * 3600 * 1000;
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: true}]},
    subscriptions: {"growdaily_monthly:monthly-autorenew": {is_sandbox: false,
      expires_date: new Date(end).toISOString(),
      grace_period_expires_date: null}},
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: end, checkedAtMs: NOW});
});

test("a sandbox monthly never hides a real lifetime", () => {
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: new Date(NOW + 1000).toISOString(),
      grace_period_expires_date: null, product_identifier: "growdaily_monthly"},
    subscriptions: {growdaily_monthly: {is_sandbox: true}},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: false}]},
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: null, checkedAtMs: NOW});
});

test("sandbox only, or a real purchase that was refunded or lapsed, is free", () => {
  const sandboxOnly = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: true}]},
  }), NOW);
  assert.equal(sandboxOnly.active, false);
  const refundedOrLapsed = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {growdaily_lifetime: [{is_sandbox: true},
      {is_sandbox: false, refunded_at: new Date(NOW - 1000).toISOString()}]},
    subscriptions: {growdaily_monthly: {is_sandbox: false,
      expires_date: new Date(NOW - 1000).toISOString()}},
  }), NOW);
  assert.equal(refundedOrLapsed.active, false);
});

test("both lifetimes are lifetimes, with or without a Play suffix", () => {
  // 2026-09-22: the welcome-window and sale price is its own product.
  assert.deepEqual([...LIFETIME_PRODUCT_IDS],
      ["growdaily_lifetime", "growdaily_lifetime_offer"]);
  assert.equal(isLifetimeProduct("growdaily_lifetime"), true);
  assert.equal(isLifetimeProduct("growdaily_lifetime_offer"), true);
  assert.equal(isLifetimeProduct("growdaily_lifetime_offer:lifetime"), true);
  // Exact ids, not a prefix: nothing else that happens to start the same way.
  assert.equal(isLifetimeProduct("growdaily_lifetime_offer_2"), false);
  assert.equal(isLifetimeProduct("growdaily_lifetimes"), false);
  assert.equal(isLifetimeProduct("growdaily_monthly"), false);
  assert.equal(isLifetimeProduct(":growdaily_lifetime"), false);
  assert.equal(isLifetimeProduct(null), false);
});

test("a real offer lifetime behind a sandbox entitlement is Premium", () => {
  // A tester whose sandbox regular lifetime is what the entitlement names,
  // and who then bought the offer lifetime for real. The old verdict looked
  // up growdaily_lifetime alone, found only the sandbox one, and read free.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {
      growdaily_lifetime: [{is_sandbox: true}],
      growdaily_lifetime_offer: [{is_sandbox: false, refunded_at: null}],
    },
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: null, checkedAtMs: NOW});
});

test("a refunded offer lifetime behind a sandbox entitlement is free", () => {
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: null, grace_period_expires_date: null,
      product_identifier: "growdaily_lifetime"},
    nonSubscriptions: {
      growdaily_lifetime: [{is_sandbox: true}],
      growdaily_lifetime_offer: [
        {is_sandbox: false, refunded_at: iso(NOW - DAY)}],
    },
  }), NOW);
  assert.deepEqual(v, {active: false, expiresAtMs: null, checkedAtMs: NOW});
});

test("a Play-suffixed real offer lifetime beats a sandbox monthly", () => {
  // Play may key the one-time product with a suffix on the customer record.
  const v = premiumFromCustomerInfo(info({
    entitlement: {expires_date: iso(NOW + DAY),
      grace_period_expires_date: null, product_identifier: "growdaily_monthly"},
    subscriptions: {growdaily_monthly: {is_sandbox: true}},
    nonSubscriptions: {
      "growdaily_lifetime_offer:lifetime": [{is_sandbox: false}],
    },
  }), NOW);
  assert.deepEqual(v, {active: true, expiresAtMs: null, checkedAtMs: NOW});
});
