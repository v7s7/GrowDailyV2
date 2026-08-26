'use strict';

/**
 * Syntax-checks the JavaScript and CSS that get EMITTED into the pages,
 * rather than only the files that emit them.
 *
 * `node --check server.js` parses server.js. It says nothing about the
 * several hundred lines of browser JS living inside a template literal in
 * it, which is a separate program that only the browser ever parses. Two
 * real breakages during this tool's rebuild made it all the way to a blank
 * page for exactly that reason:
 *
 *   - a CSS comment containing `backticks` ended the template literal early
 *   - a string written as 'today\'s' had its backslash eaten by the template
 *     literal, so the browser received an unterminated string
 *
 * Both are invisible to every check that reads the source file, and both
 * produce a page that loads, renders its static HTML, and then silently does
 * nothing at all. So this renders the pages the way the server does and
 * parses what comes out.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const { BASE_STYLES, pageShell, REPORT_SCRIPT } = require('../lib/render');

/** Every <script>…</script> body in a document. */
function scriptBodies(html) {
  const out = [];
  const re = /<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g;
  let m;
  while ((m = re.exec(html)) !== null) out.push(m[1]);
  return out;
}

/** Every <style>…</style> body in a document. */
function styleBodies(html) {
  const out = [];
  const re = /<style(?:\s[^>]*)?>([\s\S]*?)<\/style>/g;
  let m;
  while ((m = re.exec(html)) !== null) out.push(m[1]);
  return out;
}

function assertParses(source, label) {
  try {
    // Compile without running: this is browser code and touches document.
    new vm.Script(source, { filename: label });
  } catch (e) {
    assert.fail(`${label} is not valid JavaScript: ${e.message}`);
  }
}

/**
 * The dashboard's HTML, pulled out of server.js without starting a server or
 * touching Firebase.
 *
 * server.js calls admin.initializeApp() at require time and exits if there
 * is no service-account key, so it cannot simply be required here. The home
 * page is one big template literal against BASE_STYLES, so this evaluates
 * exactly that expression with the real styles substituted in. If the route
 * is ever restructured this stops finding it and fails loudly, which is the
 * correct outcome: the check would otherwise quietly cover nothing.
 */
function renderDashboardHtml() {
  const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
  const start = src.indexOf("app.get('/', (req, res) => {");
  assert.notStrictEqual(start, -1, 'could not find the dashboard route in server.js');
  const open = src.indexOf('res.type(\'html\').send(`', start);
  assert.notStrictEqual(open, -1, 'dashboard route no longer sends a template literal');
  const bodyStart = open + 'res.type(\'html\').send(`'.length;
  const end = src.indexOf('`);', bodyStart);
  assert.notStrictEqual(end, -1, 'could not find the end of the dashboard template');
  const template = src.slice(bodyStart, end);

  // EVALUATE the template rather than string-substituting into its source.
  //
  // A plain .split('${BASE_STYLES}').join(...) leaves every escape sequence
  // unprocessed, so `\\'` in the source stays two characters instead of
  // collapsing to one and the extracted "script" fails to parse even though
  // the page the server actually sends is fine. That produced a confident
  // false alarm the first time this test ran. Running the literal through vm
  // applies exactly the escape handling Node applies at request time, so
  // what is checked here is what the browser receives.
  const build = new vm.Script(
    '(function (BASE_STYLES) { return `' + template + '`; })',
    { filename: 'dashboard-template' });
  return build.runInNewContext()(BASE_STYLES);
}

test('the dashboard page emits parseable browser JavaScript', () => {
  const html = renderDashboardHtml();
  const scripts = scriptBodies(html);
  assert.ok(scripts.length >= 1, 'dashboard has no inline script');
  scripts.forEach((body, i) => assertParses(body, `dashboard inline script #${i + 1}`));
});

test('the report page emits parseable browser JavaScript', () => {
  const html = pageShell({
    title: 'test', nav: '', header: '<div class="idline"></div>',
    stats: '', body: '<section id="today"></section>', backHref: '/', uid: 'abc123',
  });
  const scripts = scriptBodies(html);
  assert.ok(scripts.length >= 1, 'report page has no inline script');
  scripts.forEach((body, i) => assertParses(body, `report inline script #${i + 1}`));
});

test('REPORT_SCRIPT parses on its own', () => {
  assertParses(REPORT_SCRIPT, 'REPORT_SCRIPT');
});

// A stray backtick inside BASE_STYLES silently ends the template literal
// that the styles are interpolated into, which is how the whole home page
// went blank once. Nothing else in this file would catch it, because the
// truncated result is still valid JavaScript.
test('no stray backtick escapes the style or script templates', () => {
  assert.ok(!BASE_STYLES.includes('`'), 'BASE_STYLES contains a backtick');
  assert.ok(!REPORT_SCRIPT.includes('`'), 'REPORT_SCRIPT contains a backtick');
});

test('both pages emit balanced, non-empty CSS', () => {
  const docs = [
    ['dashboard', renderDashboardHtml()],
    ['report', pageShell({ title: 't', nav: '', header: '', stats: '', body: '' })],
  ];
  for (const [label, html] of docs) {
    const styles = styleBodies(html);
    assert.ok(styles.length >= 1, `${label} has no inline style block`);
    const css = styles.join('\n');
    assert.ok(css.length > 500, `${label} style block looks truncated (${css.length} chars)`);
    const opens = (css.match(/\{/g) || []).length;
    const closes = (css.match(/\}/g) || []).length;
    assert.strictEqual(opens, closes, `${label} CSS braces are unbalanced (${opens} vs ${closes})`);
  }
});

test('the dashboard markup keeps the hooks its script binds to', () => {
  // Every id the inline script reaches for with $(). A rename on one side
  // only is a page that loads and then does nothing, with no error.
  const html = renderDashboardHtml();
  const required = [
    'liveStrip', 'scanWarn', 'cntActivity', 'cntAccounts', 'qA', 'feedDay',
    'feedRanges', 'typeChips', 'clearA', 'onlineRail', 'dayRoster', 'statusA',
    'dayStat', 'feed', 'horizon', 'qU', 'fromDate', 'toDate', 'quickRanges',
    'onlyActive', 'clearU', 'statusU', 'rows', 'refresh', 'scanNote',
    'drawer', 'scrim',
  ];
  for (const id of required) {
    assert.ok(html.includes(`id="${id}"`), `dashboard markup is missing #${id}`);
  }
});
