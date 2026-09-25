'use strict';

/**
 * The app's preset habits, so this tool can see them.
 *
 * A preset is not a document. custom_habits holds only what a person built
 * themselves. A preset switched on from the Add Habit list or a Plan is an
 * id in the profile's activeCatalogIds, its first day in
 * activeCatalogActivatedAt, and whatever the person changed about it in
 * catalog_habit_overrides_v1, all laid over the const template in
 * lib/features/habits/catalog/islamic_habit_catalog.dart. The app joins the
 * two in habitListProvider (today's board) and allHabitsEverProvider
 * (history), and every Grid square, completion and room link keys off the
 * catalog id.
 *
 * This tool read custom_habits alone, so an account made of presets had no
 * habits at all. adlshwaikh on 2026-09-25 had done 9 of 9 on the 23rd and on
 * the 24th: the calendar drew both days empty, the feed said "nothing
 * marked", the Day tab read 0/0, and every ledger row said "(habit no longer
 * in this account · prayer_f)". 8 of 124 accounts had presets that day, and
 * 3 had nothing else.
 *
 * The templates are read out of the Dart file itself, again whenever the
 * file changes, so a preset added to the app shows here without anyone
 * copying it across (the same reason lib/wording.js hashes the app's own
 * sources rather than trusting a copy). The parse is narrow on purpose: one
 * `key: value,` per line, which is how every template is written, and
 * test/habit_catalog.test.js fails the moment it stops finding them all.
 */

const fs = require('fs');
const path = require('path');
const DayRules = require('./day_rules');

const CATALOG_DART = path.join(__dirname, '..', '..', '..',
  'lib', 'features', 'habits', 'catalog', 'islamic_habit_catalog.dart');

/**
 * The profile fields a preset is made of. Named once because scanActivity
 * reads profiles through select(), and a field left out of that list arrives
 * undefined without a word (see the note on that query).
 */
const CATALOG_PROFILE_FIELDS = [
  'activeCatalogIds',
  'activeCatalogActivatedAt',
  'activeCatalogArchivedAt',
  'activeCatalogStintHistory',
  // LocalStoreService.catalogOverridesKey, which CatalogOverridesNotifier
  // also uses as the field name on users/{uid}.
  'catalog_habit_overrides_v1',
];

const WEEKDAY_NUM = {
  monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7,
};

/**
 * The templates in IslamicHabitCatalog.templates, in the file's order, each
 * with the fields toFirestore() would store and the constructor's defaults
 * for anything a template leaves out.
 */
function parseCatalogDart(source) {
  const start = source.indexOf('static const List<IslamicHabitTemplate> templates = [');
  if (start < 0) return [];
  const end = source.indexOf('\n  ];', start);
  if (end < 0) return [];

  const out = [];
  const chunks = source.slice(start, end).split(/\bIslamicHabitTemplate\(/).slice(1);
  for (const raw of chunks) {
    // Whole-line comments only. Several templates explain a cue or a name in
    // prose right above the field, and a quoted word in that prose must never
    // be read as the value.
    const chunk = raw.replace(/^\s*\/\/.*$/gm, '');
    // Adjacent literals join, the way Dart joins them, which is how the two
    // descriptions that run onto a second line are written.
    const str = (key) => {
      const m = chunk.match(new RegExp(`^\\s*${key}:\\s*((?:'(?:[^'\\\\]|\\\\.)*'\\s*)+)`, 'm'));
      if (!m) return null;
      const parts = m[1].match(/'(?:[^'\\]|\\.)*'/g) || [];
      return parts.map((p) => p.slice(1, -1).replace(/\\(.)/g, '$1')).join('');
    };
    const enumValue = (key, type) => {
      const m = chunk.match(new RegExp(`^\\s*${key}:\\s*${type}\\.(\\w+)`, 'm'));
      return m ? m[1] : null;
    };
    const int = (key) => {
      const m = chunk.match(new RegExp(`^\\s*${key}:\\s*(-?\\d+)`, 'm'));
      return m ? Number(m[1]) : null;
    };
    const bool = (key) => {
      const m = chunk.match(new RegExp(`^\\s*${key}:\\s*(true|false)`, 'm'));
      return m ? m[1] === 'true' : null;
    };
    const weekdays = () => {
      const m = chunk.match(/^\s*scheduledWeekdays:\s*\[([^\]]*)\]/m);
      if (!m) return [];
      return m[1].split(',').map((s) => s.trim()).filter(Boolean)
        .map((s) => {
          const named = s.match(/^DateTime\.(\w+)$/);
          return named ? WEEKDAY_NUM[named[1]] : Number(s);
        })
        .filter((n) => Number.isInteger(n) && n >= 1 && n <= 7);
    };

    const id = str('id');
    const name = str('name');
    if (!id || !name) continue;
    out.push({
      id,
      name,
      nameAr: str('nameAr'),
      description: str('description') || '',
      descriptionAr: str('descriptionAr'),
      cueAfter: str('cueAfter'),
      category: enumValue('category', 'HabitCategory') || 'custom',
      frequencyType: enumValue('frequencyType', 'HabitFrequencyType') || 'daily',
      frequencyTarget: int('frequencyTarget') || 1,
      scheduledWeekdays: weekdays(),
      goalType: enumValue('goalType', 'GoalType') || 'build',
      reductionType: enumValue('reductionType', 'ReductionType') || 'avoid',
      limitAmount: int('limitAmount'),
      limitUnit: enumValue('limitUnit', 'LimitUnit'),
      hasTimer: bool('hasTimer') === true,
      timerDurationSeconds: int('timerDurationSeconds'),
      xpReward: int('xpReward') || 0,
      goldReward: int('goldReward') || 0,
      reminderOffsetMinutes: int('reminderOffsetMinutes') || 0,
      suggestedStepGoal: int('suggestedStepGoal'),
    });
  }
  return out;
}

let _catalog = null; // { mtimeMs, templates, byId }

/**
 * The parsed templates, re-read only when the Dart file changes. A file that
 * cannot be read gives an empty catalog rather than a thrown report: presets
 * then show the way they did before this module, as ids this account has no
 * name for, which is wrong but never a blank page.
 */
function catalog() {
  let mtimeMs = null;
  try {
    mtimeMs = fs.statSync(CATALOG_DART).mtimeMs;
  } catch (_) {
    mtimeMs = null;
  }
  if (_catalog && _catalog.mtimeMs === mtimeMs) return _catalog;
  let templates = [];
  if (mtimeMs !== null) {
    try {
      templates = parseCatalogDart(fs.readFileSync(CATALOG_DART, 'utf8'));
    } catch (_) {
      templates = [];
    }
  }
  if (templates.length === 0) {
    console.warn(`habit_catalog: no preset habits read from ${CATALOG_DART}; presets will show unnamed.`);
  }
  _catalog = { mtimeMs, templates, byId: new Map(templates.map((t) => [t.id, t])) };
  return _catalog;
}

/** One template by catalog id, or null. */
function catalogTemplate(id) {
  return catalog().byId.get(id) || null;
}

/**
 * The name the person's own phone shows: localName(isAr) in the app, the
 * Arabic name unless the account is set to English. A rename in the
 * override wins in both languages, exactly as CatalogHabitOverride.applyTo
 * does, because the person typed one name and means it.
 */
function presetName(t, override, locale) {
  if (override && typeof override.name === 'string' && override.name.trim()) return override.name;
  const isAr = locale !== 'en';
  return isAr && t.nameAr && t.nameAr.trim() ? t.nameAr : t.name;
}

function plainMap(v) {
  return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
}

/**
 * Every preset this account has ever had, as document-shaped objects
 * (`id`, `data()`), so each surface that walks custom_habits can walk these
 * beside them without learning a second shape.
 *
 * Ported from allHabitsEverProvider, with one difference that keeps a day
 * from being counted twice. The app emits one template per STINT (a preset
 * switched off and on again), all sharing the catalog id, and its day score
 * then folds them back into one id. This tool has no such fold, so it builds
 * ONE entry per preset: createdAt is the earliest start, archivedAt the
 * latest end (none while it is on), and `stints` lists the windows whenever
 * there is more than one, so a day in the gap between two of them is not
 * owed (DayRules.withinStints).
 *
 * A preset whose windows all fell away (switched on and deleted the same day,
 * or switched off before archive dates were kept) is left out, as the app
 * leaves it out: there is no window to describe.
 */
function catalogHabitDocs(profile) {
  const p = profile || {};
  const activeIds = new Set(
    (Array.isArray(p.activeCatalogIds) ? p.activeCatalogIds : []).filter((x) => typeof x === 'string'));
  const activatedAt = plainMap(p.activeCatalogActivatedAt);
  const archivedAt = plainMap(p.activeCatalogArchivedAt);
  const stintHistory = plainMap(p.activeCatalogStintHistory);
  const overrides = plainMap(p.catalog_habit_overrides_v1);
  const everIds = new Set([
    ...activeIds,
    ...Object.keys(activatedAt),
    ...Object.keys(archivedAt),
    ...Object.keys(stintHistory),
  ]);
  if (everIds.size === 0) return [];

  const docs = [];
  for (const t of catalog().templates) {
    if (!everIds.has(t.id)) continue;

    const windows = [];
    // The current-or-most-recent window, only when it has a real open end
    // (on right now) or a real archive date closing it. Without either it
    // would read as "existed every day, forever".
    if (activeIds.has(t.id) || archivedAt[t.id] != null) {
      windows.push({ start: activatedAt[t.id] || null, end: archivedAt[t.id] || null });
    }
    // Every earlier, closed stint. _parseStintHistory keeps an entry only
    // when it has an end; a missing start is meaningful (switched on before
    // activation dates were kept) and stays null.
    const stints = Array.isArray(stintHistory[t.id]) ? stintHistory[t.id] : [];
    for (const s of stints) {
      if (!s || typeof s !== 'object' || !DayRules.habitDateKey(s.end)) continue;
      windows.push({ start: s.start || null, end: s.end });
    }
    if (windows.length === 0) continue;

    const byKey = (a, b) => (DayRules.habitDateKey(a) < DayRules.habitDateKey(b) ? -1 : 1);
    const starts = windows.map((w) => w.start);
    const ends = windows.map((w) => w.end);
    const createdAt = starts.some((s) => !DayRules.habitDateKey(s))
      ? null : starts.slice().sort(byKey)[0];
    const lastEnd = ends.some((e) => !DayRules.habitDateKey(e))
      ? null : ends.slice().sort(byKey)[ends.length - 1];

    const o = plainMap(overrides[t.id]);
    const weekdays = Array.isArray(o.scheduledWeekdays)
      ? o.scheduledWeekdays.map(Number).filter((n) => Number.isInteger(n) && n >= 1 && n <= 7)
      : t.scheduledWeekdays;
    const isAr = p.locale !== 'en';
    const data = {
      name: presetName(t, o, p.locale),
      description: isAr && t.descriptionAr ? t.descriptionAr : t.description,
      cueAfter: typeof o.cueAfter === 'string' ? o.cueAfter : t.cueAfter,
      category: t.category,
      frequencyType: typeof o.frequencyType === 'string' ? o.frequencyType : t.frequencyType,
      frequencyTarget: Number(o.frequencyTarget) || t.frequencyTarget,
      scheduledWeekdays: weekdays,
      goalType: t.goalType,
      reductionType: t.reductionType,
      limitAmount: t.limitAmount,
      limitUnit: t.limitUnit,
      hasTimer: t.hasTimer,
      timerDurationSeconds: t.timerDurationSeconds,
      xpReward: t.xpReward,
      goldReward: t.goldReward,
      reminderOffsetMinutes: Number.isInteger(o.reminderOffsetMinutes)
        ? o.reminderOffsetMinutes : t.reminderOffsetMinutes,
      createdAt,
      archivedAt: lastEnd,
      isPreset: true,
    };
    if (Array.isArray(o.scheduleHistory)) data.scheduleHistory = o.scheduleHistory;
    if (typeof o.stepGoal === 'number') data.stepGoal = o.stepGoal;
    if (o.alarm === true) data.alarm = true;
    if (windows.length > 1) data.stints = windows;

    // A fresh copy per call, as a Firestore snapshot's data() is, so a caller
    // that adjusts what it was handed cannot change the next caller's copy.
    docs.push({ id: t.id, data: () => ({ ...data }), isPreset: true, createTime: null, updateTime: null });
  }
  return docs;
}

/**
 * The account's whole habit list, the way the app assembles it: presets
 * first, in catalog order, then the person's own. Every surface that asks
 * "which habits does this account have" goes through here.
 */
function accountHabitDocs(profile, customHabitDocs) {
  return [...catalogHabitDocs(profile), ...(customHabitDocs || [])];
}

module.exports = {
  CATALOG_DART,
  CATALOG_PROFILE_FIELDS,
  parseCatalogDart,
  catalog,
  catalogTemplate,
  catalogHabitDocs,
  accountHabitDocs,
};
