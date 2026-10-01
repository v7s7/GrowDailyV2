/**
 * The Habit ideas page: Add Habit's single habit ideas and its ready-made
 * plans, edited in one draft and published together. The draft is
 * wording/ideas_rules.js's (draftFrom): every idea as the editor holds it,
 * the hidden built-ins too, and every plan, in the order phones show them.
 * Publish sends the parts that changed; the server checks them with the
 * same rules and stores only what differs from the app's built-in lists.
 *
 * A plain file served as it is (see lib/ideas_page.js for why no page
 * script lives inside a template literal). Needs rules.js and
 * ideas_rules.js (window.IdeasRules) loaded first.
 *
 * No em dash anywhere in this file, including comments.
 */
(function () {
  'use strict';

  const R = window.IdeasRules;

  // The edition of the page's styles this script is written for: the
  // --ideas-styles value in lib/ideas_page.js.
  const EDITION = '1';
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const state = {
    data: null, // GET /api/ideas: builtIn, stored, fingerprint, log, phones
    saved: null, // the draft the stored edits make: { ideas, plans, notes }
    draft: null, // { ideas, plans }, as edited
    tab: 'ideas',
    filter: { type: 'all', category: 'all', query: '' },
    selected: null, // the id of the idea in the editor
    saving: false,
    stale: null, // the server's words when a publish was refused as out of date
    serverErrors: [],
    check: null,
  };

  // Called after every edit: each keeps one part of the editor in step.
  let editorUpdaters = [];
  let planUpdaters = [];

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
    if (Array.isArray(child)) child.forEach((c) => append(el, c));
    else el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
  }

  function $(id) {
    return document.getElementById(id);
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
    return el;
  }

  function clone(v) {
    return JSON.parse(JSON.stringify(v));
  }

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3400);
  }

  function banner(kind, bold, rest) {
    return h('div', { class: 'banner ' + kind }, h('div', { class: 'grow' }, bold ? h('b', null, bold + ' ') : null, rest));
  }

  function fmtTime(iso) {
    if (!iso) return 'just now';
    const d = new Date(iso);
    const pad = (n) => String(n).padStart(2, '0');
    return d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear() + ', ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  // Digits typed on an Arabic keyboard read as the same number as 0 to 9.
  const EASTERN_DIGITS = ['٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹'];
  function westernDigits(text) {
    return String(text).replace(/[٠-٩۰-۹]/g, (d) => {
      for (const set of EASTERN_DIGITS) {
        const i = set.indexOf(d);
        if (i >= 0) return String(i);
      }
      return d;
    });
  }

  function norm(v) {
    return String(v == null ? '' : v).replace(/\r\n?/g, '\n').trim();
  }

  // ---- The data ---------------------------------------------------------------

  function builtIn() {
    return state.data.builtIn;
  }

  function lists() {
    return { ideas: builtIn().ideas, plans: builtIn().plans };
  }

  function builtInIdea(id) {
    return (builtIn().ideas || []).find((i) => i.id === id) || null;
  }

  function builtInPlan(id) {
    return (builtIn().plans || []).find((p) => p.id === id) || null;
  }

  function savedIdea(id) {
    return state.saved.ideas ? state.saved.ideas.find((r) => r.id === id) || null : null;
  }

  function savedPlan(id) {
    return state.saved.plans ? state.saved.plans.find((r) => r.id === id) || null : null;
  }

  function rowById(id) {
    return state.draft.ideas ? state.draft.ideas.find((r) => r.id === id) || null : null;
  }

  function ideasDirty() {
    return !!state.draft.ideas && !R.same(state.draft.ideas, state.saved.ideas);
  }

  function plansDirty() {
    return !!state.draft.plans && !R.same(state.draft.plans, state.saved.plans);
  }

  /** How many things differ from what is published: rows changed, added or
   *  deleted, plus one for each list whose order moved. */
  function unsavedCount() {
    let n = 0;
    const count = (draftRows, savedRows) => {
      if (!draftRows) return;
      const savedById = new Map(savedRows.map((r) => [r.id, r]));
      const draftIds = new Set(draftRows.map((r) => r.id));
      for (const row of draftRows) {
        const s = savedById.get(row.id);
        if (!s || !R.same(row, s)) n++;
      }
      for (const s of savedRows) if (!draftIds.has(s.id)) n++;
      const a = draftRows.map((r) => r.id).filter((id) => savedById.has(id));
      const b = savedRows.map((r) => r.id).filter((id) => draftIds.has(id));
      if (!R.same(a, b)) n++;
    };
    count(state.draft.ideas, state.saved.ideas || []);
    count(state.draft.plans, state.saved.plans || []);
    return n;
  }

  /** The draft checked, both parts, as it stands. */
  function checkNow() {
    const d = {};
    if (state.draft.ideas) d.ideas = state.draft.ideas;
    if (state.draft.plans) d.plans = state.draft.plans;
    state.check = R.checkDraft(lists(), d);
  }

  function problemsOf(tab, id) {
    return state.check.problems.filter((p) => p.tab === tab && p.id === id);
  }

  /** Whether a built-in idea row differs from the app's own idea. */
  function ideaEditedFields(row) {
    const base = builtInIdea(row.id);
    if (!base) return [];
    return R.TEXT_FIELDS.filter((f) => !R.same(R.storedValue(row, f), R.builtInValue(base, f)));
  }

  function ideaDiffers(row) {
    const base = builtInIdea(row.id);
    if (!base) return false;
    return ideaEditedFields(row).length > 0 || row.shown === false || row.featured !== base.featured;
  }

  function planEditedFields(row) {
    const base = builtInPlan(row.id);
    if (!base) return [];
    return R.PLAN_TEXT_FIELDS.filter((f) => norm(row[f]) !== norm(base[f]));
  }

  // ---- Small controls ------------------------------------------------------------

  function button(label, onClick, cls, extra) {
    return h('button', Object.assign({ type: 'button', class: cls || 'btn', onclick: onClick }, extra || {}), label);
  }

  /** A switch; [isOn] reads, [setOn] writes. */
  function switchControl(label, isOn, setOn, opts) {
    const box = h('input', { type: 'checkbox', 'aria-label': label });
    box.checked = isOn();
    if (opts && opts.disabled) box.disabled = true;
    box.addEventListener('click', (ev) => ev.stopPropagation());
    box.addEventListener('change', () => setOn(box.checked));
    const text = h('span', null, opts && opts.text ? opts.text(box.checked) : '');
    const wrap = h('label', { class: 'switch', title: (opts && opts.title) || label, onclick: (ev) => ev.stopPropagation() }, box, h('span', { class: 'track' }), text);
    wrap.sync = () => {
      box.checked = isOn();
      if (opts && opts.text) text.textContent = opts.text(box.checked);
    };
    return wrap;
  }

  function showMessages(box, problems) {
    clear(box);
    problems.filter((p) => p.level === 'error').forEach((p) => box.appendChild(h('div', { class: 'err' }, p.say || p.text)));
    problems.filter((p) => p.level === 'warning').forEach((p) => box.appendChild(h('div', { class: 'wrn' }, p.say || p.text)));
  }

  // ---- Banners -------------------------------------------------------------------

  function renderBanners() {
    const box = clear($('banners'));
    const edition = getComputedStyle(document.documentElement).getPropertyValue('--ideas-styles').trim().replace(/['"]/g, '');
    if (edition !== EDITION) {
      box.appendChild(banner('danger', 'This page was updated, but the admin tool is still running the copy from before.',
        ['Stop it (Ctrl-C in its Terminal window), start it again with ', h('code', null, 'npm start'), ', then reload this page.']));
    }
    if (state.data && state.data.phones === 'closed') {
      box.appendChild(banner('danger', 'Phones cannot read these edits yet.',
        ['The database rule that lets them read wording/live has not been deployed. From the repo folder: ',
          h('code', null, 'firebase deploy --only firestore:rules')]));
    }
    if (state.stale) {
      const b = h('div', { class: 'banner danger' },
        h('div', { class: 'grow' }, h('b', null, 'Not published. '), state.stale),
        button('Reload the page', () => location.reload(), 'btn small'));
      box.appendChild(b);
    }
  }

  // ---- Tabs ------------------------------------------------------------------------

  function tabsBar() {
    const ideasCount = state.draft.ideas ? state.draft.ideas.filter((r) => r.shown).length : 0;
    const plansCount = state.draft.plans ? state.draft.plans.filter((r) => r.shown).length : 0;
    const tab = (id, label, count) => h('button', {
      type: 'button',
      role: 'tab',
      'aria-selected': String(state.tab === id),
      onclick: () => {
        state.tab = id;
        render();
      },
    }, label, h('span', { class: 'count' }, count + ' shown'));
    return h('div', { class: 'tabs', role: 'tablist', 'aria-label': 'What to edit' },
      tab('ideas', 'Habits', ideasCount),
      tab('plans', 'Plans', plansCount));
  }

  // ---- Habits: filters and the list -----------------------------------------------------

  function matchesFilter(row) {
    const f = state.filter;
    if (f.type !== 'all' && row.type !== f.type) return false;
    if (f.category !== 'all' && row.category !== f.category) return false;
    const q = f.query.trim().toLowerCase();
    if (!q) return true;
    return [row.id, row.nameAr, row.nameEn, row.shortAr, row.shortEn].some((t) => String(t || '').toLowerCase().includes(q));
  }

  function visibleRows() {
    return state.draft.ideas.filter(matchesFilter);
  }

  function toolbar() {
    const typeSeg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Build or quit' },
      [['all', 'All'], ['build', 'Build'], ['quit', 'Quit']].map(([id, label]) => button(label, () => {
        state.filter.type = id;
        renderIdeasTab();
      }, '', { 'aria-pressed': String(state.filter.type === id) })));
    const search = h('input', { type: 'search', placeholder: 'Search the ideas, Arabic or English', 'aria-label': 'Search the ideas', value: state.filter.query });
    search.addEventListener('input', () => {
      state.filter.query = search.value;
      renderList();
    });
    const inType = state.draft.ideas.filter((r) => state.filter.type === 'all' || r.type === state.filter.type);
    const chip = (id, label) => {
      const n = id === 'all' ? inType.length : inType.filter((r) => r.category === id).length;
      return h('button', {
        type: 'button',
        class: 'chip',
        'aria-pressed': String(state.filter.category === id),
        onclick: () => {
          state.filter.category = id;
          renderIdeasTab();
        },
      }, label, h('span', { class: 'n' }, n));
    };
    return h('div', { class: 'toolbar' },
      typeSeg,
      search,
      button('New idea', newIdea, 'btn primary small', { id: 'newIdeaBtn' }),
      h('div', { class: 'toolbar-row2' },
        chip('all', 'Every category'),
        R.CATEGORIES.map((c) => chip(c.id, c.en))));
  }

  const rowEls = new Map();

  function listRow(row, i, visible) {
    const base = builtInIdea(row.id);
    const at = visible.indexOf(row);
    const probs = problemsOf('ideas', row.id);
    const saved = savedIdea(row.id);
    const cat = R.categoryOf(row.category);
    const up = button('↑', (ev) => {
      ev.stopPropagation();
      moveIdea(row.id, -1);
    }, 'icon-only', { 'aria-label': 'Move ' + (row.nameEn || row.id) + ' up', title: 'Move up' });
    const down = button('↓', (ev) => {
      ev.stopPropagation();
      moveIdea(row.id, 1);
    }, 'icon-only', { 'aria-label': 'Move ' + (row.nameEn || row.id) + ' down', title: 'Move down' });
    up.disabled = at <= 0;
    down.disabled = at < 0 || at >= visible.length - 1;
    const star = button(row.featured ? '★' : '☆', (ev) => {
      ev.stopPropagation();
      row.featured = !row.featured;
      afterListChange(row.id);
    }, 'star', {
      'aria-pressed': String(row.featured),
      'aria-label': (row.featured ? 'Stop showing ' : 'Show ') + (row.nameEn || row.id) + ' first in the app',
      title: row.featured ? 'Starred: shown first in its list in the app. Click to unstar.' : 'Click to star it: shown first in its list in the app.',
    });
    const ends = h('div', { class: 'i-ends' }, star);
    if (row.added) {
      ends.appendChild(h('span', { class: 'badge added', title: 'Made on this page. Delete it in the editor to take it off.' }, 'Added'));
    } else {
      ends.appendChild(switchControl('Show ' + (row.nameEn || row.id), () => row.shown, (on) => {
        row.shown = on;
        afterListChange(row.id);
      }, { title: 'Shown on phones' }));
    }
    const badges = [];
    if (!row.shown) badges.push(h('span', { class: 'badge hidden' }, 'Hidden'));
    if (base && ideaEditedFields(row).length) badges.push(h('span', { class: 'badge edited' }, 'Edited'));
    if (!saved || !R.same(saved, row)) badges.push(h('span', { class: 'badge unsaved' }, 'Unsaved'));
    if (probs.some((p) => p.level === 'error')) badges.push(h('span', { class: 'badge error' }, 'Fix'));
    const el = h('div', {
      class: 'i-row' + (state.selected === row.id ? ' sel' : '') + (row.shown ? '' : ' off'),
      'data-id': row.id,
      tabindex: '0',
      role: 'button',
      'aria-label': 'Edit ' + (row.nameEn || row.nameAr || row.id),
      onclick: () => select(row.id),
      onkeydown: (ev) => {
        if ((ev.key === 'Enter' || ev.key === ' ') && ev.target === el) {
          ev.preventDefault();
          select(row.id);
        }
      },
    },
    h('div', { class: 'i-moves' }, up, h('span', { class: 'pos' }, i + 1), down),
    h('div', { class: 'i-names' },
      h('span', { class: 't-ar', lang: 'ar', dir: 'rtl' }, norm(row.nameAr) || '(no Arabic name yet)'),
      h('span', { class: 't-en' }, norm(row.nameEn) || '(no English name yet)'),
      h('div', { class: 'i-meta' },
        h('span', { class: 'cat' }, cat.en),
        h('span', null, row.type === 'quit' ? 'Quit' : 'Build'),
        h('span', null, '· ' + R.describeOften(row.often)),
        badges)),
    ends);
    rowEls.set(row.id, el);
    return el;
  }

  function renderList() {
    const box = $('ideaList');
    if (!box) return;
    clear(box);
    rowEls.clear();
    const visible = visibleRows();
    if (!visible.length) {
      box.appendChild(h('div', { class: 'i-empty' }, state.draft.ideas.length ? 'No idea matches the filters.' : 'No ideas yet.'));
    }
    state.draft.ideas.forEach((row, i) => {
      if (matchesFilter(row)) box.appendChild(listRow(row, i, visible));
    });
    const note = $('listNote');
    if (note) {
      const filtered = visible.length !== state.draft.ideas.length;
      note.textContent = filtered
        ? 'Showing ' + visible.length + ' of ' + state.draft.ideas.length + '. The arrows move an idea past the next one shown here; the numbers are its place in the whole list.'
        : state.draft.ideas.length + ' ideas, in the order phones show them. Hidden ones keep their place and come back to it.';
    }
  }

  /** Redraws one list row in place, keeping the list's scroll and focus. */
  function refreshRow(id) {
    const old = rowEls.get(id);
    const row = rowById(id);
    if (!old || !row) return;
    const visible = visibleRows();
    const el = listRow(row, state.draft.ideas.indexOf(row), visible);
    old.replaceWith(el);
  }

  function moveIdea(id, dir) {
    const visible = visibleRows();
    const row = rowById(id);
    const at = visible.indexOf(row);
    const other = visible[at + dir];
    if (!row || !other) return;
    const list = state.draft.ideas;
    list.splice(list.indexOf(row), 1);
    const to = list.indexOf(other) + (dir > 0 ? 1 : 0);
    list.splice(to, 0, row);
    afterStructure();
    const el = rowEls.get(id);
    if (el) {
      el.scrollIntoView({ block: 'nearest' });
      const btn = el.querySelectorAll('.i-moves button')[dir < 0 ? 0 : 1];
      if (btn && !btn.disabled) btn.focus();
      else el.focus();
    }
  }

  function select(id) {
    state.selected = id;
    rowEls.forEach((el, rowId) => el.classList.toggle('sel', rowId === id));
    renderEditor();
  }

  function newIdea() {
    const taken = new Set(state.draft.ideas.map((r) => r.id));
    const id = R.newIdeaId(taken);
    const row = R.blankRow(id, state.filter.type === 'quit' ? 'quit' : 'build',
      state.filter.category === 'all' ? 'custom' : state.filter.category);
    state.draft.ideas.unshift(row);
    state.filter.query = '';
    state.selected = id;
    renderIdeasTab();
    updateDock();
    updateTabs();
    const first = document.querySelector('#ideaEditor input[data-field="nameAr"]');
    if (first) first.focus();
    const el = rowEls.get(id);
    if (el) el.scrollIntoView({ block: 'nearest' });
  }

  function deleteIdea(id) {
    const row = rowById(id);
    if (!row || !row.added) return;
    const published = !!savedIdea(id);
    if (published && !window.confirm('Delete “' + (norm(row.nameEn) || norm(row.nameAr) || id) + '”? Phones stop showing it once you publish.')) return;
    const i = state.draft.ideas.indexOf(row);
    state.draft.ideas.splice(i, 1);
    const visible = visibleRows();
    const next = state.draft.ideas[i] && matchesFilter(state.draft.ideas[i]) ? state.draft.ideas[i] : visible[0];
    state.selected = next ? next.id : null;
    renderIdeasTab();
    updateDock();
    updateTabs();
  }

  function resetIdea(id) {
    const row = rowById(id);
    const base = builtInIdea(id);
    if (!row || !base) return;
    const fresh = R.rowFromIdea(base, { added: false, shown: true, featured: base.featured });
    Object.keys(fresh).forEach((k) => { row[k] = fresh[k]; });
    afterStructure();
  }

  // ---- Habits: the editor ------------------------------------------------------------

  /** A text box for one word field: counter, the app's words, its messages. */
  function wordField(row, field, opts) {
    const lang = /Ar$/.test(field) ? 'ar' : 'en';
    const max = R.LIMITS[field];
    const props = {
      class: (opts.multiline ? 'ta' : 'inp') + ' t-' + lang,
      lang,
      dir: lang === 'ar' ? 'rtl' : 'ltr',
      'data-field': field,
      spellcheck: lang === 'en' ? 'true' : 'false',
      'aria-label': cap(R.FIELD_LABEL[field]),
      placeholder: opts.placeholder || '',
      autocomplete: 'off',
    };
    const input = opts.multiline ? h('textarea', Object.assign({ rows: 3 }, props)) : h('input', Object.assign({ type: 'text' }, props));
    input.value = row[field] || '';
    input.addEventListener('input', () => {
      row[field] = input.value;
      onIdeaEdit(row.id);
    });
    const cnt = h('span', { class: 'cnt' });
    const mark = h('span');
    const msgs = h('div', { class: 'msgs' });
    const builtin = h('div', { class: 'builtin' });
    editorUpdaters.push(() => {
      const len = norm(row[field]).length;
      cnt.textContent = len + ' / ' + max;
      cnt.classList.toggle('over', len > max);
      const probs = problemsOf('ideas', row.id).filter((p) => p.field === field);
      showMessages(msgs, probs);
      input.classList.toggle('has-error', probs.some((p) => p.level === 'error'));
      if (document.activeElement !== input && input.value !== (row[field] || '')) input.value = row[field] || '';
      fieldBuiltIn(row, field, mark, builtin, () => {
        input.value = row[field] || '';
      });
    });
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, opts.label), mark, h('span', { class: 'grow' }), cnt),
      input, builtin, msgs);
  }

  /** For a built-in idea: a dot when [field] differs from the app's, and its
   *  words with a way back. [after] puts the box back to the row's value. */
  function fieldBuiltIn(row, field, mark, box, after) {
    clear(mark);
    clear(box);
    const base = builtInIdea(row.id);
    if (!base) return;
    if (R.same(R.storedValue(row, field), R.builtInValue(base, field))) return;
    mark.appendChild(h('span', { class: 'dot', title: 'Changed from the app’s' }));
    const app = R.rowFromIdea(base, {})[field];
    const shown = Array.isArray(app) ? app.join(' / ') : field === 'often' ? R.describeOften(app)
      : field === 'reminder' ? R.describeReminder(app) : field === 'limit' ? R.describeLimit(app)
        : field === 'timesPerDay' ? (app > 1 ? app + ' times' : 'once')
          : field === 'category' ? R.categoryOf(app).en : (app || 'none');
    box.appendChild(document.createTextNode('The app’s: ' + shown + ' '));
    box.appendChild(button('Use the app’s', () => {
      row[field] = clone(app);
      after();
      onIdeaEdit(row.id, true);
    }, 'link-btn'));
  }

  function waysField(row) {
    const box = h('div', { class: 'pair' });
    const msgs = h('div', { class: 'msgs' });
    const marks = {};
    const builtins = {};
    function column(field) {
      const lang = field === 'waysAr' ? 'ar' : 'en';
      const list = h('div', { class: 'ways' });
      marks[field] = h('span');
      builtins[field] = h('div', { class: 'builtin' });
      function draw() {
        clear(list);
        row[field].forEach((w, i) => {
          const input = h('input', {
            type: 'text',
            class: 'inp t-' + lang,
            lang,
            dir: lang === 'ar' ? 'rtl' : 'ltr',
            'data-field': field,
            'aria-label': 'Way ' + (i + 1) + ' in ' + (lang === 'ar' ? 'Arabic' : 'English'),
            autocomplete: 'off',
          });
          input.value = w;
          input.addEventListener('input', () => {
            row[field][i] = input.value;
            onIdeaEdit(row.id);
          });
          const remove = button('✕', () => {
            row[field].splice(i, 1);
            draw();
            onIdeaEdit(row.id, true);
          }, 'icon-only', { 'aria-label': 'Remove way ' + (i + 1), title: 'Remove this way' });
          list.appendChild(h('div', { class: 'way' }, h('span', { class: 'num' }, i + 1), input, remove));
        });
      }
      draw();
      column.redraw = column.redraw || [];
      column.redraw.push(draw);
      return h('div', { class: 'fld' },
        h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, lang === 'ar' ? 'Arabic' : 'English'), marks[field],
          h('span', { class: 'grow' }), h('span', { class: 'cnt' }, R.LIMITS.way + ' each at most')),
        list, builtins[field]);
    }
    box.appendChild(column('waysAr'));
    box.appendChild(column('waysEn'));
    const redrawAll = () => column.redraw.forEach((d) => d());
    const add = button('Add a way', () => {
      row.waysAr.push('');
      row.waysEn.push('');
      redrawAll();
      onIdeaEdit(row.id, true);
    }, 'btn small');
    editorUpdaters.push(() => {
      const probs = problemsOf('ideas', row.id).filter((p) => p.field === 'waysAr' || p.field === 'waysEn');
      showMessages(msgs, probs);
      add.disabled = Math.max(row.waysAr.length, row.waysEn.length) >= 4;
      fieldBuiltIn(row, 'waysAr', marks.waysAr, builtins.waysAr, redrawAll);
      fieldBuiltIn(row, 'waysEn', marks.waysEn, builtins.waysEn, redrawAll);
    });
    return h('div', { class: 'sect' },
      h('h4', null, 'Easy ways to start'),
      box,
      h('div', { class: 'row-line' }, add, h('span', { class: 'hint' }, 'Two ways, the same in both languages. Each one short enough to read at a glance.')),
      msgs);
  }

  function selectBox(label, options, value, onChange) {
    const s = h('select', { class: 'sel-box', 'aria-label': label });
    options.forEach(([v, text]) => s.appendChild(h('option', { value: v }, text)));
    s.value = value;
    s.addEventListener('change', () => onChange(s.value));
    return s;
  }

  /** The schedule: every day, times a week, or set days. */
  function scheduleSection(row) {
    const kindOf = () => {
      const o = R.parseOften(row.often);
      if (String(row.often || '').startsWith('days:')) return 'days';
      return o ? o.kind : 'daily';
    };
    const kind = selectBox('How often', [['daily', 'Every day'], ['weekly', 'Times a week, any days'], ['days', 'On set days']], kindOf(), (v) => {
      if (v === 'daily') row.often = 'daily';
      if (v === 'weekly') row.often = 'weekly:3';
      if (v === 'days') row.often = 'days:1,4';
      fitSchedule(row);
      onIdeaEdit(row.id, true);
    });
    const times = selectBox('Times a week', [1, 2, 3, 4, 5, 6].map((n) => [String(n), n === 1 ? 'once a week' : n + ' times a week']), '3', (v) => {
      row.often = 'weekly:' + v;
      onIdeaEdit(row.id, true);
    });
    const days = h('div', { class: 'day-chips', role: 'group', 'aria-label': 'Days' }, R.WEEKDAYS.map((d) => {
      const chip = h('button', { type: 'button', class: 'chip', 'aria-pressed': 'false', title: d.en }, d.en.slice(0, 3));
      chip.addEventListener('click', () => {
        const o = R.parseOften(row.often);
        const set = new Set(o && o.kind === 'days' ? o.days : []);
        if (set.has(d.n)) set.delete(d.n);
        else set.add(d.n);
        row.often = 'days:' + [...set].sort((a, b) => a - b).join(',');
        onIdeaEdit(row.id, true);
      });
      editorUpdaters.push(() => {
        const o = R.parseOften(row.often);
        chip.setAttribute('aria-pressed', String(!!(o && o.kind === 'days' && o.days.includes(d.n))));
      });
      return chip;
    }));
    const timesBox = h('input', { type: 'text', class: 'inp short', inputmode: 'numeric', dir: 'ltr', 'aria-label': 'Times a day', autocomplete: 'off', 'data-field': 'timesPerDay' });
    timesBox.value = String(row.timesPerDay);
    timesBox.addEventListener('input', () => {
      const raw = westernDigits(timesBox.value.trim());
      row.timesPerDay = raw === '' ? 1 : /^[0-9]{1,2}$/.test(raw) ? Number(raw) : raw;
      onIdeaEdit(row.id);
    });
    const timesLine = h('div', { class: 'row-line' }, h('span', { class: 'unit' }, 'Times a day'), timesBox, h('span', { class: 'unit' }, '1 is once; up to 12 (water, say)'));
    const timesOff = h('div', { class: 'hint' }, 'Times a day is only for a daily habit to build.');
    const markOften = h('span');
    const markTimes = h('span');
    const builtinOften = h('div', { class: 'builtin' });
    const builtinTimes = h('div', { class: 'builtin' });
    const msgs = h('div', { class: 'msgs' });
    editorUpdaters.push(() => {
      const k = kindOf();
      kind.value = k;
      const o = R.parseOften(row.often);
      times.hidden = k !== 'weekly';
      if (o && o.kind === 'weekly') times.value = String(o.times);
      days.hidden = k !== 'days';
      const canTimes = row.type === 'build' && row.often === 'daily';
      timesLine.hidden = !canTimes;
      timesOff.hidden = canTimes;
      if (document.activeElement !== timesBox) timesBox.value = String(row.timesPerDay);
      const probs = problemsOf('ideas', row.id).filter((p) => p.field === 'often' || p.field === 'timesPerDay');
      timesBox.classList.toggle('has-error', probs.some((p) => p.field === 'timesPerDay' && p.level === 'error'));
      showMessages(msgs, probs);
      fieldBuiltIn(row, 'often', markOften, builtinOften, () => {});
      fieldBuiltIn(row, 'timesPerDay', markTimes, builtinTimes, () => {
        timesBox.value = String(row.timesPerDay);
      });
    });
    return h('div', { class: 'sect' },
      h('h4', null, 'Suggested schedule'),
      h('div', { class: 'fld' },
        h('div', { class: 'row-line' }, kind, times, days, markOften),
        builtinOften),
      h('div', { class: 'fld' }, h('div', { class: 'row-line' }, timesLine, markTimes), timesOff, builtinTimes),
      msgs);
  }

  /** Times a day and a limit only go with some schedules and types; the
   *  editor drops them when the habit no longer fits, as the app would. */
  function fitSchedule(row) {
    if (!(row.type === 'build' && row.often === 'daily')) row.timesPerDay = 1;
    if (row.type !== 'quit') row.limit = null;
  }

  function reminderSection(row) {
    const kindOf = () => (String(row.reminder || '').startsWith('prayer:') ? 'prayer' : String(row.reminder || '').startsWith('time:') ? 'time' : 'none');
    const kind = selectBox('Reminder', [['none', 'No reminder'], ['prayer', 'After a prayer'], ['time', 'At a time']], kindOf(), (v) => {
      row.reminder = v === 'none' ? '' : v === 'prayer' ? 'prayer:fajr' : 'time:08:00';
      onIdeaEdit(row.id, true);
    });
    const prayer = selectBox('Prayer', R.PRAYERS.map((p) => [p.id, 'After ' + p.en]), 'fajr', (v) => {
      row.reminder = 'prayer:' + v;
      onIdeaEdit(row.id, true);
    });
    const time = h('input', { type: 'text', class: 'inp short', dir: 'ltr', placeholder: '07:30', 'aria-label': 'Reminder time, 24-hour', autocomplete: 'off', 'data-field': 'reminder' });
    time.addEventListener('input', () => {
      row.reminder = 'time:' + westernDigits(time.value.trim());
      onIdeaEdit(row.id);
    });
    const mark = h('span');
    const builtin = h('div', { class: 'builtin' });
    const msgs = h('div', { class: 'msgs' });
    editorUpdaters.push(() => {
      const k = kindOf();
      kind.value = k;
      prayer.hidden = k !== 'prayer';
      time.hidden = k !== 'time';
      if (k === 'prayer') prayer.value = row.reminder.slice(7);
      if (k === 'time' && document.activeElement !== time) time.value = row.reminder.slice(5);
      const probs = problemsOf('ideas', row.id).filter((p) => p.field === 'reminder');
      time.classList.toggle('has-error', probs.some((p) => p.level === 'error'));
      showMessages(msgs, probs);
      fieldBuiltIn(row, 'reminder', mark, builtin, () => {});
    });
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, 'Suggested reminder'), mark),
      h('div', { class: 'row-line' }, kind, prayer, time, h('span', { class: 'unit' }, 'A time is 24-hour, like 07:30 or 21:00.')),
      builtin, msgs);
  }

  function limitSection(row) {
    const kind = selectBox('Quit fully or keep a limit', [['full', 'Quit fully'], ['limit', 'Keep under a daily limit']], row.limit ? 'limit' : 'full', (v) => {
      row.limit = v === 'full' ? null : { amount: 1, unit: 'times' };
      onIdeaEdit(row.id, true);
    });
    const amount = h('input', { type: 'text', class: 'inp short', inputmode: 'numeric', dir: 'ltr', 'aria-label': 'Limit amount', autocomplete: 'off', 'data-field': 'limit' });
    amount.addEventListener('input', () => {
      const raw = westernDigits(amount.value.trim());
      row.limit = { amount: /^[0-9]{1,4}$/.test(raw) ? Number(raw) : raw, unit: row.limit ? row.limit.unit : 'times' };
      onIdeaEdit(row.id);
    });
    const unit = selectBox('Limit unit', R.LIMIT_UNITS.map((u) => [u.id, u.en]), 'times', (v) => {
      row.limit = { amount: row.limit ? row.limit.amount : 1, unit: v };
      onIdeaEdit(row.id, true);
    });
    const mark = h('span');
    const builtin = h('div', { class: 'builtin' });
    const msgs = h('div', { class: 'msgs' });
    const wrap = h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, 'Quit fully or a limit'), mark),
      h('div', { class: 'row-line' }, kind, amount, unit, h('span', { class: 'unit' }, 'a day')),
      builtin, msgs);
    editorUpdaters.push(() => {
      wrap.hidden = row.type !== 'quit';
      kind.value = row.limit ? 'limit' : 'full';
      amount.hidden = !row.limit;
      unit.hidden = !row.limit;
      if (row.limit) {
        if (document.activeElement !== amount) amount.value = String(row.limit.amount);
        unit.value = row.limit.unit;
      }
      const probs = problemsOf('ideas', row.id).filter((p) => p.field === 'limit');
      amount.classList.toggle('has-error', probs.some((p) => p.level === 'error'));
      showMessages(msgs, probs);
      fieldBuiltIn(row, 'limit', mark, builtin, () => {});
    });
    return wrap;
  }

  /** The card as the list in Add Habit shows it, in both languages. */
  function previewSection(row) {
    const box = h('div', { class: 'pv' });
    const meta = h('div', { class: 'pv-meta' });
    function card(lang) {
      const isAr = lang === 'ar';
      const name = norm(isAr ? row.nameAr : row.nameEn);
      const short = norm(isAr ? row.shortAr : row.shortEn);
      const cat = R.categoryOf(row.category);
      return h('div', { class: 'pv-screen', dir: isAr ? 'rtl' : 'ltr', lang },
        h('div', { class: 'pv-label' }, isAr ? cat.ar : cat.en.toUpperCase()),
        h('div', { class: 'pv-card' },
          h('div', { class: 'pv-tile' + (row.type === 'quit' ? ' quit' : ''), 'aria-hidden': 'true' }, (isAr ? cat.ar : cat.en).charAt(0)),
          h('div', null,
            h('span', { class: 'pv-name' + (name ? '' : ' pv-empty') }, name || (isAr ? 'الاسم' : 'Name')),
            h('span', { class: 'pv-short' + (short ? '' : ' pv-empty') }, short || (isAr ? 'سطر البطاقة' : 'The card line'))),
          row.featured ? h('span', { class: 'pv-star', 'aria-label': 'Featured' }, '★') : h('span')));
    }
    editorUpdaters.push(() => {
      clear(box);
      box.appendChild(card('ar'));
      box.appendChild(card('en'));
      const bits = [R.describeOften(row.often)];
      if (row.type === 'build' && row.often === 'daily' && row.timesPerDay > 1) bits.push(row.timesPerDay + ' times a day');
      if (row.type === 'quit') bits.push(R.describeLimit(row.limit && Number.isInteger(row.limit.amount) ? row.limit : null));
      bits.push(R.describeReminder(row.reminder));
      if (!row.shown) bits.push('hidden, phones do not show it');
      meta.textContent = bits.join(' · ');
    });
    return h('div', { class: 'sect' }, h('h4', null, 'The card, as phones show it'), box, meta);
  }

  function renderEditor() {
    const box = $('ideaEditor');
    if (!box) return;
    editorUpdaters = [];
    clear(box);
    const row = rowById(state.selected);
    if (!row) {
      box.appendChild(h('div', { class: 'ed-empty' }, 'Pick an idea on the left to edit it, or make a new one.'));
      return;
    }
    const base = builtInIdea(row.id);
    const badges = h('span', { class: 'row-line' });
    const head = h('div', { class: 'ed-head' },
      h('div', null, h('h3', null, norm(row.nameEn) || norm(row.nameAr) || 'New idea'), h('code', null, row.id)),
      badges,
      h('span', { class: 'grow' }));
    const featured = switchControl('Starred', () => row.featured, (on) => {
      row.featured = on;
      afterListChange(row.id);
    }, { text: (on) => (on ? 'Starred' : 'Not starred'), title: 'A starred idea is shown first in its list in the app' });
    head.appendChild(featured);
    editorUpdaters.push(() => featured.sync());
    if (base) {
      const shown = switchControl('Shown', () => row.shown, (on) => {
        row.shown = on;
        afterListChange(row.id);
      }, { text: (on) => (on ? 'Shown' : 'Hidden'), title: 'Shown on phones' });
      head.appendChild(shown);
      editorUpdaters.push(() => shown.sync());
      const reset = button('Reset to app’s', () => resetIdea(row.id), 'btn small', { title: 'Every field, the star and the switch back to the app’s own' });
      head.appendChild(reset);
      editorUpdaters.push(() => {
        reset.disabled = !ideaDiffers(row);
      });
    } else {
      head.appendChild(button('Delete', () => deleteIdea(row.id), 'btn small danger-soft', { title: 'Delete this idea. Only ideas made on this page can be deleted.' }));
    }
    editorUpdaters.push(() => {
      clear(badges);
      if (row.added) badges.appendChild(h('span', { class: 'badge added' }, 'Added'));
      else badges.appendChild(h('span', { class: 'badge muted' }, 'From the app'));
      if (base && ideaEditedFields(row).length) badges.appendChild(h('span', { class: 'badge edited' }, 'Edited'));
      if (!row.shown) badges.appendChild(h('span', { class: 'badge hidden' }, 'Hidden'));
      const s = savedIdea(row.id);
      if (!s || !R.same(s, row)) badges.appendChild(h('span', { class: 'badge unsaved' }, 'Unsaved'));
    });

    const general = h('div', { class: 'msgs' });
    editorUpdaters.push(() => showMessages(general, problemsOf('ideas', row.id).filter((p) => !p.field || p.field === 'type' || p.field === 'featured')));

    const typeSeg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Build or quit' },
      [['build', 'Build'], ['quit', 'Quit']].map(([id, label]) => {
        const b = button(label, () => {
          row.type = id;
          fitSchedule(row);
          onIdeaEdit(row.id, true);
        }, '', { title: base ? 'A built-in idea keeps its type' : '' });
        b.disabled = !!base;
        editorUpdaters.push(() => b.setAttribute('aria-pressed', String(row.type === id)));
        return b;
      }));
    const category = selectBox('Category', R.CATEGORIES.map((c) => [c.id, c.en + '  ' + c.ar]), row.category, (v) => {
      row.category = v;
      onIdeaEdit(row.id, true);
    });
    const catMark = h('span');
    const catBuiltin = h('div', { class: 'builtin' });
    const catMsgs = h('div', { class: 'msgs' });
    editorUpdaters.push(() => {
      category.value = row.category;
      showMessages(catMsgs, problemsOf('ideas', row.id).filter((p) => p.field === 'category'));
      fieldBuiltIn(row, 'category', catMark, catBuiltin, () => {});
    });

    const body = h('div', { class: 'ed-body' },
      general,
      h('div', { class: 'sect' },
        h('h4', null, 'Kind'),
        h('div', { class: 'row-line' }, typeSeg, category, catMark),
        catBuiltin, catMsgs),
      previewSection(row),
      h('div', { class: 'sect' },
        h('h4', null, 'Name, as the habit is saved'),
        h('div', { class: 'pair' },
          wordField(row, 'nameAr', { label: 'Arabic' }),
          wordField(row, 'nameEn', { label: 'English' }))),
      h('div', { class: 'sect' },
        h('h4', null, 'The card line: why it is worth it'),
        h('div', { class: 'pair' },
          wordField(row, 'shortAr', { label: 'Arabic' }),
          wordField(row, 'shortEn', { label: 'English' }))),
      h('div', { class: 'sect' },
        h('h4', null, 'The benefit, in full'),
        h('div', { class: 'pair' },
          wordField(row, 'benefitAr', { label: 'Arabic', multiline: true }),
          wordField(row, 'benefitEn', { label: 'English', multiline: true })),
        h('div', { class: 'hint' }, 'For a faith habit, the hadith or ayah itself; otherwise one or two plain sentences. No medical promises.')),
      h('div', { class: 'sect' },
        h('h4', null, 'Source, for a hadith or ayah only'),
        h('div', { class: 'pair' },
          wordField(row, 'sourceAr', { label: 'Arabic', placeholder: 'متفق عليه' }),
          wordField(row, 'sourceEn', { label: 'English', placeholder: 'Bukhari and Muslim' }))),
      waysField(row),
      scheduleSection(row),
      h('div', { class: 'sect' }, h('h4', null, 'Reminder and limit'), reminderSection(row), limitSection(row)));
    box.appendChild(head);
    box.appendChild(body);
    editorUpdaters.forEach((u) => u());
  }

  // ---- After an edit -------------------------------------------------------------------

  /** A field of the idea in the editor changed: the editor's parts, its
   *  list row and the dock follow, without redrawing the box being typed in. */
  function onIdeaEdit(id) {
    checkNow();
    editorUpdaters.forEach((u) => u());
    refreshRow(id);
    updateDock();
    updateTabs();
  }

  /** A row's switch or star changed from the list or the editor's head. */
  function afterListChange(id) {
    checkNow();
    refreshRow(id);
    if (state.selected === id) editorUpdaters.forEach((u) => u());
    updateDock();
    updateTabs();
  }

  /** The list's order or membership changed: everything redraws. */
  function afterStructure() {
    checkNow();
    renderList();
    renderEditor();
    updateDock();
    updateTabs();
  }

  function updateTabs() {
    const old = document.querySelector('#viewIdeas .tabs');
    if (old) old.replaceWith(tabsBar());
  }

  // ---- Habits: the tab ---------------------------------------------------------------

  function ideasNotes() {
    const out = [];
    const b = builtIn();
    if (b.ideasMissing) {
      out.push(banner('warn', b.ideasFile + ' is not in the repo yet.',
        'The built-in ideas are read from that file, the same one the app ships. Until it is there, there are no ideas to show or edit here; anything already published for them is kept as it is. The Plans tab works meanwhile.'));
    } else if (b.ideasError) {
      out.push(banner('danger', 'The built-in ideas could not be read.', [b.ideasError, ' Nothing about the ideas can be published until the file reads; anything already published is kept as it is.']));
    }
    if (b.ideaSkipped && b.ideaSkipped.length) {
      out.push(banner('warn', b.ideaSkipped.length + (b.ideaSkipped.length === 1 ? ' entry' : ' entries') + ' in the file cannot be read, so the app skips ' + (b.ideaSkipped.length === 1 ? 'it' : 'them') + ':',
        h('ul', null, b.ideaSkipped.map((s) => h('li', null, s.label + ': ' + s.reasons.join(', ') + '.')))));
    }
    if (state.saved.notes && state.saved.notes.length) {
      out.push(banner('warn', 'Some published edits do nothing on phones:',
        h('ul', null, state.saved.notes.map((n) => h('li', null, n)), h('li', null, 'They are left out and go away at the next publish.'))));
    }
    if (b.ideaNotes && b.ideaNotes.length) {
      out.push(h('details', { class: 'notes' },
        h('summary', null, b.ideaNotes.length + ' note' + (b.ideaNotes.length === 1 ? '' : 's') + ' on the built-in file (sizes and copy rules). Phones still show these ideas.'),
        h('ul', null, b.ideaNotes.map((n) => h('li', null, n)))));
    }
    return out;
  }

  function renderIdeasTab() {
    const root = $('tabBody');
    if (!root || state.tab !== 'ideas') return;
    clear(root);
    append(root, ideasNotes());
    if (!state.draft.ideas) return;
    if (state.selected && !rowById(state.selected)) state.selected = null;
    if (!state.selected) {
      const first = visibleRows()[0];
      state.selected = first ? first.id : null;
    }
    root.appendChild(toolbar());
    root.appendChild(h('div', { class: 'igrid' },
      h('div', null,
        h('div', { class: 'i-list', id: 'ideaList' }),
        h('p', { class: 'list-note', id: 'listNote' })),
      h('aside', { class: 'editor', id: 'ideaEditor', 'aria-label': 'The idea being edited' })));
    checkNow();
    renderList();
    renderEditor();
  }

  // ---- Plans -----------------------------------------------------------------------------

  function planWordField(row, field, label, multiline) {
    const lang = /Ar$/.test(field) ? 'ar' : 'en';
    const max = R.LIMITS['plan' + field.charAt(0).toUpperCase() + field.slice(1)];
    const props = {
      class: (multiline ? 'ta' : 'inp') + ' t-' + lang,
      lang,
      dir: lang === 'ar' ? 'rtl' : 'ltr',
      'data-field': field,
      'aria-label': label,
      autocomplete: 'off',
      spellcheck: lang === 'en' ? 'true' : 'false',
    };
    const input = multiline ? h('textarea', Object.assign({ rows: 2 }, props)) : h('input', Object.assign({ type: 'text' }, props));
    input.value = row[field] || '';
    input.addEventListener('input', () => {
      row[field] = input.value;
      onPlanEdit();
    });
    const cnt = h('span', { class: 'cnt' });
    const mark = h('span');
    const builtin = h('div', { class: 'builtin' });
    const msgs = h('div', { class: 'msgs' });
    planUpdaters.push(() => {
      const len = norm(row[field]).length;
      cnt.textContent = len + ' / ' + max;
      cnt.classList.toggle('over', len > max);
      const probs = problemsOf('plans', row.id).filter((p) => p.field === field);
      showMessages(msgs, probs);
      input.classList.toggle('has-error', probs.some((p) => p.level === 'error'));
      if (document.activeElement !== input && input.value !== (row[field] || '')) input.value = row[field] || '';
      clear(mark);
      clear(builtin);
      const base = builtInPlan(row.id);
      if (base && norm(row[field]) !== norm(base[field])) {
        mark.appendChild(h('span', { class: 'dot', title: 'Changed from the app’s' }));
        builtin.appendChild(document.createTextNode('The app’s: ' + base[field] + ' '));
        builtin.appendChild(button('Use the app’s', () => {
          row[field] = base[field];
          input.value = base[field];
          onPlanEdit();
        }, 'link-btn'));
      }
    });
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, label), mark, h('span', { class: 'grow' }), cnt),
      input, builtin, msgs);
  }

  function planCard(row, i) {
    const base = builtInPlan(row.id);
    const list = state.draft.plans;
    const up = button('↑', () => movePlan(i, i - 1), 'icon-only', { 'aria-label': 'Move ' + base.nameEn + ' up', title: 'Move up' });
    const down = button('↓', () => movePlan(i, i + 1), 'icon-only', { 'aria-label': 'Move ' + base.nameEn + ' down', title: 'Move down' });
    up.disabled = i === 0;
    down.disabled = i === list.length - 1;
    const badges = h('span', { class: 'row-line' });
    const shown = switchControl('Show ' + base.nameEn, () => row.shown, (on) => {
      row.shown = on;
      renderPlansTab();
      afterPlanStructure();
    }, { text: (on) => (on ? 'Shown' : 'Hidden'), title: 'Shown on phones' });
    const reset = button('Reset to app’s', () => {
      row.shown = true;
      R.PLAN_TEXT_FIELDS.forEach((f) => { row[f] = base[f]; });
      renderPlansTab();
      afterPlanStructure();
    }, 'btn small', { title: 'The words and the switch back to the app’s own' });
    const habits = base.catalogIds.map((id) => {
      const n = builtIn().habits && builtIn().habits[id];
      return n
        ? h('span', { class: 'p-habit', title: id }, h('span', { class: 't-ar', lang: 'ar', dir: 'rtl' }, n.nameAr), ' · ', n.nameEn)
        : h('span', { class: 'p-habit missing', title: 'Not in the app’s preset catalog' }, id);
    });
    const card = h('div', { class: 'p-card' + (row.shown ? '' : ' off'), 'data-id': row.id },
      h('div', { class: 'p-head' },
        h('div', { class: 'i-moves', style: 'flex-direction: row' }, up, down),
        h('span', { class: 'pos' }, i + 1),
        h('span', { class: 'nm' }, base.nameEn, h('span', { class: 't-ar', lang: 'ar', dir: 'rtl' }, base.nameAr)),
        h('code', null, row.id),
        badges,
        h('span', { class: 'grow' }),
        shown,
        reset),
      h('div', { class: 'p-body' },
        h('div', { class: 'pair' },
          planWordField(row, 'nameAr', 'Name in Arabic', false),
          planWordField(row, 'nameEn', 'Name in English', false)),
        h('div', { class: 'pair' },
          planWordField(row, 'descAr', 'Description in Arabic', true),
          planWordField(row, 'descEn', 'Description in English', true)),
        h('div', { class: 'fld' },
          h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, 'Its habits'), h('span', { class: 'hint' }, 'Set in the app’s code; read only here.')),
          h('div', { class: 'p-habits' }, habits))));
    planUpdaters.push(() => {
      clear(badges);
      if (!row.shown) badges.appendChild(h('span', { class: 'badge hidden' }, 'Hidden'));
      if (planEditedFields(row).length) badges.appendChild(h('span', { class: 'badge edited' }, 'Edited'));
      const s = savedPlan(row.id);
      if (!s || !R.same(s, row)) badges.appendChild(h('span', { class: 'badge unsaved' }, 'Unsaved'));
      if (problemsOf('plans', row.id).some((p) => p.level === 'error')) badges.appendChild(h('span', { class: 'badge error' }, 'Fix'));
      reset.disabled = row.shown && planEditedFields(row).length === 0;
      card.classList.toggle('off', !row.shown);
    });
    return card;
  }

  function movePlan(from, to) {
    const list = state.draft.plans;
    if (to < 0 || to >= list.length) return;
    const [row] = list.splice(from, 1);
    list.splice(to, 0, row);
    renderPlansTab();
    afterPlanStructure();
    const card = document.querySelector('.p-card[data-id="' + row.id + '"]');
    if (card) {
      card.scrollIntoView({ block: 'nearest' });
      const btn = card.querySelectorAll('.p-head .i-moves button')[to < from ? 0 : 1];
      if (btn && !btn.disabled) btn.focus();
    }
  }

  function onPlanEdit() {
    checkNow();
    planUpdaters.forEach((u) => u());
    updateDock();
    updateTabs();
  }

  function afterPlanStructure() {
    checkNow();
    planUpdaters.forEach((u) => u());
    updateDock();
    updateTabs();
  }

  function renderPlansTab() {
    const root = $('tabBody');
    if (!root || state.tab !== 'plans') return;
    clear(root);
    planUpdaters = [];
    const b = builtIn();
    if (!b.plans) {
      root.appendChild(banner('danger', 'The plans could not be read from the app’s code.',
        [b.plansError || 'Unknown reason.', ' Nothing about the plans can be published until habit_plans.dart reads again; anything already published is kept as it is.']));
      return;
    }
    root.appendChild(h('p', { class: 'muted-note', style: 'margin-bottom: 12px' },
      'The ready-made plans in Add Habit, in the order phones show them. Change a plan’s name and description, move it, or switch it off. Its habits are set in the app’s code (' + b.plansFile + ').'));
    const list = h('div', { class: 'p-list' });
    state.draft.plans.forEach((row, i) => list.appendChild(planCard(row, i)));
    root.appendChild(list);
    checkNow();
    planUpdaters.forEach((u) => u());
  }

  // ---- History ---------------------------------------------------------------------------

  function historyCard() {
    const rows = state.data.log || [];
    const body = h('div', { class: 'card-body' });
    if (!rows.length) {
      body.appendChild(h('p', { class: 'muted-note' }, 'Nothing published from this page yet.'));
    } else {
      const list = h('div', { class: 'hlist' });
      const newest = rows.find((r) => !r.undoneBy) || null;
      rows.forEach((row) => {
        let action = null;
        if (row.undoneBy) action = h('span', { class: 'badge muted' }, 'Undone');
        else if (newest && newest.id === row.id) action = button('Undo', () => undo(row), 'btn small');
        list.appendChild(h('div', { class: 'hrow' + (row.undoneBy ? ' undone' : '') },
          h('div', { class: 'when' }, fmtTime(row.at)),
          h('div', null,
            h('div', { class: 'what' }, 'Habit ideas and plans', row.undoOf ? ' (undo)' : ''),
            h('div', { class: 'detail' }, R.describeChange(row.before, row.after))),
          h('div', null, action)));
      });
      body.appendChild(list);
    }
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', null, 'History'),
        h('span', { class: 'sub' }, 'Publishes from this page, newest first. Undo puts back what the newest one changed. Every change to the app’s text is under ',
          h('a', { href: '/wording#history' }, 'Wording, History'), '.')),
      body);
  }

  // ---- The dock ---------------------------------------------------------------------------

  function updateDock() {
    const dock = $('dock');
    if (!dock) return;
    clear(dock);
    const n = unsavedCount();
    const check = state.check;
    const errors = state.serverErrors.length ? state.serverErrors.map((t) => ({ level: 'error', text: t })) : check.problems.filter((p) => p.level === 'error');
    // Warnings only about what is about to be published: one on words that
    // are already live is old news, and so is a list-wide one with nothing
    // to publish.
    const warnings = n === 0 ? [] : check.problems.filter((p) => p.level === 'warning' && (!p.id || isUnsaved(p)));
    const status = h('div', { class: 'grow' },
      state.saving ? 'Publishing…' : n === 0 ? 'Nothing to publish: this is what phones show.' : (n === 1 ? '1 unpublished change.' : n + ' unpublished changes.'),
      n > 0 && !state.saving ? h('span', { class: 'hint' }, ' ', h('kbd', null, '⌘S'), ' publishes.') : null);
    const shown = errors.slice(0, 4).concat(warnings.slice(0, Math.max(0, 4 - errors.length)));
    if (shown.length) {
      const probs = h('div', { class: 'problems' });
      shown.forEach((p) => {
        const line = p.id ? button(p.text, () => goTo(p), '') : h('span', null, p.text);
        probs.appendChild(h('div', { class: p.level === 'error' ? 'err' : 'wrn' }, line));
      });
      const more = errors.length + warnings.length - shown.length;
      if (more > 0) probs.appendChild(h('div', { class: 'hint' }, 'And ' + more + ' more.'));
      status.appendChild(probs);
    }
    const discard = button('Discard', discardAll, 'btn', { id: 'discardBtn' });
    const publish = button('Publish', publishNow, 'btn primary', { id: 'publishBtn' });
    discard.disabled = state.saving || n === 0;
    publish.disabled = state.saving || !!state.stale || n === 0 || errors.length > 0;
    dock.appendChild(status);
    dock.appendChild(discard);
    dock.appendChild(publish);
    // The editor beside the list ends above the dock, however tall it is.
    document.documentElement.style.setProperty('--dock-h', dock.offsetHeight + 'px');
  }

  /** Whether a problem is about something not yet published (a warning on
   *  untouched published text is old news and not repeated in the dock). */
  function isUnsaved(p) {
    if (p.tab === 'ideas') {
      const row = rowById(p.id);
      const s = savedIdea(p.id);
      return !!row && (!s || !R.same(s, row));
    }
    const row = state.draft.plans && state.draft.plans.find((r) => r.id === p.id);
    const s = savedPlan(p.id);
    return !!row && (!s || !R.same(s, row));
  }

  function goTo(p) {
    if (p.tab === 'plans') {
      state.tab = 'plans';
      render();
      const card = document.querySelector('.p-card[data-id="' + p.id + '"]');
      const input = card && p.field ? card.querySelector('[data-field="' + p.field + '"]') : null;
      if (card) card.scrollIntoView({ block: 'center', behavior: 'smooth' });
      if (input) input.focus({ preventScroll: true });
      return;
    }
    state.tab = 'ideas';
    const row = rowById(p.id);
    if (row && !matchesFilter(row)) state.filter = { type: 'all', category: 'all', query: '' };
    state.selected = p.id;
    render();
    const el = rowEls.get(p.id);
    if (el) el.scrollIntoView({ block: 'nearest' });
    const input = p.field ? document.querySelector('#ideaEditor [data-field="' + p.field + '"]') : null;
    if (input) {
      input.scrollIntoView({ block: 'center', behavior: 'smooth' });
      input.focus({ preventScroll: true });
    }
  }

  function discardAll() {
    if (!window.confirm('Throw away every change on this page that is not published?')) return;
    state.draft = { ideas: state.saved.ideas ? clone(state.saved.ideas) : null, plans: state.saved.plans ? clone(state.saved.plans) : null };
    state.serverErrors = [];
    render();
  }

  // ---- The server -------------------------------------------------------------------------

  async function post(url, payload) {
    let res;
    try {
      res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    } catch (e) {
      return { ok: false, status: 0, body: { error: 'Could not reach the admin tool. Is it still running?' } };
    }
    let body = {};
    try {
      body = await res.json();
    } catch (e) {
      body = { error: 'The admin tool answered ' + res.status + '.' };
    }
    return { ok: res.ok && body.ok !== false, status: res.status, body };
  }

  function savedMessage(first) {
    return state.data && state.data.phones === 'closed'
      ? first + ' Phones will see it once the database rule is deployed.'
      : first + ' Open apps show it within seconds.';
  }

  async function publishNow() {
    if (state.saving || state.stale || unsavedCount() === 0) return;
    checkNow();
    if (state.check.errors.length) {
      const first = state.check.problems.find((p) => p.level === 'error');
      if (first && first.id) goTo(first);
      toast(state.check.errors[0]);
      return;
    }
    const draft = {};
    if (ideasDirty()) draft.ideas = state.draft.ideas;
    if (plansDirty()) draft.plans = state.draft.plans;
    state.saving = true;
    state.serverErrors = [];
    updateDock();
    const res = await post('/api/ideas', {
      draft,
      // What this page was built from, so a page left open while the ideas
      // were published elsewhere, or while the app's own lists changed in
      // the repo, is refused instead of writing over either.
      base: state.data.stored,
      builtInFingerprint: state.data.fingerprint,
    });
    state.saving = false;
    if (res.status === 409) {
      state.stale = res.body.error || 'This page is out of date. Reload it.';
      renderBanners();
      updateDock();
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }
    if (!res.ok) {
      state.serverErrors = (res.body.errors && res.body.errors.length) ? res.body.errors : [res.body.error || 'The publish did not go through.'];
      updateDock();
      return;
    }
    takeData(Object.assign({}, res.body.data, { phones: state.data.phones }), true);
    render();
    toast(savedMessage(res.body.changed ? 'Published.' : 'Nothing new to publish.'));
  }

  async function undo(row) {
    if (state.saving) return;
    if (unsavedCount() > 0 && !window.confirm('Undo throws away the changes on this page that are not published yet. Go on?')) return;
    state.saving = true;
    updateDock();
    const res = await post('/api/ideas/undo', { id: row.id });
    state.saving = false;
    if (!res.ok) {
      updateDock();
      toast(res.body.error || 'The undo did not go through.');
      return;
    }
    takeData(Object.assign({}, res.body.data, { phones: state.data.phones }), true);
    render();
    toast(savedMessage('Undone.'));
  }

  // ---- The page ---------------------------------------------------------------------------

  function render() {
    const root = clear($('viewIdeas'));
    root.appendChild(tabsBar());
    root.appendChild(h('div', { id: 'tabBody' }));
    root.appendChild(historyCard());
    root.appendChild(h('div', { class: 'dock', id: 'dock' }));
    renderBanners();
    checkNow();
    if (state.tab === 'ideas') renderIdeasTab();
    else renderPlansTab();
    updateDock();
  }

  function takeData(data, keepSelection) {
    state.data = data;
    state.saved = R.draftFrom({ ideas: data.builtIn.ideas, plans: data.builtIn.plans }, data.stored);
    state.draft = {
      ideas: state.saved.ideas ? clone(state.saved.ideas) : null,
      plans: state.saved.plans ? clone(state.saved.plans) : null,
    };
    state.serverErrors = [];
    if (!keepSelection) state.selected = null;
  }

  function cap(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  async function start() {
    window.addEventListener('beforeunload', (ev) => {
      if (state.draft && unsavedCount() > 0) {
        ev.preventDefault();
        ev.returnValue = '';
      }
    });
    document.addEventListener('keydown', (ev) => {
      if ((ev.metaKey || ev.ctrlKey) && !ev.shiftKey && !ev.altKey && String(ev.key).toLowerCase() === 's') {
        ev.preventDefault();
        publishNow();
      }
    });
    let body;
    try {
      const res = await fetch('/api/ideas');
      body = await res.json();
      if (!res.ok) throw new Error(body.error || 'The admin tool answered ' + res.status + '.');
    } catch (e) {
      clear($('viewIdeas')).appendChild(banner('danger', 'Could not load the habit ideas.', e.message));
      return;
    }
    takeData(body, false);
    render();
  }

  start();
})();
