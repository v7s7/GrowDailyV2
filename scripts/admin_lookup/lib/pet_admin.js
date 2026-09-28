'use strict';

/**
 * The «دوم» page's server side: Doum's built-in settings, read out of the
 * app's own code, and the one write, his edits into wording/live.pet.
 *
 * Aziz, 2026-09-28: "make everything changeable in the admin page". Doum's
 * words were already on the Wording page (sprout* strings, and his praise
 * lists, one line per row). This is the rest: how often he talks, how long
 * a bubble stays, how many lines he remembers, the hours he says good
 * morning, sleeps and wakes, and which praise list each habit hears.
 *
 * Where it lives: wording/live, the one document every phone already reads
 * and nobody writes but this tool, under `pet`, beside the string edits. So
 * a save needs no deploy and reaches open apps within a second or two, the
 * way a Wording save does (lib/core/l10n/pet_edits.dart reads it,
 * lib/features/mascot/pet_settings.dart lays it over the built-in values).
 * Only what differs from the built-in values is stored, so a setting nobody
 * changed keeps following the app's code. lib/wording.js keeps every field
 * it does not know when it saves, so a Wording, FAQ or Premium save never
 * drops this one, and this save writes the rest back exactly as it read it.
 *
 * Like the Achievements page, no History or Undo: every setting shows the
 * app's built-in value beside it, so going back is one click. A save is
 * refused when the stored settings changed since the page loaded them.
 */

const fs = require('fs');
const path = require('path');
const PetRules = require('../wording/pet_rules');
const HabitCatalog = require('./habit_catalog');
const { LIVE_DOC, shapeLive, liveDocument } = require('./wording');

const PET_SETTINGS_DART = path.join(__dirname, '..', '..', '..',
  'lib', 'features', 'mascot', 'pet_settings.dart');

class PetInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function lowerFirst(s) {
  return s.charAt(0).toLowerCase() + s.slice(1);
}

/**
 * The built-in settings, read out of pet_settings.dart. The parse is narrow
 * on purpose, the shape that file promises at its top: `const int kPetX = N;`
 * for a number, `'key': 'value',` for a map entry, `'key': (min, max),` for
 * a range. It throws when anything is missing, and test/pet.test.js runs it
 * on the real file, so a change there that breaks it fails a test here
 * rather than drawing a page of wrong defaults.
 */
function parsePetDart(source) {
  const numbers = {};
  for (const m of source.matchAll(/^const int kPet(\w+) = (\d+);$/gm)) {
    numbers[lowerFirst(m[1])] = Number(m[2]);
  }
  const block = (name) => {
    const m = source.match(new RegExp(`^const Map<[^>]+> ${name} = \\{\\n([\\s\\S]*?)^\\};`, 'm'));
    return m ? m[1] : null;
  };
  const textMap = (name) => {
    const body = block(name);
    if (body === null) return null;
    const out = {};
    for (const e of body.matchAll(/^\s*'([^']*)': '([^']*)',$/gm)) out[e[1]] = e[2];
    return out;
  };
  const rangeBody = block('kPetNumberRanges');
  const ranges = {};
  if (rangeBody !== null) {
    for (const e of rangeBody.matchAll(/^\s*'(\w+)': \((\d+), (\d+)\),$/gm)) {
      ranges[e[1]] = [Number(e[2]), Number(e[3])];
    }
  }
  const quit = source.match(/^const String kPetQuitList = '(\w+)';$/m);
  const builtIn = {
    numbers,
    ranges,
    categories: textMap('kPetCategoryLists'),
    presets: textMap('kPetPresetLists'),
    alsoHears: textMap('kPetAlsoHears'),
    quit: quit ? quit[1] : null,
  };

  const missing = [];
  for (const key of PetRules.NUMBER_KEYS) {
    if (!Number.isInteger(numbers[key])) missing.push(`the built-in ${key}`);
    if (!ranges[key]) missing.push(`the range of ${key}`);
  }
  if (!builtIn.categories) missing.push('kPetCategoryLists');
  else {
    for (const c of PetRules.CATEGORIES) {
      if (!PetRules.isList(builtIn.categories[c.name])) missing.push(`the list of category ${c.name}`);
    }
  }
  if (!builtIn.presets) missing.push('kPetPresetLists');
  if (!builtIn.alsoHears) missing.push('kPetAlsoHears');
  if (!PetRules.isList(builtIn.quit)) missing.push('kPetQuitList');
  if (missing.length) {
    throw new PetInputError(`Could not read Doum's built-in settings from pet_settings.dart: ${missing.join(', ')}.`, 500);
  }
  return builtIn;
}

let _builtIn = null; // { mtimeMs, value }

/** The built-in settings, read again only when the Dart file changes. */
function builtInPet() {
  const mtimeMs = fs.statSync(PET_SETTINGS_DART).mtimeMs;
  if (!_builtIn || _builtIn.mtimeMs !== mtimeMs) {
    _builtIn = { mtimeMs, value: parsePetDart(fs.readFileSync(PET_SETTINGS_DART, 'utf8')) };
  }
  return _builtIn.value;
}

/** The app's ready-made habits, as the page lists them. */
function presetHabits() {
  return HabitCatalog.catalog().templates.map((t) => ({
    id: t.id,
    name: t.name,
    nameAr: t.nameAr || null,
    category: t.category,
    goalType: t.goalType,
  }));
}

/** wording/live.pet as stored, or null. */
function storedPet(live) {
  const pet = live.extra && live.extra.pet;
  return pet === undefined ? null : pet;
}

/** Everything the page needs. */
async function readPet(db) {
  const snap = await db.doc(LIVE_DOC).get();
  const live = shapeLive(snap.exists ? snap.data() : null);
  const builtIn = builtInPet();
  const stored = storedPet(live);
  return {
    builtIn,
    presets: presetHabits(),
    stored,
    resolved: PetRules.resolve(builtIn, stored),
    version: live.version,
    updatedAt: live.updatedAt,
  };
}

/**
 * Saves the page's [draft], the whole of Doum's settings as the page shows
 * them. [base] is the stored settings the page was built from (null for
 * none); a save over settings that changed since is refused.
 *
 * Returns { ok, errors, warnings, changed }. Nothing is written unless the
 * draft passes every check.
 */
async function savePet(db, FieldValue, { draft, base }) {
  const builtIn = builtInPet();
  const presets = presetHabits();
  const check = PetRules.checkDraft(builtIn, draft, presets.map((p) => p.id));
  if (check.errors.length) {
    return { ok: false, errors: check.errors, warnings: check.warnings, changed: false };
  }
  const next = check.edits;
  const liveRef = db.doc(LIVE_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = shapeLive(snap.exists ? snap.data() : null);
    const stored = storedPet(live);
    if (base !== undefined && !PetRules.same(stored, base)) {
      throw new PetInputError('Doum\'s settings were saved from somewhere else since this page loaded. Reload the page to see them, then make your change again.', 409);
    }
    if (PetRules.same(stored, next)) return false;
    if (next) live.extra.pet = next;
    else delete live.extra.pet;
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    return true;
  });
  return { ok: true, errors: [], warnings: check.warnings, changed };
}

module.exports = {
  PET_SETTINGS_DART,
  PetInputError,
  parsePetDart,
  builtInPet,
  presetHabits,
  readPet,
  savePet,
};
