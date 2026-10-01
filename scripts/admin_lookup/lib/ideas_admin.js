'use strict';

/**
 * The Habit ideas page's server side: the built-in ideas and plans, read
 * out of the app's own files, and the one write, the admin's edits into
 * wording/live's `ideas` and `plans`.
 *
 * Aziz, 2026-10-01: Add Habit gets an ideas page, ready-made Plans and a
 * list of single habit ideas each with its benefit, easy ways to start and
 * a suggested schedule, and he wants to "easily change" both from here:
 * hide or show, feature, reorder, edit the words in both languages, add a
 * new idea, and the plans' names, descriptions, order and switch.
 *
 * Where the built-ins come from, both read again whenever the file changes:
 *   assets/data/habit_ideas.json   the ONE list of ideas; the app reads the
 *                                  same file (kHabitIdeasAsset)
 *   lib/features/habits/catalog/habit_plans.dart
 *                                  the plans, parsed out of the Dart list
 *                                  (parsePlansDart), which throws when its
 *                                  shape is not found, never guesses
 *
 * How it saves is the FAQ page's way (lib/wording.js saveFaq): the edits
 * are fields of wording/live beside `strings`, `faq`, `pet` and `splash`,
 * so phones get them within seconds with no deploy; every save REPLACES the
 * document in a transaction and bumps its version; a page older than the
 * stored edits, or drawn from built-in lists that have changed in the repo
 * since, is refused (409) rather than writing over either; and every save
 * leaves a History row (kind 'ideas') that lib/wording.js undoChange can
 * put back. lib/wording.js keeps every field it does not know, so no other
 * page's save drops these two.
 *
 * The rules (reading, checking, the draft) are ../wording/ideas_rules.js,
 * shared with the page.
 */

const fs = require('fs');
const path = require('path');
const IdeasRules = require('../wording/ideas_rules');
const HabitCatalog = require('./habit_catalog');
const wording = require('./wording');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const IDEAS_JSON = path.join(REPO_ROOT, 'assets', 'data', 'habit_ideas.json');
const PLANS_DART = path.join(REPO_ROOT, 'lib', 'features', 'habits', 'catalog', 'habit_plans.dart');

const STALE_BUILT_IN = 'The app\'s own ideas file or plan list changed in the repo since this page was opened, so publishing now could store old words. Copy anything you typed, reload the page, and make the change again.';
const STALE_STORED = 'The ideas or plans were published from another tab, or undone, since this page was opened. Copy anything you typed, reload the page to see the latest, and make the change again.';
const RELOAD = 'This page is out of date. Copy anything you typed, then reload it.';

class IdeasInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

// ---- habit_plans.dart --------------------------------------------------------------
//
// A small reader for the one Dart shape the plans are written in: a list
// of HabitPlan(...) calls with named arguments. It knows comments (a
// comment there says «the Prophet's ﷺ own prescription», and a quote in
// prose must never be read as a value), every kind of string literal,
// adjacent literals joined the way Dart joins them, and nested brackets.
// A string that interpolates ($x) is not a plain value and counts as
// missing.

const SIMPLE_ESCAPES = { n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', v: '\v' };

class DartReader {
  constructor(source, at) {
    this.s = source;
    this.i = at;
  }

  fail(what) {
    const line = this.s.slice(0, this.i).split('\n').length;
    throw new IdeasInputError(`Could not read the plans in habit_plans.dart: ${what} (line ${line}).`, 500);
  }

  /** Steps over whitespace and comments (Dart's block comments nest). */
  skip() {
    const s = this.s;
    for (;;) {
      const c = s[this.i];
      if (c === ' ' || c === '\n' || c === '\r' || c === '\t') {
        this.i++;
      } else if (c === '/' && s[this.i + 1] === '/') {
        const nl = s.indexOf('\n', this.i);
        this.i = nl < 0 ? s.length : nl + 1;
      } else if (c === '/' && s[this.i + 1] === '*') {
        let depth = 1;
        this.i += 2;
        while (this.i < s.length && depth) {
          if (s.startsWith('/*', this.i)) {
            depth++;
            this.i += 2;
          } else if (s.startsWith('*/', this.i)) {
            depth--;
            this.i += 2;
          } else {
            this.i++;
          }
        }
        if (depth) this.fail('a comment that never ends');
      } else {
        return;
      }
    }
  }

  peek() {
    this.skip();
    return this.s[this.i];
  }

  atString() {
    const c = this.s[this.i];
    const n = this.s[this.i + 1];
    return c === '\'' || c === '"' || ((c === 'r' || c === 'R') && (n === '\'' || n === '"'));
  }

  /** One string literal: its text, or null when it interpolates. */
  readString() {
    const s = this.s;
    let raw = false;
    if (s[this.i] === 'r' || s[this.i] === 'R') {
      raw = true;
      this.i++;
    }
    const q = s[this.i];
    const close = s.startsWith(q + q + q, this.i) ? q + q + q : q;
    this.i += close.length;
    let out = '';
    let plain = true;
    for (;;) {
      if (this.i >= s.length) this.fail('a string that never ends');
      if (s.startsWith(close, this.i)) {
        this.i += close.length;
        return plain ? out : null;
      }
      const c = s[this.i];
      if (close.length === 1 && c === '\n') this.fail('a string that runs past the end of its line');
      if (!raw && c === '\\') {
        const e = s[this.i + 1];
        this.i += 2;
        if (e === 'x') {
          out += String.fromCharCode(parseInt(s.slice(this.i, this.i + 2), 16));
          this.i += 2;
        } else if (e === 'u') {
          if (s[this.i] === '{') {
            const end = s.indexOf('}', this.i);
            out += String.fromCodePoint(parseInt(s.slice(this.i + 1, end), 16));
            this.i = end + 1;
          } else {
            out += String.fromCharCode(parseInt(s.slice(this.i, this.i + 4), 16));
            this.i += 4;
          }
        } else if (Object.prototype.hasOwnProperty.call(SIMPLE_ESCAPES, e)) {
          out += SIMPLE_ESCAPES[e];
        } else {
          out += e;
        }
      } else if (!raw && c === '$') {
        plain = false;
        this.i++;
        if (s[this.i] === '{') this.skipBalanced('{', '}');
        else while (/[A-Za-z0-9_]/.test(s[this.i] || '')) this.i++;
      } else {
        out += c;
        this.i++;
      }
    }
  }

  /** Adjacent literals, joined: 'one ' 'two' is 'one two'. */
  readStrings() {
    let out = '';
    let plain = true;
    do {
      const v = this.readString();
      if (v === null) plain = false;
      else out += v;
      this.skip();
    } while (this.atString());
    return plain ? out : null;
  }

  readIdent() {
    const m = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(this.s.slice(this.i, this.i + 256));
    if (!m) this.fail('a name was expected');
    this.i += m[0].length;
    return m[0];
  }

  /** From an opening bracket to its match, strings and comments included. */
  skipBalanced(open, closeCh) {
    let depth = 0;
    for (;;) {
      this.skip();
      if (this.i >= this.s.length) this.fail('a bracket that never closes');
      if (this.atString()) {
        this.readString();
        continue;
      }
      const c = this.s[this.i];
      this.i++;
      if (c === open) depth++;
      else if (c === closeCh) {
        depth--;
        if (depth === 0) return;
      }
    }
  }

  /** Type arguments such as <HabitPlan>. */
  skipTypeArgs() {
    if (this.peek() === '<') this.skipBalanced('<', '>');
  }

  /** The rest of an expression this reader does not need, up to , ) ] or }. */
  skipExpression() {
    const pairs = { '(': ')', '[': ']', '{': '}' };
    for (;;) {
      this.skip();
      if (this.i >= this.s.length) this.fail('an expression that never ends');
      if (this.atString()) {
        this.readString();
        continue;
      }
      const c = this.s[this.i];
      if (c === ',' || c === ')' || c === ']' || c === '}') return;
      if (pairs[c]) this.skipBalanced(c, pairs[c]);
      else this.i++;
    }
  }

  value() {
    this.skip();
    if (this.atString()) return { kind: 'string', value: this.readStrings() };
    const c = this.s[this.i];
    if (c === '<') {
      this.skipTypeArgs();
      return this.value();
    }
    if (c === '[') return { kind: 'list', items: this.list() };
    if (c !== undefined && /[A-Za-z_$]/.test(c)) {
      let name = this.readIdent();
      if (name === 'const' || name === 'new') return this.value();
      while (this.peek() === '.') {
        this.i++;
        this.skip();
        name += '.' + this.readIdent();
      }
      this.skipTypeArgs();
      if (this.peek() === '(') return { kind: 'call', name, args: this.args() };
      this.skipExpression();
      return { kind: 'name', name };
    }
    this.skipExpression();
    return { kind: 'other' };
  }

  list() {
    this.i++; // [
    const items = [];
    for (;;) {
      const c = this.peek();
      if (c === ']') {
        this.i++;
        return items;
      }
      items.push(this.value());
      const next = this.peek();
      if (next === ',') this.i++;
      else if (next !== ']') this.fail('a comma or ] was expected in a list');
    }
  }

  args() {
    this.i++; // (
    const named = {};
    const positional = [];
    for (;;) {
      const c = this.peek();
      if (c === ')') {
        this.i++;
        return { named, positional };
      }
      const at = this.i;
      let name = null;
      if (/[A-Za-z_$]/.test(c)) {
        name = this.readIdent();
        if (this.peek() === ':') this.i++;
        else {
          name = null;
          this.i = at;
        }
      }
      const v = this.value();
      if (name) named[name] = v;
      else positional.push(v);
      const next = this.peek();
      if (next === ',') this.i++;
      else if (next !== ')') this.fail('a comma or ) was expected in ' + (name ? 'the argument ' + name : 'an argument list'));
    }
  }
}

const PLAN_STRING_FIELDS = ['id', 'nameAr', 'nameEn', 'descAr', 'descEn'];

/**
 * The plans in habit_plans.dart, in the code's order: [{ id, nameAr,
 * nameEn, descAr, descEn, catalogIds }]. Every one of those must be a plain
 * literal (catalogIds a list of them); anything else, the list itself not
 * found, a plan id used twice, or no plans at all, throws an IdeasInputError
 * that says exactly what, so the page can show it instead of a wrong list.
 */
function parsePlansDart(source) {
  const decl = /(?:^|\n)[ \t]*(?:const|final)\s+(?:List<HabitPlan>\s+)?habitPlans\s*=/.exec(source);
  if (!decl) {
    throw new IdeasInputError('Could not read the plans in habit_plans.dart: the list `const habitPlans = <HabitPlan>[...]` is not in the file.', 500);
  }
  const reader = new DartReader(source, decl.index + decl[0].length);
  const list = reader.value();
  if (list.kind !== 'list') {
    throw new IdeasInputError('Could not read the plans in habit_plans.dart: habitPlans is not a list literal.', 500);
  }
  const plans = [];
  const missing = [];
  list.items.forEach((item, n) => {
    if (item.kind !== 'call' || item.name !== 'HabitPlan') {
      missing.push(`entry ${n + 1} is not a HabitPlan(...)`);
      return;
    }
    const a = item.args.named;
    const plan = {};
    const idArg = a.id && a.id.kind === 'string' ? a.id.value : null;
    const label = idArg ? `plan ${idArg}` : `plan ${n + 1}`;
    for (const f of PLAN_STRING_FIELDS) {
      const v = a[f];
      if (!v || v.kind !== 'string' || v.value === null || !v.value.trim()) {
        missing.push(`${label}'s ${f} as a plain string`);
      } else {
        plan[f] = v.value;
      }
    }
    const ids = a.catalogIds;
    if (!ids || ids.kind !== 'list' || ids.items.some((x) => x.kind !== 'string' || x.value === null)) {
      missing.push(`${label}'s catalogIds as a list of plain strings`);
    } else {
      plan.catalogIds = ids.items.map((x) => x.value);
    }
    plans.push(plan);
  });
  if (!list.items.length) missing.push('at least one plan');
  const seen = new Set();
  for (const p of plans) {
    if (!p.id) continue;
    if (seen.has(p.id)) missing.push(`one plan per id (${p.id} is used twice)`);
    seen.add(p.id);
  }
  if (missing.length) {
    throw new IdeasInputError(`Could not read the plans in habit_plans.dart: ${missing.join(', ')}.`, 500);
  }
  return plans.map((p) => ({
    id: p.id,
    nameAr: p.nameAr,
    nameEn: p.nameEn,
    descAr: p.descAr,
    descEn: p.descEn,
    catalogIds: p.catalogIds,
  }));
}

// ---- The built-ins -------------------------------------------------------------------

function mtime(file) {
  try {
    return fs.statSync(file).mtimeMs;
  } catch {
    return null;
  }
}

function relative(file) {
  return path.relative(REPO_ROOT, file).split(path.sep).join('/');
}

/** The built-in ideas from [file]: the list, or why there is none. */
function readIdeasFile(file) {
  const out = { ideas: null, ideasMissing: false, ideasError: null, ideaSkipped: [], ideaNotes: [] };
  if (mtime(file) === null) {
    out.ideasMissing = true;
    return out;
  }
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    out.ideasError = `${relative(file)} is not valid JSON: ${e.message}`;
    return out;
  }
  const parsed = IdeasRules.parseBuiltInIdeas(data);
  if (parsed.shapeError) {
    out.ideasError = `${relative(file)}: ${parsed.shapeError} Expected { "version": 1, "ideas": [ ... ] }.`;
    return out;
  }
  out.ideas = parsed.ideas;
  out.ideaSkipped = parsed.skipped;
  out.ideaNotes = IdeasRules.fileNotes(parsed.ideas);
  if (data.version !== 1) out.ideaNotes.unshift(`The file says version ${JSON.stringify(data.version)}; this page reads version 1.`);
  return out;
}

/** The names of the preset habits [ids] point at, for the plans' read-only list. */
function habitNames(plans) {
  const out = {};
  for (const p of plans || []) {
    for (const id of p.catalogIds) {
      if (Object.prototype.hasOwnProperty.call(out, id)) continue;
      const t = HabitCatalog.catalogTemplate(id);
      out[id] = t ? { nameAr: t.nameAr || t.name, nameEn: t.name } : null;
    }
  }
  return out;
}

const _cache = new Map(); // key: the two paths; value: { stamp, value }

/**
 * The built-in ideas and plans, read again only when either source
 * changes. Never throws: what could not be read is said in the result
 * (ideasMissing, ideasError, plansError) and that part is null.
 */
function builtIns({ ideasPath = IDEAS_JSON, plansPath = PLANS_DART } = {}) {
  const key = ideasPath + '|' + plansPath;
  const stamp = [mtime(ideasPath), mtime(plansPath), mtime(HabitCatalog.CATALOG_DART)].join('|');
  const hit = _cache.get(key);
  if (hit && hit.stamp === stamp) return hit.value;
  const ideas = readIdeasFile(ideasPath);
  let plans = null;
  let plansError = null;
  if (mtime(plansPath) === null) {
    plansError = `${relative(plansPath)} is not in the repo.`;
  } else {
    try {
      plans = parsePlansDart(fs.readFileSync(plansPath, 'utf8'));
    } catch (e) {
      plansError = e.message;
    }
  }
  const value = Object.assign(ideas, {
    ideasFile: relative(ideasPath),
    plans,
    plansError,
    plansFile: relative(plansPath),
    habits: habitNames(plans),
  });
  _cache.set(key, { stamp, value });
  return value;
}

/** The two lists alone, as checkDraft and the fingerprint take them. */
function listsOf(builtIn) {
  return { ideas: builtIn.ideas, plans: builtIn.plans };
}

function fingerprintOf(builtIn) {
  return IdeasRules.fingerprint(listsOf(builtIn));
}

/** wording/live's `ideas` and `plans` as stored (null for none). */
function storedOf(live) {
  const extra = live.extra || {};
  const pick = (k) => (Object.prototype.hasOwnProperty.call(extra, k) && extra[k] !== undefined ? extra[k] : null);
  return { ideas: pick('ideas'), plans: pick('plans') };
}

function setStored(live, key, value) {
  if (value === null || value === undefined) delete live.extra[key];
  else live.extra[key] = value;
}

// ---- Reading and saving -------------------------------------------------------------------

/** Everything the page needs. [opts] can point at other source files (tests). */
async function readIdeas(db, opts) {
  const builtIn = builtIns(opts);
  const { live, log } = await wording.readWording(db);
  return {
    builtIn,
    stored: storedOf(live),
    version: live.version,
    updatedAt: live.updatedAt,
    fingerprint: fingerprintOf(builtIn),
    log: log.filter((row) => row.kind === 'ideas'),
  };
}

/**
 * Publishes the page's [draft] ({ ideas?, plans? }: each part only when the
 * page changed it; a part left out keeps what is stored, untouched).
 * [base] is the stored { ideas, plans } the page was built from and
 * [builtInFingerprint] the fingerprint of the built-in lists it was drawn
 * from; either out of date refuses the save with a 409.
 *
 * Returns { ok, errors, warnings, changed }. Nothing is written unless the
 * whole draft passes.
 */
async function saveIdeas(db, FieldValue, { draft, base, builtInFingerprint }, opts) {
  const builtIn = builtIns(opts);
  if (builtInFingerprint !== fingerprintOf(builtIn)) throw new IdeasInputError(STALE_BUILT_IN, 409);
  if (base === undefined) throw new IdeasInputError(RELOAD, 409);
  const d = IdeasRules.isMap(draft) ? draft : {};
  const sendsIdeas = d.ideas !== undefined && d.ideas !== null;
  const sendsPlans = d.plans !== undefined && d.plans !== null;
  if (!sendsIdeas && !sendsPlans) throw new IdeasInputError('Nothing to publish.');
  const check = IdeasRules.checkDraft(listsOf(builtIn), d);
  if (!check.ok) return { ok: false, errors: check.errors, warnings: check.warnings, changed: false };

  const expected = IdeasRules.isMap(base)
    ? { ideas: base.ideas === undefined ? null : base.ideas, plans: base.plans === undefined ? null : base.plans }
    : { ideas: null, plans: null };
  const liveRef = db.doc(wording.LIVE_DOC);
  const changed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = wording.shapeLive(snap.exists ? snap.data() : null);
    const stored = storedOf(live);
    if (!IdeasRules.same(stored, expected)) throw new IdeasInputError(STALE_STORED, 409);
    const next = {
      ideas: sendsIdeas ? check.edits.ideas : stored.ideas,
      plans: sendsPlans ? check.edits.plans : stored.plans,
    };
    if (IdeasRules.same(next, stored)) return false;
    setStored(live, 'ideas', next.ideas);
    setStored(live, 'plans', next.plans);
    live.version += 1;
    tx.set(liveRef, wording.liveDocument(live, FieldValue));
    tx.set(db.collection(wording.LOG_COLLECTION).doc(), {
      at: FieldValue.serverTimestamp(),
      kind: 'ideas',
      key: null,
      lang: null,
      before: stored,
      after: next,
      builtIn: null,
      undoOf: null,
    });
    return true;
  });
  return { ok: true, errors: [], warnings: check.warnings, changed };
}

module.exports = {
  IDEAS_JSON,
  PLANS_DART,
  IdeasInputError,
  parsePlansDart,
  builtIns,
  listsOf,
  fingerprintOf,
  storedOf,
  readIdeas,
  saveIdeas,
};
