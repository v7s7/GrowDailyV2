'use strict';

/**
 * The launch splash page (lib/splash_admin.js, wording/splash_rules.js,
 * splash/app.js): which scene Doum plays on the opening curtain, stored in
 * wording/live.splash.
 *
 * The cases in fixtures/splash_cases.json are also run by the app
 * (test/features/launch/launch_settings_test.dart), so what the page shows
 * before Save is what phones do after it.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SplashRules = require('../wording/splash_rules');
const splashAdmin = require('../lib/splash_admin');
const wording = require('../lib/wording');
const { renderSplashPage } = require('../lib/splash_page');
const { fakeDb, FieldValue } = require('./support/fake_firestore');

const builtIn = splashAdmin.builtInSplash();
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'splash_cases.json'), 'utf8'));

// Built, never typed: this file keeps the rule it tests.
const EM_DASH = String.fromCharCode(0x2014);

function builtInDraft() {
  return SplashRules.draftFrom(builtIn, SplashRules.resolve(builtIn, null));
}

function liveDb(data) {
  const db = fakeDb();
  if (data) db.docs.set(wording.LIVE_DOC, data);
  return db;
}

// ---- The built-in values, read out of the app ------------------------------

test('every built-in setting is read out of launch_settings.dart', () => {
  assert.deepStrictEqual(builtIn.numbers, {
    minShowMs: 4000,
    maxShowMs: 9000,
    replayAfterMinutes: 30,
    awayDays: 3,
    firstOpenDays: 3,
    updateDays: 7,
    walkerFromHour: 16,
    walkerToHour: 18,
    newFirst: 1,
    noRepeat: 1,
  });
  for (const key of SplashRules.NUMBER_KEYS) {
    const [min, max] = builtIn.ranges[key];
    assert.ok(min <= builtIn.numbers[key] && builtIn.numbers[key] <= max, key);
  }
  assert.strictEqual(builtIn.order.length, 14);
  assert.strictEqual(builtIn.order[0], 'firstOpen');
  assert.ok(!builtIn.order.includes('dayRing') && !builtIn.order.includes('turnaround'));
  assert.deepStrictEqual(builtIn.hours.nightAsleep, [22, 4]);
  assert.deepStrictEqual(builtIn.hours.update, [4, 22]);
  assert.strictEqual(builtIn.hours.walk, undefined, 'the walk has no hours of its own');
  assert.deepStrictEqual(builtIn.months.winterWait, [3, 4, 5, 6, 7, 8, 9, 10, 11]);
  assert.deepStrictEqual(builtIn.pool, { dayRing: 2, turnaround: 2, walk: 4, stepsGoal: 4, firstOpen: 2, winterWait: 2, update: 0 });
  assert.deepStrictEqual(builtIn.onceADay, { nightAsleep: 0, ramadanLantern: 0, eid: 0, summerNoon: 1, eveningChecklist: 1, walk: 1 });
  assert.deepStrictEqual(builtIn.chance, { morningCoffee: 70, summerNoon: 60, eveningChecklist: 60, winterWait: 50 });
  assert.deepStrictEqual(builtIn.order.slice(-3), ['eveningChecklist', 'walk', 'winterWait']);
  assert.strictEqual(builtIn.poolMax, 10);
  assert.strictEqual(builtIn.lineMax, 60);
  assert.strictEqual(builtIn.slowLine, 'Slow or fast we Grow Daily');
});

test('a Dart file that lost a value is refused, never guessed', () => {
  const source = fs.readFileSync(splashAdmin.SPLASH_SETTINGS_DART, 'utf8');
  const refused = (broken, pattern) => {
    assert.notStrictEqual(broken, source);
    assert.throws(() => splashAdmin.parseSplashDart(broken), (e) =>
      e instanceof splashAdmin.SplashInputError && pattern.test(e.message));
  };
  refused(source.replace(/^const int kSplashAwayDays = \d+;$/m, ''), /awayDays/);
  refused(source.replace(/^const int kSplashWalkerToHour = \d+;$/m, ''), /walkerToHour/);
  refused(source.replace(/^\s*'minShowMs': \(\d+, \d+\),$/m, ''), /range of minShowMs/);
  refused(source.replace('kSplashSceneOrder = [', 'kSplashSceneOrdr = ['), /kSplashSceneOrder/);
  refused(source.replace('kSplashSceneHours = {', 'kSplashSceneHoursX = {'), /kSplashSceneHours/);
  refused(source.replace('kSplashSceneMonths = {', 'kSplashSceneMonthsX = {'), /kSplashSceneMonths/);
  refused(source.replace('kSplashPoolWeights = {', 'kSplashPoolWeightsX = {'), /kSplashPoolWeights/);
  refused(source.replace('kSplashOnceADay = {', 'kSplashOnceADayX = {'), /kSplashOnceADay/);
  refused(source.replace('kSplashDailyChance = {', 'kSplashDailyChanceX = {'), /kSplashDailyChance/);
  refused(source.replace(/^\s*'eveningChecklist': 60,$/m, "  'dayRing': 60,"), /dayRing.*kSplashDailyChance/);
  refused(source.replace(/^const int kSplashPoolWeightMax = \d+;$/m, ''), /kSplashPoolWeightMax/);
  refused(source.replace(/^const int kSplashLineMaxLength = \d+;$/m, ''), /kSplashLineMaxLength/);
  refused(source.replace(/^\s*'walk',$/m, "  'newScene',"), /newScene/);
});

test('every scene is on the page, with its English line from the app', () => {
  const dart = fs.readFileSync(splashAdmin.LAUNCH_SCENE_DART, 'utf8');
  const { names, lines, slowLine } = splashAdmin.parseSceneDart(dart);
  assert.deepStrictEqual(names, SplashRules.SCENE_NAMES, 'the page lists the enum, in its order');
  assert.strictEqual(builtIn.lines.walk, lines.walk);
  assert.strictEqual(builtIn.lines.turnaround, 'Let’s Grow Daily');
  assert.strictEqual(Object.keys(builtIn.lines).length, 16);
  assert.strictEqual(slowLine, builtIn.slowLine);
  for (const name of SplashRules.SCENE_NAMES) {
    assert.ok(builtIn.lines[name].length <= builtIn.lineMax, name);
  }
  assert.deepStrictEqual(
    SplashRules.SCENE_NAMES.filter((n) => !builtIn.order.includes(n)).sort(), ['dayRing', 'turnaround']);
  assert.throws(() => splashAdmin.parseSceneDart(dart.replace(/^\s*LaunchScene\.walk => '[^']*',$/m, '')), /line of walk/);
  assert.throws(() => splashAdmin.parseSceneDart(dart.replace(/^const kLaunchSlowLine = /m, 'const kLaunchSlow = ')), /kLaunchSlowLine/);
});

// ---- The same cases as the app -------------------------------------------------

for (const c of fixture.cases) {
  test(`in force: ${c.name}`, () => {
    const inForce = SplashRules.resolve(builtIn, c.edits);
    for (const [key, value] of Object.entries(c.expect)) {
      assert.deepStrictEqual(inForce[key], value, key);
    }
  });
}

// ---- Checking a draft ------------------------------------------------------------

test('an untouched page stores nothing', () => {
  const check = SplashRules.checkDraft(builtIn, builtInDraft());
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.warnings, []);
  assert.strictEqual(check.edits, null);
});

test('only what differs from the built-in values is stored', () => {
  const draft = builtInDraft();
  draft.minShowMs = 2000;
  draft.noRepeat = 0;
  draft.walkerFromHour = 6;
  draft.walkerToHour = 8;
  draft.order = ['walk', ...builtIn.order.filter((n) => n !== 'walk')];
  draft.off = ['update', 'eid', 'turnaround'];
  draft.hours.morningCoffee = [5, 9];
  draft.hours.winterWait = ['', ''];
  draft.hours.firstOpen = [8, 20];
  draft.hours.dayRing = [6, 18];
  draft.hours.nightAsleep = [0, 24]; // the whole day, same as no limit
  draft.months.summerNoon = [];
  draft.months.winterWait = [11, 10, 9, 8, 7, 6, 5, 4, 3]; // the built-in months, any order
  draft.months.eid = [3];
  draft.pool.walk = 5;
  draft.pool.update = 1;
  draft.pool.dayRing = 0;
  draft.lines.walk = '  Every   step, we Grow Daily ';
  draft.lines.eid = 'Happy Eid'; // no Grow Daily: a warning, not an error
  draft.slowLine = 'Still loading, we Grow Daily';
  draft.force = { scene: 'walk', from: '2026-12-01', to: '2026-12-31' };
  const check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(check.warnings.length, 1, check.warnings.join('\n'));
  assert.match(check.warnings[0], /Eid lights: the line has no/);
  assert.deepStrictEqual(check.edits, {
    minShowMs: 2000,
    noRepeat: 0,
    walkerFromHour: 6,
    walkerToHour: 8,
    order: draft.order,
    off: ['turnaround', 'eid', 'update'],
    hours: {
      morningCoffee: [5, 9],
      winterWait: [0, 24],
      firstOpen: [8, 20],
      dayRing: [6, 18],
      nightAsleep: [0, 24],
    },
    months: { summerNoon: [], eid: [3] },
    pool: { walk: 5, update: 1, dayRing: 0 },
    lines: { walk: 'Every step, we Grow Daily', eid: 'Happy Eid' },
    slowLine: 'Still loading, we Grow Daily',
    force: { scene: 'walk', from: '2026-12-01', to: '2026-12-31' },
  });
  // And what that puts in force is the page's draft again (hours 0 to 24 and
  // blank are the same thing, a line is kept tidied).
  const again = SplashRules.draftFrom(builtIn, SplashRules.resolve(builtIn, check.edits));
  draft.hours.nightAsleep = ['', ''];
  draft.months.winterWait = [3, 4, 5, 6, 7, 8, 9, 10, 11];
  draft.off = ['turnaround', 'eid', 'update'];
  draft.lines.walk = 'Every step, we Grow Daily';
  assert.deepStrictEqual(again, draft);
});

test('the walkers\' hour: blank is none, stored as the same hour twice; half filled is refused', () => {
  const draft = builtInDraft();
  draft.walkerFromHour = '';
  draft.walkerToHour = '';
  let check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.edits, { walkerFromHour: 0, walkerToHour: 0 });
  const inForce = SplashRules.resolve(builtIn, check.edits);
  assert.strictEqual(SplashRules.walkerWindow(inForce), null);
  assert.deepStrictEqual(SplashRules.draftFrom(builtIn, inForce).walkerFromHour, '', 'none shows blank');
  // The same hour typed twice is none too.
  draft.walkerFromHour = 7;
  draft.walkerToHour = 7;
  check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(SplashRules.walkerWindow(SplashRules.resolve(builtIn, check.edits)), null);
  draft.walkerToHour = '';
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.walkerFromHour = 24;
  draft.walkerToHour = 25;
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 2);
});

test('every month ticked is every month', () => {
  const draft = builtInDraft();
  draft.months.eid = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  draft.months.summerNoon = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  const check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.edits, { months: { summerNoon: [] } });
});

test('a draft the app would not take is refused, field by field', () => {
  const draft = builtInDraft();
  draft.minShowMs = 500;
  draft.awayDays = 'many';
  draft.newFirst = 2;
  draft.hours.walk = [16, 16];
  draft.hours.nightAsleep = [22, '']; // half filled
  draft.hours.eveningChecklist = [18, 25];
  draft.hours.winterWait = [24, 3];
  draft.months.summerNoon = [13];
  draft.pool.walk = 11;
  draft.pool.eid = 2; // not an anytime scene
  draft.lines.walk = 'x'.repeat(61);
  draft.lines.eid = '   ';
  draft.slowLine = 'y'.repeat(70);
  draft.force = { scene: 'walk', from: 'tomorrow', to: '' };
  const check = SplashRules.checkDraft(builtIn, draft);
  assert.strictEqual(check.errors.length, 14, check.errors.join('\n'));
});

test('a line of 60 characters is taken, 61 is refused', () => {
  const draft = builtInDraft();
  draft.lines.walk = 'We Grow Daily ' + 'a'.repeat(46);
  assert.strictEqual(draft.lines.walk.length, 60);
  assert.deepStrictEqual(SplashRules.checkDraft(builtIn, draft).errors, []);
  draft.lines.walk += 'a';
  const errors = SplashRules.checkDraft(builtIn, draft).errors;
  assert.strictEqual(errors.length, 1);
  assert.match(errors[0], /61 characters, 60 at most/);
});

test('the longest stay must leave a second after the shortest', () => {
  const draft = builtInDraft();
  draft.minShowMs = 5000;
  draft.maxShowMs = 5900;
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.maxShowMs = 6000;
  assert.deepStrictEqual(SplashRules.checkDraft(builtIn, draft).errors, []);
});

test('dates: the last day cannot come before the first, and a day must be a day', () => {
  const draft = builtInDraft();
  draft.force = { scene: 'eid', from: '2026-12-31', to: '2026-12-01' };
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.force = { scene: 'eid', from: '2026-02-31', to: '' };
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.force = { scene: '', from: '2026-12-01', to: '' };
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.force = { scene: 'eid', from: '2026-12-01', to: '2026-12-01' };
  assert.deepStrictEqual(SplashRules.checkDraft(builtIn, draft).errors, []);
});

test('an order that is not each scene once is refused', () => {
  const draft = builtInDraft();
  draft.order = builtIn.order.slice(1);
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
  draft.order = [...builtIn.order.slice(1), 'firstOpen', 'firstOpen'];
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).errors.length, 1);
});

test('warnings: every ordered scene off, an empty anytime list, a forced scene with no last day', () => {
  const draft = builtInDraft();
  draft.off = builtIn.order.slice();
  for (const name of Object.keys(draft.pool)) draft.pool[name] = 0;
  draft.force = { scene: 'walk', from: '', to: '' };
  const check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(check.warnings.length, 3, check.warnings.join('\n'));
  draft.force.to = '2026-12-31';
  assert.strictEqual(SplashRules.checkDraft(builtIn, draft).warnings.length, 2);
  // Shares left, but every anytime scene off: still empty.
  const off = builtInDraft();
  off.off = SplashRules.poolScenes(builtIn).slice();
  assert.ok(SplashRules.checkDraft(builtIn, off).warnings.some((w) => /anytime list is empty/.test(w)));
});

test('warnings: a walk that can never play, a walkers\' hour outside its hours', () => {
  const draft = builtInDraft();
  draft.hours.walk = [6, 9];
  let warnings = SplashRules.checkDraft(builtIn, draft).warnings;
  assert.strictEqual(warnings.length, 1, warnings.join('\n'));
  assert.match(warnings[0], /outside the walk’s own hours/);
  draft.pool.walk = 0;
  warnings = SplashRules.checkDraft(builtIn, draft).warnings;
  assert.strictEqual(warnings.length, 2, warnings.join('\n'));
});

// ---- What plays when (the port of pickLaunchScene and pickAnytimeScene) ---------

const ask = (over) => ({
  date: '2026-10-07', // a Wednesday
  hour: 9,
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
  ...over,
});
// The rules themselves, with every moment playing every day; the daily
// chance has its own tests below.
const sure = { chance: { morningCoffee: 100, summerNoon: 100, eveningChecklist: 100, winterWait: 100 } };
const builtInForce = SplashRules.resolve(builtIn, sure);
const pick = (over, edits) => SplashRules.pick(edits ? SplashRules.resolve(builtIn, { ...sure, ...edits }) : builtInForce, ask(over));
const scene = (over, edits) => pick(over, edits).scene;
const odds = (over, edits) => Object.fromEntries(pick(over, edits).odds.map((o) => [o.scene, Math.round(o.chance * 100)]));

test('preview: the built-in rules, in their order', () => {
  assert.strictEqual(scene({}), 'morningCoffee');
  assert.strictEqual(scene({ played: { morningCoffee: true } }), null, 'once a day: then the anytime list');
  assert.strictEqual(scene({ fastPlanned: true }), null, 'a fast: no mug');
  assert.strictEqual(scene({ dayBeforeRamadan: true }), null, 'the day before Ramadan: no mug');
  assert.strictEqual(scene({ ramadan: true, hour: 23 }), 'ramadanLantern');
  assert.strictEqual(scene({ freshInstall: true, hour: 23 }), 'firstOpen', 'the seed leads, even at night');
  assert.strictEqual(scene({ installedDaysAgo: 2, neverSeen: { firstOpen: true } }), 'firstOpen', 'still owed');
  assert.strictEqual(scene({ installedDaysAgo: 3, neverSeen: { firstOpen: true } }), 'morningCoffee', 'owed for three days only');
  assert.strictEqual(scene({ installedDaysAgo: 1 }), 'morningCoffee', 'the seed has played');
  assert.strictEqual(scene({ away: true, ramadan: true }), 'welcomeBack', 'away wins over Ramadan');
  assert.strictEqual(scene({ updated: true, ramadan: true }), 'update', 'the bulb wins over Ramadan');
  assert.strictEqual(scene({ updated: true, hour: 23 }), 'nightAsleep', 'the bulb waits out the night');
  assert.strictEqual(scene({ updated: true, updateDaysAgo: 7 }), 'morningCoffee', 'the bulb is old news after seven days');
  assert.strictEqual(scene({ ramadan: true, hour: 23 }), 'ramadanLantern', 'Ramadan wins over night');
  assert.strictEqual(scene({ hour: 23 }), 'nightAsleep');
  assert.strictEqual(scene({ hour: 2 }), 'nightAsleep', 'the window wraps past midnight');
  assert.strictEqual(scene({ eid: true, hour: 13 }), 'eid');
  assert.strictEqual(scene({ perfectYesterday: true, hour: 13 }), 'fullDay');
  assert.strictEqual(scene({ perfectYesterday: true, hour: 13, played: { fullDay: true } }), null);
  assert.strictEqual(scene({ perfectYesterday: true }), 'fullDay', 'full day wins over the mug, which waits');
  assert.strictEqual(scene({ stepsYesterday: true, hour: 13 }), 'stepsGoal');
  assert.strictEqual(scene({ date: '2026-10-10', hour: 10 }), 'saturday');
  assert.strictEqual(scene({ date: '2026-10-10', hour: 12, played: { saturday: true } }), null);
  assert.strictEqual(scene({ date: '2026-07-07', hour: 13 }), 'summerNoon');
  assert.strictEqual(scene({ hour: 19 }), 'eveningChecklist');
  assert.strictEqual(scene({ hour: 15 }), 'winterWait');
  assert.strictEqual(scene({ date: '2026-12-07', hour: 15 }), null, 'missing winter is not in Bahrain\'s winter');
  assert.strictEqual(scene({ hour: 16, played: { winterWait: true }, walker: true }), 'walk', 'the walkers\' hour');
  assert.strictEqual(scene({ hour: 18, walker: true }), 'eveningChecklist', 'the walkers\' hour ends at 18:00');
  assert.strictEqual(scene({ hour: 16, played: { winterWait: true } }), null, 'not a walker');
});

test('preview: the anytime list\'s odds', () => {
  // 13:00 in October: every anytime scene but missing winter (15 to 18).
  assert.deepStrictEqual(odds({ hour: 13 }), { dayRing: 14, turnaround: 14, firstOpen: 14, stepsGoal: 29, walk: 29 });
  assert.deepStrictEqual(odds({ hour: 16, played: { winterWait: true } }),
    { dayRing: 13, turnaround: 13, firstOpen: 13, stepsGoal: 25, winterWait: 13, walk: 25 });
  // Never seen first, never twice in a row.
  assert.deepStrictEqual(odds({ hour: 13, neverSeen: { walk: true } }), { walk: 100 });
  assert.strictEqual(scene({ hour: 13, neverSeen: { walk: true } }), 'walk');
  assert.deepStrictEqual(odds({ hour: 13, neverSeen: { walk: true, turnaround: true } }), { turnaround: 33, walk: 67 });
  assert.deepStrictEqual(odds({ hour: 13, neverSeen: { walk: true } }, { newFirst: 0 }), { dayRing: 14, turnaround: 14, firstOpen: 14, stepsGoal: 29, walk: 29 });
  assert.deepStrictEqual(odds({ hour: 13, lastScene: 'walk' }), { dayRing: 20, turnaround: 20, firstOpen: 20, stepsGoal: 40 });
  assert.deepStrictEqual(odds({ hour: 13, lastScene: 'walk', neverSeen: { walk: true } }), { walk: 100 }, 'the only one left may repeat');
  assert.strictEqual(odds({ hour: 13, lastScene: 'walk' }, { noRepeat: 0 }).walk, 29);
  // Shares, switches and hours.
  assert.deepStrictEqual(odds({ hour: 13 }, { pool: { dayRing: 0, turnaround: 0, firstOpen: 0, stepsGoal: 0 } }), { walk: 100 });
  assert.deepStrictEqual(odds({ hour: 13 }, { off: ['walk', 'stepsGoal'] }), { dayRing: 33, turnaround: 33, firstOpen: 33 });
  assert.deepStrictEqual(odds({ hour: 13 }, { hours: { walk: [16, 18] } }), { dayRing: 20, turnaround: 20, firstOpen: 20, stepsGoal: 40 });
  const empty = { pool: { dayRing: 0, turnaround: 0, firstOpen: 0, stepsGoal: 0, walk: 0, winterWait: 0 } };
  assert.strictEqual(scene({ hour: 13 }, empty), 'dayRing', 'an empty list plays the day ring');
  assert.strictEqual(scene({ hour: 13 }, { off: ['dayRing', 'turnaround', 'firstOpen', 'stepsGoal', 'walk', 'winterWait'] }), 'dayRing');
  assert.deepStrictEqual(odds({ hour: 13 }, { pool: { update: 2 } }), { dayRing: 13, turnaround: 13, firstOpen: 13, update: 13, stepsGoal: 25, walk: 25 });
});

test('preview: a switch, hours, months, the order, the walkers\' hour and a forced scene', () => {
  assert.strictEqual(scene({ hour: 23 }, { off: ['nightAsleep'] }), null);
  assert.strictEqual(scene({ hour: 23 }, { hours: { nightAsleep: [23, 24] } }), 'nightAsleep');
  assert.strictEqual(scene({ hour: 2 }, { hours: { nightAsleep: [23, 24] } }), null);
  assert.strictEqual(scene({ hour: 2 }, { hours: { nightAsleep: [0, 24] } }), 'nightAsleep');
  assert.strictEqual(scene({ date: '2026-07-07', hour: 13 }, { months: { summerNoon: [10] } }), null);
  assert.strictEqual(scene({ date: '2026-07-07', hour: 13 }, { months: { summerNoon: [] } }), 'summerNoon');
  // The evening moved above the first launch.
  assert.strictEqual(scene({ hour: 19, freshInstall: true }), 'firstOpen');
  assert.strictEqual(scene({ hour: 19, freshInstall: true }, { order: ['eveningChecklist'] }), 'eveningChecklist');
  // Saturday with no hours is ready from midnight.
  assert.strictEqual(scene({ date: '2026-10-10', hour: 3 }, { off: ['nightAsleep'], hours: { saturday: [0, 24] } }), 'saturday');
  // The walkers' hour, and the walk's own hours limiting it.
  assert.strictEqual(scene({ hour: 7, walker: true, played: { morningCoffee: true } }, { walkerFromHour: 6, walkerToHour: 9 }), 'walk');
  assert.strictEqual(scene({ hour: 16, walker: true, played: { winterWait: true } }, { walkerFromHour: 0, walkerToHour: 0 }), null, 'no walkers\' hour');
  assert.strictEqual(scene({ hour: 16, walker: true, played: { winterWait: true } }, { hours: { walk: [6, 9] } }), null, 'outside the walk\'s own hours');
  // Forced: wins over night, Ramadan and a fresh install, only between its days.
  const forced = { force: { scene: 'update', from: '2026-10-07', to: '2026-10-08' } };
  assert.strictEqual(scene({ hour: 23, ramadan: true, freshInstall: true }, forced), 'update');
  assert.strictEqual(pick({ hour: 23, ramadan: true }, forced).forced, true);
  assert.strictEqual(scene({ date: '2026-10-09', hour: 23 }, forced), 'nightAsleep');
  assert.strictEqual(scene({ date: '2026-10-06', hour: 23 }, forced), 'nightAsleep');
  assert.ok(pick({ date: 'soon' }).error);
});

test('the day roll is the app\'s, to the number', () => {
  const rolls = (scene) => [1, 2, 3].map((d) => SplashRules.launchDayRoll(scene, 2026, 10, d));
  assert.deepStrictEqual(rolls('morningCoffee'), [87, 26, 65]);
  assert.deepStrictEqual(rolls('eveningChecklist'), [20, 59, 45]);
  assert.deepStrictEqual(rolls('winterWait'), [15, 1, 40]);
  for (let d = 1; d <= 31; d++) {
    const r = SplashRules.launchDayRoll('summerNoon', 2027, 12, d);
    assert.ok(Number.isInteger(r) && r >= 0 && r < 100);
  }
});

test('preview: how often a moment plays, by the day\'s roll', () => {
  const real = (over, edits) => SplashRules.pick(SplashRules.resolve(builtIn, edits || null), ask(over));
  // Morning coffee plays on 70% of days: 1 October rolls 87, 2 October 26.
  const skipped = real({ date: '2026-10-01', hour: 9 });
  assert.strictEqual(skipped.scene, null);
  assert.ok(skipped.odds.length > 1);
  assert.deepStrictEqual(skipped.skipped, ['Morning coffee steps aside today (70% of days).']);
  assert.strictEqual(real({ date: '2026-10-02', hour: 9 }).scene, 'morningCoffee');
  // The evening checklist plays on 60%: 4 October rolls 84, 5 October 23.
  assert.strictEqual(real({ date: '2026-10-04', hour: 19 }).scene, null);
  assert.strictEqual(real({ date: '2026-10-05', hour: 19 }).scene, 'eveningChecklist');
  // No note for a moment that would not have played anyway.
  assert.deepStrictEqual(real({ date: '2026-10-01', hour: 9, played: { morningCoffee: true } }).skipped, []);
  // 100 is every day; 0 is never.
  assert.strictEqual(real({ date: '2026-10-01', hour: 9 }, { chance: { morningCoffee: 100 } }).scene, 'morningCoffee');
  assert.strictEqual(real({ date: '2026-10-02', hour: 9 }, { chance: { morningCoffee: 0 } }).scene, null);
  // Before 04:00 the roll is the day before's: night on 50% of days rolls
  // 64 on 1 October (steps aside) and 3 on 2 October (plays).
  const halfNight = { chance: { nightAsleep: 50 } };
  assert.strictEqual(real({ date: '2026-10-02', hour: 2 }, halfNight).scene, null, 'the 1 October launch day');
  assert.strictEqual(real({ date: '2026-10-02', hour: 23 }, halfNight).scene, 'nightAsleep', 'the 2 October launch day');
  // The next days, as the card's strip shows them.
  const inForce = SplashRules.resolve(builtIn, null);
  const days = SplashRules.chanceDays(inForce, 'eveningChecklist', 2026, 10, 1, 10);
  assert.deepStrictEqual(days.map((d) => (d.plays ? 1 : 0)), [1, 1, 1, 0, 1, 1, 1, 1, 0, 1]);
  assert.deepStrictEqual([days[0].d, days[9].d, days[0].weekday], [1, 10, 4]);
  assert.deepStrictEqual(SplashRules.addDays(2026, 12, 31, 1), { y: 2027, m: 1, d: 1, weekday: 5 });
});

test('preview: once a day hands the day\'s other opens to the anytime list', () => {
  assert.strictEqual(scene({ hour: 19, played: { eveningChecklist: true } }), null);
  assert.deepStrictEqual(pick({ hour: 19, played: { eveningChecklist: true } }).skipped, ['Evening checklist already played today (once a day).']);
  assert.strictEqual(scene({ hour: 19, played: { eveningChecklist: true } }, { onceADay: { eveningChecklist: 0 } }), 'eveningChecklist');
  assert.strictEqual(scene({ hour: 23, played: { nightAsleep: true } }), 'nightAsleep', 'night keeps every open');
  assert.strictEqual(scene({ hour: 23, played: { nightAsleep: true } }, { onceADay: { nightAsleep: 1 } }), null);
  assert.strictEqual(scene({ hour: 16, walker: true, played: { walk: true, winterWait: true } }), null, 'the walkers\' moment once a day');
});

test('checking how often and once a day', () => {
  const draft = builtInDraft();
  assert.deepStrictEqual(Object.keys(draft.onceADay), ['eveningChecklist', 'nightAsleep', 'ramadanLantern', 'eid', 'summerNoon', 'walk']);
  assert.strictEqual(draft.chance.eveningChecklist, 60);
  assert.strictEqual(draft.chance.eid, 100);
  draft.onceADay.nightAsleep = 1;
  draft.onceADay.walk = 0;
  draft.chance.eveningChecklist = 100;
  draft.chance.eid = 40;
  draft.chance.walk = 0;
  let check = SplashRules.checkDraft(builtIn, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.edits, {
    onceADay: { nightAsleep: 1, walk: 0 },
    chance: { eveningChecklist: 100, eid: 40, walk: 0 },
  });
  assert.strictEqual(check.warnings.length, 1, check.warnings.join('\n'));
  assert.match(check.warnings[0], /Walk plays on 0% of days/);
  const again = SplashRules.draftFrom(builtIn, SplashRules.resolve(builtIn, check.edits));
  assert.deepStrictEqual(again, draft);
  draft.onceADay.nightAsleep = 2;
  draft.onceADay.morningCoffee = 1;
  draft.chance.eveningChecklist = 101;
  draft.chance.dayRing = 50;
  check = SplashRules.checkDraft(builtIn, draft);
  assert.strictEqual(check.errors.length, 4, check.errors.join('\n'));
});

test('the anytime list\'s parts, whatever the hour', () => {
  const parts = Object.fromEntries(SplashRules.poolShares(builtInForce).map((p) => [p.scene, Math.round(p.chance * 100)]));
  assert.deepStrictEqual(parts, { dayRing: 13, turnaround: 13, firstOpen: 13, stepsGoal: 25, winterWait: 13, walk: 25 });
  assert.deepStrictEqual(SplashRules.poolShares(SplashRules.resolve(builtIn, { pool: { dayRing: 0, turnaround: 0, firstOpen: 0, stepsGoal: 0, walk: 0, winterWait: 0 } })), []);
});

// ---- Saving ------------------------------------------------------------------------

const otherFields = {
  strings: { ar: { signIn: 'دخول' }, en: {} },
  faq: { order: ['q-a'] },
  version: 3,
  somethingNewer: { keep: true },
  pet: { praiseEverySeconds: 15 },
};

test('a save writes wording/live.splash and keeps every other field as it was', async () => {
  const db = liveDb(JSON.parse(JSON.stringify(otherFields)));
  const draft = builtInDraft();
  draft.minShowMs = 2000;
  draft.off = ['eid'];
  draft.pool.walk = 6;
  draft.lines.walk = 'One step more, we Grow Daily';
  const result = await splashAdmin.saveSplash(db, FieldValue, { draft, base: null });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.splash, { minShowMs: 2000, off: ['eid'], pool: { walk: 6 }, lines: { walk: 'One step more, we Grow Daily' } });
  assert.strictEqual(doc.version, 4);
  assert.deepStrictEqual(doc.strings, otherFields.strings);
  assert.deepStrictEqual(doc.faq, otherFields.faq);
  assert.deepStrictEqual(doc.pet, { praiseEverySeconds: 15 });
  assert.deepStrictEqual(doc.somethingNewer, { keep: true });
});

test('going back to every built-in value removes the field', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), splash: { minShowMs: 2000 } });
  const result = await splashAdmin.saveSplash(db, FieldValue, { draft: builtInDraft(), base: { minShowMs: 2000 } });
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.strictEqual(doc.splash, undefined);
  assert.strictEqual(doc.version, 4);
});

test('saving what is stored already changes nothing', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), splash: { minShowMs: 2000 } });
  const draft = builtInDraft();
  draft.minShowMs = 2000;
  const result = await splashAdmin.saveSplash(db, FieldValue, { draft, base: { minShowMs: 2000 } });
  assert.strictEqual(result.changed, false);
  assert.strictEqual(db.docs.get(wording.LIVE_DOC).version, 3);
});

test('a page older than the stored settings is refused and writes nothing', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), splash: { awayDays: 5 } });
  const draft = builtInDraft();
  draft.minShowMs = 2000;
  await assert.rejects(
    splashAdmin.saveSplash(db, FieldValue, { draft, base: null }),
    (e) => e instanceof splashAdmin.SplashInputError && e.status === 409,
  );
  assert.deepStrictEqual(db.docs.get(wording.LIVE_DOC).splash, { awayDays: 5 });
  assert.strictEqual(db.docs.get(wording.LIVE_DOC).version, 3);
});

test('a draft with an error writes nothing', async () => {
  const db = liveDb(JSON.parse(JSON.stringify(otherFields)));
  const draft = builtInDraft();
  draft.awayDays = 0;
  const result = await splashAdmin.saveSplash(db, FieldValue, { draft, base: null });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.errors.length, 1);
  assert.strictEqual(db.state.transactions, 0);
});

test('a Wording save and a Doum save keep the splash settings', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), splash: { awayDays: 5 } });
  const signIn = { key: 'signIn', editable: true, ar: 'تسجيل الدخول', en: 'Sign in', tokensAr: [], tokensEn: [] };
  const result = await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(db.docs.get(wording.LIVE_DOC).splash, { awayDays: 5 });
});

// ---- The page ------------------------------------------------------------------------

test('the page loads its rules before its script, and neither is inline', () => {
  const html = renderSplashPage({ projectId: 'demo' });
  const rules = html.indexOf('<script src="/wording/splash_rules.js">');
  const app = html.indexOf('<script src="/splash/app.js">');
  assert.ok(rules > 0 && app > rules);
  const inline = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  for (const body of inline) {
    assert.ok(!/SplashRules|\/api\/splash/.test(body));
    new vm.Script(body);
  }
  assert.ok(html.includes('href="/splash"'), 'the sidebar links to the page');
  assert.ok(html.indexOf('href="/pet"') < html.indexOf('href="/splash"'), 'the item follows Doum');
  const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length);
  assert.ok(css.includes('--splash-styles:'));
});

test('the page\'s browser files parse, and hold no em dash', () => {
  for (const file of ['splash/app.js', 'wording/splash_rules.js', 'lib/splash_page.js', 'lib/splash_admin.js', 'test/splash.test.js', 'test/fixtures/splash_cases.json']) {
    const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    assert.ok(!source.includes(EM_DASH), file);
    if (file.endsWith('app.js') || file.includes('splash_rules')) new vm.Script(source, { filename: file });
  }
  const edition = fs.readFileSync(path.join(__dirname, '..', 'splash', 'app.js'), 'utf8').match(/const EDITION = '(\d+)'/)[1];
  assert.ok(renderSplashPage({}).includes(`--splash-styles: '${edition}'`), 'the script and the styles agree on the edition');
});
