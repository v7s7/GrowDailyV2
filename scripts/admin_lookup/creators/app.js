/**
 * The Creators page, in the browser: the simple layout of 2026-09-27.
 *
 * Reads the creators and their money from /api/creators, and what App Store
 * Connect says (codes in use, product states) from
 * /api/creators/apple-status. lib/creators.js (loaded as /creators/rules.js,
 * window.CreatorRules) checks the Add creator steps and works out the money
 * line as Aziz types; the server checks everything again.
 *
 * Add creator is three steps in one dialog: name and code, the deal, then
 * the Apple code (Preview, then Create, the same two-step request as
 * before), ending on the two links to send. Everything else a creator needs
 * (Pay, Change share, their page link, Details, Stop) is one small dialog
 * from their row, built here into #dlg.
 *
 * A plain file, not a template literal: see lib/wording_page.js for why.
 */
(function () {
  'use strict';

  const C = window.CreatorRules;
  const ASC_START = 'ASC_KEY_ID=8672BSV59Q ASC_ISSUER_ID=fb55eebc-827e-4fcd-a941-989b2e36807b npm start';
  const STEP1_CODES = new Set(['name', 'name-long', 'name-dash', 'code']);
  const state = {
    data: null,
    apple: null,
    appleError: null,
    busy: false,
    step: 1,
    touched: { 1: false, 2: false },
    preview: null,
    previewError: null,
    previewLoading: false,
    createError: null,
    done: null,
    menuFor: null,
    existing: null,
    previewDiscount: null,
  };

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

  function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
  }

  /** '27 Mar 2027' for a date key. */
  function dayText(dateKey) {
    if (!dateKey) return '';
    const d = new Date(dateKey + 'T12:00:00Z');
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
  }

  function msDay(ms) {
    return ms ? dayText(new Date(ms).toISOString().slice(0, 10)) : '';
  }

  async function copy(text) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (e) {
      const area = h('textarea', { style: 'position:fixed;opacity:0' });
      area.value = text;
      document.body.appendChild(area);
      area.select();
      try {
        document.execCommand('copy');
      } catch (e2) {
        // Nothing more to try; the toast below still says what was meant.
      }
      area.remove();
    }
    toast('Copied.');
  }

  function checkLine(kind, text) {
    const mark = kind === 'good' ? '✓' : kind === 'bad' ? '✕' : '!';
    return h('li', { class: kind }, h('span', { class: 'mk', 'aria-hidden': 'true' }, mark), h('span', null, text));
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

  function errorText(body) {
    if (!body) return 'Something went wrong.';
    if (body.errors && body.errors.length) return body.errors.map((e) => e.message).join(' ');
    return body.error || body.message || '';
  }

  // ---- Tiles and notices ------------------------------------------------------------------

  function renderTiles() {
    const d = state.data;
    const t = d.totals;
    $('tOwed').textContent = C.money(t.owedCents);
    $('tOwedSub').textContent = t.waitingCents > 0 ? C.money(t.waitingCents) + ' more once 60 days pass' : '';
    $('tSales').textContent = String(t.sales30);
    $('tSalesSub').textContent = t.refunds30 ? plural(t.refunds30, 'refunded', 'refunded') : 'None refunded';
    const inUse = state.apple ? state.apple.activeOffers : d.offersInUse;
    $('tOffers').textContent = String(inUse);
    $('tOffersMax').textContent = String(d.maxOffers);
    $('tOffersSub').textContent = state.appleError
      ? 'App Store Connect did not answer, so this is the tool\'s count.'
      : state.apple ? '' : (d.asc.ok ? 'Checking with Apple...' : 'The tool\'s count.');
  }

  function notice(kind, children) {
    return h('div', { class: 'notice ' + kind }, h('span', { class: 'grow' }, children));
  }

  function renderBanners() {
    const d = state.data;
    const box = clear($('banners'));
    if (!d.asc.ok) {
      append(box, notice('warn', [
        'App Store Connect is not connected, so codes can\'t be made from here. Start the tool with ',
        h('code', null, ASC_START), '.',
      ]));
    }
    if (d.orphans && d.orphans.rows) {
      append(box, notice('warn', plural(d.orphans.rows, 'sale matches', 'sales match') + ' no creator here. Offer names: ' +
        (d.orphans.offerRefs.join(', ') || 'none given') + '.'));
    }
  }

  // ---- The list ------------------------------------------------------------------------------

  function statusChip(c) {
    if (c.stoppedAtMs) return h('span', { class: 'chip bad' }, 'Stopped');
    if (!c.active) return h('span', { class: 'chip' }, 'Inactive');
    if (!c.appleCustomCodeId) return h('span', { class: 'chip warn' }, 'No Apple code yet');
    return null;
  }

  function endsCell(c) {
    if (!c.codeEndsOn) return h('td', null, '');
    const days = Math.ceil((c.codeEndsAtMs - state.data.nowMs) / C.DAY_MS);
    return h('td', null, h('div', { class: 'stack' },
      h('span', { class: 'nowrap' }, dayText(c.codeEndsOn)),
      h('span', { class: 'small ' + (days <= 14 ? 'chip warn' : 'faint') + ' nowrap', style: 'align-self: flex-start;' },
        days > 0 ? 'in ' + plural(days, 'day', 'days') : 'ended')));
  }

  function renderRows() {
    const d = state.data;
    const body = clear($('creatorRows'));
    if (!d.creators.length) {
      append(body, h('tr', { class: 'empty' }, h('td', { colspan: '7' }, 'No creators yet. Add creator, top right, makes the first one.')));
      return;
    }
    for (const c of d.creators) {
      const m = c.money;
      const off = !c.active || !!c.stoppedAtMs;
      const hasCode = !!c.appleCustomCodeId && !c.stoppedAtMs;
      const more = h('button', {
        type: 'button', class: 'btn sm ghost', 'aria-label': 'More for ' + (c.name || c.id), 'aria-haspopup': 'menu',
        onclick: (e) => openMenu(c, e.currentTarget),
      }, '⋯');
      append(body, h('tr', { class: off ? 'off' : null },
        h('td', null, h('div', { class: 'row', style: 'gap: 8px;' },
          h('b', null, c.name || c.id),
          h('span', { class: 'code-chip' }, c.code),
          statusChip(c))),
        h('td', null, h('div', { class: 'stack' },
          h('span', { class: 'nowrap' }, (c.discountPercent === null ? '?' : c.discountPercent) + '% off'),
          h('span', { class: 'small faint nowrap' }, (c.sharePercent === null ? '?' : c.sharePercent) + '% to them'))),
        h('td', { class: 'num' }, h('div', { class: 'stack' },
          h('span', null, String(m.sales)),
          m.refunds ? h('span', { class: 'small faint' }, plural(m.refunds, 'refund', 'refunds')) : null)),
        h('td', { class: 'num' }, C.money(m.earnedCents)),
        h('td', { class: 'num owed' }, C.money(m.owedCents)),
        endsCell(c),
        h('td', null, h('div', { class: 'acts' },
          h('button', {
            type: 'button', class: 'btn sm', disabled: hasCode ? null : true,
            title: hasCode ? null : 'The link works once Apple has the code',
            onclick: () => copy(C.shareLinkFor(c.code)),
          }, 'Copy link'),
          h('button', {
            type: 'button', class: 'btn sm', disabled: m.unpaidCents > 0 ? null : true,
            title: m.unpaidCents > 0 ? null : 'Nothing earned and unpaid',
            onclick: () => openPay(c),
          }, 'Pay'),
          more))));
    }
  }

  // ---- The row menu ------------------------------------------------------------------------------

  function closeMenu() {
    $('rowMenu').hidden = true;
    state.menuFor = null;
  }

  function openMenu(c, anchor) {
    const menu = clear($('rowMenu'));
    if (state.menuFor === c.id && !menu.hidden) {
      closeMenu();
      return;
    }
    state.menuFor = c.id;
    const item = (label, fn, cls) => h('button', {
      type: 'button', role: 'menuitem', class: cls || null,
      onclick: () => {
        closeMenu();
        fn();
      },
    }, label);
    append(menu,
      item(c.hasStatementLink ? 'New earnings page link' : 'Make their earnings page link', () => makePageLink(c)),
      item('Change their share', () => openShare(c)),
      !c.appleCustomCodeId && c.active && !c.stoppedAtMs && state.data.asc.ok ? item('Make the Apple code', () => openAddForExisting(c)) : null,
      item('Details', () => openDetails(c)),
      !c.active && !c.appleOfferCodeId && !c.stoppedAtMs ? item('Mark active again', () => reactivate(c)) : null,
      !c.stoppedAtMs ? h('hr') : null,
      !c.stoppedAtMs ? item('Stop the code', () => openStop(c), 'danger') : null);
    const r = anchor.getBoundingClientRect();
    menu.hidden = false;
    const width = menu.offsetWidth;
    menu.style.top = (window.scrollY + r.bottom + 6) + 'px';
    menu.style.left = Math.max(8, window.scrollX + r.right - width) + 'px';
    const first = menu.querySelector('button');
    if (first) first.focus();
  }

  // ---- Small dialogs from a row ------------------------------------------------------------------

  function showDlg(title, bodyNodes, footNodes) {
    const box = clear($('dlgBody'));
    append(box,
      h('div', { class: 'dlg-head' },
        h('h2', { id: 'dlgTitle' }, title),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close', onclick: () => closeDialog('dlg') }, '✕')),
      bodyNodes,
      footNodes ? h('div', { class: 'dlg-foot' }, footNodes) : null);
    openDialog('dlg');
  }

  function cancelBtn(label) {
    return h('button', { type: 'button', class: 'btn ghost lg', onclick: () => closeDialog('dlg') }, label || 'Cancel');
  }

  function openPay(c) {
    const m = c.money;
    const amount = h('input', { type: 'number', class: 'in', id: 'payAmount', min: '0.01', step: '0.01', inputmode: 'decimal' });
    amount.value = ((m.owedCents > 0 ? m.owedCents : m.unpaidCents) / 100).toFixed(2);
    const note = h('input', { type: 'text', class: 'in', id: 'payNote', maxlength: '200', placeholder: 'Like the transfer reference' });
    const msg = h('ul', { class: 'checks' });
    const save = h('button', {
      type: 'button', class: 'btn primary lg',
      onclick: async () => {
        save.disabled = true;
        const { ok, body } = await post('/api/creators/payout', { code: c.id, amountUsd: Number(amount.value), note: note.value });
        if (ok) {
          closeDialog('dlg');
          apply(body.state);
          toast('Payment of ' + C.money(Math.round(body.amountUsd * 100)) + ' to ' + c.name + ' recorded.');
        } else {
          save.disabled = false;
          clear(msg);
          append(msg, checkLine('bad', errorText(body)));
        }
      },
    }, 'Record payment');
    showDlg('Pay ' + (c.name || c.id), [
      h('p', { class: 'muted' }, 'Owed now ' + C.money(m.owedCents) + '. Earned and unpaid in all ' + C.money(m.unpaidCents) + '. Pay by bank first, then record it here.'),
      h('div', { class: 'fld' }, h('label', { for: 'payAmount' }, 'Amount paid, US dollars'), amount),
      h('div', { class: 'fld' }, h('label', { for: 'payNote' }, 'Note they see on their page'), note),
      msg,
    ], [cancelBtn(), save]);
    amount.focus();
  }

  function openShare(c) {
    const input = h('input', { type: 'number', class: 'in num', id: 'shareInput', min: '0', max: '100', step: '0.5', inputmode: 'decimal' });
    input.value = c.sharePercent === null ? '' : String(c.sharePercent);
    const msg = h('ul', { class: 'checks' });
    const save = h('button', {
      type: 'button', class: 'btn primary lg',
      onclick: async () => {
        save.disabled = true;
        const value = input.value.trim() === '' ? null : Number(input.value);
        const { ok, body } = await post('/api/creators/share', { code: c.id, sharePercent: value });
        if (ok) {
          closeDialog('dlg');
          apply(body.state);
          toast(body.changed ? c.name + '\'s share is now ' + input.value + '%.' : 'Nothing changed.');
        } else {
          save.disabled = false;
          clear(msg);
          append(msg, checkLine('bad', errorText(body)));
        }
      },
    }, 'Save');
    showDlg('Change ' + (c.name || c.id) + '\'s share', [
      h('div', { class: 'fld' },
        h('label', { for: 'shareInput' }, 'Their share of what Apple sends you'),
        h('div', { class: 'unit-row' }, input, h('span', { class: 'muted' }, '%'))),
      h('p', { class: 'small faint' }, 'Sales from now on use the new percent. Earlier sales keep theirs.'),
      msg,
    ], [cancelBtn(), save]);
    input.focus();
  }

  async function makePageLink(c) {
    if (c.hasStatementLink && !window.confirm('Make a new earnings page link for ' + (c.name || c.id) + '? The link they have now stops working.')) return;
    const { ok, body } = await post('/api/creators/statement-link', { code: c.id });
    if (!ok) {
      toast(errorText(body));
      return;
    }
    apply(body.state);
    showLink(c, body.link);
  }

  function showLink(c, link) {
    showDlg((c.name || c.id) + '\'s earnings page', [
      h('p', { class: 'muted' }, 'Send them this link. It opens their own page: their sales, money waiting and ready, and your payments.'),
      h('div', { class: 'linkbox' }, h('code', null, link), h('button', { type: 'button', class: 'btn sm primary', onclick: () => copy(link) }, 'Copy')),
      h('p', { class: 'small faint' }, 'Shown once. If it is lost, make a new one, which switches this one off.'),
    ], [cancelBtn('Done')]);
  }

  function openDetails(c) {
    const facts = [
      ['Code', c.code],
      ['Apple offer name', c.offerRef],
      ['Buyer pays', c.offerPriceUsd === null ? '?' : '$' + c.offerPriceUsd.toFixed(2) + ' in the US (' + c.discountPercent + '% off)'],
      ['Their share', (c.sharePercent === null ? '?' : c.sharePercent) + '% of what Apple sends you'],
      ['Uses allowed', c.usesAllowed === null ? '?' : Number(c.usesAllowed).toLocaleString('en-US')],
      ['Code ends', c.codeEndsOn ? dayText(c.codeEndsOn) + ', 00:00 Pacific' : '?'],
      ['Apple ids', c.appleOfferCodeId ? 'offer ' + c.appleOfferCodeId + (c.appleCustomCodeId ? ', code ' + c.appleCustomCodeId : ', no code yet') : 'none yet'],
      ['Paid so far', C.money(c.money.paidCents) + (c.lastPaidAtMs ? ', last on ' + msDay(c.lastPaidAtMs) : '')],
      ['Waiting', C.money(c.money.waitingCents) + ', under 60 days old'],
      ['Their page', c.hasStatementLink ? 'link made ' + msDay(c.statementKeyAtMs) : 'no link yet'],
      c.stoppedAtMs ? ['Stopped', msDay(c.stoppedAtMs)] : null,
    ].filter(Boolean);
    const list = h('dl', { class: 'facts' });
    for (const [k, v] of facts) append(list, h('dt', null, k), h('dd', null, v));
    const link = C.shareLinkFor(c.code);
    showDlg(c.name || c.id, [
      list,
      h('div', { class: 'fld' },
        h('span', { class: 'label' }, 'The link their followers tap'),
        h('div', { class: 'linkbox' }, h('code', null, link), h('button', { type: 'button', class: 'btn sm', onclick: () => copy(link) }, 'Copy'))),
    ], [cancelBtn('Close')]);
  }

  function openStop(c) {
    const msg = h('ul', { class: 'checks' });
    const stop = h('button', {
      type: 'button', class: 'btn danger solid lg',
      onclick: async () => {
        stop.disabled = true;
        const { ok, body } = await post('/api/creators/stop', { code: c.id });
        if (ok) {
          closeDialog('dlg');
          apply(body.state);
          toast(body.apple === 'stopped' ? (c.name || c.id) + '\'s code is stopped at Apple.' : (c.name || c.id) + ' is stopped.');
        } else {
          stop.disabled = false;
          clear(msg);
          append(msg, checkLine('bad', errorText(body)));
        }
      },
    }, 'Stop the code');
    showDlg('Stop ' + (c.name || c.id) + '\'s code?', [
      h('p', null, c.appleOfferCodeId
        ? 'Apple switches the offer off, so ' + c.code + ' stops working for everyone. Sales already made keep their share.'
        : 'They have no Apple code yet, so this only marks them stopped here.'),
      msg,
    ], [cancelBtn(), stop]);
  }

  async function reactivate(c) {
    const { ok, body } = await post('/api/creators/active', { code: c.id, active: true });
    if (ok) {
      apply(body.state);
      toast((c.name || c.id) + ' is active again.');
    } else {
      toast(errorText(body));
    }
  }

  // ---- Add creator --------------------------------------------------------------------------------

  function formInput() {
    return {
      name: $('cName').value.trim(),
      code: C.normalizeCode($('cCode').value),
      discountPercent: Number($('cOff').value),
      discountOff: $('cBase').value,
      sharePercent: $('cShare').value === '' ? null : Number($('cShare').value),
      codeEndsOn: $('cUntil').value,
      usesAllowed: Number($('cUses').value),
    };
  }

  function stepErrors(step) {
    const input = formInput();
    const all = C.checkCreatorInput(input, { nowMs: Date.now() }).errors;
    const mine = all.filter((e) => (step === 1 ? STEP1_CODES.has(e.code) : !STEP1_CODES.has(e.code)));
    if (step === 1 && input.code && state.data.creators.some((c) => c.id === input.code)) {
      mine.push({ code: 'taken', message: input.code + ' is taken. Pick another code.' });
    }
    return mine;
  }

  function resetAdd() {
    $('cName').value = '';
    $('cCode').value = '';
    $('cOff').value = '20';
    $('cShare').value = String(C.DEFAULT_SHARE_PERCENT);
    $('cUses').value = '1000';
    $('cBase').value = C.DEFAULT_PRODUCT;
    $('cRate').value = '0.70';
    $('cUntil').min = state.data.codeEndRange.min;
    $('cUntil').max = state.data.codeEndRange.max;
    $('cUntil').value = state.data.codeEndRange.max;
    state.step = 1;
    state.touched = { 1: false, 2: false };
    state.preview = null;
    state.previewError = null;
    state.previewLoading = false;
    state.createError = null;
    state.done = null;
  }

  function openAdd() {
    resetAdd();
    renderAdd();
    openDialog('addDialog');
    $('cName').focus();
  }

  /** A saved creator with no Apple code yet: straight to step 3 for it. */
  function openAddForExisting(c) {
    resetAdd();
    $('cName').value = c.name;
    $('cCode').value = c.code;
    state.step = 3;
    state.existing = c.id;
    state.previewDiscount = c.discountPercent;
    renderAdd();
    openDialog('addDialog');
    askPreview({ code: c.id });
  }

  function paintMoney() {
    const input = formInput();
    const m = C.moneyPreview({ productId: input.discountOff, discountPercent: input.discountPercent, sharePercent: input.sharePercent, keepRate: Number($('cRate').value) });
    $('mBuyer').textContent = m.buyerCents === null ? '?' : C.money(m.buyerCents);
    $('mApple').textContent = C.money(m.proceedsCents);
    $('mShareLabel').textContent = '(' + m.sharePercent + '%)';
    $('mCreator').textContent = C.money(m.creatorCents);
    $('mKeep').textContent = C.money(m.keepCents);
  }

  function renderPreviewBox() {
    const box = clear($('previewBox'));
    if (state.previewLoading) {
      append(box, h('p', { class: 'muted' }, 'Checking prices in every country with Apple. This takes about 20 seconds.'));
      return;
    }
    if (state.previewError) {
      append(box, h('ul', { class: 'checks' }, checkLine('bad', state.previewError)));
      return;
    }
    const p = state.preview;
    if (!p) return;
    const s = p.summary;
    const others = Math.max(0, s.territories - 1);
    const facts = [
      ['Apple offer', s.offerStep === 'create' ? s.offerRef + ', new' : s.offerRef + ', already at Apple'],
      ['Price', s.usPrice + ' in the US' + (s.offerStep === 'create' && others
        ? ', and at least ' + state.previewDiscount + '% off in ' + plural(others, 'more country', 'more countries')
        : '')],
      ['Code', s.code + ', ' + Number(s.usesAllowed).toLocaleString('en-US') + ' uses, ends ' + dayText(s.codeEndsOn)],
      ['Apple codes', (10 - Math.max(0, s.offersLeftAfter)) + ' of 10 used after this'],
    ];
    const list = h('dl', { class: 'facts' });
    for (const [k, v] of facts) append(list, h('dt', null, k), h('dd', null, v));
    append(box, list);
    const lines = h('ul', { class: 'checks' });
    for (const b of p.blocked) append(lines, checkLine('bad', b));
    for (const w of p.warnings || []) append(lines, checkLine('warn', w));
    if (s.deeper) append(lines, checkLine('warn', plural(s.deeper, 'country gets', 'countries get') + ' a little more off, where its currency has no closer price.'));
    if (s.dropped && s.dropped.length) append(lines, checkLine('warn', 'Left out, with no price low enough there: ' + s.dropped.join(', ') + '.'));
    if (lines.firstChild) append(box, lines);
    if (p.requests.length) {
      const details = h('details', null, h('summary', null, 'The exact requests Create sends'));
      for (const req of p.requests) append(details, h('pre', null, req.method + ' ' + req.path + '\n' + JSON.stringify(req.body, null, 2)));
      append(box, details);
    }
    if (state.createError) append(box, h('ul', { class: 'checks' }, checkLine('bad', state.createError)));
  }

  function renderDone() {
    const d = state.done;
    if (!d) return;
    $('doneTitle').textContent = d.saved ? d.name + ' is saved' : d.name + '\'s code is live';
    $('doneSub').textContent = d.saved
      ? 'No Apple code yet. Make it from their row when you are ready.'
      : 'Apple made the code ' + d.code + '.';
    $('doneLinks').hidden = d.saved;
    $('doneLink').textContent = d.shareLink;
    $('donePageBox').hidden = !d.pageLink;
    $('donePageBtn').hidden = !!d.pageLink;
    if (d.pageLink) $('donePageLink').textContent = d.pageLink;
  }

  function renderAdd() {
    const step = state.step;
    const items = $('addSteps').children;
    for (let i = 0; i < items.length; i++) {
      const n = i + 1;
      items[i].className = step === 'done' || n < step ? 'done' : n === step ? 'now' : '';
    }
    $('addPane1').hidden = step !== 1;
    $('addPane2').hidden = step !== 2;
    $('addPane3').hidden = step !== 3;
    $('addDone').hidden = step !== 'done';
    $('addTitle').textContent = step === 'done' ? 'Creator ready' : 'Add creator';

    const code = C.normalizeCode($('cCode').value);
    $('codeLink').textContent = C.shareLinkFor(code || 'CODE').replace(/^https:\/\//, '');
    paintMoney();

    const errors = clear($('formErrors'));
    if ((step === 1 || step === 2) && state.touched[step]) {
      for (const e of stepErrors(step)) append(errors, checkLine('bad', e.message));
    }

    const back = $('addBack');
    const next = $('addNext');
    const saveOnly = $('addSaveOnly');
    const ascOk = state.data.asc.ok;
    back.hidden = step === 1 || step === 'done' || (step === 3 && !!state.existing);
    saveOnly.hidden = !((step === 2 && !ascOk) || (step === 3 && !state.existing));
    saveOnly.className = step === 2 ? 'btn primary lg' : 'btn lg';
    next.hidden = step === 2 && !ascOk;
    if (step === 1) next.textContent = 'Next';
    else if (step === 2) next.textContent = 'Next: the Apple code';
    else if (step === 3) next.textContent = state.previewLoading ? 'Checking with Apple...' : 'Create the code';
    else next.textContent = 'Done';
    const p = state.preview;
    next.disabled = state.busy ||
      (step === 3 && (state.previewLoading || !p || p.blocked.length > 0 || !!state.createError));
    saveOnly.disabled = state.busy;
    if (step === 3) renderPreviewBox();
    if (step === 'done') renderDone();
  }

  async function askPreview(payload) {
    state.previewLoading = true;
    state.previewError = null;
    state.preview = null;
    state.createError = null;
    renderAdd();
    const { ok, body } = await post('/api/creators/apple/preview', payload);
    state.previewLoading = false;
    if (ok) state.preview = body.preview;
    else state.previewError = errorText(body) || 'Apple could not be asked just now.';
    renderAdd();
  }

  async function next() {
    const step = state.step;
    if (step === 1 || step === 2) {
      state.touched[step] = true;
      if (stepErrors(step).length) {
        renderAdd();
        return;
      }
      state.step = step + 1;
      renderAdd();
      if (state.step === 2) $('cOff').focus();
      if (state.step === 3) {
        state.previewDiscount = formInput().discountPercent;
        askPreview({ input: formInput() });
      }
      return;
    }
    if (step === 3) {
      const p = state.preview;
      if (!p || state.busy) return;
      state.busy = true;
      renderAdd();
      const { ok, body } = await post('/api/creators/apple/create', { planId: p.planId });
      state.busy = false;
      if (body.state) apply(body.state);
      if (ok) {
        state.done = { name: p.summary.name, code: p.summary.code, shareLink: p.summary.shareLink, saved: false, pageLink: null };
        state.step = 'done';
        state.existing = null;
        toast('Apple made the code for ' + p.summary.name + '.');
      } else {
        state.createError = errorText(body) || 'It did not go through.';
      }
      renderAdd();
      return;
    }
    closeDialog('addDialog');
  }

  async function saveOnly() {
    if (state.busy) return;
    state.touched[1] = true;
    state.touched[2] = true;
    if (stepErrors(1).length) {
      state.step = 1;
      renderAdd();
      return;
    }
    if (stepErrors(2).length) {
      state.step = 2;
      renderAdd();
      return;
    }
    state.busy = true;
    renderAdd();
    const input = formInput();
    const { ok, body } = await post('/api/creators/add', input);
    state.busy = false;
    if (ok) {
      apply(body.state);
      state.done = { name: input.name, code: input.code, shareLink: C.shareLinkFor(input.code), saved: true, pageLink: null };
      state.step = 'done';
      toast('Saved ' + input.name + '.');
    } else {
      state.createError = errorText(body);
      toast(errorText(body));
    }
    renderAdd();
  }

  async function donePageLink() {
    const d = state.done;
    if (!d) return;
    const { ok, body } = await post('/api/creators/statement-link', { code: d.code });
    if (!ok) {
      toast(errorText(body));
      return;
    }
    apply(body.state);
    d.pageLink = body.link;
    renderAdd();
  }

  // ---- Everything ------------------------------------------------------------------------------------

  function apply(data) {
    state.data = data;
    renderTiles();
    renderBanners();
    renderRows();
    $('addBtn').disabled = false;
  }

  async function loadAppleStatus() {
    let body;
    try {
      const res = await fetch('/api/creators/apple-status');
      body = await res.json();
    } catch (e) {
      body = { ok: false, error: 'Could not reach the admin tool.' };
    }
    if (body.ok) state.apple = body.status;
    else state.appleError = errorText(body) || 'no answer';
    if (state.data) renderTiles();
  }

  function wire() {
    $('addBtn').addEventListener('click', openAdd);
    $('addClose').addEventListener('click', () => closeDialog('addDialog'));
    closeOnBackdrop('addDialog');
    $('addDialog').addEventListener('close', () => {
      state.existing = null;
    });
    $('addNext').addEventListener('click', next);
    $('addBack').addEventListener('click', () => {
      if (state.step === 2 || state.step === 3) state.step -= 1;
      state.previewLoading = false;
      renderAdd();
    });
    $('addSaveOnly').addEventListener('click', saveOnly);
    for (const id of ['cName', 'cCode', 'cOff', 'cShare', 'cUntil', 'cUses', 'cBase', 'cRate']) {
      $(id).addEventListener('input', () => {
        if (id === 'cCode') {
          const clean = C.normalizeCode($('cCode').value);
          if (clean !== $('cCode').value) $('cCode').value = clean;
        }
        renderAdd();
      });
    }
    $('cName').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') next();
    });
    $('cCode').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') next();
    });
    $('doneCopy').addEventListener('click', () => copy($('doneLink').textContent));
    $('donePageBtn').addEventListener('click', donePageLink);
    $('donePageCopy').addEventListener('click', () => copy($('donePageLink').textContent));

    closeOnBackdrop('dlg');
    $('howBtn').addEventListener('click', () => openDialog('howDialog'));
    $('howClose').addEventListener('click', () => closeDialog('howDialog'));
    closeOnBackdrop('howDialog');

    document.addEventListener('click', (e) => {
      const menu = $('rowMenu');
      if (menu.hidden) return;
      if (menu.contains(e.target) || (e.target.closest && e.target.closest('[aria-haspopup="menu"]'))) return;
      closeMenu();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !$('rowMenu').hidden) closeMenu();
    });
    window.addEventListener('resize', closeMenu);
  }

  async function load() {
    let body;
    try {
      const res = await fetch('/api/creators');
      body = await res.json();
    } catch (e) {
      body = { ok: false, error: 'Could not reach the admin tool.' };
    }
    if (!body || body.ok === false) {
      append($('banners'), notice('danger', 'Could not load the creators: ' + errorText(body)));
      return;
    }
    wire();
    apply(body.state);
    if (body.state.asc.ok) loadAppleStatus();
  }

  load();
})();
