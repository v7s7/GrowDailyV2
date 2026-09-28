/**
 * The Sale page, in the browser: the simple layout of 2026-09-27.
 *
 * Reads everything once from /api/sale, and what Apple charges for both
 * Lifetime products today from /api/sale/store (a separate, slower read).
 * Runs lib/sale_rules.js (loaded as /sale/rules.js, window.SaleRules) on the
 * New sale dialog as Aziz types, and posts each action as JSON. Every write
 * answers with the page's fresh state, read back from Firestore after the
 * write, so what is on screen is what phones will read. The server checks
 * every rule again before it writes; the check here is only so a refusal
 * shows before the button is pressed.
 *
 * Prices are Apple's when the store read answered, and the plan's
 * (SaleRules.FULL_PRICE_USD and OFFER_PRICE_USD) otherwise, labelled so.
 * The plan said $39.99 while Apple still sold Lifetime at $29.99, and the
 * old page printed the plan as if it were the price.
 *
 * A plain file, not a template literal: see lib/wording_page.js for why.
 */
(function () {
  'use strict';

  const R = window.SaleRules;
  const WELCOME_CHOICES = [24, 48, 72, 96, 120, 144, 168];
  const state = { data: null, store: undefined, ascMissing: null, busy: false, typed: false };

  // ---- DOM helpers -------------------------------------------------------------

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

  function money(cents) {
    return '$' + (cents / 100).toFixed(2);
  }

  function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
  }

  // ---- Dialogs -------------------------------------------------------------------

  function openDialog(id) {
    const d = $(id);
    if (!d.open) d.showModal();
  }

  function closeDialog(id) {
    const d = $(id);
    if (d.open) d.close();
  }

  /** A press on the dimmed backdrop closes, the way Esc already does. */
  function closeOnBackdrop(id) {
    const d = $(id);
    d.addEventListener('click', (e) => {
      if (e.target !== d) return;
      const r = d.getBoundingClientRect();
      const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
      if (!inside) d.close();
    });
  }

  // ---- Server ------------------------------------------------------------------------

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

  async function run(url, payload) {
    if (state.busy) return { ok: false, body: { error: 'Still saving the last change.' } };
    state.busy = true;
    paintButtons();
    const result = await post(url, payload);
    state.busy = false;
    if (result.body && result.body.state) apply(result.body.state);
    else paintButtons();
    return result;
  }

  // ---- Prices: Apple's when known, the plan's otherwise ----------------------------------

  function prices() {
    const s = state.store;
    if (s && s[R.FULL_PRODUCT_ID] && s[R.OFFER_PRODUCT_ID] &&
        s[R.FULL_PRODUCT_ID].usCents !== null && s[R.OFFER_PRODUCT_ID].usCents !== null) {
      return { full: s[R.FULL_PRODUCT_ID].usCents, offer: s[R.OFFER_PRODUCT_ID].usCents, apple: true };
    }
    return { full: Math.round(R.FULL_PRICE_USD * 100), offer: Math.round(R.OFFER_PRICE_USD * 100), apple: false };
  }

  /** Why phones would show no sale today, or null when they would. Null too while Apple's answer is not in. */
  function notSellable() {
    const s = state.store;
    if (!s) return null;
    const offer = s[R.OFFER_PRODUCT_ID];
    const p = prices();
    const reasons = [];
    if (!offer || offer.state !== 'APPROVED') reasons.push('Apple has not approved the sale product yet');
    if (p.apple && p.offer >= p.full) {
      reasons.push(p.offer === p.full
        ? 'Lifetime and the sale price are both ' + money(p.full)
        : 'the sale price, ' + money(p.offer) + ', is above Lifetime, ' + money(p.full));
    }
    return reasons.length ? reasons : null;
  }

  function renderReady() {
    const box = $('readyNotice');
    if (state.store === undefined) {
      box.hidden = true;
      return;
    }
    if (state.store === null) {
      box.className = 'notice info';
      $('readyText').textContent = 'Prices here are the plan\'s. Start the tool with the App Store Connect key to check Apple\'s.';
      box.hidden = false;
      return;
    }
    const reasons = notSellable();
    box.className = 'notice warn';
    box.hidden = !reasons;
    if (reasons) $('readyText').textContent = 'Sales can\'t show in the app yet: ' + reasons.join(', and ') + '.';
  }

  // ---- Now ---------------------------------------------------------------------------------

  function saleName(sale) {
    return sale.nameEn || sale.nameAr || 'The sale';
  }

  function renderNow() {
    const d = state.data;
    const s = d.status;
    const end = $('endBtn');
    let title = 'No sale running';
    let sub = '';
    end.hidden = true;
    if (s.state === 'running') {
      const ends = R.effectiveEnd(s.sale);
      title = 'Sale running: ' + saleName(s.sale);
      sub = 'Ends ' + R.longDateTime(ends) + '. ' + R.daysText(ends - d.nowMs) + ' left.';
      end.textContent = 'End now';
      end.hidden = false;
    } else if (s.state === 'scheduled') {
      title = 'Sale scheduled: ' + saleName(s.sale);
      sub = 'Starts ' + R.longDateTime(s.sale.startsAtMs) + ', ends ' + R.longDateTime(R.effectiveEnd(s.sale)) + '.';
      end.textContent = 'Cancel sale';
      end.hidden = false;
    } else if (!s.fullPriceSet) {
      sub = 'Set the day Lifetime went to its full price, below, before the first sale.';
    } else if (s.canStartNow) {
      sub = 'Lifetime is at full price. A sale can start any time.';
    } else {
      sub = 'Lifetime is at full price. The next sale can start on ' + R.shortDate(s.earliestStartMs) + '.';
    }
    $('nowTitle').textContent = title;
    $('nowSub').textContent = sub;
  }

  function renderFullSince() {
    const d = state.data;
    const set = d.live.fullPriceSinceMs !== null;
    $('fullSinceText').textContent = set ? R.longDate(d.live.fullPriceSinceMs) : 'not set';
    $('fullSinceEdit').textContent = set ? 'Change' : 'Set';
    $('fullSinceInput').max = R.bahrainParts(Date.now()).dateKey;
    if (set) $('fullSinceInput').value = R.bahrainParts(d.live.fullPriceSinceMs).dateKey;
  }

  function showFullSinceForm(on) {
    $('fullSinceForm').hidden = !on;
    $('fullSinceEdit').hidden = on;
    if (on) $('fullSinceInput').focus();
  }

  // ---- Welcome price -------------------------------------------------------------------------

  function renderWelcome() {
    const d = state.data;
    const w = d.live.welcome;
    const select = clear($('welcomeHours'));
    const choices = WELCOME_CHOICES.includes(w.hours) ? WELCOME_CHOICES : WELCOME_CHOICES.concat([w.hours]).sort((a, b) => a - b);
    for (const hours of choices) {
      append(select, h('option', { value: String(hours), selected: hours === w.hours ? true : null }, hours + ' hours'));
    }
    $('welcomeSwitch').setAttribute('aria-checked', w.enabled ? 'true' : 'false');
    $('welcomeState').textContent = w.enabled ? 'On' : 'Off';
    const p = prices();
    let text;
    if (!w.enabled) {
      text = 'Off. Nobody gets a welcome price.';
    } else {
      text = 'New people get ' + money(p.offer) + ' once, for ' + w.hours + ' hours after they first see the price.';
      if (!d.live.exists) text += ' On by default until it is saved.';
      else if (notSellable()) text += ' Nothing shows while the prices are the same.';
      if (d.windowsOpen) text += ' ' + plural(d.windowsOpen, 'person is', 'people are') + ' inside their window now.';
    }
    $('welcomeText').textContent = text;
  }

  async function saveWelcome(enabled, hours) {
    const { ok, body } = await run('/api/sale/welcome', { enabled, hours });
    if (ok) toast(body.changed ? (enabled ? 'Welcome price on, ' + hours + ' hours.' : 'Welcome price off.') : 'Nothing changed.');
    else {
      toast(body.error || 'The save did not go through.');
      renderWelcome();
    }
  }

  // ---- Past sales ------------------------------------------------------------------------------

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
      append(body, h('tr', { class: 'empty' }, h('td', { colspan: '4' }, 'No sales yet.')));
      return;
    }
    for (const s of d.history) {
      const chip = STATE_CHIP[s.state] || ['', s.state];
      const end = s.state === 'cancelled' ? s.endsAtMs : R.effectiveEnd(s);
      const counted = s.state === 'ended' || s.state === 'ended-early' || s.state === 'running';
      append(body, h('tr', null,
        h('td', null, h('div', { class: 'stack' },
          h('span', { class: 'ar', dir: 'rtl' }, s.nameAr || '-'),
          s.nameEn ? h('span', { class: 'small faint' }, s.nameEn) : null)),
        h('td', { class: 'muted' }, R.shortDate(s.startsAtMs) + ' to ' + R.shortDate(end)),
        h('td', null, h('span', { class: 'chip ' + chip[0] }, chip[1])),
        h('td', { class: 'num' }, counted ? String(s.lifetimeSales) : '')));
    }
  }

  const METER_LABEL = { full: 'at full price', sale: 'in a sale', welcome: 'at the welcome price', code: 'with a creator code' };

  function renderMeter() {
    const m = state.data.meter;
    const line = $('meterLine');
    if (!m.total) {
      line.hidden = true;
      return;
    }
    line.textContent = 'Lifetime bought in the last ' + R.METER_DAYS + ' days: ' +
      R.METER_CLASSES.map((k) => m.counts[k] + ' ' + METER_LABEL[k]).join(', ') + '.';
    line.hidden = false;
  }

  // ---- The New sale dialog ------------------------------------------------------------------------

  function needsFullSince() {
    return state.data.live.fullPriceSinceMs === null;
  }

  function fullSinceForCheck() {
    if (!needsFullSince()) return state.data.live.fullPriceSinceMs;
    const key = $('dFullSince').value;
    return R.isRealDateKey(key) ? R.bahrainMs(key, '00:00') : null;
  }

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

  function checkLine(kind, text) {
    const mark = kind === 'good' ? '✓' : kind === 'bad' ? '✕' : '!';
    return h('li', { class: kind }, h('span', { class: 'mk', 'aria-hidden': 'true' }, mark), h('span', null, text));
  }

  function daysOf(ms) {
    return Math.round((ms / R.DAY_MS) * 10) / 10;
  }

  function paintSaleDialog(serverErrors) {
    const p = proposed();
    const result = R.checkSale(p, { fullPriceSinceMs: fullSinceForCheck(), sales: rulesSales(), nowMs: Date.now() });
    const list = clear($('dChecks'));
    // The dialog asks for the full-price day itself when it is missing, so
    // the rule's own sentence about it would only repeat the field above;
    // and a missing name is not worth saying before anything was typed.
    const errors = (serverErrors && serverErrors.length ? serverErrors : result.errors)
      .filter((e) => !(e.code === 'no-full-price-since' && needsFullSince()))
      .filter((e) => state.typed || e.code !== 'names');
    // Only what is wrong, when something is: the rest is noise until then.
    if (errors.length) {
      errors.forEach((e) => append(list, checkLine('bad', e.message)));
    } else {
      const f = result.facts;
      append(list, checkLine('good', 'Runs ' + R.daysText(f.durationMs) + ' (' + R.MAX_SALE_DAYS + ' at most).'));
      if (f.stretchMs !== null) append(list, checkLine('good', daysOf(f.stretchMs) + ' days at full price before it (' + R.MIN_FULL_PRICE_DAYS + ' needed).'));
      if (f.yearSaleMs !== null) append(list, checkLine('good', 'Sale days in a year with this one: ' + daysOf(f.yearSaleMs) + ' of ' + R.MAX_SALE_DAYS_PER_YEAR + '.'));
    }
    const reasons = notSellable();
    if (reasons) append(list, checkLine('warn', 'Phones won\'t show it until this changes: ' + reasons.join(', and ') + '.'));

    const pr = prices();
    const off = R.percentOff(pr.full / 100, pr.offer / 100);
    const bar = clear($('dPrices'));
    append(bar,
      h('span', null, 'Sale price ', h('b', null, money(pr.offer))),
      h('span', null, 'Full price ', h('b', null, money(pr.full))),
      off ? h('span', { style: 'color: var(--success); font-weight: 700;' }, '-' + off + '%') : null,
      pr.apple ? null : h('span', { class: 'faint' }, '(the plan\'s prices)'));

    const fullSinceOk = !needsFullSince() || fullSinceForCheck() !== null;
    $('scheduleBtn').disabled = !result.ok || !fullSinceOk || state.busy;
    renderPhone(p, pr, off);
  }

  function prefillSale() {
    const s = state.data.status;
    const tomorrow = R.bahrainParts(Date.now() + R.DAY_MS).dateKey;
    let startKey = tomorrow;
    const earliest = s.earliestStartMs;
    if (earliest && earliest > Date.now()) {
      const p = R.bahrainParts(earliest);
      startKey = p.time === '00:00' ? p.dateKey : R.bahrainParts(earliest + R.DAY_MS).dateKey;
    }
    const startMs = R.bahrainMs(startKey, '00:00');
    $('sNameAr').value = '';
    $('sNameEn').value = '';
    $('sStartDay').value = startKey;
    $('sStartTime').value = '00:00';
    $('sEndDay').value = R.bahrainParts(startMs + 6 * R.DAY_MS).dateKey;
    $('sEndTime').value = '23:59';
    $('askFullSince').hidden = !needsFullSince();
    state.typed = false;
    $('dFullSince').value = '';
    $('dFullSince').max = R.bahrainParts(Date.now()).dateKey;
  }

  function openSaleDialog() {
    prefillSale();
    paintSaleDialog();
    openDialog('saleDialog');
    $(needsFullSince() ? 'dFullSince' : 'sNameAr').focus();
  }

  async function schedule() {
    state.typed = true;
    if (needsFullSince()) {
      const first = await run('/api/sale/full-price-since', { date: $('dFullSince').value });
      if (!first.ok) {
        paintSaleDialog([{ message: first.body.error || 'The full-price day was not saved.' }]);
        return;
      }
      $('askFullSince').hidden = true;
    }
    const payload = {
      nameAr: $('sNameAr').value.trim(),
      nameEn: $('sNameEn').value.trim(),
      startDate: $('sStartDay').value,
      startTime: $('sStartTime').value,
      endDate: $('sEndDay').value,
      endTime: $('sEndTime').value,
    };
    const { ok, body } = await run('/api/sale/schedule', payload);
    if (ok) {
      closeDialog('saleDialog');
      toast('Sale scheduled. Phones show it from its start.');
    } else {
      paintSaleDialog(body.errors && body.errors.length ? body.errors : [{ message: body.error || 'The server refused it.' }]);
    }
  }

  // ---- The phone preview ----------------------------------------------------------------------------

  function renderPhone(p, pr, off) {
    const box = clear($('dPhone'));
    const has = p.startsAtMs !== null && p.endsAtMs !== null && p.endsAtMs > p.startsAtMs;
    const left = has ? p.endsAtMs - p.startsAtMs : 0;
    const days = Math.floor(left / R.DAY_MS);
    const hours = Math.floor((left % R.DAY_MS) / R.HOUR_MS);
    append(box,
      h('span', { class: 'p-name' }, p.nameAr || 'اسم العرض'),
      h('span', { class: 'p-ends' }, 'ينتهي العرض بعد ' + days + ' يوم ' + hours + ' ساعة'),
      h('span', null, 'مدى الحياة'),
      h('div', { class: 'p-price' },
        h('span', { class: 'p-now' }, money(pr.offer)),
        h('span', { class: 'p-was' }, money(pr.full)),
        off ? h('span', { class: 'p-off' }, '-' + off + '%') : null));
  }

  // ---- Everything --------------------------------------------------------------------------------------

  function paintButtons() {
    const d = state.data;
    const btn = $('newSaleBtn');
    const live = d && d.status.state !== 'none';
    btn.disabled = !d || live || state.busy;
    btn.title = live ? 'One sale at a time. End or cancel the one there is first.' : '';
    $('endBtn').disabled = state.busy;
    $('welcomeSwitch').disabled = state.busy || !d;
    $('welcomeHours').disabled = state.busy || !d;
    $('fullSinceSave').disabled = state.busy;
  }

  function apply(data) {
    state.data = data;
    renderReady();
    renderNow();
    renderFullSince();
    renderWelcome();
    renderPast();
    renderMeter();
    paintButtons();
    if ($('saleDialog').open) paintSaleDialog();
  }

  function banner(kind, text) {
    append($('banners'), h('div', { class: 'notice ' + kind }, h('span', { class: 'grow' }, text)));
  }

  function wire() {
    $('newSaleBtn').addEventListener('click', openSaleDialog);
    $('saleClose').addEventListener('click', () => closeDialog('saleDialog'));
    $('saleCancel').addEventListener('click', () => closeDialog('saleDialog'));
    closeOnBackdrop('saleDialog');
    for (const id of ['dFullSince', 'sNameAr', 'sNameEn', 'sStartDay', 'sStartTime', 'sEndDay', 'sEndTime']) {
      $(id).addEventListener('input', () => {
        if (id === 'sNameAr' || id === 'sNameEn') state.typed = true;
        paintSaleDialog();
      });
    }
    $('scheduleBtn').addEventListener('click', schedule);

    $('howBtn').addEventListener('click', () => openDialog('howDialog'));
    $('howClose').addEventListener('click', () => closeDialog('howDialog'));
    closeOnBackdrop('howDialog');

    $('endBtn').addEventListener('click', async () => {
      const s = state.data.status;
      if (!s.sale) return;
      const running = s.state === 'running';
      const question = running
        ? 'End ' + saleName(s.sale) + ' now, for everyone? Phones go back to the full price.'
        : 'Cancel ' + saleName(s.sale) + ' before it starts?';
      if (!window.confirm(question)) return;
      const { ok, body } = await run('/api/sale/end', { id: s.sale.id });
      toast(ok ? (body.result === 'cancelled' ? 'Sale cancelled.' : 'Sale ended.') : (body.error || 'It did not go through.'));
    });

    $('fullSinceEdit').addEventListener('click', () => showFullSinceForm(true));
    $('fullSinceCancel').addEventListener('click', () => {
      renderFullSince();
      showFullSinceForm(false);
    });
    $('fullSinceSave').addEventListener('click', async () => {
      const { ok, body } = await run('/api/sale/full-price-since', { date: $('fullSinceInput').value });
      if (ok) {
        showFullSinceForm(false);
        toast(body.changed ? 'Full-price day saved.' : 'Nothing changed.');
      } else {
        toast(body.error || 'The save did not go through.');
      }
    });

    $('welcomeSwitch').addEventListener('click', () => {
      const w = state.data.live.welcome;
      saveWelcome(!w.enabled, w.hours);
    });
    $('welcomeHours').addEventListener('change', () => {
      saveWelcome(state.data.live.welcome.enabled, Number($('welcomeHours').value));
    });
  }

  async function loadStore() {
    let body;
    try {
      const res = await fetch('/api/sale/store');
      body = await res.json();
    } catch (e) {
      body = { ok: false };
    }
    if (body && body.ok && body.store) state.store = body.store;
    else {
      state.store = null;
      state.ascMissing = body && body.ascMissing ? body.ascMissing : null;
    }
    if (state.data) apply(state.data);
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
      $('nowTitle').textContent = 'Could not load the sale';
      banner('danger', (body && body.error) || 'Unknown error.');
      return;
    }
    wire();
    apply(body.state);
    loadStore();
  }

  load();
})();
