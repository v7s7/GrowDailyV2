/**
 * The Messages page, in the browser.
 *
 * Served as a plain file by lib/broadcast_routes.js (broadcast_page.js says
 * why it is not inside a template). Reads everything once from
 * /api/messages, checks the message as it is typed with the same rules the
 * server applies again on send (lib/broadcast.js checkMessage; the Arabic
 * house-style reminders come from the Wording page's shared rules file),
 * draws the phone preview, and sends.
 *
 * Nothing goes to everyone without a second, explicit press on a dialog
 * that says how many phones or people it reaches. A test goes only to the
 * accounts picked under "Test on", which this browser remembers.
 */
(function () {
  'use strict';

  const TESTERS_KEY = 'gd-admin-msg-testers';
  const DRAFT_KEY = 'gd-admin-msg-draft';
  const TEXT_FIELDS = ['titleAr', 'bodyAr', 'buttonAr', 'titleEn', 'bodyEn', 'buttonEn'];
  const EM_DASH = String.fromCharCode(0x2014);
  const ARABIC_INDIC_THREE = String.fromCharCode(0x0663);
  const Rules = window.WordingRules || null;

  let ICONS = {};
  try {
    ICONS = JSON.parse(document.getElementById('msgIcons').textContent) || {};
  } catch (e) {
    ICONS = {};
  }

  // What the server says once /api/messages answers; these are only the
  // values the page shows before that.
  const config = {
    limits: {
      popup: { title: 80, body: 700, button: 24 },
      notification: { title: 60, body: 240 },
    },
    popupDays: [1, 3, 7, 14, 30],
    defaultDays: 7,
    defaultButton: { ar: 'تمام', en: 'OK' },
    maxTesters: 5,
    testPopupHours: 2,
  };

  const state = {
    kind: 'popup',
    lang: 'ar',
    data: null,
    testers: readTesters(),
    testerInfo: {},
    busy: false,
    triedSend: false,
  };

  // ---- DOM helpers (the same tiny ones the other pages use) ----------------

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

  /**
   * Appends every child given, in order. Takes any number, unlike the
   * one-child helper on the other pages: this page builds whole scenes
   * (the phone, the reach panel) in one call, and a helper that quietly
   * dropped everything after its first child drew a phone with no pop-up.
   */
  function append(el, ...children) {
    for (const child of children) {
      if (child === null || child === undefined || child === false) continue;
      if (Array.isArray(child)) {
        child.forEach((c) => append(el, c));
      } else {
        el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
      }
    }
    return el;
  }

  function $(id) {
    return document.getElementById(id);
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  /** A Lucide icon. The SVG comes from this tool's own server, never from data. */
  function ic(name) {
    const span = document.createElement('span');
    span.style.display = 'inline-flex';
    span.innerHTML = ICONS[name] || '';
    return span;
  }

  let toastTimer = null;
  function toast(message, bad) {
    const el = $('toast');
    el.textContent = message;
    el.classList.toggle('bad', Boolean(bad));
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), bad ? 7000 : 4200);
  }

  function storageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function storageSet(key, value) {
    try {
      if (value == null) localStorage.removeItem(key);
      else localStorage.setItem(key, value);
    } catch (e) {
      // Private window or blocked storage: the page still works, it just
      // forgets the test accounts and the draft on reload.
    }
  }

  // ---- Dates, always Bahrain time -------------------------------------------

  const DATE_FMT = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bahrain', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
  });
  const CLOCK_FMT = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bahrain', hour: '2-digit', minute: '2-digit', hour12: false,
  });

  function when(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? '' : DATE_FMT.format(d);
  }

  function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
  }

  // ---- The message being written ----------------------------------------------

  function normalize(text) {
    if (Rules && Rules.normalizeText) return Rules.normalizeText(text);
    return String(text == null ? '' : text).replace(/\r\n?/g, '\n').trim();
  }

  function values() {
    const out = {};
    for (const key of TEXT_FIELDS) out[key] = normalize($(key).value);
    out.days = Number($('days').value) || config.defaultDays;
    return out;
  }

  /** The message as it would be sent: the pop-up's empty buttons take the defaults. */
  function outgoing() {
    const v = values();
    const message = { titleAr: v.titleAr, bodyAr: v.bodyAr, titleEn: v.titleEn, bodyEn: v.bodyEn };
    if (state.kind === 'popup') {
      message.buttonAr = v.buttonAr || config.defaultButton.ar;
      message.buttonEn = v.buttonEn || config.defaultButton.en;
      message.days = v.days;
    }
    return message;
  }

  function styleRules() {
    const all = (Rules && Rules.ARABIC_STYLE) || [];
    if (state.kind !== 'notification') return all;
    // Notifications are where the app writes Arabic-Indic digits, so the
    // digits reminder is dropped for them (the server does the same).
    return all.filter((rule) => {
      rule.test.lastIndex = 0;
      return !rule.test.test(ARABIC_INDIC_THREE);
    });
  }

  /**
   * The same checks lib/broadcast.js runs on send. "Write an Arabic title"
   * waits until a send is tried, so an empty form is not a wall of red.
   */
  function check() {
    const v = values();
    const limits = config.limits[state.kind];
    const errors = [];
    const warnings = [];
    const bad = {};
    if (state.triedSend && !v.titleAr) {
      errors.push('Write an Arabic title.');
      bad.titleAr = true;
    }
    if (state.triedSend && !v.bodyAr) {
      errors.push('Write the Arabic message.');
      bad.bodyAr = true;
    }
    if (Boolean(v.titleEn) !== Boolean(v.bodyEn)) {
      errors.push('English needs both a title and a message, or neither (then English phones get the Arabic).');
      bad[v.titleEn ? 'bodyEn' : 'titleEn'] = true;
    }
    const fields = [
      ['titleAr', 'Arabic title', limits.title],
      ['bodyAr', 'Arabic message', limits.body],
      ['titleEn', 'English title', limits.title],
      ['bodyEn', 'English message', limits.body],
    ];
    if (state.kind === 'popup') {
      fields.push(['buttonAr', 'Arabic button', limits.button]);
      fields.push(['buttonEn', 'English button', limits.button]);
    }
    for (const [key, label, max] of fields) {
      const text = v[key];
      if (text.includes(EM_DASH)) {
        errors.push(label + ' has an em dash. Use a comma, a colon or a full stop.');
        bad[key] = true;
      }
      if (text.length > max) {
        errors.push(label + ' is too long: ' + text.length + ' characters, the limit is ' + max + '.');
        bad[key] = true;
      }
      if (state.kind === 'notification' && key.indexOf('title') === 0 && text.includes('\n')) {
        errors.push(label + ' is one line on a lock screen. Take out the line break.');
        bad[key] = true;
      }
    }
    const keys = state.kind === 'popup' ? ['titleAr', 'bodyAr', 'buttonAr'] : ['titleAr', 'bodyAr'];
    for (const key of keys) {
      const text = v[key];
      if (!text) continue;
      for (const rule of styleRules()) {
        rule.test.lastIndex = 0;
        if (rule.test.test(text) && !warnings.includes(rule.say)) warnings.push(rule.say);
      }
    }
    const complete = Boolean(v.titleAr && v.bodyAr);
    return { errors, warnings, bad, complete };
  }

  // ---- Drawing ----------------------------------------------------------------

  function renderKind() {
    document.querySelectorAll('.kind-card').forEach((card) => {
      card.setAttribute('aria-checked', card.dataset.kind === state.kind ? 'true' : 'false');
      card.tabIndex = card.dataset.kind === state.kind ? 0 : -1;
    });
    document.querySelectorAll('.popup-only').forEach((el) => {
      el.hidden = state.kind !== 'popup';
    });
    $('sendAll').lastElementChild.textContent = state.kind === 'popup' ? 'Show to everyone' : 'Send to everyone';
  }

  function renderCounts(result) {
    const limits = config.limits[state.kind];
    const v = values();
    document.querySelectorAll('[data-count]').forEach((el) => {
      const key = el.dataset.count;
      const kindKey = key.startsWith('title') ? 'title' : key.startsWith('body') ? 'body' : 'button';
      const max = limits[kindKey];
      if (!max) {
        el.textContent = '';
        return;
      }
      const n = v[key].length;
      el.textContent = n + ' / ' + max;
      el.classList.toggle('over', n > max);
    });
    document.querySelectorAll('.field[data-field]').forEach((field) => {
      field.classList.toggle('bad', Boolean(result.bad[field.dataset.field]));
    });
  }

  function renderChecks(result) {
    const box = clear($('checks'));
    result.errors.forEach((e) => append(box, h('div', { class: 'err' }, e)));
    result.warnings.forEach((w) => append(box, h('div', { class: 'wrn' }, w)));
  }

  /** Which language the preview shows, and whether that is the fallback. */
  function previewText() {
    const v = values();
    const wantEn = state.lang === 'en';
    const hasEn = Boolean(v.titleEn || v.bodyEn);
    const en = wantEn && hasEn;
    return {
      rtl: !en,
      fallback: wantEn && !hasEn,
      title: en ? v.titleEn : v.titleAr,
      body: en ? v.bodyEn : v.bodyAr,
      button: en
        ? v.buttonEn || config.defaultButton.en
        : v.buttonAr || config.defaultButton.ar,
    };
  }

  function renderPreview() {
    const screen = clear($('phoneScreen'));
    const t = previewText();
    const dir = t.rtl ? 'ph-rtl' : '';
    const title = t.title
      ? h('div', { class: 'ph-title ' + dir }, t.title)
      : h('div', { class: 'ph-title ph-empty ' + dir }, t.rtl ? 'العنوان' : 'Title');
    const body = t.body
      ? h('div', { class: 'ph-body ' + dir }, t.body)
      : h('div', { class: 'ph-body ph-empty ' + dir }, t.rtl ? 'نص الرسالة' : 'Your message');

    append(screen, h('div', { class: 'notch' }));
    if (state.kind === 'popup') {
      const board = h('div', { class: 'ph-app' });
      for (let i = 0; i < 49; i++) {
        const lit = (i * 7 + 3) % 5;
        board.appendChild(h('i', { class: lit === 0 ? 'g2' : lit < 3 ? 'g' : '' }));
      }
      append(screen, board, h('div', { class: 'ph-scrim' }), h('div', { class: 'ph-dialog' },
        h('div', { class: 'ph-ic' }, ic('megaphone')),
        title,
        body,
        h('div', { class: 'ph-btn ' + dir }, t.button),
      ));
      $('previewNote').textContent = t.fallback
        ? 'No English written, so English phones show the Arabic.'
        : 'Shows once, over whatever screen the app opens on.';
    } else {
      const now = new Date();
      append(screen,
        h('div', { class: 'ph-lock' }),
        h('div', { class: 'ph-date' }, new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Bahrain', weekday: 'long', day: 'numeric', month: 'long' }).format(now)),
        h('div', { class: 'ph-time' }, CLOCK_FMT.format(now)),
        h('div', { class: 'ph-note' },
          h('div', { class: 'ph-note-top' },
            h('span', { class: 'ph-appicon' }, h('i'), h('i'), h('i'), h('i')),
            h('span', { class: 'ph-appname' }, 'Grow Daily'),
            h('span', null, 'now'),
          ),
          title,
          body,
        ),
      );
      $('previewNote').textContent = t.fallback
        ? 'No English written, so English phones get the Arabic.'
        : 'A lock screen shows about four lines; the rest opens with a long press.';
    }
  }

  function fact(iconName, parts, cls) {
    return h('li', { class: cls || null }, ic(iconName), h('span', null, parts));
  }

  function renderReach() {
    const box = clear($('reach'));
    const data = state.data;
    if (!data) {
      append(box, h('div', { class: 'loading' }, 'Counting phones…'));
      return;
    }
    const r = data.reach || {};
    if (state.kind === 'notification') {
      const accounts = Math.max(0, (r.withPhone || 0) - (r.quiet || 0) - (r.off || 0));
      const facts = h('ul', { class: 'facts' });
      append(facts, fact('smartphone', [h('b', null, r.ar || 0), ' in Arabic, ', h('b', null, r.en || 0), ' in English, by each phone’s app language']));
      if (r.quiet) {
        append(facts, fact('moon-star', [h('b', null, plural(r.quiet, 'person is', 'people are')), ' in their quiet hours now (', CLOCK_FMT.format(new Date()), ' in Bahrain). They get it when their quiet hours end.']));
      }
      append(facts, fact('clock', [h('b', null, 'One to everyone per 24 hours, '), 'so nobody gets two in a day. A test can go any time.']));
      if (r.off) {
        append(facts, fact('bell', [h('b', null, r.off), ' turned notifications off in the app and will be skipped.']));
      }
      append(facts, fact('info', [h('b', null, r.noPhone || 0), ' of ', r.accounts || 0, ' accounts have no phone registered: guests, older app versions, or notifications never allowed. The pop-up reaches them when they open the app.']));
      // App Store Review Guideline 4.5.4: a push may only promote or market
      // to people who opted in through consent wording in the app, with a
      // way to opt out. The app has no such opt-in, so a sale or an offer
      // belongs in the pop-up, which no rule restricts this way.
      append(facts, fact('triangle-alert', [h('b', null, 'Not for sales or offers. '), 'Apple (rule 4.5.4) allows promotional notifications only to people who opted in to them in the app, and the app has no such opt-in. Announce a sale with a pop-up instead.'], 'warn'));
      append(box,
        h('div', { class: 'big' }, h('b', null, r.phones || 0), h('span', null, (r.phones === 1 ? 'phone' : 'phones') + ' on ' + plural(accounts, 'account', 'accounts'))),
        facts,
      );
    } else {
      const days = values().days;
      const facts = h('ul', { class: 'facts' });
      append(facts, fact('clock', ['Once each, for ', h('b', null, plural(days, 'day', 'days')), ' from when you send it.']));
      if (data.phones === 'open') {
        append(facts, fact('app-window', ['Phones can read pop-ups: ', h('b', null, 'yes'), '.']));
      } else if (data.phones === 'closed') {
        append(facts, fact('triangle-alert', ['Phones cannot read pop-ups yet: the Firestore rule is not deployed. Run ', h('code', null, 'firebase deploy --only firestore:rules'), ' from the project folder.'], 'warn'));
      } else {
        append(facts, fact('info', ['Could not check whether phones can read pop-ups (offline?).']));
      }
      append(facts, fact('info', ['Only app versions newer than build 77 look for pop-ups. Older versions show nothing.']));
      append(box,
        h('div', { class: 'big' }, h('b', null, 'Everyone'), h('span', null, 'who opens the app, ' + plural(r.accounts || 0, 'account', 'accounts') + ' today')),
        facts,
      );
    }
  }

  function renderBanners() {
    const box = clear($('banners'));
    const data = state.data;
    if (data && data.phones === 'closed') {
      append(box, h('div', { class: 'banner warn-b' }, ic('triangle-alert'), h('div', null,
        h('b', null, 'Pop-ups are not live yet. '),
        'Phones are not allowed to read them until the new Firestore rule is deployed: ',
        h('code', null, 'firebase deploy --only firestore:rules'),
        '. Notifications work already.')));
    }
  }

  function liveCard(p, slot) {
    const stop = h('button', {
      type: 'button',
      class: 'btn danger',
      onclick: () => confirmStop(slot, p),
    }, ic('circle-stop'), h('span', null, slot === 'test' ? 'Stop test' : 'Stop showing'));
    return h('div', { class: 'msg-card' },
      h('div', { class: 'live-top' },
        h('span', { class: 'tag ' + slot }, slot === 'test' ? 'Test' : 'Everyone'),
        slot === 'test' ? h('span', { class: 'when' }, plural(p.testers, 'account', 'accounts')) : null,
        h('span', { class: 'when' }, 'since ' + when(p.startsAt) + ', until ' + when(p.endsAt)),
        stop,
      ),
      h('div', { class: 'live-title' }, p.titleAr),
      h('div', { class: 'live-body' }, p.bodyAr),
    );
  }

  function renderLive() {
    const box = clear($('liveNow'));
    const live = state.data && state.data.live;
    if (!live) return;
    const cards = [];
    if (live.everyone && live.everyone.active) cards.push(liveCard(live.everyone, 'everyone'));
    if (live.test && live.test.active) cards.push(liveCard(live.test, 'test'));
    if (cards.length === 0) {
      const last = live.everyone;
      append(box, h('p', { class: 'none' }, last
        ? 'No pop-up is showing. The last one ended ' + when(last.endsAt) + '.'
        : 'No pop-up is showing.'));
      return;
    }
    append(box, cards);
  }

  function resultLine(row) {
    if (row.kind === 'popup') {
      if (row.stoppedAt) return h('span', null, 'stopped ' + when(row.stoppedAt));
      const ended = row.endsAt && new Date(row.endsAt).getTime() <= Date.now();
      return h('span', null, (ended ? 'ended ' : 'until ') + when(row.endsAt));
    }
    if (row.sending) {
      // Written before the first message and never finished: the tool was
      // stopped, or the network went, part way through.
      return h('span', { class: 'bad' }, 'started, never finished');
    }
    const r = row.result || {};
    const c = row.counts || {};
    const parts = [h('span', null, plural(r.sent || 0, 'phone', 'phones'))];
    if (r.gone) parts.push(' · ', h('span', { class: 'bad' }, r.gone + ' gone'));
    if (r.failed) parts.push(' · ', h('span', { class: 'bad' }, r.failed + ' failed'));
    const held = row.held;
    if (held && held.error) {
      parts.push(' · ', h('span', { class: 'bad' }, held.people + ' in quiet hours skipped'));
    } else if (held) {
      parts.push(' · ', h('span', null, held.sent + ' of ' + held.people + ' after quiet hours'));
    } else if (c.quiet) {
      parts.push(' · ', h('span', null, c.quiet + ' quiet'));
    }
    return h('span', null, parts);
  }

  function renderHistory() {
    const box = clear($('history'));
    const rows = (state.data && state.data.history) || [];
    if (rows.length === 0) {
      append(box, h('p', { class: 'none' }, 'Nothing sent yet.'));
      return;
    }
    const list = h('div', { class: 'hist' });
    for (const row of rows) {
      append(list, h('div', { class: 'hist-row' },
        h('span', { class: 'k', title: row.kind === 'popup' ? 'Pop-up' : 'Notification' }, ic(row.kind === 'popup' ? 'app-window' : 'bell')),
        h('div', { class: 't' },
          h('div', { class: 'ttl', title: row.bodyAr }, row.titleAr || '(no title)'),
          h('div', { class: 'meta' },
            h('span', { class: 'tag ' + row.audience }, row.audience === 'test' ? 'Test' : 'Everyone'),
            h('span', null, row.kind === 'popup' ? 'Pop-up' : 'Notification'),
            h('span', null, when(row.at)),
          ),
        ),
        h('div', { class: 'r' }, resultLine(row)),
      ));
    }
    append(box, list);
  }

  function renderTesters() {
    const box = clear($('testerChips'));
    if (state.testers.length === 0) {
      append(box, h('span', { class: 'none' }, 'No test account yet. Add yours.'));
    }
    for (const t of state.testers) {
      const info = state.testerInfo[t.uid];
      let phones = null;
      if (info) {
        phones = info.phones
          ? h('span', { class: 'ph' }, plural(info.phones, 'phone', 'phones'))
          : h('span', { class: 'ph none', title: 'A notification cannot reach this account: no phone has registered for it. The pop-up still works.' }, 'no phone');
      }
      append(box, h('span', { class: 'tester-chip' },
        h('span', { class: 'nm', title: t.email || t.uid }, t.name || t.email || t.uid),
        phones,
        h('button', { type: 'button', 'aria-label': 'Remove ' + (t.name || t.email || t.uid), onclick: () => removeTester(t.uid) }, ic('x')),
      ));
    }
    $('testerSearch').disabled = state.testers.length >= config.maxTesters;
  }

  function updateActions(result) {
    const r = result || check();
    const blocked = state.busy || r.errors.length > 0;
    $('sendTest').disabled = blocked || state.testers.length === 0;
    $('sendAll').disabled = blocked || !state.data;
    let why = '';
    if (state.busy) why = 'Sending…';
    else if (state.testers.length === 0) why = 'Add a test account to send a test.';
    else if (state.kind === 'notification' && state.testers.every((t) => state.testerInfo[t.uid] && !state.testerInfo[t.uid].phones)) {
      why = 'No test account has a phone for notifications.';
    }
    $('actionsWhy').textContent = why;
  }

  function renderAll() {
    const result = check();
    renderKind();
    renderCounts(result);
    renderChecks(result);
    renderPreview();
    renderReach();
    renderBanners();
    renderLive();
    renderHistory();
    renderTesters();
    updateActions(result);
  }

  /** What changes as the message is typed. The rest waits for the server. */
  function onEdit() {
    const result = check();
    renderCounts(result);
    renderChecks(result);
    renderPreview();
    if (state.kind === 'popup') renderReach();
    updateActions(result);
    saveDraft();
  }

  // ---- Draft and test accounts, remembered by this browser -------------------

  function saveDraft() {
    const draft = { kind: state.kind, days: $('days').value };
    for (const key of TEXT_FIELDS) draft[key] = $(key).value;
    storageSet(DRAFT_KEY, JSON.stringify(draft));
  }

  function restoreDraft() {
    let draft = null;
    try {
      draft = JSON.parse(storageGet(DRAFT_KEY) || 'null');
    } catch (e) {
      draft = null;
    }
    if (!draft || typeof draft !== 'object') return;
    if (draft.kind === 'popup' || draft.kind === 'notification') state.kind = draft.kind;
    for (const key of TEXT_FIELDS) {
      if (typeof draft[key] === 'string') $(key).value = draft[key];
    }
    if (draft.days) $('days').value = String(draft.days);
  }

  function clearDraft() {
    for (const key of TEXT_FIELDS) $(key).value = '';
    state.triedSend = false;
    storageSet(DRAFT_KEY, null);
  }

  function readTesters() {
    try {
      const list = JSON.parse(storageGet(TESTERS_KEY) || '[]');
      return Array.isArray(list)
        ? list.filter((t) => t && typeof t.uid === 'string').slice(0, 5)
        : [];
    } catch (e) {
      return [];
    }
  }

  function saveTesters() {
    storageSet(TESTERS_KEY, JSON.stringify(state.testers));
  }

  async function refreshTesterInfo() {
    if (state.testers.length === 0) {
      state.testerInfo = {};
      renderTesters();
      updateActions();
      return;
    }
    try {
      const res = await fetch('/api/messages/testers?uids=' + encodeURIComponent(state.testers.map((t) => t.uid).join(',')));
      const json = await res.json();
      const info = {};
      (json.testers || []).forEach((t) => {
        info[t.uid] = t;
      });
      state.testerInfo = info;
    } catch (e) {
      // Offline: the chips simply show no phone count.
    }
    renderTesters();
    updateActions();
  }

  function addTester(account) {
    if (state.testers.some((t) => t.uid === account.uid)) return;
    if (state.testers.length >= config.maxTesters) return;
    state.testers.push({ uid: account.uid, name: account.displayName || '', email: account.email || '' });
    saveTesters();
    renderTesters();
    refreshTesterInfo();
  }

  function removeTester(uid) {
    state.testers = state.testers.filter((t) => t.uid !== uid);
    saveTesters();
    renderTesters();
    refreshTesterInfo();
  }

  // ---- The account finder under "Test on" --------------------------------------

  let searchTimer = null;
  let searchSeq = 0;
  let results = [];
  let selected = -1;

  function renderResults() {
    const box = clear($('testerResults'));
    if (results.length === 0) {
      append(box, h('div', { class: 'dd-empty' }, 'No account matches.'));
    }
    results.forEach((a, i) => {
      append(box, h('button', {
        type: 'button',
        class: 'dd-item' + (i === selected ? ' sel' : ''),
        onmousedown: (e) => {
          e.preventDefault();
          pick(i);
        },
      }, h('span', { class: 'nm' }, a.displayName || a.email || a.uid), h('span', { class: 'ml' }, (a.email || '') + '  ' + a.uid)));
    });
    box.hidden = false;
  }

  function pick(i) {
    const account = results[i];
    if (!account) return;
    addTester(account);
    $('testerSearch').value = '';
    $('testerResults').hidden = true;
    results = [];
    selected = -1;
  }

  async function search(q) {
    const seq = ++searchSeq;
    try {
      const res = await fetch('/api/search?q=' + encodeURIComponent(q));
      const json = await res.json();
      if (seq !== searchSeq) return;
      const chosen = new Set(state.testers.map((t) => t.uid));
      results = (json.results || []).filter((a) => !chosen.has(a.uid)).slice(0, 8);
      selected = results.length ? 0 : -1;
      renderResults();
    } catch (e) {
      if (seq === searchSeq) $('testerResults').hidden = true;
    }
  }

  function wireSearch() {
    const input = $('testerSearch');
    input.addEventListener('input', () => {
      clearTimeout(searchTimer);
      const q = input.value.trim();
      if (!q) {
        $('testerResults').hidden = true;
        return;
      }
      searchTimer = setTimeout(() => search(q), 160);
    });
    input.addEventListener('keydown', (e) => {
      const box = $('testerResults');
      if (box.hidden) return;
      if (e.key === 'ArrowDown') {
        selected = Math.min(results.length - 1, selected + 1);
        renderResults();
        e.preventDefault();
      } else if (e.key === 'ArrowUp') {
        selected = Math.max(0, selected - 1);
        renderResults();
        e.preventDefault();
      } else if (e.key === 'Enter') {
        if (selected >= 0) pick(selected);
        e.preventDefault();
      } else if (e.key === 'Escape') {
        box.hidden = true;
      }
    });
    input.addEventListener('blur', () => {
      setTimeout(() => {
        $('testerResults').hidden = true;
      }, 120);
    });
  }

  // ---- Server --------------------------------------------------------------------

  async function api(url, body) {
    const res = await fetch(url, {
      method: body ? 'POST' : 'GET',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = null;
    try {
      json = await res.json();
    } catch (e) {
      json = null;
    }
    if (!res.ok || !json || json.ok === false) {
      throw new Error((json && json.error) || 'The server answered ' + res.status + '.');
    }
    return json;
  }

  function applyConfig(data) {
    if (data.limits) config.limits = data.limits;
    if (Array.isArray(data.popupDays)) config.popupDays = data.popupDays;
    if (data.defaultDays) config.defaultDays = data.defaultDays;
    if (data.defaultButton) config.defaultButton = data.defaultButton;
    if (data.maxTesters) config.maxTesters = data.maxTesters;
    if (data.testPopupHours) config.testPopupHours = data.testPopupHours;
  }

  function fillDays() {
    const select = $('days');
    const current = select.value;
    clear(select);
    for (const d of config.popupDays) {
      append(select, h('option', { value: String(d) }, plural(d, 'day', 'days')));
    }
    select.value = current && config.popupDays.includes(Number(current)) ? current : String(config.defaultDays);
  }

  function fillPlaceholders() {
    $('buttonAr').placeholder = config.defaultButton.ar;
    $('buttonEn').placeholder = config.defaultButton.en;
  }

  async function load(fresh) {
    try {
      const data = await api('/api/messages' + (fresh ? '?fresh=1' : ''));
      applyConfig(data);
      state.data = data;
      fillDays();
      fillPlaceholders();
      renderAll();
    } catch (e) {
      clear($('banners'));
      append($('banners'), h('div', { class: 'banner danger' }, ic('triangle-alert'), h('div', null, 'Could not load messages: ' + e.message)));
    }
  }

  function mergeStored(json) {
    if (!state.data) return;
    if (json.live) state.data.live = json.live;
    if (json.history) state.data.history = json.history;
  }

  // ---- Sending --------------------------------------------------------------------

  function setBusy(busy) {
    state.busy = busy;
    updateActions();
  }

  function describeSend(json, audience, kind) {
    const stale = json.reloadFailed
      ? ' (done: this page could not refresh itself, reload it)'
      : '';
    if (kind === 'popup') {
      return (audience === 'test'
        ? 'Test pop-up is up for the next ' +
          plural(config.testPopupHours, 'hour', 'hours') +
          '. Open the app on your phone, or leave it and come back, to see it.'
        : 'The pop-up is up for everyone until ' + when(json.endsAt) + '.') + stale;
    }
    const parts = ['Sent to ' + plural(json.sent || 0, 'phone', 'phones') + '.'];
    if (json.gone) parts.push(plural(json.gone, 'phone no longer has', 'phones no longer have') + ' the app.');
    if (json.failed) parts.push(json.failed + ' failed: ' + Object.keys(json.errors || {}).join(', ') + '.');
    const held = json.held;
    if (audience === 'everyone' && held && held.error) {
      parts.push(plural(held.people, 'person', 'people') + ' in quiet hours could not be held (' +
        held.error + '), so they were skipped. Deploy holdBroadcast and deliverHeldBroadcast.');
    } else if (audience === 'everyone' && held) {
      parts.push(plural(held.queued, 'person', 'people') + ' in quiet hours get it when theirs end.');
    }
    return parts.join(' ') + stale;
  }

  /**
   * Sends to [audience]. A send to everyone passes the [snapshot] its
   * confirm dialog showed, so what goes out is exactly what was confirmed,
   * never whatever the fields hold by the time the button is pressed.
   */
  async function send(audience, snapshot) {
    state.triedSend = true;
    const result = check();
    renderCounts(result);
    renderChecks(result);
    if (!snapshot && (result.errors.length || !result.complete)) {
      updateActions(result);
      toast('Fix the message first.', true);
      return false;
    }
    const kind = snapshot ? snapshot.kind : state.kind;
    const message = snapshot ? snapshot.message : outgoing();
    setBusy(true);
    try {
      const url = kind === 'popup' ? '/api/messages/popup' : '/api/messages/notification';
      const json = await api(url, {
        audience,
        message,
        testers: audience === 'test' ? state.testers.map((t) => t.uid) : undefined,
      });
      mergeStored(json);
      toast(describeSend(json, audience, kind));
      if (audience === 'everyone') clearDraft();
      return true;
    } catch (e) {
      toast(e.message, true);
      return false;
    } finally {
      setBusy(false);
      renderAll();
    }
  }

  // ---- The confirm dialog ------------------------------------------------------------

  let confirmAction = null;
  let lastFocus = null;

  function openConfirm({ title, body, go, danger, action }) {
    lastFocus = document.activeElement;
    $('confirmTitle').textContent = title;
    append(clear($('confirmBody')), body);
    const goBtn = $('confirmGo');
    goBtn.textContent = go;
    goBtn.className = 'btn ' + (danger ? 'danger' : 'primary');
    confirmAction = action;
    // Everything behind the dialog stops taking clicks, keys and focus, so
    // nothing can change underneath what is being confirmed.
    document.querySelector('.app').inert = true;
    $('confirmScrim').hidden = false;
    $('confirmCancel').focus();
  }

  function closeConfirm() {
    $('confirmScrim').hidden = true;
    document.querySelector('.app').inert = false;
    confirmAction = null;
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function quote(message) {
    return h('div', { class: 'quote' },
      h('div', { class: 'live-title' }, message.titleAr),
      h('div', { class: 'live-body' }, message.bodyAr),
    );
  }

  async function confirmEveryone() {
    state.triedSend = true;
    const result = check();
    renderCounts(result);
    renderChecks(result);
    updateActions(result);
    if (result.errors.length || !result.complete) {
      toast('Fix the message first.', true);
      return;
    }
    let data = state.data || {};
    const snapshot = { kind: state.kind, message: outgoing() };
    if (state.kind === 'popup') {
      const days = snapshot.message.days;
      const live = data.live && data.live.everyone;
      const body = [
        h('p', null, 'Everyone who opens the app in the next ' + plural(days, 'day', 'days') + ' sees it once.' +
          (live && live.active ? ' It replaces the pop-up showing now («' + live.titleAr + '»).' : '')),
        quote(snapshot.message),
      ];
      if (data.phones !== 'open') {
        body.push(h('p', null, h('b', null, 'Phones cannot read pop-ups yet. '), 'It will wait in place until the Firestore rule is deployed.'));
      }
      openConfirm({
        title: 'Show this pop-up to everyone?',
        body,
        go: 'Show to everyone',
        action: () => send('everyone', snapshot),
      });
    } else {
      // Counted again now: quiet hours move with the clock, and this page
      // may have been open for hours.
      setBusy(true);
      try {
        const counted = await api('/api/messages?fresh=1');
        applyConfig(counted);
        state.data = counted;
        renderReach();
      } catch (e) {
        toast('Could not count the phones just now: ' + e.message, true);
        setBusy(false);
        return;
      }
      setBusy(false);
      const r = (state.data && state.data.reach) || {};
      const skipped = [];
      if (r.off) skipped.push(r.off + ' with notifications off');
      const body = [
        h('p', null, 'It goes to about ' + plural(r.phones || 0, 'phone', 'phones') + ' now, and a notification cannot be taken back.' +
          (r.quiet ? ' ' + plural(r.quiet, 'person', 'people') + ' in quiet hours get it when theirs end.' : '') +
          (skipped.length ? ' Skipped: ' + skipped.join(', ') + '.' : '') +
          ' The next one to everyone can go in 24 hours.'),
        quote(snapshot.message),
      ];
      data = state.data || {};
      openConfirm({
        title: 'Send this notification to everyone?',
        body,
        go: 'Send now',
        action: () => send('everyone', snapshot),
      });
    }
  }

  function confirmStop(slot, p) {
    openConfirm({
      title: slot === 'test' ? 'Stop the test pop-up?' : 'Stop showing this pop-up?',
      body: [
        h('p', null, 'Anyone who has not opened the app yet will not see it. People who already saw it are not affected.'),
        h('div', { class: 'quote' }, h('div', { class: 'live-title' }, p.titleAr), h('div', { class: 'live-body' }, p.bodyAr)),
      ],
      go: 'Stop it',
      danger: true,
      action: async () => {
        setBusy(true);
        try {
          const json = await api('/api/messages/popup/stop', { slot });
          mergeStored(json);
          toast('Stopped.');
        } catch (e) {
          toast(e.message, true);
        } finally {
          setBusy(false);
          renderAll();
        }
      },
    });
  }

  // ---- Wiring ------------------------------------------------------------------------

  function setKind(kind) {
    if (kind === state.kind) return;
    state.kind = kind;
    renderAll();
    saveDraft();
  }

  function wire() {
    document.querySelectorAll('.kind-card').forEach((card) => {
      card.addEventListener('click', () => setKind(card.dataset.kind));
      card.addEventListener('keydown', (e) => {
        if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) {
          const next = state.kind === 'popup' ? 'notification' : 'popup';
          setKind(next);
          const target = document.querySelector('.kind-card[data-kind="' + next + '"]');
          if (target) target.focus();
          e.preventDefault();
        }
      });
    });
    document.querySelectorAll('.seg button').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.lang = btn.dataset.lang;
        document.querySelectorAll('.seg button').forEach((b) => b.setAttribute('aria-pressed', b === btn ? 'true' : 'false'));
        renderPreview();
      });
    });
    for (const key of TEXT_FIELDS) $(key).addEventListener('input', onEdit);
    $('days').addEventListener('change', onEdit);
    $('sendTest').addEventListener('click', () => send('test'));
    $('sendAll').addEventListener('click', confirmEveryone);
    $('confirmCancel').addEventListener('click', closeConfirm);
    $('confirmGo').addEventListener('click', async () => {
      const action = confirmAction;
      closeConfirm();
      if (action) await action();
    });
    $('confirmScrim').addEventListener('click', (e) => {
      if (e.target === $('confirmScrim')) closeConfirm();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !$('confirmScrim').hidden) closeConfirm();
    });
    wireSearch();
  }

  fillDays();
  fillPlaceholders();
  restoreDraft();
  wire();
  renderAll();
  refreshTesterInfo();
  load(false);
})();
