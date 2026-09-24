'use strict';

/**
 * The Wording page: what it lets through, what a save does to the document
 * every phone reads, and that its page and scripts load at all.
 *
 * The saves run against a small in-memory stand-in for Firestore, built
 * below, never against the real project. What matters about the real one
 * is modelled: a transaction's writes land together or not at all, and
 * set() without merge replaces the whole document, which is the property
 * "back to built-in" depends on.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const Rules = require('../wording/rules');
const wording = require('../lib/wording');
const { renderWordingPage, PAGE_STYLES } = require('../lib/wording_page');

// ---- An in-memory Firestore, just enough for lib/wording.js ---------------

class FakeTimestamp {
  constructor(date) {
    this.date = date;
  }

  toDate() {
    return this.date;
  }
}

const FieldValue = { serverTimestamp: () => ({ __serverTimestamp: true }) };

// Built, never typed: this file keeps the rule it tests.
const EM_DASH = String.fromCharCode(0x2014);

function copy(value, now) {
  if (value && value.__serverTimestamp) return new FakeTimestamp(now || new Date());
  if (value instanceof FakeTimestamp) return value;
  if (Array.isArray(value)) return value.map((v) => copy(v, now));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = copy(v, now);
    return out;
  }
  return value;
}

function fakeDb() {
  const docs = new Map();
  let clock = Date.UTC(2026, 8, 18, 12, 0, 0);
  let nextId = 1;

  function snap(ref) {
    const data = docs.get(ref.path);
    return { id: ref.id, exists: data !== undefined, data: () => copy(data) };
  }

  function ref(p) {
    return { path: p, id: p.split('/').pop(), get: async () => snap(ref(p)) };
  }

  const db = {
    docs,
    doc: (p) => ref(p),
    collection: (name) => ({
      doc: (id) => ref(name + '/' + (id || 'auto' + String(nextId++).padStart(4, '0'))),
      orderBy: () => ({
        limit: (n) => ({
          get: async () => {
            const rows = [...docs.entries()]
              .filter(([p]) => p.startsWith(name + '/'))
              .map(([p, data], order) => ({ p, data, order }))
              .sort((a, b) => (b.data.at.date - a.data.at.date) || (b.order - a.order))
              .slice(0, n);
            return { docs: rows.map((r) => ({ id: r.p.split('/').pop(), data: () => copy(r.data) })) };
          },
        }),
      }),
    }),
    async runTransaction(fn) {
      const writes = [];
      const tx = {
        get: async (r) => snap(r),
        getAll: async (...refs) => refs.map(snap),
        set: (r, data) => writes.push(['set', r, data]),
        update: (r, data) => writes.push(['update', r, data]),
      };
      const result = await fn(tx);
      clock += 1000;
      const now = new Date(clock);
      for (const [kind, r, data] of writes) {
        if (kind === 'set') docs.set(r.path, copy(data, now));
        else docs.set(r.path, Object.assign(copy(docs.get(r.path)), copy(data, now)));
      }
      return result;
    },
  };
  return db;
}

// A catalog row shaped like the generator's.
const signIn = {
  key: 'signIn', editable: true, ar: 'تسجيل الدخول', en: 'Sign in', tokensAr: [], tokensEn: [],
};
const found = {
  key: 'reconnectFound',
  editable: true,
  ar: 'لقينا على هذا الجهاز: {habitsCount(habits)}، المستوى {level}.',
  en: 'Found on this device: {habitsCount(habits)}, level {level}.',
  tokensAr: ['habitsCount(habits)', 'level'],
  tokensEn: ['habitsCount(habits)', 'level'],
};
const plural = { key: 'daysInSentence', editable: false, why: 'Picked in code.', ar: 'يومين', en: '1 day' };
const builtInQuotes = [
  { ar: 'عاداتك هي اللي تبنيك.', en: 'Your habits build you.', source: null },
  { ar: 'من جدّ وجد.', en: 'Whoever strives, finds.', source: 'Proverb (مثل)' },
];

// ---- The rules --------------------------------------------------------------

test('an edit may not be empty, carry an em dash, or name a part the app cannot fill', () => {
  assert.deepStrictEqual(Rules.checkStringEdit(signIn, 'ar', '   ').ok, false);
  const dash = Rules.checkStringEdit(signIn, 'en', 'Sign in ' + EM_DASH + ' now');
  assert.strictEqual(dash.ok, false);
  assert.match(dash.errors.join(' '), /em dash/);
  const unknown = Rules.checkStringEdit(found, 'ar', 'المستوى {lvl}');
  assert.strictEqual(unknown.ok, false);
  assert.match(unknown.errors.join(' '), /\{lvl\}/);
  assert.match(unknown.errors.join(' '), /\{level\}/, 'says what it can fill');
  assert.strictEqual(Rules.checkStringEdit(signIn, 'ar', 'x'.repeat(Rules.MAX_STRING_LENGTH + 1)).ok, false);
});

test('leaving a part out is allowed, and said', () => {
  const check = Rules.checkStringEdit(found, 'ar', 'المستوى {level}.');
  assert.strictEqual(check.ok, true);
  assert.match(check.warnings.join(' '), /\{habitsCount\(habits\)\}/);
});

test('a string with more than one wording cannot be edited at all', () => {
  const check = Rules.checkStringEdit(plural, 'ar', 'يوم');
  assert.strictEqual(check.ok, false);
  assert.deepStrictEqual(check.errors, ['Picked in code.']);
});

test('the built-in text again is recognised as no edit, whatever the spacing', () => {
  assert.strictEqual(Rules.checkStringEdit(signIn, 'ar', '  تسجيل الدخول \r\n').sameAsBuiltIn, true);
  assert.strictEqual(Rules.checkStringEdit(signIn, 'ar', 'ادخل').sameAsBuiltIn, false);
});

test('house style warns on the Arabic side without blocking the save', () => {
  const said = (text) => Rules.checkStringEdit(signIn, 'ar', text).warnings.join(' | ');
  assert.match(said('يومك مفتوح لسّه، تقدر'), /إلى الآن/, 'لسّه before a comma');
  assert.match(said('ولسا ما خلصت'), /إلى الآن/);
  assert.doesNotMatch(said('لسان عربي'), /إلى الآن/, 'a word that merely starts the same');
  assert.match(said('باچر'), /باجر/);
  assert.match(said('هذي العادة'), /هذه/);
  assert.doesNotMatch(said('هذه العادة'), /هذه, not/);
  assert.match(said('بعد ٣ أيام'), /Latin digits/);
  assert.strictEqual(Rules.checkStringEdit(signIn, 'ar', 'باچر').ok, true);
  assert.deepStrictEqual(Rules.checkStringEdit(signIn, 'en', 'lissa').warnings, []);
});

test('a rotation needs at least one line, both languages on every line', () => {
  assert.strictEqual(Rules.checkQuotes([]).ok, false);
  const missing = Rules.checkQuotes([{ ar: 'سطر', en: '' }]);
  assert.strictEqual(missing.ok, false);
  assert.match(missing.errors.join(' '), /Line 1 has no English/);
  const short = Rules.checkQuotes([{ ar: 'سطر', en: 'Line' }, { ar: 'سطر', en: 'Again' }]);
  assert.strictEqual(short.ok, true);
  assert.match(short.warnings.join(' '), /repeats line 1/);
  assert.match(short.warnings.join(' '), /same month/);
});

test('the rotation picks the same line as the app for the same day', () => {
  // daily_quotes.dart counts whole days from 2026-01-01 and wraps with a
  // non-negative modulo. 2026-09-18 is day 260; 260 % 36 = 8, the ninth
  // line, which is the Jim Rohn line Aziz was looking at that day.
  assert.strictEqual(Rules.rotationIndex('2026-09-18', 36), 8);
  assert.strictEqual(Rules.rotationIndex('2026-01-01', 36), 0);
  assert.strictEqual(Rules.rotationIndex('2025-12-31', 36), 35, 'before the epoch wraps to the end');
  assert.strictEqual(Rules.addDays('2026-12-31', 1), '2027-01-01');
});

// ---- Moving lines -------------------------------------------------------------

const letters = (s) => s.split('');

test('a moved line lands exactly where it was sent, and nothing else changes order', () => {
  const list = letters('abcdefgh');
  assert.deepStrictEqual(Rules.moveLines(list, [6], 1), letters('agbcdefh'), 'up');
  assert.deepStrictEqual(Rules.moveLines(list, [1], 6), letters('acdefgbh'), 'down');
  assert.deepStrictEqual(Rules.moveLines(list, [3], 3), list, 'onto itself');
  assert.deepStrictEqual(list, letters('abcdefgh'), 'the list passed in is not touched');
  assert.deepStrictEqual(Rules.moveLines(list, [2], 99), letters('abdefghc'), 'past the end means the end');
  assert.deepStrictEqual(Rules.moveLines(list, [2], -4), letters('cabdefgh'), 'before the start means the start');
});

test('ticked lines move together, in list order whatever order they were ticked in', () => {
  const list = letters('abcdefgh');
  assert.deepStrictEqual(Rules.moveLines(list, [6, 1, 4], 2), letters('acbegdfh'));
  assert.deepStrictEqual(Rules.moveLines(list, [0, 1], 7), letters('cdefghab'), 'a group that would run past the end is pulled back');
});

test('lines sent to a day show on that day, the days after it too, even past the last line', () => {
  const list = letters('abcdefgh');
  const n = list.length;
  // 2026-09-24 is day 266 of the rotation: 266 % 8 = 2, so today is 'c'.
  const today = '2026-09-24';
  assert.strictEqual(list[Rules.rotationIndex(today, n)], 'c');
  const shownOn = (l, day) => l[Rules.rotationIndex(day, n)];

  // One line from below today, to tomorrow: today's line stays.
  const one = Rules.moveLines(list, [6], Rules.rotationIndex(Rules.addDays(today, 1), n), true);
  assert.strictEqual(shownOn(one, Rules.addDays(today, 1)), 'g');
  assert.strictEqual(shownOn(one, today), 'c');

  // Three lines from the day whose place is the last one: they wrap round.
  const lastDay = Rules.addDays(today, n - 1 - Rules.rotationIndex(today, n));
  assert.strictEqual(Rules.rotationIndex(lastDay, n), n - 1);
  const three = Rules.moveLines(list, [0, 3, 5], Rules.rotationIndex(lastDay, n), true);
  assert.deepStrictEqual(
    [0, 1, 2].map((k) => shownOn(three, Rules.addDays(lastDay, k))),
    ['a', 'd', 'f']);
  assert.deepStrictEqual(three.slice().sort(), list, 'every line still there once');
});

test('moved counts the fewest lines that changed place', () => {
  assert.strictEqual(Rules.longestRising([0, 1, 2, 3, 4]), 5);
  assert.strictEqual(Rules.longestRising([0, 4, 1, 2, 3]), 4, 'one line dragged up');
  assert.strictEqual(Rules.longestRising([4, 3, 2, 1, 0]), 1);
  assert.strictEqual(Rules.longestRising([]), 0);
});

test('History tells a move from an edit by the text alone', () => {
  const q = (ar, en) => ({ ar, en });
  const before = [q('أ', 'A'), q('ب', 'B'), q('ج', 'C'), q('د', 'D')];
  const words = (after) => Rules.lineChangeWords(Rules.describeLineChanges(before, after));

  assert.strictEqual(words([before[0], before[3], before[1], before[2]]), '1 line moved');
  assert.strictEqual(words([before[0], q('ب', 'Bee'), before[2], before[3]]), '1 line edited');
  assert.strictEqual(words([q('أ', 'A '), before[1], before[2], before[3]]), '', 'spacing at the ends is no change');
  assert.strictEqual(words([before[3], before[0], q('جديد', 'New'), before[1]]), '1 line moved, 1 added, 1 removed');
  assert.deepStrictEqual(Rules.describeLineChanges(before, before.concat([q('هـ', 'E')])),
    { moved: 0, edited: 0, added: 1, removed: 0 });
});

test('search ignores harakat and the usual spelling variants', () => {
  assert.ok(Rules.searchKey('التّقدير').includes(Rules.searchKey('التقدير')));
  assert.strictEqual(Rules.searchKey('إلى'), Rules.searchKey('الى'));
  assert.strictEqual(Rules.searchKey('مدرسة'), Rules.searchKey('مدرسه'));
});

test('the fingerprint is FNV-1a, the same as the Dart generator writes', () => {
  assert.strictEqual(Rules.fnv1a(Buffer.from('')), '811c9dc5');
  assert.strictEqual(Rules.fnv1a(Buffer.from('hello')), '4f9f2cab');
});

// ---- Saving -----------------------------------------------------------------

test('a save lays the edit into the live document, records what it replaced, and logs it', async () => {
  const db = fakeDb();
  const result = await wording.saveStringEdits(db, FieldValue, {
    entry: signIn,
    changes: { ar: '  ادخل حسابك ' },
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.changed, 1);
  const stored = await wording.readWording(db);
  assert.deepStrictEqual(stored.live.strings, { ar: { signIn: 'ادخل حسابك' }, en: {} });
  assert.strictEqual(stored.live.version, 1);
  assert.ok(stored.live.updatedAt, 'stamped with the server time');
  assert.strictEqual(stored.admin.bases.ar.signIn, 'تسجيل الدخول');
  assert.strictEqual(stored.log.length, 1);
  assert.deepStrictEqual(
    [stored.log[0].kind, stored.log[0].key, stored.log[0].lang, stored.log[0].before, stored.log[0].after],
    ['string', 'signIn', 'ar', null, 'ادخل حسابك'],
  );
});

test('back to built-in really removes the edit from the document', async () => {
  const db = fakeDb();
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل', en: 'Log in' } });
  // Typing the built-in text back is the same as removing the edit.
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'تسجيل الدخول' } });
  let stored = await wording.readWording(db);
  assert.deepStrictEqual(stored.live.strings, { ar: {}, en: { signIn: 'Log in' } });
  assert.deepStrictEqual(stored.admin.bases.ar, {});

  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { en: null } });
  stored = await wording.readWording(db);
  assert.deepStrictEqual(stored.live.strings, { ar: {}, en: {} });
  const raw = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(raw.strings, { ar: {}, en: {} }, 'nothing left behind on the server');
});

test('a failing check writes nothing at all, in either language', async () => {
  const db = fakeDb();
  const result = await wording.saveStringEdits(db, FieldValue, {
    entry: signIn,
    changes: { ar: 'ادخل', en: 'Sign ' + EM_DASH + ' in' },
  });
  assert.strictEqual(result.ok, false);
  assert.ok(result.errors.en);
  assert.strictEqual(db.docs.size, 0);
});

test('a string that cannot be edited is refused before anything is read', async () => {
  const db = fakeDb();
  await assert.rejects(
    wording.saveStringEdits(db, FieldValue, { entry: plural, changes: { ar: 'يوم' } }),
    wording.WordingInputError,
  );
  await assert.rejects(
    wording.saveStringEdits(db, FieldValue, { entry: undefined, changes: { ar: 'x' } }),
    /No such string/,
  );
  assert.strictEqual(db.docs.size, 0);
});

test('an unchanged save changes nothing and logs nothing', async () => {
  const db = fakeDb();
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  const again = await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  assert.strictEqual(again.changed, 0);
  const stored = await wording.readWording(db);
  assert.strictEqual(stored.live.version, 1);
  assert.strictEqual(stored.log.length, 1);
});

test('saving the daily lines keeps the strings, and the built-in list saves as built-in', async () => {
  const db = fakeDb();
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  const mine = [{ ar: 'سطر جديد', en: 'A new line' }, ...builtInQuotes];
  const saved = await wording.saveQuotes(db, FieldValue, { items: mine, builtIn: builtInQuotes, builtInFnv: 'abc' });
  assert.strictEqual(saved.ok, true);
  let stored = await wording.readWording(db);
  assert.strictEqual(stored.live.quotes.length, 3);
  assert.deepStrictEqual(stored.live.strings.ar, { signIn: 'ادخل' }, 'a lines save leaves the strings alone');
  assert.strictEqual(stored.admin.quotesBuiltInFnv, 'abc');

  // Saving a list equal to the built-in one is "use the built-in list".
  await wording.saveQuotes(db, FieldValue, {
    items: builtInQuotes.map((q) => ({ ar: q.ar, en: q.en })),
    builtIn: builtInQuotes,
    builtInFnv: 'abc',
  });
  stored = await wording.readWording(db);
  assert.strictEqual(stored.live.quotes, null);
  assert.ok(!('quotes' in db.docs.get(wording.LIVE_DOC)), 'the field is gone, not an empty list');
});

test('a bad rotation is refused whole', async () => {
  const db = fakeDb();
  const result = await wording.saveQuotes(db, FieldValue, {
    items: [{ ar: 'سطر', en: '' }],
    builtIn: builtInQuotes,
    builtInFnv: 'abc',
  });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(db.docs.size, 0);
});

// ---- Undo -------------------------------------------------------------------

test('undo puts back exactly what one change replaced', async () => {
  const db = fakeDb();
  const byKey = new Map([[signIn.key, signIn]]);
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل حسابك' } });
  let stored = await wording.readWording(db);
  const newest = stored.log[0];
  assert.strictEqual(newest.after, 'ادخل حسابك');

  await wording.undoChange(db, FieldValue, { id: newest.id, catalogByKey: byKey });
  stored = await wording.readWording(db);
  assert.strictEqual(stored.live.strings.ar.signIn, 'ادخل');
  assert.strictEqual(stored.log[0].undoOf, newest.id);
  assert.strictEqual(stored.log.find((r) => r.id === newest.id).undoneBy, stored.log[0].id);

  await assert.rejects(
    wording.undoChange(db, FieldValue, { id: newest.id, catalogByKey: byKey }),
    /already been undone/,
  );
});

test('undo refuses when the same string changed again since', async () => {
  const db = fakeDb();
  const byKey = new Map([[signIn.key, signIn]]);
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  const first = (await wording.readWording(db)).log[0];
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل حسابك' } });
  await assert.rejects(
    wording.undoChange(db, FieldValue, { id: first.id, catalogByKey: byKey }),
    /changed again since/,
  );
  assert.strictEqual((await wording.readWording(db)).live.strings.ar.signIn, 'ادخل حسابك');
});

test('undoing the first edit of a string removes the edit altogether', async () => {
  const db = fakeDb();
  const byKey = new Map([[signIn.key, signIn]]);
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  const row = (await wording.readWording(db)).log[0];
  await wording.undoChange(db, FieldValue, { id: row.id, catalogByKey: byKey });
  const stored = await wording.readWording(db);
  assert.deepStrictEqual(stored.live.strings.ar, {});
  assert.deepStrictEqual(stored.admin.bases.ar, {});
});

test('undoing a rotation save brings the previous rotation back', async () => {
  const db = fakeDb();
  const mine = [{ ar: 'سطر', en: 'Line' }];
  await wording.saveQuotes(db, FieldValue, { items: mine, builtIn: builtInQuotes, builtInFnv: 'abc' });
  const row = (await wording.readWording(db)).log[0];
  await wording.undoChange(db, FieldValue, { id: row.id, catalogByKey: new Map() });
  assert.strictEqual((await wording.readWording(db)).live.quotes, null);
});

// ---- Around the requests ----------------------------------------------------

test('only this tool\'s own page may write', () => {
  const json = { 'content-type': 'application/json' };
  assert.strictEqual(wording.isLocalWrite({ host: '127.0.0.1:4127', ...json }, 4127), true);
  assert.strictEqual(wording.isLocalWrite({ host: 'localhost:4127', origin: 'http://localhost:4127', ...json }, 4127), true);
  assert.strictEqual(
    wording.isLocalWrite({ host: 'localhost:4127', 'content-type': 'application/json; charset=utf-8' }, 4127),
    true,
  );
  // Another site open in the same browser.
  assert.strictEqual(wording.isLocalWrite({ host: '127.0.0.1:4127', origin: 'https://example.com', ...json }, 4127), false);
  // DNS rebinding: a hostile name pointed at 127.0.0.1 still sends its own name.
  assert.strictEqual(wording.isLocalWrite({ host: 'evil.example:4127', ...json }, 4127), false);
  // A simple (no-preflight) cross-site request cannot send JSON.
  assert.strictEqual(wording.isLocalWrite({ host: '127.0.0.1:4127', 'content-type': 'text/plain' }, 4127), false);
  assert.strictEqual(wording.isLocalWrite({ host: '127.0.0.1:4128', ...json }, 4127), false);
});

test('whether phones can read is asked the way a phone asks, with no credentials', async () => {
  const seen = [];
  const answer = (status) => async (url, options) => {
    seen.push({ url, options });
    return { status };
  };
  assert.strictEqual(await wording.phonesCanRead('grow-daily-339ef', answer(200)), 'open');
  assert.strictEqual(await wording.phonesCanRead('grow-daily-339ef', answer(404)), 'open', 'allowed, no document yet');
  assert.strictEqual(await wording.phonesCanRead('grow-daily-339ef', answer(403)), 'closed');
  assert.strictEqual(await wording.phonesCanRead('grow-daily-339ef', answer(500)), 'unknown');
  assert.strictEqual(await wording.phonesCanRead('grow-daily-339ef', async () => { throw new Error('offline'); }), 'unknown');
  assert.match(seen[0].url, /projects\/grow-daily-339ef\/databases\/\(default\)\/documents\/wording\/live$/);
  assert.ok(!seen[0].options.headers, 'no Authorization header');
});

test('today is Bahrain\'s date, the one the Grid picks its line for', () => {
  // 22:30 UTC on the 17th is 01:30 on the 18th in Bahrain.
  assert.strictEqual(wording.todayKey(new Date(Date.UTC(2026, 8, 17, 22, 30))), '2026-09-18');
});

// ---- The page ---------------------------------------------------------------

test('the page and its two scripts parse, with every hook the script binds to', () => {
  const html = renderWordingPage();
  for (const file of ['app.js', 'rules.js']) {
    const source = fs.readFileSync(path.join(__dirname, '..', 'wording', file), 'utf8');
    try {
      new vm.Script(source, { filename: file });
    } catch (e) {
      assert.fail(`wording/${file} is not valid JavaScript: ${e.message}`);
    }
    assert.ok(html.includes(`src="/wording/${file}"`), `the page does not load ${file}`);
  }
  for (const id of ['banners', 'viewLines', 'viewText', 'viewHistory', 'toast', 'cntLines', 'cntText', 'cntHistory']) {
    assert.ok(html.includes(`id="${id}"`), `the page is missing #${id}`);
  }
  assert.ok(!PAGE_STYLES.includes('`'), 'PAGE_STYLES contains a backtick');
  const css = (html.match(/<style>([\s\S]*?)<\/style>/) || [])[1] || '';
  assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length, 'CSS braces are unbalanced');
});

test('the page script is written for the edition of the styles the page carries', () => {
  // The styles are built into the page when the server starts; app.js is
  // read from disk on every load. The script compares the two and tells a
  // stale server apart, which only works while they agree here.
  const app = fs.readFileSync(path.join(__dirname, '..', 'wording', 'app.js'), 'utf8');
  const styles = (PAGE_STYLES.match(/--wording-styles:\s*(\d+);/) || [])[1];
  const script = (app.match(/const STYLES_EDITION = '(\d+)';/) || [])[1];
  assert.ok(styles, 'PAGE_STYLES names no --wording-styles edition');
  assert.strictEqual(script, styles, 'app.js expects a different edition of the styles');
});

test('no em dash in the page or the scripts it serves', () => {
  // The shared stylesheet is the rest of the tool's, comments and all; what
  // this page adds to it is what is checked.
  const { BASE_STYLES } = require('../lib/render');
  const files = [
    renderWordingPage().replace(BASE_STYLES, ''),
    fs.readFileSync(path.join(__dirname, '..', 'wording', 'app.js'), 'utf8'),
    fs.readFileSync(path.join(__dirname, '..', 'wording', 'rules.js'), 'utf8'),
    fs.readFileSync(path.join(__dirname, '..', 'lib', 'wording.js'), 'utf8'),
  ];
  for (const text of files) assert.ok(!text.includes(EM_DASH));
});
