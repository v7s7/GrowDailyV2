/**
 * Pure purchase facts for the RevenueCat webhook: who paid which Lifetime
 * price, and what each creator earned. Split out, like revenuecat_webhook.js,
 * so every money rule here is unit-testable without Firestore, Express or a
 * deploy. Nothing in this file touches Firestore: recordPurchaseFacts in
 * index.js adds `createdAt` and does the writing.
 *
 * WHAT THE ROWS ARE. A log of what the store said happened, one row per
 * RevenueCat event, keyed by that event's id:
 *
 *  - purchase_log: every sale and refund of a LIFETIME product, at either
 *    price. growdaily_lifetime is the regular price, growdaily_lifetime_offer
 *    the lower one shown during a person's 72-hour welcome window and during
 *    dated sales, so the admin tool can count who pays full price.
 *  - creator_ledger: every sale and refund of ANY product bought through an
 *    Apple offer code, with the creator's share of it. There is one Apple
 *    offer per creator, and RevenueCat's `offer_code` carries that offer's
 *    REFERENCE NAME (for example "creator-sara"), never the custom code the
 *    buyer typed, so the reference name is what a creator is found by. A
 *    refund follows its sale's row when there is one ([ledgerRowFor]), so
 *    it reaches the creator with or without an offer code on the refund
 *    event and takes back exactly what the sale paid.
 *
 * WHAT THEY ARE NOT. Not an entitlement: nothing here grants or revokes
 * Premium, which stays RevenueCat's answer and the mirror's job
 * (revenuecat_webhook.js). And not a statement: `tax_percentage` and
 * `commission_percentage` are RevenueCat's ESTIMATES, so `netUsd` and
 * `shareUsd` are right for a meter and for drafting a payout, while Apple's
 * and Google's own proceeds reports stay the record before money moves.
 *
 * SANDBOX. Rows are written for sandbox events too, with `environment`
 * copied through, because a sandbox purchase is the only way to prove this
 * pipe before a real one (it is not yet proven that RevenueCat fills
 * `offer_code` for a one-time purchase). The admin tool hides them by
 * default.
 *
 * NEVER UNDEFINED. Every field of every row is present, and null when
 * unknown. Firestore refuses `undefined` as a value, so one field missing
 * from RevenueCat's payload would otherwise fail the write on every retry.
 */

"use strict";

const {
  LIFETIME_PRODUCT_IDS,
  baseProductId,
  isLifetimeProduct,
} = require("./revenuecat_webhook");

/**
 * The event types that bring money IN, when their price is zero or more
 * (see [purchaseKindOf]). A lifetime arrives as NON_RENEWING_PURCHASE; the
 * monthly as INITIAL_PURCHASE and then RENEWAL.
 */
const SALE_TYPES = Object.freeze([
  "INITIAL_PURCHASE",
  "NON_RENEWING_PURCHASE",
  "RENEWAL",
]);

/** A finite number, as opposed to null, a string, NaN or Infinity. */
function isFiniteNumber(v) {
  return typeof v === "number" && Number.isFinite(v);
}

/** [v] when it is a finite number, else null. */
function numOrNull(v) {
  return isFiniteNumber(v) ? v : null;
}

/** [v] when it is a non-empty string, else null. */
function strOrNull(v) {
  return typeof v === "string" && v !== "" ? v : null;
}

/** A fraction a percentage field may hold: a finite number in [0, 1). */
function isFraction(v) {
  return isFiniteNumber(v) && v >= 0 && v < 1;
}

/**
 * [n] rounded to whole cents, half AWAY FROM ZERO, or null when [n] is not
 * a finite number.
 *
 * Away from zero, and not Math.round's half-up, so a refund always mirrors
 * its sale to the cent: Math.round gives 0.125 -> 0.13 but -0.125 -> -0.12,
 * and a creator's 25% of 20.98 (5.245) would be paid as 5.25 and clawed
 * back as 5.24, leaving a cent owed for a sale refunded in full. So the
 * magnitude is rounded and the sign put back.
 *
 * The magnitude is shifted by its shortest decimal string ("1.005" becomes
 * "1.005e2", which is 100.5) rather than multiplied by 100, because
 * 1.005 * 100 is 100.49999999999999 in binary and would round down. Tiny
 * and huge values, whose string is already in exponent form, fall back to
 * the multiply, where that trap cannot matter. Never returns -0.
 */
function round2(n) {
  if (!isFiniteNumber(n)) return null;
  const abs = Math.abs(n);
  const text = String(abs);
  const cents = text.includes("e") ?
    Math.round(abs * 100) :
    Math.round(Number(text + "e2"));
  const rounded = cents / 100;
  if (rounded === 0) return 0;
  return n < 0 ? -rounded : rounded;
}

/**
 * What the developer keeps from [event], in USD rounded to cents, or null
 * when RevenueCat did not say enough to work it out.
 *
 * price x (1 - tax_percentage) x (1 - commission_percentage): the store
 * takes its commission from the price AFTER tax. That is why a Bahrain sale
 * at 30% pays about 0.636 of its price (10% VAT is 0.0909 of a price that
 * includes it, and 0.9091 x 0.7 = 0.636), the figure App Store Connect
 * showed on 2026-09-22.
 *
 * Both percentages must be fractions in [0, 1). RevenueCat may send null
 * for either, and a 30 where 0.3 was meant has to read as "unknown", not as
 * a negative payout. The sign of the price is kept, so a refund's net is
 * negative and cancels its sale.
 */
function netUsdOf(event) {
  if (!event || typeof event !== "object") return null;
  const price = event.price;
  if (!isFiniteNumber(price)) return null;
  const tax = event.tax_percentage;
  const commission = event.commission_percentage;
  if (!isFraction(tax) || !isFraction(commission)) return null;
  return round2(price * (1 - tax) * (1 - commission));
}

/**
 * "sale", "refund" or null: whether [event] moved money, and which way.
 *
 * A refund is ANY event with a negative price. RevenueCat documents a
 * negative price as a refund, and a refunded purchase arrives as a
 * CANCELLATION (cancel_reason CUSTOMER_SUPPORT), so the sign is the field to
 * trust rather than the type.
 *
 * A sale is one of [SALE_TYPES] with a price of zero or more. Zero is kept:
 * a free trial start or a free offer is a real event even though it paid
 * nothing, and it counts as zero.
 *
 * Everything else is null: an EXPIRATION, a PRODUCT_CHANGE, an unsubscribe
 * (a CANCELLATION without a negative price), a TRANSFER, the dashboard's
 * TEST button, and any price RevenueCat did not know.
 */
function purchaseKindOf(event) {
  if (!event || typeof event !== "object") return null;
  const price = event.price;
  if (!isFiniteNumber(price)) return null;
  if (price < 0) return "refund";
  return SALE_TYPES.includes(event.type) ? "sale" : null;
}

/**
 * The Apple offer's reference name this purchase came through, trimmed and
 * lowercased, or null when there was none.
 *
 * `offer_code` is the offer's REFERENCE NAME in App Store Connect (say
 * "creator-sara"), not the code the buyer typed, so it names the creator's
 * offer rather than the person. Lowercased because the name is typed by
 * hand in App Store Connect and again on the creator's record, and a
 * capital letter in one of them must not lose a creator their sale. So
 * creators/{id}.offerRef has to be stored in this same form, trimmed and
 * lowercase, for the lookup to find it. (On Play the field is the promotion
 * code itself; no creator uses one, so such a row finds no creator and is
 * flagged for review, see [creatorLedgerRow].)
 */
function offerRefOf(event) {
  const code = event && event.offer_code;
  if (typeof code !== "string") return null;
  const ref = code.trim().toLowerCase();
  return ref === "" ? null : ref;
}

/**
 * When the purchase happened, falling back to when the event fired, or
 * null when RevenueCat sent neither.
 */
function eventAtMsOf(event) {
  if (isFiniteNumber(event.purchased_at_ms)) return event.purchased_at_ms;
  return numOrNull(event.event_timestamp_ms);
}

/**
 * The purchase_log row for [event], or null when it is not a sale or refund
 * of a Lifetime product.
 *
 * Both lifetimes count, matched on the id before any Play suffix, so
 * `productId` is the id both stores share and the one the admin tool groups
 * by, while `rawProductId` keeps exactly what RevenueCat sent. The monthly
 * never lands here: this log answers which Lifetime price people pay, and
 * a renewal every month would bury that.
 *
 * `priceUsd`, `taxPct` and `commissionPct` are RevenueCat's own numbers,
 * kept as sent for audit even when [netUsdOf] cannot use them. `offerCode`
 * is also as sent; compare it through [offerRefOf]. `eventAtMs` is
 * purchased_at_ms, else event_timestamp_ms. For a refund that may be the
 * refunded purchase's own time; the row's createdAt says when the refund
 * reached the webhook.
 */
function purchaseLogRow(event) {
  if (!event || typeof event !== "object") return null;
  if (!isLifetimeProduct(event.product_id)) return null;
  const kind = purchaseKindOf(event);
  if (kind === null) return null;
  return {
    productId: baseProductId(event.product_id),
    rawProductId: event.product_id,
    store: strOrNull(event.store),
    environment: strOrNull(event.environment),
    eventType: strOrNull(event.type),
    kind,
    priceUsd: event.price,
    priceLocal: numOrNull(event.price_in_purchased_currency),
    currency: strOrNull(event.currency),
    taxPct: numOrNull(event.tax_percentage),
    commissionPct: numOrNull(event.commission_percentage),
    netUsd: netUsdOf(event),
    offerCode: typeof event.offer_code === "string" &&
      event.offer_code.trim() !== "" ? event.offer_code : null,
    transactionId: strOrNull(event.transaction_id),
    originalTransactionId: strOrNull(event.original_transaction_id),
    eventAtMs: eventAtMsOf(event),
    appUserId: strOrNull(event.app_user_id),
  };
}

/** [pct] when it is a share percent, a number from 0 to 100, else null. */
function sharePctOrNull(pct) {
  return isFiniteNumber(pct) && pct >= 0 && pct <= 100 ? pct : null;
}

/**
 * The creator_ledger row for [event], or null when the event carries no
 * offer code or moved no money (see [purchaseKindOf]).
 *
 * [creator] is the creators document as a plain object with its document
 * id as `id`, so `{id, sharePercent, ...}`, or null when no creator's
 * offerRef matches. Any product counts, the monthly included: what a
 * creator earns is not a Lifetime question.
 *
 * THE SHARE IS A SNAPSHOT, on purpose. `sharePct` is copied from the
 * creator when the event is recorded, and the row is written once and never
 * again (create-only, keyed by event id), so changing a creator's percent
 * later changes what later sales pay them and cannot rewrite what earlier
 * ones did.
 *
 * A refund only comes here when its sale was never ledgered: a refund whose
 * sale row exists follows that row instead ([refundLedgerRow], chosen by
 * [ledgerRowFor]), at the sale's percent. Here a refund is worked out from
 * its own offer code at the percent the creator has now, and carries a
 * negative `shareUsd`.
 *
 * `needsReview` is true when the share could not be worked out: the store
 * did not say enough for a net (`netUsd` null), no creator claims the offer,
 * or the creator's `sharePercent` is not a number from 0 to 100. The row is
 * still written, so the sale is not lost while someone fixes the record,
 * and `shareUsd` is null rather than a guess.
 */
function creatorLedgerRow(event, creator) {
  const offerRef = offerRefOf(event);
  if (offerRef === null) return null;
  const kind = purchaseKindOf(event);
  if (kind === null) return null;
  const creatorId = creator ? strOrNull(creator.id) : null;
  const sharePct = sharePctOrNull(creator ? creator.sharePercent : null);
  const netUsd = netUsdOf(event);
  const shareUsd = netUsd === null || sharePct === null ?
    null : round2(netUsd * sharePct / 100);
  return {
    creatorId,
    offerRef,
    kind,
    productId: baseProductId(event.product_id),
    store: strOrNull(event.store),
    environment: strOrNull(event.environment),
    priceUsd: event.price,
    taxPct: numOrNull(event.tax_percentage),
    commissionPct: numOrNull(event.commission_percentage),
    netUsd,
    sharePct,
    shareUsd,
    needsReview: creatorId === null || shareUsd === null,
    eventAtMs: eventAtMsOf(event),
    appUserId: strOrNull(event.app_user_id),
    transactionId: strOrNull(event.transaction_id),
  };
}

/**
 * The transaction ids a refund's SALE row may be filed under in
 * creator_ledger, in the order to try them, or [] for anything that is not
 * a refund.
 *
 * A refund names the transaction it refunds in `transaction_id`, and a sale
 * row keeps its own `transaction_id` as `transactionId`, so that pair comes
 * first. `original_transaction_id` is tried after it for a LIFETIME only. A
 * one-time purchase is one payment, so its original transaction is the same
 * purchase (a restored purchase can carry a new transaction_id over the same
 * original). A subscription's original transaction is its FIRST payment, a
 * different sale from the renewal being refunded, and following it would
 * charge a creator for a renewal that may never have earned them anything.
 */
function saleLookupKeys(event) {
  if (purchaseKindOf(event) !== "refund") return [];
  const keys = [];
  const transaction = strOrNull(event.transaction_id);
  if (transaction !== null) keys.push(transaction);
  const original = strOrNull(event.original_transaction_id);
  if (original !== null && original !== transaction &&
      isLifetimeProduct(event.product_id)) {
    keys.push(original);
  }
  return keys;
}

/**
 * The creator_ledger row for a refund that follows its SALE row, or null
 * unless [event] is a refund and [sale] is a sale row.
 *
 * [sale] is the ledger row of the purchase being refunded, found through
 * [saleLookupKeys]. Following it, rather than the refund's own offer code,
 * does two things. The refund reaches the right creator even when
 * RevenueCat leaves `offer_code` off the refund event. And it takes back
 * exactly what the sale paid: `creatorId`, `offerRef` and `sharePct` are the
 * sale's, so a percent changed since the sale changes nothing here, and the
 * net is worked out at the sale's own tax and commission rates rather than
 * the refund event's, so an estimate that moved in between (the commission
 * after joining the Small Business Program, say) cannot take back more than
 * the sale brought in. A full refund therefore nets to exactly zero with
 * its sale, to the cent ([round2] is symmetric), and a partial one takes
 * back its part at the same rates. Only when the sale's rates are unknown
 * are the refund's own used.
 *
 * `transactionId` is the sale's, so the two rows share it and pair by it,
 * including a Lifetime refund found through original_transaction_id. A sale
 * that no creator claimed (creatorId null) passes that on: the refund is
 * flagged for review beside it, and fixing the sale row fixes where later
 * refunds go.
 */
function refundLedgerRow(event, sale) {
  if (purchaseKindOf(event) !== "refund") return null;
  if (!sale || typeof sale !== "object" || sale.kind !== "sale") return null;
  const saleRates = isFraction(sale.taxPct) && isFraction(sale.commissionPct);
  const taxPct = saleRates ? sale.taxPct : numOrNull(event.tax_percentage);
  const commissionPct = saleRates ?
    sale.commissionPct : numOrNull(event.commission_percentage);
  const netUsd = saleRates ?
    round2(event.price * (1 - taxPct) * (1 - commissionPct)) :
    netUsdOf(event);
  const creatorId = strOrNull(sale.creatorId);
  const sharePct = sharePctOrNull(sale.sharePct);
  const shareUsd = netUsd === null || sharePct === null ?
    null : round2(netUsd * sharePct / 100);
  return {
    creatorId,
    offerRef: strOrNull(sale.offerRef),
    kind: "refund",
    productId: baseProductId(event.product_id) || strOrNull(sale.productId),
    store: strOrNull(event.store) || strOrNull(sale.store),
    environment: strOrNull(event.environment) ||
      strOrNull(sale.environment),
    priceUsd: event.price,
    taxPct,
    commissionPct,
    netUsd,
    sharePct,
    shareUsd,
    needsReview: creatorId === null || shareUsd === null,
    eventAtMs: eventAtMsOf(event),
    appUserId: strOrNull(event.app_user_id) || strOrNull(sale.appUserId),
    transactionId: strOrNull(sale.transactionId) ||
      strOrNull(event.transaction_id),
  };
}

/**
 * The creator_ledger row to write for [event], or null when there is none.
 *
 * [found] is what the caller looked up: `sale`, the ledger's sale row of
 * the purchase a refund refunds (see [saleLookupKeys]), and `creator`, the
 * creator whose offerRef matches the event's offer code (looked up only
 * when there is no sale to follow). Either may be null or left out.
 *
 * A refund follows its sale when there is one ([refundLedgerRow]).
 * Everything else goes by its own offer code ([creatorLedgerRow]): every
 * sale, and a refund whose sale was never ledgered. So a refund with no
 * ledgered sale and no offer code writes nothing to the ledger, because
 * there is no creator to charge it to. A Lifetime refund is still in
 * purchase_log either way; that log does not depend on a creator.
 */
function ledgerRowFor(event, found) {
  const sale = found && found.sale ? found.sale : null;
  const creator = found && found.creator ? found.creator : null;
  const followed = refundLedgerRow(event, sale);
  if (followed !== null) return followed;
  return creatorLedgerRow(event, creator);
}

/**
 * The document id both rows are written under: RevenueCat's event id, or
 * null when the event has none that can be a Firestore document id.
 *
 * The event id is what makes a retried delivery harmless (the second
 * create() finds the row and changes nothing), so an event without one is
 * never recorded under a made-up id, which would count one sale once per
 * retry. RevenueCat's ids are UUIDs. Anything holding a "/" (a path that
 * would write somewhere else entirely), "." or "..", or the reserved
 * __name__ form is refused.
 */
function factDocId(event) {
  const id = event && event.id;
  if (typeof id !== "string") return null;
  if (id === "" || id.length > 256) return null;
  if (id === "." || id === ".." || id.includes("/")) return null;
  if (/^__.*__$/.test(id)) return null;
  return id;
}

module.exports = {
  LIFETIME_PRODUCT_IDS,
  creatorLedgerRow,
  factDocId,
  ledgerRowFor,
  netUsdOf,
  offerRefOf,
  purchaseKindOf,
  purchaseLogRow,
  refundLedgerRow,
  round2,
  saleLookupKeys,
};
