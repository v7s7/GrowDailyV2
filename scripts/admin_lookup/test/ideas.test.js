'use strict';

/**
 * The Habit ideas page (lib/ideas_admin.js, wording/ideas_rules.js,
 * ideas/app.js): Add Habit's ideas and ready-made plans, stored in
 * wording/live's `ideas` and `plans`.
 *
 * The cases in fixtures/ideas_cases.json are also run by the app against
 * habit_ideas.dart, so what the page shows before Publish is what phones
 * show after it. The built-in ideas here are fixtures/habit_ideas_sample.json,
 * not the app's own file (which is still being written); the plans are read
 * out of the real habit_plans.dart, as the page reads them.
 *
 * Saves run against a small in-memory stand-in for Firestore, never the
 * real project.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const R = require('../wording/ideas_rules');
const ideasAdmin = require('../lib/ideas_admin');
const wording = require('../lib/wording');
const { renderIdeasPage } = require('../lib/ideas_page');

const FIXTURE = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'ideas_cases.json'), 'utf8'));
const SAMPLE = path.join(__dirname, 'fixtures', 'habit_ideas_sample.json');
const OPTS = { ideasPath: SAMPLE };
const EM_DASH = String.fromCharCode(0x2014);

// ---- An in-memory Firestore, just enough for lib/wording.js -----------------
// The same shape as content.test.js's: transactions land whole or not at
// all, set() replaces the document, and the log query is newest first.

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

function fakeDb(live) {
  const docs = new Map();
  if (live) docs.set(wording.LIVE_DOC, copy(live));
  let clock = Date.UTC(2026, 9, 1, 9, 0, 0);
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
  return [...db.docs.entries()].filter(([p]) => p.startsWith(wording.LOG_COLLECTION + '/')).map(([id, d]) => Object.assign({ id: id.split('/').pop() }, d));
}

// ---- The built-ins the draft tests use ---------------------------------------

const BUILT = ideasAdmin.builtIns(OPTS);
const LISTS = ideasAdmin.listsOf(BUILT);

function freshDraft(stored) {
  const d = R.draftFrom(LISTS, stored || null);
  return { ideas: d.ideas, plans: d.plans };
}

function row(draft, id) {
  return draft.ideas.find((r) => r.id === id);
}

function plan(draft, id) {
  return draft.plans.find((r) => r.id === id);
}

function newAdded(id, over) {
  return Object.assign(R.blankRow(id, 'build', 'mind'), {
    nameAr: 'دقيقة امتنان',
    nameEn: 'A minute of thanks',
    shortAr: 'تشوف الخير اللي حولك',
    shortEn: 'See the good around you',
    benefitAr: 'لما تكتب شي تحمد الله عليه، يومك يصير أخف.',
    benefitEn: 'Writing one thing you are thankful for makes the day lighter.',
    waysAr: ['اكتب شي واحد قبل النوم', 'قوله لنفسك'],
    waysEn: ['Write one thing before bed', 'Say it to yourself'],
  }, over || {});
}

// ---- The shared cases ----------------------------------------------------------

const LITE = ['id', 'type', 'category', 'nameAr', 'nameEn', 'shortAr', 'shortEn', 'benefitAr', 'benefitEn', 'waysAr', 'waysEn', 'often', 'featured'];

test('the shared cases are in the data spec\'s shape, and cover what they must', () => {
  assert.ok(FIXTURE.cases.length >= 12, 'at least twelve idea cases');
  for (const c of FIXTURE.cases) {
    assert.strictEqual(typeof c.name, 'string');
    assert.ok(Array.isArray(c.builtIn) && c.builtIn.length, c.name);
    for (const idea of c.builtIn) for (const key of LITE) assert.ok(key in idea, c.name + ': ' + idea.id + ' has ' + key);
    assert.ok('edits' in c, c.name);
    assert.ok(Array.isArray(c.expect.ids) && Array.isArray(c.expect.featured), c.name);
    assert.strictEqual(typeof c.expect.names, 'object', c.name);
  }
  const names = FIXTURE.cases.map((c) => c.name).join('\n');
  for (const topic of [/^no edits/m, /^hidden/m, /^order/m, /^featured/m, /^text: a word field/m, /^text: a source/m, /^text: ways/m,
    /^text: how often/m, /^text: times a day/m, /^text: reminder/m, /^text: limit/m, /^text: category/m, /^added: valid/m, /^added: one missing/m]) {
    assert.match(names, topic);
  }
  assert.ok(FIXTURE.planCases.length >= 4);
  for (const c of FIXTURE.planCases) {
    for (const p of c.builtIn) for (const key of ['id', 'nameAr', 'nameEn', 'descAr', 'descEn', 'catalogIds']) assert.ok(key in p, c.name);
    assert.ok(Array.isArray(c.expect.ids));
  }
  const raw = fs.readFileSync(path.join(__dirname, 'fixtures', 'ideas_cases.json'), 'utf8');
  assert.ok(!raw.includes(EM_DASH));
  assert.ok(!/\\u[0-9a-fA-F]{4}/.test(raw), 'plain JSON, letters as letters');
});

for (const c of FIXTURE.cases) {
  test(`ideas: ${c.name}`, () => {
    const built = R.parseBuiltInIdeas({ version: 1, ideas: c.builtIn });
    assert.deepStrictEqual(built.skipped, [], 'every built-in in a case reads');
    const out = R.resolveIdeas(built.ideas, c.edits);
    assert.deepStrictEqual(out.map((r) => r.idea.id), c.expect.ids, 'ids');
    assert.deepStrictEqual(out.filter((r) => r.featured).map((r) => r.idea.id), c.expect.featured, 'featured');
    for (const [id, nameAr] of Object.entries(c.expect.names)) {
      assert.strictEqual(out.find((r) => r.idea.id === id).idea.nameAr, nameAr, 'name of ' + id);
    }
    for (const [id, fields] of Object.entries(c.expect.fields || {})) {
      const json = R.toJson(out.find((r) => r.idea.id === id).idea);
      for (const [field, value] of Object.entries(fields)) {
        assert.deepStrictEqual(json[field] === undefined ? null : json[field], value, id + '.' + field);
      }
    }
  });
}

for (const c of FIXTURE.planCases) {
  test(`plans: ${c.name}`, () => {
    const out = R.resolvePlans(c.builtIn, c.edits);
    assert.deepStrictEqual(out.map((p) => p.id), c.expect.ids, 'ids');
    for (const [id, nameAr] of Object.entries(c.expect.names)) assert.strictEqual(out.find((p) => p.id === id).nameAr, nameAr);
    for (const [id, fields] of Object.entries(c.expect.fields || {})) {
      for (const [field, value] of Object.entries(fields)) assert.strictEqual(out.find((p) => p.id === id)[field], value, id + '.' + field);
    }
  });
}

test('reading is the app\'s: Dart\'s int.tryParse and trim, and the canonical forms', () => {
  assert.strictEqual(R.dartInt(' 3 '), 3);
  assert.strictEqual(R.dartInt('+3'), 3);
  assert.strictEqual(R.dartInt('0x3'), 3);
  assert.strictEqual(R.dartInt('3.0'), null);
  assert.strictEqual(R.dartInt('٣'), null);
  assert.strictEqual(R.dartTrim(String.fromCharCode(0x85) + ' x ' + String.fromCharCode(0x85)), 'x');
  assert.deepStrictEqual(R.parseOften(' weekly: 2 '), { kind: 'weekly', times: 2 });
  assert.strictEqual(R.parseOften('days:'), null);
  assert.strictEqual(R.parseOften('days:1,,4'), null);
  assert.strictEqual(R.oftenString(R.parseOften('days:7,1,1')), 'days:1,7');
  assert.strictEqual(R.readReminder('time:7:05'), 'time:07:05');
  assert.strictEqual(R.readReminder('prayer:fajr '), null);
  assert.deepStrictEqual(R.readLimit({ amount: 2, unit: 'cups' }), { amount: 2, unit: 'cups' });
  assert.strictEqual(R.readLimit({ amount: 2.5, unit: 'cups' }), null);
});

// ---- The plans, out of habit_plans.dart ------------------------------------------

test('every plan is read out of habit_plans.dart, in the code\'s order', () => {
  const plans = BUILT.plans;
  assert.strictEqual(BUILT.plansError, null);
  assert.deepStrictEqual(plans.map((p) => p.id), [
    'morning_warrior', 'deen_essentials', 'night_routine', 'discipline_30', 'deep_focus', 'marriage_prep', 'five_daily_prayers',
  ]);
  const morning = plans[0];
  assert.strictEqual(morning.nameEn, 'Morning Routine');
  assert.strictEqual(morning.nameAr, 'روتين الصباح');
  assert.deepStrictEqual(morning.catalogIds, ['wake_early', 'morning_athkar', 'quran_daily_page', 'no_phone_morning']);
  // The comment above marriage_prep quotes «the Prophet's ﷺ» and is not read as a value.
  const marriage = plans.find((p) => p.id === 'marriage_prep');
  assert.strictEqual(marriage.nameEn, 'Marriage Preparation');
  assert.deepStrictEqual(plans[6].catalogIds, ['prayer_fajr', 'prayer_dhuhr', 'prayer_asr', 'prayer_maghrib', 'prayer_isha']);
  for (const p of plans) {
    for (const f of ['nameAr', 'nameEn', 'descAr', 'descEn']) assert.ok(p[f].trim(), p.id + ' ' + f);
  }
  // The plans' habits have names from the preset catalog.
  assert.deepStrictEqual(BUILT.habits.morning_athkar, { nameAr: 'أذكار الصباح', nameEn: 'Morning Athkar' });
});

test('a plan file that lost its shape is refused, never guessed', () => {
  const source = fs.readFileSync(ideasAdmin.PLANS_DART, 'utf8');
  const refused = (broken, pattern) => {
    assert.notStrictEqual(broken, source);
    assert.throws(() => ideasAdmin.parsePlansDart(broken), (e) =>
      e instanceof ideasAdmin.IdeasInputError && e.status === 500 && pattern.test(e.message));
  };
  refused(source.replace('const habitPlans = <HabitPlan>[', 'const habitPlanList = <HabitPlan>['), /const habitPlans = <HabitPlan>\[\.\.\.\]/);
  refused(source.replace("    nameAr: 'روتين الليل',\n", ''), /plan night_routine's nameAr as a plain string/);
  refused(source.replace("nameEn: 'Deep Focus',", 'nameEn: kDeepFocusName,'), /plan deep_focus's nameEn/);
  refused(source.replace("id: 'deep_focus',", "id: 'deep_${x}',"), /plan 5's id/);
  refused(source.replace("catalogIds: ['deep_work_block', 'inbox_zero', 'daily_planning'],", 'catalogIds: kFocusIds,'), /plan deep_focus's catalogIds/);
  refused(source.replace("id: 'deep_focus',", "id: 'night_routine',"), /night_routine is used twice/);
  refused(source.replace("nameAr: 'تركيز عميق',", "nameAr: 'تركيز عميق,"), /string that runs past the end of its line/);
  refused(source.replace(/const habitPlans = <HabitPlan>\[[\s\S]*?\n\];/, 'const habitPlans = <HabitPlan>[];'), /at least one plan/);
  refused(source.replace(/const habitPlans = <HabitPlan>\[/, 'const habitPlans = kPlans;'), /not a list literal/);
});

test('the plan reader takes Dart\'s other string forms and comments', () => {
  const source = [
    '/* a block /* nested */ comment with \'quotes\' */',
    'final List<HabitPlan> habitPlans = const [',
    '  // One plan\'s comment, "with quotes".',
    '  const HabitPlan(',
    '    id: "one",',
    "    nameEn: 'It\\'s ' 'joined',",
    "    nameAr: r'خام\\n',",
    "    descEn: '''Three",
    "lines''',",
    "    descAr: 'سطر \\" + "u0041',",
    '    color: Color(0xFF4A9EFF),',
    '    icon: Icons.wb_twilight,',
    "    catalogIds: <String>['a', \"b\"],",
    '  ),',
    '];',
  ].join('\n');
  const [p] = ideasAdmin.parsePlansDart(source);
  assert.deepStrictEqual(p, {
    id: 'one',
    nameAr: 'خام\\n',
    nameEn: 'It\'s joined',
    descAr: 'سطر A',
    descEn: 'Three\nlines',
    catalogIds: ['a', 'b'],
  });
});

// ---- The built-in ideas file ---------------------------------------------------------

test('the sample file reads whole, with notes for what breaks the data spec', () => {
  assert.strictEqual(BUILT.ideasMissing, false);
  assert.strictEqual(BUILT.ideasError, null);
  assert.deepStrictEqual(BUILT.ideas.map((i) => i.id), ['daily_charity', 'drink_water', 'less_coffee', 'read_book']);
  assert.deepStrictEqual(BUILT.ideaSkipped, []);
  assert.deepStrictEqual(BUILT.ideaNotes, ['Idea “Drink water” (drink_water): card line in English is 65 characters, 60 at most.']);
  const water = BUILT.ideas[1];
  assert.strictEqual(water.timesPerDay, 8);
  assert.strictEqual(BUILT.ideas[2].limit.unit, 'cups');
  assert.strictEqual(BUILT.ideasFile, 'scripts/admin_lookup/test/fixtures/habit_ideas_sample.json');
});

function tempFile(name, text) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ideas-test-'));
  const file = path.join(dir, name);
  if (text !== null) fs.writeFileSync(file, text);
  return file;
}

test('a missing ideas file says so, and the plans still read', () => {
  const b = ideasAdmin.builtIns({ ideasPath: tempFile('habit_ideas.json', null) });
  assert.strictEqual(b.ideasMissing, true);
  assert.strictEqual(b.ideas, null);
  assert.strictEqual(b.plans.length, 7);
  const draft = R.draftFrom(ideasAdmin.listsOf(b), { ideas: { hidden: ['x'] }, plans: null });
  assert.strictEqual(draft.ideas, null, 'nothing to edit, so nothing can be sent');
});

test('a file that is not JSON, or has no ideas list, says why', () => {
  const notJson = ideasAdmin.builtIns({ ideasPath: tempFile('habit_ideas.json', '{ "version": 1, ') });
  assert.strictEqual(notJson.ideas, null);
  assert.match(notJson.ideasError, /is not valid JSON/);
  const noList = ideasAdmin.builtIns({ ideasPath: tempFile('habit_ideas.json', '{ "version": 1, "items": [] }') });
  assert.strictEqual(noList.ideas, null);
  assert.match(noList.ideasError, /no "ideas" list/);
});

test('entries the app cannot read are skipped, and named with why', () => {
  const good = JSON.parse(fs.readFileSync(SAMPLE, 'utf8')).ideas[3];
  const file = tempFile('habit_ideas.json', JSON.stringify({
    version: 2,
    ideas: [good, Object.assign({}, good, { nameEn: '' }), Object.assign({}, good, { id: 'a-taken' }), good, 'text',
      Object.assign({}, good, { id: 'quran_cat', category: 'quran' })],
  }));
  const b = ideasAdmin.builtIns({ ideasPath: file });
  assert.deepStrictEqual(b.ideas.map((i) => i.id), ['read_book']);
  assert.deepStrictEqual(b.ideaSkipped.map((s) => s.label), ['read_book', 'a-taken', 'read_book', 'entry 5', 'quran_cat']);
  assert.match(b.ideaSkipped[0].reasons.join(), /nameEn is missing/);
  assert.match(b.ideaSkipped[2].reasons.join(), /used by an earlier entry/);
  assert.match(b.ideaSkipped[4].reasons.join(), /category is not one of the nine/);
  assert.match(b.ideaNotes[0], /version 2/);
});

test('the app\'s own habit_ideas.json, when it is there, reads whole', (t) => {
  if (!fs.existsSync(ideasAdmin.IDEAS_JSON)) {
    t.skip('assets/data/habit_ideas.json is not in the repo yet');
    return;
  }
  const b = ideasAdmin.builtIns();
  assert.strictEqual(b.ideasError, null);
  assert.deepStrictEqual(b.ideaSkipped, [], 'every idea in the file reads the app\'s way');
  assert.ok(b.ideas.length > 0);
});

// ---- The draft, checked and turned into edits ----------------------------------------

test('an untouched page stores nothing and finds nothing wrong', () => {
  const draft = freshDraft();
  const check = R.checkDraft(LISTS, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.edits, { ideas: null, plans: null });
  assert.strictEqual(draft.ideas.length, 4);
  assert.strictEqual(draft.plans.length, 7);
  assert.deepStrictEqual(R.checkDraft(LISTS, {}).edits, { ideas: undefined, plans: undefined }, 'a part not sent is left alone');
});

test('only what differs from the built-ins is stored, and it reads back as the same page', () => {
  const draft = freshDraft();
  // Ideas: a word, a source taken away, a schedule with times a day, a
  // reminder taken away, a limit, the stars, a switch, a new idea, and a move.
  row(draft, 'daily_charity').nameAr = '  صدقة كل يوم ';
  row(draft, 'daily_charity').sourceEn = '';
  row(draft, 'daily_charity').featured = false;
  row(draft, 'drink_water').often = 'weekly:5';
  row(draft, 'drink_water').timesPerDay = 1;
  row(draft, 'read_book').reminder = '';
  row(draft, 'read_book').featured = true;
  row(draft, 'read_book').category = 'focus';
  row(draft, 'less_coffee').limit = { amount: 1, unit: 'cups' };
  row(draft, 'less_coffee').shown = false;
  row(draft, 'read_book').waysEn = ['Ten pages before bed', 'Keep the book by your pillow'];
  const fresh = newAdded('a-k3j9x2m1', { featured: true, reminder: 'time:06:30', often: 'days:1,4' });
  draft.ideas.splice(1, 0, fresh);
  // Plans: a rename, a switch and a move.
  plan(draft, 'deep_focus').nameEn = 'Deep Work';
  plan(draft, 'marriage_prep').shown = false;
  const [prayers] = draft.plans.splice(6, 1);
  draft.plans.unshift(prayers);

  const check = R.checkDraft(LISTS, draft);
  assert.deepStrictEqual(check.errors, []);
  assert.deepStrictEqual(check.edits.ideas, {
    order: ['daily_charity', 'a-k3j9x2m1', 'drink_water', 'less_coffee', 'read_book'],
    hidden: ['less_coffee'],
    featured: { daily_charity: false, read_book: true },
    text: {
      daily_charity: { nameAr: 'صدقة كل يوم', sourceEn: null },
      drink_water: { often: 'weekly:5', timesPerDay: null },
      less_coffee: { limit: { amount: 1, unit: 'cups' } },
      read_book: { waysEn: ['Ten pages before bed', 'Keep the book by your pillow'], category: 'focus', reminder: null },
    },
    added: {
      'a-k3j9x2m1': {
        id: 'a-k3j9x2m1',
        type: 'build',
        category: 'mind',
        nameAr: 'دقيقة امتنان',
        nameEn: 'A minute of thanks',
        shortAr: 'تشوف الخير اللي حولك',
        shortEn: 'See the good around you',
        benefitAr: 'لما تكتب شي تحمد الله عليه، يومك يصير أخف.',
        benefitEn: 'Writing one thing you are thankful for makes the day lighter.',
        waysAr: ['اكتب شي واحد قبل النوم', 'قوله لنفسك'],
        waysEn: ['Write one thing before bed', 'Say it to yourself'],
        often: 'days:1,4',
        reminder: 'time:06:30',
        featured: true,
      },
    },
  });
  assert.deepStrictEqual(check.edits.plans, {
    order: ['five_daily_prayers', 'morning_warrior', 'deen_essentials', 'night_routine', 'discipline_30', 'deep_focus', 'marriage_prep'],
    hidden: ['marriage_prep'],
    text: { deep_focus: { nameEn: 'Deep Work' } },
  });

  // What phones show from it, and the page drawn again from it.
  const shown = R.resolveIdeas(BUILT.ideas, check.edits.ideas);
  assert.deepStrictEqual(shown.map((r) => r.idea.id), ['daily_charity', 'a-k3j9x2m1', 'drink_water', 'read_book']);
  assert.deepStrictEqual(shown.filter((r) => r.featured).map((r) => r.idea.id), ['a-k3j9x2m1', 'drink_water', 'read_book']);
  assert.strictEqual(shown[2].idea.timesPerDay, 1);
  assert.strictEqual(shown[0].idea.sourceEn, null);
  const again = freshDraft(check.edits);
  row(draft, 'daily_charity').nameAr = 'صدقة كل يوم';
  assert.deepStrictEqual(again.ideas, draft.ideas);
  assert.deepStrictEqual(again.plans, draft.plans);
  assert.deepStrictEqual(R.checkDraft(LISTS, again).edits, check.edits, 'saving it again stores the same');
});

test('an order phones would show anyway is not stored; added ideas fall in by id', () => {
  const draft = freshDraft();
  draft.ideas.push(newAdded('a-zzzz1111'), newAdded('a-bbbb2222'));
  let edits = R.checkDraft(LISTS, draft).edits.ideas;
  assert.deepStrictEqual(edits.order, ['daily_charity', 'drink_water', 'less_coffee', 'read_book', 'a-zzzz1111', 'a-bbbb2222'],
    'not by id, so the order is kept');
  const b = row(draft, 'a-bbbb2222');
  const z = row(draft, 'a-zzzz1111');
  draft.ideas.splice(4, 2, b, z);
  edits = R.checkDraft(LISTS, draft).edits.ideas;
  assert.strictEqual(edits.order, undefined, 'built-ins in file order, then added by id: the natural order');
  assert.deepStrictEqual(Object.keys(edits.added).sort(), ['a-bbbb2222', 'a-zzzz1111']);
  assert.deepStrictEqual(R.resolveIdeas(BUILT.ideas, edits).map((r) => r.idea.id).slice(4), ['a-bbbb2222', 'a-zzzz1111']);
});

test('a hidden idea keeps its place in a stored order and comes back to it', () => {
  const draft = freshDraft();
  const [book] = draft.ideas.splice(3, 1);
  draft.ideas.unshift(book);
  row(draft, 'drink_water').shown = false;
  const edits = R.checkDraft(LISTS, draft).edits.ideas;
  assert.deepStrictEqual(edits.order, ['read_book', 'daily_charity', 'drink_water', 'less_coffee']);
  const page = freshDraft({ ideas: edits });
  assert.deepStrictEqual(page.ideas.map((r) => [r.id, r.shown]), [
    ['read_book', true], ['daily_charity', true], ['drink_water', false], ['less_coffee', true],
  ]);
});

test('a draft the app would not take is refused, field by field', () => {
  const draft = freshDraft();
  draft.ideas.push(Object.assign(R.blankRow('a-empty001', 'build', 'faith'), { featured: false }));
  const bad = newAdded('a-bad00001', {
    nameAr: 'ا'.repeat(33),
    shortEn: 'One line ' + EM_DASH + ' then more',
    benefitEn: 'Great!',
    waysEn: ['Only one'],
    often: 'weekly:9',
    timesPerDay: 3,
    reminder: 'time:7:30',
    limit: { amount: 2, unit: 'cups' },
  });
  draft.ideas.push(bad);
  draft.ideas.push(newAdded('A-Upper'));
  draft.ideas.push(newAdded('a-bad00001'));
  row(draft, 'drink_water').timesPerDay = 'many';
  row(draft, 'read_book').type = 'quit';
  draft.ideas = draft.ideas.filter((r) => r.id !== 'less_coffee');
  const check = R.checkDraft(LISTS, draft);
  const says = (re) => assert.ok(check.errors.some((e) => re.test(e)), 'expected an error like ' + re + ' in\n' + check.errors.join('\n'));
  says(/“a-empty001”: name in arabic is empty/i);
  says(/card line in english is empty/i);
  says(/name in arabic is 33 characters, 32 at most/i);
  says(/em dash/);
  says(/exclamation mark/);
  says(/Arabic has 2 ways and English 1/);
  says(/not one the app knows \("weekly:9"\)/);
  says(/Times a day goes only with a daily habit to build/i);
  says(/24-hour time like 07:30/);
  says(/A limit goes only with a habit to quit/i);
  says(/id the app does not know \(A-Upper\)/);
  says(/is in the list twice/);
  says(/Times a day is a whole number from 1 to 12/i);
  says(/keeps its type/);
  says(/“Less coffee” from the app is missing/);
  assert.deepStrictEqual(check.edits, { ideas: null, plans: null }, 'nothing is stored from a draft with an error');
});

test('a built-in\'s own words never block a save; the same words typed again do not either', () => {
  const draft = freshDraft();
  // drink_water's English card line is 65 characters in the file.
  assert.deepStrictEqual(R.checkDraft(LISTS, draft).errors, []);
  row(draft, 'drink_water').shortAr = 'الماء طول اليوم';
  assert.deepStrictEqual(R.checkDraft(LISTS, draft).errors, [], 'another field changed: the long line is still the app\'s');
  row(draft, 'drink_water').shortEn += ' too';
  assert.strictEqual(R.checkDraft(LISTS, draft).errors.length, 1);
  row(draft, 'drink_water').shortEn = BUILT.ideas[1].shortEn + '   ';
  const edits = R.checkDraft(LISTS, draft).edits.ideas;
  assert.deepStrictEqual(edits.text.drink_water, { shortAr: 'الماء طول اليوم' }, 'trailing spaces are the same words');
});

test('warnings: the house style, a source in one language, too many stars in a category', () => {
  const draft = freshDraft();
  row(draft, 'read_book').shortAr = 'هذي الصفحات تخليك بطل';
  row(draft, 'read_book').sourceAr = 'رواه مسلم';
  row(draft, 'less_coffee').benefitAr = 'القهوة يعالج الصداع.';
  row(draft, 'less_coffee').featured = true;
  draft.ideas.push(newAdded('a-heal0001', { category: 'health', featured: true, benefitEn: 'It heals you.' }));
  const check = R.checkDraft(LISTS, draft);
  assert.deepStrictEqual(check.errors, []);
  const has = (re) => assert.ok(check.warnings.some((w) => re.test(w)), 'expected a warning like ' + re + ' in\n' + check.warnings.join('\n'));
  has(/هذه, not هذي/);
  has(/no praise of the person/);
  has(/no medical promises/);
  has(/a source is given in one language only/i);
  assert.ok(!check.warnings.some((w) => /^Health, /.test(w)), 'two stars in Health (one each side) are fine');
});

test('more than two stars in a category on one side is a warning', () => {
  const draft = freshDraft();
  draft.ideas.push(newAdded('a-heal0001', { category: 'health', featured: true }), newAdded('a-heal0002', { category: 'health', featured: true }));
  const warnings = R.checkDraft(LISTS, draft).warnings;
  assert.ok(warnings.some((w) => /^Health, Build: 3 featured ideas/.test(w)), warnings.join('\n'));
});

test('plans: words are checked, an unknown plan is refused, every plan must stay', () => {
  const draft = freshDraft();
  plan(draft, 'night_routine').nameAr = 'ر'.repeat(41);
  plan(draft, 'night_routine').descEn = '';
  draft.plans.push({ id: 'new_plan', shown: true, nameAr: 'خطة', nameEn: 'Plan', descAr: 'خطة', descEn: 'Plan' });
  draft.plans = draft.plans.filter((p) => p.id !== 'deep_focus');
  const check = R.checkDraft(LISTS, { plans: draft.plans });
  assert.strictEqual(check.errors.length, 4, check.errors.join('\n'));
  assert.ok(check.errors.some((e) => /name in arabic is 41 characters, 40 at most/i.test(e)));
  assert.ok(check.errors.some((e) => /description in English is empty/i.test(e)));
  assert.ok(check.errors.some((e) => /not a plan the app has \(new_plan\)/.test(e)));
  assert.ok(check.errors.some((e) => /“Deep Focus” is missing/.test(e)));
  const all = freshDraft();
  all.plans.forEach((p) => { p.shown = false; });
  assert.ok(R.checkDraft(LISTS, { plans: all.plans }).warnings.some((w) => /Every plan is hidden/.test(w)));
});

test('stored edits phones cannot use are named on the page and left out of the draft', () => {
  const d = R.draftFrom(LISTS, { ideas: { added: { 'a-broken1': { nameAr: 'x' }, plain: newAdded('x') }, text: { gone_idea: { nameAr: 'x' } } } });
  assert.strictEqual(d.ideas.length, 4);
  assert.strictEqual(d.notes.length, 3, d.notes.join('\n'));
  assert.match(d.notes.join('\n'), /a-broken1 is stored but phones cannot use it \(type is not/);
  assert.match(d.notes.join('\n'), /plain is stored but phones cannot use it \(its id does not start "a-"\)/);
  assert.match(d.notes.join('\n'), /gone_idea, an idea the app does not have/);
});

test('History words: what one publish changed', () => {
  assert.strictEqual(R.describeChange({ ideas: null, plans: null }, { ideas: null, plans: null }), 'No change phones would see.');
  assert.strictEqual(R.describeChange(
    { ideas: { hidden: ['a'], text: { b: { nameAr: 'x' } }, added: { 'a-1': {} } }, plans: null },
    { ideas: { hidden: ['c'], text: { b: { nameAr: 'y' }, d: { nameEn: 'z' } }, added: { 'a-2': {} }, featured: { e: true }, order: ['c'] }, plans: { hidden: ['p'], text: { q: { nameAr: 'x' } } } }),
  'Ideas: 2 edited, 1 added, 1 deleted, 1 hidden, 1 shown again, 1 star changed, order changed. Plans: 1 edited, 1 hidden.');
});

// ---- Saving ------------------------------------------------------------------------------

const OTHER_FIELDS = {
  strings: { ar: { signIn: 'دخول' }, en: {} },
  faq: { order: [{ group: 'basics', items: ['a'] }] },
  version: 7,
  somethingNewer: { keep: true },
  pet: { praiseEverySeconds: 15 },
  splash: { minShowMs: 2000 },
};

function publish(db, draft, extra) {
  return ideasAdmin.saveIdeas(db, FieldValue, Object.assign({
    draft,
    base: { ideas: null, plans: null },
    builtInFingerprint: ideasAdmin.fingerprintOf(BUILT),
  }, extra || {}), OPTS);
}

test('a publish writes ideas and plans, bumps the version, logs it, and keeps every other field', async () => {
  const db = fakeDb(OTHER_FIELDS);
  const draft = freshDraft();
  row(draft, 'read_book').shown = false;
  plan(draft, 'deep_focus').nameEn = 'Deep Work';
  const result = await publish(db, draft);
  assert.deepStrictEqual(result, { ok: true, errors: [], warnings: [], changed: true });
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.ideas, { hidden: ['read_book'] });
  assert.deepStrictEqual(doc.plans, { text: { deep_focus: { nameEn: 'Deep Work' } } });
  assert.strictEqual(doc.version, 8);
  for (const key of ['strings', 'faq', 'somethingNewer', 'pet', 'splash']) assert.deepStrictEqual(doc[key], OTHER_FIELDS[key], key);
  const log = logRows(db);
  assert.strictEqual(log.length, 1);
  assert.strictEqual(log[0].kind, 'ideas');
  assert.deepStrictEqual(log[0].before, { ideas: null, plans: null });
  assert.deepStrictEqual(log[0].after, { ideas: { hidden: ['read_book'] }, plans: { text: { deep_focus: { nameEn: 'Deep Work' } } } });
  const read = await ideasAdmin.readIdeas(db, OPTS);
  assert.deepStrictEqual(read.stored, { ideas: doc.ideas, plans: doc.plans });
  assert.strictEqual(read.log.length, 1);
  assert.strictEqual(read.fingerprint, ideasAdmin.fingerprintOf(BUILT));
});

test('publishing only the plans leaves the stored ideas exactly as stored, unknown parts too', async () => {
  const storedIdeas = { hidden: ['read_book'], laterField: { x: 1 } };
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { ideas: storedIdeas }));
  const draft = freshDraft({ ideas: storedIdeas });
  plan(draft, 'night_routine').shown = false;
  const result = await publish(db, { plans: draft.plans }, { base: { ideas: storedIdeas, plans: null } });
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.ideas, storedIdeas);
  assert.deepStrictEqual(doc.plans, { hidden: ['night_routine'] });
});

test('going back to the built-ins removes both fields', async () => {
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { ideas: { hidden: ['read_book'] }, plans: { hidden: ['deep_focus'] } }));
  const draft = freshDraft();
  const result = await publish(db, draft, { base: { ideas: { hidden: ['read_book'] }, plans: { hidden: ['deep_focus'] } } });
  assert.strictEqual(result.changed, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.ok(!('ideas' in doc) && !('plans' in doc));
  assert.strictEqual(doc.version, 8);
});

test('publishing what is stored already writes nothing', async () => {
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { ideas: { hidden: ['read_book'] } }));
  const draft = freshDraft({ ideas: { hidden: ['read_book'] } });
  const result = await publish(db, draft, { base: { ideas: { hidden: ['read_book'] }, plans: null } });
  assert.strictEqual(result.changed, false);
  assert.strictEqual(db.docs.get(wording.LIVE_DOC).version, 7);
  assert.strictEqual(logRows(db).length, 0);
});

test('a page older than the stored edits is refused and writes nothing', async () => {
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { plans: { hidden: ['deep_focus'] } }));
  const draft = freshDraft();
  row(draft, 'read_book').shown = false;
  await assert.rejects(publish(db, { ideas: draft.ideas }), (e) => e instanceof ideasAdmin.IdeasInputError && e.status === 409 && /another tab/.test(e.message));
  await assert.rejects(publish(db, { ideas: draft.ideas }, { base: undefined }), (e) => e.status === 409);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.strictEqual(doc.ideas, undefined);
  assert.strictEqual(doc.version, 7);
});

test('a page drawn from other built-in lists is refused', async () => {
  const db = fakeDb(OTHER_FIELDS);
  const draft = freshDraft();
  row(draft, 'read_book').shown = false;
  await assert.rejects(publish(db, draft, { builtInFingerprint: 'deadbeef' }),
    (e) => e.status === 409 && /changed in the repo/.test(e.message));
  assert.strictEqual(db.transactions, 0);
});

test('a draft with an error, or with nothing in it, writes nothing', async () => {
  const db = fakeDb(OTHER_FIELDS);
  const draft = freshDraft();
  row(draft, 'read_book').nameEn = '';
  const result = await publish(db, draft);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.errors.length, 1);
  assert.match(result.errors[0], /name in English is empty/);
  await assert.rejects(publish(db, {}), (e) => e.status === 400 && /Nothing to publish/.test(e.message));
  assert.strictEqual(db.transactions, 0);
});

test('with the ideas file missing the ideas cannot be published, the plans can', async () => {
  const missing = { ideasPath: path.join(os.tmpdir(), 'no-such-dir-' + process.pid, 'habit_ideas.json') };
  const b = ideasAdmin.builtIns(missing);
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { ideas: { hidden: ['read_book'] } }));
  const draft = freshDraft();
  const call = (d) => ideasAdmin.saveIdeas(db, FieldValue, {
    draft: d, base: { ideas: { hidden: ['read_book'] }, plans: null }, builtInFingerprint: ideasAdmin.fingerprintOf(b),
  }, missing);
  const refused = await call({ ideas: draft.ideas });
  assert.strictEqual(refused.ok, false);
  assert.match(refused.errors[0], /built-in ideas could not be read/);
  plan(draft, 'deep_focus').shown = false;
  const ok = await call({ plans: draft.plans });
  assert.strictEqual(ok.changed, true);
  assert.deepStrictEqual(db.docs.get(wording.LIVE_DOC).ideas, { hidden: ['read_book'] }, 'the stored ideas are kept');
});

test('Undo puts back what a publish changed, refuses when it changed again, and only undoes its own rows', async () => {
  const db = fakeDb(OTHER_FIELDS);
  const first = freshDraft();
  row(first, 'read_book').shown = false;
  await publish(db, first);
  const second = freshDraft({ ideas: { hidden: ['read_book'] } });
  plan(second, 'deep_focus').shown = false;
  await publish(db, { plans: second.plans }, { base: { ideas: { hidden: ['read_book'] }, plans: null } });
  const [older, newer] = logRows(db).sort((a, b) => a.at.date - b.at.date);

  await assert.rejects(wording.undoChange(db, FieldValue, { id: older.id, catalogByKey: new Map(), onlyKind: 'ideas' }), /changed again since/);
  await wording.undoChange(db, FieldValue, { id: newer.id, catalogByKey: new Map(), onlyKind: 'ideas' });
  let doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.ideas, { hidden: ['read_book'] });
  assert.strictEqual(doc.plans, undefined);
  await wording.undoChange(db, FieldValue, { id: older.id, catalogByKey: new Map(), onlyKind: 'ideas' });
  doc = db.docs.get(wording.LIVE_DOC);
  assert.ok(!('ideas' in doc) && !('plans' in doc));
  assert.strictEqual(doc.version, 11);
  assert.deepStrictEqual(doc.splash, OTHER_FIELDS.splash);

  const read = await ideasAdmin.readIdeas(db, OPTS);
  assert.strictEqual(read.log.length, 4);
  assert.ok(read.log.filter((r) => r.undoOf).length === 2);

  // A string's row cannot be undone from this page.
  const signIn = { key: 'signIn', editable: true, ar: 'تسجيل الدخول', en: 'Sign in', tokensAr: [], tokensEn: [] };
  await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  const stringRow = logRows(db).find((r) => r.kind === 'string');
  await assert.rejects(wording.undoChange(db, FieldValue, { id: stringRow.id, catalogByKey: new Map(), onlyKind: 'ideas' }), /not one this page can undo/);
});

test('a Wording save keeps the ideas and plans', async () => {
  const db = fakeDb(Object.assign({}, OTHER_FIELDS, { ideas: { hidden: ['read_book'] }, plans: { order: ['deep_focus'] } }));
  const signIn = { key: 'signIn', editable: true, ar: 'تسجيل الدخول', en: 'Sign in', tokensAr: [], tokensEn: [] };
  const result = await wording.saveStringEdits(db, FieldValue, { entry: signIn, changes: { ar: 'ادخل' } });
  assert.strictEqual(result.ok, true);
  const doc = db.docs.get(wording.LIVE_DOC);
  assert.deepStrictEqual(doc.ideas, { hidden: ['read_book'] });
  assert.deepStrictEqual(doc.plans, { order: ['deep_focus'] });
});

// ---- The page ------------------------------------------------------------------------------

test('the page loads its rules before its script, and neither is inline', () => {
  const html = renderIdeasPage({ projectId: 'demo' });
  const rules = html.indexOf('<script src="/wording/rules.js">');
  const ideasRules = html.indexOf('<script src="/wording/ideas_rules.js">');
  const app = html.indexOf('<script src="/ideas/app.js">');
  assert.ok(rules > 0 && ideasRules > rules && app > ideasRules);
  const inline = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  for (const body of inline) {
    assert.ok(!/IdeasRules|\/api\/ideas/.test(body));
    new vm.Script(body);
  }
  assert.ok(html.includes('class="nav-item active" href="/ideas"'), 'the sidebar marks the page');
  assert.ok(html.indexOf('href="/splash"') < html.indexOf('href="/ideas"'), 'the item follows Splash');
  assert.ok(html.includes('id="viewIdeas"') && html.includes('id="banners"') && html.includes('id="toast"'));
  const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length);
});

test('the page\'s browser files parse, hold no em dash, and agree on the edition', () => {
  for (const file of ['ideas/app.js', 'wording/ideas_rules.js', 'lib/ideas_page.js', 'lib/ideas_admin.js', 'test/ideas.test.js',
    'test/fixtures/ideas_cases.json', 'test/fixtures/habit_ideas_sample.json']) {
    const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
    assert.ok(!source.includes(EM_DASH), file);
    if (file.endsWith('app.js') || file.includes('ideas_rules')) new vm.Script(source, { filename: file });
  }
  const app = fs.readFileSync(path.join(__dirname, '..', 'ideas', 'app.js'), 'utf8');
  const edition = app.match(/const EDITION = '(\d+)'/)[1];
  assert.ok(renderIdeasPage({}).includes(`--ideas-styles: '${edition}'`));
  for (const id of ['viewIdeas', 'banners', 'toast']) assert.ok(app.includes("$('" + id + "')"), id);
  // The rules run in a browser as they do here: a window with WordingRules.
  const sandbox = { window: {}, self: undefined, TextEncoder };
  sandbox.self = sandbox.window;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'wording', 'rules.js'), 'utf8'), sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'wording', 'ideas_rules.js'), 'utf8'), sandbox);
  const BrowserRules = sandbox.window.IdeasRules;
  assert.ok(BrowserRules && typeof BrowserRules.checkDraft === 'function');
  assert.strictEqual(BrowserRules.fingerprint(LISTS), ideasAdmin.fingerprintOf(BUILT), 'the page and the server agree on the fingerprint');
});

test('the Wording page\'s History knows a Habit ideas row', () => {
  const app = fs.readFileSync(path.join(__dirname, '..', 'wording', 'app.js'), 'utf8');
  assert.match(app, /row\.kind === 'ideas'/);
  assert.match(app, /href: '\/ideas'/);
});
