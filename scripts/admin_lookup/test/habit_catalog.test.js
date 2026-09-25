'use strict';

/**
 * Presets (lib/habit_catalog.js): the app's own habits, which have no
 * document in custom_habits and which this tool could not see at all.
 *
 * Measured on adlshwaikh, 2026-09-25: nine presets, no custom habit. The
 * calendar drew 9 of 9 days empty, the Day tab read 0/0, the feed said
 * "nothing marked" over five green squares, and every row was
 * "(habit no longer in this account · prayer_f)". The profile below is that
 * account's own shape.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');

const {
  CATALOG_DART,
  CATALOG_PROFILE_FIELDS,
  parseCatalogDart,
  catalog,
  catalogHabitDocs,
  accountHabitDocs,
} = require('../lib/habit_catalog');
const DayRules = require('../lib/day_rules');
const {
  buildHabitContext,
  habitLabelParts,
  habitScheduledOnParts,
  whyNotScheduled,
  dayKeyParts,
} = require('../lib/render');

const ACTIVATED_7TH = '2026-09-07T00:00:00.000';
const ACTIVATED_23RD = '2026-09-23T00:00:00.000';

function adlshwaikh(extra) {
  return {
    locale: 'ar',
    tzOffsetMinutes: 240,
    activeCatalogIds: ['wake_early', 'morning_athkar', 'quran_daily_page', 'no_phone_morning',
      'prayer_fajr', 'prayer_dhuhr', 'prayer_asr', 'prayer_maghrib', 'prayer_isha'],
    activeCatalogActivatedAt: {
      quran_daily_page: ACTIVATED_7TH,
      wake_early: ACTIVATED_7TH,
      morning_athkar: ACTIVATED_7TH,
      no_phone_morning: ACTIVATED_7TH,
      prayer_fajr: ACTIVATED_23RD,
      prayer_dhuhr: ACTIVATED_23RD,
      prayer_asr: ACTIVATED_23RD,
      prayer_maghrib: ACTIVATED_23RD,
      prayer_isha: ACTIVATED_23RD,
    },
    activeCatalogArchivedAt: {},
    activeCatalogStintHistory: {},
    ...extra,
  };
}

const byId = (docs) => Object.fromEntries(docs.map((d) => [d.id, d.data()]));

// ── Reading the Dart file ─────────────────────────────────────────────────

test('every template in the Dart catalog is read, none dropped', () => {
  const source = fs.readFileSync(CATALOG_DART, 'utf8');
  const start = source.indexOf('static const List<IslamicHabitTemplate> templates = [');
  const block = source.slice(start, source.indexOf('\n  ];', start));
  // Counted independently of the parser: one constructor call per template.
  const written = (block.match(/\bIslamicHabitTemplate\(/g) || []).length;
  const parsed = parseCatalogDart(source);
  assert.ok(written >= 28, `the catalog had 28 presets on 2026-09-25, found ${written}`);
  assert.strictEqual(parsed.length, written, 'a template the parser skipped would show unnamed again');
  assert.strictEqual(new Set(parsed.map((t) => t.id)).size, parsed.length, 'ids are unique');
  for (const t of parsed) {
    assert.match(t.id, /^[a-z0-9_]+$/, t.id);
    assert.ok(t.name && t.nameAr, `${t.id} has both names`);
    assert.ok(['daily', 'weekly'].includes(t.frequencyType), `${t.id} ${t.frequencyType}`);
    assert.ok(t.frequencyTarget >= 1, t.id);
    assert.ok(t.xpReward > 0 && t.goldReward > 0, `${t.id} pays`);
  }
});

test('the fields that decide a day are read the way the Dart writes them', () => {
  const t = (id) => catalog().byId.get(id);
  assert.deepStrictEqual(
    { name: t('prayer_fajr').name, nameAr: t('prayer_fajr').nameAr, category: t('prayer_fajr').category, cue: t('prayer_fajr').cueAfter },
    { name: 'Fajr Prayer', nameAr: 'صلاة الفجر', category: 'faith', cue: 'fajr' });
  assert.deepStrictEqual(t('sunnah_fasting').scheduledWeekdays, [1, 4], 'DateTime.monday, DateTime.thursday');
  assert.deepStrictEqual(t('marriage_checkin').scheduledWeekdays, [5], 'DateTime.friday');
  assert.deepStrictEqual([t('tahajjud').frequencyType, t('tahajjud').frequencyTarget], ['weekly', 3]);
  assert.strictEqual(t('lower_gaze').goalType, 'quit');
  assert.strictEqual(t('prayer_fajr').goalType, 'build', 'the constructor default');
  assert.deepStrictEqual([t('quran_daily_page').xpReward, t('quran_daily_page').goldReward], [30, 10]);
  assert.deepStrictEqual([t('quran_daily_page').hasTimer, t('quran_daily_page').timerDurationSeconds], [true, 600]);
  assert.strictEqual(t('daily_walk').suggestedStepGoal, 10000);
});

test('a quoted word in a comment is never read as the value', () => {
  const source = `
  static const List<IslamicHabitTemplate> templates = [
    IslamicHabitTemplate(
      id: 'one',
      // name: 'Not this one',
      name: 'Real name',
      description:
          'Two literals ' 'joined, it\\'s one',
      category: HabitCategory.quran, // trailing words
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 2,
      scheduledWeekdays: [DateTime.monday, 7],
      hasTimer: false,
      xpReward: 5,
      goldReward: 1,
    ),
  ];
`;
  const [t] = parseCatalogDart(source);
  assert.strictEqual(t.name, 'Real name');
  assert.strictEqual(t.description, "Two literals joined, it's one");
  assert.strictEqual(t.category, 'quran');
  assert.deepStrictEqual(t.scheduledWeekdays, [1, 7]);
  assert.strictEqual(t.nameAr, null);
});

test('a file that is not the catalog gives no presets rather than a throw', () => {
  assert.deepStrictEqual(parseCatalogDart('class Nothing {}'), []);
});

test('every profile field a preset is made of is named for the scan select', () => {
  // scanActivity reads profiles through select(); a field missing from this
  // list arrives undefined there and every preset silently disappears again.
  for (const f of ['activeCatalogIds', 'activeCatalogActivatedAt', 'activeCatalogArchivedAt',
    'activeCatalogStintHistory', 'catalog_habit_overrides_v1']) {
    assert.ok(CATALOG_PROFILE_FIELDS.includes(f), f);
  }
});

// ── One account's presets ─────────────────────────────────────────────────

test('a preset-only account has its nine habits, named as its phone names them', () => {
  const docs = catalogHabitDocs(adlshwaikh());
  assert.strictEqual(docs.length, 9);
  const h = byId(docs);
  assert.strictEqual(h.prayer_fajr.name, 'صلاة الفجر');
  assert.strictEqual(h.wake_early.name, 'استيقظ قبل الساعة 6 صباحًا');
  assert.strictEqual(h.prayer_fajr.createdAt, ACTIVATED_23RD, 'switched on the 23rd');
  assert.strictEqual(h.quran_daily_page.createdAt, ACTIVATED_7TH);
  assert.strictEqual(h.prayer_fajr.archivedAt, null);
  assert.ok(docs.every((d) => d.isPreset && d.data().isPreset), 'every preset says so');
  // The Dart file's order, which is allHabitsEverProvider's order.
  const order = catalog().templates.map((t) => t.id).filter((id) => h[id]);
  assert.deepStrictEqual(docs.map((d) => d.id), order);
});

test('an English account gets the English names', () => {
  const h = byId(catalogHabitDocs(adlshwaikh({ locale: 'en' })));
  assert.strictEqual(h.prayer_fajr.name, 'Fajr Prayer');
});

test('their own changes to a preset are laid over it, a rename in both languages', () => {
  const h = byId(catalogHabitDocs(adlshwaikh({
    locale: 'en',
    catalog_habit_overrides_v1: {
      prayer_fajr: { name: 'الفجر في المسجد', reminderOffsetMinutes: 120, alarm: true },
      quran_daily_page: {
        frequencyType: 'weekly',
        frequencyTarget: 1,
        scheduledWeekdays: [5, 9, 'x'],
        scheduleHistory: [{ until: '2026-09-20', frequencyType: 'daily', frequencyTarget: 1 }],
      },
    },
  })));
  assert.strictEqual(h.prayer_fajr.name, 'الفجر في المسجد');
  assert.strictEqual(h.prayer_fajr.reminderOffsetMinutes, 120);
  assert.strictEqual(h.prayer_fajr.alarm, true);
  assert.deepStrictEqual(
    [h.quran_daily_page.frequencyType, h.quran_daily_page.frequencyTarget, h.quran_daily_page.scheduledWeekdays],
    ['weekly', 1, [5]], 'weekdays out of range are dropped, as CatalogHabitOverride.fromMap drops them');
  // The schedule it had before the change still judges the days before it,
  // read the way scoreDay reads it (habitAsOf first).
  const dueOn = (key) => DayRules.habitScheduledOn(DayRules.habitAsOf(h.quran_daily_page, key), key);
  assert.strictEqual(dueOn('2026-09-16'), true, 'a Wednesday, while it was daily');
  assert.strictEqual(dueOn('2026-09-23'), false, 'a Wednesday, Fridays only now');
  assert.strictEqual(h.wake_early.frequencyType, 'daily', 'untouched presets keep the catalog');
});

test('a preset they switched off keeps its days up to the day it went', () => {
  const docs = catalogHabitDocs(adlshwaikh({
    activeCatalogIds: ['prayer_fajr'],
    activeCatalogActivatedAt: { prayer_fajr: ACTIVATED_7TH, prayer_isha: ACTIVATED_7TH },
    activeCatalogArchivedAt: { prayer_isha: '2026-09-20T00:00:00.000' },
  }));
  const h = byId(docs);
  assert.deepStrictEqual(Object.keys(h).sort(), ['prayer_fajr', 'prayer_isha']);
  assert.strictEqual(DayRules.habitScheduledOn(h.prayer_isha, '2026-09-20'), true, 'the archive day itself counts');
  assert.strictEqual(DayRules.habitScheduledOn(h.prayer_isha, '2026-09-21'), false);
});

test('an id the app would drop is dropped here too', () => {
  const docs = catalogHabitDocs(adlshwaikh({
    // Not in the catalog any more, and a preset with no window left at all
    // (dated, but neither on nor archived nor in a stint).
    activeCatalogIds: ['retired_template', 'prayer_fajr'],
    activeCatalogActivatedAt: { prayer_fajr: ACTIVATED_7TH, prayer_isha: ACTIVATED_7TH },
  }));
  assert.deepStrictEqual(docs.map((d) => d.id), ['prayer_fajr']);
});

test('a preset switched off and on again owes nothing in the gap between', () => {
  const profile = adlshwaikh({
    activeCatalogIds: ['prayer_fajr'],
    activeCatalogActivatedAt: { prayer_fajr: '2026-09-20T00:00:00.000' },
    activeCatalogStintHistory: {
      prayer_fajr: [{ start: '2026-09-01T00:00:00.000', end: '2026-09-10T00:00:00.000' }],
    },
  });
  const h = byId(catalogHabitDocs(profile)).prayer_fajr;
  assert.strictEqual(h.createdAt, '2026-09-01T00:00:00.000', 'born at the first stint');
  assert.strictEqual(h.archivedAt, null, 'on right now');
  assert.strictEqual(h.stints.length, 2);
  const on = (key) => DayRules.habitScheduledOn(h, key);
  assert.deepStrictEqual(
    ['2026-08-31', '2026-09-01', '2026-09-10', '2026-09-11', '2026-09-19', '2026-09-20', '2026-09-25'].map(on),
    [false, true, true, false, false, true, true]);
  // The report's own schedule test and its reason agree with the rule.
  assert.strictEqual(habitScheduledOnParts(h, dayKeyParts('2026-09-15')), false);
  assert.strictEqual(whyNotScheduled(h, dayKeyParts('2026-09-15')), 'switched off that day');
  // Never an empty square the habit "did not ask for" either: it did not exist.
  assert.strictEqual(DayRules.isCoveredDay({
    habitData: h, dayKey: '2026-09-15', todayKey: '2026-09-25', square: 'none', demand: null,
  }), false);
});

test('a stint written before activation dates were kept has no start, and stays', () => {
  const h = byId(catalogHabitDocs(adlshwaikh({
    activeCatalogIds: [],
    activeCatalogActivatedAt: {},
    activeCatalogStintHistory: { prayer_fajr: [{ end: '2026-09-10T00:00:00.000' }, { start: 'x' }] },
  }))).prayer_fajr;
  assert.strictEqual(h.createdAt, null, 'no birth date known: always existed');
  assert.strictEqual(DayRules.habitScheduledOn(h, '2026-01-01'), true);
  assert.strictEqual(DayRules.habitScheduledOn(h, '2026-09-11'), false, 'the stint with no end is dropped');
});

test('custom habits come after the presets, untouched', () => {
  const custom = { id: 'abc123', data: () => ({ name: 'مشي', category: 'fitness' }) };
  const docs = accountHabitDocs(adlshwaikh(), [custom]);
  assert.strictEqual(docs.length, 10);
  assert.strictEqual(docs[9], custom);
  assert.deepStrictEqual(accountHabitDocs(null, [custom]), [custom], 'no profile, no presets');
  assert.deepStrictEqual(accountHabitDocs({}, undefined), []);
});

// ── What the surfaces now say ─────────────────────────────────────────────

test('their 2026-09-25 scores 5 of 9 and still open, as their phone had it', () => {
  const docs = catalogHabitDocs(adlshwaikh());
  const green = { squareStates: {}, habitCompletions: {} };
  for (const id of ['prayer_fajr', 'prayer_dhuhr', 'wake_early', 'no_phone_morning', 'morning_athkar']) {
    green.squareStates[id] = 'complete';
    green.habitCompletions[id] = 1;
  }
  const score = DayRules.scoreDay({
    habits: docs.map((d) => ({ id: d.id, data: d.data() })),
    dayData: green,
    dayKey: '2026-09-25',
    // 13:10 on their clock (+4), when this was measured.
    nowLocalMs: DayRules.localNowMs(Date.UTC(2026, 8, 25, 9, 10), 240),
  });
  assert.deepStrictEqual([score.credit, score.owed, score.isOpen], [5, 9, true]);

  // And the 22nd, before the prayers were switched on: 3 of the 4 they had.
  const day22 = {
    squareStates: { quran_daily_page: 'complete', morning_athkar: 'complete', wake_early: 'complete' },
  };
  const s22 = DayRules.scoreDay({
    habits: docs.map((d) => ({ id: d.id, data: d.data() })),
    dayData: day22,
    dayKey: '2026-09-22',
    nowLocalMs: DayRules.localNowMs(Date.UTC(2026, 8, 25, 9, 10), 240),
  });
  assert.deepStrictEqual([s22.credit, s22.owed], [3, 4]);
});

test('a preset row is named, and a preset the account lost track of still is', () => {
  const ctx = buildHabitContext(catalogHabitDocs(adlshwaikh()));
  assert.deepStrictEqual(habitLabelParts('prayer_fajr', ctx), { emoji: '📖', name: 'صلاة الفجر' });
  assert.deepStrictEqual(habitLabelParts('evening_athkar', ctx),
    { emoji: '📖', name: 'أذكار المساء (preset, no longer on this account)' });
  assert.strictEqual(habitLabelParts('Xk2ab91LmQ0aZZZZ', ctx).name,
    '(habit no longer in this account · Xk2ab91L)', 'a deleted habit of their own reads as before');
});

test('a preset not yet switched on says so, in its own words', () => {
  const h = byId(catalogHabitDocs(adlshwaikh())).prayer_fajr;
  const why = whyNotScheduled(h, dayKeyParts('2026-09-22'));
  assert.match(why, /^switched on /);
  assert.match(why, /after this day$/);
});
