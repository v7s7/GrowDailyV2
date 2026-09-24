/**
 * The purchase facts' rules: what lands in purchase_log (who paid which
 * Lifetime price) and creator_ledger (what each creator earned).
 *
 * Money again, so each rule is pinned rather than reasoned about once. The
 * failures these guard against are quiet ones: a creator paid for a sale
 * that was refunded, a refund that claws back a cent less than its sale
 * paid, a net worked out from a percentage RevenueCat never sent, a monthly
 * renewal counted as a Lifetime buyer, or a field left undefined, which
 * Firestore refuses, so one odd payload would fail its write on every retry.
 *
 * Event payloads follow RevenueCat's documented webhook fields. `offer_code`
 * is the Apple offer's REFERENCE NAME (one offer per creator), and a refund
 * is a CANCELLATION whose price is negative.
 */

const test = require("node:test");
const assert = require("node:assert");
const webhook = require("../revenuecat_webhook");
const {
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
} = require("../purchase_facts");

const NOW = 1788000000000; // Fixed, so nothing depends on the clock.
const DAY = 86400000;
const UID = "5rLsgWgriLa7qaRDeZ3wdPfHgQl2"; // Aziz's real uid shape.
const SARA = {id: "sara", sharePercent: 25, name: "Sara", email: "x@y.z"};

/** A real App Store sale of the offer Lifetime, bought in the US. */
function sale(over) {
  return Object.assign({
    id: "8C4E7B1A-0F6D-4C3B-9E2A-5D1F7A3B6C90",
    type: "NON_RENEWING_PURCHASE",
    environment: "PRODUCTION",
    app_user_id: UID,
    product_id: "growdaily_lifetime_offer",
    store: "APP_STORE",
    price: 29.99,
    price_in_purchased_currency: 29.99,
    currency: "USD",
    tax_percentage: 0,
    commission_percentage: 0.3,
    offer_code: null,
    transaction_id: "2000000912345678",
    original_transaction_id: "2000000912345678",
    purchased_at_ms: NOW - 2000,
    event_timestamp_ms: NOW,
  }, over);
}

/** [e] refunded: a CANCELLATION carrying the sale's price made negative. */
function refundOf(e, over) {
  return Object.assign({}, e, {
    id: "refund-" + e.id,
    type: "CANCELLATION",
    cancel_reason: "CUSTOMER_SUPPORT",
    price: -e.price,
    price_in_purchased_currency: -e.price_in_purchased_currency,
    event_timestamp_ms: NOW + 3 * DAY,
  }, over);
}

/** A monthly renewal bought through [offerCode]. */
function monthly(over) {
  return sale(Object.assign({
    id: "monthly-1",
    type: "RENEWAL",
    product_id: "growdaily_monthly",
    price: 4.99,
    price_in_purchased_currency: 4.99,
  }, over));
}

test("purchase_facts and the mirror share ONE list of lifetimes", () => {
  // Two copies could drift, and then a buyer would be Premium on web but
  // missing from the log, or the other way round.
  assert.strictEqual(LIFETIME_PRODUCT_IDS, webhook.LIFETIME_PRODUCT_IDS);
});

test("an offer Lifetime sale logs what was paid and what is kept", () => {
  assert.deepEqual(purchaseLogRow(sale()), {
    productId: "growdaily_lifetime_offer",
    rawProductId: "growdaily_lifetime_offer",
    store: "APP_STORE",
    environment: "PRODUCTION",
    eventType: "NON_RENEWING_PURCHASE",
    kind: "sale",
    priceUsd: 29.99,
    priceLocal: 29.99,
    currency: "USD",
    taxPct: 0,
    commissionPct: 0.3,
    netUsd: 20.99, // 29.99 x 0.7 = 20.993
    offerCode: null,
    transactionId: "2000000912345678",
    originalTransactionId: "2000000912345678",
    eventAtMs: NOW - 2000,
    appUserId: UID,
  });
});

test("the regular Lifetime is logged too, under its own id", () => {
  const row = purchaseLogRow(sale({product_id: "growdaily_lifetime",
    price: 39.99, price_in_purchased_currency: 39.99}));
  assert.equal(row.productId, "growdaily_lifetime");
  assert.equal(row.kind, "sale");
  assert.equal(row.netUsd, 27.99); // 39.99 x 0.7 = 27.993
});

test("a refund is logged as a refund, and its net cancels the sale's", () => {
  const paid = purchaseLogRow(sale());
  const back = purchaseLogRow(refundOf(sale()));
  assert.equal(back.kind, "refund");
  assert.equal(back.eventType, "CANCELLATION");
  assert.equal(back.priceUsd, -29.99);
  assert.equal(back.netUsd, -20.99);
  assert.equal(paid.netUsd + back.netUsd, 0);
});

test("a Play purchase keyed with a suffix is logged under the bare id", () => {
  const row = purchaseLogRow(sale({
    product_id: "growdaily_lifetime_offer:lifetime", store: "PLAY_STORE",
    transaction_id: "GPA.3345-1234-5678-90123",
    original_transaction_id: "GPA.3345-1234-5678-90123"}));
  assert.equal(row.productId, "growdaily_lifetime_offer");
  assert.equal(row.rawProductId, "growdaily_lifetime_offer:lifetime");
  assert.equal(row.store, "PLAY_STORE");
  assert.equal(row.transactionId, "GPA.3345-1234-5678-90123");
});

test("a Gulf sale takes the VAT out, then the store's commission", () => {
  // 10% VAT is 0.0909 of a price that includes it. Bahrain pays about 0.636
  // of the price at 30%: 31.65 x 0.9091 x 0.7 = 20.14. Subtracting both
  // percentages from the price instead would say 19.28.
  const row = purchaseLogRow(sale({price: 31.65,
    price_in_purchased_currency: 11.9, currency: "BHD",
    tax_percentage: 0.0909}));
  assert.equal(row.netUsd, 20.14);
  assert.equal(row.priceLocal, 11.9);
  assert.equal(row.currency, "BHD");
});

test("an unknown tax or commission leaves the net unknown, not guessed", () => {
  for (const over of [
    {tax_percentage: null},
    {commission_percentage: null},
    {tax_percentage: undefined},
    // A percent where a fraction belongs must not become a negative payout.
    {commission_percentage: 30},
    {tax_percentage: 1},
    {tax_percentage: -0.1},
    {commission_percentage: "0.3"},
  ]) {
    const e = sale(over);
    assert.equal(netUsdOf(e), null, JSON.stringify(over));
    const row = purchaseLogRow(e);
    // Still a sale, still logged: only the net is unknown.
    assert.equal(row.kind, "sale", JSON.stringify(over));
    assert.equal(row.netUsd, null, JSON.stringify(over));
  }
  // The raw numbers stay on the row for whoever audits it.
  assert.equal(purchaseLogRow(sale({commission_percentage: 30}))
      .commissionPct, 30);
  assert.equal(purchaseLogRow(sale({tax_percentage: null})).taxPct, null);
});

test("the monthly never reaches the purchase log", () => {
  assert.equal(purchaseLogRow(monthly()), null);
  assert.equal(purchaseLogRow(monthly({
    product_id: "growdaily_monthly:monthly-autorenew",
    store: "PLAY_STORE"})), null);
  // Not even through a creator's offer: the ledger has that sale instead.
  const viaCreator = monthly({offer_code: "creator-sara"});
  assert.equal(purchaseLogRow(viaCreator), null);
  assert.notEqual(creatorLedgerRow(viaCreator, SARA), null);
});

test("an event that moved no money is not a fact", () => {
  for (const over of [
    {type: "EXPIRATION", price: null},
    // An unsubscribe is a CANCELLATION too, but its price is not negative.
    {type: "CANCELLATION", cancel_reason: "UNSUBSCRIBE", price: 29.99},
    {type: "PRODUCT_CHANGE"},
    {type: "UNCANCELLATION"},
    {type: "TEST"},
    {type: "NON_RENEWING_PURCHASE", price: null},
    {type: "NON_RENEWING_PURCHASE", price: undefined},
    {type: "NON_RENEWING_PURCHASE", price: "29.99"},
    {type: "NON_RENEWING_PURCHASE", price: NaN},
  ]) {
    const e = sale(Object.assign({offer_code: "creator-sara"}, over));
    assert.equal(purchaseKindOf(e), null, JSON.stringify(over));
    assert.equal(purchaseLogRow(e), null, JSON.stringify(over));
    assert.equal(creatorLedgerRow(e, SARA), null, JSON.stringify(over));
  }
  // RevenueCat's documented TRANSFER: no product, no price.
  const transfer = {id: "t", type: "TRANSFER", environment: "PRODUCTION",
    transferred_from: [UID], transferred_to: ["Z0FndO3iFYgrzWzkwJ4QlOPBLPr2"]};
  assert.equal(purchaseLogRow(transfer), null);
  assert.equal(purchaseKindOf(null), null);
  assert.equal(purchaseLogRow(null), null);
});

test("sales and refunds are told apart by the price's sign", () => {
  assert.equal(purchaseKindOf(sale()), "sale");
  assert.equal(purchaseKindOf(monthly({type: "INITIAL_PURCHASE"})), "sale");
  assert.equal(purchaseKindOf(monthly()), "sale");
  assert.equal(purchaseKindOf(refundOf(sale())), "refund");
  assert.equal(purchaseKindOf(refundOf(monthly())), "refund");
  // A free trial start or a free offer is a sale of zero, counted as one.
  assert.equal(purchaseKindOf(monthly({type: "INITIAL_PURCHASE", price: 0})),
      "sale");
  const free = purchaseLogRow(sale({price: 0, offer_code: "creator-sara"}));
  assert.equal(free.kind, "sale");
  assert.ok(Object.is(free.netUsd, 0));
});

test("sandbox purchases are recorded, and say they are sandbox", () => {
  // A sandbox purchase is how this pipe gets tested; the admin tool hides
  // these rows by default. Nothing here filters them.
  const e = sale({environment: "SANDBOX", offer_code: "creator-sara"});
  assert.equal(purchaseLogRow(e).environment, "SANDBOX");
  assert.equal(creatorLedgerRow(e, SARA).environment, "SANDBOX");
});

test("a guest's purchase is still a fact", () => {
  // The mirror cannot write for an anonymous id; the log is about money.
  const row = purchaseLogRow(sale({app_user_id: "$RCAnonymousID:9f8e7d"}));
  assert.equal(row.appUserId, "$RCAnonymousID:9f8e7d");
});

test("eventAtMs is the purchase time, else the event's own time", () => {
  assert.equal(purchaseLogRow(sale()).eventAtMs, NOW - 2000);
  assert.equal(purchaseLogRow(sale({purchased_at_ms: null})).eventAtMs, NOW);
  assert.equal(purchaseLogRow(sale({purchased_at_ms: undefined,
    event_timestamp_ms: undefined})).eventAtMs, null);
});

test("no field of either row is ever undefined", () => {
  // Firestore refuses undefined, so one missing field in RevenueCat's
  // payload would fail the write, and so the delivery, on every retry.
  const sparse = {type: "NON_RENEWING_PURCHASE", price: 39.99,
    product_id: "growdaily_lifetime", offer_code: "creator-sara"};
  const logRow = purchaseLogRow(sparse);
  assert.deepEqual(Object.keys(logRow).sort(), [
    "appUserId", "commissionPct", "currency", "environment", "eventAtMs",
    "eventType", "kind", "netUsd", "offerCode", "originalTransactionId",
    "priceLocal", "priceUsd", "productId", "rawProductId", "store", "taxPct",
    "transactionId",
  ]);
  const ledgerRow = creatorLedgerRow(sparse, null);
  assert.deepEqual(Object.keys(ledgerRow).sort(), [
    "appUserId", "commissionPct", "creatorId", "environment", "eventAtMs",
    "kind", "needsReview", "netUsd", "offerRef", "priceUsd", "productId",
    "sharePct", "shareUsd", "store", "taxPct", "transactionId",
  ]);
  for (const row of [logRow, ledgerRow]) {
    for (const [key, value] of Object.entries(row)) {
      // Strict: the loose notEqual would count null as undefined.
      assert.notStrictEqual(value, undefined, key);
    }
  }
});

test("the offer reference is trimmed and lowercased, or null", () => {
  assert.equal(offerRefOf(sale({offer_code: " Creator-Sara "})),
      "creator-sara");
  assert.equal(offerRefOf(sale({offer_code: "creator-sara"})),
      "creator-sara");
  for (const code of [null, undefined, "", "   ", 42, {}]) {
    assert.equal(offerRefOf(sale({offer_code: code})), null, String(code));
  }
  assert.equal(offerRefOf(null), null);
  // The log keeps the code exactly as RevenueCat sent it.
  assert.equal(purchaseLogRow(sale({offer_code: " Creator-Sara "})).offerCode,
      " Creator-Sara ");
  assert.equal(purchaseLogRow(sale({offer_code: "  "})).offerCode, null);
});

test("a creator's sale is ledgered with their share of the net", () => {
  assert.deepEqual(creatorLedgerRow(sale({offer_code: "Creator-Sara"}), SARA), {
    creatorId: "sara",
    offerRef: "creator-sara",
    kind: "sale",
    productId: "growdaily_lifetime_offer",
    store: "APP_STORE",
    environment: "PRODUCTION",
    priceUsd: 29.99,
    taxPct: 0,
    commissionPct: 0.3,
    netUsd: 20.99,
    sharePct: 25,
    shareUsd: 5.25, // 25% of 20.99 = 5.2475
    needsReview: false,
    eventAtMs: NOW - 2000,
    appUserId: UID,
    transactionId: "2000000912345678",
  });
  // Nothing else on the creator's record (name, contact) is copied.
});

test("a refund claws back exactly what its sale paid, to the cent", () => {
  // 29.97 nets 20.98, and 25% of that is 5.245, exactly half a cent. Plain
  // Math.round pays 5.25 and claws back 5.24, leaving a cent owed for a
  // sale refunded in full.
  const e = sale({price: 29.97, offer_code: "creator-sara"});
  const paid = creatorLedgerRow(e, SARA);
  const back = creatorLedgerRow(refundOf(e), SARA);
  assert.equal(paid.shareUsd, 5.25);
  assert.equal(back.kind, "refund");
  assert.equal(back.shareUsd, -5.25);
  assert.equal(back.netUsd, -20.98);
  assert.equal(paid.shareUsd + back.shareUsd, 0);
  assert.equal(back.transactionId, paid.transactionId); // How they pair.
});

test("the share is the percent at the time of the event, kept for good", () => {
  const creator = {id: "sara", sharePercent: 25};
  const early = creatorLedgerRow(sale({offer_code: "creator-sara"}), creator);
  // Aziz raises Sara's percent. Her next sale pays the new one...
  creator.sharePercent = 30;
  const later = creatorLedgerRow(sale({id: "later",
    offer_code: "creator-sara"}), creator);
  assert.equal(later.sharePct, 30);
  assert.equal(later.shareUsd, 6.3); // 30% of 20.99 = 6.297
  // ...and the row already made still says what the first one paid.
  assert.equal(early.sharePct, 25);
  assert.equal(early.shareUsd, 5.25);
});

test("the monthly earns a creator their share too", () => {
  const row = creatorLedgerRow(monthly({offer_code: "creator-sara",
    product_id: "growdaily_monthly:monthly-autorenew"}), SARA);
  assert.equal(row.productId, "growdaily_monthly");
  assert.equal(row.kind, "sale");
  assert.equal(row.netUsd, 3.49); // 4.99 x 0.7 = 3.493
  assert.equal(row.shareUsd, 0.87); // 25% of 3.49 = 0.8725
});

test("no offer code means no ledger row", () => {
  assert.equal(creatorLedgerRow(sale(), SARA), null);
  assert.equal(creatorLedgerRow(sale({offer_code: "  "}), SARA), null);
  assert.equal(creatorLedgerRow(null, SARA), null);
});

test("an offer code no creator claims is kept for review, not dropped", () => {
  const row = creatorLedgerRow(sale({offer_code: "ramadan-sale"}), null);
  assert.equal(row.creatorId, null);
  assert.equal(row.offerRef, "ramadan-sale");
  assert.equal(row.netUsd, 20.99);
  assert.equal(row.sharePct, null);
  assert.equal(row.shareUsd, null);
  assert.equal(row.needsReview, true);
});

test("a creator record without a usable percent is kept for review", () => {
  for (const sharePercent of ["25", 150, -1, NaN, null, undefined]) {
    const row = creatorLedgerRow(sale({offer_code: "creator-sara"}),
        {id: "sara", sharePercent});
    assert.equal(row.creatorId, "sara", String(sharePercent));
    assert.equal(row.sharePct, null, String(sharePercent));
    assert.equal(row.shareUsd, null, String(sharePercent));
    assert.equal(row.needsReview, true, String(sharePercent));
  }
  // The ends of the range are real percents.
  const none = creatorLedgerRow(sale({offer_code: "creator-sara"}),
      {id: "sara", sharePercent: 0});
  assert.equal(none.shareUsd, 0);
  assert.equal(none.needsReview, false);
  const all = creatorLedgerRow(sale({offer_code: "creator-sara"}),
      {id: "sara", sharePercent: 100});
  assert.equal(all.shareUsd, 20.99);
});

test("an unknown net leaves the share unknown and flags the row", () => {
  const row = creatorLedgerRow(sale({offer_code: "creator-sara",
    commission_percentage: null}), SARA);
  assert.equal(row.netUsd, null);
  assert.equal(row.sharePct, 25); // Still the snapshot, for whoever fixes it.
  assert.equal(row.shareUsd, null);
  assert.equal(row.needsReview, true);
});

test("round2 rounds to the cent, half away from zero", () => {
  assert.equal(round2(20.993), 20.99);
  assert.equal(round2(0.1 + 0.2), 0.3);
  // Binary traps: 1.005 x 100 is 100.49999999999999, and 2.675 is stored
  // as 2.67499999... A cent-rounder that multiplies first gets both wrong.
  assert.equal(round2(1.005), 1.01);
  assert.equal(round2(2.675), 2.68);
  // The same distance from zero either way, which is what lets a refund
  // cancel its sale. Math.round gives 0.13 and -0.12 here.
  assert.equal(round2(0.125), 0.13);
  assert.equal(round2(-0.125), -0.13);
  assert.equal(round2(-5.245), -5.25);
  // Never -0, which Firestore would keep as a separate value.
  assert.ok(Object.is(round2(-0.001), 0));
  assert.ok(Object.is(round2(-0), 0));
  assert.equal(round2(1e-7), 0);
  for (const bad of [NaN, Infinity, -Infinity, "1.5", null, undefined]) {
    assert.equal(round2(bad), null, String(bad));
  }
});

test("round2 is symmetric and within half a cent, across every mill", () => {
  // Every amount from 0 to 20 in steps of 0.001, so every half-cent tie.
  for (let mills = 0; mills <= 20000; mills++) {
    const x = mills / 1000;
    const up = round2(x);
    const down = round2(-x);
    assert.ok(up === -down, `${x}: ${up} vs ${down}`);
    assert.ok(Math.abs(up - x) <= 0.005 + 1e-9, `${x} -> ${up}`);
    assert.equal(Math.round(up * 100) / 100, up, `${x} -> ${up}`);
  }
});

test("both rows are keyed by the event id, or not written at all", () => {
  assert.equal(factDocId(sale()), "8C4E7B1A-0F6D-4C3B-9E2A-5D1F7A3B6C90");
  // No id: a made-up one would record one sale once per retry.
  for (const id of [undefined, null, "", 123]) {
    assert.equal(factDocId(sale({id})), null, String(id));
  }
  // Never a path, never a reserved name.
  for (const id of ["a/b", "../purchase_log", ".", "..", "__name__",
    "x".repeat(257)]) {
    assert.equal(factDocId(sale({id})), null, id.slice(0, 20));
  }
  assert.equal(factDocId(null), null);
});

// ── A refund follows its sale ────────────────────────────────────────────

test("a refund without an offer code follows its sale to the creator", () => {
  // RevenueCat may leave offer_code off a refund event. The sale's row
  // still names the creator, and the refund pairs with it by transaction.
  const bought = sale({offer_code: "creator-sara"});
  const saleRow = creatorLedgerRow(bought, SARA);
  const refund = refundOf(bought, {offer_code: null});
  // By its own offer code it would reach nobody.
  assert.equal(creatorLedgerRow(refund, SARA), null);
  assert.deepEqual(saleLookupKeys(refund), ["2000000912345678"]);
  assert.deepEqual(ledgerRowFor(refund, {sale: saleRow}), {
    creatorId: "sara",
    offerRef: "creator-sara",
    kind: "refund",
    productId: "growdaily_lifetime_offer",
    store: "APP_STORE",
    environment: "PRODUCTION",
    priceUsd: -29.99,
    taxPct: 0,
    commissionPct: 0.3,
    netUsd: -20.99,
    sharePct: 25,
    shareUsd: -5.25,
    needsReview: false,
    eventAtMs: NOW - 2000,
    appUserId: UID,
    transactionId: "2000000912345678",
  });
});

test("a refund after the creator's percent changed nets to zero", () => {
  // The half-cent case: 29.97 nets 20.98, and 25% of that is 5.245.
  const creator = {id: "sara", sharePercent: 25};
  const bought = sale({price: 29.97, price_in_purchased_currency: 29.97,
    offer_code: "creator-sara"});
  const saleRow = creatorLedgerRow(bought, creator);
  // Sara moves to 40% before the refund arrives.
  creator.sharePercent = 40;
  const refund = refundOf(bought);
  const row = ledgerRowFor(refund, {sale: saleRow, creator});
  assert.equal(row.sharePct, 25);
  assert.equal(row.shareUsd, -5.25);
  assert.equal(saleRow.shareUsd + row.shareUsd, 0);
  assert.equal(saleRow.netUsd + row.netUsd, 0);
  // Its own offer code at today's percent would have taken back 8.39.
  assert.equal(creatorLedgerRow(refund, creator).shareUsd, -8.39);
});

test("a refund is worked out at the sale's rates, not a moved estimate", () => {
  // Joining the Small Business Program between the sale and the refund
  // could make the refund event say 15% where the sale said 30%.
  const bought = sale({offer_code: "creator-sara"});
  const saleRow = creatorLedgerRow(bought, SARA);
  const row = refundLedgerRow(
      refundOf(bought, {commission_percentage: 0.15}), saleRow);
  assert.equal(row.commissionPct, 0.3);
  assert.equal(row.netUsd, -20.99);
  assert.equal(saleRow.shareUsd + row.shareUsd, 0);
});

test("a partial refund takes back its part, at the sale's rates", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "creator-sara"}), SARA);
  const row = refundLedgerRow(refundOf(sale(), {price: -10}), saleRow);
  assert.equal(row.netUsd, -7); // 10 x 0.7
  assert.equal(row.shareUsd, -1.75); // 25% of 7
});

test("when the sale's rates are unknown, the refund's own are used", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "creator-sara",
    commission_percentage: null}), SARA);
  assert.equal(saleRow.netUsd, null);
  const row = refundLedgerRow(refundOf(sale()), saleRow);
  assert.equal(row.commissionPct, 0.3);
  assert.equal(row.netUsd, -20.99);
  assert.equal(row.shareUsd, -5.25);
});

test("no ledgered sale and no offer code: nothing in the ledger", () => {
  const refund = refundOf(sale()); // No offer code, and no sale row found.
  assert.equal(ledgerRowFor(refund, {sale: null, creator: null}), null);
  assert.equal(ledgerRowFor(refund, {}), null);
  // A Lifetime refund is still in purchase_log, which needs no creator.
  assert.equal(purchaseLogRow(refund).kind, "refund");
  assert.equal(purchaseLogRow(refund).netUsd, -20.99);
  // A monthly one is in neither.
  const monthlyRefund = refundOf(monthly());
  assert.equal(ledgerRowFor(monthlyRefund, {}), null);
  assert.equal(purchaseLogRow(monthlyRefund), null);
});

test("a refund whose sale was never ledgered goes by its offer code", () => {
  const refund = refundOf(sale({offer_code: "creator-sara"}));
  assert.deepEqual(ledgerRowFor(refund, {sale: null, creator: SARA}),
      creatorLedgerRow(refund, SARA));
  assert.equal(ledgerRowFor(refund, {creator: SARA}).shareUsd, -5.25);
});

test("where a refund looks for its sale", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "creator-sara"}), SARA);
  const lifetime = refundOf(sale());
  assert.deepEqual(saleLookupKeys(lifetime), ["2000000912345678"]);
  // A Lifetime tries the original purchase after its own transaction: a
  // restore can carry a new transaction id over the same original.
  const restored = Object.assign({}, lifetime,
      {transaction_id: "2000000999999999"});
  assert.deepEqual(saleLookupKeys(restored),
      ["2000000999999999", "2000000912345678"]);
  // Found that way, the refund files under the sale's transaction.
  assert.equal(refundLedgerRow(restored, saleRow).transactionId,
      "2000000912345678");
  assert.deepEqual(saleLookupKeys(Object.assign({}, lifetime,
      {transaction_id: null})), ["2000000912345678"]);
  // A monthly tries its own transaction only. Its original is the FIRST
  // month, a different sale, which may be a creator's when this one is not.
  const renewal = refundOf(monthly({transaction_id: "2000000955555555"}));
  assert.deepEqual(saleLookupKeys(renewal), ["2000000955555555"]);
  assert.deepEqual(saleLookupKeys(Object.assign({}, renewal,
      {transaction_id: null})), []);
  // Only a refund looks for a sale.
  assert.deepEqual(saleLookupKeys(sale()), []);
  assert.deepEqual(saleLookupKeys(null), []);
});

test("only a refund follows, and only a sale row is followed", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "creator-sara"}), SARA);
  const refund = refundOf(sale());
  assert.equal(refundLedgerRow(sale(), saleRow), null); // Not a refund.
  assert.equal(refundLedgerRow(refund, null), null);
  const refundRow = refundLedgerRow(refund, saleRow);
  assert.equal(refundLedgerRow(refund, refundRow), null); // Not a sale.
});

test("a refund of a sale no creator claimed stays flagged beside it", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "ramadan-sale"}), null);
  const row = refundLedgerRow(refundOf(sale()), saleRow);
  assert.equal(row.creatorId, null);
  assert.equal(row.offerRef, "ramadan-sale");
  assert.equal(row.sharePct, null);
  assert.equal(row.shareUsd, null);
  assert.equal(row.needsReview, true);
});

test("a followed refund has the ledger's one shape, nothing undefined", () => {
  const saleRow = creatorLedgerRow(sale({offer_code: "creator-sara"}), SARA);
  const row = refundLedgerRow(refundOf(sale()), saleRow);
  assert.deepEqual(Object.keys(row).sort(), Object.keys(saleRow).sort());
  // Even from a bare refund event and a bare sale row.
  const bare = refundLedgerRow({type: "CANCELLATION", price: -39.99},
      {kind: "sale"});
  assert.deepEqual(Object.keys(bare).sort(), Object.keys(saleRow).sort());
  for (const [key, value] of Object.entries(bare)) {
    assert.notStrictEqual(value, undefined, key);
  }
  assert.equal(bare.needsReview, true);
});
