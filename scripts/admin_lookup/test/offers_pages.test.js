'use strict';

/**
 * The Sale and Creators pages themselves: they render inside the control-room
 * frame, load their own scripts, the scripts parse, every element a script
 * reaches for by id is on its page, and the two rule files run in a browser
 * as well as in Node.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const { renderSalePage } = require('../lib/sale_page');
const { renderCreatorsPage } = require('../lib/creators_page');
const { OFFERS_STYLES } = require('../lib/offers_styles');
const { FILES } = require('../lib/offers_routes');
const { BASE_STYLES } = require('../lib/render');

const ROOT = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');
const EM_DASH = String.fromCharCode(0x2014);

const PAGES = [
  { name: 'Sale', html: renderSalePage({ projectId: 'grow-daily-test' }), app: 'sale/app.js', rules: 'lib/sale_rules.js', src: ['/sale/rules.js', '/sale/app.js'] },
  { name: 'Creators', html: renderCreatorsPage({ projectId: 'grow-daily-test' }), app: 'creators/app.js', rules: 'lib/creators.js', src: ['/creators/rules.js', '/creators/app.js'] },
];

test('each page loads its rules, then its script, then the frame\'s script', () => {
  for (const p of PAGES) {
    const at = (s) => p.html.indexOf('src="' + s + '"');
    assert.ok(at(p.src[0]) > 0, p.name + ' does not load ' + p.src[0]);
    assert.ok(at(p.src[1]) > at(p.src[0]), p.name + ' loads its script before its rules');
    assert.ok(at('/static/shell.js') > at(p.src[1]), p.name + ' does not load the frame script last');
    assert.ok(!/<script>[\s\S]*?<\/script>/.test(p.html.replace(/<script>\(function\(\)\{try\{var t=localStorage[\s\S]*?<\/script>/, '')),
      p.name + ' has an inline script besides the theme boot');
  }
});

test('every browser file the pages load is served by name and parses', () => {
  for (const [route, file] of Object.entries(FILES)) {
    assert.ok(fs.existsSync(file), route + ' points at a missing file');
    const source = fs.readFileSync(file, 'utf8');
    try {
      new vm.Script(source, { filename: route });
    } catch (e) {
      assert.fail(route + ' is not valid JavaScript: ' + e.message);
    }
  }
  for (const p of PAGES) {
    for (const src of p.src) assert.ok(FILES[src], p.name + ' loads ' + src + ', which no route serves');
  }
});

test('every element a script reaches for by id is on its page', () => {
  for (const p of PAGES) {
    const source = read(p.app);
    const ids = new Set();
    const re = /\$\('([A-Za-z0-9_-]+)'\)/g;
    let m;
    while ((m = re.exec(source)) !== null) ids.add(m[1]);
    assert.ok(ids.size > 10, p.name + ': expected the script to bind to its page');
    for (const id of ids) assert.ok(p.html.includes('id="' + id + '"'), p.name + ' page is missing #' + id);
  }
});

test('the rule files run in a browser: they set a global and work there', () => {
  const sale = { self: {} };
  vm.runInNewContext(read('lib/sale_rules.js'), sale);
  const R = sale.self.SaleRules;
  assert.ok(R && typeof R.checkSale === 'function');
  const r = R.checkSale(
    { nameAr: 'عرض', nameEn: 'Sale', startsAtMs: R.bahrainMs('2027-03-01', '00:00'), endsAtMs: R.bahrainMs('2027-03-05', '23:59') },
    { fullPriceSinceMs: R.bahrainMs('2027-01-01', '00:00'), sales: [], nowMs: R.bahrainMs('2027-02-01', '00:00') },
  );
  assert.strictEqual(r.ok, true);

  const creators = { self: {}, Intl };
  vm.runInNewContext(read('lib/creators.js'), creators);
  const C = creators.self.CreatorRules;
  assert.strictEqual(C.money(C.moneyPreview({ productId: 'growdaily_lifetime_offer', discountPercent: 20, sharePercent: 25, keepRate: 0.7 }).keepCents), '$12.60');
});

test('both pages sit in the frame, with their own sidebar item marked', () => {
  for (const [p, id] of [[PAGES[0], 'sale'], [PAGES[1], 'creators']]) {
    assert.ok(p.html.includes('class="side"'), p.name + ' has no sidebar');
    assert.match(p.html, new RegExp('class="nav-item active" href="/' + id + '"'));
    assert.match(p.html, /href="\/sale"/);
    assert.match(p.html, /href="\/creators"/);
    assert.match(p.html, /<title>(Sale|Creators) · GrowDaily Admin<\/title>/);
  }
});

test('the pages\' CSS is balanced and the shared styles hold no backtick', () => {
  assert.ok(!OFFERS_STYLES.includes('`'), 'OFFERS_STYLES contains a backtick');
  for (const p of PAGES) {
    const css = (p.html.match(/<style>([\s\S]*?)<\/style>/) || [])[1] || '';
    assert.ok(css.length > 1000);
    assert.strictEqual((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length, p.name + ' CSS braces are unbalanced');
  }
});

test('no section on these pages carries an id (BASE_STYLES hides section[id])', () => {
  for (const p of PAGES) assert.ok(!/<section[^>]*\sid="/.test(p.html), p.name + ' has a section with an id, which BASE_STYLES hides');
});

test('no em dash in anything these pages add', () => {
  const files = [
    renderSalePage().replace(BASE_STYLES, ''),
    renderCreatorsPage().replace(BASE_STYLES, ''),
    OFFERS_STYLES,
    read('sale/app.js'),
    read('creators/app.js'),
    read('lib/sale_rules.js'),
    read('lib/sale_admin.js'),
    read('lib/sale_page.js'),
    read('lib/creators.js'),
    read('lib/creators_admin.js'),
    read('lib/creators_page.js'),
    read('lib/offers_routes.js'),
    read('lib/offers_styles.js'),
    read('lib/asc_client.js'),
  ];
  for (const text of files) assert.ok(!text.includes(EM_DASH));
});
