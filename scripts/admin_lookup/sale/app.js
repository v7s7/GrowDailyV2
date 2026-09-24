/**
 * The Sale page, in the browser.
 *
 * Reads everything once from /api/sale, runs lib/sale_rules.js (loaded as
 * /sale/rules.js, window.SaleRules) on the form as Aziz types, and posts
 * each action as JSON. Every write answers with the page's fresh state,
 * read back from Firestore after the write, so what is on screen is what
 * phones will read. The server checks every rule again before it writes;
 * the check here is only so a refusal shows before the button is pressed.
 *
 * A plain file, not a template literal: see lib/wording_page.js for why.
 */
(function () {
  'use strict';

  const R = window.SaleRules;
  const state = { data: null, busy: false };

  // ---- DOM helpers (the same tiny ones the Achievements page uses) --------

  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      for (const name of Object.keys(props)) {
        const value = props[name];
        if (value === null || value === undefined || value === false) continue;
        if (name === 'class') el.className = value;
        else if (name.slice(0, 2) === 'on') el.addEventListener(name.slice(2), value);
        else if (value === true) el.setAttribute(name, '');
        else el.setAttribute(name, String(value));
      }
    }
    for (let i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }

  /** Appends every child after [el]: nodes, text, arrays of either; null and false are skipped. */
  function append(el) {
    for (let i = 1; i < arguments.length; i++) {
      const child = arguments[i];
      if (child === null || child === undefined || child === false) continue;
      if (Array.isArray(child)) child.forEach((c) => append(el, c));
      else el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
  }

  function $(id) {
    return document.getElementById(id);
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3600);
  }

  function money(usd) {
    return '$' + Number(usd).toFixed(2);
  }

  // ---- Server -----------------------------------------------------------------

  async function post(url, payload) {
    let res;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      return { ok: false, body: { error: 'Could not reach the admin tool. Is it still running?' } };
    }
    let body = {};
    try {
      body = await res.json();
    } catch (e) {
      body = { error: 'The admin tool answered ' + res.status + '.' };
    }
    return { ok: res.ok && body.ok !== false, body };
  }

  async function run(button, url, payload, done) {
    if (state.busy) return;
    state.busy = true;
    if (button) button.disabled = true;
    const { ok, body } = await post(url, payload);
    state.busy = false;
    if (body && body.state) apply(body.state);
    else if (button) button.disabled = false;
    if (done) done(ok, body);
  }

  // ---- Status bar ---------------------------------------------------------------

  function renderStatus() {
    const d = state.data;
    const s = d.status;
    const bar = clear($('statusBar'));
    const full = money(d.facts.fullPriceUsd);
    let title = 'No sale running';
    let sub = '';
    let chip = null;
    const on = s.state !== 'none';
    const yearDays = Math.round((s.yearSaleMs / R.DAY_MS) * 10) / 10;
    const yearNote = ' Sale days in the last 365: ' + yearDays + ' of ' + R.MAX_SALE_DAYS_PER_YEAR + '.';
    if (s.state === 'running') {
      const left = R.effectiveEnd(s.sale) - d.nowMs;
      title = 'Sale running: ' + (s.sale.nameEn || s.sale.nameAr);
      sub = 'Ends ' + R.longDateTime(R.effectiveEnd(s.sale)) + ', Bahrain time, ' + R.daysText(left) + ' from now.' + yearNote;
      chip = h('span', { class: 'chip-status info' }, 'Phones show ' + money(d.facts.offerPriceUsd));
    } else if (s.state === 'scheduled') {
      title = 'Sale scheduled: ' + (s.sale.nameEn || s.sale.nameAr);
      sub = 'Starts ' + R.longDateTime(s.sale.startsAtMs) + ' and ends ' + R.longDateTime(R.effectiveEnd(s.sale)) + ', Bahrain time.' + yearNote;
      chip = h('span', { class: 'chip-status info' }, 'Lifetime stays at ' + full + ' until then');
    } else if (!s.fullPriceSet) {
      sub = 'Set the day Lifetime moved to ' + full + ' (Full price since, on the right) before scheduling a sale.';
      chip = h('span', { class: 'chip-status warn' }, 'Full price day not set');
    } else {
      sub = 'Lifetime is at its full price, ' + full + ', and has been for ' + s.daysAtFullPrice + (s.daysAtFullPrice === 1 ? ' day.' : ' days.') + yearNote;
      chip = s.canStartNow
        ? h('span', { class: 'chip-status ok' }, R.MIN_FULL_PRICE_DAYS + ' days at full price: a sale can start')
        : h('span', { class: 'chip-status warn' }, 'A sale can start from ' + R.shortDate(s.earliestStartMs));
    }
    append(bar, h('div', { class: 'status-main' },
      h('span', { class: 'status-icon' + (on ? ' on' : ''), 'aria-hidden': 'true' }, on ? '%' : '$'),
      h('div', null, h('span', { class: 'status-title' }, title), h('span', { class: 'status-sub' }, sub))));
    append(bar, chip);
  }

  // ---- Welcome price ----------------------------------------------------------------

  function welcomeDirty() {
    const w = state.data.live.welcome;
    return $('welcomeSwitch').checked !== w.enabled || Number($('welcomeHours').value) !== w.hours || !state.data.live.exists;
  }

  function paintWelcomeSwitch() {
    const on = $('welcomeSwitch').checked;
    $('welcomeSwitchText').textContent = on ? 'On' : 'Off';
    $('welcomeSwitchLabel').classList.toggle('on', on);
    const hours = Number($('welcomeHours').value);
    const check = R.checkWelcome({ enabled: on, hours });
    $('welcomeHours').classList.toggle('bad', !check.ok);
    $('welcomeSave').disabled = !check.ok || !welcomeDirty() || state.busy;
    $('welcomeMsg').textContent = check.ok
      ? (state.data.live.exists ? '' : 'offers/live does not exist yet: saving creates it.')
      : check.errors.map((e) => e.message).join(' ');
  }

  function renderWelcome() {
    const d = state.data;
    $('welcomeSwitch').checked = d.live.welcome.enabled;
    $('welcomeHours').value = d.live.welcome.hours;
    $('welcomePrice').textContent = money(d.facts.offerPriceUsd);
    $('windowsOpen').textContent = d.windowsOpen === null ? '?' : String(d.windowsOpen);
    $('windowsSub').textContent = d.windowsOpen === null
      ? 'Could not be counted just now'
      : d.live.welcome.enabled
        ? 'People inside their ' + d.live.welcome.hours + ' hours'
        : 'Inside ' + d.live.welcome.hours + ' hours of their start, but the price is off';
    paintWelcomeSwitch();
  }

  // ---- The sale form ------------------------------------------------------------------

  function proposed() {
    return {
      nameAr: $('sNameAr').value.trim(),
      nameEn: $('sNameEn').value.trim(),
      startsAtMs: R.bahrainMs($('sStartDay').value, $('sStartTime').value),
      endsAtMs: R.bahrainMs($('sEndDay').value, $('sEndTime').value),
    };
  }

  function rulesSales() {
    return state.data.history.map((s) => ({
      id: s.id, nameAr: s.nameAr, nameEn: s.nameEn, startsAtMs: s.startsAtMs, endsAtMs: s.endsAtMs, endedEarlyAtMs: s.endedEarlyAtMs,
    }));
  }

  function checkRow(kind, text) {
    const mark = kind === 'good' ? '✓' : kind === 'bad' ? '✕' : '•';
    return h('li', { class: kind }, h('span', { 'aria-hidden': 'true' }, mark), h('span', null, text));
  }

  function paintSaleCheck(serverErrors) {
    const d = state.data;
    const p = proposed();
    const result = R.checkSale(p, { fullPriceSinceMs: d.live.fullPriceSinceMs, sales: rulesSales(), nowMs: Date.now() });
    const list = clear($('saleChecks'));
    const errors = serverErrors && serverErrors.length ? serverErrors : result.errors;
    if (errors.length) errors.forEach((e) => append(list, checkRow('bad', e.message)));
    else append(list, checkRow('good', 'Keeps every rule on this page. The server checks them again when you press Schedule.'));

    const summary = $('saleSummary');
    if (p.startsAtMs !== null && p.endsAtMs !== null && p.endsAtMs > p.startsAtMs) {
      const days = R.spanDays(p.endsAtMs - p.startsAtMs);
      summary.textContent = 'Runs ' + days + (days === 1 ? ' day' : ' days') + ': ' + R.longDateTime(p.startsAtMs) + ' to ' +
        R.longDateTime(p.endsAtMs) + '. After it ends, Lifetime stays at ' + money(d.facts.fullPriceUsd) + ' until at least ' +
        R.longDate(p.endsAtMs + R.MIN_FULL_PRICE_DAYS * R.DAY_MS) + '.';
    } else {
      summary.textContent = '';
    }
    $('scheduleBtn').disabled = !result.ok || state.busy;
    renderPhone(p);
  }

  function prefillForm() {
    const s = state.data.status;
    const tomorrow = R.bahrainParts(Date.now() + R.DAY_MS).dateKey;
    let startKey = tomorrow;
    // The earliest start the rules allow: 30 days after the live sale ends,
    // or the status bar's earliest start when no sale is live.
    const earliest = s.sale ? R.effectiveEnd(s.sale) + R.MIN_FULL_PRICE_DAYS * R.DAY_MS : s.earliestStartMs;
    if (earliest && earliest > Date.now()) {
      // Moved to the next midnight when it is not one.
      const p = R.bahrainParts(earliest);
      startKey = p.time === '00:00' ? p.dateKey : R.bahrainParts(earliest + R.DAY_MS).dateKey;
    }
    const startMs = R.bahrainMs(startKey, '00:00');
    $('sStartDay').value = startKey;
    $('sStartTime').value = '00:00';
    $('sEndDay').value = R.bahrainParts(startMs + 6 * R.DAY_MS).dateKey;
    $('sEndTime').value = '23:59';
  }

  function renderEndButton() {
    const s = state.data.status;
    const btn = $('endBtn');
    const note = $('endNote');
    if (s.state === 'running') {
      btn.textContent = 'End the running sale now';
      btn.disabled = state.busy;
      note.textContent = 'Ends ' + (s.sale.nameEn || s.sale.nameAr) + ' at this minute, for everyone. Phones go back to the full price the next time their paywall opens.';
    } else if (s.state === 'scheduled') {
      btn.textContent = 'Cancel the scheduled sale';
      btn.disabled = state.busy;
      note.textContent = 'Takes ' + (s.sale.nameEn || s.sale.nameAr) + ' off phones before it starts. Its record stays in Past sales, marked cancelled.';
    } else {
      btn.textContent = 'End the running sale now';
      btn.disabled = true;
      note.textContent = '';
    }
  }

  // ---- The phone sketch ---------------------------------------------------------------

  const AR_DATE = (function () {
    try {
      return new Intl.DateTimeFormat('ar-u-nu-latn', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bahrain' });
    } catch (e) {
      return null;
    }
  })();
  const AR_TIME = (function () {
    try {
      return new Intl.DateTimeFormat('ar-u-nu-latn', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Bahrain' });
    } catch (e) {
      return null;
    }
  })();

  function arabicWhen(ms) {
    if (!AR_DATE || !AR_TIME) return R.shortDate(ms);
    const parts = AR_DATE.formatToParts(new Date(ms));
    const get = (t) => (parts.find((p) => p.type === t) || {}).value || '';
    return get('weekday') + ' ' + get('day') + ' ' + get('month') + '، ' + AR_TIME.format(new Date(ms));
  }

  function unit(value, label) {
    return h('div', { class: 'unit' }, h('b', null, String(value)), h('span', null, label));
  }

  function renderPhone(p) {
    const d = state.data;
    const box = clear($('phone'));
    const has = p.startsAtMs !== null && p.endsAtMs !== null && p.endsAtMs > p.startsAtMs;
    const left = has ? p.endsAtMs - p.startsAtMs : 0;
    const days = Math.floor(left / R.DAY_MS);
    const hours = Math.floor((left % R.DAY_MS) / R.HOUR_MS);
    const minutes = Math.floor((left % R.HOUR_MS) / R.MINUTE_MS);
    const off = R.percentOff(d.facts.fullPriceUsd, d.facts.offerPriceUsd);
    const name = p.nameAr || 'اسم العرض';
    const sale = money(d.facts.offerPriceUsd);
    const full = money(d.facts.fullPriceUsd);
    append(box, h('div', { class: 'phone', dir: 'rtl', lang: 'ar' },
      h('div', { class: 'banner-row' },
        h('div', null,
          h('span', { class: 'sale-name' }, name),
          h('span', { class: 'ends-in' }, 'ينتهي العرض بعد')),
        h('div', { class: 'clock' },
          unit(days, 'يوم'),
          unit(hours, 'ساعة'),
          unit(minutes, 'دقيقة'))),
      h('div', { class: 'plan' },
        h('div', { class: 'plan-main' },
          h('div', { class: 'plan-title' },
            h('span', null, 'مدى الحياة'),
            off ? h('span', { class: 'off', dir: 'ltr' }, '-' + off + '%') : null)),
        h('div', { class: 'prices' },
          h('span', { class: 'was', dir: 'ltr' }, full),
          h('span', { class: 'now', dir: 'ltr' }, sale))),
      has
        ? h('p', { class: 'under' },
          'سعر العرض ', h('span', { dir: 'ltr' }, sale),
          ' حتى ' + arabicWhen(p.endsAtMs) + '. بعدها يرجع السعر ',
          h('span', { dir: 'ltr' }, full), '.')
        : null));
  }

  // ---- Full price since -------------------------------------------------------------

  function renderFullSince() {
    const d = state.data;
    const input = $('fullSince');
    input.value = d.live.fullPriceSinceMs === null ? '' : R.bahrainParts(d.live.fullPriceSinceMs).dateKey;
    input.max = R.bahrainParts(Date.now()).dateKey;
    paintFullSince();
  }

  function paintFullSince(serverError) {
    const d = state.data;
    const value = $('fullSince').value;
    const stored = d.live.fullPriceSinceMs === null ? '' : R.bahrainParts(d.live.fullPriceSinceMs).dateKey;
    const msg = $('fullSinceMsg');
    if (serverError) {
      msg.textContent = serverError;
      msg.style.color = 'var(--danger)';
    } else if (!value) {
      msg.textContent = 'Not set. Scheduling a sale is refused until it is.';
      msg.style.color = 'var(--warn)';
    } else {
      const check = R.checkFullPriceSince(value, { sales: rulesSales(), nowMs: Date.now() });
      msg.textContent = check.ok
        ? (value === stored ? 'Lifetime at ' + money(d.facts.fullPriceUsd) + ' since ' + R.longDate(check.ms) + '.' : 'Not saved yet.')
        : check.errors.map((e) => e.message).join(' ');
      msg.style.color = check.ok ? '' : 'var(--danger)';
    }
    $('fullSinceSave').disabled = !value || value === stored || state.busy;
  }

  // ---- Past sales ---------------------------------------------------------------------

  const STATE_CHIP = {
    scheduled: ['info', 'Scheduled'],
    running: ['ok', 'Running'],
    ended: ['', 'Ended'],
    'ended-early': ['warn', 'Ended early'],
    cancelled: ['', 'Cancelled'],
  };

  function renderPast() {
    const d = state.data;
    const body = clear($('pastSales'));
    if (!d.history.length) {
      append(body, h('tr', { class: 'empty-row' }, h('td', { colspan: '5' }, 'No sales yet.')));
      return;
    }
    for (const s of d.history) {
      const chip = STATE_CHIP[s.state] || ['', s.state];
      const end = s.state === 'cancelled' ? s.endsAtMs : R.effectiveEnd(s);
      const counted = s.state === 'ended' || s.state === 'ended-early' || s.state === 'running';
      append(body, h('tr', null,
        h('td', null, h('div', { class: 'stack' },
          h('span', { class: 'ar', dir: 'rtl' }, s.nameAr || '-'),
          h('span', { class: 'sub' }, s.nameEn || ''))),
        h('td', { class: 'muted-cell' }, R.shortDate(s.startsAtMs) + ', ' + R.bahrainParts(s.startsAtMs).time + ' to ' + R.shortDate(end) + ', ' + R.bahrainParts(end).time),
        h('td', null, h('span', { class: 'chip-status small ' + chip[0] }, chip[1])),
        h('td', { class: 'num' }, money(d.facts.offerPriceUsd)),
        h('td', { class: 'num' }, counted ? String(s.lifetimeSales) : '')));
    }
  }

  // ---- Who pays full price --------------------------------------------------------------

  const METER_LABEL = { full: 'Full price', welcome: 'Welcome price', sale: 'Sale', code: 'Creator code' };

  function renderMeter() {
    const m = state.data.meter;
    const box = clear($('meter'));
    if (!m.total) {
      append(box, h('p', { class: 'note' }, 'No Lifetime purchases in the last ' + R.METER_DAYS + ' days yet (production only, refunds taken off).'));
    } else {
      append(box, h('div', { class: 'meter-big' },
        h('b', null, Math.round(m.pct.full) + '%'),
        h('span', null, 'of Lifetime buyers in the last ' + R.METER_DAYS + ' days paid ' + money(state.data.facts.fullPriceUsd) + ' (' + m.counts.full + ' of ' + m.total + ')')));
      const bar = h('div', { class: 'meter-bar', role: 'img', 'aria-label': R.METER_CLASSES.map((k) => METER_LABEL[k] + ' ' + m.pct[k] + '%').join(', ') });
      for (const k of R.METER_CLASSES) {
        if (m.counts[k]) append(bar, h('i', { class: 'c-' + k, style: 'width:' + m.pct[k] + '%' }));
      }
      append(box, bar);
    }
    const legend = h('ul', { class: 'meter-legend' });
    for (const k of R.METER_CLASSES) {
      append(legend, h('li', null, h('span', { class: 'sw c-' + k, 'aria-hidden': 'true' }), METER_LABEL[k] + ' ', h('b', null, String(m.counts[k])), m.total ? ' (' + m.pct[k] + '%)' : ''));
    }
    append(box, legend);
    const notes = [];
    if (m.unmatchedRefunds) notes.push(m.unmatchedRefunds + (m.unmatchedRefunds === 1 ? ' refund' : ' refunds') + ' matched no purchase by transaction id.');
    if (m.sandboxRows) notes.push(m.sandboxRows + ' sandbox ' + (m.sandboxRows === 1 ? 'row is' : 'rows are') + ' left out.');
    notes.push('Full price: Lifetime at ' + money(state.data.facts.fullPriceUsd) + ' with no code. Sale: the offer bought during a sale. Welcome: the offer at any other time.');
    append(box, h('p', { class: 'fine' }, notes.join(' ')));
  }

  // ---- Everything -------------------------------------------------------------------------

  function apply(data) {
    const first = !state.data;
    state.data = data;
    $('factSale').textContent = money(data.facts.offerPriceUsd);
    $('factFull').textContent = money(data.facts.fullPriceUsd);
    $('factOff').textContent = '-' + data.facts.percentOff + '%';
    renderStatus();
    renderWelcome();
    renderFullSince();
    renderPast();
    renderMeter();
    renderEndButton();
    if (first || data.status.state !== 'none') prefillForm();
    paintSaleCheck();
  }

  function banner(kind, text) {
    append($('banners'), h('div', { class: 'banner ' + kind }, h('div', { class: 'grow' }, text)));
  }

  function wire() {
    $('welcomeSwitch').addEventListener('change', paintWelcomeSwitch);
    $('welcomeHours').addEventListener('input', paintWelcomeSwitch);
    $('welcomeSave').addEventListener('click', () => {
      run($('welcomeSave'), '/api/sale/welcome', { enabled: $('welcomeSwitch').checked, hours: Number($('welcomeHours').value) }, (ok, body) => {
        if (ok) toast(body.changed ? 'Welcome price saved. Phones read it the next time their paywall opens.' : 'Nothing changed.');
        else toast(body.error || 'The save did not go through.');
      });
    });

    $('fullSince').addEventListener('input', () => paintFullSince());
    $('fullSinceSave').addEventListener('click', () => {
      run($('fullSinceSave'), '/api/sale/full-price-since', { date: $('fullSince').value }, (ok, body) => {
        if (ok) toast('Full price day saved.');
        else paintFullSince(body.error || 'The save did not go through.');
      });
    });

    for (const id of ['sNameAr', 'sNameEn', 'sStartDay', 'sStartTime', 'sEndDay', 'sEndTime']) {
      $(id).addEventListener('input', () => paintSaleCheck());
    }
    $('scheduleBtn').addEventListener('click', () => {
      const payload = {
        nameAr: $('sNameAr').value.trim(),
        nameEn: $('sNameEn').value.trim(),
        startDate: $('sStartDay').value,
        startTime: $('sStartTime').value,
        endDate: $('sEndDay').value,
        endTime: $('sEndTime').value,
      };
      run($('scheduleBtn'), '/api/sale/schedule', payload, (ok, body) => {
        if (ok) {
          $('sNameAr').value = '';
          $('sNameEn').value = '';
          toast('Sale scheduled. It is in offers/live now; phones show it from its start.');
          paintSaleCheck();
        } else {
          paintSaleCheck(body.errors && body.errors.length ? body.errors : [{ message: body.error || 'The server refused it.' }]);
          toast('The server refused the sale. The reasons are listed above the button.');
        }
      });
    });

    $('endBtn').addEventListener('click', () => {
      const s = state.data.status;
      if (!s.sale) return;
      const name = s.sale.nameEn || s.sale.nameAr;
      const question = s.state === 'running'
        ? 'End ' + name + ' now, for everyone? Phones go back to the full price. This can\'t be undone.'
        : 'Cancel ' + name + ' before it starts? This can\'t be undone.';
      if (!window.confirm(question)) return;
      run($('endBtn'), '/api/sale/end', { id: s.sale.id }, (ok, body) => {
        if (ok) toast(body.result === 'cancelled' ? 'Sale cancelled.' : 'Sale ended.');
        else toast(body.error || 'It did not go through.');
      });
    });
  }

  async function load() {
    let body;
    try {
      const res = await fetch('/api/sale');
      body = await res.json();
    } catch (e) {
      body = { ok: false, error: 'Could not reach the admin tool.' };
    }
    if (!body || body.ok === false) {
      clear($('statusBar'));
      banner('danger', 'Could not load the sale: ' + ((body && body.error) || 'unknown error'));
      return;
    }
    wire();
    apply(body.state);
  }

  load();
})();
