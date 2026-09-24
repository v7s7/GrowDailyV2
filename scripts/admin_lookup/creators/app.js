/**
 * The Creators page, in the browser.
 *
 * Reads everything from /api/creators, then (when the App Store Connect
 * settings are there) what Apple says from /api/creators/apple-status. The
 * Add form's money preview runs lib/creators.js (loaded as
 * /creators/rules.js, window.CreatorRules), the same maths the server
 * checks with.
 *
 * Making a creator's Apple code is two presses on purpose: Preview asks the
 * server to build the exact requests (it reads from Apple, changes
 * nothing), and only "Create in App Store Connect" sends them. Every write
 * answers with the page's fresh state, read back after the write.
 *
 * A plain file, not a template literal: see lib/wording_page.js for why.
 */
(function () {
  'use strict';

  const C = window.CreatorRules;
  // statementLink: the one link just made, { code, link }. The server keeps
  // only its hash, so this is the only time the page can show it.
  const state = { data: null, busy: false, touched: false, apple: null, open: null, preview: null, result: null, statementLink: null };

  // ---- DOM helpers ---------------------------------------------------------------

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
    toastTimer = setTimeout(() => el.classList.remove('show'), 4200);
  }

  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  function dayText(dateKey) {
    if (!dateKey) return '';
    const [y, m, d] = dateKey.split('-').map(Number);
    return d + ' ' + MONTHS[m - 1] + ' ' + y;
  }

  function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
  }

  async function copy(text) {
    try {
      await navigator.clipboard.writeText(text);
      toast('Copied.');
    } catch (e) {
      toast('Could not copy. Select the link and copy it by hand.');
    }
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
    if (!body) return 'It did not go through.';
    if (body.message) return body.message;
    if (body.error) return body.error;
    return 'It did not go through.';
  }

  // ---- Tiles ---------------------------------------------------------------------------

  function renderTiles() {
    const d = state.data;
    const apple = state.apple;
    const inUse = apple ? apple.activeOffers : d.offersInUse;
    $('tOffers').textContent = String(inUse);
    $('tOffersMax').textContent = String(d.maxOffers);
    $('tOffersBar').style.width = Math.min(100, (inUse / d.maxOffers) * 100) + '%';
    $('tOffersSub').textContent = apple
      ? 'Active offers on the two Lifetime products, as App Store Connect lists them. Apple allows 10 per app.'
      : 'One per creator, from this tool\'s records. Apple allows 10 per app.';
    $('tSales').textContent = String(d.totals.sales30);
    $('tSalesSub').textContent = d.totals.refunds30 ? plural(d.totals.refunds30, 'refunded', 'refunded') : 'None refunded';
    $('tOwed').textContent = C.money(d.totals.owedCents);
    $('tWaiting').textContent = C.money(d.totals.waitingCents);
  }

  // ---- The table ----------------------------------------------------------------------

  /** Only said when something is missing: a made code is the normal case, like in the design. */
  function appleLine(c) {
    if (c.appleCustomCodeId) return null;
    if (c.appleOfferCodeId) return h('span', { class: 'sub warn' }, 'Offer made, no code yet');
    return h('span', { class: 'sub warn' }, 'No Apple code yet');
  }

  function productPrice(productId) {
    const p = C.PRODUCTS[productId];
    return p ? '$' + p.priceUsd.toFixed(2) : '?';
  }

  function endsCell(c) {
    if (c.codeEndsAtMs === null) return h('td', null, '');
    const days = Math.ceil((c.codeEndsAtMs - state.data.nowMs) / C.DAY_MS);
    return h('td', null, h('div', { class: 'stack' },
      h('span', { class: 'nowrap' }, dayText(c.codeEndsOn)),
      h('span', { class: (days <= 14 ? 'sub warn' : 'sub') + ' nowrap' }, days > 0 ? 'in ' + plural(days, 'day', 'days') : 'ended')));
  }

  function actionsCell(c) {
    const m = c.money;
    const more = state.open && state.open.code === c.id && state.open.kind === 'more';
    return h('td', { class: 'actions' }, h('div', { class: 'act' },
      h('button', {
        type: 'button', class: 'btn small', onclick: () => openForm(c.id, 'pay'),
        disabled: m.unpaidCents <= 0 ? true : null, title: m.unpaidCents <= 0 ? 'Nothing earned and unpaid' : null,
      }, 'Mark paid'),
      h('button', {
        type: 'button', class: 'btn small ghost more-btn', onclick: () => openForm(c.id, 'more'),
        'aria-expanded': more ? 'true' : 'false', 'aria-label': 'More for ' + (c.name || c.id), title: 'Share %, Apple code, link, deactivate',
      }, '\u22EF')));
  }

  /** The row under a creator with everything that is not Mark paid: the link, the Apple ids, and the other actions. */
  function moreRow(c) {
    const link = C.shareLinkFor(c.code);
    const facts = [
      ['Offer name', c.offerRef],
      ['Buyer pays', c.offerPriceUsd === null ? '?' : '$' + c.offerPriceUsd.toFixed(2) + ' (' + c.discountPercent + '% off ' + productPrice(c.discountOff) + ')'],
      ['Uses allowed', c.usesAllowed === null ? '?' : Number(c.usesAllowed).toLocaleString('en-US')],
      ['Apple ids', c.appleOfferCodeId ? 'offer ' + c.appleOfferCodeId + (c.appleCustomCodeId ? ', code ' + c.appleCustomCodeId : ', no code yet') : 'none yet'],
      ['Last paid', c.lastPaidAtMs ? new Date(c.lastPaidAtMs).toISOString().slice(0, 10) : 'never'],
      ['Their page', c.hasStatementLink
        ? 'link made ' + (c.statementKeyAtMs ? new Date(c.statementKeyAtMs).toISOString().slice(0, 10) : '') + ' (only its hash is kept)'
        : 'no link yet'],
    ];
    const list = h('dl', { class: 'mini-facts' });
    for (const [k, v] of facts) append(list, h('dt', null, k), h('dd', null, v));
    const buttons = [
      h('button', { type: 'button', class: 'btn small', onclick: () => openForm(c.id, 'share') }, 'Change share %'),
      !c.appleCustomCodeId && c.active ? h('button', { type: 'button', class: 'btn small', onclick: () => previewExisting(c.id) }, 'Make the Apple code') : null,
      h('button', { type: 'button', class: 'btn small', onclick: () => makeStatementLink(c) }, c.hasStatementLink ? 'New page link' : 'Make their page link'),
      h('button', { type: 'button', class: 'btn small ghost', onclick: () => toggleActive(c) }, c.active ? 'Deactivate' : 'Reactivate'),
      h('button', { type: 'button', class: 'btn small ghost', onclick: () => { state.open = null; renderRows(); } }, 'Close'),
    ];
    const fresh = state.statementLink && state.statementLink.code === c.id ? state.statementLink.link : null;
    return h('tr', { class: 'more-row' }, h('td', { colspan: '9' },
      list,
      h('div', { class: 'linkbox' }, h('code', null, link), h('button', { type: 'button', class: 'btn small', onclick: () => copy(link) }, 'Copy link')),
      fresh ? [
        h('div', { class: 'linkbox' }, h('code', null, fresh), h('button', { type: 'button', class: 'btn small primary', onclick: () => copy(fresh) }, 'Copy their page link')),
        h('p', { class: 'fine' }, 'Send this to ' + (c.name || c.id) + '. It opens their own page: sales, money on hold, money ready, and your payments with their notes. ' +
          'This is the only time it is shown; if it is lost, make a new one, which switches this one off.'),
      ] : null,
      h('div', { class: 'row-form' }, buttons)));
  }

  /** Makes (or replaces) a creator's page link and shows it once. */
  async function makeStatementLink(c) {
    if (c.hasStatementLink && !window.confirm('Make a new page link for ' + (c.name || c.id) + '? The link they have now stops working at once.')) return;
    const { ok, body } = await post('/api/creators/statement-link', { code: c.id });
    if (!ok) {
      toast(errorText(body));
      return;
    }
    state.statementLink = { code: body.code, link: body.link };
    state.open = { code: body.code, kind: 'more' };
    apply(body.state);
    toast('Their page link is ready to copy.');
  }

  function formRow(c) {
    const open = state.open;
    if (!open || open.code !== c.id) return null;
    if (open.kind === 'more') return moreRow(c);
    const msg = h('span', { class: 'msg plain' });
    let body;
    if (open.kind === 'pay') {
      const amount = h('input', { type: 'number', class: 'inline-input', min: '0.01', step: '0.01', 'aria-label': 'Amount paid, US dollars' });
      amount.value = ((c.money.owedCents > 0 ? c.money.owedCents : c.money.unpaidCents) / 100).toFixed(2);
      // The creator sees this note on their own page, next to the payment.
      const note = h('input', { type: 'text', class: 'inline-input note-input', maxlength: '200', placeholder: 'Note the creator sees, like the transfer reference', 'aria-label': 'Note, shown to the creator' });
      msg.textContent = 'Owed now ' + C.money(c.money.owedCents) + '; earned and unpaid in all ' + C.money(c.money.unpaidCents) + '. Records the payment as made today.';
      const save = h('button', {
        type: 'button', class: 'btn small primary',
        onclick: async () => {
          save.disabled = true;
          const { ok, body: res } = await post('/api/creators/payout', { code: c.id, amountUsd: Number(amount.value), note: note.value });
          if (ok) {
            state.open = null;
            apply(res.state);
            toast('Payment of ' + C.money(Math.round(res.amountUsd * 100)) + ' to ' + c.name + ' recorded.');
          } else {
            save.disabled = false;
            msg.className = 'msg';
            msg.textContent = errorText(res);
          }
        },
      }, 'Record payment');
      body = [h('b', { style: 'font-size:12.5px' }, 'Mark paid, US dollars'), amount, note, save];
    } else {
      const share = h('input', { type: 'number', class: 'inline-input', min: '0', max: '100', step: '0.5', 'aria-label': 'Creator share, percent' });
      share.value = c.sharePercent === null ? '' : String(c.sharePercent);
      msg.textContent = 'Only sales recorded after this change use the new percent; earlier sales keep theirs.';
      const save = h('button', {
        type: 'button', class: 'btn small primary',
        onclick: async () => {
          save.disabled = true;
          // An empty box is no answer, not 0%: Number('') would quietly be 0.
          const value = share.value.trim() === '' ? null : Number(share.value);
          const { ok, body: res } = await post('/api/creators/share', { code: c.id, sharePercent: value });
          if (ok) {
            state.open = null;
            apply(res.state);
            toast(res.changed ? c.name + '\'s share is now ' + share.value + '%.' : 'Nothing changed.');
          } else {
            save.disabled = false;
            msg.className = 'msg';
            msg.textContent = errorText(res);
          }
        },
      }, 'Save share');
      body = [h('b', { style: 'font-size:12.5px' }, 'Creator share, %'), share, save];
    }
    const cancel = h('button', { type: 'button', class: 'btn small ghost', onclick: () => { state.open = null; renderRows(); } }, 'Cancel');
    return h('tr', null, h('td', { colspan: '9' }, h('div', { class: 'row-form' }, body, cancel, msg)));
  }

  function renderRows() {
    const d = state.data;
    const body = clear($('creatorRows'));
    if (!d.creators.length) {
      append(body, h('tr', { class: 'empty-row' }, h('td', { colspan: '9' }, 'No creators yet. Add the first one on the right.')));
    }
    for (const c of d.creators) {
      const m = c.money;
      const salesSubs = [];
      if (m.refunds) salesSubs.push(h('span', { class: 'sub bad' }, plural(m.refunds, 'refund', 'refunds')));
      if (m.needsReview) salesSubs.push(h('span', { class: 'sub warn', title: 'The webhook could not work out a share for these rows' }, plural(m.needsReview, 'needs review', 'need review')));
      append(body, h('tr', { class: c.active ? null : 'inactive' },
        h('td', null, h('div', { class: 'stack' },
          h('span', { style: 'font-weight:600' }, c.name || c.id, c.active ? null : h('span', { class: 'chip-status small', style: 'margin-inline-start:6px' }, 'Inactive')),
          h('code', { class: 'code' }, c.code),
          appleLine(c))),
        h('td', null, h('div', { class: 'stack' },
          h('span', { class: 'nowrap', title: 'Buyer pays ' + (c.offerPriceUsd === null ? '?' : '$' + c.offerPriceUsd.toFixed(2)) },
            (c.discountPercent === null ? '?' : c.discountPercent) + '% off ' + productPrice(c.discountOff)),
          h('span', { class: 'sub nowrap' }, (c.sharePercent === null ? '?' : c.sharePercent) + '% share'))),
        h('td', { class: 'num' }, h('div', { class: 'stack' }, h('span', null, String(m.sales)), salesSubs)),
        h('td', { class: 'num' }, C.money(m.earnedCents)),
        h('td', { class: 'num muted-cell' }, C.money(m.paidCents)),
        h('td', { class: 'num muted-cell' }, C.money(m.waitingCents)),
        h('td', { class: 'num owed' }, C.money(m.owedCents)),
        endsCell(c),
        actionsCell(c)));
      append(body, formRow(c));
    }
    const foot = clear($('creatorFoot'));
    if (d.creators.length) {
      const t = d.totals;
      append(foot, h('tr', null,
        h('th', { scope: 'row' }, 'All creators'),
        h('td', null, ''),
        h('td', { class: 'num' }, String(t.sales)),
        h('td', { class: 'num' }, C.money(t.earnedCents)),
        h('td', { class: 'num muted-cell' }, C.money(t.paidCents)),
        h('td', { class: 'num muted-cell' }, C.money(t.waitingCents)),
        h('td', { class: 'num owed' }, C.money(t.owedCents)),
        h('td', null, ''),
        h('td', null, '')));
    }
  }

  function renderLedgerNotes() {
    const d = state.data;
    const box = clear($('ledgerNotes'));
    if (d.orphans.rows) {
      append(box, h('div', { class: 'banner warn' }, h('div', { class: 'grow' },
        h('b', null, plural(d.orphans.rows, 'ledger row matches', 'ledger rows match') + ' no creator here. '),
        'Offer names: ' + (d.orphans.offerRefs.join(', ') || 'none given') + '. A creator whose offer name matches them would be credited from now on; these rows stay unassigned.')));
    }
    if (d.sandboxRows) {
      append(box, h('p', { class: 'fine' }, plural(d.sandboxRows, 'sandbox ledger row is', 'sandbox ledger rows are') + ' left out of every number here.'));
    }
  }

  function openForm(code, kind) {
    state.open = state.open && state.open.code === code && state.open.kind === kind ? null : { code, kind };
    renderRows();
  }

  async function toggleActive(c) {
    const question = c.active
      ? 'Mark ' + c.name + ' (' + c.code + ') inactive here? This does not turn their Apple code off: it keeps working until it ends' +
        (c.codeEndsOn ? ' on ' + dayText(c.codeEndsOn) : '') + ', and sales through it still earn their share. To stop the code itself, turn off the offer ' + c.offerRef + ' in App Store Connect.'
      : 'Make ' + c.name + ' (' + c.code + ') active again?';
    if (!window.confirm(question)) return;
    const { ok, body } = await post('/api/creators/active', { code: c.id, active: !c.active });
    if (ok) {
      apply(body.state);
      toast(c.active ? c.name + ' is inactive.' : c.name + ' is active again.');
    } else {
      toast(errorText(body));
    }
  }

  // ---- App Store Connect settings and status --------------------------------------------

  function renderAscNote() {
    const d = state.data;
    const box = clear($('ascNote'));
    if (!d.asc.ok) {
      append(box, h('div', { class: 'banner warn' }, h('div', { class: 'grow' },
        h('b', null, 'App Store Connect is not set up for this tool. '),
        d.asc.missing.join('. ') + '. Start the tool with ',
        h('code', null, 'ASC_KEY_ID=8672BSV59Q ASC_ISSUER_ID=fb55eebc-827e-4fcd-a941-989b2e36807b npm start'),
        ' to make codes from here. Until then, Save without the Apple code records the creator, and the code can be made later from its row.')));
      return;
    }
    if (state.apple) {
      for (const p of state.apple.products) {
        if (p.state !== 'APPROVED') {
          append(box, h('div', { class: 'banner warn' }, h('div', { class: 'grow' },
            h('b', null, p.productId + ' is ' + (p.state || 'unknown') + ' in App Store Connect. '),
            'Apple only makes codes for an approved product, so codes with the discount off ' + productPrice(p.productId) + ' wait until it passes review.')));
        }
      }
    }
  }

  async function loadAppleStatus() {
    let body;
    try {
      const res = await fetch('/api/creators/apple-status');
      body = await res.json();
    } catch (e) {
      body = { ok: false, error: 'Could not reach the admin tool.' };
    }
    if (body.ok) {
      state.apple = body.status;
      renderTiles();
      renderAscNote();
    } else {
      $('tOffersSub').textContent = 'From this tool\'s records. App Store Connect did not answer: ' + errorText(body);
    }
  }

  // ---- The Add form ----------------------------------------------------------------------

  function formInput() {
    return {
      name: $('cName').value.trim(),
      code: $('cCode').value.trim().toUpperCase(),
      discountPercent: Number($('cOff').value),
      discountOff: $('cBase').value,
      sharePercent: $('cShare').value === '' ? null : Number($('cShare').value),
      codeEndsOn: $('cUntil').value,
      usesAllowed: Number($('cUses').value),
    };
  }

  function paintForm() {
    const d = state.data;
    const codeBox = $('cCode');
    const clean = C.normalizeCode(codeBox.value);
    if (clean !== codeBox.value) codeBox.value = clean;
    const input = formInput();
    const m = C.moneyPreview({ productId: input.discountOff, discountPercent: input.discountPercent, sharePercent: input.sharePercent, keepRate: Number($('cRate').value) });
    $('mBuyer').textContent = m.buyerCents === null ? '?' : C.money(m.buyerCents);
    $('mApple').textContent = C.money(m.proceedsCents);
    $('mShareLabel').textContent = '(' + m.sharePercent + '%)';
    $('mCreator').textContent = C.money(m.creatorCents);
    $('mKeep').textContent = C.money(m.keepCents);
    $('mPlainNote').textContent = 'Without a code, a ' + C.money(m.baseCents) + ' sale leaves you ' + C.money(m.plainCents) +
      '. Bahrain buyers pay VAT inside the price, so every line is about 9% lower there.';
    const shown = clean || 'CODE';
    $('cLink').textContent = C.shareLinkFor(shown).replace(/^https:\/\//, '');
    const left = d.maxOffers - (state.apple ? state.apple.activeOffers : d.offersInUse) - 1;
    $('createNote').textContent = 'Makes the Apple offer ' + C.offerRefFor(shown) + ' with the code ' + shown + '. Uses 1 of your ' + d.maxOffers +
      ' offers, leaving ' + Math.max(0, left) + '.';

    const check = C.checkCreatorInput(input, { nowMs: Date.now() });
    const list = clear($('formErrors'));
    if (state.touched) check.errors.forEach((e) => append(list, h('li', { class: 'bad' }, h('span', { 'aria-hidden': 'true' }, '✕'), h('span', null, e.message))));
    $('previewBtn').disabled = !check.ok || state.busy || !d.asc.ok;
    $('saveOnlyBtn').disabled = !check.ok || state.busy;
  }

  function resetForm() {
    $('cName').value = '';
    $('cCode').value = '';
    $('cOff').value = '20';
    $('cShare').value = String(C.DEFAULT_SHARE_PERCENT);
    $('cUses').value = '1000';
    $('cBase').value = C.DEFAULT_PRODUCT;
    $('cUntil').value = state.data.codeEndRange.max;
    state.touched = false;
  }

  // ---- The two-step Apple code ----------------------------------------------------------

  function dl(rows) {
    const list = h('dl');
    for (const [k, v] of rows) {
      if (v === null || v === undefined || v === '') continue;
      append(list, [h('dt', null, k), h('dd', null, v)]);
    }
    return list;
  }

  const TERRITORY_NAMES = { USA: 'United States', BHR: 'Bahrain', SAU: 'Saudi Arabia', ARE: 'UAE', KWT: 'Kuwait', QAT: 'Qatar', OMN: 'Oman', EGY: 'Egypt', GBR: 'United Kingdom', DEU: 'Germany' };

  function renderPreview() {
    const box = clear($('previewBox'));
    const p = state.preview;
    const r = state.result;
    if (!p && !r) return;
    const panel = h('div', { class: 'preview', role: 'region', 'aria-label': 'Apple code preview' });
    if (p) {
      const s = p.summary;
      append(panel, h('h3', null, (p.isNew ? 'Preview: ' : 'Apple code for ') + s.name + ' (' + s.code + ')'));
      if (p.blocked.length) {
        append(panel, h('div', { class: 'blocked' }, h('b', null, 'Can\'t be made yet. '), p.blocked.join(' ')));
      }
      for (const w of p.warnings || []) {
        append(panel, h('div', { class: 'banner warn' }, h('div', { class: 'grow' }, h('b', null, 'Worth knowing. '), w)));
      }
      const others = s.sample.filter((x) => x.territory !== 'USA')
        .map((x) => (TERRITORY_NAMES[x.territory] || x.territory) + ' ' + x.customerPrice + (x.currency ? ' ' + x.currency : '') +
          (x.regularPrice ? ' (was ' + x.regularPrice + ', ' + x.percentOff + '% off)' : '')).join(', ');
      const dropped = (s.dropped || []).map((t) => TERRITORY_NAMES[t] || t).join(', ');
      append(panel, dl([
        ['Product', s.productId + ' (Apple id ' + s.iapId + '), ' + (s.productState || 'state unknown') +
          (s.usPriceToday ? ', sells for ' + s.usPriceToday + ' in the US today' : '')],
        ['Offer', s.offerStep === 'create' ? s.offerRef + ', a new offer' : s.offerRef + ', already in App Store Connect (' + s.offerId + '), used as it is'],
        ['Who can use it', s.eligibility],
        ['Price', s.offerStep === 'create'
          ? s.usPrice + ' in the US' + (s.usProceeds ? ' (Apple says you get $' + Number(s.usProceeds).toFixed(2) + ')' : '') +
            ', and at least the same percent off in ' + plural(Math.max(0, s.territories - 1), 'other territory', 'other territories') + (others ? ': ' + others + ', and the rest' : '') +
            (s.deeper ? '. ' + plural(s.deeper, 'territory gets', 'territories get') + ' a little more off, where its currency has no closer price' : '') +
            (dropped ? '. Left out, with no price low enough there: ' + dropped : '')
          : s.usPrice + ' in the US, as the existing offer has it'],
        ['Code', s.codeStep === 'create'
          ? s.code + ', ' + Number(s.usesAllowed).toLocaleString('en-US') + ' uses, ends ' + dayText(s.codeEndsOn) + ' at 00:00 Pacific time'
          : s.code + ', already under this offer in App Store Connect'],
        ['Apple offers', s.activeOffers + ' active now; ' + Math.max(0, s.offersLeftAfter) + ' of 10 left after this'],
        ['Share link', s.shareLink],
      ]));
      if (p.requests.length) {
        for (const req of p.requests) {
          append(panel, h('details', null,
            h('summary', null, req.step + ': ' + req.method + ' ' + req.path),
            h('pre', null, JSON.stringify(req.body, null, 2))));
        }
        append(panel, h('p', { class: 'fine' }, 'These are the exact requests Create sends, in this order, signed with your App Store Connect key.' +
          (p.requests.length === 2 ? ' The code request goes under the id Apple returns for the new offer.' : '') + ' This preview is good for 15 minutes.'));
      } else {
        append(panel, h('p', { class: 'fine' }, 'Apple already has both the offer and the code. Create sends nothing to Apple; it only records their ids here.'));
      }
      const create = h('button', {
        type: 'button', class: 'btn primary big', disabled: p.blocked.length || state.busy ? true : null,
        onclick: () => createApple(create),
      }, p.requests.length ? 'Create in App Store Connect' : 'Record the Apple ids');
      const cancel = h('button', { type: 'button', class: 'btn ghost', onclick: () => { state.preview = null; renderPreview(); } }, 'Cancel');
      append(panel, h('div', { class: 'btn-row' }, create, cancel));
    }
    if (r) {
      append(panel, h('div', { class: 'result ' + (r.ok ? 'ok' : 'bad') }, r.message));
      if (r.ok && r.shareLink) {
        append(panel, h('div', { class: 'linkbox' }, h('code', null, r.shareLink),
          h('button', { type: 'button', class: 'btn small', onclick: () => copy(r.shareLink) }, 'Copy')));
      }
      if (!p) append(panel, h('div', { class: 'btn-row' }, h('button', { type: 'button', class: 'btn ghost', onclick: () => { state.result = null; renderPreview(); } }, 'Close')));
    }
    append(box, panel);
    panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  async function askPreview(payload, button) {
    if (state.busy) return;
    state.busy = true;
    if (button) button.disabled = true;
    state.result = null;
    const { ok, body } = await post('/api/creators/apple/preview', payload);
    state.busy = false;
    if (button) button.disabled = false;
    if (ok) {
      state.preview = body.preview;
    } else {
      state.preview = null;
      state.result = { ok: false, message: errorText(body) };
    }
    renderPreview();
    paintForm();
  }

  function previewExisting(code) {
    askPreview({ code }, null);
  }

  async function createApple(button) {
    const p = state.preview;
    if (!p || state.busy) return;
    state.busy = true;
    button.disabled = true;
    const { ok, body } = await post('/api/creators/apple/create', { planId: p.planId });
    state.busy = false;
    state.preview = null;
    state.result = { ok, message: errorText(body) || (ok ? 'Done.' : 'It did not go through.'), shareLink: ok ? p.summary.shareLink : null };
    if (body.state) apply(body.state);
    // A stage means the creator was saved before Apple answered, so the
    // form's code is taken now: its row carries on from here.
    if (p.isNew && (ok || body.stage)) resetForm();
    renderPreview();
    paintForm();
    if (ok) toast('Apple code made for ' + p.summary.name + '.');
  }

  async function saveOnly() {
    if (state.busy) return;
    state.busy = true;
    $('saveOnlyBtn').disabled = true;
    const { ok, body } = await post('/api/creators/add', formInput());
    state.busy = false;
    if (ok) {
      apply(body.state);
      resetForm();
      paintForm();
      toast('Saved. Its row has Make the Apple code for when you are ready.');
    } else {
      toast(errorText(body));
      paintForm();
    }
  }

  // ---- Everything ------------------------------------------------------------------------

  function apply(data) {
    const first = !state.data;
    state.data = data;
    if (first) {
      const until = $('cUntil');
      until.min = data.codeEndRange.min;
      until.max = data.codeEndRange.max;
      until.value = data.codeEndRange.max;
      $('cShare').value = String(C.DEFAULT_SHARE_PERCENT);
    }
    renderTiles();
    renderRows();
    renderLedgerNotes();
    renderAscNote();
    paintForm();
  }

  function wire() {
    for (const id of ['cName', 'cCode', 'cOff', 'cBase', 'cShare', 'cUntil', 'cUses', 'cRate']) {
      $(id).addEventListener('input', () => {
        if (id !== 'cRate') state.touched = true;
        paintForm();
      });
    }
    $('copyLink').addEventListener('click', () => copy(C.shareLinkFor(C.normalizeCode($('cCode').value) || 'CODE')));
    $('previewBtn').addEventListener('click', () => {
      state.touched = true;
      askPreview({ input: formInput() }, $('previewBtn'));
    });
    $('saveOnlyBtn').addEventListener('click', () => {
      state.touched = true;
      saveOnly();
    });
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
      append($('banners'), h('div', { class: 'banner danger' }, h('div', { class: 'grow' }, 'Could not load the creators: ' + errorText(body))));
      return;
    }
    wire();
    apply(body.state);
    if (body.state.asc.ok) loadAppleStatus();
  }

  load();
})();
