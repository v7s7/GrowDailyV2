/**
 * The Sale page's rules, shared by the browser and the server, the same way
 * wording/rules.js is: the page runs them as Aziz types, so a refusal shows
 * before he presses Schedule, and the server runs them again inside the
 * write, so nothing the page misses (or a request that never came from the
 * page) can reach offers/live, the document every phone reads.
 *
 * Why the rules exist (Aziz, 2026-09-22). A sale is only honest if the
 * crossed-out price is a price people really paid. Consumer law and Apple
 * guideline 2.3.1 both look at the same things, so a sale here:
 *
 *   - starts 30 or more days after the later of the day Lifetime moved to
 *     its full price (fullPriceSince) and the end of the previous sale
 *   - lasts 30 days at most, and never longer than the full-price stretch
 *     right before it
 *   - keeps the total under 90 sale days in any rolling 365 days
 *   - never overlaps another sale, and ends after it starts
 *
 * offers/live holds ONE sale (the current or the next), so the page also
 * schedules one at a time: the next is scheduled once the last has ended or
 * was cancelled.
 *
 * Also here, because it is the same arithmetic over the same sales: the
 * "Who pays full price" meter's sorting of purchases.
 *
 * Every time is milliseconds since the epoch. Bahrain is UTC+3 all year (no
 * daylight saving), which is what the form's dates and times mean.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.SaleRules = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const MINUTE_MS = 60 * 1000;
  const HOUR_MS = 60 * MINUTE_MS;
  const DAY_MS = 24 * HOUR_MS;
  const BAHRAIN_OFFSET_MS = 3 * HOUR_MS;

  /** The two Lifetime prices, in US dollars (Aziz, 2026-09-22). */
  const FULL_PRICE_USD = 39.99;
  const OFFER_PRICE_USD = 29.99;
  const FULL_PRODUCT_ID = 'growdaily_lifetime';
  const OFFER_PRODUCT_ID = 'growdaily_lifetime_offer';

  const MIN_FULL_PRICE_DAYS = 30;
  const MAX_SALE_DAYS = 30;
  const MAX_SALE_DAYS_PER_YEAR = 90;
  const YEAR_DAYS = 365;

  const WELCOME_MIN_HOURS = 24;
  const WELCOME_MAX_HOURS = 168;
  const WELCOME_DEFAULT_HOURS = 72;

  /** A sale's name sits in a narrow banner on the phone. */
  const MAX_NAME_LENGTH = 40;
  /** How far in the past a start may be (the minutes between typing and pressing Schedule). */
  const START_GRACE_MS = 15 * MINUTE_MS;
  /** The meter looks back this far. */
  const METER_DAYS = 90;

  const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const EM_DASH = String.fromCharCode(0x2014);

  // ---- Bahrain dates and times ------------------------------------------

  function pad2(n) {
    return (n < 10 ? '0' : '') + n;
  }

  /** True only for a date that exists (not 2027-02-30). */
  function isRealDateKey(value) {
    const key = String(value || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return false;
    const [y, m, d] = key.split('-').map(Number);
    const probe = new Date(Date.UTC(y, m - 1, d));
    return probe.getUTCFullYear() === y && probe.getUTCMonth() === m - 1 && probe.getUTCDate() === d;
  }

  function isTime(value) {
    return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(value || ''));
  }

  /** A Bahrain date and 'HH:MM' as an instant, or null when either is not real. */
  function bahrainMs(dateKey, time) {
    if (!isRealDateKey(dateKey)) return null;
    const t = time === undefined || time === null || time === '' ? '00:00' : time;
    if (!isTime(t)) return null;
    const [y, m, d] = String(dateKey).split('-').map(Number);
    const [hh, mm] = String(t).split(':').map(Number);
    return Date.UTC(y, m - 1, d, hh, mm) - BAHRAIN_OFFSET_MS;
  }

  /** The Bahrain wall clock at [ms]. */
  function bahrainParts(ms) {
    const d = new Date(ms + BAHRAIN_OFFSET_MS);
    const y = d.getUTCFullYear();
    const m = d.getUTCMonth();
    const day = d.getUTCDate();
    return {
      dateKey: y + '-' + pad2(m + 1) + '-' + pad2(day),
      time: pad2(d.getUTCHours()) + ':' + pad2(d.getUTCMinutes()),
      year: y,
      month: m,
      day,
      weekday: d.getUTCDay(),
    };
  }

  /** '27 Feb 2027' */
  function shortDate(ms) {
    const p = bahrainParts(ms);
    return p.day + ' ' + MONTHS[p.month].slice(0, 3) + ' ' + p.year;
  }

  /** 'Saturday 27 February 2027' */
  function longDate(ms) {
    const p = bahrainParts(ms);
    return WEEKDAYS[p.weekday] + ' ' + p.day + ' ' + MONTHS[p.month] + ' ' + p.year;
  }

  /** 'Saturday 27 February 2027 at 00:00' */
  function longDateTime(ms) {
    return longDate(ms) + ' at ' + bahrainParts(ms).time;
  }

  /** Whole days a span covers, counting a day that is a minute short as whole (00:00 to 23:59). */
  function spanDays(ms) {
    return Math.max(0, Math.ceil((ms - MINUTE_MS) / DAY_MS));
  }

  /** Days to say for a span, one decimal when it is not whole. */
  function daysText(ms) {
    const exact = ms / DAY_MS;
    const n = Math.abs(exact - Math.round(exact)) < 1 / 1440 ? Math.round(exact) : Math.round(exact * 10) / 10;
    return n + (n === 1 ? ' day' : ' days');
  }

  // ---- Sales ------------------------------------------------------------

  /** [v] when it is a finite number, else NaN. Not Number(v): Number(null) is 0. */
  function num(v) {
    return typeof v === 'number' && Number.isFinite(v) ? v : NaN;
  }

  /** Where a sale really ended: its end, or earlier when it was ended early. */
  function effectiveEnd(sale) {
    const end = num(sale.endsAtMs);
    const early = sale.endedEarlyAtMs;
    return typeof early === 'number' && Number.isFinite(early) ? Math.min(end, early) : end;
  }

  /** A sale's real span, or null for one cancelled before it ever started. */
  function ranSpan(sale) {
    if (!sale || !Number.isFinite(num(sale.startsAtMs)) || !Number.isFinite(num(sale.endsAtMs))) return null;
    const start = sale.startsAtMs;
    const end = effectiveEnd(sale);
    return end > start ? { start, end } : null;
  }

  function saleLabel(sale) {
    const name = (sale.nameEn || sale.nameAr || 'A sale').trim();
    return name + ' (' + shortDate(sale.startsAtMs) + ' to ' + shortDate(effectiveEnd(sale)) + ')';
  }

  /** Sales that ran or will run, sorted by start, each with its real span. */
  function realSales(sales, ignoreId) {
    return (sales || [])
      .filter((s) => s && s.id !== ignoreId)
      .map((s) => ({ sale: s, span: ranSpan(s) }))
      .filter((x) => x.span)
      .sort((a, b) => a.span.start - b.span.start);
  }

  /** The sale running now, else the next one scheduled, else null. */
  function liveSale(sales, nowMs) {
    const list = realSales(sales).filter((x) => x.span.end > nowMs);
    return list.length ? list[0].sale : null;
  }

  /** Where the full-price stretch before [startMs] began: the later of fullPriceSince and the previous sale's end. */
  function stretchStartBefore(startMs, fullPriceSinceMs, list) {
    let from = fullPriceSinceMs;
    for (const x of list) {
      if (x.span.end <= startMs && x.span.end > from) from = x.span.end;
    }
    return from;
  }

  /** Sale time inside [from, to), over every real sale. */
  function saleTimeWithin(spans, from, to) {
    let total = 0;
    for (const s of spans) {
      const a = Math.max(s.start, from);
      const b = Math.min(s.end, to);
      if (b > a) total += b - a;
    }
    return total;
  }

  /**
   * The busiest 365-day window that touches [span], with [spans] (which
   * include it). The busiest window always starts or ends on a sale's start
   * or end, so only those are tried.
   */
  function busiestYearAround(span, spans) {
    const year = YEAR_DAYS * DAY_MS;
    const starts = [];
    for (const s of spans) starts.push(s.start, s.end, s.start - year, s.end - year);
    let best = { from: span.start, to: span.start + year, total: 0 };
    for (const from of starts) {
      const to = from + year;
      if (to <= span.start || from >= span.end) continue;
      const total = saleTimeWithin(spans, from, to);
      if (total > best.total) best = { from, to, total };
    }
    return best;
  }

  function checkNames(nameAr, nameEn, errors) {
    const ar = typeof nameAr === 'string' ? nameAr.trim() : '';
    const en = typeof nameEn === 'string' ? nameEn.trim() : '';
    if (!ar || !en) {
      errors.push({ code: 'names', message: 'Give the sale a name in Arabic and in English. Phones show the one in their language.' });
    }
    for (const [label, value] of [['Arabic', ar], ['English', en]]) {
      if (value.length > MAX_NAME_LENGTH) {
        errors.push({ code: 'name-too-long', message: 'The ' + label + ' name is ' + value.length + ' characters. Keep it to ' + MAX_NAME_LENGTH + ', it sits in a small banner.' });
      }
      if (value.includes(EM_DASH)) {
        errors.push({ code: 'name-dash', message: 'The ' + label + ' name has an em dash. Use a comma, a colon or a full stop.' });
      }
    }
    return { ar, en };
  }

  /**
   * Whether a sale may be scheduled. Returns { ok, errors, facts }: every
   * rule it breaks, each with a code (for tests) and a message (for Aziz),
   * and the facts the page shows beside it.
   *
   *   proposed  { startsAtMs, endsAtMs, nameAr, nameEn }
   *   context   { fullPriceSinceMs (null when not set), sales (from
   *             offer_sales, with endedEarlyAtMs where one was ended early),
   *             nowMs, ignoreId (a sale to leave out, when re-checking one
   *             that is already saved) }
   */
  function checkSale(proposed, context) {
    const errors = [];
    const ctx = context || {};
    const nowMs = num(ctx.nowMs);
    const p = proposed || {};
    checkNames(p.nameAr, p.nameEn, errors);

    const start = num(p.startsAtMs);
    const end = num(p.endsAtMs);
    const facts = { durationMs: null, stretchMs: null, earliestStartMs: null, fullPriceUntilMs: null, yearSaleMs: null, yearFromMs: null };

    const fullPriceSinceMs = typeof ctx.fullPriceSinceMs === 'number' && Number.isFinite(ctx.fullPriceSinceMs) ? ctx.fullPriceSinceMs : null;
    if (fullPriceSinceMs === null) {
      errors.push({ code: 'no-full-price-since', message: 'Set the day Lifetime moved to its full price ($' + FULL_PRICE_USD + ') first. No sale can be checked against the 30-day rule until that day is known.' });
    }
    if (!Number.isFinite(start) || !Number.isFinite(end)) {
      errors.push({ code: 'bad-dates', message: 'Enter a real start and end, both a date and a time.' });
      return { ok: false, errors, facts };
    }
    if (end <= start) {
      errors.push({ code: 'end-before-start', message: 'The sale has to end after it starts.' });
      return { ok: false, errors, facts };
    }
    facts.durationMs = end - start;
    facts.fullPriceUntilMs = end + MIN_FULL_PRICE_DAYS * DAY_MS;

    if (Number.isFinite(nowMs) && start < nowMs - START_GRACE_MS) {
      errors.push({ code: 'starts-in-past', message: 'The start, ' + longDateTime(start) + ', is in the past. A sale can start now at the earliest.' });
    }
    if (end - start > MAX_SALE_DAYS * DAY_MS) {
      errors.push({ code: 'too-long', message: 'A sale lasts ' + MAX_SALE_DAYS + ' days at most. This one runs ' + daysText(end - start) + '.' });
    }

    const list = realSales(ctx.sales, ctx.ignoreId);
    const live = Number.isFinite(nowMs) ? list.filter((x) => x.span.end > nowMs) : [];
    if (live.length) {
      const other = live[0].sale;
      const running = live[0].span.start <= nowMs;
      errors.push({
        code: 'one-at-a-time',
        message: saleLabel(other) + (running ? ' is running now.' : ' is already scheduled.') +
          ' Phones hold one sale at a time, so ' + (running ? 'end it first, or schedule this one after it ends.' : 'cancel it first, or schedule this one after it ends.'),
      });
    }
    for (const x of list) {
      if (x.span.start < end && start < x.span.end) {
        errors.push({ code: 'overlap', message: 'It overlaps ' + saleLabel(x.sale) + '. Sales never overlap.' });
      }
    }

    if (fullPriceSinceMs !== null) {
      const from = stretchStartBefore(start, fullPriceSinceMs, list);
      const stretch = start - from;
      facts.stretchMs = stretch;
      facts.earliestStartMs = from + MIN_FULL_PRICE_DAYS * DAY_MS;
      if (stretch < MIN_FULL_PRICE_DAYS * DAY_MS) {
        errors.push({
          code: 'too-soon',
          message: 'Lifetime has to be at its full price for ' + MIN_FULL_PRICE_DAYS + ' days before a sale. ' +
            (from === fullPriceSinceMs ? 'It has been at full price since ' : 'The last sale ended on ') + shortDate(from) +
            ', so the earliest start is ' + longDateTime(facts.earliestStartMs) + '.',
        });
      }
      if (end - start > stretch) {
        errors.push({
          code: 'longer-than-stretch',
          message: 'A sale can\'t last longer than the full-price stretch right before it. Lifetime will have been at full price for ' +
            daysText(stretch) + ' when it starts, and the sale runs ' + daysText(end - start) + '.',
        });
      }

      // The sale after this one, if any, needs its own 30 days and its own
      // stretch, now counted from this sale's end.
      const next = list.find((x) => x.span.start >= end);
      if (next) {
        const gap = next.span.start - end;
        if (gap < MIN_FULL_PRICE_DAYS * DAY_MS) {
          errors.push({ code: 'next-too-soon', message: 'It ends ' + daysText(gap) + ' before ' + saleLabel(next.sale) + ' starts. Lifetime needs ' + MIN_FULL_PRICE_DAYS + ' days at full price between two sales.' });
        }
        if (next.span.end - next.span.start > gap) {
          errors.push({ code: 'next-longer-than-stretch', message: saleLabel(next.sale) + ' would then run longer than the full-price stretch before it (' + daysText(gap) + ').' });
        }
      }
    }

    const spans = list.map((x) => x.span).concat([{ start, end }]);
    const busiest = busiestYearAround({ start, end }, spans);
    facts.yearSaleMs = busiest.total;
    facts.yearFromMs = busiest.from;
    if (busiest.total > MAX_SALE_DAYS_PER_YEAR * DAY_MS) {
      errors.push({
        code: 'year-cap',
        message: 'At most ' + MAX_SALE_DAYS_PER_YEAR + ' sale days in any 365 days. With this sale, the 365 days from ' +
          shortDate(busiest.from) + ' to ' + shortDate(busiest.to) + ' would have ' + daysText(busiest.total) + ' on sale.',
      });
    }

    return { ok: errors.length === 0, errors, facts };
  }

  /**
   * Where things stand, for the banner at the top of the page: a sale
   * running, one scheduled, or none; how long Lifetime has been at its full
   * price; and whether a sale may start now.
   */
  function saleStatus({ fullPriceSinceMs, sales, nowMs }) {
    const list = realSales(sales);
    const live = list.find((x) => x.span.end > nowMs) || null;
    const spans = list.map((x) => x.span);
    const yearSaleMs = saleTimeWithin(spans, nowMs - YEAR_DAYS * DAY_MS, nowMs);
    const out = {
      state: 'none',
      sale: null,
      fullPriceSet: typeof fullPriceSinceMs === 'number' && Number.isFinite(fullPriceSinceMs),
      atFullPriceSinceMs: null,
      daysAtFullPrice: null,
      earliestStartMs: null,
      canStartNow: false,
      yearSaleMs,
    };
    if (live) {
      out.state = live.span.start <= nowMs ? 'running' : 'scheduled';
      out.sale = live.sale;
    }
    if (!out.fullPriceSet) return out;
    if (out.state === 'running') {
      out.daysAtFullPrice = 0;
      return out;
    }
    const from = stretchStartBefore(nowMs, fullPriceSinceMs, list);
    out.atFullPriceSinceMs = from;
    out.daysAtFullPrice = Math.max(0, Math.floor((nowMs - from) / DAY_MS));
    out.earliestStartMs = from + MIN_FULL_PRICE_DAYS * DAY_MS;
    out.canStartNow = out.state === 'none' && nowMs >= out.earliestStartMs;
    return out;
  }

  /** The whole percent phones show, rounded down so it never overstates (paywall_offer.dart does the same). */
  function percentOff(full, offer) {
    if (!(full > 0) || !(offer > 0) || offer >= full) return null;
    return Math.floor((1 - offer / full) * 100 + 1e-9);
  }

  // ---- Who pays full price ------------------------------------------------

  const METER_CLASSES = ['full', 'welcome', 'sale', 'code'];

  /**
   * Which price a PRODUCTION Lifetime purchase_log row paid, or null for
   * anything the meter leaves out (sandbox, another product):
   *   code     any row that came through an Apple offer code
   *   full     growdaily_lifetime with no code
   *   sale     growdaily_lifetime_offer bought inside a sale
   *   welcome  every other growdaily_lifetime_offer row
   */
  function classifyPurchase(row, saleSpans, atMs) {
    if (!row || row.environment !== 'PRODUCTION') return null;
    const product = row.productId;
    if (product !== FULL_PRODUCT_ID && product !== OFFER_PRODUCT_ID) return null;
    if (typeof row.offerCode === 'string' && row.offerCode.trim() !== '') return 'code';
    if (product === FULL_PRODUCT_ID) return 'full';
    const at = Number.isFinite(atMs) ? atMs : num(row.eventAtMs);
    for (const s of saleSpans || []) {
      if (at >= s.start && at < s.end) return 'sale';
    }
    return 'welcome';
  }

  /**
   * The meter over [rows] (purchase_log), for purchases made in
   * [fromMs, toMs), net of refunds.
   *
   * A refund cancels the purchase it refunds, found by transaction id and
   * sorted by that purchase's own time and class. One that matches no
   * purchase is sorted by its own fields when its time falls inside the
   * window (the webhook stamps a refund with the purchase's time when the
   * store says it), and counted in unmatchedRefunds either way.
   */
  function whoPaysFullPrice(rows, sales, { fromMs, toMs }) {
    const spans = realSales(sales).map((x) => x.span);
    const counts = { full: 0, welcome: 0, sale: 0, code: 0 };
    const refunds = { full: 0, welcome: 0, sale: 0, code: 0 };
    const salesByTx = new Map();
    const refundRows = [];
    for (const row of rows || []) {
      if (!row || row.environment !== 'PRODUCTION') continue;
      if (row.kind === 'sale') {
        const cls = classifyPurchase(row, spans);
        const at = num(row.eventAtMs);
        if (!cls || !(at >= fromMs && at < toMs)) continue;
        counts[cls] += 1;
        for (const key of [row.transactionId, row.originalTransactionId]) {
          if (key && !salesByTx.has(key)) salesByTx.set(key, cls);
        }
      } else if (row.kind === 'refund') {
        refundRows.push(row);
      }
    }
    let unmatchedRefunds = 0;
    for (const row of refundRows) {
      let cls = null;
      for (const key of [row.transactionId, row.originalTransactionId]) {
        if (key && salesByTx.has(key)) {
          cls = salesByTx.get(key);
          break;
        }
      }
      if (!cls) {
        unmatchedRefunds += 1;
        const at = num(row.eventAtMs);
        if (at >= fromMs && at < toMs) cls = classifyPurchase(row, spans);
      }
      if (cls) refunds[cls] += 1;
    }
    const net = {};
    let total = 0;
    for (const k of METER_CLASSES) {
      net[k] = Math.max(0, counts[k] - refunds[k]);
      total += net[k];
    }
    const pct = {};
    for (const k of METER_CLASSES) pct[k] = total ? Math.round((net[k] / total) * 1000) / 10 : 0;
    return { total, counts: net, gross: counts, refunds, pct, unmatchedRefunds, fromMs, toMs };
  }

  /** Lifetime purchases made during one sale, net of refunds (the Past sales table). */
  function salesDuring(sale, rows) {
    const span = ranSpan(sale);
    if (!span) return 0;
    const meter = whoPaysFullPrice(rows, [sale], { fromMs: span.start, toMs: span.end });
    return meter.counts.sale;
  }

  // ---- The other inputs ---------------------------------------------------

  /** The welcome card's two fields. Returns { ok, errors, value: { enabled, hours } }. */
  function checkWelcome(input) {
    const errors = [];
    const enabled = input && input.enabled;
    const hours = input && input.hours;
    if (typeof enabled !== 'boolean') errors.push({ code: 'welcome-enabled', message: 'Say whether the welcome price is on or off.' });
    if (typeof hours !== 'number' || !Number.isInteger(hours) || hours < WELCOME_MIN_HOURS || hours > WELCOME_MAX_HOURS) {
      errors.push({ code: 'welcome-hours', message: 'The welcome window is a whole number of hours from ' + WELCOME_MIN_HOURS + ' to ' + WELCOME_MAX_HOURS + '.' });
    }
    return { ok: errors.length === 0, errors, value: errors.length ? null : { enabled, hours } };
  }

  /**
   * The day Lifetime moved to its full price, as a Bahrain date. It can't be
   * in the future, and moving it must not make the sale already running or
   * scheduled break the 30-day rule.
   */
  function checkFullPriceSince(dateKey, { sales, nowMs }) {
    const errors = [];
    const ms = bahrainMs(dateKey, '00:00');
    if (ms === null) {
      errors.push({ code: 'bad-date', message: 'Enter a real date.' });
      return { ok: false, errors, ms: null };
    }
    if (ms > nowMs) {
      errors.push({ code: 'future', message: longDate(ms) + ' is in the future. Set it on the day the new price is live in the App Store.' });
    }
    const live = liveSale(sales, nowMs);
    if (live && errors.length === 0) {
      const again = checkSale(
        { startsAtMs: live.startsAtMs, endsAtMs: effectiveEnd(live), nameAr: live.nameAr || '-', nameEn: live.nameEn || '-' },
        { fullPriceSinceMs: ms, sales, nowMs: -Infinity, ignoreId: live.id },
      );
      const broken = again.errors.filter((e) => e.code === 'too-soon' || e.code === 'longer-than-stretch');
      if (broken.length) {
        errors.push({ code: 'breaks-live-sale', message: 'With this date, ' + saleLabel(live) + ' would break the rules: ' + broken.map((e) => e.message).join(' ') + ' Cancel or end that sale first.' });
      }
    }
    return { ok: errors.length === 0, errors, ms };
  }

  return {
    DAY_MS,
    HOUR_MS,
    MINUTE_MS,
    BAHRAIN_OFFSET_MS,
    FULL_PRICE_USD,
    OFFER_PRICE_USD,
    FULL_PRODUCT_ID,
    OFFER_PRODUCT_ID,
    MIN_FULL_PRICE_DAYS,
    MAX_SALE_DAYS,
    MAX_SALE_DAYS_PER_YEAR,
    YEAR_DAYS,
    WELCOME_MIN_HOURS,
    WELCOME_MAX_HOURS,
    WELCOME_DEFAULT_HOURS,
    MAX_NAME_LENGTH,
    START_GRACE_MS,
    METER_DAYS,
    METER_CLASSES,
    isRealDateKey,
    isTime,
    bahrainMs,
    bahrainParts,
    shortDate,
    longDate,
    longDateTime,
    spanDays,
    daysText,
    effectiveEnd,
    ranSpan,
    liveSale,
    saleLabel,
    checkSale,
    saleStatus,
    percentOff,
    classifyPurchase,
    whoPaysFullPrice,
    salesDuring,
    checkWelcome,
    checkFullPriceSince,
  };
});
