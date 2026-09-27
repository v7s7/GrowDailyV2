'use strict';

/**
 * The FAQ and Premium pages: how their edits are read and laid over the
 * app's own lists (the same cases the app's Dart test runs, so the preview
 * and the phones agree), what a draft may save, what a save does to the
 * document every phone reads, and that the pages and their scripts load.
 *
 * The saves run against a small in-memory stand-in for Firestore, the same
 * shape as the Wording page's tests use, never against the real project.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const R = require('../wording/rules');
const C = require('../wording/content_rules');
const wording = require('../lib/wording');
const { renderFaqPage, renderPremiumPage, CONTENT_STYLES } = require('../lib/content_pages');
const { BASE_STYLES } = require('../lib/render');

const CASES = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'content_cases.json'), 'utf8'));
const EM_DASH = String.fromCharCode(0x2014);

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
  let clock = Date.UTC(2026, 8, 26, 12, 0, 0);
  let nextId = 1;
  let transactions = 0;

  function snap(ref) {
    const data = docs.get(ref.path);
    return { id: ref.id, exists: data !== undefined, data: () => copy(data) };
  }

  function ref(p) {
    return { path: p, id: p.split('/').pop(), get: async () => snap(ref(p)) };
  }

  return {
    docs,
    get transactions() {
      return transactions;
    },
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
      transactions++;
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
}

function logRows(db) {
  return [...db.docs.entries()].filter(([p]) => p.startsWith('wording_log/')).map(([, d]) => d);
}

// ---- A catalog shaped like the generator's ---------------------------------

const FAQ = CASES.faqBuiltIn;
const BENEFITS = CASES.benefitBuiltIn;

function stringEntry(key, ar, en) {
  return { key, editable: true, ar, en, tokensAr: [], tokensEn: [] };
}

const CATALOG = {
  strings: [
    stringEntry('habitsTitle', 'عادات بلا حد', 'Unlimited habits'),
    stringEntry('habitsDesc', 'ابن كل عادة تهمك.', 'Build every habit you care about.'),
    stringEntry('roomsTitle', 'غرف بلا حد', 'Unlimited rooms'),
    stringEntry('roomsDesc', 'كن في كل غرفة تبيها.', 'Be in every room you want.'),
    stringEntry('historyTitle', 'سجلك كامل', 'Your full history'),
    stringEntry('historyDesc', 'كل يوم من البداية.', 'Every day since you started.'),
    stringEntry('futureTitle', 'مزايا قادمة', 'Features to come'),
    stringEntry('futureDesc', 'كل ما يضاف لاحقا.', 'Anything added later.'),
    stringEntry('premiumHeadline', 'املأ حياتك بالألوان', 'Fill your life with color'),
    { key: 'premiumSave', editable: true, ar: 'وفّر {pct}', en: 'SAVE {pct}', tokensAr: ['pct'], tokensEn: ['pct'] },
    { key: 'premiumTrialLine', editable: false, why: 'Picked in code.', ar: 'x', en: 'x' },
  ],
  faq: FAQ,
  benefits: BENEFITS,
};

/** The built-in FAQ as a page draft, which is what the page sends. */
function builtInDraft() {
  return {
    groups: C.resolveFaq(FAQ, null).map((s) => ({
      id: s.id,
      title: { ar: s.title.ar, en: s.title.en },
      items: s.items.map((i) => ({ id: i.id, q: { ar: i.q.ar, en: i.q.en }, a: { ar: i.a.ar, en: i.a.en } })),
    })),
  };
}

function builtInRows() {
  const by = new Map(CATALOG.strings.map((s) => [s.key, s]));
  return BENEFITS.items.map((b) => ({
    id: b.id,
    icon: b.icon,
    title: { ar: by.get(b.titleKey).ar, en: by.get(b.titleKey).en },
    desc: { ar: by.get(b.descKey).ar, en: by.get(b.descKey).en },
  }));
}

const byKey = new Map(CATALOG.strings.map((s) => [s.key, s]));

// ---- Reading and laying over: the cases the app runs too -------------------

test('every FAQ case resolves exactly as the app resolves it', () => {
  for (const c of CASES.faqCases) {
    const sections = C.resolveFaq(FAQ, C.parseFaqEdits(c.edits));
    assert.deepStrictEqual(sections.map((s) => [s.id, s.items.map((i) => i.id)]), c.layout, c.name);
    for (const [groupId, title] of Object.entries(c.titles || {})) {
      assert.deepStrictEqual(sections.find((s) => s.id === groupId).title, title, c.name + ': heading of ' + groupId);
    }
    for (const [itemId, t] of Object.entries(c.texts || {})) {
      const item = sections.flatMap((s) => s.items).find((i) => i.id === itemId);
      assert.deepStrictEqual({ qAr: item.q.ar, qEn: item.q.en, aAr: item.a.ar, aEn: item.a.en }, t, c.name + ': words of ' + itemId);
    }
  }
});

test('every benefit case resolves exactly as the app resolves it', () => {
  for (const c of CASES.benefitCases) {
    const list = C.resolveBenefits(BENEFITS, C.parseBenefitEdits(c.edits));
    assert.deepStrictEqual(list.map((b) => (b.added ? [b.id, b.icon, b.added] : [b.id, b.icon])), c.list, c.name);
  }
});

test('reading a document keeps what is usable and drops the rest, as the app does', () => {
  assert.strictEqual(C.parseFaqEdits(null), null);
  assert.strictEqual(C.parseFaqEdits({}), null);
  assert.strictEqual(C.parseFaqEdits({ text: { a: { qAr: '  ' } }, groups: { x: 'no' } }), null);
  const edits = C.parseFaqEdits({
    order: [{ group: 'basics', items: ['a', 7, 'a', 'b'] }, 'junk', { items: ['c'] }],
    hidden: ['c', '', 'c'],
    text: { a: { qAr: ' كيف؟ ', other: 'x' }, b: 'no' },
  });
  assert.deepStrictEqual(edits, {
    order: [{ group: 'basics', items: ['a', 'b'] }],
    hidden: ['c'],
    text: { a: { qAr: 'كيف؟' } },
    groups: {},
  });
  assert.deepStrictEqual(C.faqDocument(edits), {
    order: [{ group: 'basics', items: ['a', 'b'] }],
    hidden: ['c'],
    text: { a: { qAr: 'كيف؟' } },
  });
  assert.strictEqual(C.parseBenefitEdits({ added: { 'b-x': { icon: 'star' } } }), null);
});

// ---- What a FAQ draft saves --------------------------------------------------

test('the built-in FAQ as a draft saves as no edits at all', () => {
  const check = C.faqEditsFromDraft(FAQ, builtInDraft());
  assert.ok(check.ok, check.errors.join(' '));
  assert.strictEqual(check.edits, null);
});

test('an edited answer stores that one field, with what it replaced, and no order', () => {
  const draft = builtInDraft();
  draft.groups[0].items[1].a.en = '  A better answer.  ';
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.ok(check.ok);
  assert.deepStrictEqual(check.edits, { text: { b: { aEn: 'A better answer.' } } });
  assert.deepStrictEqual(check.bases, { items: { b: { aEn: 'Answer B.' } }, groups: {} });
});

test('a question taken off is hidden, and the order stays the code\'s', () => {
  const draft = builtInDraft();
  draft.groups[1].items.splice(0, 1);
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.deepStrictEqual(check.edits, { hidden: ['c'] });
  assert.deepStrictEqual(C.resolveFaq(FAQ, C.parseFaqEdits(check.edits)).map((s) => s.items.map((i) => i.id)), [['a', 'b'], ['d'], ['e']]);
});

test('a move is kept as an order, and resolves back to the same FAQ', () => {
  const draft = builtInDraft();
  const [c] = draft.groups[1].items.splice(0, 1);
  draft.groups[0].items.unshift(c);
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.deepStrictEqual(check.edits.order, [
    { group: 'basics', items: ['c', 'a', 'b'] },
    { group: 'rooms', items: ['d'] },
    { group: 'account', items: ['e'] },
  ]);
  const back = C.resolveFaq(FAQ, C.parseFaqEdits(check.edits));
  assert.deepStrictEqual(back.map((s) => [s.id, s.items.map((i) => i.id)]), draft.groups.map((g) => [g.id, g.items.map((i) => i.id)]));
});

test('an added question and group store all their words and the order', () => {
  const draft = builtInDraft();
  draft.groups.unshift({
    id: 'g-abcd1234',
    title: { ar: 'أسئلة أكثر', en: 'More questions' },
    items: [{ id: 'q-abcd1234', q: { ar: 'سؤال؟', en: 'Question?' }, a: { ar: 'جواب.', en: 'Answer.' } }],
  });
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.ok(check.ok, check.errors.join(' '));
  assert.deepStrictEqual(check.edits.text, { 'q-abcd1234': { qAr: 'سؤال؟', qEn: 'Question?', aAr: 'جواب.', aEn: 'Answer.' } });
  assert.deepStrictEqual(check.edits.groups, { 'g-abcd1234': { ar: 'أسئلة أكثر', en: 'More questions' } });
  assert.strictEqual(check.edits.order[0].group, 'g-abcd1234');
  assert.strictEqual(C.resolveFaq(FAQ, C.parseFaqEdits(check.edits))[0].items[0].q.en, 'Question?');
});

test('a draft with a problem saves nothing and says where', () => {
  const draft = builtInDraft();
  draft.groups[0].items[0].q.ar = '';
  draft.groups[0].items[1].a.en = 'Two ' + EM_DASH + ' parts.';
  draft.groups.push({ id: 'g-empty001', title: { ar: '', en: '' }, items: [{ id: 'nope', q: { ar: 'x', en: 'x' }, a: { ar: 'x', en: 'x' } }] });
  draft.groups[1].items.push(draft.groups[1].items[0]);
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.strictEqual(check.ok, false);
  assert.strictEqual(check.edits, null);
  const said = check.errors.join('\n');
  assert.match(said, /Group 1, question 1, question in Arabic is empty/);
  assert.match(said, /em dash/);
  assert.match(said, /has an id the app does not know/);
  assert.match(said, /in the FAQ twice/);
});

test('an added group with nothing in it is not kept, and says so', () => {
  const draft = builtInDraft();
  draft.groups.push({ id: 'g-empty001', title: { ar: '', en: '' }, items: [] });
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.ok(check.ok);
  assert.strictEqual(check.edits, null);
  assert.match(check.warnings.join(' '), /not kept/);
});

test('house style warns on the Arabic side without blocking', () => {
  const draft = builtInDraft();
  draft.groups[0].items[0].a.ar = 'يومك مفتوح لسا.';
  const check = C.faqEditsFromDraft(FAQ, draft);
  assert.ok(check.ok);
  assert.match(check.warnings.join(' '), /إلى الآن/);
});

// ---- What the Premium page's rows save ----------------------------------------

test('the built-in rows save as no list edits at all', () => {
  const r = C.benefitEditsFromRows(BENEFITS, builtInRows());
  assert.ok(r.ok, r.errors.join(' '));
  assert.strictEqual(r.edits, null);
});

test('a built-in row\'s words are not list edits: the page sends them as strings', () => {
  const rows = builtInRows();
  rows[0].title.en = 'Habits, no limit';
  const r = C.benefitEditsFromRows(BENEFITS, rows);
  assert.ok(r.ok);
  assert.strictEqual(r.edits, null);
});

test('order, icons, rows taken off and rows added become the list edits', () => {
  const rows = builtInRows();
  rows[0].icon = 'star';
  const [rooms] = rows.splice(1, 1);
  rows.splice(2, 0, { id: 'b-abcd1234', icon: 'mic', title: { ar: 'ميزة', en: 'A thing' }, desc: { ar: 'تسوي كذا.', en: 'It does this.' } });
  rows.push(rooms);
  rows.splice(rows.findIndex((x) => x.id === 'history'), 1);
  const r = C.benefitEditsFromRows(BENEFITS, rows);
  assert.ok(r.ok, r.errors.join(' '));
  assert.deepStrictEqual(r.edits, {
    order: ['habits', 'b-abcd1234', 'future', 'rooms'],
    hidden: ['history'],
    icons: { habits: 'star' },
    added: { 'b-abcd1234': { icon: 'mic', titleAr: 'ميزة', titleEn: 'A thing', descAr: 'تسوي كذا.', descEn: 'It does this.' } },
  });
  const back = C.resolveBenefits(BENEFITS, C.parseBenefitEdits(r.edits)).map((b) => [b.id, b.icon]);
  assert.deepStrictEqual(back, rows.map((x) => [x.id, x.icon]));
});

test('a row taken off keeps the code\'s order, so a later build\'s order still arrives', () => {
  const rows = builtInRows().filter((x) => x.id !== 'future');
  assert.deepStrictEqual(C.benefitEditsFromRows(BENEFITS, rows).edits, { hidden: ['future'] });
});

test('rows with a problem save nothing; selling what free users have only warns', () => {
  const rows = builtInRows();
  rows.push({ id: 'b-abcd1234', icon: 'nope', title: { ar: 'بلا إعلانات', en: 'No ads' }, desc: { ar: '', en: 'x' } });
  let r = C.benefitEditsFromRows(BENEFITS, rows);
  assert.strictEqual(r.ok, false);
  assert.match(r.errors.join(' '), /icon the app does not have/);
  assert.match(r.errors.join(' '), /description, Arabic is empty/);
  rows[rows.length - 1].icon = 'star';
  rows[rows.length - 1].desc.ar = 'بدون إعلانات.';
  r = C.benefitEditsFromRows(BENEFITS, rows);
  assert.ok(r.ok);
  assert.match(r.warnings.join(' '), /free users already have/);
});

// ---- What a save does to the document ------------------------------------------

const FAQ_FP = C.fingerprint(FAQ);
const BENEFITS_FP = C.fingerprint(BENEFITS);

function liveOf(db) {
  return db.docs.get('wording/live') || { strings: { ar: {}, en: {} } };
}

/** A FAQ save as an up-to-date page makes it; [extra] overrides. */
function faqSave(db, draft, extra) {
  return wording.saveFaq(db, FieldValue, Object.assign({
    builtIn: FAQ,
    draft,
    base: liveOf(db).faq || null,
    builtInFingerprint: FAQ_FP,
  }, extra || {}));
}

/** A Premium save as an up-to-date page makes it: [strings] with what each
 *  was when loaded, and [rows] with the list it loaded. */
function premiumSave(db, { strings = {}, rows, extra } = {}) {
  const live = liveOf(db);
  const stringsBase = {};
  for (const [key, langs] of Object.entries(strings)) {
    stringsBase[key] = {};
    for (const lang of Object.keys(langs)) {
      const table = (live.strings && live.strings[lang]) || {};
      stringsBase[key][lang] = Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null;
    }
  }
  const payload = { catalog: CATALOG, strings, stringsBase };
  if (rows) {
    payload.benefits = rows;
    payload.benefitsBase = live.benefits || null;
    payload.builtInFingerprint = BENEFITS_FP;
  }
  return wording.savePremium(db, FieldValue, Object.assign(payload, extra || {}));
}

test('a FAQ save writes the edits, what they replaced and one History row', async () => {
  const db = fakeDb();
  const draft = builtInDraft();
  draft.groups[0].items[0].q.en = 'How do I mark it?';
  const result = await faqSave(db, draft);
  assert.deepStrictEqual([result.ok, result.changed], [true, 1]);
  const live = db.docs.get('wording/live');
  assert.deepStrictEqual(live.faq, { text: { a: { qEn: 'How do I mark it?' } } });
  assert.strictEqual(live.version, 1);
  assert.deepStrictEqual(db.docs.get('wording_admin/state').faqBases, { items: { a: { qEn: 'How A?' } }, groups: {} });
  const rows = logRows(db);
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].kind, 'faq');
  assert.strictEqual(rows[0].before, null);
  const again = await faqSave(db, draft);
  assert.strictEqual(again.changed, 0);
  assert.strictEqual(logRows(db).length, 1);
});

test('a save elsewhere keeps both lists exactly as stored, fields this tool does not know included', async () => {
  const db = fakeDb();
  const faq = { hidden: ['c'], fromANewerTool: { kept: true } };
  const benefits = { hidden: ['future'], alsoNewer: 'kept' };
  db.docs.set('wording/live', { strings: { ar: {}, en: {} }, faq, benefits, somethingNewer: { kept: true }, version: 4 });
  await wording.saveStringEdits(db, FieldValue, { entry: byKey.get('premiumHeadline'), changes: { en: 'Color every day' } });
  let live = db.docs.get('wording/live');
  assert.deepStrictEqual(live.faq, faq);
  assert.deepStrictEqual(live.benefits, benefits);
  assert.deepStrictEqual(live.somethingNewer, { kept: true });
  assert.strictEqual(live.strings.en.premiumHeadline, 'Color every day');
  await wording.saveQuotes(db, FieldValue, { items: null, builtIn: [], builtInFnv: 'x' });
  await premiumSave(db, { strings: { premiumHeadline: { ar: 'عنوان' } } });
  live = db.docs.get('wording/live');
  assert.deepStrictEqual(live.faq, faq);
  assert.deepStrictEqual(live.benefits, benefits);
});

test('the built-in FAQ saved again takes the edits away', async () => {
  const db = fakeDb();
  const draft = builtInDraft();
  draft.groups[2].items[0].a.ar = 'جواب أحسن.';
  await faqSave(db, draft);
  await faqSave(db, builtInDraft());
  assert.strictEqual(db.docs.get('wording/live').faq, undefined);
  assert.strictEqual(db.docs.get('wording_admin/state').faqBases, undefined);
});

test('a bad FAQ draft writes nothing', async () => {
  const db = fakeDb();
  const draft = builtInDraft();
  draft.groups[0].items[0].q.ar = '';
  const result = await faqSave(db, draft);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(db.transactions, 0);
  assert.strictEqual(db.docs.size, 0);
});

test('the app\'s own words never block a save, even a later build\'s that break a rule here', async () => {
  const db = fakeDb();
  const odd = JSON.parse(JSON.stringify(FAQ));
  odd.items[1].aEn = 'Two parts ' + EM_DASH + ' ' + 'x'.repeat(C.MAX_ANSWER_LENGTH + 5);
  const draft = builtInDraft();
  draft.groups[0].items[1].a.en = odd.items[1].aEn;
  draft.groups[0].items[0].q.en = 'My own question?';
  const check = C.faqEditsFromDraft(odd, draft);
  assert.ok(check.ok, check.errors.join(' '));
  assert.deepStrictEqual(check.edits, { text: { a: { qEn: 'My own question?' } } });
  const result = await faqSave(db, draft, { builtIn: odd, builtInFingerprint: C.fingerprint(odd) });
  assert.ok(result.ok);
});

test('a FAQ page opened before the app\'s own FAQ changed in the code is refused, and writes nothing', async () => {
  const db = fakeDb();
  const moved = JSON.parse(JSON.stringify(FAQ));
  moved.items[0].qEn = 'How does A work now?';
  moved.items.push({ id: 'f', group: 'account', qAr: 'س؟', qEn: 'F?', aAr: 'ج.', aEn: 'F.' });
  const draft = builtInDraft();
  draft.groups[1].items.reverse();
  await assert.rejects(faqSave(db, draft, { builtIn: moved }), (e) => e.status === 409 && /changed in the code/.test(e.message));
  assert.strictEqual(db.transactions, 0);
  assert.strictEqual(db.docs.size, 0);
});

test('a FAQ page left open while another tab saved is refused, and the other save stays', async () => {
  const db = fakeDb();
  const first = builtInDraft();
  first.groups[0].items[0].q.en = 'From the first tab?';
  await faqSave(db, first);
  const stale = builtInDraft();
  stale.groups[1].items.reverse();
  await assert.rejects(faqSave(db, stale, { base: null }), (e) => e.status === 409 && /another tab/.test(e.message));
  assert.deepStrictEqual(db.docs.get('wording/live').faq, { text: { a: { qEn: 'From the first tab?' } } });
  await assert.rejects(wording.saveFaq(db, FieldValue, { builtIn: FAQ, draft: stale, builtInFingerprint: FAQ_FP }), /out of date/);
});

test('"changed in code" survives an unrelated save, and clears when it is kept', async () => {
  const db = fakeDb();
  const draft = builtInDraft();
  draft.groups[0].items[0].q.en = 'My own question?';
  await faqSave(db, draft);
  // The app's own question changes in a later build, and the page reloads.
  const moved = JSON.parse(JSON.stringify(FAQ));
  moved.items[0].qEn = 'How does A work?';
  const later = { builtIn: moved, builtInFingerprint: C.fingerprint(moved) };
  draft.groups[0].items[1].a.en = 'Another edit.';
  await faqSave(db, draft, later);
  assert.strictEqual(db.docs.get('wording_admin/state').faqBases.items.a.qEn, 'How A?');
  await faqSave(db, draft, Object.assign({ checked: ['a:qEn'] }, later));
  assert.strictEqual(db.docs.get('wording_admin/state').faqBases.items.a.qEn, 'How does A work?');
});

test('undoing a FAQ save brings back the FAQ and its record, and refuses after a later save', async () => {
  const db = fakeDb();
  const first = builtInDraft();
  first.groups[0].items[0].q.en = 'First?';
  await faqSave(db, first);
  const second = builtInDraft();
  second.groups[0].items[0].q.en = 'Second?';
  await faqSave(db, second);
  const { log } = await wording.readWording(db);
  const [newest, older] = log;
  await assert.rejects(wording.undoChange(db, FieldValue, { id: older.id, catalogByKey: byKey }), /changed again since/);
  await wording.undoChange(db, FieldValue, { id: newest.id, catalogByKey: byKey });
  assert.deepStrictEqual(db.docs.get('wording/live').faq, { text: { a: { qEn: 'First?' } } });
  assert.deepStrictEqual(db.docs.get('wording_admin/state').faqBases.items, { a: { qEn: 'How A?' } });
  const after = await wording.readWording(db);
  assert.strictEqual(after.log[0].undoOf, newest.id);
});

test('a Premium save writes strings and the list in one transaction, each with its History row', async () => {
  const db = fakeDb();
  const rows = builtInRows().reverse();
  const result = await premiumSave(db, {
    strings: { premiumHeadline: { en: 'Color, every day' }, roomsTitle: { ar: 'غرف على كيفك' } },
    rows,
  });
  assert.ok(result.ok, (result.errors || []).join(' '));
  assert.strictEqual(db.transactions, 1);
  const live = db.docs.get('wording/live');
  assert.strictEqual(live.strings.en.premiumHeadline, 'Color, every day');
  assert.strictEqual(live.strings.ar.roomsTitle, 'غرف على كيفك');
  assert.deepStrictEqual(live.benefits, { order: ['future', 'history', 'rooms', 'habits'] });
  const kinds = logRows(db).map((r) => r.kind + ':' + (r.key || '')).sort();
  assert.deepStrictEqual(kinds, ['benefits:', 'string:premiumHeadline', 'string:roomsTitle']);
});

test('a Premium tab left open never puts back words it did not change', async () => {
  const db = fakeDb();
  // The tab loads, then the Wording page edits a benefit's title.
  const loaded = liveOf(db);
  await wording.saveStringEdits(db, FieldValue, { entry: byKey.get('roomsTitle'), changes: { en: 'Rooms for everyone' } });
  // The tab only reorders its list: no strings go with it.
  const result = await wording.savePremium(db, FieldValue, {
    catalog: CATALOG,
    strings: {},
    stringsBase: {},
    benefits: builtInRows().reverse(),
    benefitsBase: loaded.benefits || null,
    builtInFingerprint: BENEFITS_FP,
  });
  assert.ok(result.ok);
  assert.strictEqual(result.changed, 1);
  assert.strictEqual(db.docs.get('wording/live').strings.en.roomsTitle, 'Rooms for everyone');
});

test('a string changed somewhere else since the page loaded refuses the whole save', async () => {
  const db = fakeDb();
  await wording.saveStringEdits(db, FieldValue, { entry: byKey.get('premiumHeadline'), changes: { en: 'From the Wording page' } });
  const result = wording.savePremium(db, FieldValue, {
    catalog: CATALOG,
    strings: { premiumHeadline: { en: 'From a stale tab' } },
    stringsBase: { premiumHeadline: { en: null } },
    benefits: builtInRows().reverse(),
    benefitsBase: null,
    builtInFingerprint: BENEFITS_FP,
  });
  await assert.rejects(result, (e) => e.status === 409 && /premiumHeadline \(English\)/.test(e.message));
  const live = db.docs.get('wording/live');
  assert.strictEqual(live.strings.en.premiumHeadline, 'From the Wording page');
  assert.strictEqual(live.benefits, undefined);
});

test('a benefit list saved elsewhere, or changed in the code, refuses the save', async () => {
  const db = fakeDb();
  await premiumSave(db, { rows: builtInRows().reverse() });
  const saved = db.docs.get('wording/live').benefits;
  await assert.rejects(premiumSave(db, { rows: builtInRows().slice(1), extra: { benefitsBase: null } }),
    (e) => e.status === 409 && /another tab/.test(e.message));
  const moved = JSON.parse(JSON.stringify(CATALOG));
  moved.benefits.items.splice(1, 0, { id: 'share', icon: 'star', titleKey: 'habitsTitle', descKey: 'habitsDesc' });
  await assert.rejects(premiumSave(db, { rows: builtInRows(), extra: { catalog: moved } }),
    (e) => e.status === 409 && /changed in the code/.test(e.message));
  assert.deepStrictEqual(db.docs.get('wording/live').benefits, saved);
});

test('a Premium save with a bad string or a bad row writes nothing', async () => {
  const db = fakeDb();
  let result = await premiumSave(db, { strings: { premiumSave: { en: 'SAVE {percent}' } } });
  assert.strictEqual(result.ok, false);
  assert.match(result.errors.join(' '), /cannot fill/);
  const rows = builtInRows();
  rows[0].icon = 'nope';
  result = await premiumSave(db, { rows });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(db.docs.size, 0);
});

test('undoing a benefit list save puts the list back and leaves the strings', async () => {
  const db = fakeDb();
  await premiumSave(db, { strings: { futureTitle: { en: 'Everything later' } }, rows: builtInRows().reverse() });
  const { log } = await wording.readWording(db);
  const listRow = log.find((r) => r.kind === 'benefits');
  await wording.undoChange(db, FieldValue, { id: listRow.id, catalogByKey: byKey });
  const live = db.docs.get('wording/live');
  assert.strictEqual(live.benefits, undefined);
  assert.strictEqual(live.strings.en.futureTitle, 'Everything later');
});

test('an id the document gives never reads a JavaScript built-in', () => {
  // The app's Dart maps have no prototype; these must resolve as unknown ids.
  const faq = C.resolveFaq(FAQ, C.parseFaqEdits({ order: [{ group: 'toString', items: ['a', 'c'] }] }));
  assert.deepStrictEqual(faq.map((g) => g.id), ['basics', 'rooms', 'account']);
  const list = C.resolveBenefits(BENEFITS, C.parseBenefitEdits({ order: ['constructor', 'habits'], icons: { habits: 'valueOf' } }));
  assert.deepStrictEqual(list.map((b) => b.id + ':' + b.icon), ['habits:grid_on', 'rooms:groups', 'history:history', 'future:auto_awesome']);
});

test('what counts as empty matches the app, next-line characters included', () => {
  const nel = String.fromCharCode(0x85);
  assert.strictEqual(C.parseFaqEdits({ hidden: [nel], text: { a: { qEn: ' ' + nel } } }), null);
  assert.deepStrictEqual(C.parseFaqEdits({ hidden: [nel + 'c' + nel] }).hidden, ['c']);
});

test('a catalog from before the FAQ and Premium pages is rebuilt', () => {
  assert.deepStrictEqual(wording.staleSources({ sources: {} }), ['(a list from before the FAQ and Premium pages)']);
  assert.deepStrictEqual(wording.staleSources({ format: 2, sources: { gone: { path: 'no/such/file.dart', fnv1a: null } } }), []);
});

// ---- The pages -----------------------------------------------------------------------

test('both pages and their scripts parse, with every hook the scripts use', () => {
  const pages = { 'faq.js': renderFaqPage(), 'premium.js': renderPremiumPage() };
  for (const file of ['kit.js', 'faq.js', 'premium.js']) {
    const source = fs.readFileSync(path.join(__dirname, '..', 'content', file), 'utf8');
    try {
      new vm.Script(source, { filename: file });
    } catch (e) {
      assert.fail(`content/${file} is not valid JavaScript: ${e.message}`);
    }
  }
  for (const [script, html] of Object.entries(pages)) {
    for (const src of ['/wording/rules.js', '/wording/content_rules.js', '/content/kit.js', '/content/' + script]) {
      assert.ok(html.includes(`src="${src}"`), `the page does not load ${src}`);
    }
    for (const id of ['banners', 'dock', 'toast']) assert.ok(html.includes(`id="${id}"`), `the page is missing #${id}`);
    const css = (html.match(/<style>([\s\S]*?)<\/style>/) || [])[1] || '';
    assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length, 'CSS braces are unbalanced');
  }
  assert.ok(pages['faq.js'].includes('id="faqApp"'));
  assert.ok(pages['premium.js'].includes('id="premiumApp"'));
  assert.ok(pages['faq.js'].includes('class="nav-item active" href="/faq"'));
  assert.ok(pages['premium.js'].includes('class="nav-item active" href="/premium"'));
  assert.ok(!CONTENT_STYLES.includes('`'), 'CONTENT_STYLES contains a backtick');
});

test('the shared script is written for the edition of the styles the pages carry', () => {
  const kit = fs.readFileSync(path.join(__dirname, '..', 'content', 'kit.js'), 'utf8');
  const styles = (CONTENT_STYLES.match(/--content-styles:\s*(\d+);/) || [])[1];
  const script = (kit.match(/const EDITION = '(\d+)';/) || [])[1];
  assert.ok(styles, 'CONTENT_STYLES names no --content-styles edition');
  assert.strictEqual(script, styles);
});

test('no em dash in the pages, their scripts, or the rules they share', () => {
  const files = [
    renderFaqPage().replace(BASE_STYLES, ''),
    renderPremiumPage().replace(BASE_STYLES, ''),
    ...['kit.js', 'faq.js', 'premium.js'].map((f) => fs.readFileSync(path.join(__dirname, '..', 'content', f), 'utf8')),
    fs.readFileSync(path.join(__dirname, '..', 'wording', 'content_rules.js'), 'utf8'),
    fs.readFileSync(path.join(__dirname, 'fixtures', 'content_cases.json'), 'utf8'),
  ];
  for (const text of files) assert.ok(!text.includes(EM_DASH));
});

test('the rules file never types an invisible or confusable mark', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'wording', 'content_rules.js'), 'utf8');
  // Harakat (U+064B to U+065F), tatweel, and the no-break space.
  const marks = new RegExp('[' + String.fromCharCode(0x064B) + '-' + String.fromCharCode(0x065F) +
    String.fromCharCode(0x0640) + String.fromCharCode(0x00A0) + ']');
  assert.ok(!marks.test(source));
  assert.ok(R.normalizeText(' x ') === 'x');
});
