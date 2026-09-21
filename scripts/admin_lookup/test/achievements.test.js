'use strict';

/**
 * The Achievements page: what a field edit is checked against, what a save
 * does to the document every app reads its achievement text from, and that
 * the page and its script load at all.
 *
 * Runs against a small in-memory stand-in for Firestore, the same shape
 * wording.test.js uses and for the same reason: what matters about the real
 * one is that set() without merge replaces the whole document, which is the
 * property "back to built-in" depends on.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const Achievements = require('../lib/achievements_admin');
const { renderAchievementsPage } = require('../lib/achievements_page');
const { ACHIEVEMENTS_BY_ID } = require('../lib/achievements_catalog');

const FieldValue = { serverTimestamp: () => ({ __serverTimestamp: true }) };
const EM_DASH = String.fromCharCode(0x2014);

function copy(value) {
  if (value && value.__serverTimestamp) return { toDate: () => new Date() };
  if (Array.isArray(value)) return value.map(copy);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = copy(v);
    return out;
  }
  return value;
}

function fakeDb() {
  const docs = new Map();
  function snap(ref) {
    const data = docs.get(ref.path);
    return { exists: data !== undefined, data: () => copy(data) };
  }
  function ref(p) {
    return { path: p, get: async () => snap(ref(p)) };
  }
  return {
    docs,
    doc: (p) => ref(p),
    async runTransaction(fn) {
      const writes = [];
      const tx = { get: async (r) => snap(r), set: (r, data) => writes.push([r, data]) };
      const result = await fn(tx);
      for (const [r, data] of writes) docs.set(r.path, copy(data));
      return result;
    },
  };
}

// ---- Field checks -----------------------------------------------------------

test('an achievement name may not carry an em dash or run too long', () => {
  const dash = Achievements.checkFieldEdit('achievement', 'streak_7', 'name', 'A Week' + EM_DASH + ' Done');
  assert.strictEqual(dash.ok, false);
  assert.match(dash.errors.join(' '), /em dash/);
  const long = Achievements.checkFieldEdit('achievement', 'streak_7', 'name', 'x'.repeat(Achievements.MAX_NAME_LENGTH + 1));
  assert.strictEqual(long.ok, false);
});

test('a description has its own, longer limit than a name', () => {
  const justOver = 'x'.repeat(Achievements.MAX_NAME_LENGTH + 20);
  assert.strictEqual(Achievements.checkFieldEdit('achievement', 'streak_7', 'name', justOver).ok, false);
  assert.strictEqual(Achievements.checkFieldEdit('achievement', 'streak_7', 'description', justOver).ok, true);
});

test('an unknown achievement or field is refused', () => {
  assert.strictEqual(Achievements.checkFieldEdit('achievement', 'not_real', 'name', 'X').ok, false);
  assert.strictEqual(Achievements.checkFieldEdit('achievement', 'streak_7', 'title', 'X').ok, false, 'title is a family field');
  assert.strictEqual(Achievements.checkFieldEdit('family', 'streak', 'name', 'X').ok, false, 'name is an achievement field');
});

test('the built-in text again is recognised as no edit, whatever the spacing', () => {
  const builtIn = ACHIEVEMENTS_BY_ID.get('streak_7').name;
  const check = Achievements.checkFieldEdit('achievement', 'streak_7', 'name', '  ' + builtIn + '\n');
  assert.strictEqual(check.sameAsBuiltIn, true);
});

test('house style warns on the Arabic side without blocking the save', () => {
  const check = Achievements.checkFieldEdit('achievement', 'streak_7', 'nameAr', 'إلى الحين لسّه ما خلص');
  assert.strictEqual(check.ok, true);
  assert.match(check.warnings.join(' '), /إلى الآن/);
});

// ---- Saving, reverting, and the whole-document replace ----------------------

test('saving a field, then reverting it, leaves the document exactly as before', async () => {
  const db = fakeDb();
  const saved = await Achievements.saveField(db, FieldValue, {
    kind: 'achievement', id: 'streak_7', field: 'name', rawText: 'One Full Week',
  });
  assert.strictEqual(saved.ok, true);
  assert.strictEqual(saved.changed, true);

  let live = Achievements.shapeLive(db.docs.get(Achievements.LIVE_DOC));
  assert.strictEqual(live.achievements.streak_7.name, 'One Full Week');
  assert.strictEqual(live.version, 1);

  const reverted = await Achievements.saveField(db, FieldValue, {
    kind: 'achievement', id: 'streak_7', field: 'name', rawText: '',
  });
  assert.strictEqual(reverted.changed, true);
  live = Achievements.shapeLive(db.docs.get(Achievements.LIVE_DOC));
  assert.strictEqual(live.achievements.streak_7, undefined, 'an empty row is dropped, not kept as {}');
  assert.strictEqual(live.version, 2);
});

test('saving one field never disturbs another field already edited', async () => {
  const db = fakeDb();
  await Achievements.saveField(db, FieldValue, { kind: 'achievement', id: 'streak_7', field: 'name', rawText: 'One Full Week' });
  await Achievements.saveField(db, FieldValue, { kind: 'achievement', id: 'streak_7', field: 'nameAr', rawText: 'أسبوع واحد كامل' });
  const live = Achievements.shapeLive(db.docs.get(Achievements.LIVE_DOC));
  assert.strictEqual(live.achievements.streak_7.name, 'One Full Week');
  assert.strictEqual(live.achievements.streak_7.nameAr, 'أسبوع واحد كامل');
});

test('saving a family title does not touch achievement fields, and vice versa', async () => {
  const db = fakeDb();
  await Achievements.saveField(db, FieldValue, { kind: 'family', id: 'streak', field: 'title', rawText: 'No Breaks' });
  await Achievements.saveField(db, FieldValue, { kind: 'achievement', id: 'streak_7', field: 'name', rawText: 'One Full Week' });
  const live = Achievements.shapeLive(db.docs.get(Achievements.LIVE_DOC));
  assert.strictEqual(live.families.streak.title, 'No Breaks');
  assert.strictEqual(live.achievements.streak_7.name, 'One Full Week');
});

test('saving text identical to the built-in text is treated as no edit at all', async () => {
  const db = fakeDb();
  const builtIn = ACHIEVEMENTS_BY_ID.get('streak_7').name;
  const result = await Achievements.saveField(db, FieldValue, {
    kind: 'achievement', id: 'streak_7', field: 'name', rawText: builtIn,
  });
  assert.strictEqual(result.changed, false, 'nothing to write: it already reads as the built-in text');
  assert.strictEqual(db.docs.has(Achievements.LIVE_DOC), false);
});

test('an invalid edit throws before any write happens', async () => {
  const db = fakeDb();
  await assert.rejects(
    () => Achievements.saveField(db, FieldValue, { kind: 'achievement', id: 'streak_7', field: 'name', rawText: 'x'.repeat(999) }),
    Achievements.AchievementsInputError,
  );
  assert.strictEqual(db.docs.has(Achievements.LIVE_DOC), false);
});

// ---- Reading ------------------------------------------------------------

test('readAchievements joins the built-in catalog with whatever is overridden', async () => {
  const db = fakeDb();
  await Achievements.saveField(db, FieldValue, { kind: 'achievement', id: 'streak_7', field: 'name', rawText: 'One Full Week' });
  const data = await Achievements.readAchievements(db);
  assert.strictEqual(data.achievements.length, ACHIEVEMENTS_BY_ID.size);
  const row = data.achievements.find((a) => a.id === 'streak_7');
  assert.strictEqual(row.overrides.name, 'One Full Week');
  assert.strictEqual(row.name, ACHIEVEMENTS_BY_ID.get('streak_7').name, 'the built-in text is still there beside it');
  const untouched = data.achievements.find((a) => a.id === 'streak_30');
  assert.deepStrictEqual(untouched.overrides, {});
});

// ---- The page itself ------------------------------------------------------

test('the page renders and references its own script, not the Wording one', () => {
  const html = renderAchievementsPage({ projectId: 'grow-daily-test' });
  assert.match(html, /<title>Achievements/);
  assert.match(html, /\/achievements\/app\.js/);
  assert.doesNotMatch(html, /\/wording\/app\.js/);
});
