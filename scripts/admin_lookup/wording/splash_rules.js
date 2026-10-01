/**
 * The launch splash's settings on the admin's Splash page: the sixteen
 * scenes by name, how the stored edits are laid over the app's built-in
 * values, how a page draft is checked and turned back into edits, and the
 * "what plays when" preview (a port of pickLaunchScene and
 * pickAnytimeScene).
 * Shared by the browser (splash/app.js) and the server (lib/splash_admin.js),
 * for the same reason as rules.js: the checks run as you type and again on
 * every save, from one copy.
 *
 * The app does the same in lib/features/launch/launch_settings.dart. Both are
 * held to one set of cases (test/fixtures/splash_cases.json, run by
 * test/splash.test.js here and test/features/launch/launch_settings_test.dart
 * in the app), so what the page shows before Save is what phones do after it.
 *
 * The built-in values are not copied here. The server reads them out of
 * launch_settings.dart and launch_scene.dart itself (lib/splash_admin.js) and
 * hands them to the page, so a change in the app's code shows here without
 * anyone copying it.
 *
 * No em dash anywhere in this file, including comments (see rules.js).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.SplashRules = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * Every scene, in the app's enum order (LaunchScene). `when`: the rule
   * only the app's code knows, which the page cannot change. "Once a day"
   * means once a launch day, which turns at 04:00.
   */
  const SCENES = [
    { name: 'morningCoffee', label: 'Morning coffee', when: 'Once a day inside its hours, on the first open no bigger moment took. Never when a fast is on today’s plan, and never in Ramadan or the day before it.' },
    { name: 'dayRing', label: 'Day ring', when: 'No rule of its own: it plays from the anytime list. When the anytime list has nothing that can play, the day ring plays anyway.' },
    { name: 'turnaround', label: 'Turnaround', when: 'No rule of its own: it plays from the anytime list.' },
    { name: 'eveningChecklist', label: 'Evening checklist', when: 'Inside its hours, on every open or once a day, as its switch below says.' },
    { name: 'nightAsleep', label: 'Asleep at night', when: 'Inside its hours, on every open or once a day, as its switch below says. Quiet: no hop.' },
    { name: 'ramadanLantern', label: 'Ramadan', when: 'On a day of Ramadan, on every open or once a day, as its switch below says.' },
    { name: 'welcomeBack', label: 'Welcome back', when: 'The first open after the number of days away set under Timing.' },
    { name: 'firstOpen', label: 'First launch', when: 'The very first launch after the app is installed. If something else took that launch, it waits until it has played, for the days set under Timing.' },
    { name: 'eid', label: 'Eid lights', when: 'On a day of Eid, on every open or once a day, as its switch below says.' },
    { name: 'fullDay', label: 'Full day', when: 'Once, the day after a day with every owed habit done. If a bigger moment takes the first open, it plays on the next one.' },
    { name: 'saturday', label: 'Saturday recap', when: 'Once on Saturday, from its From hour, which is when the week’s recap is ready.' },
    { name: 'update', label: 'New version', when: 'After the app is updated, until its scene has played once, for the days set under Timing.' },
    { name: 'stepsGoal', label: 'Steps goal', when: 'Once, the day after a day the steps goal was reached. If a bigger moment takes the first open, it plays on the next one.' },
    { name: 'summerNoon', label: 'Summer noon', when: 'Inside its hours and months, on every open or once a day, as its switch below says.' },
    { name: 'winterWait', label: 'Missing winter', when: 'Once a day inside its hours and months. Later opens can still draw it from the anytime list.' },
    { name: 'walk', label: 'Walk', when: 'In the walkers’ hour, for someone with a walking or steps habit, on every open or once a day, as its switch below says. Its own hours and months below limit it everywhere, the anytime list included.' },
  ];

  const SCENE_NAMES = SCENES.map((s) => s.name);
  const SCENE_SET = new Set(SCENE_NAMES);

  function sceneByName(name) {
    return SCENES.find((s) => s.name === name) || { name, label: name, when: '' };
  }

  function sceneLabel(name) {
    return sceneByName(name).label;
  }

  const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

  /** The words the curtain draws on a green row of their own. */
  const BRAND = 'Grow Daily';

  /**
   * The numbers, in the page's order. Their ranges come with the built-in
   * values. `seconds`: stored in milliseconds, shown as seconds. `toggle`: 0
   * or 1, shown as a switch.
   */
  const NUMBERS = [
    {
      key: 'minShowMs',
      label: 'The curtain stays at least',
      unit: 'seconds',
      seconds: true,
      help: 'Long enough for Doum’s scene to read. A load that is ready sooner still waits this long.',
    },
    {
      key: 'maxShowMs',
      label: 'The curtain stays at most',
      unit: 'seconds',
      seconds: true,
      help: 'The longest it stays, ready or not. At least one second more than the shortest.',
    },
    {
      key: 'replayAfterMinutes',
      label: 'Plays again after being away',
      unit: 'minutes',
      help: 'Coming back to the app after this long shows the curtain again. A new day shows it whatever the gap.',
    },
    {
      key: 'awayDays',
      label: 'Days away that count as coming back',
      unit: 'days',
      help: 'The first open after this many days or more plays the welcome back scene.',
    },
    {
      key: 'firstOpenDays',
      label: 'Days the first launch scene waits',
      unit: 'days',
      help: 'If another scene took the very first launch, the first launch scene still plays once within this many days.',
    },
    {
      key: 'updateDays',
      label: 'Days the new version scene waits',
      unit: 'days',
      help: 'After an update the new version scene plays once within this many days, then is dropped as old news.',
    },
    {
      key: 'walkerFromHour',
      label: 'Walkers’ hour: from',
      walker: true,
      help: '',
    },
    {
      key: 'walkerToHour',
      label: 'Walkers’ hour: to',
      walker: true,
      help: '',
    },
    {
      key: 'newFirst',
      label: 'Show scenes this phone has never seen first',
      toggle: true,
      help: 'In the anytime list, a scene this phone has never shown wins over the shares, so a new scene is seen soon after it ships.',
    },
    {
      key: 'noRepeat',
      label: 'Never the same scene twice in a row',
      toggle: true,
      help: 'In the anytime list, the scene the last launch played is left out when another one can play.',
    },
  ];

  const NUMBER_KEYS = NUMBERS.map((n) => n.key);

  function isObject(v) {
    return !!v && typeof v === 'object' && !Array.isArray(v);
  }

  /** A date as yyyy-mm-dd, a real one (no 02-31), or null. */
  function parseDay(text) {
    if (typeof text !== 'string') return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    if (!m) return null;
    const y = Number(m[1]);
    const mo = Number(m[2]);
    const d = Number(m[3]);
    const date = new Date(Date.UTC(y, mo - 1, d));
    if (date.getUTCFullYear() !== y || date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d) return null;
    return { y, mo, d, text, weekday: date.getUTCDay() };
  }

  function allInts(list) {
    return Array.isArray(list) && list.every((v) => Number.isInteger(v));
  }

  /** A line as the app keeps it (LaunchSettings._cleanLine): trimmed, inner spaces as one. */
  function tidyLine(text) {
    return typeof text === 'string' ? text.trim().replace(/\s+/g, ' ') : '';
  }

  /** The tidied line, or null when the app would drop it (empty or too long). */
  function cleanLine(text, max) {
    if (typeof text !== 'string') return null;
    const line = tidyLine(text);
    return line.length === 0 || line.length > max ? null : line;
  }

  /**
   * A number from 0 to 99 fixed for [scene] on the launch day [y]-[m]-[d]:
   * the scene plays that day when it is below its chance. A port of the
   * app's launchDayRoll (launch_settings.dart), Park and Miller's generator
   * over the scene's name and the date; every product stays below 2^53, so
   * plain numbers are exact.
   */
  function launchDayRoll(scene, y, m, d) {
    const M = 2147483647;
    let h = 0;
    for (let i = 0; i < scene.length; i++) h = (h * 31 + scene.charCodeAt(i)) % M;
    h = (h + y * 372 + m * 31 + d) % M;
    for (let i = 0; i < 3; i++) h = (h * 48271) % M;
    return h % 100;
  }

  /** Whether [scene] plays on the launch day y-m-d by its chance (LaunchSettings.playsOn). */
  function playsOn(inForce, scene, y, m, d) {
    const percent = inForce.chance[scene];
    return percent === undefined || launchDayRoll(scene, y, m, d) < percent;
  }

  /** The calendar day [days] after y-m-d, as { y, m, d, weekday }. */
  function addDays(y, m, d, days) {
    const t = new Date(Date.UTC(y, m - 1, d + days));
    return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate(), weekday: t.getUTCDay() };
  }

  /**
   * Which of the [count] launch days from y-m-d [scene] plays on by its
   * chance: [{ y, m, d, weekday, plays }].
   */
  function chanceDays(inForce, scene, y, m, d, count) {
    const out = [];
    for (let i = 0; i < count; i++) {
      const day = addDays(y, m, d, i);
      out.push(Object.assign(day, { plays: playsOn(inForce, scene, day.y, day.m, day.d) }));
    }
    return out;
  }

  /**
   * What is in force: [builtIn] with the stored [edits] laid over them, the
   * way the app does it (LaunchSettings.from), in the shape of its describe().
   * A value the app would drop (out of its range, not whole, a name it does
   * not know) is dropped here too.
   */
  function resolve(builtIn, edits) {
    const e = isObject(edits) ? edits : {};
    const out = {};
    for (const key of NUMBER_KEYS) {
      const [min, max] = builtIn.ranges[key];
      const v = e[key];
      out[key] = Number.isInteger(v) && v >= min && v <= max ? v : builtIn.numbers[key];
    }

    const order = [];
    if (Array.isArray(e.order)) {
      for (const name of e.order) {
        if (typeof name === 'string' && builtIn.order.includes(name) && !order.includes(name)) order.push(name);
      }
    }
    for (const name of builtIn.order) if (!order.includes(name)) order.push(name);
    out.order = order;

    const off = new Set(Array.isArray(e.off) ? e.off.filter((n) => typeof n === 'string' && SCENE_SET.has(n)) : []);
    out.off = SCENE_NAMES.filter((n) => off.has(n));

    const hours = {};
    for (const [name, pair] of Object.entries(builtIn.hours)) hours[name] = pair.slice();
    if (isObject(e.hours)) {
      for (const [name, pair] of Object.entries(e.hours)) {
        if (!SCENE_SET.has(name) || !Array.isArray(pair) || pair.length !== 2 || !allInts(pair)) continue;
        const [from, to] = pair;
        if (from < 0 || from > 23 || to < 0 || to > 24 || from === to) continue;
        hours[name] = [from, to];
      }
    }
    out.hours = hours;

    const months = {};
    for (const [name, list] of Object.entries(builtIn.months)) months[name] = list.slice().sort((a, b) => a - b);
    if (isObject(e.months)) {
      for (const [name, list] of Object.entries(e.months)) {
        if (!SCENE_SET.has(name) || !allInts(list)) continue;
        const valid = [...new Set(list.filter((m) => m >= 1 && m <= 12))].sort((a, b) => a - b);
        if (valid.length === 0) delete months[name];
        else months[name] = valid;
      }
    }
    out.months = months;

    const pool = Object.assign({}, builtIn.pool);
    if (isObject(e.pool)) {
      for (const [name, share] of Object.entries(e.pool)) {
        if (!Object.prototype.hasOwnProperty.call(builtIn.pool, name)) continue;
        if (!Number.isInteger(share) || share < 0 || share > builtIn.poolMax) continue;
        pool[name] = share;
      }
    }
    out.pool = {};
    for (const name of SCENE_NAMES) if (pool[name] > 0) out.pool[name] = pool[name];

    const once = new Set(Object.keys(builtIn.onceADay).filter((n) => builtIn.onceADay[n] === 1));
    if (isObject(e.onceADay)) {
      for (const [name, value] of Object.entries(e.onceADay)) {
        if (!Object.prototype.hasOwnProperty.call(builtIn.onceADay, name) || !Number.isInteger(value)) continue;
        if (value === 1) once.add(name);
        if (value === 0) once.delete(name);
      }
    }
    out.onceADay = SCENE_NAMES.filter((n) => once.has(n));

    const chance = Object.assign({}, builtIn.chance);
    if (isObject(e.chance)) {
      for (const [name, percent] of Object.entries(e.chance)) {
        if (!SCENE_SET.has(name) || !Number.isInteger(percent) || percent < 0 || percent > 100) continue;
        chance[name] = percent;
      }
    }
    out.chance = {};
    for (const name of SCENE_NAMES) {
      if (chance[name] !== undefined && chance[name] !== 100) out.chance[name] = chance[name];
    }

    const lines = {};
    if (isObject(e.lines)) {
      for (const [name, text] of Object.entries(e.lines)) {
        const line = cleanLine(text, builtIn.lineMax);
        if (SCENE_SET.has(name) && line !== null) lines[name] = line;
      }
    }
    out.lines = {};
    for (const name of SCENE_NAMES) if (lines[name] !== undefined) out.lines[name] = lines[name];
    const slow = cleanLine(e.slowLine, builtIn.lineMax);
    out.slowLine = slow === null ? builtIn.slowLine : slow;

    let force = null;
    const f = isObject(e.force) ? e.force : null;
    if (f && typeof f.scene === 'string' && SCENE_SET.has(f.scene)) {
      const from = typeof f.from === 'string' && parseDay(f.from) ? f.from : null;
      const to = typeof f.to === 'string' && parseDay(f.to) ? f.to : null;
      if (!(from && to && to < from)) force = { scene: f.scene, from, to };
    }
    out.force = force;
    return out;
  }

  /** The scenes that may have a share in the anytime list. */
  function poolScenes(builtIn) {
    return SCENE_NAMES.filter((n) => Object.prototype.hasOwnProperty.call(builtIn.pool, n));
  }

  /**
   * The page's draft: every setting as it is in force. Hours are [from, to]
   * with '' for blank (no limit); months a list, empty for every month; a
   * share for every scene that may have one, 0 for out; a line for every
   * scene; the forced scene '' for none.
   */
  function draftFrom(builtIn, resolved) {
    const draft = {};
    for (const key of NUMBER_KEYS) draft[key] = resolved[key];
    if (resolved.walkerFromHour === resolved.walkerToHour) {
      draft.walkerFromHour = '';
      draft.walkerToHour = '';
    }
    draft.order = resolved.order.slice();
    draft.off = resolved.off.slice();
    draft.hours = {};
    draft.months = {};
    draft.lines = {};
    for (const name of SCENE_NAMES) {
      const pair = resolved.hours[name];
      draft.hours[name] = pair && !(pair[0] === 0 && pair[1] === 24) ? pair.slice() : ['', ''];
      draft.months[name] = (resolved.months[name] || []).slice();
      draft.lines[name] = resolved.lines[name] !== undefined ? resolved.lines[name] : builtIn.lines[name];
    }
    draft.pool = {};
    for (const name of poolScenes(builtIn)) draft.pool[name] = resolved.pool[name] || 0;
    draft.onceADay = {};
    for (const name of SCENE_NAMES) {
      if (Object.prototype.hasOwnProperty.call(builtIn.onceADay, name)) draft.onceADay[name] = resolved.onceADay.includes(name) ? 1 : 0;
    }
    draft.chance = {};
    for (const name of builtIn.order) draft.chance[name] = resolved.chance[name] !== undefined ? resolved.chance[name] : 100;
    draft.slowLine = resolved.slowLine;
    const f = resolved.force;
    draft.force = f ? { scene: f.scene, from: f.from || '', to: f.to || '' } : { scene: '', from: '', to: '' };
    return draft;
  }

  function isBlank(v) {
    return v === '' || v === null || v === undefined;
  }

  /** The hours a draft pair means: null for none, else [from, to]. */
  function hoursOf(pair) {
    if (!Array.isArray(pair) || (isBlank(pair[0]) && isBlank(pair[1]))) return null;
    if (pair[0] === 0 && pair[1] === 24) return null;
    return pair;
  }

  function sameList(a, b) {
    return a.length === b.length && a.every((v, i) => v === b[i]);
  }

  function formatRange(n, min, max) {
    return n.seconds ? `${min / 1000} to ${max / 1000} seconds` : `${min} to ${max}`;
  }

  function hourName(h) {
    return h === 24 ? 'midnight' : String(h).padStart(2, '0') + ':00';
  }

  /**
   * One line's check, shared by the page's own box and checkDraft: errors
   * block Save, a warning only says how it will be drawn.
   */
  function lineIssues(text, max) {
    const line = tidyLine(text);
    if (line.length === 0) return { error: 'cannot be empty. Use the built-in line to go back.' };
    if (line.length > max) return { error: `is ${line.length} characters, ${max} at most.` };
    if (line.indexOf(BRAND) < 0) return { warning: `has no “${BRAND}”, so it is drawn whole, with no green row.` };
    return {};
  }

  /**
   * Checks a page draft and turns it into what wording/live.splash stores:
   * only what differs from the built-in values, so a setting nobody changed
   * keeps following the app's code. `edits` is null when nothing differs.
   */
  function checkDraft(builtIn, draft) {
    const errors = [];
    const warnings = [];
    const d = isObject(draft) ? draft : {};
    const edits = {};

    let numbersOk = true;
    // The walkers' hour: both blank is none, stored as the same hour twice.
    const walkerBlank = isBlank(d.walkerFromHour) && isBlank(d.walkerToHour);
    if (!walkerBlank && (isBlank(d.walkerFromHour) || isBlank(d.walkerToHour))) {
      errors.push('Walk: fill in both walkers’ hours, or clear both for no walkers’ hour.');
    }
    for (const n of NUMBERS) {
      let v = d[n.key];
      if (n.walker) {
        if (walkerBlank) v = 0;
        else if (isBlank(v)) continue;
      }
      const [min, max] = builtIn.ranges[n.key];
      if (!Number.isInteger(v) || v < min || v > max) {
        errors.push(n.toggle ? `${n.label}: on or off.`
          : n.walker ? `Walk: the walkers’ ${n.key === 'walkerFromHour' ? 'From' : 'To'} hour is a whole number from ${min} to ${max}.`
            : `${n.label}: a number from ${formatRange(n, min, max)}.`);
        if (n.key === 'minShowMs' || n.key === 'maxShowMs') numbersOk = false;
        continue;
      }
      if (v !== builtIn.numbers[n.key]) edits[n.key] = v;
    }
    if (numbersOk && d.maxShowMs < d.minShowMs + 1000) {
      errors.push('The curtain’s longest stay must be at least one second more than its shortest.');
    }

    // The precedence: the same fourteen scenes, each once.
    const order = Array.isArray(d.order) ? d.order : [];
    const wanted = builtIn.order;
    const orderOk = order.length === wanted.length && new Set(order).size === order.length
      && order.every((n) => wanted.includes(n));
    if (!orderOk) errors.push(`The order must list each of the ${wanted.length} scenes once.`);
    else if (!sameList(order, wanted)) edits.order = order.slice();

    const off = [];
    for (const name of Array.isArray(d.off) ? d.off : []) {
      if (!SCENE_SET.has(name)) errors.push(`"${name}" is not a scene.`);
      else if (!off.includes(name)) off.push(name);
    }
    const offSorted = SCENE_NAMES.filter((n) => off.includes(n));
    if (offSorted.length) edits.off = offSorted;

    const hours = {};
    const months = {};
    const lines = {};
    const draftHours = isObject(d.hours) ? d.hours : {};
    const draftMonths = isObject(d.months) ? d.months : {};
    const draftLines = isObject(d.lines) ? d.lines : {};
    for (const name of SCENE_NAMES) {
      const label = sceneLabel(name);
      const pair = draftHours[name];
      if (pair !== undefined) {
        const both = Array.isArray(pair) ? pair : ['', ''];
        if (hoursOf(both) !== null) {
          const [from, to] = both;
          if (isBlank(from) || isBlank(to)) {
            errors.push(`${label}: fill in both hours, or clear both for no limit.`);
          } else if (!Number.isInteger(from) || from < 0 || from > 23) {
            errors.push(`${label}: the From hour is a whole number from 0 to 23.`);
          } else if (!Number.isInteger(to) || to < 0 || to > 24) {
            errors.push(`${label}: the To hour is a whole number from 0 to 24.`);
          } else if (from === to) {
            errors.push(`${label}: From and To cannot be the same hour. Clear both for no limit.`);
          } else {
            const base = builtIn.hours[name];
            if (!base || base[0] !== from || base[1] !== to) hours[name] = [from, to];
          }
        } else if (builtIn.hours[name]) {
          // The app's own hours are removed by the whole day, 0 to 24.
          hours[name] = [0, 24];
        }
      }
      const list = draftMonths[name];
      if (list !== undefined) {
        if (!allInts(list) || list.some((m) => m < 1 || m > 12)) {
          errors.push(`${label}: months are 1 to 12.`);
        } else {
          let set = [...new Set(list)].sort((a, b) => a - b);
          if (set.length === 12) set = [];
          const base = (builtIn.months[name] || []).slice().sort((a, b) => a - b);
          if (!sameList(set, base)) months[name] = set;
        }
      }
      const text = draftLines[name];
      if (text !== undefined) {
        const issue = lineIssues(text, builtIn.lineMax);
        if (issue.error) errors.push(`${label}: the line ${issue.error}`);
        else {
          const line = tidyLine(text);
          if (issue.warning && line !== builtIn.lines[name]) warnings.push(`${label}: the line ${issue.warning}`);
          if (line !== builtIn.lines[name]) lines[name] = line;
        }
      }
    }
    if (Object.keys(hours).length) edits.hours = hours;
    if (Object.keys(months).length) edits.months = months;

    const pool = {};
    const draftPool = isObject(d.pool) ? d.pool : {};
    for (const name of poolScenes(builtIn)) {
      const v = draftPool[name];
      if (v === undefined) continue;
      if (!Number.isInteger(v) || v < 0 || v > builtIn.poolMax) {
        errors.push(`${sceneLabel(name)}: its share in the anytime list is a whole number from 0 to ${builtIn.poolMax}.`);
        continue;
      }
      if (v !== builtIn.pool[name]) pool[name] = v;
    }
    for (const name of Object.keys(draftPool)) {
      if (!Object.prototype.hasOwnProperty.call(builtIn.pool, name)) errors.push(`${sceneLabel(name)} cannot be in the anytime list.`);
    }
    if (Object.keys(pool).length) edits.pool = pool;

    const once = {};
    const draftOnce = isObject(d.onceADay) ? d.onceADay : {};
    for (const [name, v] of Object.entries(draftOnce)) {
      if (!Object.prototype.hasOwnProperty.call(builtIn.onceADay, name)) {
        errors.push(`${sceneLabel(name)} cannot be switched to once a day.`);
        continue;
      }
      if (v !== 0 && v !== 1) {
        errors.push(`${sceneLabel(name)}: once a day is on or off.`);
        continue;
      }
      if (v !== builtIn.onceADay[name]) once[name] = v;
    }
    if (Object.keys(once).length) edits.onceADay = once;

    const chance = {};
    const draftChance = isObject(d.chance) ? d.chance : {};
    for (const [name, v] of Object.entries(draftChance)) {
      if (!wanted.includes(name)) {
        errors.push(`${sceneLabel(name)} cannot have a share of days.`);
        continue;
      }
      if (!Number.isInteger(v) || v < 0 || v > 100) {
        errors.push(`${sceneLabel(name)}: how often is a whole percent from 0 to 100.`);
        continue;
      }
      const base = builtIn.chance[name] !== undefined ? builtIn.chance[name] : 100;
      if (v !== base) chance[name] = v;
    }
    if (Object.keys(chance).length) edits.chance = chance;
    if (Object.keys(lines).length) edits.lines = lines;

    if (d.slowLine !== undefined) {
      const issue = lineIssues(d.slowLine, builtIn.lineMax);
      if (issue.error) errors.push(`The slow load line ${issue.error}`);
      else {
        const line = tidyLine(d.slowLine);
        if (issue.warning && line !== builtIn.slowLine) warnings.push(`The slow load line ${issue.warning}`);
        if (line !== builtIn.slowLine) edits.slowLine = line;
      }
    }

    const f = isObject(d.force) ? d.force : { scene: '' };
    if (!isBlank(f.scene)) {
      if (!SCENE_SET.has(f.scene)) {
        errors.push(`"${f.scene}" is not a scene.`);
      } else {
        const force = { scene: f.scene };
        let datesOk = true;
        for (const part of ['from', 'to']) {
          if (isBlank(f[part])) continue;
          if (!parseDay(f[part])) {
            errors.push(`Play one scene for everyone: the ${part} date is a day written like 2026-12-31.`);
            datesOk = false;
          } else {
            force[part] = f[part];
          }
        }
        if (datesOk && force.from && force.to && force.to < force.from) {
          errors.push('Play one scene for everyone: the last day cannot come before the first.');
        }
        edits.force = force;
      }
    } else if (!isBlank(f.from) || !isBlank(f.to)) {
      errors.push('Play one scene for everyone: pick the scene, or clear the dates.');
    }

    if (!errors.length) {
      const inForce = resolve(builtIn, Object.keys(edits).length ? edits : null);
      for (const name of SCENE_NAMES) {
        if (inForce.off.includes(name)) continue;
        if (!canEverMatch(inForce, name)) {
          warnings.push(`${sceneLabel(name)} can never play: its hours and months leave no moment.`);
        }
      }
      for (const name of wanted) {
        if (!inForce.off.includes(name) && inForce.chance[name] === 0) {
          warnings.push(`${sceneLabel(name)} plays on 0% of days, so it never plays from the order.`);
        }
      }
      if (wanted.every((n) => inForce.off.includes(n))) {
        warnings.push('Every scene in the order is switched off, so only the anytime list will play.');
      }
      const live = Object.keys(inForce.pool).filter((n) => !inForce.off.includes(n));
      if (live.length === 0) {
        warnings.push('The anytime list is empty (every share is 0, or its scenes are off), so the day ring plays whenever no rule holds.');
      }
      const walkers = walkerWindow(inForce);
      if (!inForce.off.includes('walk')) {
        let walkerMoment = false;
        for (let hour = 0; hour < 24; hour++) {
          if (walkers && windowHas(walkers, hour) && windowHas(inForce.hours.walk, hour)) walkerMoment = true;
        }
        if (walkers && !walkerMoment) {
          warnings.push('Walk: the walkers’ hour falls outside the walk’s own hours, so walkers never get their moment.');
        }
        if (!walkerMoment && !(inForce.pool.walk > 0)) {
          warnings.push('Walk can never play: it has no walkers’ hour inside its own hours and no share in the anytime list.');
        }
      }
      if (inForce.force && !inForce.force.to) {
        warnings.push('One scene plays for everyone with no last day: it keeps playing, over every other rule, until you clear it.');
      }
    }
    return { errors, warnings, edits: Object.keys(edits).length ? edits : null };
  }

  /** Whether a window holds [hour] (the app's LaunchWindow.contains). */
  function windowHas(pair, hour) {
    if (!pair) return true;
    const [from, to] = pair;
    return from < to ? hour >= from && hour < to : hour >= from || hour < to;
  }

  /** The walkers' hour as a window, or null for none (LaunchSettings.walkerHours). */
  function walkerWindow(inForce) {
    const from = inForce.walkerFromHour;
    const to = inForce.walkerToHour;
    return from === to ? null : [from, to];
  }

  function walkerHas(inForce, hour) {
    const w = walkerWindow(inForce);
    return !!w && windowHas(w, hour);
  }

  /** Whether any month and hour of the year passes a scene's own limits. */
  function canEverMatch(inForce, name) {
    const pair = inForce.hours[name];
    const list = inForce.months[name];
    for (let hour = 0; hour < 24; hour++) {
      if (!windowHas(pair, hour)) continue;
      if (!list || list.length) return true;
    }
    return false;
  }

  /** Whether [name] may play at [hour] of [month] by its switch, hours and months (LaunchSettings.allows). */
  function allows(inForce, name, hour, month) {
    if (inForce.off.includes(name)) return false;
    if (!windowHas(inForce.hours[name], hour)) return false;
    const months = inForce.months[name];
    return !(months && !months.includes(month));
  }

  /** Each scene's part of the anytime list, ignoring hours: [{ scene, share, chance }]. */
  function poolShares(inForce) {
    const entries = Object.keys(inForce.pool).map((scene) => ({ scene, share: inForce.pool[scene] }));
    const total = entries.reduce((sum, e) => sum + e.share, 0);
    return entries.map((e) => Object.assign(e, { chance: total ? e.share / total : 0 }));
  }

  /**
   * The anytime list's odds at [hour] of [month] (pickAnytimeScene): its
   * scenes that can play then, the never-seen ones first when newFirst is
   * on, without the last launch's scene when noRepeat is on and another can
   * play, each by its share. The day ring alone when none can.
   */
  function anytimeOdds(inForce, hour, month, q) {
    const neverSeen = (q && q.neverSeen) || {};
    const lastScene = (q && q.lastScene) || '';
    const notes = [];
    let candidates = SCENE_NAMES.filter((n) => inForce.pool[n] > 0 && allows(inForce, n, hour, month));
    if (candidates.length === 0) {
      return { odds: [{ scene: 'dayRing', share: 0, chance: 1 }], notes: ['Nothing in the anytime list can play at this hour, so the day ring plays.'] };
    }
    if (inForce.newFirst === 1) {
      const unseen = candidates.filter((n) => neverSeen[n]);
      if (unseen.length) {
        candidates = unseen;
        notes.push('Never seen first: only the scenes this phone has never shown.');
      }
    }
    if (inForce.noRepeat === 1 && candidates.length > 1 && candidates.includes(lastScene)) {
      candidates = candidates.filter((n) => n !== lastScene);
      notes.push(`Never twice in a row: ${sceneLabel(lastScene)} is left out.`);
    }
    const total = candidates.reduce((sum, n) => sum + inForce.pool[n], 0);
    return {
      odds: candidates.map((n) => ({ scene: n, share: inForce.pool[n], chance: inForce.pool[n] / total })),
      notes,
    };
  }

  /**
   * Which scene a launch plays: a port of pickLaunchScene
   * (lib/features/launch/launch_scene.dart) for the "what plays when" tool,
   * from [inForce] (resolve's output) and the [q]uestion: { date
   * 'yyyy-mm-dd', hour, freshInstall, installedDaysAgo (a number, or '' for a
   * phone that had the app before this was kept), away, updated,
   * updateDaysAgo, perfectYesterday, stepsYesterday, walker, fastPlanned,
   * ramadan, dayBeforeRamadan, eid (walker plays the walk inside the
   * walkers' hour), played: { scene: true } for "already
   * played today", neverSeen: { scene: true }, lastScene }.
   *
   * Returns { scene, reason } for a scene a rule chose, or { scene: null,
   * odds: [{ scene, share, chance }], notes } when the anytime list decides
   * (scene is set too when only one can play).
   */
  function pick(inForce, q) {
    const day = parseDay(q.date);
    if (!day) return { error: 'Enter the date like 2026-12-31.' };
    const hour = q.hour;
    // The launch day turns at 04:00: an open before it belongs to the day before.
    const launchDay = hour < 4 ? addDays(day.y, day.mo, day.d, -1) : { y: day.y, m: day.mo, d: day.d };
    const month = day.mo;
    const fresh = !!q.freshInstall;
    const played = q.played || {};
    const neverSeen = q.neverSeen || {};

    const f = inForce.force;
    if (f && (!f.from || day.text >= f.from) && (!f.to || day.text <= f.to)) {
      return { scene: f.scene, reason: 'Played for everyone: it overrides every other rule.', forced: true };
    }

    function holds(name) {
      switch (name) {
        case 'firstOpen':
          if (fresh) return true;
          return Number.isInteger(q.installedDaysAgo) && !!neverSeen.firstOpen
            && q.installedDaysAgo < inForce.firstOpenDays;
        case 'welcomeBack': return !fresh && !!q.away;
        case 'update':
          return !!q.updated && (!Number.isInteger(q.updateDaysAgo) || q.updateDaysAgo < inForce.updateDays);
        case 'ramadanLantern': return !!q.ramadan;
        case 'eid': return !!q.eid;
        case 'fullDay': return !!q.perfectYesterday && !played.fullDay;
        case 'stepsGoal': return !!q.stepsYesterday && !played.stepsGoal;
        case 'saturday': {
          const h = inForce.hours.saturday;
          const from = h ? h[0] : 10;
          return day.weekday === 6 && hour >= from && !played.saturday;
        }
        case 'morningCoffee':
          return !played.morningCoffee && !q.fastPlanned && !q.ramadan && !q.dayBeforeRamadan;
        case 'winterWait': return !played.winterWait;
        case 'walk': return !!q.walker && walkerHas(inForce, hour);
        default: return true;
      }
    }

    // Moments that would have played but stepped aside, said in the result.
    const skipped = [];
    for (const name of inForce.order) {
      if (!allows(inForce, name, hour, month)) continue;
      if (inForce.onceADay.includes(name) && played[name]) {
        if (holds(name)) skipped.push(`${sceneLabel(name)} already played today (once a day).`);
        continue;
      }
      if (!playsOn(inForce, name, launchDay.y, launchDay.m, launchDay.d)) {
        if (holds(name)) skipped.push(`${sceneLabel(name)} steps aside today (${inForce.chance[name]}% of days).`);
        continue;
      }
      if (holds(name)) {
        return { scene: name, reason: sceneByName(name).when, skipped };
      }
    }

    const any = anytimeOdds(inForce, hour, month, q);
    return {
      scene: any.odds.length === 1 ? any.odds[0].scene : null,
      odds: any.odds,
      notes: any.notes,
      skipped,
      reason: 'No rule in the order holds, so the anytime list plays.',
    };
  }

  /** A value with its object keys sorted, for comparing two stored forms. */
  function canonical(v) {
    if (Array.isArray(v)) return v.map(canonical);
    if (v && typeof v === 'object') {
      const out = {};
      for (const k of Object.keys(v).sort()) out[k] = canonical(v[k]);
      return out;
    }
    return v === undefined ? null : v;
  }

  function same(a, b) {
    return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
  }

  return {
    SCENES,
    SCENE_NAMES,
    MONTH_NAMES,
    BRAND,
    NUMBERS,
    NUMBER_KEYS,
    sceneLabel,
    sceneByName,
    parseDay,
    hourName,
    hoursOf,
    windowHas,
    tidyLine,
    cleanLine,
    lineIssues,
    poolScenes,
    poolShares,
    anytimeOdds,
    allows,
    walkerWindow,
    launchDayRoll,
    playsOn,
    addDays,
    chanceDays,
    resolve,
    draftFrom,
    checkDraft,
    pick,
    canonical,
    same,
  };
});
