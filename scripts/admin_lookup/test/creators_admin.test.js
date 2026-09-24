'use strict';

/**
 * The Creators page's writes and its two-step Apple code
 * (lib/creators_admin.js), against the in-memory Firestore in test/support
 * and a fake App Store Connect that answers the way the real one did on
 * 2026-09-22 and records every POST it is sent. Nothing here reaches Apple.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const Admin = require('../lib/creators_admin');
const C = require('../lib/creators');
const { AscApiError } = require('../lib/asc_client');
const { fakeDb, Timestamp, FieldValue, FakeTimestamp } = require('./support/fake_firestore');

const deps = { Timestamp, FieldValue };
const NOW = Date.UTC(2026, 8, 22, 9, 0);
const DAY = C.DAY_MS;

const sara = {
  name: 'Sara',
  code: 'SARA',
  discountPercent: 20,
  discountOff: 'growdaily_lifetime_offer',
  sharePercent: 25,
  codeEndsOn: '2027-03-22',
  usesAllowed: 1000,
};

/**
 * A fake App Store Connect. [state] per product, the offers already there,
 * what each product sells for in the US today ([usPrices], in cents; the
 * plan's prices unless a test says otherwise, null for "Apple lists no
 * price"), and how each POST answers.
 */
/**
 * Lifetime's regular price outside the US, as Apple's automatic prices had
 * it on 2026-09-25, plus DEU and ISL (whose list has no point low enough,
 * so it is left out).
 */
const REGULAR = { BHR: [2999, 'USD'], SAU: [12999, 'SAR'], ARE: [11999, 'AED'], QAT: [9999, 'QAR'], DEU: [2999, 'EUR'], ISL: [449900, 'ISK'] };
/** Each territory's own price points, around a true 20% off (the Gulf ones as read 2026-09-25). */
const POINTS = {
  BHR: [2299, 2399, 2499, 2999],
  SAU: [8999, 9999, 10399, 10999, 11999, 12999],
  ARE: [7999, 8999, 9599, 9999, 11999],
  QAT: [6999, 7999, 8999, 9999],
  DEU: [1799, 2349, 2399, 2449],
  ISL: [],
};

function fakeAsc({ states = {}, offers = {}, offerPrices = {}, customCodes = {}, postAnswers = [], configOk = true, usPrices = {} } = {}) {
  const posts = [];
  const gets = [];
  const iapOf = (productId) => C.PRODUCTS[productId].iapId;
  const byIap = {};
  for (const p of Object.values(C.PRODUCTS)) {
    const price = Object.prototype.hasOwnProperty.call(usPrices, p.productId) ? usPrices[p.productId] : Math.round(p.priceUsd * 100);
    byIap[p.iapId] = { state: states[p.productId] || 'APPROVED', offers: offers[p.productId] || [], usCents: price };
  }
  function answer(path, query) {
    gets.push({ path, query });
    let m;
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)$/))) return { data: { id: m[1], attributes: { state: byIap[m[1]].state } } };
    // An IAP's price schedule has the IAP's own id, as Apple's does.
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/iapPriceSchedule$/))) return { data: { id: m[1], type: 'inAppPurchasePriceSchedules' } };
    if ((m = path.match(/^\/v1\/inAppPurchasePriceSchedules\/(\d+)\/manualPrices$/))) {
      // Only the US price is set by hand; the rest are Apple's automatic ones.
      if (query['filter[territory]'] !== undefined) assert.strictEqual(query['filter[territory]'], 'USA');
      const cents = byIap[m[1]].usCents;
      if (cents === null) return { data: [], included: [] };
      return {
        data: [{
          id: 'MP-' + m[1], type: 'inAppPurchasePrices', attributes: { startDate: null, endDate: null, manual: true },
          relationships: { territory: { data: { type: 'territories', id: 'USA' } }, inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: 'PP-' + m[1] } } },
        }],
        included: [
          { type: 'inAppPurchasePricePoints', id: 'PP-' + m[1], attributes: { customerPrice: (cents / 100).toFixed(2), proceeds: '0' } },
          { type: 'territories', id: 'USA', attributes: { currency: 'USD' } },
        ],
      };
    }
    if ((m = path.match(/^\/v1\/inAppPurchasePriceSchedules\/(\d+)\/automaticPrices$/))) {
      const ts = Object.keys(REGULAR);
      return {
        data: ts.map((t) => ({
          id: 'AP-' + t, type: 'inAppPurchasePrices', attributes: { startDate: null, endDate: null, manual: false },
          relationships: { territory: { data: { type: 'territories', id: t } }, inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: 'RP-' + t } } },
        })),
        included: [
          ...ts.map((t) => ({ type: 'inAppPurchasePricePoints', id: 'RP-' + t, attributes: { customerPrice: (REGULAR[t][0] / 100).toFixed(2) } })),
          ...ts.map((t) => ({ type: 'territories', id: t, attributes: { currency: REGULAR[t][1] } })),
        ],
      };
    }
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/offerCodes$/))) {
      return { data: byIap[m[1]].offers.map((o) => ({ id: o.id, type: 'inAppPurchaseOfferCodes', attributes: { name: o.name, active: o.active !== false } })), included: [] };
    }
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/pricePoints$/))) {
      const t = query['filter[territory]'];
      if (t !== 'USA') {
        assert.ok(POINTS[t], 'asked for every price point of ' + t + ', which the product does not sell in here');
        return {
          data: POINTS[t].map((cents) => ({ id: 'PT-' + t + '-' + cents, attributes: { customerPrice: (cents / 100).toFixed(2) }, relationships: { territory: { data: { type: 'territories', id: t } } } })),
          included: [],
        };
      }
      return {
        data: [1799, 2349, 2399, 2449, 2699, 2799, 3199].map((cents) => ({
          id: 'US-' + m[1] + '-' + cents,
          attributes: { customerPrice: (cents / 100).toFixed(2), proceeds: (Math.round(0.7 * (cents + 1)) / 100).toFixed(2) },
          relationships: { territory: { data: { type: 'territories', id: 'USA' } } },
        })),
        included: [],
      };
    }
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/inAppPurchaseAvailability$/))) return { data: { id: m[1], type: 'inAppPurchaseAvailabilities' } };
    if ((m = path.match(/^\/v1\/inAppPurchaseAvailabilities\/(\d+)\/availableTerritories$/))) {
      return { data: ['USA', 'BHR', 'SAU', 'ARE', 'QAT', 'DEU', 'ISL'].map((id) => ({ id, type: 'territories' })), included: [] };
    }
    if ((m = path.match(/^\/v1\/inAppPurchaseOfferCodes\/(.+)\/prices$/))) {
      const cents = offerPrices[m[1]];
      return { data: [{ id: 'OP1' }], included: cents === undefined ? [] : [{ type: 'inAppPurchasePricePoints', id: 'PP', attributes: { customerPrice: (cents / 100).toFixed(2) } }] };
    }
    if ((m = path.match(/^\/v1\/inAppPurchaseOfferCodes\/(.+)\/customCodes$/))) {
      return { data: (customCodes[m[1]] || []).map((c) => ({ id: c.id, attributes: { customCode: c.code, active: c.active !== false } })), included: [] };
    }
    throw new Error('fake asc: no answer for GET ' + path);
  }
  return {
    posts,
    gets,
    iapOf,
    config: () => (configOk ? { ok: true, missing: [] } : { ok: false, missing: ['ASC_ISSUER_ID is not set'] }),
    get: async (path, query) => answer(path, query || {}),
    getAll: async (path, query) => {
      const r = answer(path, query || {});
      return { data: Array.isArray(r.data) ? r.data : [r.data], included: r.included || [] };
    },
    post: async (path, body) => {
      posts.push({ path, body });
      const next = postAnswers.shift();
      if (!next) throw new Error('fake asc: unexpected POST ' + path);
      if (next.error) throw new AscApiError(next.error, next.status || 409);
      return { data: { id: next.id } };
    },
  };
}

function creatorDoc(db, code) {
  return db.docs.get('creators/' + code);
}

// ---- The small writes ---------------------------------------------------------

test('adding a creator writes every field of the contract, with no Apple ids yet', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  const doc = creatorDoc(db, 'SARA');
  assert.deepStrictEqual(Object.keys(doc).sort(), [
    'active', 'appleCustomCodeId', 'appleOfferCodeId', 'code', 'codeEndsAt', 'createdAt', 'discountOff', 'discountPercent',
    'name', 'offerPriceUsd', 'offerRef', 'sharePercent', 'updatedAt', 'usesAllowed',
  ]);
  assert.strictEqual(doc.offerRef, 'creator-sara');
  assert.strictEqual(doc.offerPriceUsd, 23.99);
  assert.strictEqual(doc.active, true);
  assert.strictEqual(doc.appleOfferCodeId, null);
  assert.strictEqual(doc.appleCustomCodeId, null);
  assert.strictEqual(doc.codeEndsAt.toMillis(), C.pacificMidnightMs('2027-03-22'));
});

test('a taken code and a bad creator are refused, writing nothing', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  const writes = db.state.writes;
  await assert.rejects(() => Admin.addCreator(db, deps, { ...sara, name: 'Other' }, NOW), (e) => e.status === 409 && /already Sara's/.test(e.message));
  await assert.rejects(() => Admin.addCreator(db, deps, { ...sara, code: 'NEW1', discountPercent: 95 }, NOW), Admin.CreatorsInputError);
  assert.strictEqual(db.state.writes, writes);
});

test('share and active change one field each; an unknown creator is a 404', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  assert.deepStrictEqual(await Admin.setShare(db, deps, { code: 'sara', sharePercent: 30 }), { changed: true });
  assert.strictEqual(creatorDoc(db, 'SARA').sharePercent, 30);
  assert.deepStrictEqual(await Admin.setShare(db, deps, { code: 'SARA', sharePercent: 30 }), { changed: false });
  await assert.rejects(() => Admin.setShare(db, deps, { code: 'SARA', sharePercent: 130 }), Admin.CreatorsInputError);
  await Admin.setActive(db, deps, { code: 'SARA', active: false });
  assert.strictEqual(creatorDoc(db, 'SARA').active, false);
  await assert.rejects(() => Admin.setActive(db, deps, { code: 'NOBODY', active: false }), (e) => e.status === 404);
  await assert.rejects(() => Admin.setActive(db, deps, { code: 'SARA', active: 'no' }), Admin.CreatorsInputError);
});

test('a payout is written with the contract fields, and one over the unpaid balance is refused', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  db.docs.set('creator_ledger/e1', { creatorId: 'SARA', kind: 'sale', shareUsd: 4.2, eventAtMs: NOW - 90 * DAY, environment: 'PRODUCTION', needsReview: false, transactionId: 't1' });
  db.docs.set('creator_ledger/e2', { creatorId: 'SARA', kind: 'sale', shareUsd: 4.2, eventAtMs: NOW - 5 * DAY, environment: 'PRODUCTION', needsReview: false, transactionId: 't2' });
  await assert.rejects(() => Admin.recordPayout(db, deps, { code: 'SARA', amountUsd: 8.41 }, NOW), /more than this creator has earned/);
  const r = await Admin.recordPayout(db, deps, { code: 'SARA', amountUsd: 4.2, note: 'Bank transfer' }, NOW);
  const row = db.docs.get('creator_payouts/' + r.id);
  assert.deepStrictEqual(Object.keys(row).sort(), ['amountUsd', 'createdAt', 'creatorId', 'note', 'paidAt']);
  assert.strictEqual(row.creatorId, 'SARA');
  assert.strictEqual(row.amountUsd, 4.2);
  assert.strictEqual(row.paidAt.toMillis(), NOW);
  const state = await Admin.readCreatorsState(db, { nowMs: NOW, ascConfig: { ok: true, missing: [] } });
  const money = state.creators[0].money;
  assert.strictEqual(money.paidCents, 420);
  assert.strictEqual(money.owedCents, 0);
  assert.strictEqual(money.waitingCents, 420);
  assert.strictEqual(state.totals.earnedCents, 840);
});

// ---- The Apple code: Preview ---------------------------------------------------------

test('Preview builds the exact requests and sends nothing that changes anything', async () => {
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc();
  const p = await Admin.previewAppleCode(db, asc, { input: sara }, NOW);
  assert.deepStrictEqual(p.blocked, []);
  assert.strictEqual(asc.posts.length, 0);
  assert.strictEqual(db.state.writes, 0, 'nothing is saved until Create');
  assert.strictEqual(p.requests.length, 2);
  const [offer, code] = p.requests;
  assert.strictEqual(offer.path, '/v1/inAppPurchaseOfferCodes');
  assert.strictEqual(offer.body.data.attributes.name, 'creator-sara');
  assert.deepStrictEqual(offer.body.data.attributes.customerEligibilities, ['NON_SPENDER']);
  assert.strictEqual(offer.body.data.relationships.inAppPurchase.data.id, '6814748258');
  // US first, then every territory the product sells in, each at a true
  // 20% off its own price (ISL's list has no price low enough).
  assert.deepStrictEqual(offer.body.included.map((x) => x.relationships.territory.data.id), ['USA', 'ARE', 'BHR', 'DEU', 'QAT', 'SAU']);
  const pointOf = (t) => offer.body.included.find((x) => x.relationships.territory.data.id === t).relationships.pricePoint.data.id;
  assert.strictEqual(pointOf('USA'), 'US-6814748258-2399');
  // SAR 103.99 from Saudi's own list, where a US $23.99 converts to SAR
  // 99.99; QAR 79.99, where it converts to QAR 89.99, only 10% off.
  assert.strictEqual(pointOf('SAU'), 'PT-SAU-10399');
  assert.strictEqual(pointOf('ARE'), 'PT-ARE-9599');
  assert.strictEqual(pointOf('QAT'), 'PT-QAT-7999');
  assert.strictEqual(pointOf('BHR'), 'PT-BHR-2399');
  assert.strictEqual(pointOf('DEU'), 'PT-DEU-2399');
  assert.deepStrictEqual(p.summary.dropped, ['ISL']);
  assert.strictEqual(p.summary.deeper, 0);
  const saudi = p.summary.sample.find((x) => x.territory === 'SAU');
  assert.deepStrictEqual(saudi, { territory: 'SAU', customerPrice: '103.99', currency: 'SAR', regularPrice: '129.99', percentOff: 20 });
  assert.strictEqual(code.path, '/v1/inAppPurchaseOfferCodeCustomCodes');
  assert.deepStrictEqual(code.body.data.attributes, { customCode: 'SARA', numberOfCodes: 1000, expirationDate: '2027-03-22' });
  assert.strictEqual(p.summary.usPrice, '$23.99');
  assert.strictEqual(p.summary.usProceeds, '16.80');
  assert.strictEqual(p.summary.territories, 6);
  assert.strictEqual(p.summary.offersLeftAfter, 9);
});

test('Preview is blocked while the product is not approved, saying why', async () => {
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ states: { growdaily_lifetime_offer: 'MISSING_METADATA' } });
  const p = await Admin.previewAppleCode(db, asc, { input: sara }, NOW);
  assert.strictEqual(p.blocked.length, 1);
  assert.match(p.blocked[0], /MISSING_METADATA, not APPROVED/);
  await assert.rejects(() => Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW), /MISSING_METADATA/);
  assert.strictEqual(asc.posts.length, 0);
  assert.strictEqual(db.state.writes, 0);
});

test('Preview is blocked when all 10 of Apple\'s offer slots are in use', async () => {
  const db = fakeDb({ nowMs: NOW });
  const ten = Array.from({ length: 10 }, (_, i) => ({ id: 'O' + i, name: 'creator-x' + i }));
  const p = await Admin.previewAppleCode(db, fakeAsc({ offers: { growdaily_lifetime: ten } }), { input: sara }, NOW);
  assert.match(p.blocked.join(' '), /All 10 of Apple's offer slots are in use/);
});

// Codes go on the regular Lifetime since Aziz kept it at $29.99 (2026-09-24).
const onRegular = { ...sara, discountOff: 'growdaily_lifetime' };

test('Preview refuses a code that is not a discount on what Apple charges today', async () => {
  // 20% off $29.99 is $23.99; were Apple selling Lifetime for $19.99, that
  // code would cost MORE than the price it claims to cut (the $31.99 case
  // measured on 2026-09-24 was the same mistake the other way round).
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ usPrices: { growdaily_lifetime: 1999 } });
  const p = await Admin.previewAppleCode(db, asc, { input: onRegular }, NOW);
  assert.strictEqual(p.summary.usPrice, '$23.99');
  assert.strictEqual(p.summary.usPriceToday, '$19.99');
  assert.match(p.blocked.join(' '), /sells growdaily_lifetime for \$19\.99 in the US today, so a code at \$23\.99 would not be a discount/);
  await assert.rejects(() => Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW), /would not be a discount/);
  assert.strictEqual(asc.posts.length, 0);
  assert.strictEqual(db.state.writes, 0);
});

test('Preview refuses a percent that Apple\'s price today does not bear out', async () => {
  // 2026-09-25: the tool still worked codes out from a planned $39.99 while
  // Apple sold Lifetime at $29.99, so a "30% off" code came to $27.99, only
  // 7% below the real price: a false discount claim. The tool's price must
  // now be Apple's, or nothing is made.
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ usPrices: { growdaily_lifetime: 3999 } });
  const p = await Admin.previewAppleCode(db, asc, { input: onRegular }, NOW);
  assert.match(p.blocked.join(' '), /works out 20% off from \$29\.99, but Apple sells growdaily_lifetime for \$39\.99 in the US today, so the code would not be 20% off/);
  await assert.rejects(() => Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW), /would not be 20% off/);
  assert.strictEqual(asc.posts.length, 0);
  assert.strictEqual(db.state.writes, 0);

  // When the tool and Apple agree, the same deal goes through at a true 20%.
  const agreed = await Admin.previewAppleCode(db, fakeAsc(), { input: onRegular }, NOW);
  assert.deepStrictEqual(agreed.blocked, []);
  assert.strictEqual(agreed.summary.usPriceToday, '$29.99');
  assert.strictEqual(agreed.summary.usPrice, '$23.99');
});

test('the default is the approved regular Lifetime at Apple\'s $29.99', () => {
  assert.strictEqual(C.DEFAULT_PRODUCT, 'growdaily_lifetime');
  assert.strictEqual(C.PRODUCTS.growdaily_lifetime.priceUsd, 29.99);
  const m = C.moneyPreview({ productId: C.DEFAULT_PRODUCT, discountPercent: 20, sharePercent: 25, keepRate: 0.7 });
  assert.strictEqual(C.money(m.buyerCents), '$23.99');
  assert.strictEqual(m.percentOffShown, 20);
});

test('Preview refuses when Apple lists no US price for today, rather than guess', async () => {
  const db = fakeDb({ nowMs: NOW });
  const p = await Admin.previewAppleCode(db, fakeAsc({ usPrices: { growdaily_lifetime_offer: null } }), { input: sara }, NOW);
  assert.match(p.blocked.join(' '), /did not say what growdaily_lifetime_offer costs in the US today/);
  assert.strictEqual(p.summary.usPriceToday, null);
});

test('a code on the regular Lifetime at or above a welcome price is allowed, with a warning', async () => {
  const db = fakeDb({ nowMs: NOW });
  // Only while a welcome price sits below Lifetime (none today: both are
  // $29.99). With one at $24.99, 10% off Lifetime is $26.99, above it.
  const welcome = { usPrices: { growdaily_lifetime: 2999, growdaily_lifetime_offer: 2499 } };
  const p = await Admin.previewAppleCode(db, fakeAsc(welcome), { input: { ...onRegular, discountPercent: 10 } }, NOW);
  assert.deepStrictEqual(p.blocked, []);
  assert.strictEqual(p.warnings.length, 1);
  assert.match(p.warnings[0], /first 72 hours/);
  // 20% off is $23.99, below that welcome price: nothing to warn about.
  const deeper = await Admin.previewAppleCode(db, fakeAsc(welcome), { input: onRegular }, NOW);
  assert.deepStrictEqual(deeper.warnings, []);
  // With no welcome price (today), the default deal never warns.
  const usual = await Admin.previewAppleCode(db, fakeAsc(), { input: onRegular }, NOW);
  assert.deepStrictEqual(usual.warnings, []);
});

test('without the App Store Connect settings, Preview names what is missing', async () => {
  const db = fakeDb({ nowMs: NOW });
  await assert.rejects(
    () => Admin.previewAppleCode(db, fakeAsc({ configOk: false }), { input: sara }, NOW),
    (e) => e instanceof Admin.CreatorsInputError && /ASC_ISSUER_ID is not set/.test(e.message) && e.ascMissing.length === 1,
  );
});

// ---- The Apple code: Create ------------------------------------------------------------

test('Create sends the previewed requests once and stores the ids Apple returned', async () => {
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ postAnswers: [{ id: 'OFFER-1' }, { id: 'CODE-1' }] });
  const p = await Admin.previewAppleCode(db, asc, { input: sara }, NOW);
  const r = await Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW + 1000);
  assert.strictEqual(r.ok, true);
  assert.deepStrictEqual(asc.posts.map((x) => x.path), ['/v1/inAppPurchaseOfferCodes', '/v1/inAppPurchaseOfferCodeCustomCodes']);
  assert.deepStrictEqual(asc.posts[0].body, p.requests[0].body, 'exactly the previewed offer');
  assert.strictEqual(asc.posts[1].body.data.relationships.offerCode.data.id, 'OFFER-1');
  const doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.appleOfferCodeId, 'OFFER-1');
  assert.strictEqual(doc.appleCustomCodeId, 'CODE-1');
  // A plan is used once: a second press sends nothing.
  await assert.rejects(() => Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW + 2000), /expired or was already used/);
  assert.strictEqual(asc.posts.length, 2);
});

test('when Apple refuses the offer, the creator is saved with no Apple ids', async () => {
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ postAnswers: [{ error: 'App Store Connect answered 409: ENTITY_ERROR' }] });
  const p = await Admin.previewAppleCode(db, asc, { input: sara }, NOW);
  const r = await Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.stage, 'offer');
  assert.match(r.message, /Saved Sara \(SARA\) in this tool\. Apple did not make the offer/);
  const doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.appleOfferCodeId, null);
  assert.strictEqual(doc.appleCustomCodeId, null);
});

test('when Apple makes the offer but refuses the code, only the offer id is kept, and a retry makes just the code', async () => {
  const db = fakeDb({ nowMs: NOW });
  const asc = fakeAsc({ postAnswers: [{ id: 'OFFER-1' }, { error: 'App Store Connect answered 409: not approved' }] });
  const p = await Admin.previewAppleCode(db, asc, { input: sara }, NOW);
  const r = await Admin.createAppleCode(db, deps, asc, { planId: p.planId }, NOW);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.stage, 'code');
  let doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.appleOfferCodeId, 'OFFER-1');
  assert.strictEqual(doc.appleCustomCodeId, null, 'no code is claimed');

  // Apple now lists the offer; the retry reuses it and makes only the code.
  const retryAsc = fakeAsc({
    offers: { growdaily_lifetime_offer: [{ id: 'OFFER-1', name: 'creator-sara' }] },
    offerPrices: { 'OFFER-1': 2399 },
    postAnswers: [{ id: 'CODE-1' }],
  });
  const again = await Admin.previewAppleCode(db, retryAsc, { code: 'SARA' }, NOW);
  assert.deepStrictEqual(again.blocked, []);
  assert.strictEqual(again.summary.offerStep, 'reuse');
  assert.deepStrictEqual(again.requests.map((x) => x.path), ['/v1/inAppPurchaseOfferCodeCustomCodes']);
  assert.strictEqual(again.requests[0].body.data.relationships.offerCode.data.id, 'OFFER-1');
  const done = await Admin.createAppleCode(db, deps, retryAsc, { planId: again.planId }, NOW);
  assert.strictEqual(done.ok, true);
  doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.appleCustomCodeId, 'CODE-1');
  assert.deepStrictEqual(retryAsc.posts.map((x) => x.path), ['/v1/inAppPurchaseOfferCodeCustomCodes']);
});

test('an offer Apple already holds under the same name is used, not made twice; a different price blocks it', async () => {
  const db = fakeDb({ nowMs: NOW });
  const same = await Admin.previewAppleCode(db, fakeAsc({
    offers: { growdaily_lifetime_offer: [{ id: 'OFFER-9', name: 'Creator-Sara' }] },
    offerPrices: { 'OFFER-9': 2399 },
    customCodes: { 'OFFER-9': [{ id: 'CODE-9', code: 'SARA' }] },
  }), { input: sara }, NOW);
  assert.deepStrictEqual(same.blocked, []);
  assert.strictEqual(same.summary.offerStep, 'reuse');
  assert.strictEqual(same.summary.codeStep, 'reuse');
  assert.deepStrictEqual(same.requests, [], 'both already exist: nothing to send, only to record');

  const pricey = await Admin.previewAppleCode(db, fakeAsc({
    offers: { growdaily_lifetime_offer: [{ id: 'OFFER-9', name: 'creator-sara' }] },
    offerPrices: { 'OFFER-9': 2449 },
  }), { input: sara }, NOW);
  assert.match(pricey.blocked.join(' '), /sells at \$24\.49 in the US; this creator's deal says \$23\.99/);
});

test('a creator that already has its code, or is inactive, cannot preview another', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  await Admin.setActive(db, deps, { code: 'SARA', active: false });
  await assert.rejects(() => Admin.previewAppleCode(db, fakeAsc(), { code: 'SARA' }, NOW), /inactive/);
  await Admin.setActive(db, deps, { code: 'SARA', active: true });
  db.docs.set('creators/SARA', { ...creatorDoc(db, 'SARA'), appleOfferCodeId: 'O', appleCustomCodeId: 'C' });
  await assert.rejects(() => Admin.previewAppleCode(db, fakeAsc(), { code: 'SARA' }, NOW), /already has its Apple code/);
});

test('reading the page: tiles, per-creator money and what matches no creator', async () => {
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  db.docs.set('creators/SARA', { ...creatorDoc(db, 'SARA'), appleOfferCodeId: 'O1', appleCustomCodeId: 'C1' });
  db.docs.set('creator_ledger/e1', { creatorId: 'SARA', offerRef: 'creator-sara', kind: 'sale', shareUsd: 4.2, eventAtMs: NOW - 10 * DAY, environment: 'PRODUCTION', needsReview: false, transactionId: 't1' });
  db.docs.set('creator_ledger/e2', { creatorId: null, offerRef: 'creator-ghost', kind: 'sale', shareUsd: null, eventAtMs: NOW - 10 * DAY, environment: 'PRODUCTION', needsReview: true, transactionId: 't2' });
  const s = await Admin.readCreatorsState(db, { nowMs: NOW, ascConfig: { ok: false, missing: ['ASC_KEY_ID is not set'] } });
  assert.strictEqual(s.offersInUse, 1);
  assert.strictEqual(s.maxOffers, 10);
  assert.strictEqual(s.totals.sales30, 1);
  assert.strictEqual(s.totals.waitingCents, 420);
  assert.deepStrictEqual(s.orphans, { rows: 1, offerRefs: ['creator-ghost'] });
  assert.deepStrictEqual(s.asc, { ok: false, missing: ['ASC_KEY_ID is not set'] });
  assert.strictEqual(s.creators[0].codeEndsOn, '2027-03-22');
  assert.ok(s.creators[0].codeEndsAtMs > NOW);
  assert.ok(creatorDoc(db, 'SARA').codeEndsAt instanceof FakeTimestamp);
});

// ---- The statement link ----------------------------------------------------------------

test('a statement link stores only the key\'s hash, and a new link retires the old one', async () => {
  const crypto = require('node:crypto');
  const db = fakeDb({ nowMs: NOW });
  await Admin.addCreator(db, deps, sara, NOW);
  const keys = ['A'.repeat(43), 'B'.repeat(43)];
  const first = await Admin.makeStatementLink(db, deps, { code: 'sara' }, { randomKey: () => keys[0] });
  assert.strictEqual(first.code, 'SARA');
  assert.strictEqual(first.link, 'https://grow-daily-339ef.web.app/creator/#k=' + keys[0]);
  let doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.statementKeyHash, crypto.createHash('sha256').update(keys[0]).digest('hex'));
  assert.ok(!JSON.stringify(doc).includes(keys[0]), 'the key itself is never stored');

  const second = await Admin.makeStatementLink(db, deps, { code: 'SARA' }, { randomKey: () => keys[1] });
  doc = creatorDoc(db, 'SARA');
  assert.strictEqual(doc.statementKeyHash, Admin.statementKeyHash(keys[1]));
  assert.notStrictEqual(second.link, first.link);

  // The page learns that a link exists and when, never the hash.
  const s = await Admin.readCreatorsState(db, { nowMs: NOW, ascConfig: { ok: true, missing: [] } });
  assert.strictEqual(s.creators[0].hasStatementLink, true);
  assert.ok(!JSON.stringify(s).includes(doc.statementKeyHash));

  await assert.rejects(() => Admin.makeStatementLink(db, deps, { code: 'NOBODY' }), (e) => e.status === 404);
});

test('a real statement key is 43 base64url characters and never repeats', () => {
  const seen = new Set();
  for (let i = 0; i < 200; i++) {
    const k = Admin.newStatementKey();
    assert.match(k, /^[A-Za-z0-9_-]{43}$/);
    seen.add(k);
  }
  assert.strictEqual(seen.size, 200);
});
