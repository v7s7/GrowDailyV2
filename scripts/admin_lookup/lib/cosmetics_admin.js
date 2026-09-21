'use strict';

/**
 * The server side of the Characters & Items section of the Achievements
 * page: the one writer of the document every app lays its closet text over
 * (see lib/features/character/models/cosmetic_overrides.dart).
 *
 * Same shape as achievements_admin.js — replace-the-whole-document-in-a-
 * transaction, no History/Undo log, every field shows its built-in text
 * beside it instead — sized for three small catalogs instead of one.
 */

const Rules = require('../wording/rules');
const { CHARACTERS_BY_ID, ACCESSORIES_BY_ID, CATEGORIES_BY_ID, PRESTIGE_TIERS_BY_ID } = require('./cosmetics_catalog');

const LIVE_DOC = 'cosmetic_overrides/live';

const MAX_NAME_LENGTH = 80;
const MAX_DESCRIPTION_LENGTH = 160;

const NAME_FIELDS = new Set(['name', 'nameAr']);
const DESCRIPTION_FIELDS = new Set(['description', 'descriptionAr']);
const LABEL_FIELDS = new Set(['label', 'labelAr']);
const TITLE_FIELDS = new Set(['title', 'titleAr']);

class CosmeticsInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function isoOf(value) {
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

function plainFieldMap(map) {
  const out = {};
  if (map && typeof map === 'object') {
    for (const [id, fields] of Object.entries(map)) {
      if (!fields || typeof fields !== 'object') continue;
      const row = {};
      for (const [key, value] of Object.entries(fields)) {
        if (typeof value === 'string' && value.trim()) row[key] = value;
      }
      if (Object.keys(row).length) out[id] = row;
    }
  }
  return out;
}

function shapeLive(data) {
  return {
    characters: plainFieldMap(data && data.characters),
    accessories: plainFieldMap(data && data.accessories),
    categories: plainFieldMap(data && data.categories),
    prestige: plainFieldMap(data && data.prestige),
    version: data && Number.isInteger(data.version) ? data.version : 0,
    updatedAt: isoOf(data && data.updatedAt),
  };
}

function liveDocument(live, FieldValue) {
  return {
    characters: live.characters,
    accessories: live.accessories,
    categories: live.categories,
    prestige: live.prestige,
    version: live.version,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

const TABLE_FOR = { character: 'characters', accessory: 'accessories', category: 'categories', prestige: 'prestige' };
const CATALOG_FOR = { character: CHARACTERS_BY_ID, accessory: ACCESSORIES_BY_ID, category: CATEGORIES_BY_ID, prestige: PRESTIGE_TIERS_BY_ID };

function currentCatalog(live) {
  const row = (kind, base) => ({ ...base, overrides: live[TABLE_FOR[kind]][base.id] || {} });
  return {
    characters: Array.from(CHARACTERS_BY_ID.values()).map((c) => row('character', c)),
    accessories: Array.from(ACCESSORIES_BY_ID.values()).map((a) => row('accessory', a)),
    categories: Array.from(CATEGORIES_BY_ID.values()).map((c) => row('category', c)),
    prestige: Array.from(PRESTIGE_TIERS_BY_ID.values()).map((t) => row('prestige', t)),
  };
}

async function readCosmetics(db) {
  const snap = await db.doc(LIVE_DOC).get();
  const live = shapeLive(snap.exists ? snap.data() : null);
  return { live, ...currentCatalog(live) };
}

function builtInFor(kind, id, field) {
  const row = CATALOG_FOR[kind] && CATALOG_FOR[kind].get(id);
  return row ? row[field] : undefined;
}

function validFieldFor(kind, field) {
  if (kind === 'character') return NAME_FIELDS.has(field);
  if (kind === 'category') return LABEL_FIELDS.has(field);
  if (kind === 'prestige') return TITLE_FIELDS.has(field);
  if (kind === 'accessory') return NAME_FIELDS.has(field) || DESCRIPTION_FIELDS.has(field);
  return false;
}

function maxLengthFor(field) {
  return DESCRIPTION_FIELDS.has(field) ? MAX_DESCRIPTION_LENGTH : MAX_NAME_LENGTH;
}

function checkFieldEdit(kind, id, field, rawText) {
  const errors = [];
  const warnings = [];
  if (!TABLE_FOR[kind] || !validFieldFor(kind, field)) {
    return { ok: false, text: null, sameAsBuiltIn: false, errors: ['Unknown field for this kind.'], warnings };
  }
  const builtIn = builtInFor(kind, id, field);
  if (builtIn === undefined) {
    return { ok: false, text: null, sameAsBuiltIn: false, errors: ['No such ' + kind + ' in the catalog.'], warnings };
  }
  const text = Rules.normalizeText(rawText);
  const max = maxLengthFor(field);
  if (text.includes(String.fromCharCode(0x2014))) {
    errors.push('Has an em dash. Use a comma, a colon or a full stop.');
  }
  if (text.length > max) {
    errors.push('Too long: ' + text.length + ' characters, the limit is ' + max + '.');
  }
  if (field.endsWith('Ar')) {
    for (const rule of Rules.ARABIC_STYLE || []) {
      if (rule.test.test(text)) warnings.push(rule.say);
    }
  }
  return {
    ok: errors.length === 0,
    text: text ? text : null,
    sameAsBuiltIn: text === Rules.normalizeText(builtIn || ''),
    errors,
    warnings,
  };
}

async function saveField(db, FieldValue, { kind, id, field, rawText }) {
  if (!TABLE_FOR[kind]) throw new CosmeticsInputError('Unknown kind: ' + kind);
  const check = checkFieldEdit(kind, id, field, rawText);
  if (!check.ok) throw new CosmeticsInputError(check.errors.join(' '));

  const liveRef = db.doc(LIVE_DOC);
  const result = await db.runTransaction(async (tx) => {
    const liveSnap = await tx.get(liveRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const table = live[TABLE_FOR[kind]];
    const before = table[id] && Object.prototype.hasOwnProperty.call(table[id], field)
      ? table[id][field]
      : null;
    const after = check.sameAsBuiltIn ? null : check.text;
    if (before === after) return { changed: false, before, after };

    if (after === null) {
      if (table[id]) {
        delete table[id][field];
        if (Object.keys(table[id]).length === 0) delete table[id];
      }
    } else {
      table[id] = { ...(table[id] || {}), [field]: after };
    }
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    return { changed: true, before, after };
  });

  return { ok: true, warnings: check.warnings, ...result };
}

module.exports = {
  LIVE_DOC,
  MAX_NAME_LENGTH,
  MAX_DESCRIPTION_LENGTH,
  CosmeticsInputError,
  shapeLive,
  currentCatalog,
  readCosmetics,
  checkFieldEdit,
  saveField,
};
