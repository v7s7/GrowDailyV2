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
  // The edition of the page's styles this script is written for: the
  // --wording-styles value in lib/wording_page.js. See renderBanners.
  const STYLES_EDITION = '2';
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
    // The daily lines as edited on the page: a copy of the saved list, made
    // on the first render, whose line objects then stay the same from one
    // render to the next (see "Daily lines" below). Null only until the
    // next render after a save, a discard or an undo in History.
    draft: null,
    // Ticked lines (objects in draft), moved or deleted together.
    picked: new Set(),
    // The line ticked last, where a shift-click range starts.
    pickAnchor: null,
    // Earlier orders of draft, newest last, for Undo and Cmd+Z.
    undo: [],
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
    // The styles are built into the page when the server starts; this
    // script is read from disk on every load. A server left running across
    // an update pairs this script with the styles from before it, and the
    // list comes out half drawn: say what to do instead of leaving a puzzle.
    const edition = getComputedStyle(document.documentElement).getPropertyValue('--wording-styles').trim();
    if (edition !== STYLES_EDITION) {
      box.appendChild(h('div', { class: 'banner danger' },
        h('div', { class: 'grow' },
          h('b', null, 'This page was updated, but the admin tool is still running the copy from before. '),
          'Stop it (Ctrl-C in its Terminal window), start it again with ',
          h('code', null, 'npm start'),
          ', then reload this page.')));
    }
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
  //
  // Aziz, 2026-09-24, on the arrows that moved a line one place per click:
  // "make this easy to control and move, the lines, not one by one, drag,
  // or any smart ways". So a line now moves by dragging its grip, by its
  // date (click it: today, tomorrow, a day, a line number), by the arrows
  // as before, or several at once once ticked; Undo and Cmd+Z take a move
  // back. Every one of those ends in moveTo and R.moveLines, so the list
  // arithmetic is one function, tested in node.
  //
  // What makes it hold together is that the draft's line objects are the
  // same objects from one render to the next. A row is made once per line
  // and moved, never rebuilt, so its text boxes keep their text, size and
  // cursor; a tick follows its line wherever it goes; and an undo step can
  // be just the old order, leaving typing done since where it is.

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

  function sameLines(a, b) {
    return a.length === b.length && a.every((q, i) =>
      R.normalizeText(q.ar) === R.normalizeText(b[i].ar) &&
      R.normalizeText(q.en) === R.normalizeText(b[i].en));
  }

  function linesDirty() {
    return state.draft !== null && !sameLines(state.draft, savedLines());
  }

  /** The draft, made from the saved list when there is none. Each line
   *  keeps its place in the saved list (origin; null for a line added
   *  here), which is how the save bar can say "1 line moved" instead of
   *  counting every line whose number shifted. */
  function ensureDraft() {
    if (!state.draft) {
      state.draft = savedLines().map((q, i) => Object.assign({}, q, { origin: i }));
    }
    return state.draft;
  }

  /** Back to the saved list. The ticks and undo steps go with the draft:
   *  they name line objects that no longer exist. */
  function resetDraft() {
    state.draft = null;
    state.picked = new Set();
    state.pickAnchor = null;
    state.undo = [];
  }

  // Each draft line's row, each row's parts, and each row's line. A row is
  // made once per line, then only moved and relabelled (renderList).
  let rowOf = new Map();
  const partsOf = new WeakMap();
  const lineOf = new WeakMap();

  function reducedMotion() {
    return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  }

  /** Six dots, the usual sign for "hold here and drag". */
  function gripIcon() {
    const NS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 10 16');
    svg.setAttribute('width', '10');
    svg.setAttribute('height', '16');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    [[3, 3], [7, 3], [3, 8], [7, 8], [3, 13], [7, 13]].forEach(([cx, cy]) => {
      const dot = document.createElementNS(NS, 'circle');
      dot.setAttribute('cx', cx);
      dot.setAttribute('cy', cy);
      dot.setAttribute('r', '1.5');
      dot.setAttribute('fill', 'currentColor');
      svg.appendChild(dot);
    });
    return svg;
  }

  let liveRegion = null;
  /** Tells a screen reader what a move did; the eye sees it for itself. */
  function announce(text) {
    if (!liveRegion) {
      liveRegion = h('div', { class: 'sr-only', role: 'status', 'aria-live': 'polite' });
      document.body.appendChild(liveRegion);
    }
    liveRegion.textContent = '';
    setTimeout(() => {
      liveRegion.textContent = text;
    }, 30);
  }

  /** Days from today until line [i] of an [n]-line list shows next. */
  function daysUntil(i, n, todayIndex) {
    return (((i - todayIndex) % n) + n) % n;
  }

  function whenText(inDays) {
    return inDays === 0 ? 'Today' : inDays === 1 ? 'Tomorrow' : fmtDate(R.addDays(state.data.today, inDays));
  }

  /** The same inside a sentence: "today", "tomorrow", "on Sat 26 Sep". */
  function whenPhrase(inDays) {
    return inDays === 0 ? 'today' : inDays === 1 ? 'tomorrow' : 'on ' + fmtDate(R.addDays(state.data.today, inDays));
  }

  /** The top of the part of the window the rows are seen in: under the top
   *  bar while it is pinned. */
  function topEdge() {
    const bar = document.querySelector('.app-top');
    return bar ? Math.max(0, bar.getBoundingClientRect().bottom) : 0;
  }

  /** And its bottom: above the dock while the dock is pinned to the bottom
   *  of the window, since the rows behind it cannot be seen. */
  function bottomEdge() {
    const dock = $('dock');
    if (dock && dock.offsetHeight) {
      const r = dock.getBoundingClientRect();
      if (r.bottom >= window.innerHeight - 1 && r.top < window.innerHeight) return r.top;
    }
    return window.innerHeight;
  }

  function renderLines() {
    closeMoveMenu(false);
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

    ensureDraft();
    view.appendChild(h('div', { class: 'list-note' },
      h('p', null, 'One line a day, in this order, then the list starts again. The date is the next day each line shows.'),
      h('p', null, 'Drag ', gripIcon(), ' to move a line, or click its date to send it to today, tomorrow, another day or a line number. ',
        'Tick lines to move or delete several at once. ', h('kbd', null, '⌘Z'), ' undoes a move.')));
    rowOf = new Map();
    view.appendChild(h('div', { class: 'qlist', id: 'qlist' }));
    view.appendChild(h('div', { class: 'add-line' }, button('+ Add a line', addLine)));
    view.appendChild(h('div', { class: 'dock', id: 'dock', hidden: true },
      h('div', { class: 'selbar', id: 'selBar', hidden: true }),
      h('div', { class: 'savebar', id: 'saveBar', hidden: true })));
    renderList();
  }

  /**
   * Puts the rows in the draft's order and labels each one, making a row
   * only for a line that has none yet.
   *   animate  slide every row that moved from where it was drawn;
   *   still    except these lines' rows, which jump (a line sent forty rows
   *            away should not fly across the screen to get there);
   *   keep     scroll so this line's row stays exactly where it was on
   *            screen, which is what lets the same arrow be clicked again;
   *   first    where the rows were drawn, measured by the caller (a drop
   *            measures before it shows the rows a drag hid).
   */
  function renderList(opts) {
    opts = opts || {};
    const list = $('qlist');
    if (!list) return;
    const lines = state.draft;
    const first = opts.first || (opts.animate || opts.keep ? rowTops(list) : null);
    const focus = rememberFocus(list);
    const present = new Set(lines);
    for (const [line, row] of rowOf) {
      if (!present.has(line)) {
        row.remove();
        rowOf.delete(line);
      }
    }
    lines.forEach((line, i) => {
      let row = rowOf.get(line);
      if (!row) {
        row = lineRow(line);
        rowOf.set(line, row);
      }
      if (list.children[i] !== row) list.insertBefore(row, list.children[i] || null);
    });
    labelRows(lines);
    if (opts.keep && first) {
      const row = rowOf.get(opts.keep);
      const was = row ? first.get(row) : undefined;
      if (was !== undefined) window.scrollBy({ top: row.getBoundingClientRect().top - was, behavior: 'instant' });
    }
    restoreFocus(focus);
    if (first && opts.animate) slide(list, first, opts.still);
    updateDock();
  }

  /** Numbers, dates and states for the rows of [lines], in that order. */
  function labelRows(lines) {
    const n = lines.length;
    const todayIndex = R.rotationIndex(state.data.today, n);
    lines.forEach((line, i) => {
      const row = rowOf.get(line);
      if (row) labelRow(row, line, i, n, todayIndex);
    });
    const list = $('qlist');
    if (list) list.classList.toggle('picking', state.picked.size > 0);
  }

  function labelRow(row, line, i, n, todayIndex) {
    const ui = partsOf.get(row);
    const inDays = daysUntil(i, n, todayIndex);
    const num = i + 1;
    const picked = state.picked.has(line);
    row.setAttribute('data-index', i);
    row.classList.toggle('is-today', inDays === 0);
    row.classList.toggle('is-picked', picked);
    ui.num.textContent = String(num);
    ui.when.textContent = whenText(inDays);
    ui.when.classList.toggle('now', inDays === 0);
    ui.when.setAttribute('aria-label', 'Line ' + num + ' shows ' + whenPhrase(inDays) + '. Change when');
    ui.pick.checked = picked;
    ui.pick.setAttribute('aria-label', 'Tick line ' + num);
    ui.grip.setAttribute('aria-label', 'Move line ' + num + ': drag it, use the arrow keys, or press Enter for more');
    ui.ar.setAttribute('aria-label', 'Line ' + num + ', Arabic');
    ui.en.setAttribute('aria-label', 'Line ' + num + ', English');
    ui.up.disabled = i === 0;
    ui.up.setAttribute('aria-label', 'Move line ' + num + ' up');
    ui.down.disabled = i === n - 1;
    ui.down.setAttribute('aria-label', 'Move line ' + num + ' down');
    ui.del.disabled = n === 1;
    ui.del.setAttribute('aria-label', 'Delete line ' + num);
  }

  function lineRow(line) {
    const grip = h('button', {
      type: 'button',
      class: 'grip',
      title: 'Drag to move. Click for more ways to move.',
      'aria-haspopup': 'dialog',
    }, gripIcon());
    const pick = h('input', {
      type: 'checkbox',
      class: 'pick',
      title: 'Tick to move or delete several lines together. Shift-click ticks a run of lines.',
    });
    const num = h('b', { class: 'num' });
    const when = h('button', {
      type: 'button',
      class: 'when',
      title: 'The next day this line shows. Click to change it.',
      'aria-haspopup': 'dialog',
    });
    const ar = textBox('ar', line.ar, '');
    const en = textBox('en', line.en, '');
    const up = button('↑', () => nudge(line, -1), 'icon-btn', { title: 'Move up' });
    const down = button('↓', () => nudge(line, 1), 'icon-btn', { title: 'Move down' });
    const del = button('✕', () => removeLines([line]), 'icon-btn del', { title: 'Delete' });

    ar.addEventListener('input', () => {
      line.ar = ar.value;
      autosize(ar);
      updateSaveBar();
    });
    en.addEventListener('input', () => {
      line.en = en.value;
      autosize(en);
      updateSaveBar();
    });
    grip.addEventListener('pointerdown', (ev) => dragStart(ev, line));
    grip.addEventListener('click', () => {
      if (!dragJustEnded) openMoveMenu(line, grip);
    });
    grip.addEventListener('keydown', (ev) => {
      if (ev.key !== 'ArrowUp' && ev.key !== 'ArrowDown') return;
      ev.preventDefault();
      nudge(line, ev.key === 'ArrowUp' ? -1 : 1);
    });
    // Shift-click would also stretch a text selection across the page.
    pick.addEventListener('mousedown', (ev) => {
      if (ev.shiftKey) ev.preventDefault();
    });
    pick.addEventListener('click', (ev) => togglePick(line, ev.shiftKey));
    when.addEventListener('click', () => openMoveMenu(line, when));

    const row = h('div', { class: 'qrow' },
      grip,
      h('div', { class: 'qmeta' },
        h('div', { class: 'qhead' }, pick, num),
        when,
        line.source ? h('span', { class: 'src' }, line.source) : null),
      ar,
      en,
      h('div', { class: 'qtools' }, up, down, del));
    partsOf.set(row, { grip, pick, num, when, ar, en, up, down, del });
    lineOf.set(row, line);
    return row;
  }

  /** The focused control inside [list] and its cursor: moving a row in the
   *  page takes the focus out of it, and restoreFocus puts it back. */
  function rememberFocus(list) {
    const el = document.activeElement;
    if (!el || !list.contains(el)) return null;
    const text = el.tagName === 'TEXTAREA';
    return {
      el,
      start: text ? el.selectionStart : null,
      end: text ? el.selectionEnd : null,
      dir: text ? el.selectionDirection : null,
    };
  }

  function restoreFocus(f) {
    if (!f || !f.el.isConnected || f.el.disabled || document.activeElement === f.el) return;
    f.el.focus({ preventScroll: true });
    if (f.start !== null) f.el.setSelectionRange(f.start, f.end, f.dir || 'none');
  }

  /** Where each shown row is drawn now; then any slide still running is
   *  stopped, so what is measured next is where the rows really are. */
  function rowTops(list) {
    const tops = new Map();
    for (const row of list.children) {
      if (row.offsetHeight) tops.set(row, row.getBoundingClientRect().top);
    }
    for (const row of tops.keys()) {
      row.style.transition = '';
      row.style.transform = '';
    }
    return tops;
  }

  /** Slides each row from where it was drawn ([first]) to where it is now,
   *  except the rows of [still]. */
  function slide(list, first, still) {
    if (reducedMotion()) return;
    const skip = new Set((still || []).map((line) => rowOf.get(line)));
    const moving = [];
    for (const row of list.children) {
      if (!first.has(row) || skip.has(row) || !row.offsetHeight) continue;
      const dy = first.get(row) - row.getBoundingClientRect().top;
      if (Math.abs(dy) < 1) continue;
      row.style.transform = 'translateY(' + dy + 'px)';
      moving.push(row);
    }
    if (!moving.length) return;
    // Lay out the starting places before the slide begins.
    void list.offsetHeight;
    for (const row of moving) {
      row.style.transition = 'transform 160ms cubic-bezier(0.2, 0.7, 0.3, 1)';
      row.style.transform = '';
    }
  }

  /** Marks [rows] for a moment, so the eye finds where they went. */
  function flash(rows) {
    rows = rows.filter(Boolean);
    rows.forEach((row) => {
      row.classList.remove('flash');
      void row.offsetWidth;
      row.classList.add('flash');
    });
    setTimeout(() => rows.forEach((row) => row.classList.remove('flash')), 1200);
  }

  /** Brings [group]'s first row into view when it is not, and marks the
   *  group. By layout, not by where rows are drawn: a row still sliding is
   *  drawn somewhere else for a moment. */
  function reveal(group) {
    const rows = group.map((line) => rowOf.get(line)).filter(Boolean);
    if (!rows.length) return;
    const list = $('qlist');
    const row = rows[0];
    const top = list.getBoundingClientRect().top + row.offsetTop;
    const seen = top >= topEdge() + 8 && top + row.offsetHeight <= bottomEdge() - 8;
    if (!seen) {
      const room = bottomEdge() - topEdge();
      window.scrollTo({
        top: Math.max(0, window.scrollY + top - topEdge() - Math.max(16, (room - row.offsetHeight) / 2)),
        behavior: reducedMotion() ? 'instant' : 'smooth',
      });
    }
    flash(rows);
  }

  // ---- Moving, deleting, adding, undoing ----------------------------------

  /** One place up or down: the arrows, and the arrow keys on a grip. */
  function nudge(line, by) {
    const lines = state.draft;
    const i = lines.indexOf(line);
    const j = i + by;
    if (i < 0 || j < 0 || j >= lines.length) return;
    moveTo([line], j, { keep: line });
  }

  /**
   * Moves [group] (draft lines) so its first line is at [to] and the rest
   * follow it in their order; [opts.wrap] as in R.moveLines. [opts.reveal]
   * brings them into view and marks them, [opts.keep] as in renderList.
   * Returns whether anything moved.
   */
  function moveTo(group, to, opts) {
    opts = opts || {};
    // A save in flight resets the draft when it lands; a change made now
    // would vanish with it.
    if (state.saving) return false;
    const lines = state.draft;
    const idx = group.map((line) => lines.indexOf(line)).filter((i) => i >= 0);
    const next = R.moveLines(lines, idx, to, opts.wrap);
    if (next.every((line, i) => line === lines[i])) return false;
    pushUndo(movedLabel(group, lines, next));
    state.draft = next;
    renderList({ animate: true, keep: opts.keep, still: opts.reveal ? group : null });
    if (opts.reveal) reveal(group);
    announce(movedSentence(group, next));
    return true;
  }

  function movedLabel(group, before, after) {
    const at = after.indexOf(group[0]) + 1;
    return group.length === 1
      ? 'move line ' + (before.indexOf(group[0]) + 1) + ' to line ' + at
      : 'move ' + group.length + ' lines to line ' + at;
  }

  function movedSentence(group, after) {
    const n = after.length;
    const at = after.indexOf(group[0]);
    const when = whenPhrase(daysUntil(at, n, R.rotationIndex(state.data.today, n)));
    return group.length === 1
      ? 'Now line ' + (at + 1) + ', shows ' + when + '.'
      : group.length + ' lines moved. The first is now line ' + (at + 1) + ' and shows ' + when + '.';
  }

  function removeLines(group) {
    if (state.saving) return;
    const lines = state.draft;
    const gone = new Set(group);
    const left = lines.filter((line) => !gone.has(line));
    if (left.length === lines.length) return;
    if (!left.length) {
      toast('The Grid needs at least one line.');
      return;
    }
    const nums = group.map((line) => lines.indexOf(line) + 1).sort((a, b) => a - b);
    pushUndo(nums.length === 1 ? 'delete line ' + nums[0] : 'delete ' + nums.length + ' lines');
    state.draft = left;
    group.forEach((line) => state.picked.delete(line));
    renderList({ animate: true });
    announce(nums.length === 1 ? 'Line ' + nums[0] + ' deleted.' : nums.length + ' lines deleted.');
  }

  function addLine() {
    if (state.saving) return;
    pushUndo('add a line');
    const line = { ar: '', en: '', source: null, origin: null };
    state.draft = state.draft.concat([line]);
    renderList();
    const row = rowOf.get(line);
    row.scrollIntoView({ block: 'center', behavior: reducedMotion() ? 'instant' : 'smooth' });
    partsOf.get(row).ar.focus({ preventScroll: true });
  }

  function pushUndo(label) {
    state.undo.push({ lines: state.draft.slice(), label });
    if (state.undo.length > 50) state.undo.shift();
  }

  /** Puts back the order before the last move, delete or add. Text typed
   *  since stays: an undo step is an order of the same line objects. */
  function undoLines() {
    if (state.saving) return;
    const step = state.undo.pop();
    if (!step) return;
    closeMoveMenu(false);
    const present = new Set(state.draft);
    const back = step.lines.filter((line) => !present.has(line));
    state.draft = step.lines;
    const kept = new Set(state.draft);
    for (const line of Array.from(state.picked)) {
      if (!kept.has(line)) state.picked.delete(line);
    }
    renderList({ animate: true });
    flash(back.map((line) => rowOf.get(line)));
    announce('Undone: ' + step.label + '.');
  }

  // ---- Ticked lines -------------------------------------------------------

  /** Ticks or unticks [line]. With [range] (shift held), every line from
   *  the last one clicked to this one takes this one's new state. */
  function togglePick(line, range) {
    const lines = state.draft;
    const anchor = state.pickAnchor;
    const on = !state.picked.has(line);
    if (range && anchor && anchor !== line && lines.includes(anchor)) {
      const a = lines.indexOf(anchor);
      const b = lines.indexOf(line);
      for (let k = Math.min(a, b); k <= Math.max(a, b); k++) {
        if (on) state.picked.add(lines[k]);
        else state.picked.delete(lines[k]);
      }
    } else if (on) {
      state.picked.add(line);
    } else {
      state.picked.delete(line);
    }
    state.pickAnchor = line;
    labelRows(lines);
    updateSelBar();
  }

  function pickedLines() {
    return state.draft.filter((line) => state.picked.has(line));
  }

  function clearPicks() {
    state.picked.clear();
    state.pickAnchor = null;
    labelRows(state.draft);
    updateSelBar();
  }

  /** What an action on [line] moves: every ticked line when [line] is one
   *  of several ticked, otherwise [line] alone. */
  function groupFor(line) {
    return state.picked.has(line) && state.picked.size > 1 ? pickedLines() : [line];
  }

  // ---- The dock: ticked lines, then unsaved changes -----------------------

  function updateDock() {
    updateSelBar();
    updateSaveBar();
  }

  /** The dock shows while either of its two bars does. */
  function fitDock() {
    const dock = $('dock');
    if (dock) dock.hidden = $('selBar').hidden && $('saveBar').hidden;
  }

  function updateSelBar() {
    const bar = $('selBar');
    if (!bar) return;
    clear(bar);
    const picked = pickedLines();
    bar.hidden = !picked.length;
    fitDock();
    if (!picked.length) return;
    const nums = picked.map((line) => state.draft.indexOf(line) + 1);
    const shown = nums.length > 8
      ? nums.slice(0, 8).join(', ') + ' and ' + (nums.length - 8) + ' more'
      : nums.join(', ');
    const move = button('Move to…', () => openMoveMenu(picked[0], move), 'btn', { 'aria-haspopup': 'dialog' });
    bar.appendChild(h('div', { class: 'row' },
      h('div', { class: 'grow' },
        h('b', null, picked.length === 1 ? '1 line ticked' : picked.length + ' lines ticked'),
        h('span', { class: 'sel-nums' }, ' (' + (nums.length === 1 ? 'line ' : 'lines ') + shown + ')')),
      move,
      button('Delete', () => removeLines(picked), 'btn del-btn', { disabled: picked.length >= state.draft.length }),
      button('Clear', clearPicks, 'btn', { title: 'Untick every line (Esc)' })));
  }

  function updateSaveBar() {
    const bar = $('saveBar');
    if (!bar) return;
    clear(bar);
    bar.hidden = !linesDirty();
    fitDock();
    if (bar.hidden) return;
    const draft = state.draft;
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
    const last = state.undo[state.undo.length - 1];
    bar.appendChild(h('div', { class: 'row' },
      h('div', { class: 'grow' }, h('b', null, 'Unsaved: '), R.lineChangeWords(draftChanges()) || 'changes'),
      last ? button('Undo', undoLines, 'btn', { title: 'Undo: ' + last.label + ' (⌘Z)' }) : null,
      button('Discard', () => {
        resetDraft();
        renderLines();
      }),
      save));
    if (msgs.childNodes.length) bar.appendChild(msgs);
  }

  /** What the draft changes, told by each line's origin (see ensureDraft),
   *  so a line is still the same line with both its languages rewritten. */
  function draftChanges() {
    const saved = savedLines();
    const kept = [];
    let edited = 0;
    let added = 0;
    state.draft.forEach((line) => {
      const was = typeof line.origin === 'number' ? saved[line.origin] : null;
      if (!was) {
        added++;
        return;
      }
      kept.push(line.origin);
      if (R.normalizeText(line.ar) !== R.normalizeText(was.ar) ||
          R.normalizeText(line.en) !== R.normalizeText(was.en)) edited++;
    });
    return { moved: kept.length - R.longestRising(kept), edited, added, removed: saved.length - kept.length };
  }

  // ---- The move menu: a line's date, its grip, or "Move to…" clicked ------

  let menu = null;
  let menuSeq = 0;

  function openMoveMenu(line, anchor) {
    if (menu && menu.anchor === anchor) {
      closeMoveMenu(false);
      return;
    }
    closeMoveMenu(false);
    const lines = state.draft;
    const group = groupFor(line);
    const idx = group.map((l) => lines.indexOf(l));
    const n = lines.length;
    const g = group.length;
    const at = idx[0];
    const today = state.data.today;
    const todayIndex = R.rotationIndex(today, n);
    const lastDay = R.addDays(today, n - 1);
    const name = g === 1 ? 'line ' + (at + 1) : g + ' ticked lines';
    const changes = (to, wrap) => R.moveLines(lines, idx, to, wrap).some((l, i) => l !== lines[i]);
    // [keys]: the menu was worked from the keyboard. The menu takes the
    // focus with it, so the moved line's grip gets it and the keyboard
    // carries on from where the line went. Not after a click: a grip with
    // a focus nobody can see would turn the next arrow key, meant to
    // scroll the page, into a move.
    const go = (to, wrap, keys) => {
      closeMoveMenu(false);
      moveTo(group, to, { wrap, reveal: true });
      const row = rowOf.get(group[0]);
      if (keys && row) partsOf.get(row).grip.focus({ preventScroll: true });
    };
    // A click the keyboard made (Enter or Space on a button) has detail 0.
    const byKeys = (ev) => !!ev && ev.detail === 0;
    const id = 'mm' + (++menuSeq);
    const err = h('div', { class: 'mm-err', role: 'alert', hidden: true });
    const fail = (text) => {
      err.textContent = text;
      err.hidden = false;
    };

    // A day's place in the rotation, so these wrap past the last line.
    const dayItem = (label, day) => {
      const to = R.rotationIndex(day, n);
      return button([h('span', null, label), h('span', { class: 'mm-hint' }, fmtDate(day))],
        (ev) => go(to, true, byKeys(ev)), 'mm-item', { disabled: !changes(to, true) });
    };

    const dayBox = h('input', { type: 'date', id: id + 'd', min: today, max: lastDay });
    dayBox.value = R.addDays(today, daysUntil(at, n, todayIndex));
    const goDay = (keys) => {
      const day = dayBox.value;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < today || day > lastDay) {
        fail('Pick a day from ' + fmtDate(today) + ' to ' + fmtDate(lastDay) + '. After that the list starts again.');
        return;
      }
      go(R.rotationIndex(day, n), true, keys);
    };

    const lineBox = h('input', { type: 'number', id: id + 'n', min: 1, max: n, step: 1 });
    lineBox.value = String(at + 1);
    const goLine = (keys) => {
      const k = Number(lineBox.value);
      if (!Number.isInteger(k) || k < 1 || k > n) {
        fail('Type a line number from 1 to ' + n + '.');
        return;
      }
      go(k - 1, false, keys);
    };
    [[dayBox, goDay], [lineBox, goLine]].forEach(([box, act]) => {
      box.addEventListener('keydown', (ev) => {
        if (ev.key !== 'Enter') return;
        ev.preventDefault();
        act(true);
      });
      box.addEventListener('input', () => {
        err.hidden = true;
      });
    });

    const el = h('div', { class: 'move-menu', role: 'dialog', 'aria-label': 'Move ' + name },
      h('div', { class: 'mm-head' },
        h('b', null, 'Move ' + name),
        h('span', null, g === 1
          ? 'It shows ' + whenPhrase(daysUntil(at, n, todayIndex)) + '.'
          : 'They stay together, in their order.')),
      dayItem('Today', today),
      dayItem('Tomorrow', R.addDays(today, 1)),
      h('div', { class: 'mm-sep' }),
      h('div', { class: 'mm-field' },
        h('label', { for: id + 'd' }, 'On a day'), dayBox, button('Move', (ev) => goDay(byKeys(ev)), 'btn mm-go')),
      h('div', { class: 'mm-field' },
        h('label', { for: id + 'n' }, 'To line'), lineBox, h('span', { class: 'mm-of' }, 'of ' + n),
        button('Move', (ev) => goLine(byKeys(ev)), 'btn mm-go')),
      err);
    el.addEventListener('keydown', (ev) => {
      if (ev.key !== 'Escape') return;
      ev.preventDefault();
      ev.stopPropagation();
      closeMoveMenu(true);
    });
    el.addEventListener('focusout', (ev) => {
      if (menu && menu.el === el && ev.relatedTarget && !el.contains(ev.relatedTarget)) closeMoveMenu(false);
    });
    document.body.appendChild(el);
    placeMenu(el, anchor);
    menu = { el, anchor };
    anchor.setAttribute('aria-expanded', 'true');
    document.addEventListener('pointerdown', menuOutside, true);
    window.addEventListener('resize', closeMenuQuietly);
    (el.querySelector('.mm-item:not(:disabled)') || dayBox).focus({ preventScroll: true });
  }

  /** Under [anchor], or over it when there is no room below. Fixed to the
   *  window for the dock's button (the dock does not scroll), otherwise
   *  placed on the page so it scrolls with its row. */
  function placeMenu(el, anchor) {
    const fixed = !!anchor.closest('.dock');
    el.style.position = fixed ? 'fixed' : 'absolute';
    const r = anchor.getBoundingClientRect();
    const w = el.offsetWidth;
    const tall = el.offsetHeight;
    let top = r.bottom + 6;
    if (top + tall > window.innerHeight - 8 && r.top - 6 - tall >= topEdge()) top = r.top - 6 - tall;
    const left = Math.max(12, Math.min(r.left, document.documentElement.clientWidth - w - 12));
    el.style.top = Math.round(top + (fixed ? 0 : window.scrollY)) + 'px';
    el.style.left = Math.round(left + (fixed ? 0 : window.scrollX)) + 'px';
  }

  function closeMoveMenu(returnFocus) {
    if (!menu) return;
    const { el, anchor } = menu;
    menu = null;
    el.remove();
    anchor.removeAttribute('aria-expanded');
    document.removeEventListener('pointerdown', menuOutside, true);
    window.removeEventListener('resize', closeMenuQuietly);
    if (returnFocus && anchor.isConnected) anchor.focus({ preventScroll: true });
  }

  function closeMenuQuietly() {
    closeMoveMenu(false);
  }

  function menuOutside(ev) {
    if (!menu || menu.el.contains(ev.target) || menu.anchor.contains(ev.target)) return;
    closeMoveMenu(false);
  }

  // ---- Dragging a line by its grip ----------------------------------------
  //
  // The dragged row stays in the list as the gap (dashed, its boxes hidden
  // but kept), a small card follows the pointer, and the rows around it
  // slide out of the way, relabelled as they go so each date says the day
  // it would show after a drop there. Near the top or bottom of the window
  // the page scrolls itself. Esc puts everything back.
  //
  // Listening on the window rather than capturing the pointer: the gap is
  // the row the grip is in, moved around the page as the pointer goes, and
  // a node taken out and put back loses its pointer capture.

  let drag = null;
  // True for the moment between a drop and the click the browser sends
  // after it, which must not open the grip's menu.
  let dragJustEnded = false;
  // How close to the top or bottom edge, in pixels, the page starts to scroll.
  const EDGE = 72;

  function dragStart(ev, line) {
    if (ev.button !== 0 || !ev.isPrimary || drag || state.saving) return;
    ev.preventDefault();
    drag = { line, pointerId: ev.pointerId, x0: ev.clientX, y0: ev.clientY, y: ev.clientY, lifted: false };
    window.addEventListener('pointermove', dragMove);
    window.addEventListener('pointerup', dragEnd);
    window.addEventListener('pointercancel', dragCancel);
    window.addEventListener('blur', dragCancel);
    document.addEventListener('keydown', dragKey, true);
  }

  function dragMove(ev) {
    if (!drag || ev.pointerId !== drag.pointerId) return;
    drag.y = ev.clientY;
    if (!drag.lifted) {
      // A few pixels of wobble is still a click, which opens the menu.
      if (Math.abs(ev.clientX - drag.x0) < 5 && Math.abs(ev.clientY - drag.y0) < 5) return;
      lift();
    }
    ev.preventDefault();
    placeGhost();
    findSlot(false);
  }

  function lift() {
    closeMoveMenu(false);
    const d = drag;
    d.lifted = true;
    d.list = $('qlist');
    d.group = groupFor(d.line);
    d.row = rowOf.get(d.line);
    d.before = state.draft.slice();
    d.group.forEach((line) => {
      if (line !== d.line) rowOf.get(line).classList.add('is-hidden');
    });
    d.row.classList.add('is-placeholder');
    document.body.classList.add('lines-dragging');
    d.ghost = ghostFor(d.group, d.line);
    document.body.appendChild(d.ghost);
    d.scrollY = window.scrollY;
    d.raf = requestAnimationFrame(dragTick);
    placeGhost();
    findSlot(true);
  }

  function ghostFor(group, line) {
    const more = group.length - 1;
    return h('div', { class: 'drag-ghost' + (more ? ' is-stack' : ''), 'aria-hidden': 'true' },
      h('span', { class: 'dg-grip' }, gripIcon()),
      h('div', { class: 'dg-body' },
        h('div', { class: 'dg-head' },
          h('span', { class: 'dg-to' }),
          more ? h('span', { class: 'dg-more' }, '+' + more + (more === 1 ? ' ticked line' : ' ticked lines')) : null),
        h('div', { class: 't-ar dg-ar', lang: 'ar', dir: 'rtl' }, R.normalizeText(line.ar) || '(empty)'),
        h('div', { class: 't-en dg-en' }, R.normalizeText(line.en) || '(empty)')));
  }

  /** The card rides on the pointer, level with the list's left edge. */
  function placeGhost() {
    const left = drag.list.getBoundingClientRect().left;
    drag.ghost.style.transform = 'translate(' + Math.round(left) + 'px, ' + Math.round(drag.y - 20) + 'px)';
  }

  /** Moves the gap to the pointer: before the first row whose middle is
   *  below it. Rows are measured by layout (offsetTop), never where they
   *  are drawn, so a row mid-slide cannot make the gap jump back. With
   *  [instant] (the page is scrolling itself) the rows jump instead of
   *  sliding: slides restarted every few frames would only lag behind the
   *  page and draw rows over each other. */
  function findSlot(relabel, instant) {
    const d = drag;
    const y = d.y - d.list.getBoundingClientRect().top;
    let before = null;
    for (const row of d.list.children) {
      if (row === d.row || row.classList.contains('is-hidden')) continue;
      if (row.offsetTop + row.offsetHeight / 2 > y) {
        before = row;
        break;
      }
    }
    let next = d.row.nextElementSibling;
    while (next && next.classList.contains('is-hidden')) next = next.nextElementSibling;
    if (next !== before) {
      const first = rowTops(d.list);
      d.list.insertBefore(d.row, before);
      if (!instant) slide(d.list, first);
      relabel = true;
    }
    if (relabel) labelDrag();
  }

  /** The order a drop now would make. */
  function dragOrder() {
    const order = [];
    for (const row of drag.list.children) {
      if (row === drag.row) order.push(...drag.group);
      else if (!row.classList.contains('is-hidden')) order.push(lineOf.get(row));
    }
    return order;
  }

  /** Relabels every row for that order, and tells the card where the line
   *  would land and the day it would show. */
  function labelDrag() {
    const d = drag;
    const order = dragOrder();
    labelRows(order);
    const n = order.length;
    const at = order.indexOf(d.group[0]);
    const when = whenText(daysUntil(at, n, R.rotationIndex(state.data.today, n)));
    const to = clear(d.ghost.querySelector('.dg-to'));
    if (d.group.length === 1) {
      append(to, [h('b', null, String(d.before.indexOf(d.line) + 1)), ' → ',
        h('b', { class: 'dg-at' }, String(at + 1)), ' · ' + when]);
    } else {
      append(to, ['→ ', h('b', { class: 'dg-at' }, (at + 1) + ' to ' + (at + d.group.length)), ' · ' + when]);
    }
  }

  function dragTick() {
    const d = drag;
    if (!d || !d.lifted) return;
    const top = topEdge() + EDGE;
    const bottom = bottomEdge() - EDGE;
    let speed = 0;
    if (d.y < top) speed = -scrollSpeed((top - d.y) / EDGE);
    else if (d.y > bottom) speed = scrollSpeed((d.y - bottom) / EDGE);
    if (speed) window.scrollBy({ top: speed, behavior: 'instant' });
    // The page moved under a still pointer (this, or a trackpad): the gap
    // follows.
    if (window.scrollY !== d.scrollY) {
      d.scrollY = window.scrollY;
      findSlot(false, true);
    }
    d.raf = requestAnimationFrame(dragTick);
  }

  /** Pixels a frame: a crawl just inside the edge zone, about 2,000 a
   *  second at the edge itself, so the far end of a 37-line list (some
   *  3,500 pixels) is two seconds away. */
  function scrollSpeed(depth) {
    const t = Math.min(1, Math.max(0, depth));
    return Math.round(3 + 30 * Math.pow(t, 1.6));
  }

  function dragEnd(ev) {
    if (!drag || ev.pointerId !== drag.pointerId) return;
    const d = drag;
    if (!d.lifted) {
      // A click: the grip's own click handler opens the menu.
      stopDrag();
      return;
    }
    const order = dragOrder();
    // Measured while the lines the drag hid are still hidden, so they
    // appear in their new places rather than sliding in from the old ones.
    const first = rowTops(d.list);
    stopDrag();
    dragJustEnded = true;
    setTimeout(() => {
      dragJustEnded = false;
    }, 0);
    const moved = order.some((line, i) => line !== state.draft[i]);
    if (moved) {
      pushUndo(movedLabel(d.group, state.draft, order));
      state.draft = order;
    }
    renderList({ animate: true, first });
    if (moved) {
      flash(d.group.map((line) => rowOf.get(line)));
      announce(movedSentence(d.group, order));
    }
  }

  function dragCancel() {
    if (!drag) return;
    const d = drag;
    const first = d.lifted ? rowTops(d.list) : null;
    stopDrag();
    if (first) renderList({ animate: true, first });
  }

  function dragKey(ev) {
    if (ev.key !== 'Escape') return;
    ev.preventDefault();
    ev.stopPropagation();
    dragCancel();
  }

  function stopDrag() {
    const d = drag;
    drag = null;
    window.removeEventListener('pointermove', dragMove);
    window.removeEventListener('pointerup', dragEnd);
    window.removeEventListener('pointercancel', dragCancel);
    window.removeEventListener('blur', dragCancel);
    document.removeEventListener('keydown', dragKey, true);
    if (!d || !d.lifted) return;
    cancelAnimationFrame(d.raf);
    d.ghost.remove();
    d.row.classList.remove('is-placeholder');
    d.group.forEach((line) => {
      const row = rowOf.get(line);
      if (row) row.classList.remove('is-hidden');
    });
    document.body.classList.remove('lines-dragging');
  }

  /** Esc unticks, and Cmd+Z undoes the last move, delete or add, whenever
   *  the keys are not busy in a text box (where they mean what they
   *  always mean). */
  function linesKeys(ev) {
    if (state.tab !== 'lines' || drag || !state.draft) return;
    const t = ev.target;
    const typing = !!t && (t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable ||
      (t.tagName === 'INPUT' && t.type !== 'checkbox'));
    if (typing) return;
    const key = String(ev.key || '');
    if (key === 'Escape' && !menu && state.picked.size) {
      ev.preventDefault();
      clearPicks();
    } else if ((ev.metaKey || ev.ctrlKey) && !ev.shiftKey && !ev.altKey && key.toLowerCase() === 'z' && state.undo.length) {
      ev.preventDefault();
      undoLines();
    }
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
    resetDraft();
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
    resetDraft();
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
    // By the text, not by position: one line moved from 30 to 9 is "1 line
    // moved", not the 22 lines whose numbers shifted.
    const words = R.lineChangeWords(R.describeLineChanges(before, after));
    if (words) text += ' ' + words.charAt(0).toUpperCase() + words.slice(1) + '.';
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
    resetDraft();
    renderAll();
    toast(savedMessage('Undone.'));
  }

  // ---- Tabs and start -----------------------------------------------------

  function showTab(tab) {
    closeMoveMenu(false);
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
    document.addEventListener('keydown', linesKeys);
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
