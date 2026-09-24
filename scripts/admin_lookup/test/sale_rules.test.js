'use strict';

/**
 * The Sale page's rules (lib/sale_rules.js): every reason a sale is
 * refused, the status banner, the "Who pays full price" meter, and the
 * Bahrain-time arithmetic under all of it.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const R = require('../lib/sale_rules');

const DAY = R.DAY_MS;
/** A Bahrain wall-clock instant. */
const at = (date, time = '00:00') => R.bahrainMs(date, time);

const FULL_SINCE = at('2027-01-01');
const names = { nameAr: 'عرض رمضان', nameEn: 'Ramadan sale' };

function sale(id, start, end, extra = {}) {
  return { id, nameAr: 'عرض ' + id, nameEn: 'Sale ' + id, startsAtMs: start, endsAtMs: end, endedEarlyAtMs: null, ...extra };
}

function codes(result) {
  return result.errors.map((e) => e.code).sort();
}

// ---- Bahrain time ---------------------------------------------------------

test('a Bahrain date and time is UTC+3, all year', () => {
  assert.strictEqual(at('2027-02-27', '00:00'), Date.UTC(2027, 1, 26, 21, 0));
  assert.strictEqual(at('2027-07-01', '12:30'), Date.UTC(2027, 6, 1, 9, 30));
  assert.strictEqual(R.bahrainParts(Date.UTC(2027, 1, 26, 21, 0)).dateKey, '2027-02-27');
  assert.strictEqual(R.bahrainParts(Date.UTC(2027, 1, 26, 21, 0)).time, '00:00');
});

test('an impossible date or time is no instant at all', () => {
  assert.strictEqual(R.bahrainMs('2027-02-30', '00:00'), null);
  assert.strictEqual(R.bahrainMs('2027-13-01', '00:00'), null);
  assert.strictEqual(R.bahrainMs('2027-02-27', '24:00'), null);
  assert.strictEqual(R.bahrainMs('2027-02-27', '9:00'), null);
});

test('dates read the way the page says them', () => {
  assert.strictEqual(R.longDateTime(at('2027-02-27', '00:00')), 'Saturday 27 February 2027 at 00:00');
  assert.strictEqual(R.shortDate(at('2027-03-09', '23:59')), '9 Mar 2027');
  // 00:00 to 23:59 eleven days later reads as 11 days, not 10.
  assert.strictEqual(R.spanDays(at('2027-03-09', '23:59') - at('2027-02-27', '00:00')), 11);
});

test('the percent phones show is rounded down, like the app', () => {
  assert.strictEqual(R.percentOff(39.99, 29.99), 25);
  assert.strictEqual(R.percentOff(39.99, 39.99), null);
  assert.strictEqual(R.percentOff(0, 29.99), null);
});

// ---- A sale that passes ------------------------------------------------------

test('a sale that keeps every rule is accepted, with the facts the page shows', () => {
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-02-27'), endsAtMs: at('2027-03-09', '23:59') },
    { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-02-20') },
  );
  assert.deepStrictEqual(r.errors, []);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.facts.stretchMs, at('2027-02-27') - FULL_SINCE);
  assert.strictEqual(r.facts.earliestStartMs, FULL_SINCE + 30 * DAY);
  assert.strictEqual(R.shortDate(r.facts.fullPriceUntilMs), '8 Apr 2027');
});

// ---- Every refusal ----------------------------------------------------------

test('refused until fullPriceSince is set, and says so', () => {
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-02-27'), endsAtMs: at('2027-03-09') },
    { fullPriceSinceMs: null, sales: [], nowMs: at('2027-02-20') },
  );
  assert.deepStrictEqual(codes(r), ['no-full-price-since']);
  assert.match(r.errors[0].message, /full price/);
});

test('refused without real dates', () => {
  const r = R.checkSale({ ...names, startsAtMs: null, endsAtMs: at('2027-03-09') }, { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-02-20') });
  assert.deepStrictEqual(codes(r), ['bad-dates']);
});

test('refused when it ends before (or when) it starts', () => {
  const ctx = { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-02-20') };
  assert.deepStrictEqual(codes(R.checkSale({ ...names, startsAtMs: at('2027-03-09'), endsAtMs: at('2027-02-27') }, ctx)), ['end-before-start']);
  assert.deepStrictEqual(codes(R.checkSale({ ...names, startsAtMs: at('2027-03-09'), endsAtMs: at('2027-03-09') }, ctx)), ['end-before-start']);
});

test('refused without both names, with a long name, or with an em dash', () => {
  const ctx = { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-02-20') };
  const dates = { startsAtMs: at('2027-02-27'), endsAtMs: at('2027-03-05') };
  assert.deepStrictEqual(codes(R.checkSale({ ...dates, nameAr: '', nameEn: 'Sale' }, ctx)), ['names']);
  assert.deepStrictEqual(codes(R.checkSale({ ...dates, nameAr: 'عرض', nameEn: 'x'.repeat(R.MAX_NAME_LENGTH + 1) }, ctx)), ['name-too-long']);
  const dash = 'Big' + String.fromCharCode(0x2014) + 'sale';
  assert.deepStrictEqual(codes(R.checkSale({ ...dates, nameAr: 'عرض', nameEn: dash }, ctx)), ['name-dash']);
});

test('refused when it starts in the past, with a few minutes of grace', () => {
  const ctx = { fullPriceSinceMs: FULL_SINCE, sales: [] };
  const past = R.checkSale({ ...names, startsAtMs: at('2027-02-27'), endsAtMs: at('2027-03-05') }, { ...ctx, nowMs: at('2027-02-27', '01:00') });
  assert.deepStrictEqual(codes(past), ['starts-in-past']);
  const justNow = R.checkSale({ ...names, startsAtMs: at('2027-02-27', '00:00'), endsAtMs: at('2027-03-05') }, { ...ctx, nowMs: at('2027-02-27', '00:10') });
  assert.strictEqual(justNow.ok, true);
});

test('refused when longer than 30 days; exactly 30 is fine', () => {
  const ctx = { fullPriceSinceMs: at('2026-10-01'), sales: [], nowMs: at('2027-02-20') };
  assert.strictEqual(R.checkSale({ ...names, startsAtMs: at('2027-03-01'), endsAtMs: at('2027-03-31') }, ctx).ok, true);
  const long = R.checkSale({ ...names, startsAtMs: at('2027-03-01'), endsAtMs: at('2027-03-31', '00:01') }, ctx);
  assert.deepStrictEqual(codes(long), ['too-long']);
});

test('refused while another sale is scheduled or running: phones hold one', () => {
  const scheduled = sale('A', at('2027-03-01'), at('2027-03-10'));
  const later = { ...names, startsAtMs: at('2027-05-01'), endsAtMs: at('2027-05-10') };
  const r = R.checkSale(later, { fullPriceSinceMs: FULL_SINCE, sales: [scheduled], nowMs: at('2027-02-20') });
  assert.deepStrictEqual(codes(r), ['one-at-a-time']);
  assert.match(r.errors[0].message, /already scheduled/);
  const running = R.checkSale(later, { fullPriceSinceMs: FULL_SINCE, sales: [scheduled], nowMs: at('2027-03-05') });
  assert.deepStrictEqual(codes(running), ['one-at-a-time']);
  assert.match(running.errors[0].message, /running now/);
});

test('refused when it overlaps an earlier sale', () => {
  const past = sale('A', at('2027-02-01'), at('2027-02-10'));
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-02-09'), endsAtMs: at('2027-02-12') },
    { fullPriceSinceMs: at('2026-10-01'), sales: [past], nowMs: at('2027-02-08') },
  );
  assert.ok(codes(r).includes('overlap'), codes(r).join(','));
});

test('refused less than 30 days after fullPriceSince, naming the earliest start', () => {
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-01-20'), endsAtMs: at('2027-01-25') },
    { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-01-10') },
  );
  assert.deepStrictEqual(codes(r), ['too-soon']);
  assert.match(r.errors[0].message, /31 January 2027 at 00:00/);
});

test('refused less than 30 days after the previous sale ended', () => {
  const past = sale('A', at('2027-03-01'), at('2027-03-10'));
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-04-01'), endsAtMs: at('2027-04-05') },
    { fullPriceSinceMs: FULL_SINCE, sales: [past], nowMs: at('2027-03-20') },
  );
  assert.deepStrictEqual(codes(r), ['too-soon']);
  assert.match(r.errors[0].message, /last sale ended on 10 Mar 2027/);
  assert.match(r.errors[0].message, /9 April 2027/);
});

test('refused when longer than the full-price stretch right before it', () => {
  // 20 days at full price, then a 25-day sale: too soon, and longer than the stretch.
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-01-21'), endsAtMs: at('2027-02-15') },
    { fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-01-10') },
  );
  assert.deepStrictEqual(codes(r), ['longer-than-stretch', 'too-soon']);
});

test('a sale ended early counts only until it ended; one cancelled before it started does not count', () => {
  const endedEarly = sale('A', at('2027-03-01'), at('2027-03-20'), { endedEarlyAtMs: at('2027-03-05') });
  const ok = R.checkSale(
    { ...names, startsAtMs: at('2027-04-04'), endsAtMs: at('2027-04-10') },
    { fullPriceSinceMs: FULL_SINCE, sales: [endedEarly], nowMs: at('2027-03-25') },
  );
  assert.strictEqual(ok.ok, true, codes(ok).join(','));
  const cancelled = sale('B', at('2027-03-01'), at('2027-03-20'), { endedEarlyAtMs: at('2027-02-25') });
  const alsoOk = R.checkSale(
    { ...names, startsAtMs: at('2027-03-02'), endsAtMs: at('2027-03-10') },
    { fullPriceSinceMs: FULL_SINCE, sales: [cancelled], nowMs: at('2027-02-26') },
  );
  assert.strictEqual(alsoOk.ok, true, codes(alsoOk).join(','));
});

test('with no clock, only the calendar rules apply: a sale placed before another needs its 30 days too', () => {
  const next = sale('A', at('2027-06-01'), at('2027-06-20'));
  const r = R.checkSale(
    { ...names, startsAtMs: at('2027-05-10'), endsAtMs: at('2027-05-20') },
    { fullPriceSinceMs: FULL_SINCE, sales: [next] },
  );
  assert.deepStrictEqual(codes(r), ['next-longer-than-stretch', 'next-too-soon']);
});

test('refused past 90 sale days in any 365; exactly 90 is fine', () => {
  const sales = [
    sale('A', at('2027-02-01'), at('2027-03-03')),
    sale('B', at('2027-04-02'), at('2027-05-02')),
  ];
  const ctx = { fullPriceSinceMs: FULL_SINCE, sales, nowMs: at('2027-05-20') };
  // A third 30-day sale brings the year to exactly 90 days.
  const third = R.checkSale({ ...names, startsAtMs: at('2027-06-01'), endsAtMs: at('2027-07-01') }, ctx);
  assert.strictEqual(third.ok, true, codes(third).join(','));
  assert.strictEqual(third.facts.yearSaleMs, 90 * DAY);

  const withThird = sales.concat([sale('C', at('2027-06-01'), at('2027-07-01'))]);
  const fourth = R.checkSale(
    { ...names, startsAtMs: at('2027-07-31'), endsAtMs: at('2027-08-10') },
    { fullPriceSinceMs: FULL_SINCE, sales: withThird, nowMs: at('2027-07-15') },
  );
  assert.deepStrictEqual(codes(fourth), ['year-cap']);
  assert.match(fourth.errors[0].message, /100 days on sale/);
  // A year after the first sale began, the window has moved on.
  const muchLater = R.checkSale(
    { ...names, startsAtMs: at('2028-02-02'), endsAtMs: at('2028-02-12') },
    { fullPriceSinceMs: FULL_SINCE, sales: withThird, nowMs: at('2028-01-15') },
  );
  assert.strictEqual(muchLater.ok, true, codes(muchLater).join(','));
});

// ---- Status -------------------------------------------------------------------

test('status: no fullPriceSince means no sale can start', () => {
  const s = R.saleStatus({ fullPriceSinceMs: null, sales: [], nowMs: at('2027-02-20') });
  assert.strictEqual(s.state, 'none');
  assert.strictEqual(s.fullPriceSet, false);
  assert.strictEqual(s.canStartNow, false);
});

test('status: days at full price, and whether a sale may start now', () => {
  const young = R.saleStatus({ fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-01-20') });
  assert.strictEqual(young.daysAtFullPrice, 19);
  assert.strictEqual(young.canStartNow, false);
  assert.strictEqual(young.earliestStartMs, at('2027-01-31'));
  const old = R.saleStatus({ fullPriceSinceMs: FULL_SINCE, sales: [], nowMs: at('2027-02-15') });
  assert.strictEqual(old.daysAtFullPrice, 45);
  assert.strictEqual(old.canStartNow, true);
});

test('status: running, then counted from its end once it is over', () => {
  const s = sale('A', at('2027-03-01'), at('2027-03-10'));
  const running = R.saleStatus({ fullPriceSinceMs: FULL_SINCE, sales: [s], nowMs: at('2027-03-05') });
  assert.strictEqual(running.state, 'running');
  assert.strictEqual(running.sale.id, 'A');
  assert.strictEqual(running.daysAtFullPrice, 0);
  const scheduled = R.saleStatus({ fullPriceSinceMs: FULL_SINCE, sales: [s], nowMs: at('2027-02-20') });
  assert.strictEqual(scheduled.state, 'scheduled');
  assert.strictEqual(scheduled.canStartNow, false);
  const after = R.saleStatus({ fullPriceSinceMs: FULL_SINCE, sales: [s], nowMs: at('2027-03-20') });
  assert.strictEqual(after.state, 'none');
  assert.strictEqual(after.daysAtFullPrice, 10);
  assert.strictEqual(after.earliestStartMs, at('2027-04-09'));
});

// ---- The other inputs ---------------------------------------------------------

test('welcome: a switch and a whole number of hours from 24 to 168', () => {
  assert.strictEqual(R.checkWelcome({ enabled: true, hours: 72 }).ok, true);
  assert.strictEqual(R.checkWelcome({ enabled: false, hours: 24 }).ok, true);
  assert.strictEqual(R.checkWelcome({ enabled: true, hours: 23 }).ok, false);
  assert.strictEqual(R.checkWelcome({ enabled: true, hours: 169 }).ok, false);
  assert.strictEqual(R.checkWelcome({ enabled: true, hours: 72.5 }).ok, false);
  assert.strictEqual(R.checkWelcome({ enabled: 'yes', hours: 72 }).ok, false);
});

test('fullPriceSince: a real day, not in the future, and not one that breaks the live sale', () => {
  const now = at('2027-02-20');
  assert.strictEqual(R.checkFullPriceSince('2027-01-01', { sales: [], nowMs: now }).ok, true);
  assert.strictEqual(R.checkFullPriceSince('2027-01-01', { sales: [], nowMs: now }).ms, FULL_SINCE);
  assert.deepStrictEqual(R.checkFullPriceSince('2027-02-30', { sales: [], nowMs: now }).errors.map((e) => e.code), ['bad-date']);
  assert.deepStrictEqual(R.checkFullPriceSince('2027-03-01', { sales: [], nowMs: now }).errors.map((e) => e.code), ['future']);
  const scheduled = sale('A', at('2027-03-01'), at('2027-03-10'));
  const breaks = R.checkFullPriceSince('2027-02-10', { sales: [scheduled], nowMs: now });
  assert.deepStrictEqual(breaks.errors.map((e) => e.code), ['breaks-live-sale']);
  assert.strictEqual(R.checkFullPriceSince('2027-01-15', { sales: [scheduled], nowMs: now }).ok, true);
});

// ---- Who pays full price --------------------------------------------------------

function row(kind, productId, eventAtMs, extra = {}) {
  return { kind, productId, eventAtMs, environment: 'PRODUCTION', offerCode: null, transactionId: 'tx-' + Math.random(), ...extra };
}

test('the meter sorts each purchase into full, welcome, sale or code', () => {
  const s = sale('A', at('2027-03-01'), at('2027-03-10'));
  const rows = [
    row('sale', 'growdaily_lifetime', at('2027-02-01')),
    row('sale', 'growdaily_lifetime', at('2027-02-02')),
    row('sale', 'growdaily_lifetime_offer', at('2027-02-03')),
    row('sale', 'growdaily_lifetime_offer', at('2027-03-02')),
    row('sale', 'growdaily_lifetime_offer', at('2027-03-03'), { offerCode: 'creator-sara' }),
    row('sale', 'growdaily_lifetime', at('2027-03-04'), { offerCode: 'creator-fajr' }),
    row('sale', 'growdaily_lifetime', at('2027-02-05'), { environment: 'SANDBOX' }),
    row('sale', 'growdaily_monthly', at('2027-02-06')),
  ];
  const m = R.whoPaysFullPrice(rows, [s], { fromMs: at('2027-01-01'), toMs: at('2027-04-01') });
  assert.deepStrictEqual(m.counts, { full: 2, welcome: 1, sale: 1, code: 2 });
  assert.strictEqual(m.total, 6);
  assert.strictEqual(m.pct.full, 33.3);
});

test('the meter takes refunds off the class of the purchase they refund', () => {
  const s = sale('A', at('2027-03-01'), at('2027-03-10'));
  const bought = row('sale', 'growdaily_lifetime_offer', at('2027-03-02'), { transactionId: 'T1' });
  // Refunded after the sale ended, stamped with the refund's own time: still a sale refund.
  const refund = row('refund', 'growdaily_lifetime_offer', at('2027-03-20'), { transactionId: 'T1' });
  const full = row('sale', 'growdaily_lifetime', at('2027-02-01'));
  const m = R.whoPaysFullPrice([bought, refund, full], [s], { fromMs: at('2027-01-01'), toMs: at('2027-04-01') });
  assert.deepStrictEqual(m.counts, { full: 1, welcome: 0, sale: 0, code: 0 });
  assert.strictEqual(m.unmatchedRefunds, 0);
});

test('a refund that matches no purchase is sorted by its own fields inside the window, and counted as unmatched', () => {
  const m = R.whoPaysFullPrice([
    row('sale', 'growdaily_lifetime', at('2027-02-01')),
    row('sale', 'growdaily_lifetime', at('2027-02-02')),
    row('refund', 'growdaily_lifetime', at('2027-02-03'), { transactionId: 'unknown' }),
    row('refund', 'growdaily_lifetime', at('2026-10-03'), { transactionId: 'older' }),
  ], [], { fromMs: at('2027-01-01'), toMs: at('2027-04-01') });
  assert.strictEqual(m.counts.full, 1);
  assert.strictEqual(m.unmatchedRefunds, 2);
});

test('purchases outside the window are left out, and an empty meter is all zeros', () => {
  const m = R.whoPaysFullPrice([row('sale', 'growdaily_lifetime', at('2026-01-01'))], [], { fromMs: at('2027-01-01'), toMs: at('2027-04-01') });
  assert.strictEqual(m.total, 0);
  assert.strictEqual(m.pct.full, 0);
});

test('a sale counts the offer purchases made during it', () => {
  const s = sale('A', at('2027-03-01'), at('2027-03-10'));
  const rows = [
    row('sale', 'growdaily_lifetime_offer', at('2027-03-02')),
    row('sale', 'growdaily_lifetime_offer', at('2027-03-03')),
    row('sale', 'growdaily_lifetime_offer', at('2027-03-12')),
    row('sale', 'growdaily_lifetime', at('2027-03-04')),
  ];
  assert.strictEqual(R.salesDuring(s, rows), 2);
});
