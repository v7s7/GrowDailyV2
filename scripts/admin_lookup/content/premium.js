/**
 * The Premium page, in the browser.
 *
 * Aziz, 2026-09-26: "make ... the premium details all in the admin change
 * firebase, online change not hard code". Everything the paywall says, in
 * the order a reader meets it, and its list of what Premium includes: the
 * rows' words, their order, their icons, rows taken off and rows added.
 *
 * Every word here is an S string, the same one the Wording page's App text
 * edits, and saves exactly as it would (same checks, same History, same
 * Undo). The list's order, icons and added rows are the `benefits` edits
 * (see content_edits.dart). One Save sends both, and the server writes them
 * in one transaction.
 *
 * The phone on the right draws the paywall's top half from the page as it
 * is now, in the app's own colours, opened from any of the places that
 * open it (each one puts its own benefit first).
 *
 * No em dash anywhere in this file, including comments.
 */
(function () {
  'use strict';

  const K = window.ContentKit;
  const R = window.WordingRules;
  const C = window.ContentRules;
  const { h, $, clear, button } = K;
  const LANGS = ['ar', 'en'];
  const LANG_NAME = { ar: 'Arabic', en: 'English' };
  const norm = (t) => R.normalizeText(t);

  /**
   * The paywall's words, in the order a reader meets them. A key the app
   * no longer has is skipped; any `premium` string not named here lands in
   * "Other Premium text", so a string added later is never out of reach.
   */
  const TEXT_GROUPS = [
    {
      id: 'top', title: 'Top of the page', open: true,
      note: 'The title bar and the two lines under the crown.',
      keys: [['premiumTitle', 'Title bar'], ['premiumHeadline', 'Headline'], ['premiumSubhead', 'Line under the headline']],
    },
    { id: 'benefits' },
    {
      id: 'plans', title: 'Plans and the buy button', open: true,
      note: 'Prices are never text: they come from the App Store and Google Play in the reader’s own currency.',
      keys: [
        ['premiumLifetime', 'Lifetime plan'], ['premiumOneTime', 'Under the Lifetime price'],
        ['premiumMonthly', 'Monthly plan'], ['premiumPerMonth', 'Under the Monthly price'],
        ['premiumBestValueBadge', 'Badge on the first plan'], ['premiumCta', 'Buy button'],
        ['premiumYearly', 'Yearly plan (no yearly plan in the stores yet)'], ['premiumPerYear', 'Under the Yearly price'],
        ['premiumSave', 'Yearly saving'],
      ],
    },
    {
      id: 'under', title: 'Under the buy button', open: false,
      warn: 'Apple requires this small print beside a subscription (guideline 3.1.2), and reviewers read it. Keep every sentence true.',
      keys: [
        ['premiumRestore', 'Restore button'], ['premiumHaveCode', 'Offer code button (iPhone)'],
        ['premiumFinePrintLifetime', 'Small print, Lifetime'], ['premiumFinePrintMonthly', 'Small print, Monthly on iPhone'],
        ['premiumFinePrintMonthlyPlay', 'Small print, Monthly on Android'],
        ['premiumTermsOfUse', 'Terms link'], ['premiumPrivacyPolicy', 'Privacy link'],
      ],
    },
    {
      id: 'owned', title: 'When Premium is active', open: false,
      keys: [
        ['premiumActive', 'Premium is active'], ['premiumLifetimeOwned', 'Lifetime owner'],
        ['premiumLifetimeStillRenewing', 'Lifetime, with a Monthly still renewing'], ['premiumManageSubscription', 'Manage button'],
        ['premiumUpgradeTitle', 'Monthly to Lifetime: title'], ['premiumUpgradeCancelNote', 'Monthly to Lifetime: cancel note'],
        ['premiumUpgradeCta', 'Monthly to Lifetime: button'],
      ],
    },
    {
      id: 'messages', title: 'Messages after a tap', open: false,
      keys: [
        ['premiumPurchaseError', 'Something went wrong'], ['premiumPurchasePending', 'Payment still pending'],
        ['premiumPurchaseNotEntitled', 'Paid, but not active yet'], ['premiumRestoreSuccess', 'Restored'],
        ['premiumRestoreNothingFound', 'Nothing to restore'], ['premiumComingSoon', 'Plans did not load'],
        ['premiumBuyOnIphone', 'On the web'], ['premiumRetry', 'Try again button'], ['premiumLinkOpenError', 'A link did not open'],
      ],
    },
    {
      id: 'offers', title: 'Welcome price and sales', open: false,
      note: 'Only shown while an offer runs (the Sale page).',
      keys: [
        ['premiumWelcomeTitle', 'Welcome price: title'], ['premiumWelcomeEndsIn', 'Welcome price: countdown label'],
        ['premiumWelcomeFinePrint', 'Welcome price: small print'], ['premiumSaleEndsIn', 'Sale: countdown label'],
        ['premiumSaleFinePrint', 'Sale: small print'], ['premiumThenPrice', 'Price after the welcome price'],
        ['premiumRegularPriceSpoken', 'Crossed-out price, read aloud'], ['premiumCountdownSpoken', 'Countdown, read aloud'],
        ['premiumCountdownDays', 'Countdown: days'], ['premiumCountdownHours', 'Countdown: hours'],
        ['premiumCountdownMinutes', 'Countdown: minutes'], ['premiumCountdownSeconds', 'Countdown: seconds'],
      ],
    },
    {
      id: 'gates', title: 'Where the app sends people to Premium', open: false,
      note: 'The sheets a locked feature opens before the paywall.',
      keys: [
        ['guestLimitTitle', 'Guest limit: title'], ['guestLimitBody', 'Guest limit: text'], ['guestLimitCta', 'Guest limit: button'],
        ['guestLimitMaybeLater', 'Maybe later (every limit sheet)'],
        ['roomLimitTitle', 'Room limit: title'], ['roomLimitBody', 'Room limit: text'],
        ['reminderGateTitle', 'More reminders: title'], ['reminderGateBody', 'More reminders on a task'], ['reminderGateHabitBody', 'More reminders on a habit'],
        ['voiceNoteGateTitle', 'Voice notes: title'], ['voiceNoteGateBody', 'Voice notes: text'],
        ['navBarLockedTitle', 'Bottom bar: title'], ['navBarLockedBody', 'Bottom bar: text'], ['navBarLockedCta', 'Bottom bar: button'],
        ['historyLockedBody', 'History: text'], ['historyLockedCta', 'History: button'],
        ['demoGateMonthTitle', 'History example: title'], ['demoGateCta', 'History example: button'], ['demoGateNotNow', 'History example: not now'],
      ],
    },
    { id: 'other', title: 'Other Premium text', open: false, note: 'Every other Premium string in the app, so a new one is never out of reach.', keys: 'rest' },
  ];

  /** Which benefit leads when the paywall is opened from each place (the
   *  same map as _orderedBenefits in premium_screen.dart). */
  const REASONS = [
    ['general', 'Settings (nothing leads)', null],
    ['appearance', 'A locked colour or theme', 'appearance'],
    ['history', 'Locked history', 'history'],
    ['tasks', 'A second reminder', 'reminders'],
    ['voice', 'Voice notes', 'voice'],
    ['navBar', 'The bottom bar', 'bottom-bar'],
    ['rooms', 'The room limit', 'rooms'],
  ];

  /** The paywall's colour strip, kCustomSwatches[2] in theme_preset.dart. */
  const SWATCHES = ['#F6BFB9', '#F8C196', '#E0C8B2', '#EEC931', '#61E57B', '#19E5C9', '#A7D0F8', '#DDC1F4', '#F7BADB'];

  const state = {
    data: null,
    // The catalog's `benefits`: { items: [{id, icon, titleKey, descKey}], icons, fallbackIcon }.
    builtIn: null,
    saved: null,
    // The list as edited: [{ id, icon, title: {ar, en}, desc: {ar, en} }].
    rows: null,
    savedList: '',
    // The page's other words as edited, by key: { ar, en }.
    texts: new Map(),
    open: new Set(),
    lang: 'ar',
    reason: 'general',
    saving: false,
  };

  let byKey = new Map();
  let builtInById = new Map();
  let groups = [];
  let benefitKeys = new Set();
  let titleKeys = new Set();

  // ---- Strings ----------------------------------------------------------------

  function liveText(key, lang) {
    const table = state.data.live.strings[lang] || {};
    if (Object.prototype.hasOwnProperty.call(table, key)) return table[key];
    const entry = byKey.get(key);
    return entry ? entry[lang] : '';
  }

  function builtInText(key, lang) {
    const entry = byKey.get(key);
    return entry ? entry[lang] : '';
  }

  function isEdited(key, lang) {
    return Object.prototype.hasOwnProperty.call(state.data.live.strings[lang] || {}, key);
  }

  /** Edited, and the app's own text has changed since the edit was made:
   *  the same test as the Wording page's "Changed in code". */
  function drifted(key, lang) {
    if (!isEdited(key, lang)) return false;
    const base = ((state.data.admin.bases || {})[lang] || {})[key];
    return typeof base === 'string' && base !== builtInText(key, lang);
  }

  function driftBadge(keys) {
    const langs = LANGS.filter((lang) => keys.some((key) => drifted(key, lang)));
    if (!langs.length) return null;
    return h('span', {
      class: 'badge drift',
      title: 'The app’s own ' + langs.map((l) => LANG_NAME[l]).join(' and ') +
        ' text changed after you edited it. Your edit still shows. "Use built-in text" shows the new one.',
    }, 'Changed in code');
  }

  /** The screens besides the paywall that show [key], for "Also on". */
  function alsoOn(key) {
    const entry = byKey.get(key);
    return ((entry && entry.screens) || []).filter((s) => s !== 'Premium paywall');
  }

  /** [text] for the preview, with any {part} shown as a sample. */
  function sample(text) {
    return String(text || '')
      .replace(/\{pct\}/g, '63%')
      .replace(/\{price\}/g, '$39.99')
      .replace(/\{[^{}\n]+\}/g, '…');
  }

  function draftText(key, lang) {
    const t = state.texts.get(key);
    return t ? t[lang] : liveText(key, lang);
  }

  /** Every word typed differently from what this page loaded, as the
   *  server wants it: the new text, or null for "back to the built-in".
   *  A built-in benefit row's words are strings too, so they are here.
   *  Worked out against what the page loaded (state.data.live changes only
   *  with this page's own saves), never against the server now, so a tab
   *  left open never sends words it did not change. */
  function textChanges() {
    const out = {};
    const add = (key, lang, value) => {
      const typed = norm(value);
      if (typed === norm(liveText(key, lang))) return;
      out[key] = Object.assign(out[key] || {}, { [lang]: typed === norm(builtInText(key, lang)) ? null : typed });
    };
    state.texts.forEach((t, key) => LANGS.forEach((lang) => add(key, lang, t[lang])));
    (state.rows || []).forEach((row) => {
      const b = builtInById.get(row.id);
      if (!b) return;
      LANGS.forEach((lang) => {
        add(b.titleKey, lang, row.title[lang]);
        add(b.descKey, lang, row.desc[lang]);
      });
    });
    return out;
  }

  /** What each changed string was when this page loaded: its edit, or null
   *  for the built-in text. The server refuses the save if one has moved. */
  function stringsBase(changes) {
    const out = {};
    Object.keys(changes).forEach((key) => {
      out[key] = {};
      Object.keys(changes[key]).forEach((lang) => {
        out[key][lang] = isEdited(key, lang) ? state.data.live.strings[lang][key] : null;
      });
    });
    return out;
  }

  /** How many changed words would be refused: the string rules, and for a
   *  benefit row the row's own length limit. */
  function textProblems() {
    let n = 0;
    const changes = textChanges();
    Object.keys(changes).forEach((key) => {
      Object.keys(changes[key]).forEach((lang) => {
        const value = changes[key][lang];
        if (value === null) return;
        if (!R.checkStringEdit(byKey.get(key), lang, value).ok) n++;
        else if (benefitKeys.has(key) && value.length > (titleKeys.has(key) ? C.MAX_BENEFIT_TITLE_LENGTH : C.MAX_BENEFIT_DESC_LENGTH)) n++;
      });
    });
    return n;
  }

  // ---- The benefit rows -------------------------------------------------------

  function rowsFrom(edits, useBuiltInWords) {
    const words = useBuiltInWords ? builtInText : liveText;
    return C.resolveBenefits(state.builtIn, edits).map((slot) => {
      const b = builtInById.get(slot.id);
      if (b) {
        return {
          id: slot.id,
          icon: slot.icon,
          title: { ar: words(b.titleKey, 'ar'), en: words(b.titleKey, 'en') },
          desc: { ar: words(b.descKey, 'ar'), en: words(b.descKey, 'en') },
        };
      }
      const a = slot.added;
      return { id: slot.id, icon: slot.icon, title: { ar: a.titleAr, en: a.titleEn }, desc: { ar: a.descAr, en: a.descEn } };
    });
  }

  function normRows(rows) {
    return rows.map((r) => ({
      id: r.id,
      icon: r.icon,
      title: { ar: norm(r.title.ar), en: norm(r.title.en) },
      desc: { ar: norm(r.desc.ar), en: norm(r.desc.en) },
    }));
  }

  /** The list itself: which rows, in what order, with which icon, and an
   *  added row's words. A built-in row's words are strings (textChanges). */
  function structureOf(rows) {
    return rows.map((r) => (builtInById.has(r.id)
      ? { id: r.id, icon: r.icon }
      : {
          id: r.id,
          icon: r.icon,
          title: { ar: norm(r.title.ar), en: norm(r.title.en) },
          desc: { ar: norm(r.desc.ar), en: norm(r.desc.en) },
        }));
  }

  function listDirty() {
    return C.canonical(structureOf(state.rows)) !== state.savedList;
  }

  function dirty() {
    return !!state.rows && (listDirty() || Object.keys(textChanges()).length > 0);
  }

  /** Back to what is saved. With no benefit list in the catalog (see the
   *  banner) the list stays empty and only the words can be edited. */
  function resetDraft() {
    state.saved = C.parseBenefitEdits(state.data.live.benefits);
    state.rows = state.builtIn ? rowsFrom(state.saved, false) : [];
    state.savedList = C.canonical(structureOf(state.rows));
    state.texts = new Map();
    groups.forEach((g) => (g.entries || []).forEach((e) => {
      if (e.entry.editable) state.texts.set(e.key, { ar: liveText(e.key, 'ar'), en: liveText(e.key, 'en') });
    }));
  }

  function listEdits() {
    return C.benefitEditsFromRows(state.builtIn, state.rows);
  }

  function takenIds() {
    const taken = new Set(state.builtIn.items.map((b) => b.id));
    state.rows.forEach((r) => taken.add(r.id));
    return taken;
  }

  // ---- Drawing the page -------------------------------------------------------

  function render() {
    closeIconPicker();
    K.renderBanners($('banners'), state.data, state.data.catalog.benefits ? [] : [
      K.banner('danger', 'The app’s own benefit list could not be read, so the list cannot be edited here.',
        state.data.catalog.benefitsError || 'The list of strings has no benefit list in it.'),
    ]);
    const app = clear($('premiumApp'));
    const editor = h('div', { class: 'editor-col' });
    groups.forEach((g) => {
      if (g.id === 'benefits') {
        if (state.builtIn) editor.appendChild(benefitsCard());
      } else if (g.entries.length) {
        editor.appendChild(textCard(g));
      }
    });
    editor.appendChild(historyCard());
    app.appendChild(h('div', { class: 'cgrid' }, editor, previewCol()));
    updateDock();
    renderPreview();
    requestAnimationFrame(() => K.resizeAll(app));
  }

  function textCard(g) {
    const edited = g.entries.filter((e) => LANGS.some((lang) => isEdited(e.key, lang))).length;
    const card = h('details', { class: 'card', 'data-card': g.id });
    if (state.open.has(g.id)) card.setAttribute('open', '');
    card.addEventListener('toggle', () => {
      if (card.open) state.open.add(g.id);
      else state.open.delete(g.id);
      if (card.open) requestAnimationFrame(() => K.resizeAll(card));
    });
    card.appendChild(h('summary', { class: 'card-head' },
      h('h3', null, g.title),
      h('span', { class: 'sub' }, g.entries.length + (g.entries.length === 1 ? ' text' : ' texts') + (edited ? ', ' + edited + ' edited' : '')),
      h('span', { class: 'grow' }),
      K.glyph('expand_more', 'chev')));
    const body = h('div', { class: 'card-body' });
    if (g.warn) body.appendChild(h('p', { class: 'card-note warn' }, g.warn));
    else if (g.note) body.appendChild(h('p', { class: 'card-note' }, g.note));
    g.entries.forEach((e) => body.appendChild(stringRow(e)));
    card.appendChild(body);
    return card;
  }

  function stringRow({ key, label }) {
    const entry = byKey.get(key);
    const also = alsoOn(key);
    const badges = h('span', { class: 'badges' },
      LANGS.filter((lang) => isEdited(key, lang)).map((lang) => h('span', { class: 'badge edited' }, 'Edited ' + LANG_NAME[lang])),
      driftBadge([key]));
    const head = h('div', { class: 's-label' },
      h('b', null, label),
      h('code', null, key),
      also.length ? h('span', { class: 'also' }, 'Also on: ' + also.join(', ')) : null,
      badges);
    if (!entry.editable) {
      return h('div', { class: 's-row' }, head, h('div', { class: 's-fixed' },
        h('div', { class: 't-ar', lang: 'ar', dir: 'rtl' }, entry.ar.split('\n')[0]),
        h('div', { class: 't-en', lang: 'en', dir: 'ltr' }, entry.en.split('\n')[0]),
        h('div', null, entry.why)));
    }
    const t = state.texts.get(key);
    return h('div', { class: 's-row', 'data-key': key }, head,
      LANGS.map((lang) => stringField(entry, lang, t)));
  }

  function stringField(entry, lang, t) {
    const msgs = h('div', { class: 'msgs' });
    const parts = h('div', { class: 'parts' });
    const tokens = (lang === 'ar' ? entry.tokensAr : entry.tokensEn) || [];
    const ta = K.textBox(lang, t[lang], entry.key + ', ' + LANG_NAME[lang], (value) => {
      t[lang] = value;
      check();
      changed();
    });
    const useBuiltIn = h('button', {
      type: 'button',
      class: 'link-btn',
      onclick: () => {
        ta.value = entry[lang];
        ta.dispatchEvent(new Event('input'));
        ta.focus();
      },
    }, 'Use built-in text');
    function check() {
      const typed = norm(ta.value);
      const same = typed === norm(liveText(entry.key, lang));
      const result = same ? { ok: true, errors: [], warnings: [] } : R.checkStringEdit(entry, lang, ta.value);
      ta.classList.toggle('has-error', !result.ok);
      K.showMessages(msgs, result.errors, result.warnings);
      useBuiltIn.hidden = typed === norm(entry[lang]);
      clear(parts);
      if (tokens.length) {
        const used = R.partsIn(ta.value);
        parts.appendChild(h('span', null, 'The app fills in:'));
        tokens.forEach((token) => parts.appendChild(button('{' + token + '}', () => insertAtCursor(ta, '{' + token + '}'),
          'part' + (used.includes(token) ? '' : ' missing'))));
      }
    }
    check();
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, LANG_NAME[lang]), useBuiltIn), ta, parts, msgs);
  }

  function insertAtCursor(ta, text) {
    const start = ta.selectionStart;
    const end = ta.selectionEnd;
    ta.value = ta.value.slice(0, start) + text + ta.value.slice(end);
    ta.selectionStart = ta.selectionEnd = start + text.length;
    ta.focus();
    ta.dispatchEvent(new Event('input'));
  }

  // ---- The benefit list ---------------------------------------------------------

  function benefitsCard() {
    const card = h('section', { class: 'card', 'data-card': 'benefits' });
    const list = h('div', { class: 'b-list', id: 'benefitList' });
    state.rows.forEach((row, i) => list.appendChild(benefitRow(row, i)));
    const gone = state.builtIn.items.filter((b) => !state.rows.some((r) => r.id === b.id));
    const asBuiltIn = C.canonical(normRows(state.rows)) === C.canonical(normRows(rowsFrom(null, true)));
    card.appendChild(h('div', { class: 'card-head' },
      h('h3', null, 'What Premium includes'),
      h('span', { class: 'sub' }, state.rows.length + ' rows'),
      h('span', { class: 'grow' }),
      button('Back to the app’s own list', backToBuiltIn, 'btn small', {
        disabled: asBuiltIn,
        title: 'The app’s own rows, order, icons and words. Nothing changes on phones until you Save.',
      })));
    const body = h('div', { class: 'card-body' },
      h('p', { class: 'card-note warn' }, 'Every row is a promise about what the purchase unlocks, and Apple checks it (guidelines 2.3.1 and 3.1.2). Only list what Premium really does in the app today.'),
      list,
      h('div', { class: 'g-foot', style: 'padding: 10px 0 0' }, button('+ Add a benefit', addBenefit, 'btn small')));
    if (gone.length) {
      body.appendChild(h('div', { style: 'margin-top: var(--s4)' },
        h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, 'Taken off the page')),
        gone.map((b) => h('div', { class: 'removed-row' },
          h('div', { class: 't-ar', lang: 'ar', dir: 'rtl' }, liveText(b.titleKey, 'ar')),
          h('div', { class: 't-en', lang: 'en', dir: 'ltr' }, liveText(b.titleKey, 'en')),
          button('Put back', () => putBack(b.id), 'btn small')))));
    }
    card.appendChild(body);
    return card;
  }

  function benefitRow(row, i) {
    const b = builtInById.get(row.id) || null;
    const el = h('article', { class: 'b-row', 'data-item': row.id });
    const grip = h('button', { type: 'button', class: 'grip', title: 'Drag to move', 'aria-label': 'Drag to move this benefit' }, K.gripIcon());
    const iconBtn = h('button', {
      type: 'button',
      class: 'b-icon',
      title: 'Icon: ' + row.icon + '. Click to change it.',
      'aria-label': 'Change the icon, now ' + row.icon,
    }, K.glyph(row.icon));
    iconBtn.addEventListener('click', () => openIconPicker(row, iconBtn));
    const fields = h('div', { class: 'b-fields' },
      benefitField(row, 'title', 'ar', b, el), benefitField(row, 'title', 'en', b, el),
      benefitField(row, 'desc', 'ar', b, el), benefitField(row, 'desc', 'en', b, el),
      h('div', { class: 'b-meta' }, benefitBadges(row, b)));
    const n = state.rows.length;
    const tools = h('div', { class: 'b-tools' },
      button('↑', () => nudge(row, -1), 'icon-only', { disabled: i === 0, title: 'Move up', 'aria-label': 'Move up' }),
      button('↓', () => nudge(row, 1), 'icon-only', { disabled: i === n - 1, title: 'Move down', 'aria-label': 'Move down' }),
      button('✕', () => removeRow(row), 'icon-only', {
        title: b ? 'Take this row off the page' : 'Delete this row',
        'aria-label': b ? 'Take this row off the page' : 'Delete this row',
      }));
    el.appendChild(grip);
    el.appendChild(iconBtn);
    el.appendChild(fields);
    el.appendChild(tools);
    return el;
  }

  function benefitBadges(row, b) {
    const out = [];
    if (!b) out.push(h('span', { class: 'badge added' }, 'Added'));
    if (b && row.icon !== b.icon) out.push(h('span', { class: 'badge edited' }, 'Icon changed'));
    if (b) {
      const edited = [b.titleKey, b.descKey].some((key) => LANGS.some((lang) => {
        const part = key === b.titleKey ? row.title : row.desc;
        return norm(part[lang]) !== norm(builtInText(key, lang));
      }));
      if (edited) out.push(h('span', { class: 'badge edited' }, 'Your words'));
      const drift = driftBadge([b.titleKey, b.descKey]);
      if (drift) out.push(drift);
      const also = Array.from(new Set(alsoOn(b.titleKey).concat(alsoOn(b.descKey))));
      if (also.length) out.push(h('span', null, 'The title is also on: ' + also.join(', ') + '.'));
    }
    const saved = C.canonical(normRows(rowsFrom(state.saved, false)).find((r) => r.id === row.id) || null);
    if (saved !== C.canonical(normRows([row])[0])) out.push(h('span', { class: 'badge unsaved' }, 'Unsaved'));
    out.push(h('code', { class: 'key', title: 'This row’s id. Edits are kept by it.' }, row.id));
    return out;
  }

  function benefitField(row, part, lang, b, el) {
    const isTitle = part === 'title';
    const label = (isTitle ? 'Title, ' : 'Description, ') + LANG_NAME[lang];
    const max = isTitle ? C.MAX_BENEFIT_TITLE_LENGTH : C.MAX_BENEFIT_DESC_LENGTH;
    const key = b ? (isTitle ? b.titleKey : b.descKey) : null;
    const msgs = h('div', { class: 'msgs' });
    const ta = K.textBox(lang, row[part][lang], label, (value) => {
      row[part][lang] = value;
      check();
      const meta = el.querySelector('.b-meta');
      if (meta) {
        clear(meta);
        benefitBadges(row, b).forEach((x) => meta.appendChild(x));
      }
      changed();
    });
    const useBuiltIn = b ? h('button', {
      type: 'button',
      class: 'link-btn',
      onclick: () => {
        ta.value = builtInText(key, lang);
        ta.dispatchEvent(new Event('input'));
        ta.focus();
      },
    }, 'Use built-in text') : null;
    function check() {
      let result;
      if (b) {
        const same = norm(ta.value) === norm(liveText(key, lang));
        result = same ? { ok: true, errors: [], warnings: [] } : R.checkStringEdit(byKey.get(key), lang, ta.value);
        if (!same && norm(ta.value).length > max) result.errors = result.errors.concat(['Too long for a benefit row, the limit is ' + max + '.']);
      } else {
        result = C.checkField(label, lang, ta.value, max);
      }
      const warnings = (result.warnings || []).concat(C.notABenefit(label, norm(ta.value)));
      ta.classList.toggle('has-error', result.errors.length > 0);
      K.showMessages(msgs, result.errors, warnings);
      if (useBuiltIn) useBuiltIn.hidden = norm(ta.value) === norm(builtInText(key, lang));
    }
    check();
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, label), useBuiltIn), ta, msgs);
  }

  // ---- The icon picker --------------------------------------------------------

  let picker = null;

  function openIconPicker(row, anchor) {
    closeIconPicker();
    const name = h('span', { class: 'ip-name' }, row.icon);
    const grid = h('div', { class: 'icon-grid', role: 'listbox', 'aria-label': 'Icons' });
    state.builtIn.icons.forEach((icon) => {
      const pick = h('button', {
        type: 'button',
        class: icon === row.icon ? 'on' : '',
        title: icon,
        'aria-label': icon,
        role: 'option',
        'aria-selected': icon === row.icon ? 'true' : 'false',
      }, K.glyph(icon));
      pick.addEventListener('mouseenter', () => { name.textContent = icon; });
      pick.addEventListener('focus', () => { name.textContent = icon; });
      pick.addEventListener('click', () => {
        closeIconPicker();
        // By id: the list may have been redrawn from a save since the
        // picker opened, and the old row object is then not in it.
        const current = state.rows.find((r) => r.id === row.id);
        if (!current) return;
        current.icon = icon;
        const el = document.querySelector('.b-row[data-item="' + CSS.escape(current.id) + '"]');
        if (el) el.replaceWith(benefitRow(current, state.rows.indexOf(current)));
        changed();
        requestAnimationFrame(() => K.resizeAll($('benefitList')));
      });
      grid.appendChild(pick);
    });
    picker = h('div', { class: 'icon-pop', role: 'dialog', 'aria-label': 'Pick an icon' },
      h('div', { class: 'ip-head' }, h('span', null, 'The app’s icons for a benefit row'), name), grid);
    document.body.appendChild(picker);
    const r = anchor.getBoundingClientRect();
    picker.style.left = Math.max(8, Math.min(window.innerWidth - picker.offsetWidth - 8, r.left + window.scrollX)) + 'px';
    picker.style.top = r.bottom + window.scrollY + 6 + 'px';
    const on = picker.querySelector('button.on') || picker.querySelector('button');
    if (on) on.focus();
  }

  function closeIconPicker() {
    if (picker) {
      picker.remove();
      picker = null;
    }
  }

  // ---- Changing the list ----------------------------------------------------------

  function changed() {
    updateDock();
    schedulePreview();
  }

  function redrawList(focusRow) {
    closeIconPicker();
    const list = $('benefitList');
    if (!list) return render();
    const card = list.closest('.card');
    card.replaceWith(benefitsCard());
    requestAnimationFrame(() => K.resizeAll($('benefitList')));
    if (focusRow) {
      const el = document.querySelector('.b-row[data-item="' + CSS.escape(focusRow.id) + '"]');
      if (el) {
        el.classList.add('flash');
        const r = el.getBoundingClientRect();
        if (r.top < 90 || r.bottom > window.innerHeight - 90) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    }
    changed();
  }

  function indexOfRow(row) {
    return state.rows.findIndex((r) => r.id === row.id);
  }

  function moveRow(row, to) {
    const from = indexOfRow(row);
    if (from < 0) return;
    const [item] = state.rows.splice(from, 1);
    state.rows.splice(Math.max(0, Math.min(to, state.rows.length)), 0, item);
    redrawList(item);
    K.announce('Moved to place ' + (state.rows.indexOf(item) + 1) + '.');
  }

  function nudge(row, by) {
    const at = indexOfRow(row);
    if (at >= 0) moveRow(row, at + by);
  }

  function onDrop(rowEl, fromList, fromIndex, toList, toIndex) {
    const row = state.rows[fromIndex];
    if (row) moveRow(row, toIndex);
  }

  function removeRow(row) {
    const b = builtInById.get(row.id);
    if (!b) {
      const typed = ['title', 'desc'].some((p) => LANGS.some((lang) => norm(row[p][lang])));
      if (typed && !window.confirm('Delete this row? Until you Save, Discard brings it back.')) return;
    }
    const at = indexOfRow(row);
    if (at < 0) return;
    state.rows.splice(at, 1);
    redrawList();
  }

  function putBack(benefitId) {
    const b = builtInById.get(benefitId);
    const i = state.builtIn.items.indexOf(b);
    let pos = 0;
    for (let j = i - 1; j >= 0; j--) {
      const at = state.rows.findIndex((r) => r.id === state.builtIn.items[j].id);
      if (at >= 0) {
        pos = at + 1;
        break;
      }
    }
    const row = {
      id: b.id,
      icon: b.icon,
      title: { ar: liveText(b.titleKey, 'ar'), en: liveText(b.titleKey, 'en') },
      desc: { ar: liveText(b.descKey, 'ar'), en: liveText(b.descKey, 'en') },
    };
    state.rows.splice(pos, 0, row);
    redrawList(row);
  }

  function addBenefit() {
    const row = { id: C.newId(C.ADDED.benefit, takenIds()), icon: 'star', title: { ar: '', en: '' }, desc: { ar: '', en: '' } };
    // Before "Premium features to come" when that row is last: it sells
    // what comes next, so it reads last.
    const last = state.rows[state.rows.length - 1];
    const at = last && last.id === 'future' ? state.rows.length - 1 : state.rows.length;
    state.rows.splice(at, 0, row);
    redrawList(row);
    const el = document.querySelector('.b-row[data-item="' + CSS.escape(row.id) + '"]');
    const first = el && el.querySelector('textarea');
    if (first) first.focus({ preventScroll: true });
  }

  function backToBuiltIn() {
    if (!window.confirm('Put the app’s own list back on this page, with its own words and icons? Nothing changes on phones until you Save, and Discard undoes this.')) return;
    state.rows = rowsFrom(null, true);
    redrawList();
  }

  function discard() {
    if (!window.confirm('Throw away every change on this page since the last save?')) return;
    resetDraft();
    render();
  }

  // ---- The phone ------------------------------------------------------------

  function previewCol() {
    const seg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Preview language' },
      button('عربي', () => setLang('ar'), state.lang === 'ar' ? 'on' : '', { lang: 'ar' }),
      button('English', () => setLang('en'), state.lang === 'en' ? 'on' : ''));
    const reason = h('select', { 'aria-label': 'Opened from' },
      REASONS.map(([id, label]) => h('option', { value: id }, 'Opened from: ' + label)));
    reason.value = state.reason;
    reason.addEventListener('change', () => {
      state.reason = reason.value;
      renderPreview();
    });
    return h('aside', { class: 'preview-col', 'aria-label': 'Preview' },
      h('div', { class: 'preview-tools' }, seg, reason),
      h('div', { class: 'phone' }, h('div', { class: 'phone-screen', id: 'phoneScreen' })),
      h('p', { class: 'pv-note' }, 'The Premium page as phones will show it after Save, to someone without Premium. The dashed row is the one the chosen place puts first. Prices are samples.'));
  }

  function setLang(lang) {
    state.lang = lang;
    document.querySelectorAll('.preview-tools .seg button').forEach((b, i) => b.classList.toggle('on', (i === 0) === (lang === 'ar')));
    renderPreview();
  }

  function renderPreview() {
    const screen = $('phoneScreen');
    if (!screen) return;
    const lang = state.lang;
    const ar = lang === 'ar';
    const top = screen.scrollTop;
    const t = (key) => sample(norm(draftText(key, lang)) || builtInText(key, lang));
    screen.setAttribute('dir', ar ? 'rtl' : 'ltr');
    screen.setAttribute('lang', lang);
    clear(screen);
    screen.appendChild(h('div', { class: 'pv-status' }));
    screen.appendChild(h('div', { class: 'pv-bar' }, K.glyph(ar ? 'arrow_forward' : 'arrow_back'), t('premiumTitle')));
    screen.appendChild(h('div', { class: 'pv-hero' },
      h('div', { class: 'pv-crown' }, K.glyph('workspace_premium')),
      h('div', { class: 'pv-headline' }, t('premiumHeadline')),
      h('div', { class: 'pv-sub' }, t('premiumSubhead'))));
    const rows = (state.rows || []).slice();
    const lead = (REASONS.find((r) => r[0] === state.reason) || [])[2];
    const at = lead ? rows.findIndex((r) => r.id === lead) : -1;
    if (at > 0) rows.unshift(rows.splice(at, 1)[0]);
    rows.forEach((row) => {
      const known = state.builtIn.icons.includes(row.icon);
      screen.appendChild(h('div', { class: 'pv-benefit' + (lead && row.id === lead ? ' lead' : '') },
        h('div', { class: 'tile' }, K.glyph(known ? row.icon : state.builtIn.fallbackIcon)),
        h('div', null,
          h('b', null, norm(row.title[lang]) || '…'),
          h('span', null, norm(row.desc[lang]) || '…'),
          row.id === 'appearance' ? h('div', { class: 'pv-palette' }, SWATCHES.map((c) => {
            const sw = h('i');
            sw.style.background = c;
            return sw;
          })) : null)));
    });
    screen.appendChild(h('div', { class: 'pv-plan on' },
      h('div', { class: 'nm' }, t('premiumLifetime'), h('span', { class: 'bd' }, t('premiumBestValueBadge'))),
      h('div', { class: 'pr' }, h('b', null, '$29.99'), h('span', null, t('premiumOneTime')))));
    screen.appendChild(h('div', { class: 'pv-plan' },
      h('div', { class: 'nm' }, t('premiumMonthly')),
      h('div', { class: 'pr' }, h('b', null, '$4.99'), h('span', null, t('premiumPerMonth')))));
    screen.appendChild(h('div', { class: 'pv-cta' }, t('premiumCta')));
    screen.appendChild(h('div', { class: 'pv-links' }, h('span', null, t('premiumRestore')), h('span', null, '·'), h('span', null, t('premiumHaveCode'))));
    screen.appendChild(h('div', { class: 'pv-fine' }, t('premiumFinePrintLifetime')));
    screen.appendChild(h('div', { class: 'pv-legal' }, h('span', null, t('premiumTermsOfUse')), h('span', null, t('premiumPrivacyPolicy'))));
    screen.scrollTop = top;
  }

  const schedulePreview = K.debounce(renderPreview, 120);

  // ---- History ----------------------------------------------------------------

  function historyCard() {
    const pageKeys = new Set(benefitKeys);
    groups.forEach((g) => (g.entries || []).forEach((e) => pageKeys.add(e.key)));
    const rows = state.data.log.filter((r) => r.kind === 'benefits' || (r.kind === 'string' && pageKeys.has(r.key)));
    const labels = new Map();
    groups.forEach((g) => (g.entries || []).forEach((e) => labels.set(e.key, e.label)));
    state.builtIn && state.builtIn.items.forEach((b) => {
      labels.set(b.titleKey, 'Benefit title (' + b.id + ')');
      labels.set(b.descKey, 'Benefit description (' + b.id + ')');
    });
    const body = h('div', { class: 'card-body' });
    K.renderHistory(body, {
      rows,
      describe: (row) => {
        if (row.kind === 'benefits') {
          const words = state.builtIn ? C.describeBenefitsChange(state.builtIn, row.before, row.after) : '';
          return { what: 'The benefit list', detail: h('div', { class: 'detail' }, words ? words.charAt(0).toUpperCase() + words.slice(1) + '.' : 'No change phones would see.') };
        }
        const dir = row.lang === 'ar' ? 'rtl' : 'ltr';
        const said = (value) => (value === null ? (row.builtIn || '') + ' (built-in)' : value);
        return {
          what: (labels.get(row.key) || row.key) + ', ' + (LANG_NAME[row.lang] || row.lang),
          detail: h('div', { class: 'detail' },
            h('div', { class: 't-' + row.lang, lang: row.lang, dir }, h('del', null, said(row.before))),
            h('div', { class: 't-' + row.lang, lang: row.lang, dir }, said(row.after))),
        };
      },
      targetOf: (row) => (row.kind === 'benefits' ? 'benefits' : row.key + '/' + row.lang),
      onUndo: undo,
      empty: 'Nothing on this page has been saved yet.',
    });
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', null, 'History'),
        h('span', { class: 'sub' }, 'The latest saves of this page’s words and list. Every change is under ',
          h('a', { href: '/wording#history' }, 'Wording, History'), '.')),
      body);
  }

  // ---- Saving -------------------------------------------------------------------

  function updateDock() {
    const dock = $('dock');
    if (!dirty()) {
      dock.hidden = true;
      clear(dock);
      return;
    }
    clear(dock);
    dock.hidden = false;
    const texts = Object.keys(textChanges());
    const list = listDirty() && state.builtIn ? listEdits() : null;
    const problems = textProblems() + (list && !list.ok ? list.errors.length : 0);
    let said;
    if (problems) {
      said = h('div', { class: 'problems' },
        problems + (problems === 1 ? ' thing to fix' : ' things to fix') + ' before saving. ',
        button('Show me', showFirstProblem, 'link-btn'));
    } else {
      const parts = [];
      const total = texts.length;
      if (total) parts.push(total + (total === 1 ? ' text' : ' texts'));
      const listWords = list ? C.describeBenefitsChange(state.builtIn, state.data.live.benefits, list.edits) : '';
      if (listWords) parts.push('the list: ' + listWords);
      said = h('div', null, h('b', null, 'Not saved: '), parts.length ? parts.join('; ') + '.' : 'nothing phones would see.');
    }
    const notes = list && list.warnings.length
      ? h('div', { class: 'notes' }, list.warnings.length + (list.warnings.length === 1 ? ' note' : ' notes') + ' (orange). They do not block Save.')
      : null;
    dock.appendChild(h('div', { class: 'grow' }, said, notes));
    dock.appendChild(button('Discard', discard, 'btn'));
    dock.appendChild(button(state.saving ? 'Saving…' : 'Save', save, 'btn primary', { disabled: state.saving || problems > 0 }));
    dock.appendChild(h('span', { class: 'muted-note' }, h('kbd', null, '⌘'), ' ', h('kbd', null, 'S')));
  }

  function showFirstProblem() {
    const bad = document.querySelector('textarea.has-error');
    if (!bad) {
      // A problem with the list itself (too many rows, say) has no box.
      const list = listDirty() && state.builtIn ? listEdits() : null;
      if (list && !list.ok) K.toast(list.errors.join(' '));
      return;
    }
    const card = bad.closest('details');
    if (card && !card.open) card.open = true;
    requestAnimationFrame(() => {
      bad.scrollIntoView({ block: 'center', behavior: 'smooth' });
      bad.focus({ preventScroll: true });
    });
  }

  async function save() {
    if (state.saving || !dirty()) return;
    if (textProblems() || (listDirty() && !listEdits().ok)) {
      showFirstProblem();
      return;
    }
    const strings = textChanges();
    const payload = { strings, stringsBase: stringsBase(strings) };
    if (listDirty()) {
      // The list only: a built-in row's words went into strings above.
      payload.benefits = state.rows.map((r) => (builtInById.has(r.id)
        ? { id: r.id, icon: r.icon }
        : { id: r.id, icon: r.icon, title: { ar: r.title.ar, en: r.title.en }, desc: { ar: r.desc.ar, en: r.desc.en } }));
      // What this page was built from, so a stale page is refused instead
      // of hiding a row the code added or undoing another tab's save.
      payload.benefitsBase = state.data.live.benefits || null;
      payload.builtInFingerprint = C.fingerprint(state.builtIn);
    }
    state.saving = true;
    updateDock();
    K.setReadOnly($('premiumApp'), true);
    const res = await K.post('/api/wording/premium', payload);
    state.saving = false;
    K.setReadOnly($('premiumApp'), false);
    if (!res.ok) {
      updateDock();
      if (res.status === 409) K.showStale(K.errorText(res.body));
      else K.toast(K.errorText(res.body));
      return;
    }
    applyWording(res.body.wording);
    resetDraft();
    render();
    K.toast(K.savedMessage(res.body.changed ? 'Saved.' : 'Nothing changed.', state.data.phones));
  }

  async function undo(row) {
    if (state.saving) return;
    if (dirty() && !window.confirm('Undo throws away the changes on this page that are not saved yet. Go on?')) return;
    state.saving = true;
    const res = await K.post('/api/wording/undo', { id: row.id });
    state.saving = false;
    if (!res.ok) {
      K.toast(K.errorText(res.body));
      return;
    }
    applyWording(res.body.wording);
    resetDraft();
    render();
    K.toast(K.savedMessage('Undone.', state.data.phones));
  }

  function applyWording(wording) {
    if (!wording) return;
    state.data.live = wording.live;
    state.data.admin = wording.admin;
    state.data.log = wording.log;
  }

  // ---- Start ----------------------------------------------------------------------

  /** TEXT_GROUPS with each key's catalog row, missing keys dropped and
   *  "rest" filled with every other premium string. */
  function buildGroups() {
    const named = new Set(benefitKeys);
    TEXT_GROUPS.forEach((g) => {
      if (Array.isArray(g.keys)) g.keys.forEach(([key]) => named.add(key));
    });
    return TEXT_GROUPS.map((g) => {
      if (g.id === 'benefits') return g;
      const pairs = g.keys === 'rest'
        ? state.data.catalog.strings
          .filter((s) => /^premium/.test(s.key) && !named.has(s.key))
          .map((s) => [s.key, s.key])
        : g.keys;
      return Object.assign({}, g, {
        entries: pairs.filter(([key]) => byKey.has(key)).map(([key, label]) => ({ key, label, entry: byKey.get(key) })),
      });
    });
  }

  async function start() {
    K.sortable({
      lists: () => Array.from(document.querySelectorAll('#benefitList')),
      handle: '.b-row > .grip',
      row: '.b-row',
      onDrop,
    });
    document.addEventListener('keydown', (ev) => {
      if ((ev.metaKey || ev.ctrlKey) && !ev.shiftKey && !ev.altKey && String(ev.key).toLowerCase() === 's') {
        ev.preventDefault();
        save();
      } else if (ev.key === 'Escape' && picker) {
        closeIconPicker();
      }
    });
    document.addEventListener('pointerdown', (ev) => {
      if (picker && !picker.contains(ev.target) && !ev.target.closest('.b-icon')) closeIconPicker();
    });
    window.addEventListener('beforeunload', (ev) => {
      if (dirty()) {
        ev.preventDefault();
        ev.returnValue = '';
      }
    });
    window.addEventListener('resize', K.debounce(() => K.resizeAll($('premiumApp')), 150));
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => K.resizeAll($('premiumApp')));

    try {
      state.data = await K.load();
    } catch (e) {
      clear($('premiumApp')).appendChild(K.banner('danger', 'Could not load the Premium page.', e.message));
      return;
    }
    byKey = new Map(state.data.catalog.strings.map((s) => [s.key, s]));
    state.builtIn = state.data.catalog.benefits || null;
    builtInById = new Map(((state.builtIn && state.builtIn.items) || []).map((b) => [b.id, b]));
    benefitKeys = new Set();
    titleKeys = new Set();
    builtInById.forEach((b) => {
      benefitKeys.add(b.titleKey);
      benefitKeys.add(b.descKey);
      titleKeys.add(b.titleKey);
    });
    groups = buildGroups();
    groups.forEach((g) => {
      if (g.open) state.open.add(g.id);
    });
    resetDraft();
    render();
  }

  start();
})();
