/**
 * The Creators page's pure logic, shared by the browser and the server the
 * way wording/rules.js is: the Add form's money preview runs this as Aziz
 * types, and the server runs the same checks again before any write.
 *
 * What a creator is (Aziz, 2026-09-22). Someone with a following gets one
 * Apple offer code. Their followers pay less for Lifetime with it, and the
 * creator earns a share of what Apple actually sends for each of those
 * sales (after tax and Apple's cut), minus refunds. The buyer discount and
 * the share are set per creator; the share is 25% unless Aziz says
 * otherwise. The webhook copies the percent onto every ledger row when the
 * sale arrives (functions/purchase_facts.js), so changing a creator's
 * percent only changes later sales.
 *
 * One creator is one Apple offer, named 'creator-' + the code in lower case.
 * RevenueCat reports that offer NAME (not the code the buyer typed) as
 * offer_code, which is how the webhook finds the creator.
 *
 * What is here:
 *   the facts (products, limits), codes and links
 *   price points and the money preview, in whole cents
 *   checks for a new creator, a share change and a payout
 *   the ledger sums: earned, paid, waiting, owed
 *   the App Store Connect request bodies, and the plan built from Apple's
 *   price points (lib/creators_admin.js sends them)
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.CreatorRules = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DAY_MS = 24 * 60 * 60 * 1000;

  /** GrowDaily's App Store id, for the redeem link. */
  const APP_APPLE_ID = '6788149393';

  /** The two products a code can take its discount off. */
  const PRODUCTS = {
    growdaily_lifetime_offer: { productId: 'growdaily_lifetime_offer', iapId: '6814748258', priceUsd: 29.99, label: 'Lifetime, $29.99' },
    growdaily_lifetime: { productId: 'growdaily_lifetime', iapId: '6791138092', priceUsd: 39.99, label: 'Lifetime, $39.99' },
  };
  const DEFAULT_PRODUCT = 'growdaily_lifetime_offer';

  const DEFAULT_SHARE_PERCENT = 25;
  /** Apple allows 10 active offers per app. */
  const MAX_ACTIVE_OFFERS = 10;
  /** A sale's share becomes payable once it is this old, so most refunds have happened. */
  const OWED_AFTER_DAYS = 60;
  const MIN_DISCOUNT = 1;
  const MAX_DISCOUNT = 90;
  const MIN_USES = 1;
  /** Apple's limit for one batch of a custom code. */
  const MAX_USES = 25000;
  /** Apple's limit for how far ahead a code may end. */
  const CODE_MAX_MONTHS = 6;
  const CODE_MIN_LENGTH = 3;
  /** Apple's limit for a custom code. */
  const CODE_MAX_LENGTH = 64;
  const MAX_NAME_LENGTH = 80;
  const MAX_NOTE_LENGTH = 200;
  const MAX_PAYOUT_USD = 100000;
  /** Who an offer is for: people who never bought anything in the app. */
  const ELIGIBILITY = ['NON_SPENDER'];
  /** What Apple keeps from a sale, for the preview: 30% now, 15% on the Small Business Program. */
  const KEEP_RATES = [0.70, 0.85];

  const EM_DASH = String.fromCharCode(0x2014);

  // ---- Codes and links --------------------------------------------------

  /** What the Code field keeps as you type: Latin letters and digits, upper case. */
  function normalizeCode(raw) {
    return String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, CODE_MAX_LENGTH);
  }

  /** The Apple offer's reference name, which the webhook matches on (trimmed, lower case). */
  function offerRefFor(code) {
    return 'creator-' + String(code || '').trim().toLowerCase();
  }

  /** The link a creator shares: opens the App Store with the code filled in. */
  function shareLinkFor(code) {
    return 'https://apps.apple.com/redeem?ctx=offercodes&id=' + APP_APPLE_ID + '&code=' + encodeURIComponent(String(code || ''));
  }

  // ---- Money, in whole cents ---------------------------------------------

  function toCents(usd) {
    return Math.round(Number(usd) * 100);
  }

  function money(cents) {
    const c = Math.round(Number(cents) || 0);
    const sign = c < 0 ? '-' : '';
    const abs = Math.abs(c);
    return sign + '$' + Math.floor(abs / 100).toLocaleString('en-US') + '.' + String(abs % 100).padStart(2, '0');
  }

  /**
   * The Apple US price point at or below [targetCents]. In the range a code
   * can land in, the points GrowDaily uses end in .49 or .99 (Apple also has
   * .00, .90 and .95 points; the tool never picks those). Round down, so a
   * code never costs more than the discount promised. Null below $0.49.
   */
  function pricePointAtOrBelow(targetCents) {
    const k = Math.floor((Math.floor(targetCents) + 1) / 50);
    return k >= 1 ? k * 50 - 1 : null;
  }

  /** The buyer's price, in cents, for [discountPercent] off [productId]. */
  function offerPriceCents(productId, discountPercent) {
    const product = PRODUCTS[productId];
    if (!product) return null;
    const base = toCents(product.priceUsd);
    const d = Number(discountPercent);
    if (!Number.isFinite(d) || d <= 0) return base;
    // base * (100 - d) / 100, floored to a cent, in integers.
    const target = Math.floor((base * (100 - d)) / 100);
    return pricePointAtOrBelow(target);
  }

  /** Roughly what Apple sends for a US sale at [priceCents]: keepRate x (price + 1 cent). */
  function proceedsCents(priceCents, keepRate) {
    return Math.round(Number(keepRate) * (priceCents + 1));
  }

  function shareCents(proceeds, sharePercent) {
    return Math.round((proceeds * Number(sharePercent)) / 100);
  }

  /**
   * One sale with this code, US buyer: what the buyer pays, what Apple
   * sends, the creator's share, what Aziz keeps, and what the same sale
   * leaves without a code.
   */
  function moneyPreview({ productId, discountPercent, sharePercent, keepRate }) {
    const product = PRODUCTS[productId] || PRODUCTS[DEFAULT_PRODUCT];
    const rate = KEEP_RATES.includes(Number(keepRate)) ? Number(keepRate) : KEEP_RATES[0];
    const share = Math.min(100, Math.max(0, Number(sharePercent) || 0));
    const baseCents = toCents(product.priceUsd);
    const buyerCents = offerPriceCents(product.productId, discountPercent);
    const proceeds = proceedsCents(buyerCents, rate);
    const creator = shareCents(proceeds, share);
    return {
      productId: product.productId,
      baseCents,
      buyerCents,
      proceedsCents: proceeds,
      creatorCents: creator,
      keepCents: proceeds - creator,
      plainCents: proceedsCents(baseCents, rate),
      percentOffShown: Math.floor((1 - buyerCents / baseCents) * 100 + 1e-9),
      keepRate: rate,
      sharePercent: share,
    };
  }

  // ---- Dates for codes ----------------------------------------------------

  function isRealDateKey(value) {
    const key = String(value || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return false;
    const [y, m, d] = key.split('-').map(Number);
    const probe = new Date(Date.UTC(y, m - 1, d));
    return probe.getUTCFullYear() === y && probe.getUTCMonth() === m - 1 && probe.getUTCDate() === d;
  }

  /** Today's date in Pacific time, the clock Apple ends codes by. */
  function pacificDateKey(nowMs) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(new Date(nowMs));
    const get = (t) => parts.find((p) => p.type === t).value;
    return get('year') + '-' + get('month') + '-' + get('day');
  }

  /** 00:00 Pacific on [dateKey], the moment Apple switches a code off that ends that day. */
  function pacificMidnightMs(dateKey) {
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const wallUtc = Date.UTC(y, m - 1, d, 0, 0);
    let guess = wallUtc + 8 * 60 * 60 * 1000;
    for (let i = 0; i < 2; i++) {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: 'America/Los_Angeles', hourCycle: 'h23',
        year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric',
      }).formatToParts(new Date(guess));
      const get = (t) => Number(parts.find((p) => p.type === t).value);
      const seen = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'));
      guess += wallUtc - seen;
    }
    return guess;
  }

  /** [dateKey] plus [months] calendar months, the day clamped to the month's end. */
  function addMonths(dateKey, months) {
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const first = new Date(Date.UTC(y, m - 1 + months, 1));
    const last = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
    const day = Math.min(d, last);
    return first.getUTCFullYear() + '-' + String(first.getUTCMonth() + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
  }

  function addDaysKey(dateKey, days) {
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const t = new Date(Date.UTC(y, m - 1, d + days));
    return t.getUTCFullYear() + '-' + String(t.getUTCMonth() + 1).padStart(2, '0') + '-' + String(t.getUTCDate()).padStart(2, '0');
  }

  /** The earliest and latest end date the Code field accepts today. */
  function codeEndRange(nowMs) {
    const today = pacificDateKey(nowMs);
    return { min: addDaysKey(today, 1), max: addMonths(today, CODE_MAX_MONTHS) };
  }

  // ---- Checks ---------------------------------------------------------------

  function isWholeCents(n) {
    return Number.isFinite(n) && Math.abs(Math.round(n * 100) - n * 100) < 1e-6;
  }

  function checkSharePercent(value, errors) {
    const n = value;
    if (typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > 100 || !isWholeCents(n)) {
      errors.push({ code: 'share', message: 'The creator share is a percent from 0 to 100, with at most two decimals.' });
      return null;
    }
    return n;
  }

  /**
   * A new creator from the Add form. Returns { ok, errors, value } where
   * value is everything the creators/{CODE} document stores about the deal.
   */
  function checkCreatorInput(input, { nowMs }) {
    const raw = input || {};
    const errors = [];
    const name = typeof raw.name === 'string' ? raw.name.trim() : '';
    if (!name) errors.push({ code: 'name', message: 'Give the creator\'s name, the one you pay them under.' });
    if (name.length > MAX_NAME_LENGTH) errors.push({ code: 'name-long', message: 'The name is ' + name.length + ' characters; keep it to ' + MAX_NAME_LENGTH + '.' });
    if (name.includes(EM_DASH)) errors.push({ code: 'name-dash', message: 'The name has an em dash. Use a comma, a colon or a full stop.' });

    const code = typeof raw.code === 'string' ? raw.code.trim().toUpperCase() : '';
    if (!new RegExp('^[A-Z0-9]{' + CODE_MIN_LENGTH + ',' + CODE_MAX_LENGTH + '}$').test(code)) {
      errors.push({ code: 'code', message: 'The code is ' + CODE_MIN_LENGTH + ' to ' + CODE_MAX_LENGTH + ' Latin letters and digits, nothing else.' });
    }

    const discount = raw.discountPercent;
    if (typeof discount !== 'number' || !Number.isInteger(discount) || discount < MIN_DISCOUNT || discount > MAX_DISCOUNT) {
      errors.push({ code: 'discount', message: 'The buyer discount is a whole percent from ' + MIN_DISCOUNT + ' to ' + MAX_DISCOUNT + '.' });
    }
    const product = PRODUCTS[raw.discountOff];
    if (!product) errors.push({ code: 'product', message: 'Pick which Lifetime price the discount comes off.' });

    const share = checkSharePercent(raw.sharePercent, errors);

    const range = codeEndRange(nowMs);
    const endsOn = raw.codeEndsOn;
    if (!isRealDateKey(endsOn)) {
      errors.push({ code: 'ends', message: 'Pick the day the code ends.' });
    } else if (endsOn < range.min) {
      errors.push({ code: 'ends-past', message: 'The code has to end after today. The earliest end is ' + range.min + '.' });
    } else if (endsOn > range.max) {
      errors.push({ code: 'ends-far', message: 'Apple allows ' + CODE_MAX_MONTHS + ' months at most. The latest end today is ' + range.max + '; renew it with a new batch later.' });
    }

    const uses = raw.usesAllowed;
    if (typeof uses !== 'number' || !Number.isInteger(uses) || uses < MIN_USES || uses > MAX_USES) {
      errors.push({ code: 'uses', message: 'Uses allowed is a whole number from ' + MIN_USES + ' to ' + MAX_USES.toLocaleString('en-US') + ' (Apple\'s limit for one batch).' });
    }

    if (errors.length) return { ok: false, errors, value: null };
    const priceCents = offerPriceCents(product.productId, discount);
    return {
      ok: true,
      errors,
      value: {
        name,
        code,
        offerRef: offerRefFor(code),
        discountPercent: discount,
        discountOff: product.productId,
        offerPriceUsd: priceCents / 100,
        sharePercent: share,
        codeEndsOn: endsOn,
        codeEndsAtMs: pacificMidnightMs(endsOn),
        usesAllowed: uses,
      },
    };
  }

  /** A new share percent for an existing creator. */
  function checkShareChange(value) {
    const errors = [];
    const share = checkSharePercent(value, errors);
    return { ok: errors.length === 0, errors, value: share };
  }

  /** A payout. It can't be more than the creator has earned and not been paid. */
  function checkPayout(input, { unpaidCents }) {
    const raw = input || {};
    const errors = [];
    const amount = raw.amountUsd;
    if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0 || amount > MAX_PAYOUT_USD || !isWholeCents(amount)) {
      errors.push({ code: 'amount', message: 'The amount is in US dollars, more than zero, with at most two decimals.' });
    } else if (toCents(amount) > unpaidCents) {
      errors.push({ code: 'amount-over', message: money(toCents(amount)) + ' is more than this creator has earned and not been paid (' + money(unpaidCents) + ').' });
    }
    const note = typeof raw.note === 'string' ? raw.note.trim() : '';
    if (note.length > MAX_NOTE_LENGTH) errors.push({ code: 'note', message: 'Keep the note to ' + MAX_NOTE_LENGTH + ' characters.' });
    if (note.includes(EM_DASH)) errors.push({ code: 'note-dash', message: 'The note has an em dash. Use a comma, a colon or a full stop.' });
    return { ok: errors.length === 0, errors, value: errors.length ? null : { amountUsd: toCents(amount) / 100, note } };
  }

  // ---- The ledger -----------------------------------------------------------

  function shareOf(row) {
    if (row.needsReview === true) return null;
    const v = row.shareUsd;
    if (typeof v !== 'number' || !Number.isFinite(v)) return null;
    // The webhook writes a refund's share as negative. Taking the size and
    // putting the sign back from `kind` gives the same answer either way.
    const cents = Math.abs(toCents(v));
    return row.kind === 'refund' ? -cents : cents;
  }

  /**
   * Per creator and in total: sales, refunds, earned (the PRODUCTION shares,
   * refunds taken off), paid, waiting (earned on sales younger than 60
   * days) and owed (earned on sales 60 or more days old, minus what was
   * paid, never below zero). A refund counts against the age of the sale it
   * refunds, found by transaction id, so refunding an old sale lowers what
   * is owed, even after a payment (it comes off the next one).
   *
   *   creators  [{ id (the code), ...creators doc }]
   *   ledger    creator_ledger rows
   *   payouts   creator_payouts rows
   */
  function creatorTotals({ creators, ledger, payouts, nowMs }) {
    const matureBefore = nowMs - OWED_AFTER_DAYS * DAY_MS;
    const last30 = nowMs - 30 * DAY_MS;
    const byId = new Map();
    for (const c of creators || []) {
      byId.set(c.id, {
        id: c.id,
        sales: 0,
        refunds: 0,
        earnedCents: 0,
        maturedCents: 0,
        youngCents: 0,
        paidCents: 0,
        needsReview: 0,
        sales30: 0,
        refunds30: 0,
        lastSaleAtMs: null,
      });
    }
    const orphans = { rows: 0, offerRefs: [] };
    let sandboxRows = 0;

    const saleAt = new Map();
    for (const row of ledger || []) {
      if (!row || row.environment !== 'PRODUCTION' || row.kind !== 'sale' || !row.transactionId) continue;
      saleAt.set(row.creatorId + '|' + row.transactionId, Number(row.eventAtMs));
    }

    for (const row of ledger || []) {
      if (!row) continue;
      if (row.environment !== 'PRODUCTION') {
        sandboxRows += 1;
        continue;
      }
      const t = byId.get(row.creatorId);
      if (!t) {
        orphans.rows += 1;
        if (row.offerRef && !orphans.offerRefs.includes(row.offerRef)) orphans.offerRefs.push(row.offerRef);
        continue;
      }
      const at = Number(row.eventAtMs);
      if (row.kind === 'sale') {
        t.sales += 1;
        if (at >= last30) t.sales30 += 1;
        if (Number.isFinite(at) && (t.lastSaleAtMs === null || at > t.lastSaleAtMs)) t.lastSaleAtMs = at;
      } else if (row.kind === 'refund') {
        t.refunds += 1;
        if (at >= last30) t.refunds30 += 1;
      } else {
        continue;
      }
      const cents = shareOf(row);
      if (cents === null) {
        t.needsReview += 1;
        continue;
      }
      let age = at;
      if (row.kind === 'refund' && row.transactionId && saleAt.has(row.creatorId + '|' + row.transactionId)) {
        age = saleAt.get(row.creatorId + '|' + row.transactionId);
      }
      t.earnedCents += cents;
      if (Number.isFinite(age) && age <= matureBefore) t.maturedCents += cents;
      else t.youngCents += cents;
    }

    for (const p of payouts || []) {
      const t = p && byId.get(p.creatorId);
      if (!t) continue;
      const cents = toCents(p.amountUsd);
      if (Number.isFinite(cents)) t.paidCents += cents;
    }

    const rows = [];
    const totals = { sales: 0, refunds: 0, earnedCents: 0, paidCents: 0, waitingCents: 0, owedCents: 0, sales30: 0, refunds30: 0, needsReview: 0 };
    for (const t of byId.values()) {
      t.waitingCents = Math.max(0, t.youngCents);
      t.owedCents = Math.max(0, t.maturedCents - t.paidCents);
      t.unpaidCents = Math.max(0, t.earnedCents - t.paidCents);
      rows.push(t);
      for (const k of Object.keys(totals)) totals[k] += t[k];
    }
    return { rows, totals, orphans, sandboxRows };
  }

  /**
   * The Apple offers this tool knows it made. Deactivating a creator here
   * does not turn their offer off in App Store Connect, so it still holds
   * one of Apple's 10 slots and still counts.
   */
  function offersInUse(creators) {
    return (creators || []).filter((c) => c && c.appleOfferCodeId).length;
  }

  // ---- App Store Connect ------------------------------------------------------

  /** The local id an inline-created price goes by inside one request. */
  function priceLocalId(territory) {
    return '${price-' + territory + '}';
  }

  /**
   * POST /v1/inAppPurchaseOfferCodes: the offer itself, on [iapId], named
   * [offerRef], for people who never bought anything in the app, at one
   * price per territory ([prices], each { territory, pricePointId }).
   */
  function buildOfferCodeRequest({ iapId, offerRef, prices }) {
    return {
      method: 'POST',
      path: '/v1/inAppPurchaseOfferCodes',
      body: {
        data: {
          type: 'inAppPurchaseOfferCodes',
          attributes: {
            name: offerRef,
            customerEligibilities: ELIGIBILITY.slice(),
          },
          relationships: {
            inAppPurchase: { data: { type: 'inAppPurchases', id: String(iapId) } },
            prices: { data: prices.map((p) => ({ type: 'inAppPurchaseOfferPrices', id: priceLocalId(p.territory) })) },
          },
        },
        included: prices.map((p) => ({
          type: 'inAppPurchaseOfferPrices',
          id: priceLocalId(p.territory),
          relationships: {
            territory: { data: { type: 'territories', id: p.territory } },
            pricePoint: { data: { type: 'inAppPurchasePricePoints', id: p.pricePointId } },
          },
        })),
      },
    };
  }

  /**
   * POST /v1/inAppPurchaseOfferCodeCustomCodes: the code people type, under
   * the offer, good for [usesAllowed] redemptions until [expirationDate]
   * (YYYY-MM-DD; Apple ends it at 00:00 Pacific that day).
   */
  function buildCustomCodeRequest({ offerCodeId, code, usesAllowed, expirationDate }) {
    return {
      method: 'POST',
      path: '/v1/inAppPurchaseOfferCodeCustomCodes',
      body: {
        data: {
          type: 'inAppPurchaseOfferCodeCustomCodes',
          attributes: {
            customCode: code,
            numberOfCodes: usesAllowed,
            expirationDate,
          },
          relationships: {
            offerCode: { data: { type: 'inAppPurchaseOfferCodes', id: String(offerCodeId) } },
          },
        },
      },
    };
  }

  /** The US price point whose customer price is exactly [targetCents], from GET /v2/inAppPurchases/{id}/pricePoints. */
  function pickUsPricePoint(points, targetCents) {
    for (const p of points || []) {
      const territory = p && p.relationships && p.relationships.territory && p.relationships.territory.data;
      if (territory && territory.id !== 'USA') continue;
      const price = p && p.attributes && Number(p.attributes.customerPrice);
      if (Number.isFinite(price) && toCents(price) === targetCents) {
        return { id: p.id, customerPrice: p.attributes.customerPrice, proceeds: p.attributes.proceeds };
      }
    }
    return null;
  }

  /**
   * One price per territory: the US point, then Apple's equalized point for
   * every other territory (GET /v1/inAppPurchasePricePoints/{id}/equalizations),
   * kept to the territories the product is sold in when that list is known.
   * This is what App Store Connect's own "comparable prices" step does.
   */
  function equalizedPrices({ usPoint, equalizations, currencies, availableTerritories }) {
    const allowed = availableTerritories ? new Set(availableTerritories) : null;
    const out = [{ territory: 'USA', pricePointId: usPoint.id, customerPrice: usPoint.customerPrice, currency: 'USD' }];
    const seen = new Set(['USA']);
    for (const p of equalizations || []) {
      const t = p && p.relationships && p.relationships.territory && p.relationships.territory.data && p.relationships.territory.data.id;
      if (!t || seen.has(t)) continue;
      if (allowed && !allowed.has(t)) continue;
      seen.add(t);
      out.push({
        territory: t,
        pricePointId: p.id,
        customerPrice: p.attributes ? p.attributes.customerPrice : null,
        currency: (currencies && currencies[t]) || null,
      });
    }
    return out;
  }

  /** The territories a plan summary names first, the ones GrowDaily sells most in. */
  const SAMPLE_TERRITORIES = ['USA', 'BHR', 'SAU', 'ARE', 'KWT', 'QAT', 'OMN', 'EGY', 'GBR', 'DEU'];

  return {
    DAY_MS,
    APP_APPLE_ID,
    PRODUCTS,
    DEFAULT_PRODUCT,
    DEFAULT_SHARE_PERCENT,
    MAX_ACTIVE_OFFERS,
    OWED_AFTER_DAYS,
    MIN_DISCOUNT,
    MAX_DISCOUNT,
    MIN_USES,
    MAX_USES,
    CODE_MAX_MONTHS,
    CODE_MIN_LENGTH,
    CODE_MAX_LENGTH,
    MAX_NAME_LENGTH,
    MAX_NOTE_LENGTH,
    ELIGIBILITY,
    KEEP_RATES,
    SAMPLE_TERRITORIES,
    normalizeCode,
    offerRefFor,
    shareLinkFor,
    toCents,
    money,
    pricePointAtOrBelow,
    offerPriceCents,
    proceedsCents,
    shareCents,
    moneyPreview,
    isRealDateKey,
    pacificDateKey,
    pacificMidnightMs,
    addMonths,
    codeEndRange,
    checkCreatorInput,
    checkShareChange,
    checkPayout,
    creatorTotals,
    offersInUse,
    priceLocalId,
    buildOfferCodeRequest,
    buildCustomCodeRequest,
    pickUsPricePoint,
    equalizedPrices,
  };
});
