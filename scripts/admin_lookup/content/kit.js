/**
 * What the FAQ and Premium pages share in the browser: building elements,
 * talking to the server, the banners every live page shows, text boxes
 * that grow with their text, dragging rows into place, and the History
 * list with its Undo.
 *
 * A plain file served as it is (see lib/content_pages.js for why no page
 * script lives inside a template literal). It sets window.ContentKit and
 * nothing else.
 *
 * No em dash anywhere in this file, including comments.
 */
(function () {
  'use strict';

  // The edition of the pages' styles this script is written for: the
  // --content-styles value in lib/content_pages.js. The styles are built
  // into a page when the server starts and this file is read on every load,
  // so a server left running across an update pairs a new script with old
  // styles; the pages say so instead of drawing half a page.
  const EDITION = '1';
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // ---- Elements -------------------------------------------------------------

  /** An element. Text children are always text nodes, never parsed as HTML. */
  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      for (const name of Object.keys(props)) {
        const value = props[name];
        if (value === null || value === undefined || value === false) continue;
        if (name === 'class') el.className = value;
        else if (name === 'value') el.value = value;
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

  /** A Material Symbols glyph, the same set the app draws its icons from. */
  function glyph(name, cls) {
    return h('span', { class: 'msr' + (cls ? ' ' + cls : ''), 'aria-hidden': 'true' }, name);
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

  /** A text box as tall as its text, so no line of an answer hides. A box
   *  not on screen yet is sized when it is (resizeAll). */
  function autosize(ta) {
    if (!ta.offsetParent) return;
    ta.style.height = 'auto';
    // Borders plus one for Arabic's fractional line height, which
    // scrollHeight rounds down.
    ta.style.height = ta.scrollHeight + 3 + 'px';
    ta.style.overflowY = 'hidden';
  }

  function resizeAll(root) {
    (root || document).querySelectorAll('textarea').forEach(autosize);
  }

  function textBox(lang, value, label, onInput) {
    const ta = h('textarea', {
      class: 't-' + lang,
      lang,
      dir: lang === 'ar' ? 'rtl' : 'ltr',
      rows: 1,
      spellcheck: lang === 'en' ? 'true' : 'false',
      'aria-label': label,
    });
    ta.value = value || '';
    ta.addEventListener('input', () => {
      autosize(ta);
      if (onInput) onInput(ta.value);
    });
    requestAnimationFrame(() => autosize(ta));
    return ta;
  }

  /** Errors and warnings under a field. */
  function showMessages(box, errors, warnings) {
    clear(box);
    (errors || []).forEach((e) => box.appendChild(h('div', { class: 'err' }, e)));
    (warnings || []).forEach((w) => box.appendChild(h('div', { class: 'wrn' }, w)));
  }

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3400);
  }

  function debounce(fn, ms) {
    let t = null;
    return function () {
      clearTimeout(t);
      t = setTimeout(fn, ms);
    };
  }

  function fmtTime(iso) {
    if (!iso) return 'just now';
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, '0');
    return d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear() + ', ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
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

  // ---- The server -----------------------------------------------------------

  async function load() {
    const res = await fetch('/api/wording');
    let body = {};
    try {
      body = await res.json();
    } catch (e) {
      body = {};
    }
    if (!res.ok) throw new Error(body.error || 'The admin tool answered ' + res.status + '.');
    return body;
  }

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
    return { ok: res.ok && body.ok !== false, status: res.status, body };
  }

  /**
   * The page is out of date (the server answered 409): says so at the top
   * and offers a reload, leaving everything typed on the page where it is
   * so it can be copied first.
   */
  function showStale(message) {
    const box = $('banners');
    const old = box.querySelector('.banner.stale');
    if (old) old.remove();
    // The page's own guard still asks before a reload drops unsaved text.
    const reload = button('Reload the page', () => location.reload(), 'btn small');
    const b = h('div', { class: 'banner danger stale' }, h('div', { class: 'grow' }, h('b', null, 'Not saved. '), message), reload);
    box.insertBefore(b, box.firstChild);
    b.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  /** Every text box in [root] read-only while a save is in flight, so
   *  nothing typed then is lost when the page redraws from the answer. */
  function setReadOnly(root, on) {
    (root || document).querySelectorAll('textarea').forEach((ta) => {
      ta.readOnly = !!on;
    });
  }

  function errorText(body) {
    if (!body) return 'The save did not go through.';
    if (body.error) return body.error;
    if (Array.isArray(body.errors) && body.errors.length) return body.errors.join(' ');
    return 'The save did not go through.';
  }

  function savedMessage(first, phones) {
    return phones === 'closed'
      ? first + ' Phones will see it once the database rule is deployed.'
      : first + ' Open apps show it within seconds.';
  }

  // ---- Banners --------------------------------------------------------------

  function banner(kind, bold, rest) {
    return h('div', { class: 'banner ' + kind }, h('div', { class: 'grow' }, bold ? h('b', null, bold + ' ') : null, rest));
  }

  /** The banners every live page shows, over [extra] of its own. */
  function renderBanners(box, data, extra) {
    clear(box);
    const edition = getComputedStyle(document.documentElement).getPropertyValue('--content-styles').trim();
    if (edition !== EDITION) {
      box.appendChild(banner('danger', 'This page was updated, but the admin tool is still running the copy from before.',
        ['Stop it (Ctrl-C in its Terminal window), start it again with ', h('code', null, 'npm start'), ', then reload this page.']));
    }
    if (data && data.phones === 'closed') {
      box.appendChild(banner('danger', 'Phones cannot read these edits yet.',
        ['The database rule that lets them read has not been deployed. From the repo folder: ',
          h('code', null, 'firebase deploy --only firestore:rules')]));
    }
    if (data && data.catalogNote) box.appendChild(banner('warn', null, data.catalogNote));
    (extra || []).forEach((b) => box.appendChild(b));
  }

  // ---- Dragging rows into place ---------------------------------------------
  //
  // Pointer events rather than HTML drag and drop: the same code runs for a
  // mouse, a trackpad and a test driving the page, rows keep their text
  // boxes (the row itself moves, it is never copied), and the page scrolls
  // when a row is held near the top or the bottom of the window.
  //
  // sortable({ lists, handle, row, onDrop }) where lists() returns the
  // containers a row may land in (in page order), handle is the selector of
  // what starts a drag inside a row, row the selector of a row, and
  // onDrop(rowEl, fromList, fromIndex, toList, toIndex) makes the move in
  // the page's own data (indices count rows only, never the gap).

  const EDGE = 70;

  function sortable(opts) {
    let drag = null;

    function rowsOf(list) {
      return Array.from(list.children).filter((el) => el.matches(opts.row) && !el.classList.contains('is-lifted'));
    }

    function start(ev) {
      const handle = ev.target.closest(opts.handle);
      if (!handle || ev.button !== 0) return;
      const row = handle.closest(opts.row);
      if (!row) return;
      const list = row.parentElement;
      drag = {
        row,
        handle,
        fromList: list,
        fromIndex: rowsOf(list).indexOf(row),
        x: ev.clientX,
        y: ev.clientY,
        dx: 0,
        dy: 0,
        lifted: false,
        pointerId: ev.pointerId,
        slot: null,
        scroll: 0,
        frame: null,
      };
      handle.setPointerCapture(ev.pointerId);
      ev.preventDefault();
    }

    function lift() {
      const r = drag.row.getBoundingClientRect();
      drag.offsetX = drag.x - r.left;
      drag.offsetY = drag.y - r.top;
      drag.slot = h('div', { class: 'drag-slot' });
      drag.slot.style.height = r.height + 'px';
      drag.row.parentElement.insertBefore(drag.slot, drag.row);
      drag.row.classList.add('is-lifted');
      drag.row.style.width = r.width + 'px';
      drag.row.style.left = r.left + 'px';
      drag.row.style.top = r.top + 'px';
      document.body.classList.add('rows-dragging');
      drag.lifted = true;
      drag.scrollY = window.scrollY;
      tick();
    }

    function place(x, y) {
      drag.row.style.left = x - drag.offsetX + 'px';
      drag.row.style.top = y - drag.offsetY + 'px';
    }

    /** The list under the pointer (or the nearest one above or below it),
     *  and the place in it: before the first row whose middle is below. */
    function target(y) {
      const lists = opts.lists();
      if (!lists.length) return null;
      let best = null;
      let bestDistance = Infinity;
      for (const list of lists) {
        const r = list.getBoundingClientRect();
        const distance = y < r.top ? r.top - y : y > r.bottom ? y - r.bottom : 0;
        if (distance < bestDistance) {
          best = list;
          bestDistance = distance;
        }
      }
      const rows = rowsOf(best);
      let index = rows.length;
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i].getBoundingClientRect();
        if (y < r.top + r.height / 2) {
          index = i;
          break;
        }
      }
      return { list: best, index };
    }

    function moveSlot(y) {
      const t = target(y);
      if (!t) return;
      const rows = rowsOf(t.list);
      const before = rows[t.index] || null;
      if (before) {
        if (drag.slot.parentElement !== t.list || drag.slot.nextElementSibling !== before) t.list.insertBefore(drag.slot, before);
      } else if (rows.length) {
        const last = rows[rows.length - 1];
        if (last.nextElementSibling !== drag.slot) last.after(drag.slot);
      } else if (drag.slot.parentElement !== t.list) {
        // An empty list: first, before its "nothing here" note.
        t.list.insertBefore(drag.slot, t.list.firstChild);
      }
      opts.lists().forEach((l) => l.classList.toggle('drop-here', l === t.list));
    }

    /** The top of the part of the window rows are seen in: under the top
     *  bar and any toolbar pinned beneath it. */
    function topEdge() {
      let edge = 0;
      document.querySelectorAll('.app-top, .toolbar').forEach((el) => {
        const style = getComputedStyle(el);
        if (style.position !== 'sticky') return;
        const r = el.getBoundingClientRect();
        if (r.top <= (parseFloat(style.top) || 0) + 1) edge = Math.max(edge, r.bottom);
      });
      return edge;
    }

    /** And its bottom: above the save dock while it is pinned. */
    function bottomEdge() {
      const dock = document.getElementById('dock');
      if (dock && !dock.hidden && dock.offsetHeight) {
        const r = dock.getBoundingClientRect();
        if (r.top < window.innerHeight) return r.top;
      }
      return window.innerHeight;
    }

    /** Pixels a frame, the Wording page's curve: a crawl just inside the
     *  edge zone, about 2,000 a second at the edge itself. */
    function speedFor(depth) {
      const t = Math.min(1, Math.max(0, depth));
      return Math.round(3 + 30 * Math.pow(t, 1.6));
    }

    /** Keeps the page scrolling while a row is held near an edge, and the
     *  gap under the pointer while the page moves under it. */
    function tick() {
      if (!drag || !drag.lifted) return;
      const y = drag.y + drag.dy;
      const top = topEdge() + EDGE;
      const bottom = bottomEdge() - EDGE;
      let speed = 0;
      if (y < top) speed = -speedFor((top - y) / EDGE);
      else if (y > bottom) speed = speedFor((y - bottom) / EDGE);
      if (speed) window.scrollBy({ top: speed, behavior: 'instant' });
      if (window.scrollY !== drag.scrollY) {
        drag.scrollY = window.scrollY;
        moveSlot(y);
      }
      drag.frame = requestAnimationFrame(tick);
    }

    function move(ev) {
      if (!drag || ev.pointerId !== drag.pointerId) return;
      drag.dx = ev.clientX - drag.x;
      drag.dy = ev.clientY - drag.y;
      if (!drag.lifted) {
        if (Math.abs(drag.dx) + Math.abs(drag.dy) < 5) return;
        lift();
      }
      place(ev.clientX, ev.clientY);
      moveSlot(ev.clientY);
    }

    function finish(commit) {
      if (!drag) return;
      const d = drag;
      drag = null;
      cancelAnimationFrame(d.frame);
      try {
        d.handle.releasePointerCapture(d.pointerId);
      } catch (e) {
        // Already released.
      }
      if (!d.lifted) return;
      document.body.classList.remove('rows-dragging');
      opts.lists().forEach((l) => l.classList.remove('drop-here'));
      // The row never left its place in the page while it was held (it was
      // only drawn under the pointer), so a cancel just drops the gap.
      const toList = d.slot.parentElement;
      const toIndex = Array.from(toList.children)
        .filter((el) => el === d.slot || (el.matches(opts.row) && el !== d.row))
        .indexOf(d.slot);
      if (commit) d.slot.replaceWith(d.row);
      else d.slot.remove();
      d.row.classList.remove('is-lifted');
      d.row.style.width = '';
      d.row.style.left = '';
      d.row.style.top = '';
      if (commit && (toList !== d.fromList || toIndex !== d.fromIndex)) {
        opts.onDrop(d.row, d.fromList, d.fromIndex, toList, toIndex);
      }
    }

    document.addEventListener('pointerdown', start);
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', (ev) => {
      if (drag && ev.pointerId === drag.pointerId) finish(true);
    });
    document.addEventListener('pointercancel', () => finish(false));
    document.addEventListener('keydown', (ev) => {
      if (drag && ev.key === 'Escape') {
        ev.preventDefault();
        finish(false);
      }
    });
    return { get dragging() { return !!(drag && drag.lifted); } };
  }

  // ---- History ----------------------------------------------------------------

  /**
   * The page's own History rows, newest first, each with what it changed
   * and, for the newest row of each target that is not undone, Undo.
   * [rows] are wording_log rows (lib/wording.js); [describe] turns one into
   * { what, detail }; [targetOf] names what a row changed, so only the
   * newest change to each thing can be undone (an older one would throw the
   * later away).
   */
  function renderHistory(box, { rows, describe, targetOf, onUndo, empty }) {
    clear(box);
    if (!rows.length) {
      box.appendChild(h('p', { class: 'muted-note' }, empty));
      return;
    }
    const newest = new Map();
    rows.forEach((row) => {
      if (!newest.has(targetOf(row))) newest.set(targetOf(row), row.id);
    });
    const list = h('div', { class: 'hlist' });
    rows.forEach((row) => {
      const said = describe(row);
      let action = null;
      if (row.undoneBy) action = h('span', { class: 'badge muted' }, 'Undone');
      else if (newest.get(targetOf(row)) === row.id) action = button('Undo', () => onUndo(row), 'btn small');
      list.appendChild(h('div', { class: 'hrow' + (row.undoneBy ? ' undone' : '') },
        h('div', { class: 'when' }, fmtTime(row.at)),
        h('div', null, h('div', { class: 'what' }, said.what, row.undoOf ? ' (undo)' : ''), said.detail || null),
        h('div', null, action)));
    });
    box.appendChild(list);
  }

  window.ContentKit = {
    EDITION,
    h,
    append,
    $,
    clear,
    button,
    glyph,
    gripIcon,
    autosize,
    resizeAll,
    textBox,
    showMessages,
    toast,
    debounce,
    fmtTime,
    announce,
    load,
    post,
    errorText,
    showStale,
    setReadOnly,
    savedMessage,
    banner,
    renderBanners,
    sortable,
    renderHistory,
  };
})();
