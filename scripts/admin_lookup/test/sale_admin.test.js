'use strict';

/**
 * The Sale page's writes (lib/sale_admin.js), against the in-memory
 * Firestore in test/support: what each action writes to offers/live and
 * offer_sales, that a refused action writes nothing, and what the page
 * reads back.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const Sale = require('../lib/sale_admin');
const R = require('../lib/sale_rules');
const { fakeDb, Timestamp, FieldValue, FakeTimestamp } = require('./support/fake_firestore');

const deps = { Timestamp, FieldValue };
const at = (date, time = '00:00') => R.bahrainMs(date, time);

function live(db) {
  return db.docs.get(Sale.LIVE_DOC);
}

function salesIn(db) {
  return [...db.docs.entries()].filter(([p]) => p.startsWith(Sale.SALES + '/')).map(([p, d]) => ({ id: p.split('/')[1], ...d }));
}

const ramadan = { nameAr: 'عرض رمضان', nameEn: 'Ramadan sale', startDate: '2027-02-27', startTime: '00:00', endDate: '2027-03-09', endTime: '23:59' };

test('an empty project reads as the app\'s own fallback: welcome on for 72 hours, no sale, no full-price day', async () => {
  const db = fakeDb();
  const s = await Sale.readSaleState(db, { nowMs: at('2027-02-20'), Timestamp });
  assert.deepStrictEqual(s.live.welcome, { enabled: true, hours: 72 });
  assert.strictEqual(s.live.sale, null);
  assert.strictEqual(s.status.state, 'none');
  assert.strictEqual(s.status.fullPriceSet, false);
  assert.strictEqual(s.meter.total, 0);
  assert.strictEqual(s.windowsOpen, 0);
  assert.deepStrictEqual(s.facts, { fullPriceUsd: 39.99, offerPriceUsd: 29.99, percentOff: 25 });
});

test('the welcome card writes the whole document, every field present', async () => {
  const db = fakeDb();
  const r = await Sale.saveWelcome(db, deps, { enabled: false, hours: 48 });
  assert.strictEqual(r.changed, true);
  const doc = live(db);
  assert.deepStrictEqual(Object.keys(doc).sort(), ['fullPriceSince', 'sale', 'updatedAt', 'welcome']);
  assert.deepStrictEqual(doc.welcome, { enabled: false, hours: 48 });
  assert.strictEqual(doc.sale, null);
  assert.strictEqual(doc.fullPriceSince, null);
  assert.ok(doc.updatedAt instanceof FakeTimestamp);
  assert.strictEqual((await Sale.saveWelcome(db, deps, { enabled: false, hours: 48 })).changed, false);
});

test('a refused welcome writes nothing', async () => {
  const db = fakeDb();
  await assert.rejects(() => Sale.saveWelcome(db, deps, { enabled: true, hours: 200 }), Sale.SaleInputError);
  assert.strictEqual(db.state.writes, 0);
});

test('fullPriceSince is stored as 00:00 Bahrain on that day, and a future day is refused', async () => {
  const db = fakeDb();
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  assert.strictEqual(live(db).fullPriceSince.toMillis(), at('2027-01-01'));
  await assert.rejects(() => Sale.setFullPriceSince(db, deps, { date: '2027-03-01' }, at('2027-02-20')), /in the future/);
  assert.strictEqual(live(db).fullPriceSince.toMillis(), at('2027-01-01'));
});

test('scheduling is refused until fullPriceSince is set, and nothing is written', async () => {
  const db = fakeDb();
  await assert.rejects(
    () => Sale.scheduleSale(db, deps, ramadan, at('2027-02-20')),
    (e) => e instanceof Sale.SaleInputError && e.errors.some((x) => x.code === 'no-full-price-since'),
  );
  assert.strictEqual(db.state.writes, 0);
});

test('a scheduled sale is one offer_sales record and the same sale in offers/live', async () => {
  const db = fakeDb();
  await Sale.saveWelcome(db, deps, { enabled: true, hours: 72 });
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  const { id } = await Sale.scheduleSale(db, deps, ramadan, at('2027-02-20'));
  const [record] = salesIn(db);
  assert.strictEqual(record.id, id);
  assert.deepStrictEqual(Object.keys(record).sort(), ['createdAt', 'endsAt', 'id', 'nameAr', 'nameEn', 'startsAt']);
  assert.strictEqual(record.startsAt.toMillis(), at('2027-02-27', '00:00'));
  assert.strictEqual(record.endsAt.toMillis(), at('2027-03-09', '23:59'));
  const doc = live(db);
  assert.deepStrictEqual(Object.keys(doc.sale).sort(), ['endsAt', 'id', 'nameAr', 'nameEn', 'startsAt']);
  assert.strictEqual(doc.sale.id, id);
  assert.strictEqual(doc.sale.nameAr, 'عرض رمضان');
  assert.strictEqual(doc.sale.startsAt.toMillis(), at('2027-02-27'));
  assert.deepStrictEqual(doc.welcome, { enabled: true, hours: 72 }, 'the welcome settings survive');
  assert.strictEqual(doc.fullPriceSince.toMillis(), at('2027-01-01'));
  // Saving the welcome card again keeps the sale: the whole document is rewritten from what it holds.
  await Sale.saveWelcome(db, deps, { enabled: true, hours: 96 });
  assert.strictEqual(live(db).sale.id, id);
});

test('what the form alone gets wrong is refused before any transaction opens', async () => {
  const db = fakeDb();
  await assert.rejects(
    () => Sale.scheduleSale(db, deps, { ...ramadan, nameAr: '', endDate: '2027-02-26' }, at('2027-02-20')),
    (e) => e.errors.map((x) => x.code).sort().join(',') === 'end-before-start,names',
  );
  await assert.rejects(() => Sale.setFullPriceSince(db, deps, { date: '2027-02-30' }, at('2027-02-20')), /real date/);
  assert.strictEqual(db.state.transactions, 0);
  assert.strictEqual(db.state.writes, 0);
});

test('a second sale is refused while one is scheduled, with the reason, and writes nothing', async () => {
  const db = fakeDb();
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  await Sale.scheduleSale(db, deps, ramadan, at('2027-02-20'));
  const before = db.state.writes;
  await assert.rejects(
    () => Sale.scheduleSale(db, deps, { ...ramadan, startDate: '2027-06-01', endDate: '2027-06-05' }, at('2027-02-21')),
    (e) => e.errors.some((x) => x.code === 'one-at-a-time'),
  );
  assert.strictEqual(db.state.writes, before);
});

test('ending the running sale sets endsAt to now in both places', async () => {
  const db = fakeDb();
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  const { id } = await Sale.scheduleSale(db, deps, ramadan, at('2027-02-20'));
  const now = at('2027-03-02', '15:30');
  assert.deepStrictEqual(await Sale.endSale(db, deps, { id }, now), { result: 'ended' });
  const [record] = salesIn(db);
  assert.strictEqual(record.endsAt.toMillis(), now);
  assert.strictEqual(record.endedEarlyAt.toMillis(), now);
  assert.strictEqual(live(db).sale.endsAt.toMillis(), now);
  await assert.rejects(() => Sale.endSale(db, deps, { id }, now + 1000), /already ended/);
});

test('cancelling a scheduled sale takes it off phones and frees its dates', async () => {
  const db = fakeDb();
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  const { id } = await Sale.scheduleSale(db, deps, ramadan, at('2027-02-20'));
  assert.deepStrictEqual(await Sale.endSale(db, deps, { id }, at('2027-02-21')), { result: 'cancelled' });
  assert.strictEqual(live(db).sale, null);
  const [record] = salesIn(db);
  assert.strictEqual(record.endsAt.toMillis(), at('2027-03-09', '23:59'), 'the plan is kept as it was');
  assert.strictEqual(record.endedEarlyAt.toMillis(), at('2027-02-21'));
  // The same dates can be scheduled again: a cancelled sale never ran.
  const again = await Sale.scheduleSale(db, deps, ramadan, at('2027-02-21'));
  assert.notStrictEqual(again.id, id);
  const state = await Sale.readSaleState(db, { nowMs: at('2027-02-21'), Timestamp });
  assert.deepStrictEqual(state.history.map((h) => h.state).sort(), ['cancelled', 'scheduled']);
});

test('ending an unknown sale is a 404', async () => {
  const db = fakeDb();
  await assert.rejects(() => Sale.endSale(db, deps, { id: 'nope' }, at('2027-02-21')), (e) => e.status === 404);
  await assert.rejects(() => Sale.endSale(db, deps, { id: 'a/b' }, at('2027-02-21')), Sale.SaleInputError);
});

test('the page reads the meter, each sale\'s own count, and the open welcome windows', async () => {
  const db = fakeDb();
  await Sale.setFullPriceSince(db, deps, { date: '2027-01-01' }, at('2027-02-20'));
  await Sale.scheduleSale(db, deps, ramadan, at('2027-02-20'));
  const put = (id, data) => db.docs.set('purchase_log/' + id, { environment: 'PRODUCTION', offerCode: null, transactionId: id, ...data });
  put('e1', { kind: 'sale', productId: 'growdaily_lifetime', eventAtMs: at('2027-03-15') });
  put('e2', { kind: 'sale', productId: 'growdaily_lifetime_offer', eventAtMs: at('2027-03-01') });
  put('e3', { kind: 'sale', productId: 'growdaily_lifetime_offer', eventAtMs: at('2027-03-16') });
  put('e4', { kind: 'sale', productId: 'growdaily_lifetime', eventAtMs: at('2027-03-17'), environment: 'SANDBOX' });
  const now = at('2027-03-20');
  db.docs.set('users/a', { welcomeOfferStartedAt: new FakeTimestamp(now - 10 * R.HOUR_MS) });
  db.docs.set('users/b', { welcomeOfferStartedAt: new FakeTimestamp(now - 80 * R.HOUR_MS) });
  db.docs.set('users/c', { name: 'never opened the paywall' });
  const s = await Sale.readSaleState(db, { nowMs: now, Timestamp });
  assert.deepStrictEqual(s.meter.counts, { full: 1, welcome: 1, sale: 1, code: 0 });
  assert.strictEqual(s.meter.sandboxRows, 1);
  assert.strictEqual(s.history[0].lifetimeSales, 1);
  assert.strictEqual(s.history[0].state, 'ended');
  assert.strictEqual(s.windowsOpen, 1);
  assert.strictEqual(s.status.state, 'none');
  assert.strictEqual(s.status.daysAtFullPrice, 10);
});
