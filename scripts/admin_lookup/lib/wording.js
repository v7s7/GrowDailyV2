'use strict';

/**
 * The server side of the Wording page: the one place in this tool that
 * WRITES, and the only writer of the document every app reads its wording
 * edits from.
 *
 * Everything else in this tool reads accounts and never changes them. This
 * page changes no account either. It writes three things, all of them about
 * wording and nothing about any person:
 *
 *   wording/live          what every app lays over its built-in text (see
 *                         lib/core/l10n/wording_edits.dart). Public read,
 *                         no client write (firestore.rules), so only the
 *                         Admin SDK here can change it.
 *   wording_admin/state   the built-in text each live edit replaced, so the
 *                         page can say when the code has moved on under an
 *                         edit. Admin only.
 *   wording_log/{id}      one row per change, for History and Undo. Admin
 *                         only.
 *
 * Every save REPLACES wording/live whole, inside a transaction, rather than
 * merging into it. A merge only ever adds or changes keys: removing an edit
 * by writing the map without it is silently a no-op on the server, which is
 * exactly the trap that once cost real data in this project. Reading the
 * document, changing the copy and writing all of it back is what makes
 * "back to built-in" actually take the edit away.
 *
 * The rules for what may be saved live in ../wording/rules.js, shared with
 * the page itself.
 *
 * Since 2026-09-26 the same document also holds the FAQ's edits (`faq`) and
 * the paywall benefit list's (`benefits`), saved from the FAQ and Premium
 * pages (lib/content_pages.js); ../wording/content_rules.js has their rules
 * and lib/core/l10n/content_edits.dart says why they are shaped as they
 * are. Because every save here writes the WHOLE document, each one carries
 * those two, and any field this file does not know yet, through unchanged:
 * a string saved from an older copy of this file would otherwise have
 * wiped them.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');

const Rules = require('../wording/rules');
const Content = require('../wording/content_rules');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const CATALOG_PATH = path.join(__dirname, '..', 'wording', 'catalog.json');
const GENERATOR_DIR = path.join(REPO_ROOT, 'docs', 'wording', 'generator');

const LIVE_DOC = 'wording/live';
const ADMIN_DOC = 'wording_admin/state';
const LOG_COLLECTION = 'wording_log';
const LOG_LIMIT = 60;

// Why a FAQ or Premium save is refused because the page is out of date.
// The page keeps what was typed and offers to reload.
const RELOAD = 'This page is out of date. Copy anything you typed, then reload it.';
const STALE_BUILT_IN_FAQ = 'The app\'s own FAQ changed in the code since this page was opened, so saving it now could store old words. Copy anything you typed, reload the page, and make the change again.';
const STALE_FAQ = 'The FAQ was saved from another tab, or undone, since this page was opened. Copy anything you typed, reload the page to see the latest, and make the change again.';
const STALE_BUILT_IN_BENEFITS = 'The app\'s own benefit list changed in the code since this page was opened, so saving it now could hide a new row. Copy anything you typed, reload the page, and make the change again.';
const STALE_BENEFITS = 'The benefit list was saved from another tab, or undone, since this page was opened. Copy anything you typed, reload the page to see the latest, and make the change again.';

/** A request the page should show as a message, not as a server fault. */
class WordingInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

// ---- The catalog ----------------------------------------------------------

function readCatalog(file = CATALOG_PATH) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * The catalog shape this tool reads: 2 added the FAQ and the paywall's
 * benefit list (and their two sources). An older catalog is rebuilt like
 * one built from older sources.
 */
const CATALOG_FORMAT = 2;

/**
 * The sources that changed since [catalog] was built, by path. Empty when it
 * is current. The fingerprints are the generator's own (FNV-1a of the file),
 * so any edit to app_strings.dart, daily_quotes.dart, the FAQ or the benefit
 * list, even a comment, is enough to rebuild. A source the generator found
 * missing is recorded as null, and still missing reads as unchanged.
 */
function staleSources(catalog, root = REPO_ROOT) {
  if (!catalog || !catalog.sources) return ['(no list built yet)'];
  if (!(catalog.format >= CATALOG_FORMAT)) return ['(a list from before the FAQ and Premium pages)'];
  const out = [];
  for (const source of Object.values(catalog.sources)) {
    let now = null;
    try {
      now = Rules.fnv1a(fs.readFileSync(path.join(root, source.path)));
    } catch {
      now = null;
    }
    if (now !== source.fnv1a) out.push(source.path);
  }
  return out;
}

let rebuilding = null;

/** Reruns the generator for the catalog alone. One run at a time. */
function rebuildCatalog() {
  if (!rebuilding) {
    rebuilding = new Promise((resolve, reject) => {
      execFile(
        'dart',
        ['run', 'bin/gen_wording_edits.dart', '--catalog-only'],
        { cwd: GENERATOR_DIR, timeout: 180000 },
        (err, stdout, stderr) => {
          if (err) {
            const said = String(stderr || err.message).trim().split('\n');
            reject(new Error(said.slice(-3).join(' ')));
          } else {
            resolve(String(stdout).trim());
          }
        },
      );
    }).finally(() => {
      rebuilding = null;
    });
  }
  return rebuilding;
}

/**
 * The catalog, rebuilt first when the app's wording has changed since it was
 * built. Never throws: a rebuild that fails returns the last catalog with a
 * note saying so, because an old list is still far more useful than none.
 */
async function currentCatalog() {
  let catalog = readCatalog();
  const stale = staleSources(catalog);
  if (stale.length === 0) return { catalog, note: null };
  try {
    await rebuildCatalog();
    catalog = readCatalog();
    return {
      catalog,
      note: catalog
        ? null
        : 'The list of strings could not be read after rebuilding it.',
    };
  } catch (e) {
    return {
      catalog,
      note:
        'The app\'s wording changed (' + stale.join(', ') + ') and the list ' +
        'could not be rebuilt: ' + e.message + '. Run: cd docs/wording/generator ' +
        '&& dart run bin/gen_wording_edits.dart --catalog-only',
    };
  }
}

// ---- Document shapes ------------------------------------------------------

function isoOf(value) {
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

function plainStrings(map) {
  const out = {};
  if (map && typeof map === 'object') {
    for (const [key, value] of Object.entries(map)) {
      if (typeof value === 'string') out[key] = value;
    }
  }
  return out;
}

function plainQuotes(list) {
  if (!Array.isArray(list)) return null;
  return list.map((q) => ({ ar: String((q && q.ar) || ''), en: String((q && q.en) || '') }));
}

const LIVE_FIELDS = new Set(['strings', 'quotes', 'faq', 'benefits', 'version', 'updatedAt']);

/**
 * wording/live's data in the one shape the rest of this file uses. `faq`
 * and `benefits` are read the way the app reads them and kept in the
 * document's own sparse form; `extra` is every field this file does not
 * know, written back as it came.
 */
function shapeLive(data) {
  const strings = (data && data.strings) || {};
  const extra = {};
  if (data && typeof data === 'object') {
    for (const [key, value] of Object.entries(data)) {
      if (!LIVE_FIELDS.has(key)) extra[key] = value;
    }
  }
  return {
    strings: { ar: plainStrings(strings.ar), en: plainStrings(strings.en) },
    quotes: plainQuotes(data && data.quotes),
    faq: Content.faqDocument(Content.parseFaqEdits(data && data.faq)),
    benefits: Content.benefitsDocument(Content.parseBenefitEdits(data && data.benefits)),
    // The two lists exactly as stored. A save that does not change a list
    // writes this back rather than the reading above, so a field a later
    // version of this tool adds inside a list survives an unrelated save.
    // A save that changes a list sets it to undefined (liveDocument).
    faqRaw: data && data.faq !== undefined ? data.faq : undefined,
    benefitsRaw: data && data.benefits !== undefined ? data.benefits : undefined,
    version: data && Number.isInteger(data.version) ? data.version : 0,
    updatedAt: isoOf(data && data.updatedAt),
    extra,
  };
}

/**
 * The built-in text each stored FAQ field replaced, by question id and
 * field, and each stored group heading, by group id and language. Only
 * strings are kept.
 */
function plainFaqBases(raw) {
  const out = { items: {}, groups: {} };
  for (const part of ['items', 'groups']) {
    const table = raw && raw[part];
    if (!table || typeof table !== 'object') continue;
    for (const [key, fields] of Object.entries(table)) {
      if (!fields || typeof fields !== 'object') continue;
      const row = plainStrings(fields);
      if (Object.keys(row).length) out[part][key] = row;
    }
  }
  return out;
}

function shapeAdmin(data) {
  const bases = (data && data.bases) || {};
  return {
    bases: { ar: plainStrings(bases.ar), en: plainStrings(bases.en) },
    quotesBuiltInFnv: (data && data.quotesBuiltInFnv) || null,
    faqBases: plainFaqBases(data && data.faqBases),
  };
}

function shapeLog(id, data) {
  return {
    id,
    at: isoOf(data.at),
    kind: data.kind,
    key: data.key || null,
    lang: data.lang || null,
    before: data.before === undefined ? null : data.before,
    after: data.after === undefined ? null : data.after,
    builtIn: data.builtIn === undefined ? null : data.builtIn,
    basesBefore: data.basesBefore || null,
    basesAfter: data.basesAfter || null,
    undoOf: data.undoOf || null,
    undoneBy: data.undoneBy || null,
  };
}

/** The whole live document, as a save writes it. */
function liveDocument(live, FieldValue) {
  const doc = Object.assign({}, live.extra || {}, {
    strings: live.strings,
    version: live.version,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (live.quotes) doc.quotes = live.quotes;
  const faq = live.faqRaw !== undefined ? live.faqRaw : live.faq;
  if (faq !== null && faq !== undefined) doc.faq = faq;
  const benefits = live.benefitsRaw !== undefined ? live.benefitsRaw : live.benefits;
  if (benefits !== null && benefits !== undefined) doc.benefits = benefits;
  return doc;
}

function adminDocument(admin, FieldValue) {
  const doc = {
    bases: admin.bases,
    quotesBuiltInFnv: admin.quotesBuiltInFnv,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const faqBases = admin.faqBases || { items: {}, groups: {} };
  if (Object.keys(faqBases.items).length || Object.keys(faqBases.groups).length) doc.faqBases = faqBases;
  return doc;
}

function sameQuotes(a, b) {
  return JSON.stringify(plainQuotes(a)) === JSON.stringify(plainQuotes(b));
}

// ---- Reading --------------------------------------------------------------

/** Everything the page shows that lives in Firestore. */
async function readWording(db) {
  const [liveSnap, adminSnap, logSnap] = await Promise.all([
    db.doc(LIVE_DOC).get(),
    db.doc(ADMIN_DOC).get(),
    db.collection(LOG_COLLECTION).orderBy('at', 'desc').limit(LOG_LIMIT).get(),
  ]);
  return {
    live: shapeLive(liveSnap.exists ? liveSnap.data() : null),
    admin: shapeAdmin(adminSnap.exists ? adminSnap.data() : null),
    log: logSnap.docs.map((d) => shapeLog(d.id, d.data())),
  };
}

// ---- Saving ---------------------------------------------------------------

/**
 * Saves one string's Arabic and English edits together, in one transaction.
 *
 * [changes] maps 'ar' and 'en' to the new text, or to null for "back to the
 * built-in text"; a language that is not named is left as it is. Text equal
 * to the built-in text is also "back to built-in": storing a copy of it
 * would only freeze the string against the next change in the app's code.
 *
 * Returns { ok, errors, warnings, changed }, errors and warnings by language.
 * Nothing is written unless every named language passes.
 */
async function saveStringEdits(db, FieldValue, { entry, changes }) {
  if (!entry) throw new WordingInputError('No such string in the app.');
  if (!entry.editable) throw new WordingInputError(entry.why || 'This string cannot be edited here.');
  if (!changes || typeof changes !== 'object') throw new WordingInputError('Nothing to save.');

  const next = {};
  const errors = {};
  const warnings = {};
  for (const lang of Object.keys(changes)) {
    if (lang !== 'ar' && lang !== 'en') throw new WordingInputError('Unknown language: ' + lang);
    const value = changes[lang];
    if (value === null) {
      next[lang] = null;
      continue;
    }
    const check = Rules.checkStringEdit(entry, lang, value);
    if (!check.ok) errors[lang] = check.errors;
    if (check.warnings.length) warnings[lang] = check.warnings;
    next[lang] = check.sameAsBuiltIn ? null : check.text;
  }
  if (Object.keys(errors).length) return { ok: false, errors, warnings, changed: 0 };

  const liveRef = db.doc(LIVE_DOC);
  const adminRef = db.doc(ADMIN_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const [liveSnap, adminSnap] = await tx.getAll(liveRef, adminRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const admin = shapeAdmin(adminSnap.exists ? adminSnap.data() : null);
    const done = applyStringChanges(live, admin, entry, next);
    if (done.length === 0) return done;
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    logStringChanges(tx, db, FieldValue, done);
    return done;
  });
  return { ok: true, errors: {}, warnings, changed: changed.length };
}

/**
 * Lays one string's checked changes ([next]: language to text, or to null
 * for "back to built-in") into [live] and [admin], recording the built-in
 * text each edit replaced. Returns what changed, for the log.
 */
function applyStringChanges(live, admin, entry, next) {
  const done = [];
  for (const [lang, text] of Object.entries(next)) {
    const before = Object.prototype.hasOwnProperty.call(live.strings[lang], entry.key)
      ? live.strings[lang][entry.key]
      : null;
    if (before === text) continue;
    const builtIn = lang === 'ar' ? entry.ar : entry.en;
    if (text === null) {
      delete live.strings[lang][entry.key];
      delete admin.bases[lang][entry.key];
    } else {
      live.strings[lang][entry.key] = text;
      admin.bases[lang][entry.key] = builtIn;
    }
    done.push({ key: entry.key, lang, before, after: text, builtIn });
  }
  return done;
}

function logStringChanges(tx, db, FieldValue, done) {
  for (const change of done) {
    tx.set(db.collection(LOG_COLLECTION).doc(), {
      at: FieldValue.serverTimestamp(),
      kind: 'string',
      key: change.key,
      lang: change.lang,
      before: change.before,
      after: change.after,
      builtIn: change.builtIn,
      undoOf: null,
    });
  }
}

/**
 * Saves the whole daily rotation, or with [items] null goes back to the
 * app's built-in list. A list identical to the built-in one is saved as
 * "built-in" too, for the same reason as a string: so a later change to the
 * list in the app's code still reaches the Grid.
 */
async function saveQuotes(db, FieldValue, { items, builtIn, builtInFnv }) {
  let next = null;
  let warnings = [];
  if (items !== null) {
    const check = Rules.checkQuotes(items);
    if (!check.ok) return { ok: false, errors: check.errors, warnings: check.warnings, changed: 0 };
    warnings = check.warnings;
    next = sameQuotes(check.items, builtIn) ? null : check.items;
  }

  const liveRef = db.doc(LIVE_DOC);
  const adminRef = db.doc(ADMIN_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const [liveSnap, adminSnap] = await tx.getAll(liveRef, adminRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const admin = shapeAdmin(adminSnap.exists ? adminSnap.data() : null);
    const before = live.quotes;
    if (before === null ? next === null : next !== null && sameQuotes(before, next)) return 0;
    live.quotes = next;
    live.version += 1;
    admin.quotesBuiltInFnv = next ? builtInFnv : null;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    tx.set(db.collection(LOG_COLLECTION).doc(), {
      at: FieldValue.serverTimestamp(),
      kind: 'quotes',
      key: null,
      lang: null,
      before,
      after: next,
      builtIn: null,
      undoOf: null,
    });
    return 1;
  });
  return { ok: true, errors: [], warnings, changed };
}

/**
 * Saves the whole FAQ as the FAQ page shows it. [builtIn] is the catalog's
 * `faq` (the app's own FAQ), [draft] the page's { groups: [...] }; see
 * faqEditsFromDraft in ../wording/content_rules.js for what is stored and
 * what is left to the code. A draft equal to the built-in FAQ saves as
 * "built-in": `faq` leaves the document.
 *
 * [checked] lists fields ("questionId:qAr", "group:groupId:ar") whose
 * built-in text changed in the code after they were edited, and which the
 * page's reader has looked at and kept: their record of what the edit
 * replaced moves to today's built-in text, which clears the page's flag.
 * Any other field that is still edited with the same words keeps its old
 * record, so the flag cannot clear by accident on an unrelated save.
 *
 * Returns { ok, errors, warnings, changed }. Nothing is written unless the
 * whole draft passes.
 */
async function saveFaq(db, FieldValue, { builtIn, draft, checked, base, builtInFingerprint }) {
  if (!builtIn) {
    throw new WordingInputError('The app\'s own FAQ could not be read, so nothing can be saved. See the note at the top of the page.', 500);
  }
  if (builtInFingerprint !== Content.fingerprint(builtIn)) {
    throw new WordingInputError(STALE_BUILT_IN_FAQ, 409);
  }
  if (base === undefined) throw new WordingInputError(RELOAD, 409);
  const expected = Content.faqDocument(Content.parseFaqEdits(base));
  const check = Content.faqEditsFromDraft(builtIn, draft);
  if (!check.ok) return { ok: false, errors: check.errors, warnings: check.warnings, changed: 0 };
  const acknowledged = new Set(Array.isArray(checked) ? checked.map(String) : []);

  const liveRef = db.doc(LIVE_DOC);
  const adminRef = db.doc(ADMIN_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const [liveSnap, adminSnap] = await tx.getAll(liveRef, adminRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const admin = shapeAdmin(adminSnap.exists ? adminSnap.data() : null);
    const before = live.faq;
    if (!Content.same(before, expected)) throw new WordingInputError(STALE_FAQ, 409);
    const after = check.edits;
    const bases = keptFaqBases(before, after, admin.faqBases, check.bases, acknowledged);
    if (Content.same(before, after) && Content.same(admin.faqBases, bases)) return 0;
    const basesBefore = admin.faqBases;
    live.faq = after;
    live.faqRaw = undefined;
    live.version += 1;
    admin.faqBases = bases;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    tx.set(db.collection(LOG_COLLECTION).doc(), {
      at: FieldValue.serverTimestamp(),
      kind: 'faq',
      key: null,
      lang: null,
      before,
      after,
      builtIn: null,
      basesBefore,
      basesAfter: bases,
      undoOf: null,
    });
    return 1;
  });
  return { ok: true, errors: [], warnings: check.warnings, changed };
}

/**
 * The record of what each stored FAQ field replaced, after a save. A field
 * edited before and still carrying the same words keeps its old record (so
 * "changed in code since your edit" survives an unrelated save), unless the
 * page says it was [acknowledged]; every other stored field records today's
 * built-in text ([fresh], from faqEditsFromDraft).
 */
function keptFaqBases(before, after, old, fresh, acknowledged) {
  const out = { items: {}, groups: {} };
  if (!after || !fresh) return out;
  const beforeText = (before && before.text) || {};
  const beforeGroups = (before && before.groups) || {};
  const afterText = after.text || {};
  const afterGroups = after.groups || {};
  for (const [itemId, fields] of Object.entries(fresh.items || {})) {
    for (const [field, base] of Object.entries(fields)) {
      const kept = !acknowledged.has(itemId + ':' + field) &&
        beforeText[itemId] && beforeText[itemId][field] === (afterText[itemId] || {})[field] &&
        old.items[itemId] && typeof old.items[itemId][field] === 'string';
      out.items[itemId] = Object.assign(out.items[itemId] || {}, { [field]: kept ? old.items[itemId][field] : base });
    }
  }
  for (const [groupId, langs] of Object.entries(fresh.groups || {})) {
    for (const [lang, base] of Object.entries(langs)) {
      const kept = !acknowledged.has('group:' + groupId + ':' + lang) &&
        beforeGroups[groupId] && beforeGroups[groupId][lang] === (afterGroups[groupId] || {})[lang] &&
        old.groups[groupId] && typeof old.groups[groupId][lang] === 'string';
      out.groups[groupId] = Object.assign(out.groups[groupId] || {}, { [lang]: kept ? old.groups[groupId][lang] : base });
    }
  }
  return out;
}

/**
 * Saves the Premium page: its strings and its benefit list, together, in
 * one transaction, so the paywall never shows half a save.
 *
 * [strings] maps an S key to { ar?, en? }: the new text, or null for "back
 * to the built-in text", exactly as the Wording page's App text saves one.
 * The page sends only what it changed, worked out against what it loaded,
 * and [stringsBase] says what each of those was when it loaded (the live
 * edit, or null for the built-in text). A string changed elsewhere since
 * (the Wording page, another tab, an Undo) refuses the whole save rather
 * than quietly putting the older text back.
 *
 * [benefits] is the page's list of rows (see benefitEditsFromRows in
 * ../wording/content_rules.js), or undefined when the list was not touched;
 * [benefitsBase] is the list edits the page loaded and [builtInFingerprint]
 * the fingerprint of the app's own list it was built from. Either one out
 * of date refuses the save too.
 *
 * Returns { ok, errors, warnings, changed }. Nothing is written unless
 * everything passes.
 */
async function savePremium(db, FieldValue, { catalog, strings, stringsBase, benefits, benefitsBase, builtInFingerprint }) {
  if (!catalog) throw new WordingInputError('The list of strings is missing.', 500);
  const byKey = new Map(catalog.strings.map((entry) => [entry.key, entry]));
  const errors = [];
  const warnings = [];
  const pageStrings = [];
  for (const [key, changes] of Object.entries(strings || {})) {
    const entry = byKey.get(key);
    if (!entry) {
      errors.push('The app has no string ' + key + '.');
      continue;
    }
    if (!changes || typeof changes !== 'object') continue;
    const next = {};
    const was = {};
    for (const lang of Object.keys(changes)) {
      if (lang !== 'ar' && lang !== 'en') {
        errors.push('Unknown language: ' + lang);
        continue;
      }
      const base = Content.own(Content.own(stringsBase, key), lang);
      if (base === undefined) throw new WordingInputError(RELOAD, 409);
      was[lang] = base;
      if (changes[lang] === null) {
        next[lang] = null;
        continue;
      }
      const check = Rules.checkStringEdit(entry, lang, changes[lang]);
      check.errors.forEach((e) => errors.push(key + ', ' + (lang === 'ar' ? 'Arabic' : 'English') + ': ' + e));
      check.warnings.forEach((w) => warnings.push(key + ', ' + (lang === 'ar' ? 'Arabic' : 'English') + ': ' + w));
      next[lang] = check.sameAsBuiltIn ? null : check.text;
    }
    pageStrings.push({ entry, next, was });
  }
  let list = null;
  let expectedList = null;
  if (benefits !== undefined) {
    if (!catalog.benefits) {
      throw new WordingInputError('The app\'s own benefit list could not be read, so the list cannot be saved. See the note at the top of the page.', 500);
    }
    if (builtInFingerprint !== Content.fingerprint(catalog.benefits)) {
      throw new WordingInputError(STALE_BUILT_IN_BENEFITS, 409);
    }
    if (benefitsBase === undefined) throw new WordingInputError(RELOAD, 409);
    expectedList = Content.benefitsDocument(Content.parseBenefitEdits(benefitsBase));
    list = Content.benefitEditsFromRows(catalog.benefits, benefits);
    errors.push(...list.errors);
    warnings.push(...list.warnings);
  }
  if (errors.length) return { ok: false, errors, warnings, changed: 0 };

  const liveRef = db.doc(LIVE_DOC);
  const adminRef = db.doc(ADMIN_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const [liveSnap, adminSnap] = await tx.getAll(liveRef, adminRef);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const admin = shapeAdmin(adminSnap.exists ? adminSnap.data() : null);
    const moved = [];
    for (const { entry, was } of pageStrings) {
      for (const [lang, base] of Object.entries(was)) {
        const now = Object.prototype.hasOwnProperty.call(live.strings[lang], entry.key) ? live.strings[lang][entry.key] : null;
        if (now !== base) moved.push(entry.key + ' (' + (lang === 'ar' ? 'Arabic' : 'English') + ')');
      }
    }
    if (moved.length) {
      throw new WordingInputError('Changed somewhere else since this page was opened: ' + moved.join(', ') +
        '. Copy anything you typed, reload the page to see the latest, and make the change again.', 409);
    }
    if (list && !Content.same(live.benefits, expectedList)) throw new WordingInputError(STALE_BENEFITS, 409);
    const done = [];
    for (const { entry, next } of pageStrings) done.push(...applyStringChanges(live, admin, entry, next));
    const listBefore = live.benefits;
    const listChanged = list !== null && !Content.same(listBefore, list.edits);
    if (!done.length && !listChanged) return 0;
    if (listChanged) {
      live.benefits = list.edits;
      live.benefitsRaw = undefined;
    }
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    logStringChanges(tx, db, FieldValue, done);
    if (listChanged) {
      tx.set(db.collection(LOG_COLLECTION).doc(), {
        at: FieldValue.serverTimestamp(),
        kind: 'benefits',
        key: null,
        lang: null,
        before: listBefore,
        after: list.edits,
        builtIn: null,
        undoOf: null,
      });
    }
    return done.length + (listChanged ? 1 : 0);
  });
  return { ok: true, errors: [], warnings, changed };
}

/**
 * Puts back what one History row changed. Refused when the same thing has
 * changed again since, so an undo can never silently throw away a later
 * edit: undo the later one first.
 */
async function undoChange(db, FieldValue, { id, catalogByKey }) {
  const logRef = db.collection(LOG_COLLECTION).doc(String(id || ''));
  const liveRef = db.doc(LIVE_DOC);
  const adminRef = db.doc(ADMIN_DOC);
  return db.runTransaction(async (tx) => {
    const [logSnap, liveSnap, adminSnap] = await tx.getAll(logRef, liveRef, adminRef);
    if (!logSnap.exists) throw new WordingInputError('That change is not in History.', 404);
    const row = shapeLog(logSnap.id, logSnap.data());
    if (row.undoneBy) throw new WordingInputError('That change has already been undone.', 409);
    const live = shapeLive(liveSnap.exists ? liveSnap.data() : null);
    const admin = shapeAdmin(adminSnap.exists ? adminSnap.data() : null);

    let current;
    if (row.kind === 'string') {
      const table = live.strings[row.lang] || {};
      current = Object.prototype.hasOwnProperty.call(table, row.key) ? table[row.key] : null;
      if (current !== row.after) {
        throw new WordingInputError('This string has changed again since. Undo the later change first.', 409);
      }
      const entry = catalogByKey.get(row.key);
      if (row.before === null) {
        delete live.strings[row.lang][row.key];
        delete admin.bases[row.lang][row.key];
      } else {
        live.strings[row.lang][row.key] = row.before;
        admin.bases[row.lang][row.key] = entry
          ? (row.lang === 'ar' ? entry.ar : entry.en)
          : (row.builtIn || '');
      }
    } else if (row.kind === 'quotes') {
      current = live.quotes;
      const matches = row.after === null ? current === null : current !== null && sameQuotes(current, row.after);
      if (!matches) {
        throw new WordingInputError('The daily lines have changed again since. Undo the later change first.', 409);
      }
      live.quotes = plainQuotes(row.before);
      if (!live.quotes) admin.quotesBuiltInFnv = null;
    } else if (row.kind === 'faq') {
      current = live.faq;
      if (!Content.same(current, Content.faqDocument(Content.parseFaqEdits(row.after)))) {
        throw new WordingInputError('The FAQ has changed again since. Undo the later change first.', 409);
      }
      live.faq = Content.faqDocument(Content.parseFaqEdits(row.before));
      live.faqRaw = undefined;
      admin.faqBases = plainFaqBases(row.basesBefore);
    } else if (row.kind === 'benefits') {
      current = live.benefits;
      if (!Content.same(current, Content.benefitsDocument(Content.parseBenefitEdits(row.after)))) {
        throw new WordingInputError('The Premium benefit list has changed again since. Undo the later change first.', 409);
      }
      live.benefits = Content.benefitsDocument(Content.parseBenefitEdits(row.before));
      live.benefitsRaw = undefined;
    } else {
      throw new WordingInputError('That History row cannot be undone.');
    }

    live.version += 1;
    const undoRef = db.collection(LOG_COLLECTION).doc();
    const restored = row.kind === 'quotes' ? plainQuotes(row.before)
      : row.kind === 'faq' ? live.faq
        : row.kind === 'benefits' ? live.benefits
          : row.before;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    const undoRow = {
      at: FieldValue.serverTimestamp(),
      kind: row.kind,
      key: row.key,
      lang: row.lang,
      before: current,
      after: restored,
      builtIn: row.builtIn,
      undoOf: row.id,
    };
    if (row.kind === 'faq') {
      undoRow.basesBefore = row.basesAfter;
      undoRow.basesAfter = row.basesBefore;
    }
    tx.set(undoRef, undoRow);
    tx.update(logRef, { undoneBy: undoRef.id });
    return { ok: true };
  });
}

// ---- Around the requests --------------------------------------------------

/**
 * Whether a write request came from this tool's own page.
 *
 * The server only listens on 127.0.0.1, but a web page open in any tab of
 * the same browser can still send requests to 127.0.0.1. Three checks stop
 * that from ever reaching the document every phone reads:
 *   - Host must be this server by name, which defeats DNS rebinding (a
 *     hostile domain re-pointed at 127.0.0.1 still sends its own name);
 *   - Origin, when the browser sends one, must be this server;
 *   - the body must be JSON, which a cross-site form or a no-cors fetch
 *     cannot send without a preflight this server never answers.
 */
function isLocalWrite(headers, port) {
  const hosts = ['127.0.0.1:' + port, 'localhost:' + port];
  const host = String(headers.host || '').toLowerCase();
  if (!hosts.includes(host)) return false;
  const origin = headers.origin;
  if (origin && !hosts.some((h) => origin.toLowerCase() === 'http://' + h)) return false;
  const type = String(headers['content-type'] || '').toLowerCase();
  return type.split(';')[0].trim() === 'application/json';
}

/**
 * Whether a phone can read wording/live right now, asked the way a phone
 * asks: with no credentials at all. 'open' (the rule is deployed; a missing
 * document still answers 404 when reading is allowed), 'closed' (403, the
 * rule is not live yet, so every edit stays invisible), or 'unknown'
 * (offline, or an answer this does not recognise).
 */
async function phonesCanRead(projectId, fetchImpl = globalThis.fetch) {
  if (!projectId || typeof fetchImpl !== 'function') return 'unknown';
  const url = 'https://firestore.googleapis.com/v1/projects/' +
    encodeURIComponent(projectId) + '/databases/(default)/documents/' + LIVE_DOC;
  try {
    const res = await fetchImpl(url, { signal: AbortSignal.timeout(6000) });
    if (res.status === 200 || res.status === 404) return 'open';
    if (res.status === 403) return 'closed';
    return 'unknown';
  } catch {
    return 'unknown';
  }
}

/** Today's date in Bahrain, 'YYYY-MM-DD', the day the Grid's line is picked for. */
function todayKey(now = new Date(), timeZone = 'Asia/Bahrain') {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

module.exports = {
  CATALOG_PATH,
  LIVE_DOC,
  ADMIN_DOC,
  LOG_COLLECTION,
  WordingInputError,
  readCatalog,
  staleSources,
  currentCatalog,
  readWording,
  saveStringEdits,
  saveQuotes,
  saveFaq,
  savePremium,
  undoChange,
  shapeLive,
  liveDocument,
  isLocalWrite,
  phonesCanRead,
  todayKey,
};
