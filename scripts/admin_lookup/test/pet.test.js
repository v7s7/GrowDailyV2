'use strict';

/**
 * The «دوم» page (lib/pet_admin.js, wording/pet_rules.js, pet/app.js):
 * Doum's timing, hours and praise lists, stored in wording/live.pet.
 *
 * The cases in fixtures/pet_cases.json are also run by the app
 * (test/features/mascot/pet_settings_test.dart), so what the page shows
 * before Save is what phones do after it.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const PetRules = require('../wording/pet_rules');
const petAdmin = require('../lib/pet_admin');
const wording = require('../lib/wording');
const { renderPetPage } = require('../lib/pet_page');
const { fakeDb, FieldValue } = require('./support/fake_firestore');

const builtIn = petAdmin.builtInPet();
const presetIds = petAdmin.presetHabits().map((p) => p.id);
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'pet_cases.json'), 'utf8'));

// Built, never typed: this file keeps the rule it tests.
const EM_DASH = String.fromCharCode(0x2014);

function builtInDraft() {
  return PetRules.draftFrom(PetRules.resolve(builtIn, null), presetIds);
}

function liveDb(data) {
  const db = fakeDb();
  if (data) db.docs.set(wording.LIVE_DOC, data);
  return db;
}

// ---- The built-in values, read out of the app ------------------------------

test('every built-in setting is read out of pet_settings.dart', () => {
  assert.deepStrictEqual(builtIn.numbers, {
    praiseEverySeconds: 20,
    bubbleSeconds: 3,
    rememberLines: 30,
    morningUntilHour: 12,
    bedtimeHour: 21,
    wakeHour: 4,
    squareConfettiPieces: 16,
    squareConfettiSpread: 72,
    squareConfettiMs: 650,
    streakConfettiPieces: 16,
    streakConfettiSpread: 72,
    streakConfettiMs: 650,
    fullDayConfettiPieces: 30,
    fullDayConfettiSpread: 130,
    fullDayConfettiMs: 1000,
    fullDaySecondConfettiPieces: 22,
    fullDaySecondConfettiSpread: 170,
    fullDaySecondConfettiMs: 1100,
  });
  for (const key of PetRules.NUMBER_KEYS) {
    const [min, max] = builtIn.ranges[key];
    assert.ok(min <= builtIn.numbers[key] && builtIn.numbers[key] <= max, key);
  }
  assert.strictEqual(Object.keys(builtIn.categories).length, PetRules.CATEGORIES.length);
  assert.strictEqual(builtIn.categories.fitness, 'sport');
  assert.deepStrictEqual(builtIn.presets, { tahajjud: 'faith' });
  assert.strictEqual(builtIn.alsoHears.quran, 'faith');
  assert.strictEqual(builtIn.quit, 'general');
});

test('a Dart file that lost a value is refused, never guessed', () => {
  const source = fs.readFileSync(petAdmin.PET_SETTINGS_DART, 'utf8');
  const broken = source.replace(/^const int kPetBedtimeHour = \d+;$/m, '');
  assert.notStrictEqual(broken, source);
  assert.throws(() => petAdmin.parsePetDart(broken), (e) =>
    e instanceof petAdmin.PetInputError && /bedtimeHour/.test(e.message));
});

test('every ready-made habit is listed, and the lists match the app\'s', () => {
  assert.ok(presetIds.length >= 20, 'the catalog parse found the presets');
  assert.ok(presetIds.includes('tahajjud'));
  const lists = PetRules.LISTS.map((l) => l.name).sort();
  assert.deepStrictEqual(lists, [
    'athkar', 'faith', 'fasting', 'focus', 'general', 'health', 'learning',
    'mind', 'money', 'quran', 'sadaqah', 'sleep', 'social', 'sport',
  ]);
  // The app's PraiseGroup enum, read from its own source.
  const dart = fs.readFileSync(path.join(__dirname, '..', '..', '..',
    'lib', 'features', 'mascot', 'sprout_praise.dart'), 'utf8');
  const body = dart.match(/enum PraiseGroup \{([\s\S]*?)\}/)[1];
  const names = body.split(',').map((s) => s.trim()).filter(Boolean).sort();
  assert.deepStrictEqual(names, lists);
});

// ---- The same cases as the app -------------------------------------------------

for (const c of fixture.cases) {
  test(`in force: ${c.name}`, () => {
    const inForce = PetRules.resolve(builtIn, c.edits);
    for (const [key, value] of Object.entries(c.expect)) {
      assert.deepStrictEqual(inForce[key], value, key);
    }
  });
}

test('what a ready-made habit hears, as the app picks it', () => {
  const inForce = PetRules.resolve(builtIn, null);
  const habits = petAdmin.presetHabits();
  const byId = (id) => habits.find((h) => h.id === id);
  assert.strictEqual(PetRules.listFor(inForce, byId('tahajjud')), 'faith');
  const walk = habits.find((h) => h.category === 'fitness');
  assert.strictEqual(PetRules.listFor(inForce, walk), 'sport');
  const quit = habits.find((h) => h.goalType === 'quit');
  assert.strictEqual(PetRules.listFor(inForce, quit), 'general');
  const moved = PetRules.resolve(builtIn, { presets: { [quit.id]: 'faith' } });
  assert.strictEqual(PetRules.listFor(moved, quit), 'faith', 'its own list wins over the quit rule');
});

// ---- Checking a draft ------------------------------------------------------------

test('an untouched page stores nothing', () => {
  const check = PetRules.checkDraft(builtIn, builtInDraft(), presetIds);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(check.edits, null);
});

test('only what differs from the built-in values is stored', () => {
  const draft = builtInDraft();
  draft.praiseEverySeconds = 15;
  draft.presets.tahajjud = '';
  draft.presets.cold_shower = 'health';
  draft.categories.custom = 'focus';
  draft.alsoHears.quran = '';
  draft.alsoHears.learning = 'focus';
  draft.quit = 'social';
  const check = PetRules.checkDraft(builtIn, draft, presetIds);
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.edits, {
    praiseEverySeconds: 15,
    presets: { tahajjud: '', cold_shower: 'health' },
    categories: { custom: 'focus' },
    alsoHears: { quran: '', learning: 'focus' },
    quit: 'social',
  });
  // And what that puts in force is the page's draft again.
  const inForce = PetRules.resolve(builtIn, check.edits);
  assert.deepStrictEqual(PetRules.draftFrom(inForce, presetIds), draft);
});

test('a draft the app would not take is refused, field by field', () => {
  const draft = builtInDraft();
  draft.praiseEverySeconds = 301;
  draft.bubbleSeconds = 2.5;
  draft.rememberLines = 'many';
  draft.presets.tahajjud = 'nope';
  draft.presets.no_such_habit = 'faith';
  draft.categories.faith = 'nope';
  draft.alsoHears.quran = 'quran';
  draft.alsoHears.general = 'faith';
  draft.quit = 'nope';
  const check = PetRules.checkDraft(builtIn, draft, presetIds);
  assert.strictEqual(check.errors.length, 9, check.errors.join('\n'));
});

test('warnings: confetti that no longer grows from one moment to the next', () => {
  const draft = builtInDraft();
  draft.fullDayConfettiPieces = 10;
  draft.fullDaySecondConfettiPieces = 12;
  draft.squareConfettiPieces = 40;
  const check = PetRules.checkDraft(builtIn, draft, presetIds);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(check.warnings.length, 2, check.warnings.join('\n'));
  assert.deepStrictEqual(check.edits, {
    fullDayConfettiPieces: 10,
    fullDaySecondConfettiPieces: 12,
    squareConfettiPieces: 40,
  });
});

test('warnings: a morning inside the sleeping hours, a bubble longer than the gap', () => {
  const draft = builtInDraft();
  draft.morningUntilHour = 4;
  draft.bubbleSeconds = 8;
  draft.praiseEverySeconds = 5;
  const check = PetRules.checkDraft(builtIn, draft, presetIds);
  assert.deepStrictEqual(check.errors, []);
  assert.strictEqual(check.warnings.length, 2);
});

// ---- Saving ------------------------------------------------------------------------

const otherFields = {
  strings: { ar: { signIn: 'دخول' }, en: {} },
  faq: { order: ['q-a'] },
  version: 3,
  somethingNewer: { keep: true },
};

test('a save writes wording/live.pet and keeps every other field as it was', async () => {
  const db = liveDb(JSON.parse(JSON.stringify(otherFields)));
  const draft = builtInDraft();
  draft.praiseEverySeconds = 15;
  const result = await petAdmin.savePet(db, FieldValue, { draft, base: null });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.pet, { praiseEverySeconds: 15 });
  assert.strictEqual(doc.version, 4);
  assert.deepStrictEqual(doc.strings, otherFields.strings);
  assert.deepStrictEqual(doc.faq, otherFields.faq);
  assert.deepStrictEqual(doc.somethingNewer, { keep: true });
});

test('going back to every built-in value removes the field', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), pet: { praiseEverySeconds: 15 } });
  const result = await petAdmin.savePet(db, FieldValue, { draft: builtInDraft(), base: { praiseEverySeconds: 15 } });
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.strictEqual(doc.pet, undefined);
  assert.strictEqual(doc.version, 4);
});

test('a page older than the stored settings is refused and writes nothing', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), pet: { bubbleSeconds: 5 } });
  const draft = builtInDraft();
  draft.praiseEverySeconds = 15;
  await assert.rejects(
    petAdmin.savePet(db, FieldValue, { draft, base: null }),
    (e) => e instanceof petAdmin.PetInputError && e.status === 409,
  );
  assert.deepStrictEqual(db.docs.get(wording.LIVE_DOC).pet, { bubbleSeconds: 5 });
  assert.strictEqual(db.docs.get(wording.LIVE_DOC).version, 3);
});

test('a draft with an error writes nothing', async () => {
  const db = liveDb(JSON.parse(JSON.stringify(otherFields)));
  const draft = builtInDraft();
  draft.bubbleSeconds = 0;
  const result = await petAdmin.savePet(db, FieldValue, { draft, base: null });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.errors.length, 1);
  assert.strictEqual(db.state.transactions, 0);
});

test('a Wording save keeps Doum\'s settings', async () => {
  const db = liveDb({ ...JSON.parse(JSON.stringify(otherFields)), pet: { quit: 'social' } });
  const signIn = { key: 'signIn', editable: true, ar: 'تسجيل الدخول', en: 'Sign in', tokensAr: [], tokensEn: [] };
  const result = await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(db.docs.get(wording.LIVE_DOC).pet, { quit: 'social' });
});

// ---- The page ------------------------------------------------------------------------

test('the page loads its rules before its script, and neither is inline', () => {
  const html = renderPetPage({ projectId: 'demo' });
  const rules = html.indexOf('<script src="/wording/pet_rules.js">');
  const app = html.indexOf('<script src="/pet/app.js">');
  assert.ok(rules > 0 && app > rules);
  // The only inline script is the frame's own theme switch (SHELL_HEAD),
  // and it parses.
  const inline = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  for (const body of inline) {
    assert.ok(!/PetRules|\/api\/pet/.test(body));
    new vm.Script(body);
  }
  assert.ok(html.includes('href="/pet"'), 'the sidebar links to the page');
  const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length);
});

test('the page\'s browser files parse, and hold no em dash', () => {
  for (const file of ['pet/app.js', 'wording/pet_rules.js', 'lib/pet_page.js', 'lib/pet_admin.js']) {
    const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    assert.ok(!source.includes(EM_DASH), file);
    if (file.endsWith('app.js') || file.includes('pet_rules')) new vm.Script(source, { filename: file });
  }
});
