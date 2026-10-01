/**
 * Add Habit's habit ideas and ready-made plans, on the admin's Habit ideas
 * page: how the stored edits (wording/live `ideas` and `plans`) are read
 * and laid over the app's built-in lists, how one idea is checked, and how
 * the page's draft is turned back into edits. Shared by the browser
 * (ideas/app.js) and the server (lib/ideas_admin.js), for the same reason
 * as rules.js: the checks run as you type and again on every save, from
 * one copy.
 *
 * The app does the same in lib/features/habits/catalog/habit_ideas.dart
 * (resolveIdeas, resolvePlans) over lib/core/l10n/ideas_edits.dart. Both
 * are held to one set of cases, test/fixtures/ideas_cases.json, run by
 * test/ideas.test.js here and by the app's own test, so what this page
 * shows before Publish is what phones show after it.
 *
 * Two kinds of rule live here, kept apart on purpose:
 *   - READING (ideaFromJson, withText, resolveIdeas, resolvePlans): what
 *     phones do with whatever the document holds. Lenient the app's way:
 *     a field of the wrong type is ignored, an added idea missing anything
 *     is dropped whole. These are the ones the fixture holds both sides to.
 *   - CHECKING (checkDraft): what this page lets you publish. Stricter: the
 *     lengths, the copy rules and the shapes of the data spec. Nothing the
 *     page refuses can reach a phone, so the two never disagree in practice.
 *
 * The built-in lists are not copied here: the server reads the ideas from
 * assets/data/habit_ideas.json and the plans out of habit_plans.dart
 * (lib/ideas_admin.js) and hands them to the page.
 *
 * Needs rules.js (window.WordingRules) loaded first in the browser.
 *
 * No em dash anywhere in this file, including comments (see rules.js).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./rules'));
  } else {
    root.IdeasRules = factory(root.WordingRules);
  }
})(typeof self !== 'undefined' ? self : this, function (R) {
  'use strict';

  const ch = (code) => String.fromCharCode(code);
  const EM_DASH = ch(0x2014);

  // ---- The words the data uses -----------------------------------------------

  const TYPES = ['build', 'quit'];

  /** The nine categories of the data spec, with the app's own labels. */
  const CATEGORIES = [
    { id: 'faith', en: 'Faith', ar: 'الإيمان' },
    { id: 'health', en: 'Health', ar: 'الصحة' },
    { id: 'learning', en: 'Learning', ar: 'التعلّم' },
    { id: 'focus', en: 'Focus', ar: 'التركيز' },
    { id: 'sleep', en: 'Sleep', ar: 'النوم' },
    { id: 'money', en: 'Money', ar: 'المال' },
    { id: 'mind', en: 'Mind', ar: 'العقل' },
    { id: 'social', en: 'Social', ar: 'العلاقات' },
    { id: 'custom', en: 'Custom', ar: 'مخصص' },
  ];
  const CATEGORY_IDS = CATEGORIES.map((c) => c.id);

  const PRAYERS = [
    { id: 'fajr', en: 'Fajr' },
    { id: 'dhuhr', en: 'Dhuhr' },
    { id: 'asr', en: 'Asr' },
    { id: 'maghrib', en: 'Maghrib' },
    { id: 'isha', en: 'Isha' },
  ];
  const PRAYER_IDS = PRAYERS.map((p) => p.id);

  const LIMIT_UNITS = [
    { id: 'minutes', en: 'minutes' },
    { id: 'times', en: 'times' },
    { id: 'cups', en: 'cups' },
    { id: 'money', en: 'money' },
  ];
  const LIMIT_UNIT_IDS = LIMIT_UNITS.map((u) => u.id);

  /** ISO weekdays, Monday 1 to Sunday 7, as `often` writes them. */
  const WEEKDAYS = [
    { n: 1, en: 'Monday' },
    { n: 2, en: 'Tuesday' },
    { n: 3, en: 'Wednesday' },
    { n: 4, en: 'Thursday' },
    { n: 5, en: 'Friday' },
    { n: 6, en: 'Saturday' },
    { n: 7, en: 'Sunday' },
  ];

  /**
   * The fields of a BUILT-IN idea the admin may change (`text`), in the one
   * order they are applied. `type`, `id` and `featured` are not among them:
   * a built-in idea keeps its type, and featured has its own map.
   */
  const TEXT_FIELDS = [
    'nameAr', 'nameEn', 'shortAr', 'shortEn', 'benefitAr', 'benefitEn',
    'sourceAr', 'sourceEn', 'waysAr', 'waysEn', 'category', 'often',
    'timesPerDay', 'reminder', 'limit',
  ];
  const WORD_FIELDS = ['nameAr', 'nameEn', 'shortAr', 'shortEn', 'benefitAr', 'benefitEn'];
  const PLAN_TEXT_FIELDS = ['nameAr', 'nameEn', 'descAr', 'descEn'];

  /**
   * The longest text the app READS for each field (HabitIdea.fromJson):
   * generous caps that only stop junk. What this page lets you WRITE is
   * LIMITS below, the data spec's sizes.
   */
  const READ_MAX = {
    id: 64,
    nameAr: 60,
    nameEn: 60,
    shortAr: 120,
    shortEn: 160,
    benefitAr: 400,
    benefitEn: 400,
    sourceAr: 80,
    sourceEn: 80,
  };
  const MAX_WAYS_READ = 4;

  /** The data spec's sizes, checked when the page publishes. */
  const LIMITS = {
    nameAr: 32,
    nameEn: 40,
    shortAr: 60,
    shortEn: 60,
    benefitAr: 220,
    benefitEn: 220,
    sourceAr: 60,
    sourceEn: 60,
    way: 70,
    planNameAr: 40,
    planNameEn: 40,
    planDescAr: 160,
    planDescEn: 160,
  };
  const MAX_ADDED = 150;
  const MAX_LIMIT_AMOUNT = 9999;
  const MAX_ID_LENGTH = 64;

  /** How the ids of ideas made on this page begin. A built-in id never does. */
  const ADDED_PREFIX = 'a-';
  const ADDED_ID_SHAPE = /^a-[a-z0-9]{3,40}$/;
  const BUILT_IN_ID_SHAPE = /^[a-z0-9_]{2,40}$/;

  /** Words the copy rules keep out of an idea (warnings, not errors). */
  const PRAISE_WORDS = ['بطل', 'أبطال', 'أسطورة', 'أسطوري'];
  const PROMISE_WORDS = ['يعالج', 'يشفي', 'علاج'];

  const FIELD_LABEL = {
    nameAr: 'name in Arabic',
    nameEn: 'name in English',
    shortAr: 'card line in Arabic',
    shortEn: 'card line in English',
    benefitAr: 'benefit in Arabic',
    benefitEn: 'benefit in English',
    sourceAr: 'source in Arabic',
    sourceEn: 'source in English',
    waysAr: 'ways to start in Arabic',
    waysEn: 'ways to start in English',
    category: 'category',
    often: 'how often',
    timesPerDay: 'times a day',
    reminder: 'reminder',
    limit: 'limit',
    type: 'type',
    featured: 'featured',
    descAr: 'description in Arabic',
    descEn: 'description in English',
  };

  // ---- Small readers, the app's way -------------------------------------------

  function isMap(v) {
    return !!v && typeof v === 'object' && !Array.isArray(v);
  }

  /** [map]'s own value under [key], or undefined (an id is text from the
   *  document, and a plain object would answer "toString" from its prototype). */
  function own(map, key) {
    return isMap(map) && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined;
  }

  // Dart's trim also drops U+0085 (next line) at either end; JavaScript's
  // does not. Stripped here too, so both sides agree on what is blank.
  const NEL_ENDS = new RegExp('^' + ch(0x85) + '+|' + ch(0x85) + '+$', 'g');

  function dartTrim(s) {
    let t = s.trim();
    for (;;) {
      const next = t.replace(NEL_ENDS, '').trim();
      if (next === t) return t;
      t = next;
    }
  }

  /**
   * Dart's int.tryParse with no radix: surrounding whitespace, a sign and a
   * 0x prefix are all taken, nothing else is. The app reads every number in
   * `often` and `reminder` through it.
   */
  function dartInt(s) {
    if (typeof s !== 'string') return null;
    const m = /^([+-]?)(?:0[xX]([0-9a-fA-F]+)|([0-9]+))$/.exec(dartTrim(s));
    if (!m) return null;
    const v = m[2] !== undefined ? parseInt(m[2], 16) : parseInt(m[3], 10);
    if (!Number.isSafeInteger(v)) return null;
    return m[1] === '-' ? -v : v;
  }

  /** A trimmed, non-blank string of at most [max] characters, or null. */
  function readText(v, max) {
    if (typeof v !== 'string') return null;
    const t = dartTrim(v);
    return t.length === 0 || t.length > max ? null : t;
  }

  /** The strings of a list, trimmed, blanks and non-strings left out; 1 to 4 of them, or null. */
  function readWays(v) {
    if (!Array.isArray(v)) return null;
    const out = [];
    for (const w of v) {
      if (typeof w === 'string' && dartTrim(w).length) out.push(dartTrim(w));
    }
    return out.length === 0 || out.length > MAX_WAYS_READ ? null : out;
  }

  /**
   * `often` read the app's way (IdeaOften.parse): { kind: 'daily' } |
   * { kind: 'weekly', times } | { kind: 'days', days: [ascending ISO days] },
   * or null for anything else.
   */
  function parseOften(raw) {
    if (typeof raw !== 'string') return null;
    const v = dartTrim(raw);
    if (v === 'daily') return { kind: 'daily' };
    if (v.startsWith('weekly:')) {
      const n = dartInt(v.slice(7));
      return n === null || n < 1 || n > 6 ? null : { kind: 'weekly', times: n };
    }
    if (v.startsWith('days:')) {
      const days = new Set();
      for (const part of v.slice(5).split(',')) {
        const d = dartInt(dartTrim(part));
        if (d === null || d < 1 || d > 7) return null;
        days.add(d);
      }
      if (!days.size) return null;
      return { kind: 'days', days: [...days].sort((a, b) => a - b) };
    }
    return null;
  }

  /** The stored form of a read `often`: "daily", "weekly:3", "days:1,4". */
  function oftenString(often) {
    if (!often) return null;
    if (often.kind === 'daily') return 'daily';
    if (often.kind === 'weekly') return 'weekly:' + often.times;
    return 'days:' + often.days.join(',');
  }

  function pad2(n) {
    return String(n).padStart(2, '0');
  }

  /** A reminder read the app's way, in its stored form ("prayer:fajr",
   *  "time:07:30"), or null. */
  function readReminder(raw) {
    if (typeof raw !== 'string') return null;
    if (raw.startsWith('prayer:')) {
      const p = raw.slice(7);
      return PRAYER_IDS.includes(p) ? 'prayer:' + p : null;
    }
    if (raw.startsWith('time:')) {
      const parts = raw.slice(5).split(':');
      if (parts.length !== 2) return null;
      const h = dartInt(parts[0]);
      const m = dartInt(parts[1]);
      if (h === null || m === null || h < 0 || h > 23 || m < 0 || m > 59) return null;
      return 'time:' + pad2(h) + ':' + pad2(m);
    }
    return null;
  }

  /** A limit read the app's way, { amount, unit }, or null. */
  function readLimit(raw) {
    if (!isMap(raw)) return null;
    const amount = raw.amount;
    const unit = raw.unit;
    if (!Number.isInteger(amount) || amount < 1) return null;
    if (typeof unit !== 'string' || !LIMIT_UNIT_IDS.includes(unit)) return null;
    return { amount, unit };
  }

  function readTimes(raw) {
    return Number.isInteger(raw) && raw >= 2 && raw <= 12 ? raw : 1;
  }

  // ---- One idea ------------------------------------------------------------------

  /**
   * The idea in [json], read the way the app reads it (HabitIdea.fromJson),
   * or null when anything a card or its detail needs is missing or
   * malformed: an idea is shown whole or not at all. Optional fields that
   * do not fit (a reminder it cannot read, times a day on a weekly habit, a
   * limit on a habit to build) are left off, not the idea.
   *
   * The result is the canonical idea every function here works with: every
   * key present, null for "none", timesPerDay 1 for once a day.
   */
  function ideaFromJson(json, id) {
    if (!isMap(json)) return null;
    const ideaId = id !== undefined ? id : readText(json.id, READ_MAX.id);
    const type = json.type === 'build' || json.type === 'quit' ? json.type : null;
    const category = typeof json.category === 'string' && CATEGORY_IDS.includes(json.category) ? json.category : null;
    const words = {};
    for (const f of WORD_FIELDS) words[f] = readText(json[f], READ_MAX[f]);
    const waysAr = readWays(json.waysAr);
    const waysEn = readWays(json.waysEn);
    const often = parseOften(json.often);
    if (ideaId === null || type === null || category === null || waysAr === null || waysEn === null ||
      often === null || WORD_FIELDS.some((f) => words[f] === null)) {
      return null;
    }
    return {
      id: ideaId,
      type,
      category,
      nameAr: words.nameAr,
      nameEn: words.nameEn,
      shortAr: words.shortAr,
      shortEn: words.shortEn,
      benefitAr: words.benefitAr,
      benefitEn: words.benefitEn,
      sourceAr: readText(json.sourceAr, READ_MAX.sourceAr),
      sourceEn: readText(json.sourceEn, READ_MAX.sourceEn),
      waysAr,
      waysEn,
      often: oftenString(often),
      timesPerDay: often.kind === 'daily' && type === 'build' ? readTimes(json.timesPerDay) : 1,
      reminder: readReminder(json.reminder),
      limit: type === 'quit' ? readLimit(json.limit) : null,
      featured: json.featured === true,
    };
  }

  /**
   * Why the app would not read [json] as an idea, in words, for the page's
   * note on the built-in file. Empty when it reads.
   */
  function ideaIssues(json, id) {
    if (!isMap(json)) return ['it is not an object'];
    const out = [];
    if ((id !== undefined ? id : readText(json.id, READ_MAX.id)) === null) out.push('no id');
    if (json.type !== 'build' && json.type !== 'quit') out.push('type is not "build" or "quit"');
    if (!(typeof json.category === 'string' && CATEGORY_IDS.includes(json.category))) out.push('category is not one of the nine');
    for (const f of WORD_FIELDS) {
      if (readText(json[f], READ_MAX[f]) === null) out.push(f + ' is missing, blank or longer than ' + READ_MAX[f]);
    }
    if (readWays(json.waysAr) === null) out.push('waysAr is not a list of 1 to 4');
    if (readWays(json.waysEn) === null) out.push('waysEn is not a list of 1 to 4');
    if (parseOften(json.often) === null) out.push('often is not "daily", "weekly:N" or "days:..."');
    return out;
  }

  /** The idea as the app's toJson writes it: absent fields left out. */
  function toJson(idea) {
    const out = {
      id: idea.id,
      type: idea.type,
      category: idea.category,
      nameAr: idea.nameAr,
      nameEn: idea.nameEn,
      shortAr: idea.shortAr,
      shortEn: idea.shortEn,
      benefitAr: idea.benefitAr,
      benefitEn: idea.benefitEn,
    };
    if (idea.sourceAr !== null) out.sourceAr = idea.sourceAr;
    if (idea.sourceEn !== null) out.sourceEn = idea.sourceEn;
    out.waysAr = idea.waysAr.slice();
    out.waysEn = idea.waysEn.slice();
    out.often = idea.often;
    if (idea.timesPerDay > 1) out.timesPerDay = idea.timesPerDay;
    if (idea.reminder !== null) out.reminder = idea.reminder;
    if (idea.limit !== null) out.limit = { amount: idea.limit.amount, unit: idea.limit.unit };
    out.featured = idea.featured;
    return out;
  }

  /**
   * A built-in [idea] with the admin's edited [fields] laid over it, field
   * by field, in TEXT_FIELDS' order whatever order the document lists them
   * in. A value of the wrong type is ignored and the idea keeps its own.
   * `null` removes an optional field: the source, the reminder, the limit
   * (quit fully), times a day (once). Then the fields that only go with
   * something else are dropped when it is not there: times a day without a
   * daily habit to build, a limit on a habit to build.
   */
  function withText(idea, fields) {
    if (!isMap(fields)) return idea;
    const out = Object.assign({}, idea, {
      waysAr: idea.waysAr.slice(),
      waysEn: idea.waysEn.slice(),
      limit: idea.limit ? Object.assign({}, idea.limit) : null,
    });
    for (const f of TEXT_FIELDS) {
      if (!Object.prototype.hasOwnProperty.call(fields, f)) continue;
      const v = fields[f];
      switch (f) {
        case 'sourceAr':
        case 'sourceEn': {
          if (v === null) out[f] = null;
          else {
            const t = readText(v, READ_MAX[f]);
            if (t !== null) out[f] = t;
          }
          break;
        }
        case 'waysAr':
        case 'waysEn': {
          const list = readWays(v);
          if (list !== null) out[f] = list;
          break;
        }
        case 'category':
          if (typeof v === 'string' && CATEGORY_IDS.includes(v)) out.category = v;
          break;
        case 'often': {
          const often = parseOften(v);
          if (often) out.often = oftenString(often);
          break;
        }
        case 'timesPerDay':
          if (v === null || v === 1) out.timesPerDay = 1;
          else if (Number.isInteger(v) && v >= 2 && v <= 12) out.timesPerDay = v;
          break;
        case 'reminder': {
          if (v === null) out.reminder = null;
          else {
            const r = readReminder(v);
            if (r !== null) out.reminder = r;
          }
          break;
        }
        case 'limit': {
          if (v === null) out.limit = null;
          else {
            const l = readLimit(v);
            if (l !== null) out.limit = l;
          }
          break;
        }
        default: {
          const t = readText(v, READ_MAX[f]);
          if (t !== null) out[f] = t;
        }
      }
    }
    if (!(out.type === 'build' && out.often === 'daily')) out.timesPerDay = 1;
    if (out.type !== 'quit') out.limit = null;
    return out;
  }

  // ---- The built-in file ----------------------------------------------------------

  /**
   * The ideas in habit_ideas.json's parsed [data], the app's way
   * (parseHabitIdeas): an entry it cannot read, one whose id starts "a-"
   * and a second entry with an id already seen are skipped. [skipped] says
   * which and why, for the page.
   */
  function parseBuiltInIdeas(data) {
    const list = isMap(data) ? data.ideas : null;
    if (!Array.isArray(list)) return { ideas: [], skipped: [], shapeError: 'The file has no "ideas" list.' };
    const ideas = [];
    const skipped = [];
    const seen = new Set();
    list.forEach((raw, i) => {
      const label = isMap(raw) && typeof raw.id === 'string' ? raw.id : 'entry ' + (i + 1);
      if (!isMap(raw)) {
        skipped.push({ label, reasons: ['it is not an object'] });
        return;
      }
      const idea = ideaFromJson(raw);
      if (!idea) {
        skipped.push({ label, reasons: ideaIssues(raw) });
        return;
      }
      if (idea.id.startsWith(ADDED_PREFIX)) {
        skipped.push({ label, reasons: ['its id starts "a-", which only ideas made on this page may'] });
        return;
      }
      if (seen.has(idea.id)) {
        skipped.push({ label, reasons: ['its id is used by an earlier entry'] });
        return;
      }
      seen.add(idea.id);
      ideas.push(idea);
    });
    return { ideas, skipped, shapeError: null };
  }

  // ---- The stored edits, read the app's way ---------------------------------------

  function ids(raw) {
    if (!Array.isArray(raw)) return null;
    return raw.filter((v) => typeof v === 'string' && v.length > 0 && v.length <= MAX_ID_LENGTH);
  }

  function maps(raw) {
    const out = {};
    if (!isMap(raw)) return out;
    for (const [k, v] of Object.entries(raw)) {
      if (k.length <= MAX_ID_LENGTH && isMap(v)) out[k] = v;
    }
    return out;
  }

  /** wording/live's `ideas` as the app reads it (IdeasEdits.fromData), or null. */
  function parseIdeasEdits(raw) {
    if (!isMap(raw)) return null;
    const featured = {};
    if (isMap(raw.featured)) {
      for (const [k, v] of Object.entries(raw.featured)) if (typeof v === 'boolean') featured[k] = v;
    }
    return {
      order: ids(raw.order),
      hidden: ids(raw.hidden) || [],
      featured,
      text: maps(raw.text),
      added: maps(raw.added),
    };
  }

  /** wording/live's `plans` as the app reads it (PlansEdits.fromData), or null. */
  function parsePlansEdits(raw) {
    if (!isMap(raw)) return null;
    const text = {};
    for (const [k, fields] of Object.entries(maps(raw.text))) {
      const row = {};
      for (const f of PLAN_TEXT_FIELDS) {
        const v = fields[f];
        if (typeof v === 'string' && dartTrim(v).length) row[f] = dartTrim(v);
      }
      text[k] = row;
    }
    return { order: ids(raw.order), hidden: ids(raw.hidden) || [], text };
  }

  // ---- Laying the edits over the built-ins ------------------------------------------

  /**
   * The ideas as phones show them (resolveIdeas in habit_ideas.dart):
   *   1. the built-ins in file order, each with its `text` laid over it,
   *      without the hidden ones;
   *   2. then each valid added idea (id starting "a-"), in key order, an
   *      invalid one dropped whole;
   *   3. ordered by `order` for the ids it names that exist, then every
   *      other idea in the order of 1 and 2;
   *   4. featured by `featured[id]` where it names the idea, else its own.
   *
   * [builtIn] is parseBuiltInIdeas' list; [rawEdits] the stored `ideas`.
   * With { keepHidden: true } the hidden built-ins stay in, marked hidden,
   * placed by the same order: the page's list, which shows them greyed.
   *
   * Returns [{ idea, featured, added, hidden }].
   */
  function resolveIdeas(builtIn, rawEdits, opts) {
    const keepHidden = !!(opts && opts.keepHidden);
    const e = parseIdeasEdits(rawEdits) || { order: null, hidden: [], featured: {}, text: {}, added: {} };
    const hidden = new Set(e.hidden);
    const rows = [];
    for (const idea of builtIn) {
      const isHidden = hidden.has(idea.id);
      if (isHidden && !keepHidden) continue;
      const fields = own(e.text, idea.id);
      rows.push({ idea: fields ? withText(idea, fields) : idea, added: false, hidden: isHidden });
    }
    const known = new Set(builtIn.map((i) => i.id));
    for (const key of Object.keys(e.added).sort()) {
      if (!key.startsWith(ADDED_PREFIX) || known.has(key)) continue;
      const idea = ideaFromJson(e.added[key], key);
      if (!idea) continue;
      rows.push({ idea, added: true, hidden: false });
      known.add(key);
    }
    const byId = new Map(rows.map((r) => [r.idea.id, r]));
    const ordered = [];
    const placed = new Set();
    for (const id of e.order || []) {
      const row = byId.get(id);
      if (row && !placed.has(id)) {
        ordered.push(row);
        placed.add(id);
      }
    }
    for (const row of rows) {
      if (!placed.has(row.idea.id)) {
        ordered.push(row);
        placed.add(row.idea.id);
      }
    }
    return ordered.map((r) => {
      const f = own(e.featured, r.idea.id);
      return { idea: r.idea, featured: typeof f === 'boolean' ? f : r.idea.featured, added: r.added, hidden: r.hidden };
    });
  }

  /**
   * The plans as phones show them (resolvePlans): hidden ones taken off,
   * ordered by `order` for the ids it names and code order for the rest,
   * each with its edited words over its own. [builtIn] is
   * [{ id, nameAr, nameEn, descAr, descEn, catalogIds }] in the code's
   * order. { keepHidden: true } keeps the hidden ones in, marked.
   */
  function resolvePlans(builtIn, rawEdits, opts) {
    const keepHidden = !!(opts && opts.keepHidden);
    const e = parsePlansEdits(rawEdits) || { order: null, hidden: [], text: {} };
    const hidden = new Set(e.hidden);
    const shown = builtIn.filter((p) => keepHidden || !hidden.has(p.id));
    const byId = new Map(shown.map((p) => [p.id, p]));
    const ordered = [];
    const placed = new Set();
    for (const id of e.order || []) {
      const p = byId.get(id);
      if (p && !placed.has(id)) {
        ordered.push(p);
        placed.add(id);
      }
    }
    for (const p of shown) {
      if (!placed.has(p.id)) {
        ordered.push(p);
        placed.add(p.id);
      }
    }
    return ordered.map((p) => {
      const t = own(e.text, p.id) || {};
      return {
        id: p.id,
        nameAr: t.nameAr || p.nameAr,
        nameEn: t.nameEn || p.nameEn,
        descAr: t.descAr || p.descAr,
        descEn: t.descEn || p.descEn,
        catalogIds: (p.catalogIds || []).slice(),
        hidden: hidden.has(p.id),
      };
    });
  }

  // ---- The page's draft ---------------------------------------------------------------

  /**
   * One idea as the page edits it: the canonical idea's fields in the forms
   * the editor's boxes hold ('' for no source and no reminder, null for no
   * limit, 1 for once a day), plus where it stands: added on this page,
   * shown (built-ins only can be hidden), featured.
   */
  function rowFromIdea(idea, extra) {
    return {
      id: idea.id,
      added: !!extra.added,
      shown: extra.shown !== false,
      featured: !!extra.featured,
      type: idea.type,
      category: idea.category,
      nameAr: idea.nameAr,
      nameEn: idea.nameEn,
      shortAr: idea.shortAr,
      shortEn: idea.shortEn,
      benefitAr: idea.benefitAr,
      benefitEn: idea.benefitEn,
      sourceAr: idea.sourceAr || '',
      sourceEn: idea.sourceEn || '',
      waysAr: idea.waysAr.slice(),
      waysEn: idea.waysEn.slice(),
      often: idea.often,
      timesPerDay: idea.timesPerDay,
      reminder: idea.reminder || '',
      limit: idea.limit ? { amount: idea.limit.amount, unit: idea.limit.unit } : null,
    };
  }

  /** A new idea's row, empty but for its schedule. */
  function blankRow(id, type, category) {
    return {
      id,
      added: true,
      shown: true,
      featured: false,
      type: TYPES.includes(type) ? type : 'build',
      category: CATEGORY_IDS.includes(category) ? category : 'custom',
      nameAr: '',
      nameEn: '',
      shortAr: '',
      shortEn: '',
      benefitAr: '',
      benefitEn: '',
      sourceAr: '',
      sourceEn: '',
      waysAr: ['', ''],
      waysEn: ['', ''],
      often: 'daily',
      timesPerDay: 1,
      reminder: '',
      limit: null,
    };
  }

  /** A new id for an idea made on this page: "a-" and 8 letters or digits. */
  function newIdeaId(taken) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    for (;;) {
      let out = ADDED_PREFIX;
      for (let i = 0; i < 8; i++) out += alphabet[Math.floor(Math.random() * alphabet.length)];
      if (!taken || !taken.has(out)) return out;
    }
  }

  /**
   * The page's draft from the built-ins and what is stored: every idea (the
   * hidden built-ins too, greyed on the page) and every plan, in the order
   * phones show them. [builtIn] is { ideas: list | null, plans: list | null };
   * a list that could not be read gives null for its part, which the page
   * shows read-only and never sends.
   *
   * [notes] are stored edits phones cannot use, said on the page; they are
   * left out of the draft and go away at the next publish of that part.
   */
  function draftFrom(builtIn, stored) {
    const notes = [];
    let ideas = null;
    if (builtIn.ideas) {
      const rawIdeas = stored ? stored.ideas : null;
      const resolved = resolveIdeas(builtIn.ideas, rawIdeas, { keepHidden: true });
      ideas = resolved.map((r) => rowFromIdea(r.idea, { added: r.added, shown: !r.hidden, featured: r.featured }));
      const e = parseIdeasEdits(rawIdeas);
      if (e) {
        const builtInIds = new Set(builtIn.ideas.map((i) => i.id));
        for (const key of Object.keys(e.added).sort()) {
          if (!ideas.some((r) => r.id === key)) {
            notes.push('Added idea ' + key + ' is stored but phones cannot use it (' +
              (key.startsWith(ADDED_PREFIX) ? (ideaIssues(e.added[key], key).join(', ') || 'its id is taken') : 'its id does not start "a-"') + ').');
          }
        }
        for (const key of Object.keys(e.text).sort()) {
          if (!builtInIds.has(key)) notes.push('Stored edits for ' + key + ', an idea the app does not have, do nothing.');
        }
      }
    }
    let plans = null;
    if (builtIn.plans) {
      plans = resolvePlans(builtIn.plans, stored ? stored.plans : null, { keepHidden: true }).map((p) => ({
        id: p.id,
        shown: !p.hidden,
        nameAr: p.nameAr,
        nameEn: p.nameEn,
        descAr: p.descAr,
        descEn: p.descEn,
      }));
    }
    return { ideas, plans, notes };
  }

  // ---- What a draft field means, in the stored form -------------------------------

  function norm(v) {
    return R.normalizeText(v);
  }

  /**
   * A row's [field] in the form `text` stores it, so it can be compared with
   * the built-in idea's: words trimmed, '' and a once-a-day 1 as null, a
   * schedule or reminder in its canonical spelling when it reads. A value
   * still being typed (a number box holding "x") is passed through as it
   * is, and the checks refuse it.
   */
  function storedValue(row, field) {
    const v = row[field];
    switch (field) {
      case 'sourceAr':
      case 'sourceEn':
        return norm(v) === '' ? null : norm(v);
      case 'waysAr':
      case 'waysEn':
        return Array.isArray(v) ? v.map(norm) : v;
      case 'often': {
        const o = parseOften(v);
        return o ? oftenString(o) : v;
      }
      case 'timesPerDay':
        return v === 1 || v === '' || v === null || v === undefined ? null : v;
      case 'reminder': {
        if (v === '' || v === null || v === undefined) return null;
        return v;
      }
      case 'limit':
        return v ? { amount: v.amount, unit: v.unit } : null;
      case 'category':
      case 'type':
        return v;
      default:
        return norm(v);
    }
  }

  /** The built-in idea's [field] in the same form as storedValue. */
  function builtInValue(idea, field) {
    switch (field) {
      case 'timesPerDay':
        return idea.timesPerDay > 1 ? idea.timesPerDay : null;
      case 'limit':
        return idea.limit ? { amount: idea.limit.amount, unit: idea.limit.unit } : null;
      case 'waysAr':
      case 'waysEn':
        return idea[field].slice();
      default:
        return idea[field] === undefined ? null : idea[field];
    }
  }

  // ---- Checking ------------------------------------------------------------------------

  const ARABIC_LETTER = new RegExp('[' + ch(0x0621) + '-' + ch(0x064A) + ']');
  const LATIN_LETTER = /[A-Za-z]/;

  /**
   * One piece of text, checked against the data spec and the copy rules.
   * Returns { errors, warnings } as short sentences about [label].
   */
  function checkWords(label, lang, text, max, opts) {
    const errors = [];
    const warnings = [];
    const t = norm(text);
    if (!t) {
      if (!(opts && opts.optional)) errors.push(cap(label) + ' is empty.');
      return { errors, warnings };
    }
    if (t.length > max) errors.push(cap(label) + ' is ' + t.length + ' characters, ' + max + ' at most.');
    if (t.includes(EM_DASH)) errors.push(cap(label) + ' has an em dash. Use a comma, a colon or a full stop.');
    if (t.includes('!')) errors.push(cap(label) + ' has an exclamation mark. The app\'s copy uses none.');
    if (/\n/.test(t) && !(opts && opts.multiline)) errors.push(cap(label) + ' is more than one line.');
    if (lang === 'ar') {
      if (!ARABIC_LETTER.test(t)) warnings.push(cap(label) + ' has no Arabic letters.');
      for (const rule of R.ARABIC_STYLE) {
        if (rule.test.test(t)) warnings.push(cap(label) + ': ' + rule.say);
      }
      const praise = PRAISE_WORDS.find((w) => t.includes(w));
      if (praise) warnings.push(cap(label) + ': no praise of the person («' + praise + '»).');
      const promise = PROMISE_WORDS.find((w) => t.includes(w));
      if (promise) warnings.push(cap(label) + ': no medical promises («' + promise + '»). Say plainly what it does.');
    } else {
      if (ARABIC_LETTER.test(t)) warnings.push(cap(label) + ' has Arabic letters in the English text.');
      if (/\b(cures?|heals?|treats?)\b/i.test(t)) warnings.push(cap(label) + ': no medical promises. Say plainly what it does.');
      if (/\b(hero|legend)\b/i.test(t)) warnings.push(cap(label) + ': no praise of the person.');
    }
    if (lang === 'ar' && LATIN_LETTER.test(t) && t.replace(/[^A-Za-z]/g, '').length > t.length / 2) {
      warnings.push(cap(label) + ' looks like English.');
    }
    return { errors, warnings };
  }

  function cap(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  /** How [often] is written, as the page needs it: an error, or null. */
  function oftenProblem(value) {
    if (typeof value !== 'string' || !value) return 'How often is missing.';
    if (value.startsWith('days:') && value.length === 5) return 'Pick at least one day.';
    const o = parseOften(value);
    if (!o) return 'How often is not one the app knows ("' + value + '").';
    if (oftenString(o) !== value) return 'How often should be written "' + oftenString(o) + '".';
    return null;
  }

  function reminderProblem(value) {
    if (value === '' || value === null || value === undefined) return null;
    if (typeof value !== 'string') return 'The reminder is not one the app knows.';
    if (value.startsWith('prayer:')) return PRAYER_IDS.includes(value.slice(7)) ? null : 'Pick the prayer.';
    if (value.startsWith('time:')) {
      return /^time:([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) ? null : 'The reminder time is a 24-hour time like 07:30.';
    }
    return 'The reminder is not one the app knows.';
  }

  function limitProblem(limit) {
    if (limit === null || limit === undefined) return null;
    if (!isMap(limit)) return 'The limit is not readable.';
    if (!Number.isInteger(limit.amount) || limit.amount < 1 || limit.amount > MAX_LIMIT_AMOUNT) {
      return 'The limit is a whole number from 1 to ' + MAX_LIMIT_AMOUNT + '.';
    }
    if (!LIMIT_UNIT_IDS.includes(limit.unit)) return 'Pick the limit\'s unit.';
    return null;
  }

  function timesProblem(times, type, often) {
    if (times === 1 || times === null || times === undefined || times === '') return null;
    if (!Number.isInteger(times) || times < 2 || times > 12) return 'Times a day is a whole number from 1 to 12.';
    if (type !== 'build' || often !== 'daily') return 'Times a day goes only with a daily habit to build.';
    return null;
  }

  /**
   * Checks one idea row. [base] is the built-in idea for a built-in row
   * (only the fields that differ from it are checked: the app's own text
   * never blocks a save, even if a later file breaks a rule here), null for
   * an added one (every field is checked).
   *
   * Returns { problems: [{ level, field, say }], changed: [field] }.
   */
  function checkIdeaRow(row, base) {
    const problems = [];
    const add = (level, field, say) => problems.push({ level, field, say });
    const changed = [];
    const fieldsToCheck = base ? TEXT_FIELDS.filter((f) => !same(storedValue(row, f), builtInValue(base, f))) : TEXT_FIELDS;
    changed.push(...(base ? fieldsToCheck : []));
    const type = base ? base.type : row.type;
    if (!base && !TYPES.includes(row.type)) add('error', 'type', 'Pick Build or Quit.');
    if (base && row.type !== base.type) add('error', 'type', 'A built-in idea keeps its type. Hide it and add a new one instead.');
    for (const f of fieldsToCheck) {
      const lang = /Ar$/.test(f) ? 'ar' : 'en';
      switch (f) {
        case 'nameAr':
        case 'nameEn':
        case 'shortAr':
        case 'shortEn':
        case 'benefitAr':
        case 'benefitEn': {
          const c = checkWords(FIELD_LABEL[f], lang, row[f], LIMITS[f], { multiline: f.startsWith('benefit') });
          c.errors.forEach((s) => add('error', f, s));
          c.warnings.forEach((s) => add('warning', f, s));
          break;
        }
        case 'sourceAr':
        case 'sourceEn': {
          const c = checkWords(FIELD_LABEL[f], lang, row[f], LIMITS[f], { optional: true });
          c.errors.forEach((s) => add('error', f, s));
          c.warnings.forEach((s) => add('warning', f, s));
          break;
        }
        case 'waysAr':
        case 'waysEn': {
          const list = Array.isArray(row[f]) ? row[f] : [];
          if (!list.length) add('error', f, cap(FIELD_LABEL[f]) + ': add at least one way.');
          if (list.length > MAX_WAYS_READ) add('error', f, cap(FIELD_LABEL[f]) + ': ' + MAX_WAYS_READ + ' ways at most.');
          list.forEach((w, i) => {
            const c = checkWords('way ' + (i + 1) + ' in ' + (lang === 'ar' ? 'Arabic' : 'English'), lang, w, LIMITS.way);
            c.errors.forEach((s) => add('error', f, s));
            c.warnings.forEach((s) => add('warning', f, s));
          });
          break;
        }
        case 'category':
          if (!CATEGORY_IDS.includes(row.category)) add('error', f, 'Pick a category.');
          break;
        case 'often': {
          const p = oftenProblem(row.often);
          if (p) add('error', f, p);
          break;
        }
        case 'timesPerDay': {
          const p = timesProblem(row.timesPerDay, type, row.often);
          if (p) add('error', f, p);
          break;
        }
        case 'reminder': {
          const p = reminderProblem(row.reminder);
          if (p) add('error', f, p);
          break;
        }
        case 'limit': {
          if (row.limit && type !== 'quit') add('error', f, 'A limit goes only with a habit to quit.');
          else {
            const p = limitProblem(row.limit);
            if (p) add('error', f, p);
          }
          break;
        }
        default:
          break;
      }
    }
    // Across fields: both languages give the same number of ways, and a
    // source is given in both or neither. Checked whenever either side was
    // touched, so a built-in file's own mismatch never blocks a save.
    const touched = (a, b) => !base || fieldsToCheck.includes(a) || fieldsToCheck.includes(b);
    if (touched('waysAr', 'waysEn') && Array.isArray(row.waysAr) && Array.isArray(row.waysEn) &&
      row.waysAr.length !== row.waysEn.length) {
      add('error', 'waysEn', 'Arabic has ' + row.waysAr.length + ' ways and English ' + row.waysEn.length + '. Give the same ways in both.');
    } else if (touched('waysAr', 'waysEn') && Array.isArray(row.waysAr) && row.waysAr.length && row.waysAr.length !== 2) {
      add('warning', 'waysAr', 'The card is designed for 2 ways to start; this has ' + row.waysAr.length + '.');
    }
    if (touched('sourceAr', 'sourceEn') && (norm(row.sourceAr) === '') !== (norm(row.sourceEn) === '')) {
      add('warning', norm(row.sourceAr) ? 'sourceEn' : 'sourceAr', 'A source is given in one language only.');
    }
    if (typeof row.featured !== 'boolean') add('error', 'featured', 'Featured is on or off.');
    return { problems, changed };
  }

  /** One plan row checked; only fields that differ from the built-in plan. */
  function checkPlanRow(row, base) {
    const problems = [];
    const changed = [];
    for (const f of PLAN_TEXT_FIELDS) {
      if (norm(row[f]) === norm(base[f])) continue;
      changed.push(f);
      const lang = /Ar$/.test(f) ? 'ar' : 'en';
      const max = LIMITS['plan' + f.charAt(0).toUpperCase() + f.slice(1)];
      const c = checkWords(f.startsWith('name') ? 'name in ' + (lang === 'ar' ? 'Arabic' : 'English') : FIELD_LABEL[f], lang, row[f], max);
      c.errors.forEach((s) => problems.push({ level: 'error', field: f, say: s }));
      c.warnings.forEach((s) => problems.push({ level: 'warning', field: f, say: s }));
    }
    return { problems, changed };
  }

  function ideaLabel(row) {
    const name = norm(row && row.nameEn) || norm(row && row.nameAr);
    return 'Idea “' + (name || (row && row.id) || '?') + '”';
  }

  function planLabel(row, base) {
    return 'Plan “' + (norm(row && row.nameEn) || (base && base.nameEn) || (row && row.id)) + '”';
  }

  /** The stored IDEA for an added row (the data spec's shape, its id inside). */
  function addedIdea(row) {
    const idea = {
      id: row.id,
      type: row.type,
      category: row.category,
      nameAr: norm(row.nameAr),
      nameEn: norm(row.nameEn),
      shortAr: norm(row.shortAr),
      shortEn: norm(row.shortEn),
      benefitAr: norm(row.benefitAr),
      benefitEn: norm(row.benefitEn),
    };
    if (norm(row.sourceAr)) idea.sourceAr = norm(row.sourceAr);
    if (norm(row.sourceEn)) idea.sourceEn = norm(row.sourceEn);
    idea.waysAr = row.waysAr.map(norm);
    idea.waysEn = row.waysEn.map(norm);
    idea.often = row.often;
    if (row.timesPerDay > 1) idea.timesPerDay = row.timesPerDay;
    if (row.reminder) idea.reminder = row.reminder;
    if (row.limit) idea.limit = { amount: row.limit.amount, unit: row.limit.unit };
    idea.featured = row.featured;
    return idea;
  }

  /**
   * The page's draft, checked and turned into what wording/live stores.
   *
   * [builtIn] is { ideas, plans } (either may be null when its source could
   * not be read); [draft] is { ideas?: [row], plans?: [row] }, each part
   * present only when the page changed it. Nothing is stored that the
   * built-in lists already say:
   *   - a built-in idea keeps only the fields that differ (`text`, null for
   *     an optional field taken away), its switch (`hidden`) and its star
   *     when it differs (`featured`);
   *   - an added idea is stored whole (`added`), its own star inside;
   *   - the order is stored only when it differs from the order phones
   *     would show with none (built-ins in file order, then added ideas by
   *     id), and then whole, hidden ideas included, so a hidden idea put
   *     back returns to its place.
   * Plans the same way, with only order, hidden and their four words.
   *
   * Returns { errors, warnings, problems, edits: { ideas, plans } }. An
   * edits part is undefined when the draft did not include it, null when
   * it stores nothing (the built-in list as it is).
   */
  function checkDraft(builtIn, draft) {
    const problems = [];
    const d = isMap(draft) ? draft : {};
    const edits = { ideas: undefined, plans: undefined };
    const push = (p) => problems.push(p);

    if (d.ideas !== undefined && d.ideas !== null) {
      if (!builtIn.ideas) {
        push({ level: 'error', tab: 'ideas', id: null, field: null, text: 'The built-in ideas could not be read, so the ideas cannot be published.' });
      } else if (!Array.isArray(d.ideas)) {
        push({ level: 'error', tab: 'ideas', id: null, field: null, text: 'Nothing to save for the ideas.' });
      } else {
        edits.ideas = ideasFromRows(builtIn.ideas, d.ideas, push);
      }
    }
    if (d.plans !== undefined && d.plans !== null) {
      if (!builtIn.plans) {
        push({ level: 'error', tab: 'plans', id: null, field: null, text: 'The built-in plans could not be read, so the plans cannot be published.' });
      } else if (!Array.isArray(d.plans)) {
        push({ level: 'error', tab: 'plans', id: null, field: null, text: 'Nothing to save for the plans.' });
      } else {
        edits.plans = plansFromRows(builtIn.plans, d.plans, push);
      }
    }
    const errors = problems.filter((p) => p.level === 'error').map((p) => p.text);
    const warnings = problems.filter((p) => p.level === 'warning').map((p) => p.text);
    if (errors.length) {
      if (edits.ideas !== undefined) edits.ideas = null;
      if (edits.plans !== undefined) edits.plans = null;
    }
    return { errors, warnings, problems, edits, ok: errors.length === 0 };
  }

  function ideasFromRows(builtInIdeas, rows, push) {
    const byId = new Map(builtInIdeas.map((i) => [i.id, i]));
    const seen = new Set();
    const order = [];
    const hidden = [];
    const featured = {};
    const text = {};
    const added = {};
    let addedCount = 0;
    rows.forEach((row, i) => {
      const id = row && typeof row.id === 'string' ? row.id : '';
      const label = ideaLabel(row);
      const say = (level, field, s) => push({ level, tab: 'ideas', id, field, say: s, text: label + ': ' + lowerFirst(s) });
      if (seen.has(id)) {
        say('error', null, 'Is in the list twice.');
        return;
      }
      seen.add(id);
      const base = byId.get(id);
      if (!base) {
        if (!ADDED_ID_SHAPE.test(id)) {
          say('error', null, 'Has an id the app does not know (' + (id || 'none') + ').');
          return;
        }
        if (!row.added) say('error', null, 'Is marked built-in but is not in the built-in file.');
        if (row.shown === false) say('error', null, 'An added idea cannot be hidden. Delete it instead.');
        addedCount++;
      } else if (row.added) {
        say('error', null, 'Has the id of a built-in idea.');
        return;
      }
      const check = checkIdeaRow(row, base || null);
      check.problems.forEach((p) => say(p.level, p.field, p.say));
      order.push(id);
      if (base) {
        if (row.shown === false) hidden.push(id);
        if (typeof row.featured === 'boolean' && row.featured !== base.featured) featured[id] = row.featured;
        const fields = {};
        for (const f of check.changed) fields[f] = storedValue(row, f);
        if (Object.keys(fields).length) text[id] = fields;
      } else if (!check.problems.some((p) => p.level === 'error')) {
        added[id] = addedIdea(row);
      }
    });
    for (const idea of builtInIdeas) {
      if (!seen.has(idea.id)) {
        push({ level: 'error', tab: 'ideas', id: idea.id, field: null, text: 'Idea “' + idea.nameEn + '” from the app is missing from the list. Built-in ideas are hidden, never deleted.' });
      }
    }
    if (addedCount > MAX_ADDED) {
      push({ level: 'error', tab: 'ideas', id: null, field: null, text: 'Too many added ideas: ' + addedCount + ', the limit is ' + MAX_ADDED + '.' });
    }

    // Featured: the design aims for two per category on each side at most.
    const count = {};
    rows.forEach((row) => {
      if (!row || row.shown === false || row.featured !== true) return;
      const key = row.type + '|' + row.category;
      count[key] = (count[key] || 0) + 1;
    });
    for (const [key, n] of Object.entries(count)) {
      if (n <= 2) continue;
      const [type, category] = key.split('|');
      const c = CATEGORIES.find((x) => x.id === category);
      push({ level: 'warning', tab: 'ideas', id: null, field: null,
        text: (c ? c.en : category) + ', ' + (type === 'quit' ? 'Quit' : 'Build') + ': ' + n + ' featured ideas. The design aims for 2 at most.' });
    }
    if (rows.length && rows.every((row) => !row || row.shown === false)) {
      push({ level: 'warning', tab: 'ideas', id: null, field: null, text: 'Every idea is hidden, so the ideas list will be empty.' });
    }

    // With an error anywhere nothing is stored, so only a clean draft's
    // order is compared: built-ins in file order, then added ideas by id.
    const natural = builtInIdeas.map((i) => i.id).concat(Object.keys(added).sort());
    const doc = {};
    if (!same(order, natural)) doc.order = order;
    if (hidden.length) doc.hidden = hidden;
    if (Object.keys(featured).length) doc.featured = featured;
    if (Object.keys(text).length) doc.text = text;
    if (Object.keys(added).length) doc.added = added;
    return Object.keys(doc).length ? doc : null;
  }

  function plansFromRows(builtInPlans, rows, push) {
    const byId = new Map(builtInPlans.map((p) => [p.id, p]));
    const seen = new Set();
    const order = [];
    const hidden = [];
    const text = {};
    rows.forEach((row) => {
      const id = row && typeof row.id === 'string' ? row.id : '';
      const base = byId.get(id);
      const label = planLabel(row, base);
      const say = (level, field, s) => push({ level, tab: 'plans', id, field, say: s, text: label + ': ' + lowerFirst(s) });
      if (seen.has(id)) {
        say('error', null, 'Is in the list twice.');
        return;
      }
      seen.add(id);
      if (!base) {
        say('error', null, 'Is not a plan the app has (' + (id || 'none') + '). Plans are made in the app\'s code.');
        return;
      }
      order.push(id);
      if (row.shown === false) hidden.push(id);
      const check = checkPlanRow(row, base);
      check.problems.forEach((p) => say(p.level, p.field, p.say));
      const fields = {};
      for (const f of check.changed) fields[f] = norm(row[f]);
      if (Object.keys(fields).length) text[id] = fields;
    });
    for (const p of builtInPlans) {
      if (!seen.has(p.id)) push({ level: 'error', tab: 'plans', id: p.id, field: null, text: 'Plan “' + p.nameEn + '” is missing from the list. Plans are hidden, never deleted.' });
    }
    if (rows.length && rows.every((row) => !row || row.shown === false)) {
      push({ level: 'warning', tab: 'plans', id: null, field: null, text: 'Every plan is hidden, so Add Habit will show no plans.' });
    }
    const doc = {};
    if (!same(order, builtInPlans.map((p) => p.id))) doc.order = order;
    if (hidden.length) doc.hidden = hidden;
    if (Object.keys(text).length) doc.text = text;
    return Object.keys(doc).length ? doc : null;
  }

  /** A sentence carried on after "Idea X: ", its first word lower case
   *  unless it is a language's name. */
  function lowerFirst(s) {
    if (/^(Arabic|English)\b/.test(s)) return s;
    return s.charAt(0).toLowerCase() + s.slice(1);
  }

  /**
   * What the built-in file itself breaks of the data spec (sizes, copy
   * rules, an id's shape), as notes for the page. The app still shows these
   * ideas; the notes are for whoever writes the file next.
   */
  function fileNotes(ideas) {
    const out = [];
    for (const idea of ideas) {
      const label = 'Idea “' + idea.nameEn + '” (' + idea.id + ')';
      if (!BUILT_IN_ID_SHAPE.test(idea.id)) out.push(label + ': the id should be 2 to 40 of a-z, 0-9 and _.');
      const check = checkIdeaRow(rowFromIdea(idea, { featured: idea.featured }), null);
      check.problems.forEach((p) => out.push(label + ': ' + lowerFirst(p.say)));
    }
    return out;
  }

  // ---- Words for the page ------------------------------------------------------------

  function describeOften(value) {
    const o = parseOften(value);
    if (!o) return 'Schedule not set';
    if (o.kind === 'daily') return 'Every day';
    if (o.kind === 'weekly') return o.times === 1 ? 'Once a week' : o.times + ' times a week';
    return o.days.map((n) => WEEKDAYS[n - 1].en.slice(0, 3)).join(', ');
  }

  function describeReminder(value) {
    const r = readReminder(value);
    if (!r) return 'No reminder';
    if (r.startsWith('prayer:')) {
      const p = PRAYERS.find((x) => x.id === r.slice(7));
      return 'After ' + (p ? p.en : r.slice(7));
    }
    return 'At ' + r.slice(5);
  }

  function describeLimit(limit) {
    if (!limit) return 'Quit fully';
    const u = LIMIT_UNITS.find((x) => x.id === limit.unit);
    return 'At most ' + limit.amount + ' ' + (u ? u.en : limit.unit) + ' a day';
  }

  function categoryOf(id) {
    return CATEGORIES.find((c) => c.id === id) || { id, en: id, ar: id };
  }

  /**
   * What one publish changed, in words, for History: "Ideas: 2 edited, 1
   * added. Plans: order changed." [before] and [after] are
   * { ideas, plans } as stored.
   */
  function describeChange(before, after) {
    const b = isMap(before) ? before : {};
    const a = isMap(after) ? after : {};
    const parts = [];
    const ib = parseIdeasEdits(b.ideas) || { order: null, hidden: [], featured: {}, text: {}, added: {} };
    const ia = parseIdeasEdits(a.ideas) || { order: null, hidden: [], featured: {}, text: {}, added: {} };
    const ideaWords = [];
    const n = (count, one, many) => count + ' ' + (count === 1 ? one : many);
    const textKeys = new Set(Object.keys(ib.text).concat(Object.keys(ia.text)));
    const edited = [...textKeys].filter((k) => !same(own(ib.text, k), own(ia.text, k))).length +
      Object.keys(ia.added).filter((k) => own(ib.added, k) !== undefined && !same(ib.added[k], ia.added[k])).length;
    const addedNew = Object.keys(ia.added).filter((k) => own(ib.added, k) === undefined).length;
    const deleted = Object.keys(ib.added).filter((k) => own(ia.added, k) === undefined).length;
    const hiddenNew = ia.hidden.filter((k) => !ib.hidden.includes(k)).length;
    const shownAgain = ib.hidden.filter((k) => !ia.hidden.includes(k)).length;
    const starKeys = new Set(Object.keys(ib.featured).concat(Object.keys(ia.featured)));
    const stars = [...starKeys].filter((k) => own(ib.featured, k) !== own(ia.featured, k)).length;
    if (edited) ideaWords.push(edited + ' edited');
    if (addedNew) ideaWords.push(addedNew + ' added');
    if (deleted) ideaWords.push(deleted + ' deleted');
    if (hiddenNew) ideaWords.push(hiddenNew + ' hidden');
    if (shownAgain) ideaWords.push(shownAgain + ' shown again');
    if (stars) ideaWords.push(n(stars, 'star changed', 'stars changed'));
    if (!same(ib.order, ia.order)) ideaWords.push('order changed');
    if (ideaWords.length) parts.push('Ideas: ' + ideaWords.join(', ') + '.');

    const pb = parsePlansEdits(b.plans) || { order: null, hidden: [], text: {} };
    const pa = parsePlansEdits(a.plans) || { order: null, hidden: [], text: {} };
    const planWords = [];
    const planKeys = new Set(Object.keys(pb.text).concat(Object.keys(pa.text)));
    const planEdited = [...planKeys].filter((k) => !same(own(pb.text, k), own(pa.text, k))).length;
    const planHidden = pa.hidden.filter((k) => !pb.hidden.includes(k)).length;
    const planShown = pb.hidden.filter((k) => !pa.hidden.includes(k)).length;
    if (planEdited) planWords.push(planEdited + ' edited');
    if (planHidden) planWords.push(planHidden + ' hidden');
    if (planShown) planWords.push(planShown + ' shown again');
    if (!same(pb.order, pa.order)) planWords.push('order changed');
    if (planWords.length) parts.push('Plans: ' + planWords.join(', ') + '.');
    return parts.join(' ') || 'No change phones would see.';
  }

  // ---- Comparing and fingerprints -------------------------------------------------------

  /** [value] as JSON with every map's keys sorted. */
  function canonical(value) {
    if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
    if (isMap(value)) {
      return '{' + Object.keys(value).sort().map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
    }
    return JSON.stringify(value === undefined ? null : value);
  }

  function same(a, b) {
    return canonical(a === undefined ? null : a) === canonical(b === undefined ? null : b);
  }

  /**
   * A short fingerprint of the built-in lists a page was drawn from. A save
   * from a page whose built-ins have changed since is refused: it would
   * store the old words as edits.
   */
  function fingerprint(value) {
    return R.fnv1a(new TextEncoder().encode(canonical(value === undefined ? null : value)));
  }

  return {
    TYPES,
    CATEGORIES,
    CATEGORY_IDS,
    PRAYERS,
    LIMIT_UNITS,
    WEEKDAYS,
    TEXT_FIELDS,
    WORD_FIELDS,
    PLAN_TEXT_FIELDS,
    FIELD_LABEL,
    READ_MAX,
    LIMITS,
    MAX_ADDED,
    MAX_LIMIT_AMOUNT,
    ADDED_PREFIX,
    ADDED_ID_SHAPE,
    BUILT_IN_ID_SHAPE,
    isMap,
    own,
    dartTrim,
    dartInt,
    parseOften,
    oftenString,
    readReminder,
    readLimit,
    ideaFromJson,
    ideaIssues,
    toJson,
    withText,
    parseBuiltInIdeas,
    parseIdeasEdits,
    parsePlansEdits,
    resolveIdeas,
    resolvePlans,
    rowFromIdea,
    blankRow,
    newIdeaId,
    draftFrom,
    storedValue,
    builtInValue,
    checkWords,
    checkIdeaRow,
    checkPlanRow,
    checkDraft,
    fileNotes,
    addedIdea,
    describeOften,
    describeReminder,
    describeLimit,
    categoryOf,
    describeChange,
    canonical,
    same,
    fingerprint,
  };
});
