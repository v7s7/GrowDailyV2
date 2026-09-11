'use strict';

/**
 * Tests for lib/day_key.js: date keys on the member's phone calendar.
 *
 * Run with `npm test` in scripts/admin_lookup.
 *
 * The instants are the real ones that went wrong: ELQVF8 slot 2's addedAt,
 * which is 2026-09-09 on Hoor's +180 phone and 2026-09-08 in UTC, and
 * ZCNGFT's startDate, which is 2026-07-15 on mohdabood2003's +240 phone. The
 * last test repeats the calls in child processes under four timezones,
 * because the bug these helpers replace only showed on a machine whose clock
 * disagreed with the member's.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { spawnSync } = require('child_process');

const DAY_KEY = path.join(__dirname, '..', 'lib', 'day_key.js');
const {
  APP_FALLBACK_OFFSET_MINUTES,
  keyAtOffset,
  localMinuteOfDay,
  offsetOf,
  storedDateKey,
  tsKey,
} = require(DAY_KEY);

/** The one part of a Firestore Timestamp the helpers use. */
const ts = (iso) => ({ toDate: () => new Date(iso) });

test('ELQVF8 slot 2 addedAt is 09-09 on a +180 phone and 09-08 in UTC', () => {
  const ms = Date.parse('2026-09-08T21:48:29.651Z');
  assert.strictEqual(keyAtOffset(ms, 180), '2026-09-09');
  assert.strictEqual(keyAtOffset(ms, 0), '2026-09-08');
});

test('a room that starts at Bahrain midnight keys to its own first day', () => {
  assert.strictEqual(tsKey(ts('2026-08-31T21:00:00Z'), 180), '2026-09-01');
});

test('ZCNGFT startDate is 07-15 on a +240 phone and 07-14 at +180', () => {
  const start = ts('2026-07-14T20:00:00Z');
  assert.strictEqual(tsKey(start, 240), '2026-07-15');
  assert.strictEqual(tsKey(start, 180), '2026-07-14');
});

test('a phone west of UTC is still on the previous day', () => {
  assert.strictEqual(keyAtOffset(Date.parse('2026-09-09T03:00:00Z'), -300), '2026-09-08');
});

test('a createdAt string with no zone is the phone date as written, never reparsed', () => {
  assert.strictEqual(storedDateKey('2026-09-08T00:00:00.000', 240), '2026-09-08');
  // Late and early times at far offsets. Read through Date.parse, a zoneless
  // string is taken as the machine's local time and the offset then carries
  // it across midnight: on a +180 machine 23:30 at +840 reads 2026-09-09 and
  // 00:30 at -600 reads 2026-09-07. Between them the two cases catch that
  // regression on a machine in any timezone. The slice keeps both on the
  // date as written.
  assert.strictEqual(storedDateKey('2026-09-08T23:30:00.000', 840), '2026-09-08');
  assert.strictEqual(storedDateKey('2026-09-08T00:30:00.000', -600), '2026-09-08');
  assert.strictEqual(storedDateKey('2026-09-08', 180), '2026-09-08');
});

test('a createdAt that names its zone is an instant, keyed at the member offset', () => {
  assert.strictEqual(storedDateKey('2026-09-08T22:30:00Z', 180), '2026-09-09');
  assert.strictEqual(storedDateKey('2026-09-08T22:30:00+00:00', 180), '2026-09-09');
  assert.strictEqual(storedDateKey('2026-09-09T01:30:00+0300', 0), '2026-09-08');
  assert.strictEqual(storedDateKey(ts('2026-09-08T22:30:00Z'), 180), '2026-09-09');
  assert.strictEqual(storedDateKey(new Date('2026-09-08T22:30:00Z'), 180), '2026-09-09');
});

test('storedDateKey returns null for what it cannot read', () => {
  assert.strictEqual(storedDateKey(undefined, 180), null);
  assert.strictEqual(storedDateKey(null, 180), null);
  assert.strictEqual(storedDateKey('2026-09', 180), null);
  assert.strictEqual(storedDateKey(1757368800000, 180), null);
  assert.strictEqual(storedDateKey('not a dateZ', 180), null);
  assert.strictEqual(storedDateKey(new Date('nope'), 180), null);
});

test('offsetOf trusts a recorded offset, 0 included, and flags the fallback', () => {
  assert.strictEqual(APP_FALLBACK_OFFSET_MINUTES, 180);
  assert.deepStrictEqual(offsetOf({}), { minutes: 180, assumed: true });
  assert.deepStrictEqual(offsetOf({ tzOffsetMinutes: 0 }), { minutes: 0, assumed: false });
  assert.deepStrictEqual(offsetOf({ tzOffsetMinutes: 240 }), { minutes: 240, assumed: false });
  assert.deepStrictEqual(offsetOf({ tzOffsetMinutes: -300 }), { minutes: -300, assumed: false });
  assert.deepStrictEqual(offsetOf(null), { minutes: 180, assumed: true });
  assert.deepStrictEqual(offsetOf(undefined), { minutes: 180, assumed: true });
  assert.deepStrictEqual(offsetOf({ tzOffsetMinutes: '180' }), { minutes: 180, assumed: true });
  assert.deepStrictEqual(offsetOf({ tzOffsetMinutes: NaN }), { minutes: 180, assumed: true });
});

test('tsKey and keyAtOffset return null rather than a wrong key', () => {
  assert.strictEqual(tsKey(undefined, 180), null);
  assert.strictEqual(tsKey(null, 180), null);
  assert.strictEqual(tsKey('2026-09-08T21:48:29.651Z', 180), null);
  assert.strictEqual(keyAtOffset(NaN, 180), null);
  assert.strictEqual(keyAtOffset(Infinity, 180), null);
  assert.strictEqual(keyAtOffset(Date.parse('2026-09-08T21:48:29.651Z'), NaN), null);
});

test('localMinuteOfDay reads the phone clock', () => {
  const ms = Date.parse('2026-09-08T21:48:29.651Z');
  assert.strictEqual(localMinuteOfDay(ms, 180), 48);
  assert.strictEqual(localMinuteOfDay(ms, 0), 21 * 60 + 48);
  assert.strictEqual(localMinuteOfDay(Date.parse('2026-09-09T03:00:00Z'), -300), 22 * 60);
  assert.strictEqual(localMinuteOfDay(Date.parse('1969-12-31T23:59:00Z'), 0), 1439);
  assert.strictEqual(localMinuteOfDay(NaN, 180), null);
});

test('keys are the same whatever timezone the machine running the script is in', () => {
  const probe = `
    const k = require(${JSON.stringify(DAY_KEY)});
    const ts = (iso) => ({ toDate: () => new Date(iso) });
    const addedAt = Date.parse('2026-09-08T21:48:29.651Z');
    const local = new Date(addedAt);
    const p = (n) => String(n).padStart(2, '0');
    process.stdout.write(JSON.stringify({
      machineOffset: local.getTimezoneOffset(),
      machineKey: local.getFullYear() + '-' + p(local.getMonth() + 1) + '-' + p(local.getDate()),
      keys: [
        k.keyAtOffset(addedAt, 180),
        k.keyAtOffset(addedAt, 0),
        k.tsKey(ts('2026-08-31T21:00:00Z'), 180),
        k.tsKey(ts('2026-07-14T20:00:00Z'), 240),
        k.tsKey(ts('2026-07-14T20:00:00Z'), 180),
        k.keyAtOffset(Date.parse('2026-09-09T03:00:00Z'), -300),
        k.storedDateKey('2026-09-08T00:00:00.000', 240),
        k.storedDateKey('2026-09-08T22:30:00Z', 180),
        k.storedDateKey(new Date('2026-09-08T22:30:00Z'), 180),
        k.localMinuteOfDay(addedAt, 180),
        JSON.stringify(k.offsetOf({})),
      ],
    }));
  `;
  const run = (tz) => {
    const out = spawnSync(process.execPath, ['-e', probe], {
      env: { ...process.env, TZ: tz },
      encoding: 'utf8',
    });
    assert.strictEqual(out.status, 0, `TZ=${tz} failed: ${out.stderr}`);
    return JSON.parse(out.stdout);
  };

  const riyadh = run('Asia/Riyadh');
  assert.deepStrictEqual(riyadh.keys, [
    '2026-09-09', '2026-09-08', '2026-09-01', '2026-07-15', '2026-07-14',
    '2026-09-08', '2026-09-08', '2026-09-09', '2026-09-09', 48,
    '{"minutes":180,"assumed":true}',
  ]);

  const offsets = new Set([riyadh.machineOffset]);
  const machineKeys = new Set([riyadh.machineKey]);
  for (const tz of ['UTC', 'America/Los_Angeles', 'Pacific/Kiritimati']) {
    const other = run(tz);
    // The child really ran in that zone, so the comparison is not vacuous.
    assert.ok(!offsets.has(other.machineOffset), `TZ=${tz} did not take effect`);
    offsets.add(other.machineOffset);
    machineKeys.add(other.machineKey);
    assert.deepStrictEqual(other.keys, riyadh.keys, `TZ=${tz}`);
  }
  // And the old machine-local key really does move across these zones,
  // which is the failure the helpers exist to remove.
  assert.ok(machineKeys.size > 1, `machine keys: ${[...machineKeys]}`);
});
