/**
 * The «دوم» page: Doum's timing, his hours and which praise list each habit
 * hears. Every setting is a field of one draft; Save sends the whole draft,
 * the server checks it with the same rules (wording/pet_rules.js) and
 * stores only what differs from the app's built-in values.
 *
 * A plain file served as it is (see lib/pet_page.js for why no page script
 * lives inside a template literal). Needs pet_rules.js (window.PetRules)
 * loaded first.
 *
 * No em dash anywhere in this file, including comments.
 */
(function () {
  'use strict';

  const R = window.PetRules;

  // The edition of the page's styles this script is written for: the
  // --pet-styles value in lib/pet_page.js. The styles are built into the page
  // when the server starts, and this file is read on every load.
  const EDITION = '2';

  const state = {
    data: null, // GET /api/pet: builtIn, presets, stored, resolved, phones
    saved: null, // the draft the stored settings make
    draft: null, // the page's settings, as edited
    saving: false,
    stale: false,
    serverErrors: [],
    check: null, // the draft checked, as of the last refresh (see checked)
  };

  // Called after every change: each keeps one part of the page in step.
  let updaters = [];

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

  let toastTimer = null;
  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 3200);
  }

  function banner(kind, bold, rest) {
    return h('div', { class: 'banner ' + kind }, h('div', null, bold ? h('b', null, bold + ' ') : null, rest));
  }

  function clone(v) {
    return JSON.parse(JSON.stringify(v));
  }

  // Digits typed on an Arabic keyboard (Arabic-Indic or Persian) read as the
  // same number as 0 to 9.
  const EASTERN_DIGITS = ['\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669',
    '\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9'];
  function westernDigits(text) {
    return text.replace(/[\u0660-\u0669\u06f0-\u06f9]/g, (d) => {
      for (const set of EASTERN_DIGITS) {
        const i = set.indexOf(d);
        if (i >= 0) return String(i);
      }
      return d;
    });
  }

  // ---- Names ----------------------------------------------------------------

  function listText(name) {
    const l = R.LISTS.find((x) => x.name === name);
    return l ? l.ar + '  ·  ' + l.en : name;
  }

  function categoryOf(name) {
    return R.CATEGORIES.find((c) => c.name === name) || { name, ar: name, en: name, chip: false };
  }

  function builtIn() {
    return state.data.builtIn;
  }

  function presetIds() {
    return state.data.presets.map((p) => p.id);
  }

  /** The draft checked, and what it would put in force. */
  function checked() {
    const check = R.checkDraft(builtIn(), state.draft, presetIds());
    return Object.assign(check, { inForce: R.resolve(builtIn(), check.edits) });
  }

  /** How many settings differ from what is stored. */
  function unsavedCount() {
    let n = 0;
    for (const key of R.NUMBER_KEYS) if (state.draft[key] !== state.saved[key]) n++;
    for (const part of ['presets', 'categories', 'alsoHears']) {
      for (const key of Object.keys(state.draft[part])) {
        if (state.draft[part][key] !== state.saved[part][key]) n++;
      }
    }
    if (state.draft.quit !== state.saved.quit) n++;
    return n;
  }

  // ---- Fields ---------------------------------------------------------------

  /** The "Built in: X" note, with a way back when the value is not it. */
  function builtInNote(text, isBuiltIn, reset) {
    const note = h('span', { class: 'built-in' }, 'Built in: ' + text);
    if (!isBuiltIn) note.appendChild(h('button', { type: 'button', class: 'link-btn', onclick: reset }, 'Use built-in'));
    return note;
  }

  function numberField(n) {
    const [min, max] = builtIn().ranges[n.key];
    // Text, not type=number: a number box draws its digits in the browser's
    // own language (Arabic-Indic on an Arabic Mac) and quietly drops what it
    // cannot read, where this shows exactly what was typed.
    const input = h('input', {
      type: 'text',
      id: 'n-' + n.key,
      inputmode: 'numeric',
      dir: 'ltr',
      autocomplete: 'off',
      value: String(state.draft[n.key]),
    });
    input.addEventListener('input', () => {
      const raw = westernDigits(input.value.trim());
      state.draft[n.key] = /^\d{1,4}$/.test(raw) ? Number(raw) : raw;
      refresh();
    });
    const noteBox = h('div');
    updaters.push(() => {
      const v = state.draft[n.key];
      const base = builtIn().numbers[n.key];
      input.classList.toggle('has-error', !(Number.isInteger(v) && v >= min && v <= max));
      clear(noteBox).appendChild(builtInNote(String(base), v === base, () => {
        state.draft[n.key] = base;
        input.value = String(base);
        refresh();
      }));
    });
    return h('div', { class: 'num' },
      h('label', { for: input.id }, n.label),
      h('div', { class: 'row' }, input, h('span', { class: 'unit' }, n.unit + ', ' + min + ' to ' + max)),
      noteBox,
      h('div', { class: 'help' }, n.help));
  }

  /** A select of Doum's lists; [extra] is an option before them, or null. */
  function listSelect(label, value, extra, skip, onPick) {
    const sel = h('select', { class: 'pick', 'aria-label': label });
    if (extra) sel.appendChild(h('option', { value: extra.value }, extra.text));
    for (const l of R.LISTS) {
      if (l.name === skip) continue;
      sel.appendChild(h('option', { value: l.name }, listText(l.name)));
    }
    sel.value = value;
    sel.addEventListener('change', () => onPick(sel.value));
    return sel;
  }

  // ---- Sections ---------------------------------------------------------------

  function wordsCard() {
    return h('div', { class: 'card words-card', id: 'words' },
      h('div', { class: 'grow' },
        h('h2', null, 'What Doum says'),
        h('p', { class: 'about' }, 'His hello, his lines through the day, all fourteen praise lists (one line per row, a man’s and a woman’s), the full-day blessing and the hide question are app text, edited on the Wording page with its checks and History.')),
      h('a', { class: 'btn-link', href: '/wording?q=sprout#text' }, 'Open his words on the Wording page'));
  }

  function numbersCard(title, about, keys) {
    return h('div', { class: 'card' },
      h('h2', null, title),
      h('p', { class: 'about' }, about),
      h('div', { class: 'num-grid' }, keys.map((key) => numberField(R.NUMBERS.find((n) => n.key === key)))));
  }

  function confettiCard() {
    return h('div', { class: 'card', id: 'confetti' },
      h('h2', null, 'Confetti'),
      h('p', { class: 'about' }, 'The day’s three moments, each bigger than the one before: a habit finished, the streak point, and every habit done, which fires two bursts. 0 pieces fires none.'),
      R.CONFETTI.map((c) => h('div', { class: 'burst' },
        h('h3', null, c.title),
        h('p', { class: 'about' }, c.about),
        h('div', { class: 'num-grid' }, R.NUMBERS.filter((n) => n.confetti === c.id).map(numberField)))));
  }

  function presetsCard() {
    const rows = state.data.presets.map((p) => {
      const cat = categoryOf(p.category);
      const quit = p.goalType === 'quit';
      const follow = { value: '', text: '' };
      const sel = listSelect('The list ' + (p.nameAr || p.name) + ' hears', state.draft.presets[p.id], follow, null, (v) => {
        state.draft.presets[p.id] = v;
        refresh();
      });
      const noteBox = h('div');
      updaters.push(() => {
        const inForce = state.check.inForce;
        const followed = quit ? inForce.quit : inForce.categories[p.category] || 'general';
        sel.options[0].textContent = (quit ? 'The quit list: ' : 'Its category’s list: ') + listText(followed);
        const base = builtIn().presets[p.id] || '';
        const v = state.draft.presets[p.id];
        sel.classList.toggle('edited', v !== base);
        clear(noteBox).appendChild(builtInNote(base ? listText(base) : 'its category’s list', v === base, () => {
          state.draft.presets[p.id] = base;
          sel.value = base;
          refresh();
        }));
      });
      return h('tr', null,
        h('td', null,
          p.nameAr ? h('div', { class: 't-ar' }, p.nameAr) : null,
          h('div', { class: 'sub' }, p.name)),
        h('td', null, h('span', { class: 't-ar' }, cat.ar), h('div', { class: 'sub' }, cat.en), quit ? h('span', { class: 'tag' }, 'quit') : null),
        h('td', null, sel, noteBox));
    });
    return h('div', { class: 'card', id: 'presets' },
      h('h2', null, 'Ready-made habits'),
      h('p', { class: 'about' }, 'The list each of the app’s own habits hears when its square turns green. A habit set to its category’s list follows the Categories table below; a quit habit follows the quit list. A habit given its own list keeps it whatever its category.'),
      h('table', { class: 'pet-table' },
        h('thead', null, h('tr', null, h('th', null, 'Habit'), h('th', null, 'Category'), h('th', null, 'Hears'))),
        h('tbody', null, rows)));
  }

  function categoriesCard() {
    const rows = R.CATEGORIES.map((c) => {
      const sel = listSelect('The list the ' + c.en + ' category hears', state.draft.categories[c.name], null, null, (v) => {
        state.draft.categories[c.name] = v;
        refresh();
      });
      const noteBox = h('div');
      updaters.push(() => {
        const base = builtIn().categories[c.name];
        const v = state.draft.categories[c.name];
        sel.classList.toggle('edited', v !== base);
        clear(noteBox).appendChild(builtInNote(listText(base), v === base, () => {
          state.draft.categories[c.name] = base;
          sel.value = base;
          refresh();
        }));
      });
      return h('tr', null,
        h('td', null, h('span', { class: 't-ar' }, c.ar), h('div', { class: 'sub' }, c.en),
          c.chip ? null : h('span', { class: 'tag' }, 'ready-made only')),
        h('td', null, sel, noteBox));
    });
    return h('div', { class: 'card', id: 'categories' },
      h('h2', null, 'Categories'),
      h('p', { class: 'about' }, 'The list each category hears. A habit someone types gets one of Add Habit’s chips (the first nine rows), from its name or their tap, and hears that chip’s list. The last five are categories only ready-made habits have.'),
      h('table', { class: 'pet-table' },
        h('thead', null, h('tr', null, h('th', null, 'Category'), h('th', null, 'Hears'))),
        h('tbody', null, rows)));
  }

  function quitCard() {
    const sel = listSelect('The list every quit habit hears', state.draft.quit, null, null, (v) => {
      state.draft.quit = v;
      refresh();
    });
    const noteBox = h('div');
    updaters.push(() => {
      const base = builtIn().quit;
      sel.classList.toggle('edited', state.draft.quit !== base);
      clear(noteBox).appendChild(builtInNote(listText(base), state.draft.quit === base, () => {
        state.draft.quit = base;
        sel.value = base;
        refresh();
      }));
    });
    return h('div', { class: 'card', id: 'quit' },
      h('h2', null, 'Quit habits'),
      h('p', { class: 'about' }, 'Every habit of the ترك أو تقليل kind hears this list, unless it is a ready-made habit given its own list above. Its green square is a day kept clean, not a thing done.'),
      sel, noteBox);
  }

  function alsoCard() {
    const rows = R.LISTS.filter((l) => l.name !== 'general').map((l) => {
      const sel = listSelect('The list ' + l.en + ' also draws on', state.draft.alsoHears[l.name],
        { value: '', text: 'Nothing else' }, l.name, (v) => {
          state.draft.alsoHears[l.name] = v;
          refresh();
        });
      const noteBox = h('div');
      updaters.push(() => {
        const base = builtIn().alsoHears[l.name] || '';
        const v = state.draft.alsoHears[l.name];
        sel.classList.toggle('edited', v !== base);
        clear(noteBox).appendChild(builtInNote(base ? listText(base) : 'nothing else', v === base, () => {
          state.draft.alsoHears[l.name] = base;
          sel.value = base;
          refresh();
        }));
      });
      return h('tr', null,
        h('td', null, h('span', { class: 't-ar' }, l.ar), h('div', { class: 'sub' }, l.en)),
        h('td', null, sel, noteBox));
    });
    return h('div', { class: 'card', id: 'also' },
      h('h2', null, 'Lists that also draw on another'),
      h('p', { class: 'about' }, 'A habit hears its own list and this one together, never the general list: once all of those were said lately, the one said longest ago comes round again. So a Quran page can hear «تقبّل الله» from the Faith list too. One step only: what the other list draws on is not added.'),
      h('table', { class: 'pet-table' },
        h('thead', null, h('tr', null, h('th', null, 'List'), h('th', null, 'Also draws on'))),
        h('tbody', null, rows)));
  }

  function saveBar() {
    const status = h('div', { class: 'status', id: 'barStatus' });
    const discard = h('button', { type: 'button', class: 'btn', id: 'discardBtn' }, 'Discard');
    const save = h('button', { type: 'button', class: 'btn primary', id: 'saveBtn' }, 'Save');
    discard.addEventListener('click', () => {
      state.draft = clone(state.saved);
      state.serverErrors = [];
      render();
    });
    save.addEventListener('click', saveNow);
    updaters.push(() => {
      const check = state.check;
      const n = unsavedCount();
      const errors = state.serverErrors.length ? state.serverErrors : check.errors;
      const box = clear(status);
      if (state.saving) box.appendChild(document.createTextNode('Saving…'));
      else if (state.stale) box.appendChild(document.createTextNode('Reload the page before saving: these settings changed elsewhere.'));
      else box.appendChild(document.createTextNode(n === 0 ? 'No unsaved changes.' : n === 1 ? '1 unsaved change.' : n + ' unsaved changes.'));
      if (errors.length || check.warnings.length) {
        box.appendChild(h('div', { class: 'msgs' },
          errors.map((e) => h('div', { class: 'err' }, e)),
          check.warnings.map((w) => h('div', { class: 'wrn' }, w))));
      }
      save.disabled = state.saving || state.stale || n === 0 || check.errors.length > 0;
      discard.disabled = state.saving || n === 0;
    });
    return h('div', { class: 'save-bar' }, status, discard, save);
  }

  // ---- Page -------------------------------------------------------------------

  function refresh() {
    state.check = checked();
    updaters.forEach((u) => u());
  }

  function renderBanners() {
    const box = clear($('banners'));
    const edition = getComputedStyle(document.documentElement).getPropertyValue('--pet-styles').trim().replace(/['"]/g, '');
    if (edition !== EDITION) {
      box.appendChild(banner('danger', 'This page was updated, but the admin tool is still running the copy from before.',
        ['Stop it (Ctrl-C in its Terminal window), start it again with ', h('code', null, 'npm start'), ', then reload this page.']));
    }
    if (state.data && state.data.phones === 'closed') {
      box.appendChild(banner('danger', 'Phones cannot read these settings yet.',
        ['The database rule that lets them read wording/live has not been deployed. From the repo folder: ',
          h('code', null, 'firebase deploy --only firestore:rules')]));
    }
    if (state.stale) {
      box.appendChild(banner('warn', 'Doum’s settings were saved from somewhere else since this page loaded.',
        'Reload the page to see them, then make your change again.'));
    }
  }

  function render() {
    updaters = [];
    const root = clear($('viewPet'));
    root.appendChild(wordsCard());
    root.appendChild(numbersCard('Talking',
      'How often he puts praise into words, how long a line stays, and how many lines he keeps from repeating.',
      ['praiseEverySeconds', 'bubbleSeconds', 'rememberLines']));
    root.appendChild(numbersCard('Day and night',
      'The hours his hello changes, a finished day goes to sleep, and an empty new day wakes up. The phone’s own clock.',
      ['morningUntilHour', 'bedtimeHour', 'wakeHour']));
    root.appendChild(confettiCard());
    root.appendChild(presetsCard());
    root.appendChild(categoriesCard());
    root.appendChild(quitCard());
    root.appendChild(alsoCard());
    root.appendChild(saveBar());
    renderBanners();
    refresh();
  }

  function takeData(data) {
    state.data = data;
    state.saved = R.draftFrom(data.resolved, presetIds());
    state.draft = clone(state.saved);
    state.serverErrors = [];
  }

  async function saveNow() {
    state.saving = true;
    state.serverErrors = [];
    refresh();
    try {
      const res = await fetch('/api/pet', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ draft: state.draft, base: state.data.stored }),
      });
      const body = await res.json();
      if (res.status === 409) {
        state.stale = true;
        renderBanners();
      } else if (!res.ok || !body.ok) {
        state.serverErrors = (body.errors && body.errors.length) ? body.errors : [body.error || 'The admin tool answered ' + res.status + '.'];
      } else {
        takeData(Object.assign({}, body.pet, { phones: state.data.phones }));
        state.saving = false;
        render();
        toast(body.changed ? 'Saved. Open apps follow within seconds.' : 'Nothing new to save: that is what is stored already.');
        return;
      }
    } catch (e) {
      state.serverErrors = ['Could not reach the admin tool: ' + e.message];
    }
    state.saving = false;
    refresh();
  }

  async function start() {
    window.addEventListener('beforeunload', (ev) => {
      if (state.draft && unsavedCount() > 0) {
        ev.preventDefault();
        ev.returnValue = '';
      }
    });
    let body;
    try {
      const res = await fetch('/api/pet');
      body = await res.json();
      if (!res.ok) throw new Error(body.error || 'The admin tool answered ' + res.status + '.');
    } catch (e) {
      clear($('viewPet')).appendChild(banner('danger', 'Could not load Doum’s settings.', e.message));
      return;
    }
    takeData(body);
    render();
  }

  start();
})();
