'use strict';

// Every value the admin panel renders can be attacker-controlled: Firestore
// rules let any signed-in user write their own profile and custom_habits docs
// with no type or content validation, and this tool renders them straight into
// an admin's browser. These tests pin the two escaping holes that let a plain
// user reach into that browser.

const { test } = require('node:test');
const assert = require('node:assert');

const { safeCssColor, renderHabitDetail } = require('../lib/render');
const { REPORT_SCRIPT } = require('../lib/render');
const fs = require('fs');
const path = require('path');

test('safeCssColor accepts only #hex literals', () => {
  assert.strictEqual(safeCssColor('#FF5722'), '#FF5722');
  assert.strictEqual(safeCssColor('#abc'), '#abc');
  assert.strictEqual(safeCssColor('#12345678'), '#12345678');
  assert.strictEqual(safeCssColor('  #0af  '), '#0af');
});

test('safeCssColor rejects a CSS-injection payload', () => {
  // The exact shape a user could store in iconColorHex to make the admin's
  // browser fetch an attacker URL when their habit is expanded.
  assert.strictEqual(
    safeCssColor("red;background-image:url(https://attacker.example/beacon.png)"),
    null,
  );
  assert.strictEqual(safeCssColor('red'), null);
  assert.strictEqual(safeCssColor('url(x)'), null);
  assert.strictEqual(safeCssColor(''), null);
  assert.strictEqual(safeCssColor(null), null);
  assert.strictEqual(safeCssColor(undefined), null);
});

test('renderHabitDetail drops a malicious iconColorHex instead of injecting it', () => {
  const html = renderHabitDetail({
    name: 'Test habit',
    iconColorHex: "red;background-image:url(https://attacker.example/beacon.png)",
  });
  assert.ok(!html.includes('attacker.example'), 'the payload must not reach the style attribute');
  assert.ok(!html.includes('background-image'), 'no extra CSS declaration should render');
});

test('renderHabitDetail keeps a valid iconColorHex swatch', () => {
  const html = renderHabitDetail({ name: 'Test habit', iconColorHex: '#5DADEC' });
  assert.ok(html.includes('style="background:#5DADEC"'), 'a real colour still paints the swatch');
});

test('the Accounts table escapes profile level and currentStreak', () => {
  // The row template lives in the browser-side REPORT script emitted by the
  // dashboard page. The two numeric-looking profile fields must go through
  // esc() like every sibling cell, or a user who writes a string into their
  // own level/currentStreak lands script in the admin origin.
  const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
  // Match the two Accounts-table cells and assert they call esc().
  const levelCell = /u\.level == null \? '—' : esc\(u\.level\)/;
  const streakCell = /u\.currentStreak == null \? '—' : esc\(u\.currentStreak\)/;
  assert.ok(levelCell.test(src), 'level cell must be escaped');
  assert.ok(streakCell.test(src), 'currentStreak cell must be escaped');
  // And make sure the raw, unescaped forms are gone.
  assert.ok(!/\? '—' : u\.level\b/.test(src), 'no unescaped level cell may remain');
  assert.ok(!/\? '—' : u\.currentStreak\b/.test(src), 'no unescaped currentStreak cell may remain');
});
