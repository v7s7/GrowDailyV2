'use strict';

/**
 * The server side of the Sale page: what it reads, and the four writes it
 * makes. The rules themselves are lib/sale_rules.js, which the page also
 * runs in the browser; every write here runs them again inside the same
 * transaction that writes, so a request that skipped the page, or two tabs
 * saving at once, still cannot put a dishonest sale on a phone.
 *
 * Writes (nothing else, and never an account):
 *   offers/live         the one document phones read: welcome switch and
 *                       length, the current or next sale, fullPriceSince.
 *                       Always replaced whole inside a transaction, never
 *                       merged, the lesson lib/wording.js's doc comment
 *                       explains (a merge cannot take a field away).
 *   offer_sales/{id}    one record per scheduled sale, and endedEarlyAt
 *                       when one is ended or cancelled.
 *
 * Reads: offers/live, offer_sales, purchase_log (for the meter), and a
 * count of users whose welcomeOfferStartedAt is inside the window.
 */

const Rules = require('./sale_rules');

const LIVE_DOC = 'offers/live';
const SALES = 'offer_sales';
const PURCHASES = 'purchase_log';

/** A request the page should show as a message, not as a server fault. */
class SaleInputError extends Error {
  constructor(message, status = 400, errors = []) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

function msOf(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  return null;
}

function text(value) {
  return typeof value === 'string' ? value : '';
}

/** offers/live in the one shape the rest of this file uses. A missing document reads as the app's own fallback: welcome on, 72 hours, no sale. */
function shapeLive(data) {
  const d = data || {};
  const w = d.welcome && typeof d.welcome === 'object' ? d.welcome : {};
  const hours = Number.isInteger(w.hours) && w.hours >= Rules.WELCOME_MIN_HOURS && w.hours <= Rules.WELCOME_MAX_HOURS
    ? w.hours
    : Rules.WELCOME_DEFAULT_HOURS;
  let sale = null;
  if (d.sale && typeof d.sale === 'object') {
    const startsAtMs = msOf(d.sale.startsAt);
    const endsAtMs = msOf(d.sale.endsAt);
    if (startsAtMs !== null && endsAtMs !== null) {
      sale = { id: text(d.sale.id), nameAr: text(d.sale.nameAr), nameEn: text(d.sale.nameEn), startsAtMs, endsAtMs };
    }
  }
  return {
    exists: !!data,
    welcome: { enabled: typeof w.enabled === 'boolean' ? w.enabled : true, hours },
    sale,
    fullPriceSinceMs: msOf(d.fullPriceSince),
    updatedAtMs: msOf(d.updatedAt),
  };
}

/** The whole document, as written. Every field is always present. */
function liveDocument(live, { Timestamp, FieldValue }) {
  return {
    welcome: { enabled: live.welcome.enabled, hours: live.welcome.hours },
    sale: live.sale
      ? {
          id: live.sale.id,
          nameAr: live.sale.nameAr,
          nameEn: live.sale.nameEn,
          startsAt: Timestamp.fromMillis(live.sale.startsAtMs),
          endsAt: Timestamp.fromMillis(live.sale.endsAtMs),
        }
      : null,
    fullPriceSince: live.fullPriceSinceMs === null ? null : Timestamp.fromMillis(live.fullPriceSinceMs),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function shapeSale(id, data) {
  const d = data || {};
  return {
    id,
    nameAr: text(d.nameAr),
    nameEn: text(d.nameEn),
    startsAtMs: msOf(d.startsAt),
    endsAtMs: msOf(d.endsAt),
    endedEarlyAtMs: msOf(d.endedEarlyAt),
    createdAtMs: msOf(d.createdAt),
  };
}

/**
 * The sales the rules look at: every offer_sales record, plus the one in
 * offers/live when (only through some older write) it has no record.
 */
function salesForRules(sales, live) {
  const list = sales.filter((s) => s.startsAtMs !== null && s.endsAtMs !== null);
  if (live.sale && !list.some((s) => s.id === live.sale.id)) list.push({ ...live.sale, endedEarlyAtMs: null });
  return list;
}

function errorsMessage(errors) {
  return errors.map((e) => e.message).join(' ');
}

/** What a sale record says about itself, for the Past sales table. */
function saleState(sale, nowMs) {
  const span = Rules.ranSpan(sale);
  if (!span) return 'cancelled';
  if (span.end <= nowMs) return sale.endedEarlyAtMs !== null && sale.endedEarlyAtMs < sale.endsAtMs ? 'ended-early' : 'ended';
  return span.start <= nowMs ? 'running' : 'scheduled';
}

async function countOpenWindows(db, { nowMs, hours, Timestamp }) {
  try {
    const since = Timestamp.fromMillis(nowMs - hours * Rules.HOUR_MS);
    const snap = await db.collection('users').where('welcomeOfferStartedAt', '>', since).count().get();
    return snap.data().count;
  } catch (e) {
    console.error('[sale] could not count open welcome windows: ' + e.message);
    return null;
  }
}

/** Everything the page shows, in one read. */
async function readSaleState(db, { nowMs, Timestamp }) {
  const [liveSnap, salesSnap] = await Promise.all([db.doc(LIVE_DOC).get(), db.collection(SALES).get()]);
  const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
  const sales = salesSnap.docs.map((d) => shapeSale(d.id, d.data()));
  const ruleSales = salesForRules(sales, live);
  const status = Rules.saleStatus({ fullPriceSinceMs: live.fullPriceSinceMs, sales: ruleSales, nowMs });

  const meterFrom = nowMs - Rules.METER_DAYS * Rules.DAY_MS;
  const since = Math.min(meterFrom, ...ruleSales.map((s) => s.startsAtMs));
  const [rowsSnap, windowsOpen] = await Promise.all([
    db.collection(PURCHASES).where('eventAtMs', '>=', since).get(),
    countOpenWindows(db, { nowMs, hours: live.welcome.hours, Timestamp }),
  ]);
  const rows = rowsSnap.docs.map((d) => d.data());
  const meter = Rules.whoPaysFullPrice(rows, ruleSales, { fromMs: meterFrom, toMs: nowMs });
  const sandboxRows = rows.filter((r) => r.environment !== 'PRODUCTION' && Number(r.eventAtMs) >= meterFrom).length;

  const history = sales
    .filter((s) => s.startsAtMs !== null && s.endsAtMs !== null)
    .sort((a, b) => b.startsAtMs - a.startsAtMs)
    .map((s) => ({ ...s, state: saleState(s, nowMs), lifetimeSales: Rules.salesDuring(s, rows) }));

  return {
    nowMs,
    live,
    status,
    history,
    meter: { ...meter, sandboxRows },
    windowsOpen,
    facts: {
      fullPriceUsd: Rules.FULL_PRICE_USD,
      offerPriceUsd: Rules.OFFER_PRICE_USD,
      percentOff: Rules.percentOff(Rules.FULL_PRICE_USD, Rules.OFFER_PRICE_USD),
    },
  };
}

/** Welcome price on or off, and its length in hours. */
async function saveWelcome(db, deps, input) {
  const check = Rules.checkWelcome(input);
  if (!check.ok) throw new SaleInputError(errorsMessage(check.errors), 400, check.errors);
  const liveRef = db.doc(LIVE_DOC);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const changed = !live.exists || live.welcome.enabled !== check.value.enabled || live.welcome.hours !== check.value.hours;
    if (!changed) return { changed: false };
    live.welcome = check.value;
    tx.set(liveRef, liveDocument(live, deps));
    return { changed: true };
  });
}

/** The day Lifetime moved to its full price, a Bahrain date. */
async function setFullPriceSince(db, deps, { date }, nowMs) {
  // A day that is not real or is in the future is refused before any read;
  // the check against the live sale needs the sales, so it runs inside.
  const alone = Rules.checkFullPriceSince(date, { sales: [], nowMs });
  if (!alone.ok) throw new SaleInputError(errorsMessage(alone.errors), 400, alone.errors);
  const liveRef = db.doc(LIVE_DOC);
  return db.runTransaction(async (tx) => {
    const [snap, salesSnap] = await Promise.all([tx.get(liveRef), tx.get(db.collection(SALES))]);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const sales = salesForRules(salesSnap.docs.map((d) => shapeSale(d.id, d.data())), live);
    const check = Rules.checkFullPriceSince(date, { sales, nowMs });
    if (!check.ok) throw new SaleInputError(errorsMessage(check.errors), 400, check.errors);
    if (live.exists && live.fullPriceSinceMs === check.ms) return { changed: false };
    live.fullPriceSinceMs = check.ms;
    tx.set(liveRef, liveDocument(live, deps));
    return { changed: true };
  });
}

/** The refusals that depend on the form alone, not on anything stored. */
const FORM_ONLY_CODES = new Set(['names', 'name-too-long', 'name-dash', 'bad-dates', 'end-before-start', 'starts-in-past', 'too-long']);

/**
 * Schedules a sale: a new offer_sales record, and the same sale in
 * offers/live. Input is what the form holds: two names, and a Bahrain date
 * and time for each end.
 */
async function scheduleSale(db, deps, input, nowMs) {
  const raw = input || {};
  const proposed = {
    nameAr: text(raw.nameAr).trim(),
    nameEn: text(raw.nameEn).trim(),
    startsAtMs: Rules.bahrainMs(raw.startDate, raw.startTime),
    endsAtMs: Rules.bahrainMs(raw.endDate, raw.endTime),
  };
  // What the form alone gets wrong is refused before any read; the rules
  // that need the stored sales and fullPriceSince run inside, with them.
  const alone = Rules.checkSale(proposed, { fullPriceSinceMs: 0, sales: [], nowMs }).errors
    .filter((e) => FORM_ONLY_CODES.has(e.code));
  if (alone.length) throw new SaleInputError(errorsMessage(alone), 400, alone);
  const liveRef = db.doc(LIVE_DOC);
  return db.runTransaction(async (tx) => {
    const [snap, salesSnap] = await Promise.all([tx.get(liveRef), tx.get(db.collection(SALES))]);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const sales = salesForRules(salesSnap.docs.map((d) => shapeSale(d.id, d.data())), live);
    const check = Rules.checkSale(proposed, { fullPriceSinceMs: live.fullPriceSinceMs, sales, nowMs });
    if (!check.ok) throw new SaleInputError(errorsMessage(check.errors), 400, check.errors);
    const ref = db.collection(SALES).doc();
    tx.create(ref, {
      nameAr: proposed.nameAr,
      nameEn: proposed.nameEn,
      startsAt: deps.Timestamp.fromMillis(proposed.startsAtMs),
      endsAt: deps.Timestamp.fromMillis(proposed.endsAtMs),
      createdAt: deps.FieldValue.serverTimestamp(),
    });
    live.sale = { id: ref.id, nameAr: proposed.nameAr, nameEn: proposed.nameEn, startsAtMs: proposed.startsAtMs, endsAtMs: proposed.endsAtMs };
    tx.set(liveRef, liveDocument(live, deps));
    return { id: ref.id, facts: check.facts };
  });
}

/**
 * Ends the running sale now (endsAt becomes now, in both places), or
 * cancels one that has not started yet (it leaves offers/live, and its
 * record keeps its planned dates with endedEarlyAt before its start, which
 * the rules read as never having run).
 */
async function endSale(db, deps, { id }, nowMs) {
  const saleId = typeof id === 'string' ? id : '';
  if (!saleId || saleId.includes('/')) throw new SaleInputError('Which sale? The request named none.');
  const liveRef = db.doc(LIVE_DOC);
  const saleRef = db.doc(SALES + '/' + saleId);
  return db.runTransaction(async (tx) => {
    const [snap, saleSnap] = await Promise.all([tx.get(liveRef), tx.get(saleRef)]);
    if (!saleSnap.exists) throw new SaleInputError('There is no sale with that id.', 404);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const sale = shapeSale(saleSnap.id, saleSnap.data());
    const span = Rules.ranSpan(sale);
    if (!span || span.end <= nowMs) throw new SaleInputError('That sale has already ended.', 409);
    const now = deps.Timestamp.fromMillis(nowMs);
    let result;
    if (span.start <= nowMs) {
      tx.update(saleRef, { endsAt: now, endedEarlyAt: now });
      if (live.sale && live.sale.id === saleId) live.sale = { ...live.sale, endsAtMs: nowMs };
      result = 'ended';
    } else {
      tx.update(saleRef, { endedEarlyAt: now });
      if (live.sale && live.sale.id === saleId) live.sale = null;
      result = 'cancelled';
    }
    tx.set(liveRef, liveDocument(live, deps));
    return { result };
  });
}

module.exports = {
  LIVE_DOC,
  SALES,
  PURCHASES,
  SaleInputError,
  msOf,
  shapeLive,
  shapeSale,
  liveDocument,
  saleState,
  readSaleState,
  saveWelcome,
  setFullPriceSince,
  scheduleSale,
  endSale,
};
