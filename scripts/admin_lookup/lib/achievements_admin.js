'use strict';

/**
 * The server side of the Achievements page: the one writer of the document
 * every app lays its achievement text over (see
 * lib/features/achievements/models/achievement_overrides.dart).
 *
 * Much smaller than lib/wording.js for the same reason
 * achievement_overrides.dart is smaller than wording_edits.dart: 24
 * achievements and 6 families, no `{parts}` to fill, no daily rotation, and
 * (for now) no per-change History/Undo log — the safety net here is that
 * every field always shows its built-in text right beside the edit, so
 * "back to built-in" is always one click away with no risk of undoing the
 * wrong thing.
 *
 * Writes: achievement_overrides/live, ALWAYS by replacing the whole
 * document inside a transaction, never merged. The same lesson wording.js's
 * own doc comment states: a merge only ever adds or changes keys, so
 * removing an edit by writing the map without it is silently a no-op on the
 * server. Read, change the copy, write it all back is what makes "back to
 * built-in" actually take the edit away.
 */

const Rules = require('../wording/rules');
const { ACHIEVEMENTS_BY_ID, FAMILIES_BY_ID } = require('./achievements_catalog');

const LIVE_DOC = 'achievement_overrides/live';

/** Longest name/title accepted. The longest built-in one is under 30. */
const MAX_NAME_LENGTH = 80;
/** Longest description accepted. The longest built-in one is under 45. */
const MAX_DESCRIPTION_LENGTH = 160;

const NAME_FIELDS = new Set(['name', 'nameAr']);
const DESCRIPTION_FIELDS = new Set(['description', 'descriptionAr']);
const TITLE_FIELDS = new Set(['title', 'titleAr']);

/** A request the page should show as a message, not as a server fault. */
class AchievementsInputError extends Error {
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

/** achievement_overrides/live's data, in the one shape the rest of this file uses. */
function shapeLive(data) {
  return {
    achievements: plainFieldMap(data && data.achievements),
    families: plainFieldMap(data && data.families),
    version: data && Number.isInteger(data.version) ? data.version : 0,
    updatedAt: isoOf(data && data.updatedAt),
  };
}

function liveDocument(live, FieldValue) {
  return {
    achievements: live.achievements,
    families: live.families,
    version: live.version,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * The built-in catalog joined with whatever is currently overridden, one
 * row per achievement (each carrying its family) and one per family. This
 * is everything the page needs to render the list and know, per field,
 * whether it is edited.
 */
function currentCatalog(live) {
  const families = Array.from(FAMILIES_BY_ID.values()).map((f) => ({
    ...f,
    overrides: live.families[f.id] || {},
  }));
  const achievements = Array.from(ACHIEVEMENTS_BY_ID.values()).map((a) => ({
    ...a,
    overrides: live.achievements[a.id] || {},
  }));
  return { families, achievements };
}

async function readAchievements(db) {
  const snap = await db.doc(LIVE_DOC).get();
  const live = shapeLive(snap.exists ? snap.data() : null);
  return { live, ...currentCatalog(live) };
}

function builtInFor(kind, id, field) {
  const row = kind === 'family' ? FAMILIES_BY_ID.get(id) : ACHIEVEMENTS_BY_ID.get(id);
  return row ? row[field] : undefined;
}

function validFieldFor(kind, field) {
  if (kind === 'family') return TITLE_FIELDS.has(field);
  return NAME_FIELDS.has(field) || DESCRIPTION_FIELDS.has(field);
}

function maxLengthFor(field) {
  return NAME_FIELDS.has(field) || TITLE_FIELDS.has(field) ? MAX_NAME_LENGTH : MAX_DESCRIPTION_LENGTH;
}

/**
 * Checks one field's new text against the same house-style rules Wording
 * uses (no em dash, the Arabic-only style reminders), sized for a name or a
 * short description instead of a whole sentence.
 *
 * Returns { ok, text, sameAsBuiltIn, errors, warnings }. [text] is what
 * would be stored: null means "back to built-in" (an empty edit, or one
 * that matches the built-in text exactly, which is treated as no edit at
 * all for the same reason a matching wording edit is never stored).
 */
function checkFieldEdit(kind, id, field, rawText) {
  const errors = [];
  const warnings = [];
  if (!validFieldFor(kind, field)) {
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
  const isArabicField = field.endsWith('Ar');
  if (isArabicField) {
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

/**
 * Saves (or, with an empty/built-in [rawText], reverts) one field of one
 * achievement or family, replacing the whole live document in a
 * transaction — see this file's own doc comment for why a merge cannot be
 * used here.
 */
async function saveField(db, FieldValue, { kind, id, field, rawText }) {
  if (kind !== 'achievement' && kind !== 'family') {
    throw new AchievementsInputError('Unknown kind: ' + kind);
  }
  const check = checkFieldEdit(kind, id, field, rawText);
  if (!check.ok) throw new AchievementsInputError(check.errors.join(' '));

  const liveRef = db.doc(LIVE_DOC);
  const result = await db.runTransaction(async (tx) => {
    const liveSnap = await tx.get(liveRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const table = kind === 'family' ? live.families : live.achievements;
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
  AchievementsInputError,
  shapeLive,
  currentCatalog,
  readAchievements,
  checkFieldEdit,
  saveField,
};
