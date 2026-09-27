/**
 * The FAQ page, in the browser.
 *
 * Aziz, 2026-09-26: "make the faq ... all in the admin change firebase,
 * online change not hard code". The page holds the whole FAQ as a draft
 * (every group with its heading, every question with its answer, in both
 * languages), lets it be edited, dragged, taken off and added to, and
 * saves it in one go. The server turns the draft into per-question edits
 * (faqEditsFromDraft in wording/content_rules.js), so a question left as
 * the app wrote it keeps following the app's code.
 *
 * The phone on the right draws the draft through the same resolveFaq the
 * app uses (content_edits.dart), so it shows what phones will show.
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
  const FIELDS = [
    { key: 'qAr', part: 'q', lang: 'ar', label: 'Question, Arabic', max: C.MAX_QUESTION_LENGTH },
    { key: 'qEn', part: 'q', lang: 'en', label: 'Question, English', max: C.MAX_QUESTION_LENGTH },
    { key: 'aAr', part: 'a', lang: 'ar', label: 'Answer, Arabic', max: C.MAX_ANSWER_LENGTH },
    { key: 'aEn', part: 'a', lang: 'en', label: 'Answer, English', max: C.MAX_ANSWER_LENGTH },
  ];

  const state = {
    data: null,
    // The app's own FAQ, from the catalog: { groups, items }.
    builtIn: null,
    // The saved edits, read the way phones read them.
    saved: null,
    // The FAQ as edited on this page: { groups: [{ id, title: {ar, en},
    // items: [{ id, q: {ar, en}, a: {ar, en} }] }] }.
    draft: null,
    savedJson: '',
    savedItems: new Map(),
    // Fields whose built-in text changed in the code after they were
    // edited, and which were looked at and kept ("id:qAr", "group:id:ar").
    checked: new Set(),
    open: new Set(),
    query: '',
    previewLang: 'ar',
    previewOpen: null,
    saving: false,
  };

  let builtInItem = new Map();
  let builtInGroup = new Map();
  const norm = (t) => R.normalizeText(t);
  // Holds an empty heading's line in the preview. Built, never typed: it is invisible.
  const NBSP = String.fromCharCode(0xA0);

  // ---- The draft ------------------------------------------------------------

  function draftFrom(edits) {
    return {
      groups: C.resolveFaq(state.builtIn, edits).map((s) => ({
        id: s.id,
        title: { ar: s.title.ar, en: s.title.en },
        items: s.items.map((i) => ({ id: i.id, q: { ar: i.q.ar, en: i.q.en }, a: { ar: i.a.ar, en: i.a.en } })),
      })),
    };
  }

  /** The draft with every text as it would be stored, for comparing. */
  function normalized(draft) {
    return {
      groups: draft.groups.map((g) => ({
        id: g.id,
        title: { ar: norm(g.title.ar), en: norm(g.title.en) },
        items: g.items.map(normItem),
      })),
    };
  }

  function normItem(i) {
    return { id: i.id, q: { ar: norm(i.q.ar), en: norm(i.q.en) }, a: { ar: norm(i.a.ar), en: norm(i.a.en) } };
  }

  function resetDraft() {
    state.draft = draftFrom(state.saved);
    state.savedJson = C.canonical(normalized(state.draft));
    state.savedItems = new Map();
    state.draft.groups.forEach((g) => g.items.forEach((i) => state.savedItems.set(i.id, C.canonical(normItem(i)))));
    state.checked = new Set();
  }

  function dirty() {
    return !!state.draft && (C.canonical(normalized(state.draft)) !== state.savedJson || state.checked.size > 0);
  }

  function allItems() {
    const out = [];
    state.draft.groups.forEach((g) => g.items.forEach((i) => out.push(i)));
    return out;
  }

  function groupOf(item) {
    return state.draft.groups.find((g) => g.items.includes(item));
  }

  function takenIds() {
    const taken = new Set(state.builtIn.items.map((i) => i.id));
    state.builtIn.groups.forEach((g) => taken.add(g.id));
    state.draft.groups.forEach((g) => {
      taken.add(g.id);
      g.items.forEach((i) => taken.add(i.id));
    });
    return taken;
  }

  function fieldOf(item, f) {
    return item[f.part][f.lang];
  }

  function stringText(key, lang) {
    const live = state.data.live.strings[lang] || {};
    if (Object.prototype.hasOwnProperty.call(live, key)) return live[key];
    const entry = state.data.catalog.strings.find((s) => s.key === key);
    return entry ? entry[lang] : key;
  }

  function titleOf(g) {
    return norm(g.title.en) || norm(g.title.ar) || '(a group with no heading yet)';
  }

  // ---- What each question is --------------------------------------------------

  /** Added in the app's code after the last save, and so placed by the app. */
  function isNewInApp(itemId) {
    const saved = state.saved;
    if (!saved || !saved.order || !builtInItem.has(itemId)) return false;
    if (saved.hidden.includes(itemId)) return false;
    return !saved.order.some((g) => g.items.includes(itemId));
  }

  function itemState(item) {
    const b = builtInItem.get(item.id);
    const savedText = (state.saved && state.saved.text[item.id]) || {};
    const bases = state.data.admin.faqBases.items[item.id] || {};
    const edited = b ? FIELDS.filter((f) => norm(fieldOf(item, f)) !== norm(b[f.key])) : [];
    const drift = b
      ? FIELDS.filter((f) => typeof savedText[f.key] === 'string' &&
        typeof bases[f.key] === 'string' && bases[f.key] !== b[f.key] &&
        norm(fieldOf(item, f)) === norm(savedText[f.key]) &&
        !state.checked.has(item.id + ':' + f.key))
      : [];
    return {
      builtIn: b || null,
      added: !b,
      edited,
      drift,
      fresh: isNewInApp(item.id),
      unsaved: state.savedItems.get(item.id) !== C.canonical(normItem(item)),
    };
  }

  function headingDrift(g) {
    const b = builtInGroup.get(g.id);
    if (!b) return [];
    const saved = (state.saved && state.saved.groups[g.id]) || {};
    const bases = state.data.admin.faqBases.groups[g.id] || {};
    return LANGS.filter((lang) => typeof saved[lang] === 'string' && typeof bases[lang] === 'string' &&
      bases[lang] !== b[lang] && norm(g.title[lang]) === norm(saved[lang]) &&
      !state.checked.has('group:' + g.id + ':' + lang));
  }

  function badgesFor(item) {
    const st = itemState(item);
    return h('span', { class: 'q-badges' },
      st.added ? h('span', { class: 'badge added', title: 'Added on this page. Not in the app’s code.' }, 'Added') : null,
      st.fresh ? h('span', { class: 'badge fresh', title: 'Added to the app after you last saved the FAQ. Phones already show it, right here.' }, 'New in the app') : null,
      st.edited.length ? h('span', {
        class: 'badge edited',
        title: 'Your words, not the app’s: ' + st.edited.map((f) => f.label.toLowerCase()).join(', '),
      }, 'Edited') : null,
      st.drift.length ? h('span', { class: 'badge drift', title: 'The app’s own text changed after you edited it. Open it to compare.' }, 'Changed in code') : null,
      st.unsaved ? h('span', { class: 'badge unsaved' }, 'Unsaved') : null);
  }

  // ---- Drawing the page ---------------------------------------------------------

  function renderBanners() {
    const extra = [];
    const drifting = allItems().filter((i) => itemState(i).drift.length).length +
      state.draft.groups.filter((g) => headingDrift(g).length).length;
    if (drifting) {
      extra.push(K.banner('warn', drifting + (drifting === 1 ? ' question was' : ' questions were') + ' changed in the app’s code after you edited ' + (drifting === 1 ? 'it.' : 'them.'),
        'Phones still show your words. Open the ones marked "Changed in code" to compare, then keep yours or take the new text.'));
    }
    const fresh = allItems().filter((i) => isNewInApp(i.id)).length;
    if (fresh) {
      extra.push(K.banner('info', fresh + (fresh === 1 ? ' question is' : ' questions are') + ' new in the app since your last save.',
        'Phones already show ' + (fresh === 1 ? 'it' : 'them') + ' where the app put ' + (fresh === 1 ? 'it' : 'them') + ', marked "New in the app" below. Move or edit ' + (fresh === 1 ? 'it' : 'them') + ' like any other.'));
    }
    K.renderBanners($('banners'), state.data, extra);
  }

  function render() {
    renderBanners();
    const app = clear($('faqApp'));
    app.appendChild(toolbar());
    const editor = h('div', { class: 'editor-col' });
    state.draft.groups.forEach((g, gi) => editor.appendChild(groupCard(g, gi)));
    editor.appendChild(h('div', { class: 'g-foot', style: 'padding: 0 0 var(--s4)' },
      button('+ Add a group', addGroup, 'btn')));
    const removed = removedCard();
    if (removed) editor.appendChild(removed);
    editor.appendChild(historyCard());
    app.appendChild(h('div', { class: 'cgrid' }, editor, previewCol()));
    applySearch();
    updateDock();
    renderPreview();
    requestAnimationFrame(() => K.resizeAll(app));
  }

  function toolbar() {
    const search = h('input', {
      type: 'search',
      value: state.query,
      dir: 'auto',
      placeholder: 'Search the questions and answers, Arabic or English',
      autocomplete: 'off',
      spellcheck: 'false',
      'aria-label': 'Search the FAQ',
    });
    search.addEventListener('input', K.debounce(() => {
      state.query = search.value;
      applySearch();
    }, 90));
    const count = allItems().length;
    const asBuiltIn = C.canonical(normalized(state.draft)) === C.canonical(normalized(draftFrom(null)));
    return h('div', { class: 'toolbar' },
      search,
      h('span', { class: 'muted-note' }, count + (count === 1 ? ' question' : ' questions') + ' in ' + state.draft.groups.filter((g) => g.items.length).length + ' groups'),
      h('span', { class: 'sep' }),
      button('Open all', () => {
        allItems().forEach((i) => state.open.add(i.id));
        render();
      }, 'btn small'),
      button('Close all', () => {
        state.open.clear();
        render();
      }, 'btn small'),
      h('span', { class: 'sep' }),
      button('Back to the app’s own FAQ', backToBuiltIn, 'btn small', {
        disabled: asBuiltIn,
        title: asBuiltIn ? 'This is the app’s own FAQ.' : 'Puts the app’s own FAQ back on this page. Nothing changes on phones until you Save.',
      }));
  }

  function groupCard(g, gi) {
    const b = builtInGroup.get(g.id) || null;
    const n = state.draft.groups.length;
    const drift = headingDrift(g);
    const edited = b && LANGS.some((lang) => norm(g.title[lang]) !== norm(b[lang]));
    const card = h('section', { class: 'card g-card', 'data-group': g.id });
    const count = g.items.length;
    card.appendChild(h('div', { class: 'g-head' },
      h('div', { class: 'g-moves' },
        button('↑', () => moveGroup(gi, -1), 'icon-only', { disabled: gi === 0, title: 'Move this group up', 'aria-label': 'Move this group up' }),
        button('↓', () => moveGroup(gi, 1), 'icon-only', { disabled: gi === n - 1, title: 'Move this group down', 'aria-label': 'Move this group down' })),
      headingField(g, 'ar', b),
      headingField(g, 'en', b),
      h('div', { class: 'g-side' },
        h('span', { class: 'badges' },
          !b ? h('span', { class: 'badge added' }, 'Added') : null,
          edited ? h('span', { class: 'badge edited' }, 'Heading edited') : null,
          drift.length ? h('span', { class: 'badge drift', title: 'The app’s own heading changed after you edited it.' }, 'Changed in code') : null),
        h('span', null, count + (count === 1 ? ' question' : ' questions')),
        count ? null : button('Remove group', () => removeGroup(gi), 'btn small danger-soft'))));
    if (drift.length) {
      card.appendChild(h('div', { class: 'card-body', style: 'padding-bottom: 0' }, drift.map((lang) =>
        driftNote('The app’s own ' + LANG_NAME[lang] + ' heading changed after you edited it.',
          state.data.admin.faqBases.groups[g.id][lang], b[lang], lang,
          () => {
            state.checked.add('group:' + g.id + ':' + lang);
            render();
          },
          () => {
            g.title[lang] = b[lang];
            render();
          }))));
    }
    const list = h('div', { class: 'q-list', 'data-group': g.id });
    g.items.forEach((item) => list.appendChild(questionRow(item)));
    if (!count) {
      list.appendChild(h('div', { class: 'q-empty' }, b
        ? 'No questions here, so phones do not show this group. Drag one in, or add one.'
        : 'No questions yet. Drag one in or add one; a group with none is not kept.'));
    }
    card.appendChild(list);
    card.appendChild(h('div', { class: 'g-foot' }, button('+ Add a question', () => addQuestion(g), 'btn small')));
    return card;
  }

  function headingField(g, lang, b) {
    const label = 'Heading, ' + LANG_NAME[lang];
    const msgs = h('div', { class: 'msgs' });
    const ta = K.textBox(lang, g.title[lang], label, (value) => {
      g.title[lang] = value;
      check();
      changed();
    });
    const useBuiltIn = b ? h('button', {
      type: 'button',
      class: 'link-btn',
      onclick: () => {
        ta.value = b[lang];
        ta.dispatchEvent(new Event('input'));
        ta.focus();
      },
    }, 'Use built-in') : null;
    function check() {
      const asBuilt = b && norm(ta.value) === norm(b[lang]);
      const result = g.items.length && !asBuilt ? C.checkField(label, lang, ta.value, C.MAX_HEADING_LENGTH) : { errors: [], warnings: [] };
      ta.classList.toggle('has-error', result.errors.length > 0);
      K.showMessages(msgs, result.errors, result.warnings);
      if (useBuiltIn) useBuiltIn.hidden = norm(ta.value) === norm(b[lang]);
    }
    check();
    return h('div', { class: 'g-title-' + lang },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, label), useBuiltIn), ta, msgs);
  }

  function questionRow(item) {
    const open = state.open.has(item.id);
    const row = h('article', { class: 'q-row' + (open ? ' open' : ''), 'data-item': item.id });
    const grip = h('button', {
      type: 'button',
      class: 'grip',
      title: 'Drag to move, to another group too',
      'aria-label': 'Drag to move this question',
    }, K.gripIcon());
    const line = h('div', { class: 'q-line', role: 'button', tabindex: '0', 'aria-expanded': open ? 'true' : 'false' },
      h('div', { class: 't-ar', lang: 'ar', dir: 'rtl' }, norm(item.q.ar) || '(no Arabic question yet)'),
      h('div', { class: 't-en', lang: 'en', dir: 'ltr' }, norm(item.q.en) || '(no English question yet)'),
      h('div', { class: 'ends' }, badgesFor(item), K.glyph('expand_more', 'chev')));
    line.addEventListener('click', () => toggle(item));
    line.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        toggle(item);
      }
    });
    const main = h('div', { class: 'q-main' }, line);
    if (open) main.appendChild(editorFor(item, row));
    row.appendChild(grip);
    row.appendChild(main);
    return row;
  }

  function rowOf(item) {
    return document.querySelector('.q-row[data-item="' + CSS.escape(item.id) + '"]');
  }

  function redrawRow(item) {
    const old = rowOf(item);
    if (!old) return;
    const fresh = questionRow(item);
    old.replaceWith(fresh);
    requestAnimationFrame(() => K.resizeAll(fresh));
    return fresh;
  }

  function toggle(item) {
    if (state.open.has(item.id)) state.open.delete(item.id);
    else state.open.add(item.id);
    const row = redrawRow(item);
    if (row && state.open.has(item.id)) {
      const first = row.querySelector('textarea');
      if (first) first.focus({ preventScroll: true });
    }
    applySearch();
  }

  function editorFor(item, row) {
    const st = itemState(item);
    const b = st.builtIn;
    const box = h('div', { class: 'q-edit' });
    st.drift.forEach((f) => {
      box.appendChild(driftNote('The app’s own ' + LANG_NAME[f.lang] + ' ' + (f.part === 'q' ? 'question' : 'answer') + ' changed after you edited it.',
        state.data.admin.faqBases.items[item.id][f.key], b[f.key], f.lang,
        () => {
          state.checked.add(item.id + ':' + f.key);
          redrawRow(item);
          changed();
        },
        () => {
          item[f.part][f.lang] = b[f.key];
          redrawRow(item);
          changed();
        }));
    });
    FIELDS.forEach((f) => box.appendChild(fieldEditor(item, f, b, row)));

    const g = groupOf(item);
    const gi = state.draft.groups.indexOf(g);
    const idx = g.items.indexOf(item);
    const lastGroup = state.draft.groups.length - 1;
    const select = h('select', { 'aria-label': 'Move to another group' },
      h('option', { value: '' }, 'Move to group…'),
      moveTargets(g).map((t) => h('option', { value: t.id }, t.label)));
    select.addEventListener('change', () => {
      if (select.value) moveToGroup(item, select.value);
    });
    box.appendChild(h('div', { class: 'q-foot' },
      select,
      button('Up', () => nudge(item, -1), 'btn small', { disabled: idx === 0 && gi === 0 }),
      button('Down', () => nudge(item, 1), 'btn small', { disabled: idx === g.items.length - 1 && gi === lastGroup }),
      h('span', { class: 'grow' }),
      h('code', { class: 'key', title: 'This question’s id. Edits are kept by it.' }, item.id),
      b
        ? button('Take off the FAQ', () => takeOff(item), 'btn small danger-soft', { title: 'Phones stop showing it. You can put it back from the list at the bottom.' })
        : button('Delete', () => deleteAdded(item), 'btn small danger-soft')));
    return box;
  }

  function fieldEditor(item, f, b, row) {
    const msgs = h('div', { class: 'msgs' });
    const ta = K.textBox(f.lang, fieldOf(item, f), f.label, (value) => {
      item[f.part][f.lang] = value;
      check();
      if (f.part === 'q') {
        const cell = row.querySelector('.q-line .t-' + f.lang);
        if (cell) cell.textContent = norm(value) || '(no ' + LANG_NAME[f.lang] + ' question yet)';
      }
      const ends = row.querySelector('.q-line .ends');
      if (ends) ends.replaceChild(badgesFor(item), ends.firstChild);
      changed();
    });
    ta.setAttribute('data-field', f.key);
    ta.addEventListener('keydown', (ev) => {
      if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') {
        ev.preventDefault();
        save();
      }
    });
    const useBuiltIn = b ? h('button', {
      type: 'button',
      class: 'link-btn',
      onclick: () => {
        ta.value = b[f.key];
        ta.dispatchEvent(new Event('input'));
        ta.focus();
      },
    }, 'Use built-in text') : null;
    function check() {
      // The app's own words, left as they are, are never a problem here:
      // the save stores nothing for them (faqEditsFromDraft).
      const asBuilt = b && norm(ta.value) === norm(b[f.key]);
      const result = asBuilt ? { errors: [], warnings: [] } : C.checkField(f.label, f.lang, ta.value, f.max);
      ta.classList.toggle('has-error', result.errors.length > 0);
      K.showMessages(msgs, result.errors, result.warnings);
      if (useBuiltIn) useBuiltIn.hidden = !!asBuilt;
    }
    check();
    return h('div', { class: 'fld' },
      h('div', { class: 'fld-head' }, h('span', { class: 'lab' }, f.label), useBuiltIn), ta, msgs);
  }

  function driftNote(said, was, now, lang, keep, take) {
    const dir = lang === 'ar' ? 'rtl' : 'ltr';
    return h('div', { class: 'drift-note full' },
      h('b', null, said), ' Phones still show your words.',
      h('span', { class: 'was' }, 'Before: ', h('span', { class: 't-' + lang, lang, dir }, was)),
      h('span', { class: 'was' }, 'Now: ', h('span', { class: 't-' + lang, lang, dir }, now)),
      h('div', { class: 'acts' },
        button('Keep my text', keep, 'link-btn'),
        button('Use the app’s new text', take, 'link-btn')));
  }

  function moveTargets(current) {
    const out = [];
    state.draft.groups.forEach((g) => {
      if (g !== current) out.push({ id: g.id, label: titleOf(g) });
    });
    state.builtIn.groups.forEach((b) => {
      if (!state.draft.groups.some((g) => g.id === b.id)) out.push({ id: b.id, label: b.en + ' (not shown now)' });
    });
    return out;
  }

  function removedCard() {
    const present = new Set(allItems().map((i) => i.id));
    const gone = state.builtIn.items.filter((i) => !present.has(i.id));
    if (!gone.length) return null;
    const body = h('div', { class: 'card-body' });
    gone.forEach((i) => body.appendChild(h('div', { class: 'removed-row' },
      h('div', { class: 't-ar', lang: 'ar', dir: 'rtl' }, i.qAr),
      h('div', { class: 't-en', lang: 'en', dir: 'ltr' }, i.qEn),
      button('Put back', () => putBack(i.id), 'btn small'))));
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', null, 'Taken off the FAQ'),
        h('span', { class: 'sub' }, gone.length + (gone.length === 1 ? ' question from the app is' : ' questions from the app are') + ' not shown. Put one back and it returns where the app had it.')),
      body);
  }

  function historyCard() {
    const rows = state.data.log.filter((r) => r.kind === 'faq');
    const body = h('div', { class: 'card-body' });
    K.renderHistory(body, {
      rows,
      describe: (row) => ({
        what: 'FAQ',
        detail: h('div', { class: 'detail' }, capital(C.describeFaqChange(state.builtIn, row.before, row.after)) || 'No change phones would see.'),
      }),
      targetOf: () => 'faq',
      onUndo: undo,
      empty: 'No FAQ saves yet.',
    });
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', null, 'History'),
        h('span', { class: 'sub' }, 'The latest FAQ saves, newest first. Every change to the app’s text is under ',
          h('a', { href: '/wording#history' }, 'Wording, History'), '.')),
      body);
  }

  function capital(text) {
    return text ? text.charAt(0).toUpperCase() + text.slice(1) + '.' : '';
  }

  // ---- The phone ------------------------------------------------------------

  function previewCol() {
    const seg = h('div', { class: 'seg', role: 'group', 'aria-label': 'Preview language' },
      button('عربي', () => setLang('ar'), state.previewLang === 'ar' ? 'on' : '', { lang: 'ar' }),
      button('English', () => setLang('en'), state.previewLang === 'en' ? 'on' : ''));
    return h('aside', { class: 'preview-col', 'aria-label': 'Preview' },
      h('div', { class: 'preview-tools' }, seg),
      h('div', { class: 'phone' }, h('div', { class: 'phone-screen', id: 'phoneScreen' })),
      h('p', { class: 'pv-note' }, 'Help & Support as phones will show it after Save. Tap a question to open it.'));
  }

  function setLang(lang) {
    state.previewLang = lang;
    document.querySelectorAll('.preview-tools .seg button').forEach((b, i) => b.classList.toggle('on', (i === 0) === (lang === 'ar')));
    renderPreview();
  }

  /** What phones will show: the draft's edits resolved the app's way when
   *  the draft can be saved, else the draft as it stands. */
  function previewGroups() {
    const check = C.faqEditsFromDraft(state.builtIn, state.draft);
    if (check.ok) return C.resolveFaq(state.builtIn, C.parseFaqEdits(check.edits));
    return state.draft.groups.filter((g) => g.items.length).map((g) => ({
      id: g.id,
      title: { ar: norm(g.title.ar), en: norm(g.title.en) },
      items: g.items.map(normItem),
    }));
  }

  function renderPreview() {
    const screen = $('phoneScreen');
    if (!screen) return;
    const lang = state.previewLang;
    const ar = lang === 'ar';
    const top = screen.scrollTop;
    screen.setAttribute('dir', ar ? 'rtl' : 'ltr');
    screen.setAttribute('lang', lang);
    clear(screen);
    screen.appendChild(h('div', { class: 'pv-status' }));
    screen.appendChild(h('div', { class: 'pv-bar' }, K.glyph(ar ? 'arrow_forward' : 'arrow_back'), stringText('helpSupportRowTitle', lang)));
    screen.appendChild(h('div', { class: 'pv-label' }, stringText('helpFaqSectionTitle', lang)));
    previewGroups().forEach((g) => {
      screen.appendChild(h('div', { class: 'pv-group' }, g.title[lang] || NBSP));
      const card = h('div', { class: 'pv-card' });
      g.items.forEach((i) => {
        const open = state.previewOpen === i.id;
        const q = h('button', { type: 'button', class: 'pv-q' + (open ? ' open' : '') },
          h('div', { class: 'row' }, h('span', { class: 'qt' }, i.q[lang] || '…'), K.glyph('keyboard_arrow_down')),
          open ? h('div', { class: 'at' }, i.a[lang] || '…') : null);
        q.addEventListener('click', () => {
          state.previewOpen = open ? null : i.id;
          renderPreview();
        });
        card.appendChild(q);
      });
      screen.appendChild(card);
    });
    screen.scrollTop = top;
  }

  const schedulePreview = K.debounce(renderPreview, 120);

  // ---- Changing the draft ---------------------------------------------------------

  /** After any change to the draft's text: the dock, the preview, the
   *  toolbar's Back button. Nothing that would redraw a text box. */
  function changed() {
    updateDock();
    schedulePreview();
  }

  function flash(item) {
    const row = rowOf(item);
    if (!row) return;
    row.classList.remove('flash');
    void row.offsetWidth;
    row.classList.add('flash');
    const r = row.getBoundingClientRect();
    if (r.top < 90 || r.bottom > window.innerHeight - 90) row.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }

  function moveItem(item, toGroup, toIndex) {
    const from = groupOf(item);
    from.items.splice(from.items.indexOf(item), 1);
    toGroup.items.splice(Math.max(0, Math.min(toIndex, toGroup.items.length)), 0, item);
    render();
    flash(item);
    K.announce('Moved to ' + titleOf(toGroup) + ', position ' + (toGroup.items.indexOf(item) + 1) + '.');
  }

  function onDrop(rowEl, fromList, fromIndex, toList, toIndex) {
    const from = state.draft.groups.find((g) => g.id === fromList.getAttribute('data-group'));
    const to = state.draft.groups.find((g) => g.id === toList.getAttribute('data-group'));
    const item = from && from.items[fromIndex];
    if (!item || !to) return render();
    moveItem(item, to, toIndex);
  }

  function nudge(item, by) {
    const g = groupOf(item);
    const gi = state.draft.groups.indexOf(g);
    const idx = g.items.indexOf(item);
    if (by < 0 && idx === 0) {
      if (gi === 0) return;
      const prev = state.draft.groups[gi - 1];
      return moveItem(item, prev, prev.items.length);
    }
    if (by > 0 && idx === g.items.length - 1) {
      if (gi === state.draft.groups.length - 1) return;
      return moveItem(item, state.draft.groups[gi + 1], 0);
    }
    moveItem(item, g, idx + by);
  }

  function moveToGroup(item, groupId) {
    let target = state.draft.groups.find((g) => g.id === groupId);
    if (!target) target = insertBuiltInGroup(groupId);
    if (target) moveItem(item, target, target.items.length);
  }

  /** A built-in group not on the page, put back where the app has it. */
  function insertBuiltInGroup(groupId) {
    const b = builtInGroup.get(groupId);
    if (!b) return null;
    const rank = state.builtIn.groups.indexOf(b);
    let at = 0;
    state.draft.groups.forEach((g, i) => {
      const r = state.builtIn.groups.findIndex((x) => x.id === g.id);
      if (r >= 0 && r < rank) at = i + 1;
    });
    const group = { id: b.id, title: { ar: b.ar, en: b.en }, items: [] };
    state.draft.groups.splice(at, 0, group);
    return group;
  }

  function putBack(itemId) {
    const b = builtInItem.get(itemId);
    if (!b) return;
    const group = state.draft.groups.find((g) => g.id === b.group) || insertBuiltInGroup(b.group);
    const i = state.builtIn.items.indexOf(b);
    let pos = 0;
    for (let j = i - 1; j >= 0; j--) {
      const prev = state.builtIn.items[j];
      if (prev.group !== b.group) continue;
      const at = group.items.findIndex((x) => x.id === prev.id);
      if (at >= 0) {
        pos = at + 1;
        break;
      }
    }
    const item = { id: b.id, q: { ar: b.qAr, en: b.qEn }, a: { ar: b.aAr, en: b.aEn } };
    group.items.splice(pos, 0, item);
    render();
    flash(item);
  }

  function takeOff(item) {
    const g = groupOf(item);
    g.items.splice(g.items.indexOf(item), 1);
    state.open.delete(item.id);
    render();
    K.toast('Taken off. It is in "Taken off the FAQ" at the bottom until you Save.');
  }

  function deleteAdded(item) {
    const typed = FIELDS.some((f) => norm(fieldOf(item, f)));
    if (typed && !window.confirm('Delete this question? Until you Save, Discard brings it back.')) return;
    const g = groupOf(item);
    g.items.splice(g.items.indexOf(item), 1);
    state.open.delete(item.id);
    render();
  }

  function addQuestion(g) {
    const item = { id: C.newId(C.ADDED.question, takenIds()), q: { ar: '', en: '' }, a: { ar: '', en: '' } };
    g.items.push(item);
    state.open.add(item.id);
    state.query = '';
    render();
    const row = rowOf(item);
    if (row) {
      row.scrollIntoView({ block: 'center', behavior: 'smooth' });
      const first = row.querySelector('textarea');
      if (first) first.focus({ preventScroll: true });
    }
  }

  function addGroup() {
    const g = { id: C.newId(C.ADDED.group, takenIds()), title: { ar: '', en: '' }, items: [] };
    state.draft.groups.push(g);
    render();
    const card = document.querySelector('.g-card[data-group="' + g.id + '"]');
    if (card) {
      card.scrollIntoView({ block: 'center', behavior: 'smooth' });
      const first = card.querySelector('textarea');
      if (first) first.focus({ preventScroll: true });
    }
  }

  function removeGroup(gi) {
    state.draft.groups.splice(gi, 1);
    render();
  }

  function moveGroup(gi, by) {
    const to = gi + by;
    if (to < 0 || to >= state.draft.groups.length) return;
    const [g] = state.draft.groups.splice(gi, 1);
    state.draft.groups.splice(to, 0, g);
    render();
    K.announce('Group moved to place ' + (to + 1) + '.');
  }

  function backToBuiltIn() {
    if (!window.confirm('Put the app’s own FAQ back on this page? Nothing changes on phones until you Save, and Discard undoes this.')) return;
    state.draft = draftFrom(null);
    state.checked = new Set();
    render();
  }

  function discard() {
    if (!window.confirm('Throw away every change on this page since the last save?')) return;
    resetDraft();
    render();
  }

  // ---- Search -----------------------------------------------------------------

  function applySearch() {
    const words = R.searchKey(state.query).split(/\s+/).filter(Boolean);
    const searching = words.length > 0;
    document.querySelectorAll('.g-card').forEach((card) => {
      const g = state.draft.groups.find((x) => x.id === card.getAttribute('data-group'));
      let shown = 0;
      card.querySelectorAll('.q-row').forEach((row) => {
        const item = g && g.items.find((i) => i.id === row.getAttribute('data-item'));
        const hay = item ? R.searchKey([item.q.ar, item.q.en, item.a.ar, item.a.en].join('\n')) : '';
        const hit = !searching || state.open.has(item && item.id) || words.every((w) => hay.includes(w));
        row.classList.toggle('hidden-by-search', !hit);
        const grip = row.querySelector('.grip');
        if (grip) grip.disabled = searching;
        if (hit) shown++;
      });
      card.hidden = searching && shown === 0;
    });
  }

  // ---- Saving ---------------------------------------------------------------------

  function payload() {
    return {
      groups: state.draft.groups.map((g) => ({
        id: g.id,
        title: { ar: g.title.ar, en: g.title.en },
        items: g.items.map((i) => ({ id: i.id, q: { ar: i.q.ar, en: i.q.en }, a: { ar: i.a.ar, en: i.a.en } })),
      })),
    };
  }

  function updateDock() {
    const dock = $('dock');
    if (!state.draft || !dirty()) {
      dock.hidden = true;
      clear(dock);
      return;
    }
    const check = C.faqEditsFromDraft(state.builtIn, state.draft);
    clear(dock);
    dock.hidden = false;
    let said;
    if (!check.ok) {
      said = h('div', { class: 'problems' },
        check.errors.length + (check.errors.length === 1 ? ' thing to fix' : ' things to fix') + ' before saving. ',
        button('Show me', showFirstProblem, 'link-btn'));
    } else {
      const words = C.describeFaqChange(state.builtIn, state.data.live.faq, check.edits);
      said = h('div', null, h('b', null, 'Not saved: '), words ? words + '.' : state.checked.size ? 'your text kept over the app’s change.' : 'nothing phones would see.');
    }
    const notes = check.warnings.length
      ? h('div', { class: 'notes' }, check.warnings.length + (check.warnings.length === 1 ? ' house-style note' : ' house-style notes') + ' (orange). They do not block Save.')
      : null;
    dock.appendChild(h('div', { class: 'grow' }, said, notes));
    dock.appendChild(button('Discard', discard, 'btn'));
    dock.appendChild(button(state.saving ? 'Saving…' : 'Save', save, 'btn primary', { disabled: state.saving || !check.ok }));
    dock.appendChild(h('span', { class: 'muted-note' }, h('kbd', null, '⌘'), ' ', h('kbd', null, 'S')));
    // The Back button's state follows the draft too.
    const back = document.querySelector('.toolbar .btn:last-child');
    if (back) back.disabled = C.canonical(normalized(state.draft)) === C.canonical(normalized(draftFrom(null)));
  }

  /** Opens and focuses the first box that stops the save. */
  function showFirstProblem() {
    for (const g of state.draft.groups) {
      const bg = builtInGroup.get(g.id);
      if (g.items.length) {
        for (const lang of LANGS) {
          if (bg && norm(g.title[lang]) === norm(bg[lang])) continue;
          if (C.checkField('', lang, g.title[lang], C.MAX_HEADING_LENGTH).errors.length) {
            const card = document.querySelector('.g-card[data-group="' + CSS.escape(g.id) + '"]');
            const ta = card && card.querySelector('.g-title-' + lang + ' textarea');
            if (ta) {
              ta.scrollIntoView({ block: 'center', behavior: 'smooth' });
              ta.focus({ preventScroll: true });
            }
            return;
          }
        }
      }
      for (const item of g.items) {
        const bi = builtInItem.get(item.id);
        const bad = FIELDS.find((f) => !(bi && norm(fieldOf(item, f)) === norm(bi[f.key])) &&
          C.checkField('', f.lang, fieldOf(item, f), f.max).errors.length);
        if (!bad) continue;
        state.query = '';
        if (!state.open.has(item.id)) {
          state.open.add(item.id);
          render();
        }
        const row = rowOf(item);
        const ta = row && row.querySelector('textarea[data-field="' + bad.key + '"]');
        if (ta) {
          ta.scrollIntoView({ block: 'center', behavior: 'smooth' });
          ta.focus({ preventScroll: true });
        }
        return;
      }
    }
    K.toast(K.errorText({ errors: C.faqEditsFromDraft(state.builtIn, state.draft).errors }));
  }

  async function save() {
    if (state.saving || !dirty()) return;
    const check = C.faqEditsFromDraft(state.builtIn, state.draft);
    if (!check.ok) {
      showFirstProblem();
      return;
    }
    state.saving = true;
    updateDock();
    K.setReadOnly($('faqApp'), true);
    const res = await K.post('/api/wording/faq', {
      draft: payload(),
      checked: Array.from(state.checked),
      // What this page was built from, so a page left open while the FAQ
      // was saved elsewhere, or while the app's own FAQ changed in the
      // code, is refused instead of writing over either.
      base: state.data.live.faq || null,
      builtInFingerprint: C.fingerprint(state.builtIn),
    });
    state.saving = false;
    K.setReadOnly($('faqApp'), false);
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
    state.saved = C.parseFaqEdits(wording.live.faq);
  }

  // ---- Start ----------------------------------------------------------------------

  async function start() {
    K.sortable({
      lists: () => Array.from(document.querySelectorAll('#faqApp .q-list')),
      handle: '.q-row > .grip',
      row: '.q-row',
      onDrop,
    });
    document.addEventListener('keydown', (ev) => {
      if ((ev.metaKey || ev.ctrlKey) && !ev.shiftKey && !ev.altKey && String(ev.key).toLowerCase() === 's') {
        ev.preventDefault();
        save();
      }
    });
    window.addEventListener('beforeunload', (ev) => {
      if (dirty()) {
        ev.preventDefault();
        ev.returnValue = '';
      }
    });
    window.addEventListener('resize', K.debounce(() => K.resizeAll($('faqApp')), 150));
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => K.resizeAll($('faqApp')));

    try {
      state.data = await K.load();
    } catch (e) {
      clear($('faqApp')).appendChild(K.banner('danger', 'Could not load the FAQ.', e.message));
      return;
    }
    state.builtIn = state.data.catalog.faq;
    if (!state.builtIn) {
      K.renderBanners($('banners'), state.data, [K.banner('danger', 'The app’s own FAQ could not be read, so it cannot be edited here.',
        state.data.catalog.faqError || 'The list of strings has no FAQ in it.')]);
      clear($('faqApp'));
      return;
    }
    builtInItem = new Map(state.builtIn.items.map((i) => [i.id, i]));
    builtInGroup = new Map(state.builtIn.groups.map((g) => [g.id, g]));
    state.saved = C.parseFaqEdits(state.data.live.faq);
    resetDraft();
    render();
  }

  start();
})();
