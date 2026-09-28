/**
 * Doum's settings on the «دوم» page: his praise lists and the app's habit
 * categories by name, how the stored edits are laid over the app's built-in
 * values, and how a page draft is checked and turned back into edits.
 * Shared by the browser (pet/app.js) and the server (lib/pet_admin.js), for
 * the same reason as rules.js: the checks run as you type and again on
 * every save, from one copy.
 *
 * The app does the same in lib/features/mascot/pet_settings.dart. Both are
 * held to one set of cases (test/fixtures/pet_cases.json, run by
 * test/pet.test.js here and test/features/mascot/pet_settings_test.dart in
 * the app), so what the page shows before Save is what phones do after it.
 *
 * The built-in values are not copied here. The server reads them out of
 * pet_settings.dart itself (lib/pet_admin.js) and hands them to the page, so
 * a change in the app's code shows here without anyone copying it across.
 *
 * No em dash anywhere in this file, including comments (see rules.js).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.PetRules = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /** Doum's praise lists (PraiseGroup in the app), in the page's order. */
  const LISTS = [
    { name: 'general', ar: 'عام', en: 'General' },
    { name: 'faith', ar: 'الإيمان', en: 'Faith' },
    { name: 'quran', ar: 'القرآن', en: 'Quran' },
    { name: 'athkar', ar: 'الأذكار', en: 'Athkar' },
    { name: 'fasting', ar: 'الصيام', en: 'Fasting' },
    { name: 'sadaqah', ar: 'الصدقة', en: 'Sadaqah' },
    { name: 'sport', ar: 'الرياضة', en: 'Sport' },
    { name: 'health', ar: 'الصحة', en: 'Health' },
    { name: 'learning', ar: 'التعلّم', en: 'Learning' },
    { name: 'focus', ar: 'التركيز', en: 'Focus' },
    { name: 'sleep', ar: 'النوم', en: 'Sleep' },
    { name: 'money', ar: 'المال', en: 'Money' },
    { name: 'mind', ar: 'العقل', en: 'Mind' },
    { name: 'social', ar: 'العلاقات', en: 'Relationships' },
  ];

  /**
   * The app's habit categories (HabitCategory). `chip`: one of Add Habit's
   * chips, the only categories a habit someone types can have. The other
   * five belong to ready-made habits only.
   */
  const CATEGORIES = [
    { name: 'faith', ar: 'الإيمان', en: 'Faith', chip: true },
    { name: 'health', ar: 'الصحة', en: 'Health', chip: true },
    { name: 'learning', ar: 'التعلّم', en: 'Learning', chip: true },
    { name: 'focus', ar: 'التركيز', en: 'Focus', chip: true },
    { name: 'sleep', ar: 'النوم', en: 'Sleep', chip: true },
    { name: 'money', ar: 'المال', en: 'Money', chip: true },
    { name: 'mind', ar: 'العقل', en: 'Mind', chip: true },
    { name: 'social', ar: 'العلاقات', en: 'Relationships', chip: true },
    { name: 'custom', ar: 'مخصص', en: 'No category', chip: true },
    { name: 'quran', ar: 'القرآن', en: 'Quran', chip: false },
    { name: 'athkar', ar: 'الأذكار', en: 'Athkar', chip: false },
    { name: 'fasting', ar: 'الصيام', en: 'Fasting', chip: false },
    { name: 'sadaqah', ar: 'الصدقة', en: 'Sadaqah', chip: false },
    { name: 'fitness', ar: 'الرياضة', en: 'Sport', chip: false },
  ];

  /** The numbers, in the page's order. Their ranges come with the built-in values. */
  const NUMBERS = [
    {
      key: 'praiseEverySeconds',
      label: 'Seconds between two praise lines',
      unit: 'seconds',
      help: 'Every habit done still gets its hop at once; only the words wait. The streak point and a full day always speak. 0 lets every habit speak.',
    },
    {
      key: 'bubbleSeconds',
      label: 'Seconds a speech bubble stays',
      unit: 'seconds',
      help: 'How long each line stays before it fades.',
    },
    {
      key: 'rememberLines',
      label: 'Lines remembered',
      unit: 'lines',
      help: 'The last lines he said, none of which he says again until his lists run out. Kept on the phone across launches.',
    },
    {
      key: 'morningUntilHour',
      label: 'Morning ends at',
      unit: 'o’clock',
      help: 'Before this hour an empty day gets the morning hello (sproutMorning), from it the other one (sproutHello).',
    },
    {
      key: 'bedtimeHour',
      label: 'Bedtime on a finished day',
      unit: 'o’clock',
      help: 'From this hour a day with every habit done sleeps (sproutGoodNight).',
    },
    {
      key: 'wakeHour',
      label: 'Wakes at',
      unit: 'o’clock',
      help: 'After midnight an empty new day sleeps until this hour (sproutLateNight). 0 never sleeps then.',
    },
  ];

  /**
   * The day's three confetti moments, smallest to biggest (Aziz, 2026-09-28:
   * each must feel bigger than the one before). Every habit done fires two
   * bursts, the second a beat after the first.
   */
  const CONFETTI = [
    { id: 'square', title: 'A habit finished', about: 'Flies from the habit’s own square, the moment a tap finishes it for the day.' },
    { id: 'streak', title: 'The streak point', about: 'From the middle of the screen, with the pop-up, on the tap that makes the day count toward the streak.' },
    { id: 'fullDay', title: 'Every habit done: first burst', about: 'The biggest moment of the day, with a strong buzz.' },
    { id: 'fullDaySecond', title: 'Every habit done: second burst', about: 'A beat after the first, with a second buzz.' },
  ];

  // Three numbers per burst.
  for (const c of CONFETTI) {
    NUMBERS.push(
      { key: c.id + 'ConfettiPieces', confetti: c.id, title: c.title + ': pieces', label: 'Pieces', unit: 'pieces', help: '0 fires no confetti at all.' },
      { key: c.id + 'ConfettiSpread', confetti: c.id, title: c.title + ': spread', label: 'Spread', unit: 'points', help: 'How far the pieces fly.' },
      { key: c.id + 'ConfettiMs', confetti: c.id, title: c.title + ': lasts', label: 'Lasts', unit: 'ms', help: '1000 is one second.' },
    );
  }

  const LIST_NAMES = new Set(LISTS.map((l) => l.name));
  const CATEGORY_NAMES = new Set(CATEGORIES.map((c) => c.name));
  const NUMBER_KEYS = NUMBERS.map((n) => n.key);

  function isList(v) {
    return typeof v === 'string' && LIST_NAMES.has(v);
  }

  function isObject(v) {
    return !!v && typeof v === 'object' && !Array.isArray(v);
  }

  /** A stored map's entries whose value is text, the way the app reads them. */
  function textEntries(raw) {
    if (!isObject(raw)) return [];
    return Object.keys(raw)
      .filter((k) => typeof raw[k] === 'string')
      .map((k) => [k, raw[k]]);
  }

  /**
   * What is in force: [builtIn] with the stored [edits] laid over them, the
   * way the app does it (PetSettings.from). A value the app would drop (out
   * of its range, not whole, a name it does not know) is dropped here too.
   */
  function resolve(builtIn, edits) {
    const e = isObject(edits) ? edits : {};
    const out = {};
    for (const key of NUMBER_KEYS) {
      const [min, max] = builtIn.ranges[key];
      const v = e[key];
      out[key] = Number.isInteger(v) && v >= min && v <= max ? v : builtIn.numbers[key];
    }
    const presets = Object.assign({}, builtIn.presets);
    for (const [id, name] of textEntries(e.presets)) {
      if (!id) continue;
      if (name === '') delete presets[id];
      else if (isList(name)) presets[id] = name;
    }
    const categories = Object.assign({}, builtIn.categories);
    for (const [category, name] of textEntries(e.categories)) {
      if (CATEGORY_NAMES.has(category) && isList(name)) categories[category] = name;
    }
    const alsoHears = Object.assign({}, builtIn.alsoHears);
    for (const [list, wider] of textEntries(e.alsoHears)) {
      if (!isList(list)) continue;
      if (wider === '') delete alsoHears[list];
      else if (isList(wider) && wider !== list) alsoHears[list] = wider;
    }
    // Every other list turns to the general one once its own lines are all
    // said; the general list draws on nothing.
    delete alsoHears.general;
    out.presets = presets;
    out.categories = categories;
    out.alsoHears = alsoHears;
    out.quit = isList(e.quit) ? e.quit : builtIn.quit;
    return out;
  }

  /**
   * The list one ready-made habit hears, as the app picks it
   * (praiseGroupFor): its own list, else the quit list for a quit habit,
   * else its category's.
   */
  function listFor(resolved, habit) {
    const own = resolved.presets[habit.id];
    if (own) return own;
    if (habit.goalType === 'quit') return resolved.quit;
    return resolved.categories[habit.category] || 'general';
  }

  /**
   * The page's draft: every setting as it is in force. Every ready-made
   * habit is named, '' for "follows its category"; every list but the
   * general one says what it also draws on, '' for nothing.
   */
  function draftFrom(resolved, presetIds) {
    const draft = {};
    for (const key of NUMBER_KEYS) draft[key] = resolved[key];
    draft.presets = {};
    for (const id of presetIds) draft.presets[id] = resolved.presets[id] || '';
    draft.categories = Object.assign({}, resolved.categories);
    draft.alsoHears = {};
    for (const l of LISTS) {
      if (l.name !== 'general') draft.alsoHears[l.name] = resolved.alsoHears[l.name] || '';
    }
    draft.quit = resolved.quit;
    return draft;
  }

  function listLabel(name) {
    const l = LISTS.find((x) => x.name === name);
    return l ? l.en : name;
  }

  /**
   * Checks a page draft and turns it into what wording/live.pet stores:
   * only what differs from the built-in values, so a setting nobody changed
   * keeps following the app's code. `edits` is null when nothing differs.
   */
  function checkDraft(builtIn, draft, presetIds) {
    const errors = [];
    const warnings = [];
    const d = isObject(draft) ? draft : {};
    const edits = {};

    for (const n of NUMBERS) {
      const v = d[n.key];
      const [min, max] = builtIn.ranges[n.key];
      if (!Number.isInteger(v) || v < min || v > max) {
        errors.push(`${n.title || n.label}: a whole number from ${min} to ${max}.`);
        continue;
      }
      if (v !== builtIn.numbers[n.key]) edits[n.key] = v;
    }

    const known = new Set(presetIds);
    const presets = {};
    for (const [id, name] of Object.entries(isObject(d.presets) ? d.presets : {})) {
      if (!known.has(id)) {
        errors.push(`The app has no ready-made habit "${id}".`);
        continue;
      }
      if (name !== '' && !isList(name)) {
        errors.push(`"${name}" is not one of Doum's lists.`);
        continue;
      }
      if (name !== (builtIn.presets[id] || '')) presets[id] = name;
    }
    if (Object.keys(presets).length) edits.presets = presets;

    const categories = {};
    const draftCategories = isObject(d.categories) ? d.categories : {};
    for (const c of CATEGORIES) {
      const name = draftCategories[c.name];
      if (name === undefined) continue;
      if (!isList(name)) {
        errors.push(`${c.en}: "${name}" is not one of Doum's lists.`);
        continue;
      }
      if (name !== builtIn.categories[c.name]) categories[c.name] = name;
    }
    if (Object.keys(categories).length) edits.categories = categories;

    const alsoHears = {};
    const draftAlso = isObject(d.alsoHears) ? d.alsoHears : {};
    for (const l of LISTS) {
      const wider = draftAlso[l.name];
      if (wider === undefined) continue;
      if (l.name === 'general') {
        if (wider !== '') errors.push('The general list cannot draw on another list.');
        continue;
      }
      if (wider !== '' && !isList(wider)) {
        errors.push(`${l.en}: "${wider}" is not one of Doum's lists.`);
        continue;
      }
      if (wider === l.name) {
        errors.push(`${l.en} cannot draw on itself.`);
        continue;
      }
      if (wider !== (builtIn.alsoHears[l.name] || '')) alsoHears[l.name] = wider;
    }
    if (Object.keys(alsoHears).length) edits.alsoHears = alsoHears;

    if (d.quit !== undefined) {
      if (!isList(d.quit)) errors.push(`Quit habits: "${d.quit}" is not one of Doum's lists.`);
      else if (d.quit !== builtIn.quit) edits.quit = d.quit;
    }

    if (!errors.length) {
      const inForce = resolve(builtIn, edits);
      if (inForce.morningUntilHour <= inForce.wakeHour) {
        warnings.push('Doum sleeps until the wake hour, so a morning that ends at or before it never gets the morning hello.');
      }
      if (inForce.bubbleSeconds > inForce.praiseEverySeconds && inForce.praiseEverySeconds > 0) {
        warnings.push('A bubble stays longer than the gap between two praise lines, so a new line can replace one still being read.');
      }
      const fullDayPieces = Math.max(inForce.fullDayConfettiPieces, inForce.fullDaySecondConfettiPieces);
      if (fullDayPieces < inForce.streakConfettiPieces) {
        warnings.push('Every habit done now fires fewer confetti pieces than the streak point, so the biggest moment looks smaller.');
      }
      if (inForce.streakConfettiPieces < inForce.squareConfettiPieces) {
        warnings.push('The streak point now fires fewer confetti pieces than a single finished habit.');
      }
    }
    return { errors, warnings, edits: Object.keys(edits).length ? edits : null };
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
    LISTS,
    CATEGORIES,
    NUMBERS,
    CONFETTI,
    NUMBER_KEYS,
    isList,
    resolve,
    listFor,
    listLabel,
    draftFrom,
    checkDraft,
    canonical,
    same,
  };
});
