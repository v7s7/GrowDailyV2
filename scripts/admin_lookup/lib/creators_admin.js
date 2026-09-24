'use strict';

/**
 * The server side of the Creators page: reading creators with what each
 * has earned, the four small writes (add, share, active, payout), and
 * making a creator's Apple offer code in two steps.
 *
 * Writes:
 *   creators/{CODE}       a creator's deal; later only sharePercent,
 *                         active, and the two Apple ids change
 *   creator_payouts/{id}  one row per payment Aziz made
 * Never written here: creator_ledger (the webhook's), purchase_log.
 *
 * The Apple code, in two steps (Aziz, 2026-09-22):
 *   Preview  reads what it needs from App Store Connect (the product's
 *            state, the offers already there, the US price point, Apple's
 *            equalized prices, where the product is sold), builds the exact
 *            requests, and keeps them for 15 minutes under a plan id. It
 *            sends nothing that changes anything.
 *   Create   sends exactly the previewed requests, once: the plan is taken
 *            out of the cache before the first request, so a double click
 *            cannot make two offers.
 * The creator document only ever names an Apple id Apple has returned. If
 * Apple refuses the offer, the creator is saved with no Apple ids; if it
 * makes the offer and refuses the code, the offer's id is kept (so a retry
 * does not use a second of the 10 offer slots) and the code's is not, so
 * the page never says a code exists that does not.
 */

const crypto = require('node:crypto');
const Creators = require('./creators');
const { AscApiError } = require('./asc_client');

const CREATORS = 'creators';
const LEDGER = 'creator_ledger';
const PAYOUTS = 'creator_payouts';
const PLAN_TTL_MS = 15 * 60 * 1000;

/** A request the page should show as a message, not as a server fault. */
class CreatorsInputError extends Error {
  constructor(message, status = 400, extra = {}) {
    super(message);
    this.status = status;
    Object.assign(this, extra);
  }
}

function msOf(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  return null;
}

function errorsMessage(errors) {
  return errors.map((e) => e.message).join(' ');
}

/** A creators document in the shape the page and the checks use. */
function shapeCreator(id, data) {
  const d = data || {};
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const str = (v) => (typeof v === 'string' && v !== '' ? v : null);
  const endsAtMs = msOf(d.codeEndsAt);
  return {
    id,
    name: typeof d.name === 'string' ? d.name : '',
    code: str(d.code) || id,
    offerRef: str(d.offerRef) || Creators.offerRefFor(id),
    discountPercent: num(d.discountPercent),
    discountOff: str(d.discountOff),
    offerPriceUsd: num(d.offerPriceUsd),
    sharePercent: num(d.sharePercent),
    active: d.active !== false,
    codeEndsAtMs: endsAtMs,
    codeEndsOn: endsAtMs === null ? null : Creators.pacificDateKey(endsAtMs),
    usesAllowed: num(d.usesAllowed),
    appleOfferCodeId: str(d.appleOfferCodeId),
    appleCustomCodeId: str(d.appleCustomCodeId),
    createdAtMs: msOf(d.createdAt),
    updatedAtMs: msOf(d.updatedAt),
  };
}

function creatorDocument(value, { Timestamp, FieldValue }) {
  return {
    name: value.name,
    code: value.code,
    offerRef: value.offerRef,
    discountPercent: value.discountPercent,
    discountOff: value.discountOff,
    offerPriceUsd: value.offerPriceUsd,
    sharePercent: value.sharePercent,
    active: true,
    codeEndsAt: Timestamp.fromMillis(value.codeEndsAtMs),
    usesAllowed: value.usesAllowed,
    appleOfferCodeId: null,
    appleCustomCodeId: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** A code from a request, as the document id it would be. */
function codeParam(value) {
  const code = typeof value === 'string' ? value.trim().toUpperCase() : '';
  if (!/^[A-Z0-9]{1,64}$/.test(code)) throw new CreatorsInputError('Which creator? The request named no valid code.');
  return code;
}

// ---- Reading ----------------------------------------------------------------

async function readCreatorsState(db, { nowMs, ascConfig }) {
  const [cSnap, lSnap, pSnap] = await Promise.all([
    db.collection(CREATORS).get(),
    db.collection(LEDGER).get(),
    db.collection(PAYOUTS).get(),
  ]);
  const creators = cSnap.docs.map((d) => shapeCreator(d.id, d.data()));
  const ledger = lSnap.docs.map((d) => d.data());
  const payouts = pSnap.docs.map((d) => ({ id: d.id, ...d.data(), paidAtMs: msOf(d.data().paidAt) }));
  const sums = Creators.creatorTotals({ creators, ledger, payouts, nowMs });
  const byId = new Map(sums.rows.map((r) => [r.id, r]));
  const lastPaid = new Map();
  for (const p of payouts) {
    if (p.paidAtMs !== null && (!lastPaid.has(p.creatorId) || p.paidAtMs > lastPaid.get(p.creatorId))) lastPaid.set(p.creatorId, p.paidAtMs);
  }
  const rows = creators
    .map((c) => ({ ...c, money: byId.get(c.id), lastPaidAtMs: lastPaid.get(c.id) || null }))
    .sort((a, b) => (a.active === b.active ? (b.createdAtMs || 0) - (a.createdAtMs || 0) : a.active ? -1 : 1));
  return {
    nowMs,
    creators: rows,
    totals: sums.totals,
    orphans: sums.orphans,
    sandboxRows: sums.sandboxRows,
    offersInUse: Creators.offersInUse(creators),
    maxOffers: Creators.MAX_ACTIVE_OFFERS,
    codeEndRange: Creators.codeEndRange(nowMs),
    asc: { ok: ascConfig.ok, missing: ascConfig.missing },
  };
}

/**
 * What App Store Connect says right now about the two Lifetime products:
 * each one's review state, and the offers on each. Read-only, for the page
 * to show beside its own records.
 */
async function readAppleStatus(asc) {
  const products = [];
  let active = 0;
  for (const product of Object.values(Creators.PRODUCTS)) {
    const [iap, offers] = await Promise.all([
      asc.get('/v2/inAppPurchases/' + product.iapId),
      asc.getAll('/v2/inAppPurchases/' + product.iapId + '/offerCodes', { 'fields[inAppPurchaseOfferCodes]': 'name,active', limit: 200 }),
    ]);
    const list = offers.data.map((o) => ({ id: o.id, name: o.attributes && o.attributes.name, active: !!(o.attributes && o.attributes.active) }));
    active += list.filter((o) => o.active).length;
    products.push({
      productId: product.productId,
      iapId: product.iapId,
      state: iap && iap.data && iap.data.attributes ? iap.data.attributes.state : null,
      offers: list,
    });
  }
  return { products, activeOffers: active, maxOffers: Creators.MAX_ACTIVE_OFFERS };
}

// ---- The four small writes -------------------------------------------------

/** Saves a new creator with no Apple code yet. Refuses a code that is taken. */
async function addCreator(db, deps, input, nowMs) {
  const check = Creators.checkCreatorInput(input, { nowMs });
  if (!check.ok) throw new CreatorsInputError(errorsMessage(check.errors), 400, { errors: check.errors });
  await createCreatorDoc(db, deps, check.value);
  return { code: check.value.code };
}

async function createCreatorDoc(db, deps, value) {
  const ref = db.doc(CREATORS + '/' + value.code);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const other = snap.data() || {};
      throw new CreatorsInputError('The code ' + value.code + ' is already ' + (other.name ? other.name + '\'s' : 'taken') + '. Pick another.', 409);
    }
    tx.create(ref, creatorDocument(value, deps));
  });
}

async function updateCreator(db, deps, code, patch) {
  const ref = db.doc(CREATORS + '/' + code);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new CreatorsInputError('There is no creator with the code ' + code + '.', 404);
    const before = snap.data() || {};
    const changed = Object.keys(patch).some((k) => before[k] !== patch[k]);
    if (!changed) return { changed: false };
    tx.update(ref, { ...patch, updatedAt: deps.FieldValue.serverTimestamp() });
    return { changed: true };
  });
}

/** A new share percent. Only sales recorded after this use it. */
async function setShare(db, deps, { code, sharePercent }) {
  const id = codeParam(code);
  const check = Creators.checkShareChange(sharePercent);
  if (!check.ok) throw new CreatorsInputError(errorsMessage(check.errors), 400, { errors: check.errors });
  return updateCreator(db, deps, id, { sharePercent: check.value });
}

/** Marks a creator inactive (or active again) in this tool. Apple's offer is not touched. */
async function setActive(db, deps, { code, active }) {
  const id = codeParam(code);
  if (typeof active !== 'boolean') throw new CreatorsInputError('Say whether the creator is active.');
  return updateCreator(db, deps, id, { active });
}

/**
 * Records a payment. Refused when it is more than the creator has earned
 * and not yet been paid, worked out inside the same transaction as the
 * write, so two payments sent at once cannot both pass.
 */
async function recordPayout(db, deps, { code, amountUsd, note }, nowMs) {
  const id = codeParam(code);
  const creatorRef = db.doc(CREATORS + '/' + id);
  return db.runTransaction(async (tx) => {
    const [snap, ledgerSnap, payoutSnap] = await Promise.all([
      tx.get(creatorRef),
      tx.get(db.collection(LEDGER).where('creatorId', '==', id)),
      tx.get(db.collection(PAYOUTS).where('creatorId', '==', id)),
    ]);
    if (!snap.exists) throw new CreatorsInputError('There is no creator with the code ' + id + '.', 404);
    const creator = shapeCreator(id, snap.data());
    const sums = Creators.creatorTotals({
      creators: [creator],
      ledger: ledgerSnap.docs.map((d) => d.data()),
      payouts: payoutSnap.docs.map((d) => d.data()),
      nowMs,
    });
    const check = Creators.checkPayout({ amountUsd, note }, { unpaidCents: sums.rows[0].unpaidCents });
    if (!check.ok) throw new CreatorsInputError(errorsMessage(check.errors), 400, { errors: check.errors });
    const ref = db.collection(PAYOUTS).doc();
    tx.create(ref, {
      creatorId: id,
      amountUsd: check.value.amountUsd,
      paidAt: deps.Timestamp.fromMillis(nowMs),
      note: check.value.note,
      createdAt: deps.FieldValue.serverTimestamp(),
    });
    return { id: ref.id, amountUsd: check.value.amountUsd };
  });
}

// ---- The Apple code ------------------------------------------------------------

const plans = new Map();

function keepPlan(plan, nowMs) {
  for (const [id, p] of plans) if (p.expiresAtMs <= nowMs) plans.delete(id);
  plans.set(plan.id, plan);
}

function takePlan(planId, nowMs) {
  const plan = plans.get(planId);
  plans.delete(planId);
  if (!plan || plan.expiresAtMs <= nowMs) return null;
  return plan;
}

const ELIGIBILITY_TEXT = 'People who have never bought anything in the app';
const NEW_OFFER_ID = '<the id Apple gives the new offer>';

/**
 * Builds the plan for one creator's Apple code: from the Add form's fields
 * (a creator not saved yet) or from a saved creator's code. Reads from App
 * Store Connect, writes nothing anywhere. Returns what the page shows.
 */
async function previewAppleCode(db, asc, { input, code }, nowMs) {
  let creator;
  let isNew;
  if (code !== undefined && code !== null && code !== '') {
    const id = codeParam(code);
    const snap = await db.doc(CREATORS + '/' + id).get();
    if (!snap.exists) throw new CreatorsInputError('There is no creator with the code ' + id + '.', 404);
    creator = shapeCreator(id, snap.data());
    isNew = false;
    if (creator.appleCustomCodeId) throw new CreatorsInputError(id + ' already has its Apple code.', 409);
    if (!creator.active) throw new CreatorsInputError(id + ' is inactive. Make them active first.', 409);
    if (!Creators.PRODUCTS[creator.discountOff] || creator.offerPriceUsd === null || creator.usesAllowed === null || !creator.codeEndsOn) {
      throw new CreatorsInputError(id + '\'s record is missing part of the deal (product, price, uses or end date).', 409);
    }
    const range = Creators.codeEndRange(nowMs);
    if (creator.codeEndsOn < range.min) throw new CreatorsInputError(id + '\'s code was set to end on ' + creator.codeEndsOn + ', which has passed.', 409);
  } else {
    const check = Creators.checkCreatorInput(input, { nowMs });
    if (!check.ok) throw new CreatorsInputError(errorsMessage(check.errors), 400, { errors: check.errors });
    creator = check.value;
    isNew = true;
    const taken = await db.doc(CREATORS + '/' + creator.code).get();
    if (taken.exists) {
      const other = taken.data() || {};
      throw new CreatorsInputError('The code ' + creator.code + ' is already ' + (other.name ? other.name + '\'s' : 'taken') + '. Pick another.', 409);
    }
  }

  const cfg = asc.config();
  if (!cfg.ok) throw new CreatorsInputError('App Store Connect is not set up for this tool: ' + cfg.missing.join('. ') + '.', 400, { ascMissing: cfg.missing });

  const product = Creators.PRODUCTS[creator.discountOff];
  const blocked = [];
  const status = await readAppleStatus(asc);
  const mine = status.products.find((p) => p.productId === product.productId);
  if (mine.state !== 'APPROVED') {
    blocked.push('Apple lists ' + product.productId + ' as ' + (mine.state || 'unknown') + ', not APPROVED. Apple only makes custom codes for an approved product, so this waits until it passes review.');
  }

  // Which offer the code goes under: the one this creator already has, one
  // Apple already holds under this exact name (a run that timed out after
  // Apple made it), or a new one.
  const all = status.products.flatMap((p) => p.offers.map((o) => ({ ...o, productId: p.productId })));
  let offerStep = 'create';
  let offerId = null;
  if (creator.appleOfferCodeId) {
    const found = all.find((o) => o.id === creator.appleOfferCodeId);
    if (!found) blocked.push('Apple has no offer with the id this creator has (' + creator.appleOfferCodeId + ').');
    else if (!found.active) blocked.push('Apple\'s offer ' + found.name + ' has been turned off, so no code can go under it.');
    offerStep = 'reuse';
    offerId = creator.appleOfferCodeId;
  } else {
    const same = all.find((o) => String(o.name || '').trim().toLowerCase() === creator.offerRef);
    if (same) {
      if (same.productId !== product.productId) blocked.push('Apple already has an offer named ' + creator.offerRef + ' on ' + same.productId + '. Pick another code.');
      else if (!same.active) blocked.push('Apple already has a turned-off offer named ' + creator.offerRef + '. Pick another code.');
      offerStep = 'reuse';
      offerId = same.id;
    } else if (status.activeOffers >= Creators.MAX_ACTIVE_OFFERS) {
      blocked.push('All ' + Creators.MAX_ACTIVE_OFFERS + ' of Apple\'s offer slots are in use. Turn one off in App Store Connect first.');
    }
  }

  const targetCents = Creators.toCents(creator.offerPriceUsd);
  let offerRequest = null;
  let prices = [];
  let usPoint = null;
  let codeStep = 'create';
  let customCodeId = null;
  if (offerStep === 'create') {
    const points = await asc.getAll('/v2/inAppPurchases/' + product.iapId + '/pricePoints', { 'filter[territory]': 'USA', limit: 8000 });
    usPoint = Creators.pickUsPricePoint(points.data, targetCents);
    if (!usPoint) {
      blocked.push('Apple has no US price point at ' + Creators.money(targetCents) + ' for ' + product.productId + '.');
    } else {
      const eq = await asc.getAll('/v1/inAppPurchasePricePoints/' + usPoint.id + '/equalizations', { limit: 8000, include: 'territory', 'fields[territories]': 'currency' });
      const currencies = {};
      for (const t of eq.included) if (t.type === 'territories') currencies[t.id] = t.attributes && t.attributes.currency;
      const availability = await asc.get('/v2/inAppPurchases/' + product.iapId + '/inAppPurchaseAvailability');
      const territories = await asc.getAll('/v1/inAppPurchaseAvailabilities/' + availability.data.id + '/availableTerritories', { limit: 200 });
      const available = territories.data.map((t) => t.id);
      prices = Creators.equalizedPrices({ usPoint, equalizations: eq.data, currencies, availableTerritories: available.length ? available : null });
      offerRequest = Creators.buildOfferCodeRequest({ iapId: product.iapId, offerRef: creator.offerRef, prices });
    }
  } else if (offerId && !blocked.length) {
    // An offer that already exists is used as it is. Its US price must be
    // the deal's, and a code already under it is recorded, not made twice.
    const [offerPrices, codes] = await Promise.all([
      asc.getAll('/v1/inAppPurchaseOfferCodes/' + offerId + '/prices', { include: 'pricePoint', 'filter[territory]': 'USA', limit: 200 }),
      asc.getAll('/v1/inAppPurchaseOfferCodes/' + offerId + '/customCodes', { limit: 200 }),
    ]);
    const point = offerPrices.included.find((x) => x.type === 'inAppPurchasePricePoints');
    const usCents = point && point.attributes ? Creators.toCents(point.attributes.customerPrice) : null;
    if (usCents !== targetCents) {
      blocked.push('Apple\'s offer ' + creator.offerRef + ' sells at ' + (usCents === null ? 'an unknown price' : Creators.money(usCents)) + ' in the US; this creator\'s deal says ' + Creators.money(targetCents) + '.');
    }
    const existing = codes.data.find((c) => c.attributes && String(c.attributes.customCode).toUpperCase() === creator.code && c.attributes.active);
    if (existing) {
      codeStep = 'reuse';
      customCodeId = existing.id;
    }
  }

  const codeRequest = codeStep === 'create'
    ? Creators.buildCustomCodeRequest({ offerCodeId: offerId || NEW_OFFER_ID, code: creator.code, usesAllowed: creator.usesAllowed, expirationDate: creator.codeEndsOn })
    : null;

  const sample = Creators.SAMPLE_TERRITORIES
    .map((t) => prices.find((p) => p.territory === t))
    .filter(Boolean)
    .map((p) => ({ territory: p.territory, customerPrice: p.customerPrice, currency: p.currency }));

  const plan = {
    id: crypto.randomUUID(),
    createdAtMs: nowMs,
    expiresAtMs: nowMs + PLAN_TTL_MS,
    isNew,
    creator,
    offerStep,
    offerId,
    codeStep,
    customCodeId,
    offerRequest,
    blocked,
  };
  keepPlan(plan, nowMs);

  const requests = [];
  if (offerRequest) requests.push({ step: 'Make the offer', ...offerRequest });
  if (codeRequest) requests.push({ step: 'Make the code under it', ...codeRequest });

  return {
    planId: plan.id,
    expiresAtMs: plan.expiresAtMs,
    blocked,
    isNew,
    summary: {
      name: creator.name,
      code: creator.code,
      offerRef: creator.offerRef,
      productId: product.productId,
      iapId: product.iapId,
      productState: mine.state,
      eligibility: ELIGIBILITY_TEXT,
      offerStep,
      offerId,
      codeStep,
      usPrice: Creators.money(targetCents),
      usProceeds: usPoint && usPoint.proceeds !== undefined ? usPoint.proceeds : null,
      territories: prices.length,
      sample,
      usesAllowed: creator.usesAllowed,
      codeEndsOn: creator.codeEndsOn,
      activeOffers: status.activeOffers,
      offersLeftAfter: Creators.MAX_ACTIVE_OFFERS - status.activeOffers - (offerStep === 'create' ? 1 : 0),
      shareLink: Creators.shareLinkFor(creator.code),
    },
    requests,
  };
}

/**
 * Sends a previewed plan. Returns { ok, stage, message, ... } rather than
 * throwing when Apple refuses, because by then something may already be
 * saved and the page has to say exactly what.
 */
async function createAppleCode(db, deps, asc, { planId }, nowMs) {
  const plan = takePlan(String(planId || ''), nowMs);
  if (!plan) throw new CreatorsInputError('That preview has expired or was already used. Press Preview again.', 409);
  if (plan.blocked.length) throw new CreatorsInputError(plan.blocked.join(' '), 409);
  const c = plan.creator;
  const ref = db.doc(CREATORS + '/' + c.code);

  if (plan.isNew) {
    await createCreatorDoc(db, deps, c);
  } else {
    const snap = await ref.get();
    const now = snap.exists ? shapeCreator(c.code, snap.data()) : null;
    if (!now || now.appleCustomCodeId || (now.appleOfferCodeId || null) !== (c.appleOfferCodeId || null)) {
      throw new CreatorsInputError(c.code + ' changed since the preview. Press Preview again.', 409);
    }
  }
  const stamp = () => deps.FieldValue.serverTimestamp();
  const saved = plan.isNew ? 'Saved ' + c.name + ' (' + c.code + ') in this tool. ' : '';

  let offerId = plan.offerId;
  if (plan.offerStep === 'create') {
    try {
      const res = await asc.post(plan.offerRequest.path, plan.offerRequest.body);
      offerId = res && res.data && res.data.id;
      if (!offerId) throw new AscApiError('App Store Connect answered without an offer id.', 0);
    } catch (e) {
      return { ok: false, stage: 'offer', message: saved + 'Apple did not make the offer: ' + e.message + ' Nothing was made in App Store Connect.' };
    }
  }
  if (offerId !== c.appleOfferCodeId) await ref.update({ appleOfferCodeId: offerId, updatedAt: stamp() });

  let customCodeId = plan.customCodeId;
  if (plan.codeStep === 'create') {
    const req = Creators.buildCustomCodeRequest({ offerCodeId: offerId, code: c.code, usesAllowed: c.usesAllowed, expirationDate: c.codeEndsOn });
    try {
      const res = await asc.post(req.path, req.body);
      customCodeId = res && res.data && res.data.id;
      if (!customCodeId) throw new AscApiError('App Store Connect answered without a code id.', 0);
    } catch (e) {
      return {
        ok: false,
        stage: 'code',
        offerId,
        message: saved + 'Apple made the offer ' + c.offerRef + ' (' + offerId + ') but not the code ' + c.code + ': ' + e.message +
          ' The creator shows no code until it is made; Make the Apple code tries the code again under the same offer.',
      };
    }
  }
  await ref.update({ appleCustomCodeId: customCodeId, updatedAt: stamp() });
  return { ok: true, offerId, customCodeId, message: 'Apple made the offer ' + c.offerRef + ' and the code ' + c.code + '.' };
}

module.exports = {
  CREATORS,
  LEDGER,
  PAYOUTS,
  PLAN_TTL_MS,
  CreatorsInputError,
  shapeCreator,
  creatorDocument,
  readCreatorsState,
  readAppleStatus,
  addCreator,
  setShare,
  setActive,
  recordPayout,
  previewAppleCode,
  createAppleCode,
  _plans: plans,
};
