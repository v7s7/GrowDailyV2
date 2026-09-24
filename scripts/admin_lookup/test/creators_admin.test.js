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
 * and how each POST answers.
 */
function fakeAsc({ states = {}, offers = {}, offerPrices = {}, customCodes = {}, postAnswers = [], configOk = true } = {}) {
  const posts = [];
  const gets = [];
  const iapOf = (productId) => C.PRODUCTS[productId].iapId;
  const byIap = {};
  for (const p of Object.values(C.PRODUCTS)) {
    byIap[p.iapId] = { state: states[p.productId] || 'APPROVED', offers: offers[p.productId] || [] };
  }
  function answer(path, query) {
    gets.push({ path, query });
    let m;
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)$/))) return { data: { id: m[1], attributes: { state: byIap[m[1]].state } } };
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/offerCodes$/))) {
      return { data: byIap[m[1]].offers.map((o) => ({ id: o.id, type: 'inAppPurchaseOfferCodes', attributes: { name: o.name, active: o.active !== false } })), included: [] };
    }
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/pricePoints$/))) {
      assert.strictEqual(query['filter[territory]'], 'USA');
      return {
        data: [2349, 2399, 2449].map((cents) => ({
          id: 'US-' + m[1] + '-' + cents,
          attributes: { customerPrice: (cents / 100).toFixed(2), proceeds: (Math.round(0.7 * (cents + 1)) / 100).toFixed(2) },
          relationships: { territory: { data: { type: 'territories', id: 'USA' } } },
        })),
        included: [],
      };
    }
    if ((m = path.match(/^\/v1\/inAppPurchasePricePoints\/(.+)\/equalizations$/))) {
      return {
        data: ['BHR', 'SAU', 'ARE', 'XXX'].map((t) => ({ id: 'EQ-' + t, attributes: { customerPrice: t === 'SAU' ? '99.99' : '24.99' }, relationships: { territory: { data: { type: 'territories', id: t } } } })),
        included: [{ type: 'territories', id: 'BHR', attributes: { currency: 'USD' } }, { type: 'territories', id: 'SAU', attributes: { currency: 'SAR' } }],
      };
    }
    if ((m = path.match(/^\/v2\/inAppPurchases\/(\d+)\/inAppPurchaseAvailability$/))) return { data: { id: m[1], type: 'inAppPurchaseAvailabilities' } };
    if ((m = path.match(/^\/v1\/inAppPurchaseAvailabilities\/(\d+)\/availableTerritories$/))) {
      return { data: ['USA', 'BHR', 'SAU', 'ARE'].map((id) => ({ id, type: 'territories' })), included: [] };
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
  // US first, then the equalized territories the product is sold in (XXX is not).
  assert.deepStrictEqual(offer.body.included.map((x) => x.relationships.territory.data.id), ['USA', 'BHR', 'SAU', 'ARE']);
  assert.strictEqual(offer.body.included[0].relationships.pricePoint.data.id, 'US-6814748258-2399');
  assert.strictEqual(code.path, '/v1/inAppPurchaseOfferCodeCustomCodes');
  assert.deepStrictEqual(code.body.data.attributes, { customCode: 'SARA', numberOfCodes: 1000, expirationDate: '2027-03-22' });
  assert.strictEqual(p.summary.usPrice, '$23.99');
  assert.strictEqual(p.summary.usProceeds, '16.80');
  assert.strictEqual(p.summary.territories, 4);
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
