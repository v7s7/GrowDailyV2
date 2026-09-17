/**
 * Pure entitlement logic for the RevenueCat webhook, split out so it is
 * unit-testable without Firestore, Express or a deploy.
 *
 * WHY A MIRROR EXISTS AT ALL. RevenueCat is and stays the source of truth:
 * iOS and Android read entitlement straight from its SDK, which verifies
 * receipts with Apple and Google server-side. Flutter web has no RevenueCat
 * SDK, so purchase_service.dart returns null on web (`if (kIsWeb) return
 * null;`) and a person who bought Premium on their iPhone reads as FREE on
 * grow-daily-app.web.app. This mirror is the ONLY way a non-SDK client can
 * learn the answer, and it is written exclusively by the webhook below,
 * never by a client: firestore.rules forbids the fields outright.
 *
 * TRUST DIRECTION. The mirror is a cache of RevenueCat's answer, not a
 * second authority. iOS and Android must keep asking the SDK, because it is
 * fresher (a purchase is live before any webhook lands), works offline from
 * its own cache, and cannot be affected by a webhook outage.
 */

"use strict";

/**
 * The entitlement RevenueCat grants for Premium. Must match
 * PurchaseService.entitlementId in the Dart app exactly.
 */
const ENTITLEMENT_ID = "Grow Daily Premium";

/**
 * The products that grant [ENTITLEMENT_ID], for the one case the entitlement
 * alone cannot answer (see [productionPurchaseVerdict]). The monthly is a
 * PREFIX because RevenueCat's v1 record can key a Play subscription with its
 * base plan appended ("growdaily_monthly:monthly-autorenew").
 */
const LIFETIME_PRODUCT_ID = "growdaily_lifetime";
const MONTHLY_PRODUCT_PREFIX = "growdaily_monthly";

/**
 * A RevenueCat app_user_id we are willing to write a mirror for.
 *
 * PurchaseService.logIn(uid) binds the App User ID to the Firebase uid, so a
 * signed-in person's events carry that uid. A person who has NOT signed in
 * gets a RevenueCat-generated anonymous id of the form
 * `$RCAnonymousID:1a2b3c...`, which belongs to no account and must never be
 * written anywhere: there is no user doc for it, and treating the literal
 * string as a document id would create a junk doc that nothing ever reads.
 *
 * Firebase uids are 28 chars of [A-Za-z0-9] in practice, but the only
 * property this needs to guarantee is that the value is a safe single path
 * segment, so it is checked as one rather than pinned to a length.
 */
function isRealUid(appUserId) {
  if (typeof appUserId !== "string") return false;
  if (appUserId.length === 0 || appUserId.length > 128) return false;
  if (appUserId.startsWith("$RCAnonymousID:")) return false;
  // No path separators, no relative segments, no Firestore-illegal chars.
  if (appUserId.includes("/") || appUserId.includes("__")) return false;
  return /^[A-Za-z0-9_-]+$/.test(appUserId);
}

/**
 * Whether this event describes a REAL purchase.
 *
 * RevenueCat sends SANDBOX events for App Store sandbox testers, TestFlight
 * builds and Play's licence testers, in exactly the same shape as a real
 * one. Mirroring those writes a permanent production entitlement for anyone
 * who can run a sandbox purchase, which on TestFlight is anybody Aziz has
 * ever invited. RevenueCat also fires a TEST event from the dashboard's own
 * "send test webhook" button, carrying a made-up app_user_id.
 *
 * Only PRODUCTION is mirrored. The mobile SDKs are unaffected either way:
 * they read entitlement from RevenueCat directly and sandbox testers keep
 * working there, which is the point of sandbox.
 */
function isProduction(event) {
  return event && event.environment === "PRODUCTION";
}


/**
 * Every account whose mirror this event may have changed.
 *
 * WHY THE EVENT IS ONLY A DOORBELL. The mirror used to be computed from the
 * event's own `type`, `entitlement_ids` and `expiration_at_ms`. Those fields
 * describe ONE PRODUCT'S transaction, not the customer's entitlement, and
 * Premium has two products behind it (growdaily_monthly and
 * growdaily_lifetime). A lifetime owner whose old monthly ran out got an
 * EXPIRATION for the monthly and was mirrored as free for good, and every
 * RENEWAL or CANCELLATION of that monthly overwrote the lifetime's open
 * expiry with a month-end date the web client then enforced. RevenueCat's
 * own guidance is to call GET /subscribers after ANY webhook, because the
 * customer record already folds every product, refund, transfer and grace
 * period into one answer. So the event now says only WHO to re-read.
 *
 * TRANSFER is the case that needs this most. Its real payload carries no
 * `app_user_id`, no `entitlement_ids` and no expiry (only
 * `transferred_from` / `transferred_to`), so the old per-event verdict could
 * never grant the receiving account at all, and it revoked the losing
 * account blindly even when that account still held a purchase from a
 * different store account. Re-reading both sides gets both right.
 *
 * `original_app_user_id` and `aliases` are included because RevenueCat's
 * docs say to look users up by both: a guest who bought before signing in
 * is ONE RevenueCat customer under two ids, and `app_user_id` is only the
 * last one seen. Every id here resolves to the same customer record, so
 * re-reading each can only write the same answer RevenueCat gives the SDK.
 * Anonymous ids fall out through [isRealUid], as before.
 */
function uidsToRefresh(event) {
  const ids = [];
  if (String(event.type || "") === "TRANSFER") {
    for (const list of [event.transferred_from, event.transferred_to]) {
      if (Array.isArray(list)) ids.push(...list);
    }
  } else {
    ids.push(event.app_user_id, event.original_app_user_id);
    if (Array.isArray(event.aliases)) ids.push(...event.aliases);
  }
  return [...new Set(ids.filter(isRealUid))];
}

/** An ISO 8601 string as epoch ms, or null when absent or unparseable. */
function isoMs(value) {
  if (typeof value !== "string") return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Whether the purchase RevenueCat says backs Premium is a sandbox one.
 *
 * The event gate ([isProduction]) is not enough on its own any more. By
 * default RevenueCat lets sandbox purchases grant entitlements ("Sandbox
 * Testing Access: Anybody"), and the customer record mixes sandbox and
 * production purchases, so a TestFlight tester whose real uid also gets
 * one production event would otherwise have a sandbox lifetime mirrored as
 * permanent web Premium. That is exactly the hole isProduction was added to
 * close, re-opened one level down.
 *
 * The entitlement names only the purchase with the furthest-out expiry, so
 * this looks that product up. A lifetime counts as sandbox only when EVERY
 * purchase of it is sandbox or refunded: one real, unrefunded purchase among
 * test ones is real, and a refunded one backs nothing.
 * A product that cannot be found is trusted, which keeps the old trust
 * direction (RevenueCat's answer wins) rather than revoking on a lookup gap;
 * RevenueCat documents that product_identifier can briefly be unavailable.
 */
function isSandboxBacked(subscriber, productId) {
  if (typeof productId !== "string" || productId === "") return false;
  const subs = subscriber.subscriptions || {};
  const sub = subs[productId];
  if (sub && typeof sub === "object") return sub.is_sandbox === true;
  const nons = subscriber.non_subscriptions || {};
  const non = nons[productId];
  if (Array.isArray(non) && non.length > 0) {
    return non.every((p) => p && (p.is_sandbox === true || !!p.refunded_at));
  }
  return false;
}

/**
 * The verdict from the customer's PRODUCTION purchases alone, for when the
 * purchase the entitlement names is a sandbox one.
 *
 * The entitlement reports only the purchase with the furthest-out expiry,
 * and a sandbox lifetime's null expiry beats everything, so on its own it
 * would hide a real paid purchase behind a test one: a TestFlight tester (or
 * Aziz) who later pays for real would read free on web on every event
 * (review, 2026-09-17). So look past it: any real, unrefunded lifetime is
 * Premium with no expiry; otherwise the real monthly with the latest end
 * (the later of expiry and grace) decides; otherwise free.
 */
function productionPurchaseVerdict(subscriber, nowMs, checkedAtMs) {
  const off = {active: false, expiresAtMs: null, checkedAtMs};
  const nons = subscriber.non_subscriptions || {};
  const lifetime = nons[LIFETIME_PRODUCT_ID];
  if (Array.isArray(lifetime) &&
      lifetime.some((p) => p && p.is_sandbox !== true && !p.refunded_at)) {
    return {active: true, expiresAtMs: null, checkedAtMs};
  }
  let end = null;
  const subs = subscriber.subscriptions || {};
  for (const [id, sub] of Object.entries(subs)) {
    if (!id.startsWith(MONTHLY_PRODUCT_PREFIX)) continue;
    if (!sub || typeof sub !== "object") continue;
    if (sub.is_sandbox === true || sub.refunded_at) continue;
    const expires = isoMs(sub.expires_date);
    if (expires === null) continue;
    const grace = isoMs(sub.grace_period_expires_date);
    const subEnd = grace !== null && grace > expires ? grace : expires;
    if (end === null || subEnd > end) end = subEnd;
  }
  if (end === null) return off;
  return {active: end > nowMs, expiresAtMs: end, checkedAtMs};
}

/**
 * The mirror's verdict from a GET /v1/subscribers response body.
 *
 * `subscriber.entitlements` lists expired entitlements too, and when several
 * purchases grant one entitlement it reports the one with the furthest-out
 * expiry. So a lifetime owner reads `expires_date: null` no matter what
 * their old monthly did, and a refunded or transferred purchase simply
 * stops being the answer. Nothing here looks at event types.
 *
 * Active means no expiry (lifetime), or the later of `expires_date` and
 * `grace_period_expires_date` is still ahead. Grace counts because the SDK
 * keeps Premium through a store's billing grace period; mirroring the
 * period end instead would drop a web user while their phone still reads
 * Premium.
 * That later date is what gets stored, since the web client re-checks it.
 *
 * Returns null for a body it cannot read, so the caller answers 500 and
 * RevenueCat retries, rather than writing "free" from a response it did not
 * understand. `checkedAtMs` is RevenueCat's own `request_date_ms`, the
 * instant the answer was true, used to order concurrent writes.
 */
function premiumFromCustomerInfo(body, nowMs) {
  if (!body || typeof body !== "object") return null;
  const subscriber = body.subscriber;
  const checkedAtMs = body.request_date_ms;
  if (!subscriber || typeof subscriber !== "object") return null;
  if (typeof checkedAtMs !== "number") return null;
  const off = {active: false, expiresAtMs: null, checkedAtMs};

  const ents = subscriber.entitlements || {};
  const ent = ents[ENTITLEMENT_ID];
  if (!ent || typeof ent !== "object") return off;
  if (isSandboxBacked(subscriber, ent.product_identifier)) {
    return productionPurchaseVerdict(subscriber, nowMs, checkedAtMs);
  }

  if (ent.expires_date === null) {
    return {active: true, expiresAtMs: null, checkedAtMs};
  }
  const expires = isoMs(ent.expires_date);
  if (expires === null) return null; // Missing or garbled: refuse.
  const grace = isoMs(ent.grace_period_expires_date);
  const end = grace !== null && grace > expires ? grace : expires;
  return {active: end > nowMs, expiresAtMs: end, checkedAtMs};
}

/**
 * Whether a customer-record snapshot taken at [checkedAtMs] may overwrite
 * what is stored.
 *
 * Re-reading makes a retried or out-of-order event harmless by itself: it
 * fetches today's truth, not the truth of when it fired. What can still go
 * wrong is two deliveries racing, where the one that READ first COMMITS
 * last. Comparing RevenueCat's `request_date_ms` stops that older snapshot
 * landing on a newer one. Equal instants are allowed through: both
 * snapshots describe the same moment, so writing either is the same write.
 *
 * Stored in `premiumEventMs` so firestore.rules needs no change: that field
 * is already server-only, and must stay so, because a client that wrote a
 * far-future value would freeze its own mirror against any later refund.
 */
function shouldWrite(checkedAtMs, stored) {
  if (typeof checkedAtMs !== "number") return false;
  const seen = stored && typeof stored.premiumEventMs === "number" ?
    stored.premiumEventMs : null;
  return seen === null || checkedAtMs >= seen;
}

module.exports = {
  ENTITLEMENT_ID,
  isProduction,
  isRealUid,
  premiumFromCustomerInfo,
  shouldWrite,
  uidsToRefresh,
};
