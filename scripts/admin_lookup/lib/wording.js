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
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');

const Rules = require('../wording/rules');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const CATALOG_PATH = path.join(__dirname, '..', 'wording', 'catalog.json');
const GENERATOR_DIR = path.join(REPO_ROOT, 'docs', 'wording', 'generator');

const LIVE_DOC = 'wording/live';
const ADMIN_DOC = 'wording_admin/state';
const LOG_COLLECTION = 'wording_log';
const LOG_LIMIT = 60;

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
 * The sources that changed since [catalog] was built, by path. Empty when it
 * is current. The fingerprints are the generator's own (FNV-1a of the file),
 * so any edit to app_strings.dart or daily_quotes.dart, even a comment, is
 * enough to rebuild.
 */
function staleSources(catalog, root = REPO_ROOT) {
  if (!catalog || !catalog.sources) return ['(no list built yet)'];
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

/** wording/live's data in the one shape the rest of this file uses. */
function shapeLive(data) {
  const strings = (data && data.strings) || {};
  return {
    strings: { ar: plainStrings(strings.ar), en: plainStrings(strings.en) },
    quotes: plainQuotes(data && data.quotes),
    version: data && Number.isInteger(data.version) ? data.version : 0,
    updatedAt: isoOf(data && data.updatedAt),
  };
}

function shapeAdmin(data) {
  const bases = (data && data.bases) || {};
  return {
    bases: { ar: plainStrings(bases.ar), en: plainStrings(bases.en) },
    quotesBuiltInFnv: (data && data.quotesBuiltInFnv) || null,
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
    undoOf: data.undoOf || null,
    undoneBy: data.undoneBy || null,
  };
}

/** The whole live document, as a save writes it. */
function liveDocument(live, FieldValue) {
  const doc = {
    strings: live.strings,
    version: live.version,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (live.quotes) doc.quotes = live.quotes;
  return doc;
}

function adminDocument(admin, FieldValue) {
  return {
    bases: admin.bases,
    quotesBuiltInFnv: admin.quotesBuiltInFnv,
    updatedAt: FieldValue.serverTimestamp(),
  };
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
      done.push({ lang, before, after: text, builtIn });
    }
    if (done.length === 0) return done;
    live.version += 1;
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    for (const change of done) {
      tx.set(db.collection(LOG_COLLECTION).doc(), {
        at: FieldValue.serverTimestamp(),
        kind: 'string',
        key: entry.key,
        lang: change.lang,
        before: change.before,
        after: change.after,
        builtIn: change.builtIn,
        undoOf: null,
      });
    }
    return done;
  });
  return { ok: true, errors: {}, warnings, changed: changed.length };
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
    } else {
      throw new WordingInputError('That History row cannot be undone.');
    }

    live.version += 1;
    const undoRef = db.collection(LOG_COLLECTION).doc();
    tx.set(liveRef, liveDocument(live, FieldValue));
    tx.set(adminRef, adminDocument(admin, FieldValue));
    tx.set(undoRef, {
      at: FieldValue.serverTimestamp(),
      kind: row.kind,
      key: row.key,
      lang: row.lang,
      before: current,
      after: row.kind === 'quotes' ? plainQuotes(row.before) : row.before,
      builtIn: row.builtIn,
      undoOf: row.id,
    });
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
  undoChange,
  isLocalWrite,
  phonesCanRead,
  todayKey,
};
