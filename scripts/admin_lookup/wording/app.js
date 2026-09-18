/**
 * The Wording page, in the browser.
 *
 * Served as a plain file by server.js (lib/wording_page.js says why it is
 * not inside a template). It reads everything once from /api/wording, lets
 * you edit, and posts each save; every save answers with the fresh state of
 * the document, so the page never shows anything the phones are not seeing.
 *
 * The checks that decide whether a save may go through are
 * window.WordingRules (rules.js), the same code the server runs.
 */
(function () {
  'use strict';

  const R = window.WordingRules;
  const LANGS = ['ar', 'en'];
  const LANG_NAME = { ar: 'Arabic', en: 'English' };
  const PAGE_SIZE = 80;
  const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const state = {
    data: null,
    byKey: new Map(),
    index: [],
    tab: 'lines',
    // Daily lines being edited, or null when the page shows what is saved.
    draft: null,
    query: '',
    filter: 'all',
    // The string whose editor is open, and the text in its two boxes.
    open: null,
    edit: null,
    limit: PAGE_SIZE,
    saving: false,
  };

  // ---- DOM ----------------------------------------------------------------

  /** An element. Text children are always text nodes, never parsed as HTML. */
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

  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) {
      child.forEach((c) => append(el, c));
    } else {
      el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
  }

  function $(id) {
    return document.getElementById(id);
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  function button(label, onClick, cls, extra) {
    return h('button', Object.assign({ type: 'button', class: cls || 'btn', onclick: onClick }, extra || {}), label);
  }

  /** A textarea as tall as its text, so no line of a sentence hides.
   *  A box on a hidden tab has no height to measure; it is sized when its
   *  tab opens (resizeAll), not squashed to nothing now. */
  function autosize(ta) {
    if (!ta.offsetParent) return;
    ta.style.height = 'auto';
    // Borders (2px) plus one for Arabic's fractional line height, which
    // scrollHeight rounds down: without it a sliver of overflow puts a
    // scrollbar on a box that is showing all of its text.
    ta.style.height = ta.scrollHeight + 3 + 'px';
    ta.style.overflowY = 'hidden';
  }

  /** Every box on the open tab, again: after the Arabic face loads (it is
   *  taller than the fallback the first sizing measured), on resize, and
   *  when a tab is opened. */
  function resizeAll() {
    document.querySelectorAll('.view.active textarea').forEach(autosize);
  }

  function textBox(lang, value, label) {
    const ta = h('textarea', {
      class: 't-' + lang,
      lang,
      dir: lang === 'ar' ? 'rtl' : 'ltr',
      rows: 1,
      spellcheck: lang === 'en' ? 'true' : 'false',
      'aria-label': label,
    });
    ta.value = value;
    requestAnimationFrame(() => autosize(ta));
    return ta;
  }

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3200);
  }

  function debounce(fn, ms) {
    let t = null;
    return function () {
      clearTimeout(t);
      t = setTimeout(fn, ms);
    };
  }

  function fmtDate(dateKey) {
    const d = new Date(dateKey + 'T00:00:00Z');
    return DAY_NAMES[d.getUTCDay()] + ' ' + d.getUTCDate() + ' ' + MONTH_NAMES[d.getUTCMonth()];
  }

  function fmtTime(iso) {
    if (!iso) return 'just now';
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, '0');
    return d.getDate() + ' ' + MONTH_NAMES[d.getMonth()] + ' ' + d.getFullYear() +
      ', ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  // ---- Server -------------------------------------------------------------

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

  /** Takes a save's answer: the document as it now is. */
  function applyWording(wording) {
    if (!wording) return;
    state.data.live = wording.live;
    state.data.admin = wording.admin;
    state.data.log = wording.log;
    reindex();
  }

  function errorText(body) {
    if (!body) return 'The save did not go through.';
    if (body.error) return body.error;
    if (Array.isArray(body.errors)) return body.errors.join(' ');
    if (body.errors && typeof body.errors === 'object') {
      return Object.keys(body.errors).map((lang) => LANG_NAME[lang] + ': ' + body.errors[lang].join(' ')).join(' ');
    }
    return 'The save did not go through.';
  }

  // ---- What is edited -----------------------------------------------------

  function builtIn(entry, lang) {
    return lang === 'ar' ? entry.ar : entry.en;
  }

  function isEdited(entry, lang) {
    return Object.prototype.hasOwnProperty.call(state.data.live.strings[lang], entry.key);
  }

  function liveText(entry, lang) {
    return isEdited(entry, lang) ? state.data.live.strings[lang][entry.key] : builtIn(entry, lang);
  }

  /** Edited, and the app's own text has changed since the edit was made. */
  function drifted(entry, lang) {
    if (!isEdited(entry, lang)) return false;
    const base = state.data.admin.bases[lang][entry.key];
    return typeof base === 'string' && base !== builtIn(entry, lang);
  }

  function anyEdited(entry) {
    return isEdited(entry, 'ar') || isEdited(entry, 'en');
  }

  function anyDrift(entry) {
    return drifted(entry, 'ar') || drifted(entry, 'en');
  }

  function reindex() {
    state.index = state.data.catalog.strings.map((entry) => ({
      entry,
      hay: R.searchKey([
        entry.key,
        entry.section,
        (entry.screens || []).join(' '),
        entry.ar,
        entry.en,
        liveText(entry, 'ar'),
        liveText(entry, 'en'),
      ].join('\n')),
    }));
  }

  // ---- Banners and counts -------------------------------------------------

  function renderBanners() {
    const box = clear($('banners'));
    const d = state.data;
    if (d.phones === 'closed') {
      box.appendChild(h('div', { class: 'banner danger' },
        h('div', { class: 'grow' },
          h('b', null, 'Phones cannot read these edits yet. '),
          'The database rule that lets them read has not been deployed. It is a one-time step, from the repo folder: ',
          h('code', null, 'firebase deploy --only firestore:rules'))));
    }
    if (d.catalogNote) {
      box.appendChild(h('div', { class: 'banner warn' }, h('div', { class: 'grow' }, d.catalogNote)));
    }
  }

  function renderCounts() {
    const d = state.data;
    $('cntLines').textContent = String((d.live.quotes || d.catalog.quotes).length);
    const edited = d.catalog.strings.filter(anyEdited).length;
    $('cntText').textContent = edited ? edited + ' edited' : String(d.catalog.strings.length);
    $('cntHistory').textContent = d.log.length ? String(d.log.length) : '';
  }

  // ---- Daily lines --------------------------------------------------------

  /** A built-in line's credit, found again by its English (which an edit to
   *  the Arabic leaves alone), so a saved list still says whose words a
   *  line is. */
  function creditFor(line) {
    const match = state.data.catalog.quotes.find((q) => q.en === line.en || q.ar === line.ar);
    return match ? match.source || null : null;
  }

  function savedLines() {
    const d = state.data;
    if (d.live.quotes) {
      return d.live.quotes.map((q) => ({ ar: q.ar, en: q.en, source: creditFor(q) }));
    }
    return d.catalog.quotes.map((q) => ({ ar: q.ar, en: q.en, source: q.source || null }));
  }

  function shownLines() {
    return state.draft || savedLines();
  }

  function sameLines(a, b) {
    return a.length === b.length && a.every((q, i) =>
      R.normalizeText(q.ar) === R.normalizeText(b[i].ar) &&
      R.normalizeText(q.en) === R.normalizeText(b[i].en));
  }

  function linesDirty() {
    return state.draft !== null && !sameLines(state.draft, savedLines());
  }

  function ensureDraft() {
    if (!state.draft) state.draft = savedLines().map((q) => Object.assign({}, q));
  }

  function renderLines() {
    const view = clear($('viewLines'));
    const d = state.data;
    const today = d.today;
    const phoneList = d.live.quotes || d.catalog.quotes;
    const phoneLine = phoneList[R.rotationIndex(today, phoneList.length)];

    const from = d.live.quotes
      ? h('span', { class: 'grow' }, 'From your list of ' + d.live.quotes.length + ' lines' +
          (d.live.updatedAt ? ', saved ' + fmtTime(d.live.updatedAt) : '') + '.')
      : h('span', { class: 'grow' }, 'From the app’s built-in list of ' + d.catalog.quotes.length + ' lines.');
    view.appendChild(h('div', { class: 'today' },
      h('div', { class: 'label' }, 'Phones show today, ' + fmtDate(today)),
      h('div', { class: 't-ar', lang: 'ar', dir: 'rtl' }, phoneLine ? phoneLine.ar : ''),
      h('div', { class: 't-en' }, phoneLine ? phoneLine.en : ''),
      h('div', { class: 'from' }, from,
        d.live.quotes ? button('Use the built-in list', useBuiltInLines) : null)));

    if (d.live.quotes && d.admin.quotesBuiltInFnv &&
        d.admin.quotesBuiltInFnv !== d.catalog.sources.dailyQuotes.fnv1a) {
      view.appendChild(h('div', { class: 'banner info' }, h('div', { class: 'grow' },
        'The app’s built-in list has changed in code since you saved yours. Phones keep showing yours; ',
        'use the built-in list to take the new one.')));
    }

    const lines = shownLines();
    const n = lines.length;
    const todayIndex = R.rotationIndex(today, n);
    view.appendChild(h('p', { class: 'list-note' },
      'One line a day, in this order, then the list starts again. The date is the next day each line shows.'));
    const list = h('div', { class: 'qlist' });
    lines.forEach((line, i) => list.appendChild(lineRow(line, i, n, todayIndex, today)));
    view.appendChild(list);
    view.appendChild(h('div', { class: 'add-line' }, button('+ Add a line', addLine)));
    view.appendChild(h('div', { class: 'savebar', id: 'saveBar', hidden: true }));
    updateSaveBar();
  }

  function lineRow(line, i, n, todayIndex, today) {
    const inDays = (((i - todayIndex) % n) + n) % n;
    const when = inDays === 0 ? 'Today' : inDays === 1 ? 'Tomorrow' : fmtDate(R.addDays(today, inDays));
    const ar = textBox('ar', line.ar, 'Line ' + (i + 1) + ', Arabic');
    const en = textBox('en', line.en, 'Line ' + (i + 1) + ', English');
    ar.addEventListener('input', () => {
      ensureDraft();
      state.draft[i].ar = ar.value;
      autosize(ar);
      updateSaveBar();
    });
    en.addEventListener('input', () => {
      ensureDraft();
      state.draft[i].en = en.value;
      autosize(en);
      updateSaveBar();
    });
    return h('div', { class: 'qrow' + (inDays === 0 ? ' is-today' : ''), 'data-index': i },
      h('div', { class: 'qmeta' },
        h('b', null, String(i + 1)),
        h('span', { class: 'when' + (inDays === 0 ? ' now' : ''), title: 'Next day this line shows' }, when),
        line.source ? h('span', { class: 'src' }, line.source) : null),
      ar,
      en,
      h('div', { class: 'qtools' },
        button('↑', () => moveLine(i, -1), 'icon-btn', { title: 'Move up', 'aria-label': 'Move line ' + (i + 1) + ' up', disabled: i === 0 }),
        button('↓', () => moveLine(i, 1), 'icon-btn', { title: 'Move down', 'aria-label': 'Move line ' + (i + 1) + ' down', disabled: i === n - 1 }),
        button('✕', () => deleteLine(i), 'icon-btn del', { title: 'Delete', 'aria-label': 'Delete line ' + (i + 1), disabled: n === 1 })));
  }

  function moveLine(i, by) {
    ensureDraft();
    const j = i + by;
    if (j < 0 || j >= state.draft.length) return;
    const moved = state.draft.splice(i, 1)[0];
    state.draft.splice(j, 0, moved);
    renderLines();
  }

  function deleteLine(i) {
    ensureDraft();
    if (state.draft.length <= 1) return;
    state.draft.splice(i, 1);
    renderLines();
  }

  function addLine() {
    ensureDraft();
    state.draft.push({ ar: '', en: '', source: null });
    renderLines();
    const rows = document.querySelectorAll('#viewLines .qrow');
    const last = rows[rows.length - 1];
    if (last) {
      last.scrollIntoView({ block: 'center', behavior: 'smooth' });
      const box = last.querySelector('textarea');
      if (box) box.focus();
    }
  }

  function updateSaveBar() {
    const bar = $('saveBar');
    if (!bar) return;
    clear(bar);
    if (!linesDirty()) {
      bar.hidden = true;
      return;
    }
    bar.hidden = false;
    const draft = state.draft;
    const saved = savedLines();
    let changed = 0;
    for (let i = 0; i < Math.min(draft.length, saved.length); i++) {
      if (R.normalizeText(draft[i].ar) !== R.normalizeText(saved[i].ar) ||
          R.normalizeText(draft[i].en) !== R.normalizeText(saved[i].en)) changed++;
    }
    const parts = [];
    if (changed) parts.push(changed + (changed === 1 ? ' line changed' : ' lines changed'));
    if (draft.length > saved.length) parts.push((draft.length - saved.length) + ' added');
    if (draft.length < saved.length) parts.push((saved.length - draft.length) + ' removed');

    const check = R.checkQuotes(draft);
    const today = state.data.today;
    const phoneList = state.data.live.quotes || state.data.catalog.quotes;
    const nowLine = phoneList[R.rotationIndex(today, phoneList.length)];
    const nextLine = draft[R.rotationIndex(today, draft.length)];
    const msgs = h('div', { class: 'msgs' });
    if (nowLine && nextLine && R.normalizeText(nextLine.ar) !== R.normalizeText(nowLine.ar)) {
      msgs.appendChild(h('div', { class: 'wrn' }, 'Saving changes today’s line on every phone to: ',
        h('span', { class: 't-ar', lang: 'ar', dir: 'rtl' }, R.normalizeText(nextLine.ar) || '(empty)')));
    }
    check.errors.forEach((e) => msgs.appendChild(h('div', { class: 'err' }, e)));
    check.warnings.forEach((w) => msgs.appendChild(h('div', { class: 'wrn' }, w)));

    const save = button('Save list', saveLines, 'btn primary', { disabled: !check.ok || state.saving });
    bar.appendChild(h('div', { class: 'row' },
      h('div', { class: 'grow' }, h('b', null, 'Unsaved: '), parts.join(', ') || 'order changed'),
      button('Discard', () => {
        state.draft = null;
        renderLines();
      }),
      save));
    if (msgs.childNodes.length) bar.appendChild(msgs);
  }

  async function saveLines() {
    if (state.saving || !linesDirty()) return;
    state.saving = true;
    updateSaveBar();
    const res = await post('/api/wording/quotes', {
      items: state.draft.map((q) => ({ ar: q.ar, en: q.en })),
    });
    state.saving = false;
    if (!res.ok) {
      updateSaveBar();
      toast(errorText(res.body));
      return;
    }
    applyWording(res.body.wording);
    state.draft = null;
    renderAll();
    toast(savedMessage(res.body.changed ? 'Saved.' : 'Nothing changed.'));
  }

  async function useBuiltInLines() {
    const d = state.data;
    if (!window.confirm('Go back to the app’s built-in ' + d.catalog.quotes.length +
        ' lines on every phone? Your list stays in History and can be restored from there.')) return;
    const res = await post('/api/wording/quotes', { items: null });
    if (!res.ok) {
      toast(errorText(res.body));
      return;
    }
    applyWording(res.body.wording);
    state.draft = null;
    renderAll();
    toast(savedMessage('Back to the built-in list.'));
  }

  function savedMessage(first) {
    return state.data.phones === 'closed'
      ? first + ' Phones will see it once the database rule is deployed.'
      : first + ' Open apps show it within seconds.';
  }

  // ---- App text -----------------------------------------------------------

  const FILTERS = [
    { id: 'all', label: 'All', test: () => true, always: true },
    { id: 'edited', label: 'Edited', test: anyEdited, always: true },
    { id: 'drift', label: 'Changed in code since your edit', test: anyDrift },
    { id: 'fixed', label: 'Built-in only', test: (e) => !e.editable },
    { id: 'unused', label: 'Not shown anywhere', test: (e) => e.unused === true },
  ];

  function buildTextView() {
    const view = clear($('viewText'));
    const search = h('input', {
      type: 'search',
      id: 'q',
      dir: 'auto',
      placeholder: 'Search Arabic or English text, a screen, or a key',
      autocomplete: 'off',
      spellcheck: 'false',
    });
    search.addEventListener('input', debounce(() => {
      state.query = search.value;
      state.limit = PAGE_SIZE;
      renderTextList();
    }, 90));
    view.appendChild(h('div', { class: 'filter-bar' }, search, h('div', { class: 'chip-row', id: 'chips' })));
    view.appendChild(h('div', { class: 'status-row', id: 'textStatus' }));
    view.appendChild(h('div', { class: 'slist', id: 'slist' }));
    view.appendChild(h('div', { class: 'more', id: 'more' }));
  }

  function renderTextList() {
    const strings = state.data.catalog.strings;
    const chips = clear($('chips'));
    for (const f of FILTERS) {
      const count = strings.filter(f.test).length;
      if (!count && !f.always) continue;
      chips.appendChild(button([f.label, h('span', { class: 'n' }, String(count))], () => {
        state.filter = f.id;
        state.limit = PAGE_SIZE;
        renderTextList();
      }, 'chip-btn' + (state.filter === f.id ? ' active' : '')));
    }

    const words = R.searchKey(state.query).split(/\s+/).filter(Boolean);
    const filter = FILTERS.find((f) => f.id === state.filter) || FILTERS[0];
    const matches = state.index
      .filter((x) => filter.test(x.entry) && words.every((w) => x.hay.includes(w)))
      .map((x) => x.entry);
    // The open editor stays on screen whatever the search says, so a typed
    // edit is never hidden (and never thrown away) by narrowing the list.
    const openEntry = state.open ? state.byKey.get(state.open) : null;
    if (openEntry && !matches.includes(openEntry)) matches.unshift(openEntry);

    const shown = matches.slice(0, state.limit);
    const list = clear($('slist'));
    shown.forEach((entry) => list.appendChild(stringRow(entry)));
    if (!shown.length) {
      list.appendChild(h('div', { class: 'loading' }, 'Nothing matches.'));
    }
    $('textStatus').textContent = matches.length === strings.length
      ? strings.length + ' strings'
      : matches.length + ' of ' + strings.length + ' strings';
    const more = clear($('more'));
    if (matches.length > shown.length) {
      more.appendChild(button('Show ' + Math.min(PAGE_SIZE, matches.length - shown.length) + ' more', () => {
        state.limit += PAGE_SIZE;
        renderTextList();
      }));
    }
  }

  function rowHead(entry) {
    const screens = entry.screens && entry.screens.length ? ' · ' + entry.screens.join(', ') : '';
    const badges = [];
    if (!entry.editable) badges.push(h('span', { class: 'badge fixed' }, 'Built-in only'));
    LANGS.forEach((lang) => {
      if (isEdited(entry, lang)) badges.push(h('span', { class: 'badge edited' }, 'Edited ' + LANG_NAME[lang]));
    });
    if (anyDrift(entry)) {
      badges.push(h('span', {
        class: 'badge drift',
        title: 'The app’s own text for this string changed after you edited it. Your edit still shows.',
      }, 'Changed in code'));
    }
    if (entry.unused) {
      badges.push(h('span', {
        class: 'badge unused',
        title: 'The wording workbook found no screen that shows this string.',
      }, 'Not shown anywhere'));
    }
    return h('div', { class: 'srow-head' },
      h('span', { class: 'where' }, h('b', null, entry.section || 'Other'), screens),
      badges,
      h('code', { class: 'key' }, entry.key));
  }

  /** [text] with each {part} the app fills set apart as its own chip. A
   *  part is Latin code inside an Arabic sentence, and left to the bidi
   *  algorithm it drags the words around it into the wrong order; isolated,
   *  it sits in the sentence exactly where the app will put its value. */
  function withParts(text, parts) {
    if (!parts || !parts.length || text.indexOf('{') < 0) return text;
    const out = [];
    let rest = text;
    while (rest.length) {
      let at = -1;
      let hit = null;
      parts.forEach((p) => {
        const i = rest.indexOf('{' + p + '}');
        if (i >= 0 && (at < 0 || i < at)) {
          at = i;
          hit = p;
        }
      });
      if (at < 0) {
        out.push(rest);
        break;
      }
      if (at > 0) out.push(rest.slice(0, at));
      out.push(h('span', { class: 'tok', dir: 'ltr' }, '{' + hit + '}'));
      rest = rest.slice(at + hit.length + 2);
    }
    return out;
  }

  function textCell(entry, lang) {
    const parts = lang === 'ar' ? entry.tokensAr : entry.tokensEn;
    return h('div', { class: 'cell t-' + lang, lang, dir: lang === 'ar' ? 'rtl' : 'ltr' },
      isEdited(entry, lang) ? h('span', { class: 'mark', title: 'Edited' }) : null,
      withParts(liveText(entry, lang) || '(empty)', parts));
  }

  function stringRow(entry) {
    const open = state.open === entry.key;
    const row = h('article', {
      class: 'srow ' + (entry.editable ? 'editable' : 'fixed') + (open ? ' open' : ''),
      'data-key': entry.key,
    });
    row.appendChild(rowHead(entry));
    if (open) {
      row.appendChild(editor(entry));
      return row;
    }
    row.appendChild(h('div', { class: 'srow-cols' }, textCell(entry, 'ar'), textCell(entry, 'en')));
    if (!entry.editable) {
      row.appendChild(h('div', { class: 'why' }, entry.why));
    } else {
      row.addEventListener('click', () => {
        // Selecting text to copy it is not a request to edit.
        if (String(window.getSelection() || '')) return;
        openEditor(entry.key);
      });
    }
    return row;
  }

  /** The edits typed into the open editor that differ from what is saved,
   *  by language; null when there are none. Text equal to the built-in text
   *  is sent as null, "back to built-in". */
  function pendingChanges(entry) {
    if (!state.edit) return null;
    const changes = {};
    LANGS.forEach((lang) => {
      const typed = R.normalizeText(state.edit[lang]);
      if (typed === R.normalizeText(liveText(entry, lang))) return;
      changes[lang] = typed === R.normalizeText(builtIn(entry, lang)) ? null : typed;
    });
    return Object.keys(changes).length ? changes : null;
  }

  function openEditorHasChanges() {
    const entry = state.open ? state.byKey.get(state.open) : null;
    return !!(entry && pendingChanges(entry));
  }

  function openEditor(key) {
    if (state.open === key) return;
    if (openEditorHasChanges() &&
        !window.confirm('Throw away your unsaved edit to ' + state.open + '?')) return;
    const entry = state.byKey.get(key);
    state.open = key;
    state.edit = { ar: liveText(entry, 'ar'), en: liveText(entry, 'en') };
    renderTextList();
    const row = document.querySelector('.srow.open');
    if (row) {
      const box = row.querySelector('textarea');
      if (box) box.focus();
      row.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  function closeEditor(force) {
    if (!force && openEditorHasChanges() && !window.confirm('Throw away your unsaved edit?')) return;
    state.open = null;
    state.edit = null;
    renderTextList();
  }

  function editor(entry) {
    const fields = {};
    const grid = h('div', { class: 'editor' });
    const save = button('Save', doSave, 'btn primary');
    const cancel = button('Cancel', () => closeEditor(false));
    const serverMsgs = h('div', { class: 'msgs' });

    LANGS.forEach((lang) => {
      const ta = textBox(lang, state.edit[lang], LANG_NAME[lang]);
      const useBuiltIn = button('Use built-in text', () => {
        ta.value = builtIn(entry, lang);
        ta.dispatchEvent(new Event('input'));
        ta.focus();
      }, 'link-btn');
      const parts = h('div', { class: 'parts' });
      const msgs = h('div', { class: 'msgs' });
      const ref = h('div', { class: 'ref' });
      if (isEdited(entry, lang)) {
        ref.appendChild(h('div', null, 'Built-in: ',
          h('span', { class: 't-' + lang, lang, dir: lang === 'ar' ? 'rtl' : 'ltr' }, builtIn(entry, lang))));
      }
      if (drifted(entry, lang)) {
        ref.appendChild(h('div', null, 'Your edit replaced an older built-in text: ',
          h('span', { class: 't-' + lang, lang, dir: lang === 'ar' ? 'rtl' : 'ltr' },
            state.data.admin.bases[lang][entry.key])));
      }
      grid.appendChild(h('div', null,
        h('div', { class: 'field-head' }, h('span', { class: 'lang' }, LANG_NAME[lang]), useBuiltIn),
        ta, parts, msgs, ref));
      fields[lang] = { ta, parts, msgs, useBuiltIn };

      ta.addEventListener('input', () => {
        state.edit[lang] = ta.value;
        autosize(ta);
        clear(serverMsgs);
        refresh();
      });
      ta.addEventListener('keydown', (ev) => {
        if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') {
          ev.preventDefault();
          doSave();
        } else if (ev.key === 'Escape') {
          ev.preventDefault();
          closeEditor(false);
        }
      });
    });

    /** Re-checks both boxes as they are typed in. Nothing here re-renders
     *  a box, so the cursor stays where it is. */
    function refresh() {
      let blocked = false;
      LANGS.forEach((lang) => {
        const f = fields[lang];
        const text = state.edit[lang];
        const check = R.checkStringEdit(entry, lang, text);
        f.ta.classList.toggle('has-error', !check.ok);
        if (!check.ok) blocked = true;
        clear(f.msgs);
        check.errors.forEach((e) => f.msgs.appendChild(h('div', { class: 'err' }, e)));
        check.warnings.forEach((w) => f.msgs.appendChild(h('div', { class: 'wrn' }, w)));
        f.useBuiltIn.hidden = R.normalizeText(text) === R.normalizeText(builtIn(entry, lang));

        const tokens = (lang === 'ar' ? entry.tokensAr : entry.tokensEn) || [];
        clear(f.parts);
        if (tokens.length) {
          const used = R.partsIn(text);
          f.parts.appendChild(h('span', null, 'The app fills in:'));
          tokens.forEach((token) => {
            f.parts.appendChild(button('{' + token + '}', () => insertAtCursor(f.ta, '{' + token + '}'),
              'part' + (used.includes(token) ? '' : ' missing'),
              { title: used.includes(token) ? 'Click to insert again' : 'Not in your text. Click to insert it at the cursor.' }));
          });
        }
      });
      save.disabled = blocked || state.saving || !pendingChanges(entry);
    }

    async function doSave() {
      const changes = pendingChanges(entry);
      if (!changes) {
        closeEditor(true);
        return;
      }
      if (save.disabled || state.saving) return;
      state.saving = true;
      save.disabled = true;
      save.textContent = 'Saving…';
      const res = await post('/api/wording/string', { key: entry.key, changes });
      state.saving = false;
      save.textContent = 'Save';
      if (!res.ok) {
        clear(serverMsgs);
        serverMsgs.appendChild(h('div', { class: 'err' }, errorText(res.body)));
        refresh();
        return;
      }
      applyWording(res.body.wording);
      state.open = null;
      state.edit = null;
      renderAll();
      toast(savedMessage('Saved.'));
    }

    const notes = entry.notes
      ? h('details', { class: 'notes' }, h('summary', null, 'Why it is worded this way (notes from the code)'),
          entry.notes.split('\n').map((p) => h('p', null, p)))
      : null;
    const wrap = h('div', null, grid, serverMsgs,
      h('div', { class: 'editor-foot' }, save, cancel,
        h('span', { class: 'hint' }, h('kbd', null, '⌘'), ' ', h('kbd', null, 'Enter'), ' saves, ', h('kbd', null, 'Esc'), ' cancels')),
      notes);
    refresh();
    return wrap;
  }

  function insertAtCursor(ta, text) {
    const start = ta.selectionStart;
    const end = ta.selectionEnd;
    ta.value = ta.value.slice(0, start) + text + ta.value.slice(end);
    ta.selectionStart = ta.selectionEnd = start + text.length;
    ta.focus();
    ta.dispatchEvent(new Event('input'));
  }

  // ---- History ------------------------------------------------------------

  function targetOf(row) {
    return row.kind === 'quotes' ? 'quotes' : row.key + '/' + row.lang;
  }

  function renderHistory() {
    const view = clear($('viewHistory'));
    const log = state.data.log;
    if (!log.length) {
      view.appendChild(h('div', { class: 'loading' }, 'Nothing has been edited yet.'));
      return;
    }
    // Only the newest change to each thing can be undone: undoing an older
    // one would throw away everything after it.
    const newest = new Map();
    log.forEach((row) => {
      if (!newest.has(targetOf(row))) newest.set(targetOf(row), row.id);
    });
    const list = h('div', { class: 'hlist' });
    log.forEach((row) => list.appendChild(historyRow(row, newest.get(targetOf(row)) === row.id)));
    view.appendChild(list);
    view.appendChild(h('p', { class: 'fine', style: 'color: var(--text-tert); font-size: 12px;' },
      'The latest ' + log.length + ' changes.'));
  }

  function historyRow(row, isNewest) {
    let what;
    let change;
    if (row.kind === 'quotes') {
      what = h('div', { class: 'what' }, 'Daily lines', row.undoOf ? ' (undo)' : '');
      change = quotesChange(row);
    } else {
      const entry = state.byKey.get(row.key);
      what = h('div', { class: 'what' }, LANG_NAME[row.lang] || row.lang,
        entry ? ' · ' + entry.section : '', row.undoOf ? ' (undo)' : '',
        h('code', { class: 'key' }, row.key));
      change = stringChange(row);
    }
    let action = null;
    if (row.undoneBy) {
      action = h('span', { class: 'badge unused' }, 'Undone');
    } else if (isNewest) {
      action = button('Undo', () => undo(row), 'btn');
    }
    return h('div', { class: 'hrow' + (row.undoneBy ? ' undone' : '') },
      h('div', { class: 'when' }, fmtTime(row.at)),
      h('div', null, what, change),
      h('div', null, action));
  }

  function stringChange(row) {
    const entry = state.byKey.get(row.key);
    const parts = entry ? (row.lang === 'ar' ? entry.tokensAr : entry.tokensEn) : [];
    const dir = row.lang === 'ar' ? 'rtl' : 'ltr';
    // null on either side means "the built-in text", which the row keeps
    // (builtIn) so the change can be read without the code at hand.
    const side = (label, value, tag) => [
      h('div', { class: 'side-label' }, value === null ? label + ' (built-in text)' : label),
      h('div', { class: 'change t-' + row.lang, lang: row.lang, dir },
        h(tag, null, withParts(value === null ? row.builtIn || '' : value, parts))),
    ];
    return h('div', null, side('Before', row.before, 'del'), side('After', row.after, 'ins'));
  }

  function quotesChange(row) {
    const builtInList = state.data.catalog.quotes;
    const before = row.before || builtInList;
    const after = row.after || builtInList;
    const name = (list, own) => own ? 'your list of ' + list.length : 'the built-in ' + list.length;
    let text = 'From ' + name(before, !!row.before) + ' to ' + name(after, !!row.after) + '.';
    const changed = [];
    for (let i = 0; i < Math.min(before.length, after.length); i++) {
      if (before[i].ar !== after[i].ar || before[i].en !== after[i].en) changed.push(i + 1);
    }
    if (changed.length) {
      text += ' Changed ' + (changed.length === 1 ? 'line ' : 'lines ') + changed.slice(0, 12).join(', ') +
        (changed.length > 12 ? ' and ' + (changed.length - 12) + ' more' : '') + '.';
    }
    return h('div', { class: 'none' }, text);
  }

  async function undo(row) {
    if (state.saving) return;
    state.saving = true;
    const res = await post('/api/wording/undo', { id: row.id });
    state.saving = false;
    if (!res.ok) {
      toast(errorText(res.body));
      return;
    }
    applyWording(res.body.wording);
    state.draft = null;
    renderAll();
    toast(savedMessage('Undone.'));
  }

  // ---- Tabs and start -----------------------------------------------------

  function showTab(tab) {
    state.tab = tab;
    document.querySelectorAll('.view-tab').forEach((t) => {
      const on = t.getAttribute('data-tab') === tab;
      t.classList.toggle('active', on);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    $('viewLines').classList.toggle('active', tab === 'lines');
    $('viewText').classList.toggle('active', tab === 'text');
    $('viewHistory').classList.toggle('active', tab === 'history');
    if (location.hash !== '#' + tab) history.replaceState(null, '', '#' + tab);
    requestAnimationFrame(resizeAll);
    if (tab === 'text') {
      const q = $('q');
      if (q && !state.open) q.focus();
    }
  }

  function renderAll() {
    renderBanners();
    renderCounts();
    renderLines();
    renderTextList();
    renderHistory();
  }

  async function start() {
    document.querySelectorAll('.view-tab').forEach((t) => {
      t.addEventListener('click', () => showTab(t.getAttribute('data-tab')));
    });
    window.addEventListener('resize', debounce(resizeAll, 150));
    window.addEventListener('hashchange', () => {
      const tab = location.hash.slice(1);
      if (['lines', 'text', 'history'].includes(tab) && tab !== state.tab) showTab(tab);
    });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(resizeAll);
    window.addEventListener('beforeunload', (ev) => {
      if (linesDirty() || openEditorHasChanges()) {
        ev.preventDefault();
        ev.returnValue = '';
      }
    });

    let body;
    try {
      const res = await fetch('/api/wording');
      body = await res.json();
      if (!res.ok) throw new Error(body.error || 'The admin tool answered ' + res.status + '.');
    } catch (e) {
      clear($('viewLines')).appendChild(h('div', { class: 'banner danger' },
        h('div', { class: 'grow' }, h('b', null, 'Could not load the wording. '), e.message)));
      return;
    }
    state.data = body;
    state.byKey = new Map(body.catalog.strings.map((s) => [s.key, s]));
    reindex();
    buildTextView();
    renderAll();
    const hash = location.hash.slice(1);
    showTab(['lines', 'text', 'history'].includes(hash) ? hash : 'lines');
  }

  start();
})();
