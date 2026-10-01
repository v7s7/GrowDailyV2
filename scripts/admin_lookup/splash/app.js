/**
 * The launch splash page: which scene Doum plays on the opening curtain,
 * when, in what order and for how long. Every setting is a field of one
 * draft; Save sends the whole draft, the server checks it with the same
 * rules (wording/splash_rules.js) and stores only what differs from the
 * app's built-in values.
 *
 * A plain file served as it is (see lib/splash_page.js for why no page script
 * lives inside a template literal). Needs splash_rules.js (window.SplashRules)
 * loaded first. Same shape as pet/app.js.
 *
 * No em dash anywhere in this file, including comments.
 */
(function () {
  'use strict';

  const R = window.SplashRules;

  // The edition of the page's styles this script is written for: the
  // --splash-styles value in lib/splash_page.js.
  const EDITION = '3';

  const state = {
    data: null, // GET /api/splash: builtIn, stored, resolved, phones
    saved: null, // the draft the stored settings make
    draft: null, // the page's settings, as edited
    saving: false,
    stale: false,
    serverErrors: [],
    check: null, // the draft checked, as of the last refresh
    preview: null, // the "what plays when" question
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
  const EASTERN_DIGITS = ['٠١٢٣٤٥٦٧٨٩',
    '۰۱۲۳۴۵۶۷۸۹'];
  function westernDigits(text) {
    return text.replace(/[٠-٩۰-۹]/g, (d) => {
      for (const set of EASTERN_DIGITS) {
        const i = set.indexOf(d);
        if (i >= 0) return String(i);
      }
      return d;
    });
  }

  function builtIn() {
    return state.data.builtIn;
  }

  /** The line in force for [name] in the draft, else the app's. */
  function draftLine(name) {
    const text = state.draft.lines[name];
    return typeof text === 'string' && R.tidyLine(text) ? R.tidyLine(text) : builtIn().lines[name];
  }

  /** The draft checked, and what it would put in force. */
  function checked() {
    const check = R.checkDraft(builtIn(), state.draft);
    return Object.assign(check, { inForce: R.resolve(builtIn(), check.edits) });
  }

  /** How many settings differ from what is stored. */
  function unsavedCount() {
    const a = state.draft;
    const b = state.saved;
    let n = 0;
    for (const key of R.NUMBER_KEYS) if (a[key] !== b[key]) n++;
    if (!R.same(a.order, b.order)) n++;
    for (const name of R.SCENE_NAMES) {
      if (a.off.includes(name) !== b.off.includes(name)) n++;
      if (!R.same(a.hours[name], b.hours[name])) n++;
      if (!R.same(a.months[name], b.months[name])) n++;
      if (a.lines[name] !== b.lines[name]) n++;
    }
    for (const name of Object.keys(a.pool)) if (a.pool[name] !== b.pool[name]) n++;
    for (const name of Object.keys(a.onceADay)) if (a.onceADay[name] !== b.onceADay[name]) n++;
    for (const name of Object.keys(a.chance)) if (a.chance[name] !== b.chance[name]) n++;
    if (a.slowLine !== b.slowLine) n++;
    if (!R.same(a.force, b.force)) n++;
    return n;
  }

  // ---- Fields ---------------------------------------------------------------

  /** The "Built in: X" note, with a way back when the value is not it. */
  function builtInNote(text, isBuiltIn, reset) {
    const note = h('span', { class: 'built-in' }, 'Built in: ' + text);
    if (!isBuiltIn) note.appendChild(h('button', { type: 'button', class: 'link-btn', onclick: reset }, 'Use built-in'));
    return note;
  }

  function secondsText(ms) {
    return (ms / 1000).toFixed(1);
  }

  function numberOf(key) {
    return R.NUMBERS.find((n) => n.key === key);
  }

  /** A switch: [isOn] reads the draft, [setOn] writes it; [words] its On and Off text. */
  function switchControl(labelText, isOn, setOn, words) {
    const [onText, offText] = words || ['On', 'Off'];
    const box = h('input', { type: 'checkbox', 'aria-label': labelText });
    box.checked = isOn();
    box.addEventListener('change', () => {
      setOn(box.checked);
      refresh();
    });
    const text = h('span');
    updaters.push(() => {
      box.checked = isOn();
      text.textContent = isOn() ? onText : offText;
    });
    return h('label', { class: 'switch' }, box, h('span', { class: 'track' }), text);
  }

  /** A number box. Text, not type=number: see pet/app.js for why. */
  function numberField(n) {
    const [min, max] = builtIn().ranges[n.key];
    if (n.toggle) {
      const control = switchControl(n.label, () => state.draft[n.key] === 1, (on) => { state.draft[n.key] = on ? 1 : 0; });
      const noteBox = h('div');
      updaters.push(() => {
        const base = builtIn().numbers[n.key];
        clear(noteBox).appendChild(builtInNote(base === 1 ? 'on' : 'off', state.draft[n.key] === base, () => {
          state.draft[n.key] = base;
          refresh();
        }));
      });
      return h('div', { class: 'num' },
        h('label', null, n.label),
        h('div', { class: 'row' }, control),
        noteBox,
        h('div', { class: 'help' }, n.help));
    }
    const show = (v) => (n.seconds && Number.isInteger(v) ? secondsText(v) : String(v));
    const input = h('input', {
      type: 'text',
      id: 'n-' + n.key,
      inputmode: n.seconds ? 'decimal' : 'numeric',
      dir: 'ltr',
      autocomplete: 'off',
      value: show(state.draft[n.key]),
    });
    input.addEventListener('input', () => {
      const raw = westernDigits(input.value.trim()).replace(',', '.');
      if (n.seconds) {
        state.draft[n.key] = /^\d{1,2}(\.\d{1,3})?$/.test(raw) ? Math.round(parseFloat(raw) * 1000) : raw;
      } else {
        state.draft[n.key] = /^\d{1,4}$/.test(raw) ? Number(raw) : raw;
      }
      refresh();
    });
    const noteBox = h('div');
    updaters.push(() => {
      const v = state.draft[n.key];
      const base = builtIn().numbers[n.key];
      input.classList.toggle('has-error', !(Number.isInteger(v) && v >= min && v <= max));
      clear(noteBox).appendChild(builtInNote(show(base) + ' ' + n.unit, v === base, () => {
        state.draft[n.key] = base;
        input.value = show(base);
        refresh();
      }));
    });
    const range = n.seconds ? (min / 1000) + ' to ' + (max / 1000) : min + ' to ' + max;
    return h('div', { class: 'num' },
      h('label', { for: input.id }, n.label),
      h('div', { class: 'row' }, input, h('span', { class: 'unit' }, n.unit + ', ' + range)),
      noteBox,
      h('div', { class: 'help' }, n.help));
  }

  /** A small whole-number box; '' when blank, the number, or what was typed. */
  function smallBox(label, value, onValue) {
    const input = h('input', {
      type: 'text',
      inputmode: 'numeric',
      dir: 'ltr',
      autocomplete: 'off',
      maxlength: '2',
      'aria-label': label,
      value: String(value),
    });
    input.addEventListener('input', () => {
      const raw = westernDigits(input.value.trim());
      onValue(raw === '' ? '' : /^\d{1,3}$/.test(raw) ? Number(raw) : raw);
      refresh();
    });
    return input;
  }

  function hoursText(pair) {
    if (!pair || (pair[0] === 0 && pair[1] === 24)) return 'no hours limit';
    return R.hourName(pair[0]) + ' to ' + R.hourName(pair[1]);
  }

  function hoursField(name) {
    const label = R.sceneLabel(name);
    const from = smallBox(label + ' from hour', state.draft.hours[name][0], (v) => { state.draft.hours[name][0] = v; });
    const to = smallBox(label + ' to hour', state.draft.hours[name][1], (v) => { state.draft.hours[name][1] = v; });
    const noteBox = h('div');
    updaters.push(() => {
      const base = builtIn().hours[name] || null;
      const mine = R.hoursOf(state.draft.hours[name]);
      const bad = state.check.errors.some((e) => e.indexOf(label + ':') === 0 && / hour/.test(e) && !/walkers/.test(e));
      from.classList.toggle('has-error', bad);
      to.classList.toggle('has-error', bad);
      clear(noteBox).appendChild(builtInNote(hoursText(base), R.same(mine, base), () => {
        state.draft.hours[name] = base ? base.slice() : ['', ''];
        from.value = String(state.draft.hours[name][0]);
        to.value = String(state.draft.hours[name][1]);
        refresh();
      }));
    });
    return h('div', { class: 'field' },
      h('div', { class: 'field-row hours' },
        h('span', { class: 'name' }, 'Hours'),
        h('label', null, 'From'), from, h('label', null, 'to'), to,
        noteBox),
      h('div', { class: 'hint' }, '0 to 23, and 24 is midnight. From after To runs past midnight. Both blank: any hour.'));
  }

  /** The walk card's walkers' hour: two boxes, both blank for none. */
  function walkerField() {
    const from = smallBox('Walkers’ hour from', state.draft.walkerFromHour, (v) => { state.draft.walkerFromHour = v; });
    const to = smallBox('Walkers’ hour to', state.draft.walkerToHour, (v) => { state.draft.walkerToHour = v; });
    const noteBox = h('div');
    const status = h('div', { class: 'hint' });
    updaters.push(() => {
      const bf = builtIn().numbers.walkerFromHour;
      const bt = builtIn().numbers.walkerToHour;
      const df = state.draft.walkerFromHour;
      const dt = state.draft.walkerToHour;
      const bad = state.check.errors.some((e) => /walkers/.test(e));
      from.classList.toggle('has-error', bad);
      to.classList.toggle('has-error', bad);
      const none = (df === '' && dt === '') || (Number.isInteger(df) && df === dt);
      status.textContent = none
        ? 'No walkers’ hour: the walk then plays only from the anytime list.'
        : 'Every open from ' + (Number.isInteger(df) ? R.hourName(df) : '?') + ' to ' + (Number.isInteger(dt) ? R.hourName(dt) : '?') + ' plays the walk for someone with a walking or steps habit. Both blank: no walkers’ hour.';
      clear(noteBox).appendChild(builtInNote(R.hourName(bf) + ' to ' + R.hourName(bt), df === bf && dt === bt, () => {
        state.draft.walkerFromHour = bf;
        state.draft.walkerToHour = bt;
        from.value = String(bf);
        to.value = String(bt);
        refresh();
      }));
    });
    return h('div', { class: 'field' },
      h('div', { class: 'field-row hours' },
        h('span', { class: 'name' }, 'Walkers’ hour'),
        h('label', null, 'From'), from, h('label', null, 'to'), to,
        noteBox),
      status);
  }

  function monthsField(name) {
    const chips = R.MONTH_NAMES.map((label, i) => {
      const month = i + 1;
      const chip = h('button', { type: 'button', class: 'chip', 'aria-pressed': 'false', title: label }, label.slice(0, 3));
      chip.addEventListener('click', () => {
        const list = state.draft.months[name];
        const at = list.indexOf(month);
        if (at >= 0) list.splice(at, 1);
        else list.push(month);
        list.sort((a, b) => a - b);
        refresh();
      });
      updaters.push(() => chip.setAttribute('aria-pressed', String(state.draft.months[name].includes(month))));
      return chip;
    });
    const noteBox = h('div');
    updaters.push(() => {
      const base = (builtIn().months[name] || []).slice().sort((a, b) => a - b);
      const mine = state.draft.months[name].slice().sort((a, b) => a - b);
      const same = R.same(mine.length === 12 ? [] : mine, base);
      const text = base.length ? base.map((m) => R.MONTH_NAMES[m - 1].slice(0, 3)).join(', ') : 'every month';
      clear(noteBox).appendChild(builtInNote(text, same, () => {
        state.draft.months[name] = base.slice();
        refresh();
      }));
    });
    return h('div', { class: 'field' },
      h('div', { class: 'field-row' },
        h('span', { class: 'name' }, 'Months'),
        h('div', { class: 'chips' }, chips),
        noteBox),
      h('div', { class: 'hint' }, 'None ticked: every month.'));
  }

  function shareField(name) {
    const max = builtIn().poolMax;
    const input = smallBox('Share of ' + R.sceneLabel(name) + ' in the anytime list', state.draft.pool[name], (v) => { state.draft.pool[name] = v; });
    const noteBox = h('div');
    const part = h('span', { class: 'unit' });
    updaters.push(() => {
      const v = state.draft.pool[name];
      const base = builtIn().pool[name];
      input.classList.toggle('has-error', !(Number.isInteger(v) && v >= 0 && v <= max));
      const p = R.poolShares(state.check.inForce).find((x) => x.scene === name);
      part.textContent = '0 to ' + max + ', 0 leaves it out. ' + (p ? Math.round(p.chance * 100) + '% of the list.' : 'Not in the list.');
      clear(noteBox).appendChild(builtInNote(String(base), v === base, () => {
        state.draft.pool[name] = base;
        input.value = String(base);
        refresh();
      }));
    });
    return h('div', { class: 'field-row share' },
      h('span', { class: 'name' }, 'Share in the anytime list'), input, part, noteBox);
  }

  function onceField(name) {
    const control = switchControl(R.sceneLabel(name) + ' once a day',
      () => state.draft.onceADay[name] === 1,
      (on) => { state.draft.onceADay[name] = on ? 1 : 0; },
      ['Once a day (other opens go to the anytime list)', 'Every open in its hours']);
    const noteBox = h('div');
    updaters.push(() => {
      const base = builtIn().onceADay[name];
      clear(noteBox).appendChild(builtInNote(base === 1 ? 'once a day' : 'every open', state.draft.onceADay[name] === base, () => {
        state.draft.onceADay[name] = base;
        refresh();
      }));
    });
    return h('div', { class: 'field-row' }, h('span', { class: 'name' }, 'How many'), control, noteBox);
  }

  const DAY_LETTERS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  /** Today's launch day on this computer (the day turns at 04:00), as { y, m, d }. */
  function launchToday() {
    const now = new Date();
    const t = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (now.getHours() < 4 ? 1 : 0));
    return { y: t.getFullYear(), m: t.getMonth() + 1, d: t.getDate() };
  }

  function chanceField(name) {
    const input = smallBox('How often ' + R.sceneLabel(name) + ' plays, percent of days', state.draft.chance[name], (v) => { state.draft.chance[name] = v; });
    input.setAttribute('maxlength', '3');
    const noteBox = h('div');
    const strip = h('div', { class: 'days-strip' });
    updaters.push(() => {
      const v = state.draft.chance[name];
      const base = builtIn().chance[name] !== undefined ? builtIn().chance[name] : 100;
      input.classList.toggle('has-error', !(Number.isInteger(v) && v >= 0 && v <= 100));
      clear(noteBox).appendChild(builtInNote(base + '%', v === base, () => {
        state.draft.chance[name] = base;
        input.value = String(base);
        refresh();
      }));
      clear(strip);
      const inForce = state.check.inForce;
      if (inForce.chance[name] === undefined) return;
      const t = launchToday();
      const days = R.chanceDays(inForce, name, t.y, t.m, t.d, 14);
      const plays = days.filter((d) => d.plays).length;
      strip.appendChild(h('span', { class: 'days-label' }, 'Next 14 days: plays on ' + plays));
      strip.appendChild(h('span', { class: 'days' }, days.map((d) => h('span', {
        class: 'day' + (d.plays ? ' on' : ''),
        title: DAY_LETTERS[d.weekday] + ' ' + d.d + ' ' + R.MONTH_NAMES[d.m - 1].slice(0, 3) + (d.plays ? ': plays' : ': steps aside'),
      }, h('span', { class: 'dot' }), h('span', { class: 'dn' }, d.d)))));
    });
    return h('div', { class: 'field' },
      h('div', { class: 'field-row share' },
        h('span', { class: 'name' }, 'How often'), h('span', { class: 'unit' }, 'plays on'), input,
        h('span', { class: 'unit' }, '% of days (the other days its opens go to the anytime list)'),
        noteBox),
      strip);
  }

  /** A line box: [get] and [set] read and write the draft, [base] is the app's line. */
  function lineField(label, get, set, base) {
    const max = builtIn().lineMax;
    const input = h('input', { type: 'text', class: 'line-box', dir: 'ltr', autocomplete: 'off', spellcheck: 'true', 'aria-label': label, value: get() });
    input.addEventListener('input', () => {
      set(input.value);
      refresh();
    });
    const count = h('span', { class: 'count' });
    const issue = h('div', { class: 'line-issue' });
    const noteBox = h('div');
    updaters.push(() => {
      const text = get();
      const tidy = R.tidyLine(text);
      const found = R.lineIssues(text, max);
      count.textContent = tidy.length + ' / ' + max;
      count.classList.toggle('over', tidy.length > max);
      input.classList.toggle('has-error', !!found.error);
      issue.className = 'line-issue' + (found.error ? ' err' : found.warning ? ' wrn' : '');
      issue.textContent = found.error ? 'The line ' + found.error : found.warning ? 'The line ' + found.warning : '';
      clear(noteBox).appendChild(builtInNote('“' + base + '”', tidy === base, () => {
        set(base);
        input.value = base;
        refresh();
      }));
    });
    return h('div', { class: 'field' },
      h('div', { class: 'field-row line-row' }, h('span', { class: 'name' }, 'Line'), input, count),
      issue,
      noteBox);
  }

  // ---- Sections ---------------------------------------------------------------

  function sceneCard(name) {
    const info = R.sceneByName(name);
    const isPool = Object.prototype.hasOwnProperty.call(builtIn().pool, name);
    const body = h('div', { class: 'scene-body' });
    body.appendChild(lineField(info.label + ' line', () => state.draft.lines[name], (v) => { state.draft.lines[name] = v; }, builtIn().lines[name]));
    if (name === 'walk') body.appendChild(walkerField());
    body.appendChild(hoursField(name));
    body.appendChild(monthsField(name));
    if (Object.prototype.hasOwnProperty.call(builtIn().onceADay, name)) body.appendChild(onceField(name));
    if (builtIn().order.includes(name)) body.appendChild(chanceField(name));
    if (isPool) body.appendChild(shareField(name));

    const switchNote = h('div');
    updaters.push(() => {
      const isOff = state.draft.off.includes(name);
      clear(switchNote).appendChild(builtInNote('on', !isOff, () => {
        state.draft.off = state.draft.off.filter((n) => n !== name);
        refresh();
      }));
    });
    const control = switchControl(info.label + ' on or off', () => !state.draft.off.includes(name), (on) => {
      const off = state.draft.off.filter((n) => n !== name);
      if (!on) off.push(name);
      state.draft.off = off;
    });
    const quote = h('p', { class: 'line' });
    const wrap = h('div', { class: 'scene', id: 'scene-' + name },
      h('div', { class: 'scene-head' },
        h('div', { class: 'grow' },
          h('h3', null, info.label,
            builtIn().order.includes(name) ? null : h('span', { class: 'tag' }, 'anytime only'),
            isPool && builtIn().order.includes(name) ? h('span', { class: 'tag' }, 'also anytime') : null),
          quote,
          h('p', { class: 'when' }, info.when)),
        h('div', { class: 'switch-box' }, control, switchNote)),
      body);
    updaters.push(() => {
      wrap.classList.toggle('is-off', state.draft.off.includes(name));
      quote.textContent = '“' + draftLine(name) + '”';
    });
    return wrap;
  }

  function scenesCard() {
    const order = builtIn().order;
    const cards = order.map(sceneCard).concat(R.SCENE_NAMES.filter((n) => !order.includes(n)).map(sceneCard));
    return h('div', { class: 'card', id: 'scenes' },
      h('h2', null, 'Scenes'),
      h('p', { class: 'about' }, 'Each scene’s line under Doum, when it plays, and the switch, hours and months you can change. A scene plays only when its own rule holds, its switch is On, and the hour and month fit. Hours, months and days are the phone’s own clock; a day turns at 04:00. Scenes with a share also play from the anytime list, inside the same switch, hours and months.'),
      h('p', { class: 'about' }, 'The lines are English for everyone, whatever language the app is in. “Grow Daily” in a line is drawn on its own row in green; a line without it is drawn whole.'),
      cards);
  }

  function slowLineCard() {
    return h('div', { class: 'card', id: 'slow' },
      h('h2', null, 'Slow load line'),
      h('p', { class: 'about' }, 'When the app takes long to get ready, Doum takes out his magnifier in every scene but the night, and this line replaces the scene’s own. While the account’s data is still coming from the server, a Wi-Fi mark searches over his head; at night he stays asleep and only the mark shows. English for everyone.'),
      lineField('Slow load line', () => state.draft.slowLine, (v) => { state.draft.slowLine = v; }, builtIn().slowLine));
  }

  function orderCard() {
    const list = h('ol', { class: 'order-list', id: 'orderList' });
    let dragging = null;

    function move(from, to) {
      if (to < 0 || to >= state.draft.order.length || from === to) return;
      const order = state.draft.order.slice();
      const [item] = order.splice(from, 1);
      order.splice(to, 0, item);
      state.draft.order = order;
      refresh();
    }

    function rebuild() {
      clear(list);
      const order = state.draft.order;
      order.forEach((name, i) => {
        const up = h('button', { type: 'button', 'aria-label': 'Move ' + R.sceneLabel(name) + ' up', onclick: () => move(i, i - 1) }, '↑');
        const down = h('button', { type: 'button', 'aria-label': 'Move ' + R.sceneLabel(name) + ' down', onclick: () => move(i, i + 1) }, '↓');
        up.disabled = i === 0;
        down.disabled = i === order.length - 1;
        const item = h('li', { class: 'order-item', draggable: 'true', 'data-scene': name },
          h('span', { class: 'grip', 'aria-hidden': 'true' }, '⠇'),
          h('span', { class: 'pos' }, i + 1),
          h('span', { class: 'nm' }, R.sceneLabel(name),
            state.draft.off.includes(name) ? h('span', { class: 'tag off' }, 'off') : null),
          up, down);
        item.addEventListener('dragstart', (ev) => {
          dragging = i;
          item.classList.add('dragging');
          ev.dataTransfer.effectAllowed = 'move';
          try { ev.dataTransfer.setData('text/plain', name); } catch (e) { /* some browsers refuse */ }
        });
        item.addEventListener('dragend', () => {
          dragging = null;
          list.querySelectorAll('.over,.dragging').forEach((el) => el.classList.remove('over', 'dragging'));
        });
        item.addEventListener('dragover', (ev) => {
          if (dragging === null) return;
          ev.preventDefault();
          item.classList.add('over');
        });
        item.addEventListener('dragleave', () => item.classList.remove('over'));
        item.addEventListener('drop', (ev) => {
          ev.preventDefault();
          if (dragging !== null) move(dragging, i);
          dragging = null;
        });
        list.appendChild(item);
      });
    }

    const noteBox = h('div', { class: 'order-note' });
    updaters.push(() => {
      rebuild();
      const same = R.same(state.draft.order, builtIn().order);
      clear(noteBox).appendChild(builtInNote('the order in the app', same, () => {
        state.draft.order = builtIn().order.slice();
        refresh();
      }));
    });
    return h('div', { class: 'card', id: 'order' },
      h('h2', null, 'Which scene wins'),
      h('p', { class: 'about' }, 'When more than one scene could play, the one nearest the top wins. Drag a row, or use the arrows. A scene that is off is skipped. If none of them plays, the anytime list does.'),
      list, noteBox);
  }

  function anytimeCard() {
    const bars = h('div', { class: 'pool-bars', id: 'poolBars' });
    updaters.push(() => {
      clear(bars);
      const inForce = state.check.inForce;
      const parts = R.poolShares(inForce);
      if (!parts.length) {
        bars.appendChild(h('div', { class: 'hint' }, 'Empty: every share is 0, so the day ring plays whenever no rule holds.'));
        return;
      }
      for (const p of parts) {
        const off = inForce.off.includes(p.scene);
        const pc = Math.round(p.chance * 100);
        bars.appendChild(h('div', { class: 'pool-row' + (off ? ' is-off' : '') },
          h('span', { class: 'nm' }, R.sceneLabel(p.scene), off ? h('span', { class: 'tag off' }, 'off') : null),
          h('span', { class: 'bar' }, h('span', { class: 'fill', style: 'width: ' + pc + '%' })),
          h('span', { class: 'pc' }, pc + '%'),
          h('span', { class: 'sh' }, p.share === 1 ? '1 share' : p.share + ' shares')));
      }
    });
    return h('div', { class: 'card', id: 'anytime' },
      h('h2', null, 'Anytime list'),
      h('p', { class: 'about' }, 'What plays when no scene in the order above can: one of these, picked by its share. Each still keeps to its own switch, hours and months, so at a given hour only some of them can play; the preview below shows the odds for any hour. Set the shares on the scene cards. When none of them can play, the day ring does.'),
      bars,
      h('div', { class: 'num-grid' }, ['newFirst', 'noRepeat'].map((key) => numberField(numberOf(key)))));
  }

  function timingCard() {
    return h('div', { class: 'card', id: 'timing' },
      h('h2', null, 'Timing'),
      h('p', { class: 'about' }, 'How long the curtain stays, when it plays again, what counts as coming back, and how long a missed first launch or new version scene still waits.'),
      h('div', { class: 'num-grid' },
        ['minShowMs', 'maxShowMs', 'replayAfterMinutes', 'awayDays', 'firstOpenDays', 'updateDays'].map((key) => numberField(numberOf(key)))));
  }

  function forceCard() {
    const scene = h('select', { class: 'pick', 'aria-label': 'The scene to play for everyone' });
    scene.appendChild(h('option', { value: '' }, 'None: every scene follows its own rules'));
    for (const s of R.SCENES) scene.appendChild(h('option', { value: s.name }, s.label));
    scene.value = state.draft.force.scene;
    scene.addEventListener('change', () => {
      state.draft.force.scene = scene.value;
      refresh();
    });
    const dateBox = (part, label) => {
      const input = h('input', {
        type: 'text',
        dir: 'ltr',
        autocomplete: 'off',
        placeholder: 'yyyy-mm-dd',
        'aria-label': label,
        value: state.draft.force[part],
      });
      input.addEventListener('input', () => {
        state.draft.force[part] = westernDigits(input.value.trim());
        refresh();
      });
      updaters.push(() => {
        const v = state.draft.force[part];
        input.classList.toggle('has-error', v !== '' && !R.parseDay(v));
      });
      return input;
    };
    const from = dateBox('from', 'First day, optional');
    const to = dateBox('to', 'Last day, optional');
    const reset = () => {
      state.draft.force = { scene: '', from: '', to: '' };
      scene.value = '';
      from.value = '';
      to.value = '';
      refresh();
    };
    const clearBtn = h('button', { type: 'button', class: 'btn', id: 'forceClear', onclick: reset }, 'Clear');
    const line = h('p', { class: 'when' });
    const noteBox = h('div');
    updaters.push(() => {
      const f = state.draft.force;
      line.textContent = f.scene ? 'Its line: “' + draftLine(f.scene) + '”' : '';
      const none = !f.scene && !f.from && !f.to;
      clearBtn.disabled = none;
      clear(noteBox).appendChild(builtInNote('nothing forced', none, reset));
    });
    return h('div', { class: 'card', id: 'force' },
      h('h2', null, 'Play one scene for everyone'),
      h('div', { class: 'force-warn' }, banner('danger', 'This overrides every other rule.',
        'While it is set, every open of the app plays this one scene, whatever the hour, the month, Ramadan, Eid, night, a first launch or a switch above. Leave the dates blank and it plays until you clear it.')),
      h('div', { class: 'force-row field-row' },
        scene,
        h('label', null, 'From'), from,
        h('label', null, 'to'), to,
        clearBtn),
      h('div', { class: 'hint' }, 'Both dates optional, both days included.'),
      line,
      noteBox);
  }

  function today() {
    const d = new Date();
    const p = (n) => String(n).padStart(2, '0');
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
  }

  function checkBox(id, text, isOn, setOn) {
    const box = h('input', { type: 'checkbox', id });
    box.checked = isOn();
    box.addEventListener('change', () => { setOn(box.checked); refresh(); });
    const span = h('span', null, text);
    return { label: h('label', { class: 'check', for: id }, box, span), span };
  }

  function previewCard() {
    const q = state.preview;
    const date = h('input', { type: 'text', class: 'date', dir: 'ltr', autocomplete: 'off', placeholder: 'yyyy-mm-dd', 'aria-label': 'Date', value: q.date });
    date.addEventListener('input', () => { q.date = westernDigits(date.value.trim()); refresh(); });
    const hour = h('select', { class: 'pick', 'aria-label': 'Hour', style: 'min-width: 0' });
    for (let i = 0; i < 24; i++) hour.appendChild(h('option', { value: String(i) }, String(i).padStart(2, '0') + ':00'));
    hour.value = String(q.hour);
    hour.addEventListener('change', () => { q.hour = Number(hour.value); refresh(); });

    const flag = (key, text) => checkBox('q-' + key, text, () => !!q[key], (on) => { q[key] = on; }).label;
    const away = checkBox('q-away', '', () => !!q.away, (on) => { q.away = on; });
    updaters.push(() => {
      const days = state.draft.awayDays;
      away.span.textContent = 'Away ' + (Number.isInteger(days) ? days : '?') + ' days or more';
    });
    const installed = smallBox('Installed days ago', q.installedDaysAgo, (v) => { q.installedDaysAgo = v; });
    const updatedAgo = smallBox('Days since the update', q.updateDaysAgo, (v) => { q.updateDaysAgo = v; });

    const facts = h('div', { class: 'preview-grid' },
      flag('freshInstall', 'Fresh install: the very first launch'),
      away.label,
      flag('updated', 'Updated, the new version scene not played yet'),
      flag('perfectYesterday', 'Yesterday: every owed habit was done'),
      flag('stepsYesterday', 'Yesterday: the steps goal was reached'),
      flag('walker', 'Has a walking or steps habit'),
      flag('fastPlanned', 'A fast is on today’s plan'),
      flag('ramadan', 'It is a day of Ramadan'),
      flag('dayBeforeRamadan', 'It is the day before Ramadan'),
      flag('eid', 'It is a day of Eid'));
    const numbers = h('div', { class: 'preview-row' },
      h('label', null, 'Installed'), installed, h('span', { class: 'unit' }, 'days ago (blank: had the app before this was kept)'),
      h('label', null, 'Updated'), updatedAgo, h('span', { class: 'unit' }, 'days ago'));

    const playedNames = ['fullDay', 'stepsGoal', 'saturday', 'morningCoffee', 'winterWait']
      .concat(R.SCENE_NAMES.filter((n) => Object.prototype.hasOwnProperty.call(builtIn().onceADay, n)));
    const played = h('div', { class: 'chips' }, playedNames.map((name) => {
      const chip = h('button', { type: 'button', class: 'chip', 'aria-pressed': 'false' }, R.sceneLabel(name));
      chip.addEventListener('click', () => { q.played[name] = !q.played[name]; refresh(); });
      updaters.push(() => chip.setAttribute('aria-pressed', String(!!q.played[name])));
      return chip;
    }));
    const poolNames = R.poolScenes(builtIn());
    const seen = h('div', { class: 'chips' }, poolNames.map((name) => {
      const chip = h('button', { type: 'button', class: 'chip', 'aria-pressed': 'false' }, R.sceneLabel(name));
      chip.addEventListener('click', () => { q.neverSeen[name] = !q.neverSeen[name]; refresh(); });
      updaters.push(() => chip.setAttribute('aria-pressed', String(!!q.neverSeen[name])));
      return chip;
    }));
    const last = h('select', { class: 'pick', 'aria-label': 'The scene the last launch played' });
    last.appendChild(h('option', { value: '' }, 'Not known'));
    for (const s of R.SCENES) last.appendChild(h('option', { value: s.name }, s.label));
    last.value = q.lastScene;
    last.addEventListener('change', () => { q.lastScene = last.value; refresh(); });

    const result = h('div', { class: 'result', id: 'previewResult' });
    updaters.push(() => {
      const out = R.pick(state.check.inForce, q);
      clear(result);
      if (out.error) {
        result.appendChild(h('div', { class: 'big' }, out.error));
        return;
      }
      const skipped = (out.skipped || []).map((t) => h('div', { class: 'small skip' }, t));
      if (out.odds) {
        result.appendChild(h('div', { class: 'big' }, out.odds.length === 1 ? R.sceneLabel(out.odds[0].scene) : 'The anytime list'));
        append(result, skipped);
        result.appendChild(h('div', { class: 'small' }, out.reason));
        out.notes.forEach((n) => result.appendChild(h('div', { class: 'small' }, n)));
        const rows = h('div', { class: 'pool-bars' });
        for (const o of out.odds) {
          const pc = Math.round(o.chance * 100);
          rows.appendChild(h('div', { class: 'pool-row' },
            h('span', { class: 'nm' }, R.sceneLabel(o.scene)),
            h('span', { class: 'bar' }, h('span', { class: 'fill', style: 'width: ' + pc + '%' })),
            h('span', { class: 'pc' }, pc + '%'),
            h('span', { class: 'sh' }, '“' + draftLine(o.scene) + '”')));
        }
        result.appendChild(rows);
      } else {
        result.appendChild(h('div', { class: 'big' }, R.sceneLabel(out.scene) + (out.forced ? ' (played for everyone)' : '')));
        result.appendChild(h('div', { class: 'small' }, '“' + draftLine(out.scene) + '”'));
        append(result, skipped);
        result.appendChild(h('div', { class: 'small' }, out.reason));
      }
      if (state.check.errors.length) {
        result.appendChild(h('div', { class: 'small' }, 'The draft has errors, so this uses the settings that are valid so far.'));
      }
    });

    return h('div', { class: 'card', id: 'preview' },
      h('h2', null, 'What plays when'),
      h('p', { class: 'about' }, 'Pick a day and an hour and say what is true for that open. This shows the scene your draft would play, or the anytime list’s odds, before you save. It reads nothing from any account.'),
      h('div', { class: 'preview-row' },
        h('label', null, 'Date'), date, h('label', null, 'Hour'), hour),
      facts,
      numbers,
      h('div', { class: 'preview-sub' }, 'Already played today (the day turns at 04:00)'), played,
      h('div', { class: 'preview-sub' }, 'Never shown on this phone (anytime list, and a missed first launch)'), seen,
      h('div', { class: 'preview-row' }, h('label', null, 'The last launch played'), last),
      result);
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
    const edition = getComputedStyle(document.documentElement).getPropertyValue('--splash-styles').trim().replace(/['"]/g, '');
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
      box.appendChild(banner('warn', 'The launch splash settings were saved from somewhere else since this page loaded.',
        'Reload the page to see them, then make your change again.'));
    }
  }

  function render() {
    updaters = [];
    const root = clear($('viewSplash'));
    root.appendChild(scenesCard());
    root.appendChild(slowLineCard());
    root.appendChild(orderCard());
    root.appendChild(anytimeCard());
    root.appendChild(timingCard());
    root.appendChild(forceCard());
    root.appendChild(previewCard());
    root.appendChild(saveBar());
    renderBanners();
    refresh();
  }

  function takeData(data) {
    state.data = data;
    state.saved = R.draftFrom(data.builtIn, data.resolved);
    state.draft = clone(state.saved);
    state.serverErrors = [];
  }

  async function saveNow() {
    state.saving = true;
    state.serverErrors = [];
    refresh();
    try {
      const res = await fetch('/api/splash', {
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
        takeData(Object.assign({}, body.splash, { phones: state.data.phones }));
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
      const res = await fetch('/api/splash');
      body = await res.json();
      if (!res.ok) throw new Error(body.error || 'The admin tool answered ' + res.status + '.');
    } catch (e) {
      clear($('viewSplash')).appendChild(banner('danger', 'Could not load the launch splash settings.', e.message));
      return;
    }
    state.preview = {
      date: today(),
      hour: new Date().getHours(),
      freshInstall: false,
      installedDaysAgo: '',
      away: false,
      updated: false,
      updateDaysAgo: 0,
      perfectYesterday: false,
      stepsYesterday: false,
      walker: false,
      fastPlanned: false,
      ramadan: false,
      dayBeforeRamadan: false,
      eid: false,
      played: {},
      neverSeen: {},
      lastScene: '',
    };
    takeData(body);
    render();
  }

  start();
})();
