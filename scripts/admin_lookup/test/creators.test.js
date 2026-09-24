'use strict';

/**
 * The Creators page's pure logic (lib/creators.js): price points, the money
 * preview, what a new creator and a payout are checked against, the ledger
 * sums (earned, paid, waiting, owed, with refunds), and the App Store
 * Connect request bodies.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const C = require('../lib/creators');

const DAY = C.DAY_MS;
const NOW = Date.UTC(2026, 8, 22, 9, 0);

// ---- Codes and links ----------------------------------------------------------

test('a code keeps Latin letters and digits, upper case; its offer name is lower case', () => {
  assert.strictEqual(C.normalizeCode(' sara-20! '), 'SARA20');
  assert.strictEqual(C.normalizeCode('x'.repeat(80)).length, 64);
  assert.strictEqual(C.offerRefFor('SARA'), 'creator-sara');
  assert.strictEqual(C.shareLinkFor('SARA'), 'https://apps.apple.com/redeem?ctx=offercodes&id=6788149393&code=SARA');
});

// ---- Price points and money ---------------------------------------------------

test('the buyer price is the .49/.99 point at or below the discount, rounded down', () => {
  assert.strictEqual(C.pricePointAtOrBelow(2399), 2399);
  assert.strictEqual(C.pricePointAtOrBelow(2398), 2349);
  assert.strictEqual(C.pricePointAtOrBelow(2449), 2449);
  assert.strictEqual(C.pricePointAtOrBelow(2448), 2399);
  assert.strictEqual(C.pricePointAtOrBelow(48), null);
  // 20% off 29.99 is 23.992: 23.99. 10% off 29.99 is 26.991: 26.99. Both
  // Lifetimes are $29.99 since Aziz kept that price (2026-09-24).
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime_offer', 20), 2399);
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime', 20), 2399);
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime', 10), 2699);
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime_offer', 10), 2699);
  // 25% off 29.99 is 22.4925, so 22.49; 26% off is 22.1926, so 21.99, never 22.49.
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime_offer', 25), 2249);
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime_offer', 26), 2199);
  assert.strictEqual(C.offerPriceCents('growdaily_lifetime_offer', 90), 299);
  assert.strictEqual(C.offerPriceCents('nope', 20), null);
});

test('every point the formula can pick is a real Apple US price point', () => {
  // The .49 and .99 points Apple listed for the offer product on 2026-09-22 (GET pricePoints, USA).
  const real = new Set();
  for (let d = 0; d < 50; d++) { real.add(d * 100 + 49); real.add(d * 100 + 99); }
  for (const productId of Object.keys(C.PRODUCTS)) {
    for (let d = C.MIN_DISCOUNT; d <= C.MAX_DISCOUNT; d++) {
      const cents = C.offerPriceCents(productId, d);
      assert.ok(real.has(cents), productId + ' at ' + d + '% gave ' + cents);
      assert.ok(cents < C.toCents(C.PRODUCTS[productId].priceUsd));
    }
  }
});

test('the money preview matches the approved design: 20% off $29.99, 25% share, Apple keeps 30%', () => {
  const m = C.moneyPreview({ productId: 'growdaily_lifetime_offer', discountPercent: 20, sharePercent: 25, keepRate: 0.70 });
  assert.strictEqual(C.money(m.buyerCents), '$23.99');
  assert.strictEqual(C.money(m.proceedsCents), '$16.80');
  assert.strictEqual(C.money(m.creatorCents), '$4.20');
  assert.strictEqual(C.money(m.keepCents), '$12.60');
  assert.strictEqual(C.money(m.plainCents), '$21.00');
  const sbp = C.moneyPreview({ productId: 'growdaily_lifetime_offer', discountPercent: 20, sharePercent: 25, keepRate: 0.85 });
  assert.strictEqual(C.money(sbp.proceedsCents), '$20.40');
  assert.strictEqual(C.money(sbp.creatorCents), '$5.10');
});

test('money prints with cents, a sign and thousands', () => {
  assert.strictEqual(C.money(0), '$0.00');
  assert.strictEqual(C.money(-420), '-$4.20');
  assert.strictEqual(C.money(123456), '$1,234.56');
});

// ---- Dates -------------------------------------------------------------------------

test('a code ends at 00:00 Pacific on its day, summer or winter', () => {
  // PDT (UTC-7) in September, PST (UTC-8) in March before the switch.
  assert.strictEqual(C.pacificMidnightMs('2026-09-30'), Date.UTC(2026, 8, 30, 7, 0));
  assert.strictEqual(C.pacificMidnightMs('2027-03-01'), Date.UTC(2027, 2, 1, 8, 0));
  assert.strictEqual(C.pacificDateKey(C.pacificMidnightMs('2027-03-22')), '2027-03-22');
});

test('six months ahead clamps to the end of a shorter month', () => {
  assert.strictEqual(C.addMonths('2026-08-31', 6), '2027-02-28');
  assert.strictEqual(C.addMonths('2026-09-22', 6), '2027-03-22');
  const range = C.codeEndRange(NOW);
  assert.deepStrictEqual(range, { min: '2026-09-23', max: '2027-03-22' });
});

// ---- A new creator ----------------------------------------------------------------

const good = {
  name: 'Sara',
  code: 'SARA',
  discountPercent: 20,
  discountOff: 'growdaily_lifetime_offer',
  sharePercent: 25,
  codeEndsOn: '2027-03-22',
  usesAllowed: 1000,
};

test('a good creator becomes the record the creators document stores', () => {
  const r = C.checkCreatorInput(good, { nowMs: NOW });
  assert.deepStrictEqual(r.errors, []);
  assert.deepStrictEqual(r.value, {
    name: 'Sara',
    code: 'SARA',
    offerRef: 'creator-sara',
    discountPercent: 20,
    discountOff: 'growdaily_lifetime_offer',
    offerPriceUsd: 23.99,
    sharePercent: 25,
    codeEndsOn: '2027-03-22',
    codeEndsAtMs: C.pacificMidnightMs('2027-03-22'),
    usesAllowed: 1000,
  });
});

test('every refusal for a new creator', () => {
  const codes = (patch) => C.checkCreatorInput({ ...good, ...patch }, { nowMs: NOW }).errors.map((e) => e.code);
  assert.deepStrictEqual(codes({ name: '  ' }), ['name']);
  assert.deepStrictEqual(codes({ name: 'x'.repeat(81) }), ['name-long']);
  assert.deepStrictEqual(codes({ name: 'A' + String.fromCharCode(0x2014) + 'B' }), ['name-dash']);
  assert.deepStrictEqual(codes({ code: 'SA' }), ['code']);
  assert.deepStrictEqual(codes({ code: 'SARA-20' }), ['code']);
  assert.deepStrictEqual(codes({ discountPercent: 0 }), ['discount']);
  assert.deepStrictEqual(codes({ discountPercent: 91 }), ['discount']);
  assert.deepStrictEqual(codes({ discountPercent: 12.5 }), ['discount']);
  assert.deepStrictEqual(codes({ discountOff: 'growdaily_monthly' }), ['product']);
  assert.deepStrictEqual(codes({ sharePercent: 101 }), ['share']);
  assert.deepStrictEqual(codes({ sharePercent: 12.345 }), ['share']);
  assert.deepStrictEqual(codes({ sharePercent: '25' }), ['share']);
  assert.deepStrictEqual(codes({ codeEndsOn: '2027-02-30' }), ['ends']);
  assert.deepStrictEqual(codes({ codeEndsOn: '2026-09-22' }), ['ends-past']);
  assert.deepStrictEqual(codes({ codeEndsOn: '2027-03-23' }), ['ends-far']);
  assert.deepStrictEqual(codes({ usesAllowed: 0 }), ['uses']);
  assert.deepStrictEqual(codes({ usesAllowed: 25001 }), ['uses']);
  assert.strictEqual(C.checkCreatorInput({ ...good, sharePercent: 0 }, { nowMs: NOW }).ok, true, 'a creator may take no share');
  assert.strictEqual(C.checkCreatorInput({ ...good, sharePercent: 12.5 }, { nowMs: NOW }).ok, true);
});

test('a payout is more than zero and no more than what is earned and unpaid', () => {
  assert.strictEqual(C.checkPayout({ amountUsd: 13.6, note: 'Bank transfer' }, { unpaidCents: 1360 }).ok, true);
  assert.deepStrictEqual(C.checkPayout({ amountUsd: 13.61 }, { unpaidCents: 1360 }).errors.map((e) => e.code), ['amount-over']);
  assert.deepStrictEqual(C.checkPayout({ amountUsd: 0 }, { unpaidCents: 1360 }).errors.map((e) => e.code), ['amount']);
  assert.deepStrictEqual(C.checkPayout({ amountUsd: 1.005 }, { unpaidCents: 1360 }).errors.map((e) => e.code), ['amount']);
  assert.deepStrictEqual(C.checkPayout({ amountUsd: 5, note: 'x'.repeat(201) }, { unpaidCents: 1360 }).errors.map((e) => e.code), ['note']);
  assert.strictEqual(C.checkShareChange(30).ok, true);
  assert.strictEqual(C.checkShareChange(-1).ok, false);
});

// ---- The ledger ------------------------------------------------------------------------

function ledgerRow(creatorId, kind, shareUsd, eventAtMs, extra = {}) {
  return {
    creatorId, offerRef: 'creator-' + String(creatorId).toLowerCase(), kind, shareUsd, eventAtMs,
    environment: 'PRODUCTION', needsReview: false, transactionId: 'tx-' + Math.random(), ...extra,
  };
}

test('earned, waiting and owed split at 60 days; payouts come off what is owed', () => {
  const creators = [{ id: 'SARA' }];
  const ledger = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 90 * DAY),
    ledgerRow('SARA', 'sale', 4.2, NOW - 70 * DAY),
    ledgerRow('SARA', 'sale', 4.2, NOW - 10 * DAY),
  ];
  const payouts = [{ creatorId: 'SARA', amountUsd: 5 }];
  const t = C.creatorTotals({ creators, ledger, payouts, nowMs: NOW }).rows[0];
  assert.strictEqual(t.sales, 3);
  assert.strictEqual(t.earnedCents, 1260);
  assert.strictEqual(t.waitingCents, 420);
  assert.strictEqual(t.paidCents, 500);
  assert.strictEqual(t.owedCents, 340);
  assert.strictEqual(t.unpaidCents, 760);
  assert.strictEqual(t.sales30, 1);
});

test('a refund comes off the bucket of the sale it refunds, whatever its sign', () => {
  const creators = [{ id: 'SARA' }];
  const ledger = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 90 * DAY, { transactionId: 'OLD' }),
    ledgerRow('SARA', 'sale', 4.2, NOW - 10 * DAY, { transactionId: 'NEW' }),
    // The webhook writes refunds negative; an unsigned one must count the same.
    ledgerRow('SARA', 'refund', -4.2, NOW - 5 * DAY, { transactionId: 'OLD' }),
  ];
  const a = C.creatorTotals({ creators, ledger, payouts: [], nowMs: NOW }).rows[0];
  assert.strictEqual(a.earnedCents, 420);
  assert.strictEqual(a.owedCents, 0, 'the refunded sale was the old one');
  assert.strictEqual(a.waitingCents, 420);
  assert.strictEqual(a.refunds, 1);
  const unsigned = ledger.slice(0, 2).concat([ledgerRow('SARA', 'refund', 4.2, NOW - 5 * DAY, { transactionId: 'OLD' })]);
  assert.deepStrictEqual(C.creatorTotals({ creators, ledger: unsigned, payouts: [], nowMs: NOW }).rows[0].earnedCents, 420);
});

test('a refund after a payment leaves nothing owed now and comes off the next payment', () => {
  const creators = [{ id: 'SARA' }];
  const sales = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 100 * DAY, { transactionId: 'A' }),
    ledgerRow('SARA', 'sale', 4.2, NOW - 95 * DAY, { transactionId: 'B' }),
  ];
  const paid = [{ creatorId: 'SARA', amountUsd: 8.4 }];
  const refunded = sales.concat([ledgerRow('SARA', 'refund', -4.2, NOW - 2 * DAY, { transactionId: 'A' })]);
  const now = C.creatorTotals({ creators, ledger: refunded, payouts: paid, nowMs: NOW }).rows[0];
  assert.strictEqual(now.owedCents, 0, 'never below zero');
  assert.strictEqual(now.unpaidCents, 0);
  // A new sale matures: the refund is taken off it.
  const later = refunded.concat([ledgerRow('SARA', 'sale', 4.2, NOW - 61 * DAY, { transactionId: 'C' })]);
  assert.strictEqual(C.creatorTotals({ creators, ledger: later, payouts: paid, nowMs: NOW }).rows[0].owedCents, 0);
  const twoMore = later.concat([ledgerRow('SARA', 'sale', 4.2, NOW - 62 * DAY, { transactionId: 'D' })]);
  assert.strictEqual(C.creatorTotals({ creators, ledger: twoMore, payouts: paid, nowMs: NOW }).rows[0].owedCents, 420);
});

test('sandbox rows, rows needing review and rows for no known creator stay out of the money', () => {
  const creators = [{ id: 'SARA' }, { id: 'FAJR10' }];
  const ledger = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 90 * DAY),
    ledgerRow('SARA', 'sale', 4.2, NOW - 90 * DAY, { environment: 'SANDBOX' }),
    ledgerRow('SARA', 'sale', null, NOW - 90 * DAY, { needsReview: true }),
    ledgerRow(null, 'sale', null, NOW - 90 * DAY, { offerRef: 'creator-ghost', needsReview: true }),
  ];
  const sums = C.creatorTotals({ creators, ledger, payouts: [], nowMs: NOW });
  const sara = sums.rows.find((r) => r.id === 'SARA');
  assert.strictEqual(sara.earnedCents, 420);
  assert.strictEqual(sara.needsReview, 1);
  assert.strictEqual(sara.sales, 2);
  assert.strictEqual(sums.sandboxRows, 1);
  assert.deepStrictEqual(sums.orphans, { rows: 1, offerRefs: ['creator-ghost'] });
  assert.strictEqual(sums.totals.owedCents, 420);
  assert.strictEqual(sums.rows.find((r) => r.id === 'FAJR10').earnedCents, 0);
});

test('offers in use counts every creator with an Apple offer, active here or not', () => {
  assert.strictEqual(C.offersInUse([{ appleOfferCodeId: 'a' }, { appleOfferCodeId: 'b', active: false }, { appleOfferCodeId: null }]), 2);
});

// ---- App Store Connect request bodies ------------------------------------------------

test('the offer request names the product, the offer, who may use it, and one price per territory', () => {
  const req = C.buildOfferCodeRequest({
    iapId: '6814748258',
    offerRef: 'creator-sara',
    prices: [{ territory: 'USA', pricePointId: 'P-USA' }, { territory: 'BHR', pricePointId: 'P-BHR' }],
  });
  assert.strictEqual(req.method, 'POST');
  assert.strictEqual(req.path, '/v1/inAppPurchaseOfferCodes');
  assert.deepStrictEqual(req.body, {
    data: {
      type: 'inAppPurchaseOfferCodes',
      attributes: { name: 'creator-sara', customerEligibilities: ['NON_SPENDER'] },
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: '6814748258' } },
        prices: {
          data: [
            { type: 'inAppPurchaseOfferPrices', id: '${price-USA}' },
            { type: 'inAppPurchaseOfferPrices', id: '${price-BHR}' },
          ],
        },
      },
    },
    included: [
      {
        type: 'inAppPurchaseOfferPrices',
        id: '${price-USA}',
        relationships: {
          territory: { data: { type: 'territories', id: 'USA' } },
          pricePoint: { data: { type: 'inAppPurchasePricePoints', id: 'P-USA' } },
        },
      },
      {
        type: 'inAppPurchaseOfferPrices',
        id: '${price-BHR}',
        relationships: {
          territory: { data: { type: 'territories', id: 'BHR' } },
          pricePoint: { data: { type: 'inAppPurchasePricePoints', id: 'P-BHR' } },
        },
      },
    ],
  });
});

test('the custom code request carries the code, the uses and the end day, under the offer', () => {
  const req = C.buildCustomCodeRequest({ offerCodeId: 'OFFER1', code: 'SARA', usesAllowed: 1000, expirationDate: '2027-03-22' });
  assert.strictEqual(req.path, '/v1/inAppPurchaseOfferCodeCustomCodes');
  assert.deepStrictEqual(req.body, {
    data: {
      type: 'inAppPurchaseOfferCodeCustomCodes',
      attributes: { customCode: 'SARA', numberOfCodes: 1000, expirationDate: '2027-03-22' },
      relationships: { offerCode: { data: { type: 'inAppPurchaseOfferCodes', id: 'OFFER1' } } },
    },
  });
});

// Shapes as App Store Connect answered them on 2026-09-22 (read-only GETs).
const usPoints = [
  { type: 'inAppPurchasePricePoints', id: 'P0', attributes: { customerPrice: '0.0', proceeds: '0.0' }, relationships: { territory: { data: { type: 'territories', id: 'USA' } } } },
  { type: 'inAppPurchasePricePoints', id: 'P2395', attributes: { customerPrice: '23.95', proceeds: '16.77' }, relationships: { territory: { data: { type: 'territories', id: 'USA' } } } },
  { type: 'inAppPurchasePricePoints', id: 'P2399', attributes: { customerPrice: '23.99', proceeds: '16.8' }, relationships: { territory: { data: { type: 'territories', id: 'USA' } } } },
];

test('the US point is the one whose price is exactly the buyer price', () => {
  assert.deepStrictEqual(C.pickUsPricePoint(usPoints, 2399), { id: 'P2399', customerPrice: '23.99', proceeds: '16.8' });
  assert.strictEqual(C.pickUsPricePoint(usPoints, 2349), null);
});

// ---- A true percent in every country ---------------------------------------------

test('each country pays at least the promised percent off its own price, never less', () => {
  // 2026-09-25, read from App Store Connect: the US $23.99 converts to
  // SAR 99.99, AED 99.99, $24.99 in Bahrain and QAR 89.99, which is 23%,
  // 17%, 17% and 10% off. Each country's own list has the true 20%.
  const pt = (id, price) => ({ id, cents: C.toCents(price), customerPrice: price.toFixed(2) });
  const regular = new Map([['USA', 2999], ['SAU', 12999], ['ARE', 11999], ['BHR', 2999], ['QAT', 9999], ['JPN', 450000], ['NOR', 34900]]);
  const candidates = new Map([
    ['USA', [pt('U2349', 23.49), pt('U2399', 23.99), pt('U2449', 24.49)]],
    ['SAU', [pt('S9999', 99.99), pt('S10399', 103.99), pt('S10999', 109.99)]],
    ['ARE', [pt('A8999', 89.99), pt('A9999', 99.99)]],
    ['BHR', [pt('B2399', 23.99), pt('B2499', 24.99)]],
    ['QAT', [pt('Q7999', 79.99), pt('Q8999', 89.99)]],
    ['JPN', [pt('J3800', 3800), pt('J3600', 3600)]],
    ['NOR', [pt('N299', 299)]],
  ]);
  const { prices, dropped } = C.truePercentPrices({
    regular,
    candidates,
    currencies: { SAU: 'SAR', ARE: 'AED', QAT: 'QAR', JPN: 'JPY', NOR: 'NOK' },
    discountPercent: 20,
    availableTerritories: ['SAU', 'QAT', 'USA', 'ARE', 'BHR', 'JPN', 'NOR', 'ISL'],
  });
  assert.deepStrictEqual(prices.map((p) => p.territory), ['USA', 'ARE', 'BHR', 'JPN', 'QAT', 'SAU']);
  const by = Object.fromEntries(prices.map((p) => [p.territory, p]));
  assert.strictEqual(by.USA.pricePointId, 'U2399');
  assert.strictEqual(by.SAU.pricePointId, 'S10399', 'SAR 103.99 is 20% off 129.99; the converted 99.99 would be 23%');
  assert.strictEqual(by.QAT.pricePointId, 'Q7999', 'QAR 79.99, never the 89.99 that is only 10% off');
  assert.strictEqual(by.BHR.pricePointId, 'B2399', '$24.99 would be only 16% off $29.99');
  // No AED point between 89.99 and 95.99 here, so the UAE gets more off, not less.
  assert.strictEqual(by.ARE.pricePointId, 'A8999');
  assert.strictEqual(by.ARE.percentOff, 25);
  // Whole-yen prices: 20% off 4,500 is 3,600 exactly.
  assert.strictEqual(by.JPN.pricePointId, 'J3600');
  assert.deepStrictEqual(by.SAU, { territory: 'SAU', pricePointId: 'S10399', customerPrice: '103.99', currency: 'SAR', regularCents: 12999, percentOff: 20 });
  for (const p of prices) assert.ok(p.percentOff >= 20, p.territory + ' gets only ' + p.percentOff + '%');
  // NOR: its only point is 299, above 20% off 349. ISL: no price at all. Both left out.
  assert.deepStrictEqual(dropped, ['ISL', 'NOR']);
});

test('without a known territory list, every territory with a regular price is priced', () => {
  const regular = new Map([['USA', 2999], ['DEU', 2999]]);
  const candidates = new Map([['USA', [{ id: 'U', cents: 2399, customerPrice: '23.99' }]], ['DEU', [{ id: 'D', cents: 2399, customerPrice: '23.99' }]]]);
  const { prices, dropped } = C.truePercentPrices({ regular, candidates, currencies: {}, discountPercent: 20, availableTerritories: null });
  assert.deepStrictEqual(prices.map((p) => p.territory), ['USA', 'DEU']);
  assert.deepStrictEqual(dropped, []);
});

test('prices in force: one per territory, the latest started, ended ones skipped', () => {
  const row = (id, territory, point, startDate, endDate) => ({
    id, attributes: { startDate, endDate },
    relationships: { territory: { data: { id: territory } }, inAppPurchasePricePoint: { data: { id: point } } },
  });
  const included = [
    { type: 'inAppPurchasePricePoints', id: 'P1', attributes: { customerPrice: '129.99' } },
    { type: 'inAppPurchasePricePoints', id: 'P2', attributes: { customerPrice: '149.99' } },
    { type: 'inAppPurchasePricePoints', id: 'P3', attributes: { customerPrice: '29.99' } },
  ];
  const prices = [
    row('a', 'SAU', 'P1', null, '2026-10-01'),
    row('b', 'SAU', 'P2', '2026-10-01', null),
    row('c', 'BHR', 'P3', null, null),
    { id: 'd', attributes: {}, relationships: { inAppPurchasePricePoint: { data: { id: 'P3' } } } },
  ];
  const before = C.pricesInForce({ prices, included, todayKey: '2026-09-25' });
  assert.deepStrictEqual([...before], [['SAU', 12999], ['BHR', 2999]]);
  const after = C.pricesInForce({ prices, included, todayKey: '2026-10-01' });
  assert.strictEqual(after.get('SAU'), 14999);
});

test('a payment made before the 60 days comes off waiting, so paid, owed and waiting add up to earned', () => {
  const creators = [{ id: 'SARA' }];
  const ledger = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 70 * DAY),
    ledgerRow('SARA', 'sale', 4.2, NOW - 10 * DAY),
    ledgerRow('SARA', 'sale', 4.2, NOW - 5 * DAY),
  ];
  // Aziz paid $6 early: more than the $4.20 that is 60 days old.
  const t = C.creatorTotals({ creators, ledger, payouts: [{ creatorId: 'SARA', amountUsd: 6 }], nowMs: NOW }).rows[0];
  assert.strictEqual(t.earnedCents, 1260);
  assert.strictEqual(t.owedCents, 0);
  assert.strictEqual(t.waitingCents, 660, 'the $1.80 paid early is not shown as still waiting');
  assert.strictEqual(t.paidCents + t.owedCents + t.waitingCents, t.earnedCents);
});

test('a refund of a young sale never leaves more owed than is unpaid', () => {
  const creators = [{ id: 'SARA' }];
  const ledger = [
    ledgerRow('SARA', 'sale', 4.2, NOW - 80 * DAY, { transactionId: 'OLD' }),
    // A refund for a sale the ledger never saw ages from its own date.
    ledgerRow('SARA', 'refund', -4.2, NOW - 3 * DAY, { transactionId: 'UNSEEN' }),
  ];
  const t = C.creatorTotals({ creators, ledger, payouts: [], nowMs: NOW }).rows[0];
  assert.strictEqual(t.earnedCents, 0);
  assert.strictEqual(t.owedCents, 0, 'the $4.20 matured, but the refund took it back');
  assert.strictEqual(t.waitingCents, 0);
});

// ---- What Apple charges today --------------------------------------------------------

function manual(entries) {
  return {
    prices: entries.map((e, i) => ({
      id: 'MP' + i,
      attributes: { startDate: e.start || null, endDate: e.end || null },
      relationships: {
        territory: { data: { type: 'territories', id: e.territory || 'USA' } },
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: 'PP' + i } },
      },
    })),
    included: entries.map((e, i) => ({ type: 'inAppPurchasePricePoints', id: 'PP' + i, attributes: { customerPrice: e.price } })),
  };
}

test('today\'s US price is the one whose dates cover today, a scheduled change included', () => {
  // One open price, the shape Apple answered with on 2026-09-24.
  assert.strictEqual(C.currentUsPriceCents({ ...manual([{ price: '29.99' }]), todayKey: '2026-09-24' }), 2999);
  // A change scheduled for 1 October: $29.99 until then, $39.99 from then.
  const scheduled = manual([{ price: '29.99', end: '2026-10-01' }, { price: '39.99', start: '2026-10-01' }]);
  assert.strictEqual(C.currentUsPriceCents({ ...scheduled, todayKey: '2026-09-30' }), 2999);
  assert.strictEqual(C.currentUsPriceCents({ ...scheduled, todayKey: '2026-10-01' }), 3999);
  // Other territories and a price with no point are ignored; nothing covering today is null.
  assert.strictEqual(C.currentUsPriceCents({ ...manual([{ price: '99.99', territory: 'SAU' }]), todayKey: '2026-09-24' }), null);
  assert.strictEqual(C.currentUsPriceCents({ prices: manual([{ price: '29.99' }]).prices, included: [], todayKey: '2026-09-24' }), null);
  assert.strictEqual(C.currentUsPriceCents({ ...manual([{ price: '29.99', start: '2026-12-01' }]), todayKey: '2026-09-24' }), null);
});
