'use strict';

/**
 * The closet section of the Achievements page: what a field edit is
 * checked against, what a save does to the document every app reads its
 * character/accessory text from. Same fake-Firestore shape as
 * achievements.test.js and for the same reason.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const Cosmetics = require('../lib/cosmetics_admin');
const { CHARACTERS_BY_ID, ACCESSORIES_BY_ID, CATEGORIES_BY_ID, PRESTIGE_TIERS_BY_ID } = require('../lib/cosmetics_catalog');

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

test('a character only offers name fields, never a description', () => {
  assert.strictEqual(Cosmetics.checkFieldEdit('character', 'male_ghutra_blue', 'name', 'X').ok, true);
  assert.strictEqual(Cosmetics.checkFieldEdit('character', 'male_ghutra_blue', 'description', 'X').ok, false);
});

test('a category only offers label fields', () => {
  assert.strictEqual(Cosmetics.checkFieldEdit('category', 'misbah', 'label', 'X').ok, true);
  assert.strictEqual(Cosmetics.checkFieldEdit('category', 'misbah', 'name', 'X').ok, false);
});

test('a prestige rank only offers title fields', () => {
  assert.strictEqual(Cosmetics.checkFieldEdit('prestige', 'resolute', 'title', 'X').ok, true);
  assert.strictEqual(Cosmetics.checkFieldEdit('prestige', 'resolute', 'name', 'X').ok, false);
});

test('the level-15 rank added 2026-09-21 is in the catalog', () => {
  const tier = PRESTIGE_TIERS_BY_ID.get('resolute');
  assert.ok(tier, 'resolute should exist');
  assert.strictEqual(tier.minLevel, 15);
});

test('an accessory offers both name and description fields', () => {
  assert.strictEqual(Cosmetics.checkFieldEdit('accessory', 'misbah_amber', 'name', 'X').ok, true);
  assert.strictEqual(Cosmetics.checkFieldEdit('accessory', 'misbah_amber', 'description', 'X').ok, true);
});

test('an unknown id in a real kind is refused, not silently accepted', () => {
  assert.strictEqual(Cosmetics.checkFieldEdit('character', 'not_real', 'name', 'X').ok, false);
  assert.strictEqual(Cosmetics.checkFieldEdit('accessory', 'not_real', 'name', 'X').ok, false);
});

test('an em dash is refused in any kind', () => {
  const check = Cosmetics.checkFieldEdit('character', 'male_ghutra_blue', 'name', 'Blue' + EM_DASH + 'Ghutra');
  assert.strictEqual(check.ok, false);
  assert.match(check.errors.join(' '), /em dash/);
});

test('saving, then reverting, leaves the document exactly as before', async () => {
  const db = fakeDb();
  const saved = await Cosmetics.saveField(db, FieldValue, {
    kind: 'character', id: 'male_ghutra_blue', field: 'name', rawText: 'The Blue Ghutra',
  });
  assert.strictEqual(saved.changed, true);
  let live = Cosmetics.shapeLive(db.docs.get(Cosmetics.LIVE_DOC));
  assert.strictEqual(live.characters.male_ghutra_blue.name, 'The Blue Ghutra');

  const reverted = await Cosmetics.saveField(db, FieldValue, {
    kind: 'character', id: 'male_ghutra_blue', field: 'name', rawText: '',
  });
  assert.strictEqual(reverted.changed, true);
  live = Cosmetics.shapeLive(db.docs.get(Cosmetics.LIVE_DOC));
  assert.strictEqual(live.characters.male_ghutra_blue, undefined);
});

test('characters, accessories and categories never share a table', async () => {
  const db = fakeDb();
  await Cosmetics.saveField(db, FieldValue, { kind: 'character', id: 'male_ghutra_blue', field: 'name', rawText: 'X' });
  await Cosmetics.saveField(db, FieldValue, { kind: 'accessory', id: 'misbah_amber', field: 'name', rawText: 'Y' });
  await Cosmetics.saveField(db, FieldValue, { kind: 'category', id: 'misbah', field: 'label', rawText: 'Z' });
  const live = Cosmetics.shapeLive(db.docs.get(Cosmetics.LIVE_DOC));
  assert.strictEqual(live.characters.male_ghutra_blue.name, 'X');
  assert.strictEqual(live.accessories.misbah_amber.name, 'Y');
  assert.strictEqual(live.categories.misbah.label, 'Z');
  assert.strictEqual(live.characters.misbah, undefined);
});

test('readCosmetics joins the built-in catalog with whatever is overridden', async () => {
  const db = fakeDb();
  await Cosmetics.saveField(db, FieldValue, { kind: 'accessory', id: 'misbah_amber', field: 'description', rawText: 'A shinier one' });
  const data = await Cosmetics.readCosmetics(db);
  assert.strictEqual(data.characters.length, CHARACTERS_BY_ID.size);
  assert.strictEqual(data.accessories.length, ACCESSORIES_BY_ID.size);
  assert.strictEqual(data.categories.length, CATEGORIES_BY_ID.size);
  assert.strictEqual(data.prestige.length, PRESTIGE_TIERS_BY_ID.size);
  const row = data.accessories.find((a) => a.id === 'misbah_amber');
  assert.strictEqual(row.overrides.description, 'A shinier one');
  assert.strictEqual(row.description, ACCESSORIES_BY_ID.get('misbah_amber').description);
});

test('a prestige title edit round-trips through save and revert', async () => {
  const db = fakeDb();
  const builtIn = PRESTIGE_TIERS_BY_ID.get('resolute').title;
  const saved = await Cosmetics.saveField(db, FieldValue, {
    kind: 'prestige', id: 'resolute', field: 'title', rawText: 'Committed',
  });
  assert.strictEqual(saved.changed, true);
  let data = await Cosmetics.readCosmetics(db);
  assert.strictEqual(data.prestige.find((t) => t.id === 'resolute').overrides.title, 'Committed');

  const reverted = await Cosmetics.saveField(db, FieldValue, {
    kind: 'prestige', id: 'resolute', field: 'title', rawText: builtIn,
  });
  assert.strictEqual(reverted.changed, true);
  data = await Cosmetics.readCosmetics(db);
  assert.deepStrictEqual(data.prestige.find((t) => t.id === 'resolute').overrides, {});
});

test('saving text identical to the built-in text is treated as no edit at all', async () => {
  const db = fakeDb();
  const builtIn = CHARACTERS_BY_ID.get('male_ghutra_blue').name;
  const result = await Cosmetics.saveField(db, FieldValue, {
    kind: 'character', id: 'male_ghutra_blue', field: 'name', rawText: builtIn,
  });
  assert.strictEqual(result.changed, false);
  assert.strictEqual(db.docs.has(Cosmetics.LIVE_DOC), false);
});

test('an invalid edit throws before any write happens', async () => {
  const db = fakeDb();
  await assert.rejects(
    () => Cosmetics.saveField(db, FieldValue, { kind: 'character', id: 'male_ghutra_blue', field: 'name', rawText: 'x'.repeat(999) }),
    Cosmetics.CosmeticsInputError,
  );
  assert.strictEqual(db.docs.has(Cosmetics.LIVE_DOC), false);
});
