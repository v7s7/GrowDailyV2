'use strict';

/**
 * The launch splash page's server side: the built-in settings, read out of
 * the app's own code, and the one write, the admin's edits into
 * wording/live.splash.
 *
 * Aziz, 2026-10-01: "make it controlled by admin page, he can control when
 * each appear and etc". Which scene Doum plays on the launch curtain, when,
 * in what order, for how long, and one scene played for everyone for a
 * stretch of days.
 *
 * Where it lives, and why it is built this way, is the Doum page's story
 * (lib/pet_admin.js): the `splash` field of wording/live, sparse (only what
 * differs from the built-in values), no History or Undo (every setting shows
 * the built-in value beside it), a save refused when the stored settings
 * changed since the page loaded them. lib/wording.js keeps every field it
 * does not know, so no other save drops this one.
 */

const fs = require('fs');
const path = require('path');
const SplashRules = require('../wording/splash_rules');
const { LIVE_DOC, shapeLive, liveDocument } = require('./wording');

const LAUNCH_DIR = path.join(__dirname, '..', '..', '..', 'lib', 'features', 'launch');
const SPLASH_SETTINGS_DART = path.join(LAUNCH_DIR, 'launch_settings.dart');
const LAUNCH_SCENE_DART = path.join(LAUNCH_DIR, 'launch_scene.dart');

class SplashInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function lowerFirst(s) {
  return s.charAt(0).toLowerCase() + s.slice(1);
}

/** The body of `const <type> <name> = <open> ... <close>;`, or null. */
function block(source, name, open, close) {
  const m = source.match(new RegExp(`^const [^=\\n]+ ${name} = \\${open}\\n([\\s\\S]*?)^\\${close};`, 'm'));
  return m ? m[1] : null;
}

/**
 * The built-in settings, read out of launch_settings.dart. The parse is
 * narrow on purpose, the shape that file promises at its top:
 * `const int kSplashX = N;` for a number, `'scene',` for an order entry,
 * `'scene': (from, to),` for hours, `'scene': '6,7',` for months,
 * `'scene': N,` for a share, once-a-day switch or daily chance, and
 * `'key': (min, max),` for a range. It throws when anything is missing, and
 * test/splash.test.js runs it on the real file.
 */
function parseSplashDart(source) {
  const ints = {};
  for (const m of source.matchAll(/^const int kSplash(\w+) = (\d+);$/gm)) {
    ints[lowerFirst(m[1])] = Number(m[2]);
  }
  const numbers = {};
  for (const key of SplashRules.NUMBER_KEYS) if (ints[key] !== undefined) numbers[key] = ints[key];
  const pairs = (name) => {
    const body = block(source, name, '{', '}');
    if (body === null) return null;
    const out = {};
    for (const e of body.matchAll(/^\s*'(\w+)': \((\d+), (\d+)\),$/gm)) out[e[1]] = [Number(e[2]), Number(e[3])];
    return out;
  };
  const ranges = pairs('kSplashNumberRanges');
  const hours = pairs('kSplashSceneHours');
  const orderBody = block(source, 'kSplashSceneOrder', '[', ']');
  const order = orderBody === null ? null : [...orderBody.matchAll(/^\s*'(\w+)',$/gm)].map((m) => m[1]);
  const monthsBody = block(source, 'kSplashSceneMonths', '{', '}');
  let months = null;
  if (monthsBody !== null) {
    months = {};
    for (const e of monthsBody.matchAll(/^\s*'(\w+)': '([\d,]+)',$/gm)) {
      months[e[1]] = e[2].split(',').map(Number);
    }
  }

  const intMap = (name) => {
    const body = block(source, name, '{', '}');
    if (body === null) return null;
    const out = {};
    for (const e of body.matchAll(/^\s*'(\w+)': (\d+),$/gm)) out[e[1]] = Number(e[2]);
    return out;
  };
  const pool = intMap('kSplashPoolWeights');
  const onceADay = intMap('kSplashOnceADay');
  const chance = intMap('kSplashDailyChance');
  const poolMax = ints.poolWeightMax;
  const lineMax = ints.lineMaxLength;

  const missing = [];
  for (const key of SplashRules.NUMBER_KEYS) {
    if (!Number.isInteger(numbers[key])) missing.push(`the built-in ${key}`);
    if (!ranges || !ranges[key]) missing.push(`the range of ${key}`);
  }
  if (!order || order.length === 0) missing.push('kSplashSceneOrder');
  else {
    for (const name of order) {
      if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`a known scene for "${name}" in kSplashSceneOrder`);
    }
  }
  if (!hours) missing.push('kSplashSceneHours');
  else {
    for (const [name, [from, to]] of Object.entries(hours)) {
      if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`a known scene for "${name}" in kSplashSceneHours`);
      if (from < 0 || from > 23 || to < 0 || to > 24 || from === to) missing.push(`valid hours for ${name}`);
    }
  }
  if (!months) missing.push('kSplashSceneMonths');
  else {
    for (const [name, list] of Object.entries(months)) {
      if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`a known scene for "${name}" in kSplashSceneMonths`);
      if (list.some((m) => m < 1 || m > 12)) missing.push(`valid months for ${name}`);
    }
  }
  if (!Number.isInteger(poolMax)) missing.push('kSplashPoolWeightMax');
  if (!Number.isInteger(lineMax)) missing.push('kSplashLineMaxLength');
  if (!pool || Object.keys(pool).length === 0) missing.push('kSplashPoolWeights');
  else {
    for (const [name, share] of Object.entries(pool)) {
      if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`a known scene for "${name}" in kSplashPoolWeights`);
      if (Number.isInteger(poolMax) && share > poolMax) missing.push(`a share of at most kSplashPoolWeightMax for ${name}`);
    }
  }
  if (!onceADay || Object.keys(onceADay).length === 0) missing.push('kSplashOnceADay');
  else {
    for (const [name, v] of Object.entries(onceADay)) {
      if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`a known scene for "${name}" in kSplashOnceADay`);
      if (v !== 0 && v !== 1) missing.push(`0 or 1 for ${name} in kSplashOnceADay`);
    }
  }
  if (!chance) missing.push('kSplashDailyChance');
  else {
    for (const [name, v] of Object.entries(chance)) {
      if (!(order || []).includes(name)) missing.push(`a scene of the order for "${name}" in kSplashDailyChance`);
      if (v > 100) missing.push(`a percent up to 100 for ${name} in kSplashDailyChance`);
    }
  }
  if (missing.length) {
    throw new SplashInputError(`Could not read the launch splash's built-in settings from launch_settings.dart: ${missing.join(', ')}.`, 500);
  }
  return { numbers, ranges, order, hours, months, pool, poolMax, lineMax, onceADay, chance };
}

/**
 * The scenes and their English lines, read out of launch_scene.dart: the enum
 * LaunchScene's values, each `LaunchScene.x => 'line',` of launchLine, and
 * `const kLaunchSlowLine = '...';`.
 */
function parseSceneDart(source) {
  const en = source.match(/^enum LaunchScene \{([\s\S]*?)^\}/m);
  const names = en ? [...en[1].matchAll(/^\s{2}(\w+),$/gm)].map((m) => m[1]) : [];
  const fn = source.match(/^String launchLine\(LaunchScene scene\) => switch \(scene\) \{([\s\S]*?)^\s{4}\};/m);
  const lines = {};
  if (fn) {
    for (const m of fn[1].matchAll(/LaunchScene\.(\w+) => '([^']*)',/g)) lines[m[1]] = m[2];
  }
  const slow = source.match(/^const kLaunchSlowLine = '([^']*)';$/m);
  const missing = [];
  if (!slow) missing.push('kLaunchSlowLine');
  if (!names.length) missing.push('enum LaunchScene');
  for (const name of SplashRules.SCENE_NAMES) {
    if (!names.includes(name)) missing.push(`the scene ${name}`);
    if (typeof lines[name] !== 'string') missing.push(`the line of ${name}`);
  }
  for (const name of names) {
    if (!SplashRules.SCENE_NAMES.includes(name)) missing.push(`the page's own entry for the new scene ${name}`);
  }
  if (missing.length) {
    throw new SplashInputError(`Could not read the launch scenes from launch_scene.dart: ${missing.join(', ')}.`, 500);
  }
  return { names, lines, slowLine: slow ? slow[1] : null };
}

let _builtIn = null; // { key, value }

/** The built-in settings and lines, read again only when either Dart file changes. */
function builtInSplash() {
  const key = [SPLASH_SETTINGS_DART, LAUNCH_SCENE_DART].map((f) => fs.statSync(f).mtimeMs).join('|');
  if (!_builtIn || _builtIn.key !== key) {
    const settings = parseSplashDart(fs.readFileSync(SPLASH_SETTINGS_DART, 'utf8'));
    const scenes = parseSceneDart(fs.readFileSync(LAUNCH_SCENE_DART, 'utf8'));
    _builtIn = { key, value: { ...settings, lines: scenes.lines, slowLine: scenes.slowLine } };
  }
  return _builtIn.value;
}

/** wording/live.splash as stored, or null. */
function storedSplash(live) {
  const splash = live.extra && live.extra.splash;
  return splash === undefined ? null : splash;
}

/** Everything the page needs. */
async function readSplash(db) {
  const snap = await db.doc(LIVE_DOC).get();
  const live = shapeLive(snap.exists ? snap.data() : null);
  const builtIn = builtInSplash();
  const stored = storedSplash(live);
  return {
    builtIn,
    stored,
    resolved: SplashRules.resolve(builtIn, stored),
    version: live.version,
    updatedAt: live.updatedAt,
  };
}

/**
 * Saves the page's [draft], the whole of the splash settings as the page
 * shows them. [base] is the stored settings the page was built from (null
 * for none); a save over settings that changed since is refused.
 *
 * Returns { ok, errors, warnings, changed }. Nothing is written unless the
 * draft passes every check.
 */
async function saveSplash(db, FieldValue, { draft, base }) {
  const builtIn = builtInSplash();
  const check = SplashRules.checkDraft(builtIn, draft);
  if (check.errors.length) {
    return { ok: false, errors: check.errors, warnings: check.warnings, changed: false };
  }
  const next = check.edits;
  const liveRef = db.doc(LIVE_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const stored = storedSplash(live);
    if (base !== undefined && !SplashRules.same(stored, base)) {
      throw new SplashInputError('The launch splash settings were saved from somewhere else since this page loaded. Reload the page to see them, then make your change again.', 409);
    }
    if (SplashRules.same(stored, next)) return false;
    if (next) live.extra.splash = next;
    else delete live.extra.splash;
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    return true;
  });
  return { ok: true, errors: [], warnings: check.warnings, changed };
}

module.exports = {
  SPLASH_SETTINGS_DART,
  LAUNCH_SCENE_DART,
  SplashInputError,
  parseSplashDart,
  parseSceneDart,
  builtInSplash,
  readSplash,
  saveSplash,
};
