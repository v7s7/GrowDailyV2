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
 * Whether [event] says Premium is active, and until when.
 *
 * Read from `entitlement_ids` plus `expiration_at_ms` rather than from the
 * event TYPE, deliberately. Mapping types to a boolean means keeping a list
 * of every type RevenueCat has and every one it adds later, and getting a
 * single one wrong revokes a paying customer or pays a refunded one. The
 * two fields above are what the entitlement actually IS at the moment the
 * event fired, for every type.
 *
 * A lifetime purchase has no expiry: `expiration_at_ms` is null and the
 * entitlement stays active until a refund event says otherwise.
 *
 * CANCELLATION is deliberately NOT a revocation. Cancelling an
 * auto-renewing subscription means it will not renew; the person keeps
 * Premium until the period they already paid for runs out, which is exactly
 * what `expiration_at_ms` in the future encodes. Treating CANCELLATION as
 * "off" would cut short time someone has paid for.
 */
function entitlementFrom(event, nowMs) {
  const ids = Array.isArray(event.entitlement_ids) ? event.entitlement_ids :
    (typeof event.entitlement_id === "string" ? [event.entitlement_id] : []);
  const mentionsPremium = ids.includes(ENTITLEMENT_ID);
  const type = String(event.type || "");

  // A refund, a chargeback or a revoked family-share is an immediate off,
  // whatever the expiry says: the money went back.
  if (type === "REFUND" || type === "EXPIRATION") {
    return {active: false, expiresAtMs: null};
  }
  // TRANSFER moves the purchase to a different App User ID. The event is
  // delivered for the id LOSING it as well, and that person is no longer
  // entitled. RevenueCat sends the loser's id in `transferred_from`.
  if (type === "TRANSFER") {
    const from = Array.isArray(event.transferred_from) ?
      event.transferred_from : [];
    if (from.includes(event.app_user_id)) {
      return {active: false, expiresAtMs: null};
    }
  }
  if (!mentionsPremium) return null; // Not about Premium, leave the mirror.

  const expires = typeof event.expiration_at_ms === "number" ?
    event.expiration_at_ms : null;
  // null expiry = lifetime / non-expiring.
  if (expires === null) return {active: true, expiresAtMs: null};
  return {active: expires > nowMs, expiresAtMs: expires};
}

/**
 * Whether [event] should be applied over what is already stored.
 *
 * RevenueCat retries a webhook until it gets a 2xx, so the SAME event can
 * arrive several times, and a retry of an OLD event can land AFTER a newer
 * one. Without this, a retried CANCELLATION could revoke Premium that a
 * later RENEWAL had already restored.
 *
 * `event_timestamp_ms` is RevenueCat's own ordering key. Equal timestamps
 * are allowed through only when the id differs, so a genuine duplicate is a
 * no-op while two distinct events stamped the same millisecond both apply.
 */
function shouldApply(event, stored) {
  const ts = typeof event.event_timestamp_ms === "number" ?
    event.event_timestamp_ms : null;
  if (ts === null) return false; // Unorderable: refuse rather than guess.
  if (!stored) return true;
  const seenTs = typeof stored.premiumEventMs === "number" ?
    stored.premiumEventMs : null;
  if (seenTs === null) return true;
  if (ts > seenTs) return true;
  if (ts < seenTs) return false;
  return stored.premiumEventId !== event.id;
}

/**
 * Every account this event changes, and what it changes them to.
 *
 * Usually one: the event's own app_user_id. A TRANSFER is the exception and
 * the reason this function exists at all. RevenueCat moves a purchase
 * between App User IDs and sends ONE event, whose app_user_id is the
 * account RECEIVING it; the account losing it is named only in
 * `transferred_from`. Writing just app_user_id therefore granted the new
 * account and left the old account's mirror reading true forever.
 *
 * That is not a stale-cache annoyance, it is free Premium at scale: buy
 * growdaily_lifetime once, sign in as a fresh account to move the purchase,
 * and repeat. Every account walked away permanently Premium on the web,
 * because nothing would ever write false to any of them again. The mobile
 * SDKs were never exposed to this, since RevenueCat itself only ever
 * reports the entitlement to whoever currently holds it.
 */
function targetsFor(event, nowMs) {
  const verdict = entitlementFrom(event, nowMs);
  const out = [];
  const from = Array.isArray(event.transferred_from) ?
    event.transferred_from : [];
  if (String(event.type || "") === "TRANSFER") {
    // Everyone who LOST it, whatever the entitlement now says.
    for (const uid of from) {
      if (isRealUid(uid)) out.push({uid, active: false, expiresAtMs: null});
    }
    const to = Array.isArray(event.transferred_to) ? event.transferred_to : [];
    const gainers = to.length ? to : [event.app_user_id];
    if (verdict) {
      for (const uid of gainers) {
        if (isRealUid(uid) && !from.includes(uid)) {
          out.push({uid, active: verdict.active,
            expiresAtMs: verdict.expiresAtMs});
        }
      }
    }
    return out;
  }
  if (!verdict) return out;
  if (!isRealUid(event.app_user_id)) return out;
  out.push({uid: event.app_user_id, active: verdict.active,
    expiresAtMs: verdict.expiresAtMs});
  return out;
}

module.exports = {
  ENTITLEMENT_ID,
  entitlementFrom,
  isProduction,
  isRealUid,
  shouldApply,
  targetsFor,
};
