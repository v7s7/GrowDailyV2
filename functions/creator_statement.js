/**
 * A creator's own statement: what their code sold and what they earned,
 * for the private page each creator opens from their link
 * (public/creator/index.html, served through the creatorStatement function
 * in index.js).
 *
 * WHY A PAGE AND NOT THE APP. The money is the creator's business, not the
 * app's, and a screen inside the app that pays people for other people's
 * purchases is the kind of thing App Review asks about. So the app has no
 * creator screen at all; each creator gets a link Aziz sends them.
 *
 * THE LINK IS THE KEY. A creator's link carries a random key (32 bytes,
 * base64url, 43 characters) in its #fragment, which a browser never sends
 * to any server on its own, so it is not in any log or Referer. The page
 * posts it to the function. Only the key's SHA-256 is stored, on
 * creators/{CODE}.statementKeyHash, written by the admin tool when Aziz
 * makes the link; making a new link replaces the hash, and the old link
 * stops working at once. [statementKeyHash] here and the admin tool's
 * lib/creators.js hash the key the same way, and a test holds them to it.
 *
 * THE SAME SUMS AS THE ADMIN TOOL. Earned, paid, waiting and owed are
 * worked out exactly as the Creators page works them out
 * (scripts/admin_lookup/lib/creators.js, creatorTotals): production rows
 * only, a refund taken back at the age of the sale it refunds, a sale
 * payable once it is [OWED_AFTER_DAYS] old. A creator and Aziz must never
 * see two different numbers, so functions/test/creator_statement.test.js
 * runs both on the same rows and requires the same answer.
 *
 * WHAT IT NEVER SHOWS. No buyer: not their account id, not the store's
 * transaction id, nothing that points at a person. A row is a date, a
 * product, a price and a share.
 */

"use strict";

const crypto = require("crypto");

const DAY_MS = 24 * 60 * 60 * 1000;

/** Must match OWED_AFTER_DAYS in scripts/admin_lookup/lib/creators.js. */
const OWED_AFTER_DAYS = 60;

/** GrowDaily's App Store id, for the link a creator shares. */
const APP_APPLE_ID = "6788149393";

/** Bahrain is UTC+3 all year, which is how months are grouped. */
const BAHRAIN_OFFSET_MS = 3 * 60 * 60 * 1000;

/** How many of the latest sales and refunds the page lists one by one. */
const RECENT_LIMIT = 60;

/** A statement key: 32 random bytes in base64url, no padding. */
const KEY_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/**
 * The stored form of a statement key, or null for anything that is not a
 * well-formed key (checked before hashing, so junk never reaches a query).
 * @param {*} key What the page sent.
 * @return {?string} Lowercase hex SHA-256 of the key.
 */
function statementKeyHash(key) {
  if (typeof key !== "string" || !KEY_PATTERN.test(key)) return null;
  return crypto.createHash("sha256").update(key, "utf8").digest("hex");
}

/**
 * Whole cents, the way the admin tool counts them.
 * @param {*} usd A dollar amount.
 * @return {number} Cents, possibly NaN.
 */
function toCents(usd) {
  return Math.round(Number(usd) * 100);
}

/**
 * A ledger row's share in cents, negative for a refund, or null when the
 * webhook could not work one out (needsReview) and nothing is counted.
 * Same as shareOf in the admin tool.
 * @param {object} row A creator_ledger row.
 * @return {?number} Cents.
 */
function shareCentsOf(row) {
  if (row.needsReview === true) return null;
  const v = row.shareUsd;
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  const cents = Math.abs(toCents(v));
  return row.kind === "refund" ? -cents : cents;
}

/**
 * Milliseconds from a number or a Firestore Timestamp, else null.
 * @param {*} value The stored value.
 * @return {?number} Milliseconds since the epoch.
 */
function msOf(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  return null;
}

/**
 * "2026-09" for the Bahrain month [ms] falls in.
 * @param {number} ms Milliseconds since the epoch.
 * @return {string} Year and month.
 */
function bahrainMonthKey(ms) {
  const d = new Date(ms + BAHRAIN_OFFSET_MS);
  return d.getUTCFullYear() + "-" +
    String(d.getUTCMonth() + 1).padStart(2, "0");
}

/**
 * The link a creator shares: the App Store with their code filled in.
 * @param {string} code The creator's code.
 * @return {string} The redeem link.
 */
function shareLinkFor(code) {
  return "https://apps.apple.com/redeem?ctx=offercodes&id=" + APP_APPLE_ID +
    "&code=" + encodeURIComponent(String(code || ""));
}

/**
 * The money, in cents, from a creator's ledger rows and payouts: the same
 * rule set as creatorTotals in the admin tool, for one creator.
 *
 * owed is capped at what is earned and not yet paid, and waiting is what
 * is left of that, so paid + owed + waiting always adds up to what the
 * creator earned (when a payment ran ahead of the 60 days, the early part
 * comes off waiting, not off nothing).
 *
 * @param {object} args
 * @param {string} args.creatorId The creator's code (document id).
 * @param {object[]} args.ledger Their creator_ledger rows.
 * @param {object[]} args.payouts Their creator_payouts rows.
 * @param {number} args.nowMs Now.
 * @return {object} The sums, and per-row facts for the list.
 */
function moneyFor({creatorId, ledger, payouts, nowMs}) {
  const matureBefore = nowMs - OWED_AFTER_DAYS * DAY_MS;
  const last30 = nowMs - 30 * DAY_MS;
  const rows = (ledger || []).filter((r) => r &&
    r.environment === "PRODUCTION" && r.creatorId === creatorId &&
    (r.kind === "sale" || r.kind === "refund"));

  const saleAt = new Map();
  const refunded = new Set();
  for (const r of rows) {
    if (r.kind === "sale" && r.transactionId) {
      saleAt.set(r.transactionId, Number(r.eventAtMs));
    }
    if (r.kind === "refund" && r.transactionId) refunded.add(r.transactionId);
  }

  const m = {
    sales: 0, refunds: 0, sales30: 0, refunds30: 0, needsReview: 0,
    earnedCents: 0, maturedCents: 0, youngCents: 0, paidCents: 0,
    nextReadyAtMs: null, lastSaleAtMs: null,
  };
  for (const r of rows) {
    const at = Number(r.eventAtMs);
    if (r.kind === "sale") {
      m.sales += 1;
      if (at >= last30) m.sales30 += 1;
      if (Number.isFinite(at) &&
          (m.lastSaleAtMs === null || at > m.lastSaleAtMs)) {
        m.lastSaleAtMs = at;
      }
    } else {
      m.refunds += 1;
      if (at >= last30) m.refunds30 += 1;
    }
    const cents = shareCentsOf(r);
    if (cents === null) {
      m.needsReview += 1;
      continue;
    }
    let age = at;
    if (r.kind === "refund" && r.transactionId &&
        saleAt.has(r.transactionId)) {
      age = saleAt.get(r.transactionId);
    }
    m.earnedCents += cents;
    if (Number.isFinite(age) && age <= matureBefore) {
      m.maturedCents += cents;
    } else {
      m.youngCents += cents;
      // The next day money becomes payable: the youngest-but-oldest sale
      // still waiting, unless it was refunded (then it never will).
      if (r.kind === "sale" && Number.isFinite(at) &&
          !(r.transactionId && refunded.has(r.transactionId))) {
        const readyAt = at + OWED_AFTER_DAYS * DAY_MS;
        if (m.nextReadyAtMs === null || readyAt < m.nextReadyAtMs) {
          m.nextReadyAtMs = readyAt;
        }
      }
    }
  }
  for (const p of payouts || []) {
    if (!p || p.creatorId !== creatorId) continue;
    const cents = toCents(p.amountUsd);
    if (Number.isFinite(cents)) m.paidCents += cents;
  }
  m.unpaidCents = Math.max(0, m.earnedCents - m.paidCents);
  m.owedCents = Math.min(m.unpaidCents,
      Math.max(0, m.maturedCents - m.paidCents));
  m.waitingCents = m.unpaidCents - m.owedCents;
  return {money: m, rows, saleAt, refunded, matureBefore};
}

/**
 * Everything the creator's page shows, from their creators document, their
 * ledger rows and their payouts. Pure: the function does the reading.
 *
 * @param {object} args
 * @param {string} args.id The creator's code (the document id).
 * @param {object} args.creator The creators document's data.
 * @param {object[]} args.ledger Their creator_ledger rows.
 * @param {object[]} args.payouts Their creator_payouts rows.
 * @param {number} args.nowMs Now.
 * @return {object} The statement.
 */
function buildStatement({id, creator, ledger, payouts, nowMs}) {
  const c = creator || {};
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);
  const {money, rows, refunded, matureBefore} =
    moneyFor({creatorId: id, ledger, payouts, nowMs});

  const months = new Map();
  for (const r of rows) {
    const at = Number(r.eventAtMs);
    if (!Number.isFinite(at)) continue;
    const key = bahrainMonthKey(at);
    if (!months.has(key)) {
      months.set(key, {month: key, sales: 0, refunds: 0, shareCents: 0});
    }
    const mo = months.get(key);
    if (r.kind === "sale") mo.sales += 1;
    else mo.refunds += 1;
    const cents = shareCentsOf(r);
    if (cents !== null) mo.shareCents += cents;
  }

  const recent = rows
      .filter((r) => Number.isFinite(Number(r.eventAtMs)))
      .sort((a, b) => Number(b.eventAtMs) - Number(a.eventAtMs))
      .slice(0, RECENT_LIMIT)
      .map((r) => {
        const at = Number(r.eventAtMs);
        const cents = shareCentsOf(r);
        let status;
        let readyAtMs = null;
        if (r.kind === "refund") {
          status = "refund";
        } else if (r.transactionId && refunded.has(r.transactionId)) {
          status = "refunded";
        } else if (cents === null) {
          status = "review";
        } else if (at <= matureBefore) {
          status = "cleared";
        } else {
          status = "waiting";
          readyAtMs = at + OWED_AFTER_DAYS * DAY_MS;
        }
        return {
          atMs: at,
          kind: r.kind,
          productId: typeof r.productId === "string" ? r.productId : null,
          store: typeof r.store === "string" ? r.store : null,
          priceUsd: num(r.priceUsd),
          shareCents: cents,
          status,
          readyAtMs,
        };
      });

  const paid = (payouts || [])
      .filter((p) => p && p.creatorId === id)
      .map((p) => ({
        paidAtMs: msOf(p.paidAt),
        amountCents: toCents(p.amountUsd),
        note: typeof p.note === "string" ? p.note : "",
      }))
      .filter((p) => Number.isFinite(p.amountCents))
      .sort((a, b) => (b.paidAtMs || 0) - (a.paidAtMs || 0));

  const code = typeof c.code === "string" && c.code ? c.code : id;
  const endsAtMs = msOf(c.codeEndsAt);
  return {
    creator: {
      name: typeof c.name === "string" ? c.name : "",
      code,
      sharePercent: num(c.sharePercent),
      discountPercent: num(c.discountPercent),
      offerPriceUsd: num(c.offerPriceUsd),
      codeEndsAtMs: endsAtMs,
      codeEnded: endsAtMs !== null && endsAtMs <= nowMs,
      active: c.active !== false,
      hasAppleCode: typeof c.appleCustomCodeId === "string" &&
        c.appleCustomCodeId !== "",
      shareLink: shareLinkFor(code),
    },
    money: {
      earnedCents: money.earnedCents,
      paidCents: money.paidCents,
      owedCents: money.owedCents,
      waitingCents: money.waitingCents,
      nextReadyAtMs: money.waitingCents > 0 ? money.nextReadyAtMs : null,
    },
    counts: {
      sales: money.sales,
      refunds: money.refunds,
      sales30: money.sales30,
      refunds30: money.refunds30,
      needsReview: money.needsReview,
    },
    months: [...months.values()].sort((a, b) =>
      (a.month < b.month ? 1 : a.month > b.month ? -1 : 0)),
    recent,
    payouts: paid,
    holdDays: OWED_AFTER_DAYS,
    nowMs,
  };
}

module.exports = {
  APP_APPLE_ID,
  KEY_PATTERN,
  OWED_AFTER_DAYS,
  RECENT_LIMIT,
  bahrainMonthKey,
  buildStatement,
  moneyFor,
  shareLinkFor,
  statementKeyHash,
};
