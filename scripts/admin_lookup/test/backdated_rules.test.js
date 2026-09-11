'use strict';

/**
 * Tests for lib/backdated_rules.js, the decision behind
 * repair_backdated_rules.js.
 *
 * Run with `npm test` in scripts/admin_lookup.
 *
 * Every fixture is a real member's shape, in the fields the script reads:
 * rooms/{code} startDate and sharedHabits[i].addedAt (Timestamps), the
 * participant's habitRules (habit id -> [{from, frequencyType,
 * frequencyTarget}]), linkedHabitIds (positional, one per plan slot) and
 * dailyDoneCount (day key -> count as stored), and each habit's raw
 * createdAt, a zoneless ISO string on these documents.
 */

const test = require('node:test');
const assert = require('node:assert');

const { proposeFor, looksLikeUtcKeyedStamp } = require('../lib/backdated_rules');

/** The one part of a Firestore Timestamp the decision uses. */
const ts = (iso) => ({ toDate: () => new Date(iso) });

const EXERCISE = '93bfae4a-8c6c-4a53-8bd9-bf41f0efe1c7';
const WITR = '64954035-f900-4891-90cd-62e861e3155b';
const QURAN = 'd6a6b8a8-9f7a-4541-8820-1c6f7ead3d1c';

/** Room ELQVF8: slot 2 was added by the leader to the running room. */
function elqvf8Room() {
  return {
    habitMode: 'shared',
    startDate: ts('2026-08-31T21:00:00.000Z'),
    endDate: ts('2026-09-29T21:00:00.000Z'),
    sharedHabits: [
      { frequencyType: 'weekly', frequencyTarget: 4 },
      { frequencyType: 'daily', frequencyTarget: 1 },
      { frequencyType: 'daily', frequencyTarget: 1, addedAt: ts('2026-09-08T21:48:29.651Z') },
    ],
  };
}

/** Hoor in ELQVF8. quranFrom is slot 2's stamp; 2026-09-08 is what is stored today. */
function hoor(quranFrom = '2026-09-08') {
  return {
    displayName: 'Hoor',
    linkedHabitIds: [EXERCISE, WITR, QURAN],
    habitRules: {
      [EXERCISE]: [{ from: '2026-09-01', frequencyType: 'weekly', frequencyTarget: 4 }],
      [WITR]: [{ from: '2026-09-01', frequencyType: 'daily', frequencyTarget: 1 }],
      [QURAN]: [{ from: quranFrom, frequencyType: 'daily', frequencyTarget: 1 }],
    },
    dailyDoneCount: {
      '2026-09-01': 1, '2026-09-02': 1, '2026-09-05': 2, '2026-09-06': 2,
      '2026-09-07': 2, '2026-09-08': 3, '2026-09-09': 3, '2026-09-10': 2,
    },
  };
}

const hoorCreatedAt = () => new Map([[QURAN, '2026-09-08T00:00:00.000']]);

const summary = (res) => res.proposals.map((p) => [p.habitId, p.minFrom, p.proposed, p.why]);

test('ELQVF8 Hoor at +180: slot 2 joined the plan on 09-09 and the stored 09-08 count refuses it', () => {
  const res = proposeFor({
    room: elqvf8Room(), participant: hoor(), offsetMinutes: 180, createdAtById: hoorCreatedAt(),
  });
  assert.strictEqual(res.startKey, '2026-09-01');
  assert.deepStrictEqual(summary(res), [[QURAN, '2026-09-08', '2026-09-09', 'slot joined plan 2026-09-09']]);
  assert.strictEqual(res.proposals[0].addedAtMs, Date.parse('2026-09-08T21:48:29.651Z'));
  assert.ok(res.broken.some((b) => b.day === '2026-09-08'), JSON.stringify(res.broken));
  assert.deepStrictEqual(res.broken, [{ day: '2026-09-08', done: 3, asked: 2, askedBefore: 3 }]);
  assert.deepStrictEqual(res.patch, {});
  // The one refused day is the UTC stamp day, and 3 done is exactly what that
  // stamp asked on it: the shape the old UTC keying left behind.
  assert.strictEqual(looksLikeUtcKeyedStamp(res.proposals[0], res.broken), true);
});

test('the same ELQVF8 fixture keyed in UTC: slot 2 joins on 09-08, the day its rule already starts', () => {
  const res = proposeFor({
    room: elqvf8Room(), participant: hoor(), offsetMinutes: 0, createdAtById: hoorCreatedAt(),
  });
  assert.strictEqual(res.startKey, '2026-08-31');
  // In UTC the addition and the stored rule are the same day, so there is
  // nothing to propose: the reason the UTC-keyed script never listed Hoor.
  assert.deepStrictEqual(res.proposals, []);
  assert.deepStrictEqual(res.broken, []);
  assert.deepStrictEqual(res.patch, {});
});

test('slot 2 stamped at the room start: UTC proposes 09-08 as SAFE, the phone calendar proposes 09-09 and refuses', () => {
  const utc = proposeFor({
    room: elqvf8Room(), participant: hoor('2026-09-01'), offsetMinutes: 0, createdAtById: hoorCreatedAt(),
  });
  assert.deepStrictEqual(summary(utc), [[QURAN, '2026-09-01', '2026-09-08', 'slot joined plan 2026-09-08']]);
  assert.deepStrictEqual(utc.broken, []);
  // The wrong calendar would have written a date a day early.
  assert.deepStrictEqual(utc.patch, {
    [QURAN]: [{ from: '2026-09-08', frequencyType: 'daily', frequencyTarget: 1 }],
  });

  const phone = proposeFor({
    room: elqvf8Room(), participant: hoor('2026-09-01'), offsetMinutes: 180, createdAtById: hoorCreatedAt(),
  });
  assert.deepStrictEqual(summary(phone), [[QURAN, '2026-09-01', '2026-09-09', 'slot joined plan 2026-09-09']]);
  assert.deepStrictEqual(phone.broken.map((b) => b.day), ['2026-09-08']);
  assert.deepStrictEqual(phone.patch, {});
});

test('an assumed offset reports the proposal but never builds a patch', () => {
  const args = {
    room: elqvf8Room(), participant: hoor('2026-09-01'), offsetMinutes: 0, createdAtById: hoorCreatedAt(),
  };
  assert.notDeepStrictEqual(proposeFor(args).patch, {});
  const assumed = proposeFor({ ...args, offsetAssumed: true });
  assert.strictEqual(assumed.proposals.length, 1);
  assert.deepStrictEqual(assumed.broken, []);
  assert.deepStrictEqual(assumed.patch, {});
});

test('A8GEL7 Aziz: a habit remade on 09-01 over 16 stored days is UNSAFE, judged from STORED counts', () => {
  // If anyone swaps the stored dailyDoneCount for a recount under the
  // corrected rule, every day passes and this test fails, as it must: the
  // 16 stored days are real history the repair would erase.
  const H = '747fae86-863d-4307-8824-eb0ea068e196';
  const done = {};
  for (let i = 0; i < 16; i++) {
    done[new Date(Date.UTC(2026, 6, 29 + i)).toISOString().slice(0, 10)] = 1;
  }
  const room = {
    habitMode: 'shared',
    startDate: ts('2026-07-27T21:00:00.000Z'),
    sharedHabits: [{ frequencyType: 'weekly', frequencyTarget: 4 }],
  };
  const participant = {
    displayName: 'Aziz',
    linkedHabitIds: [H],
    habitRules: { [H]: [{ from: '2026-07-28', frequencyType: 'weekly', frequencyTarget: 4 }] },
    dailyDoneCount: done,
  };
  const res = proposeFor({
    room, participant, offsetMinutes: 180, createdAtById: { [H]: '2026-09-01T00:00:00.000' },
  });
  assert.strictEqual(res.startKey, '2026-07-28');
  assert.deepStrictEqual(summary(res), [[H, '2026-07-28', '2026-09-01', 'habit created 2026-09-01']]);
  assert.strictEqual(res.broken.length, 16);
  assert.strictEqual(res.broken[0].day, '2026-07-29');
  assert.strictEqual(res.broken[15].day, '2026-08-13');
  assert.ok(res.broken.every((b) => b.done === 1 && b.asked === 0 && b.askedBefore === 1));
  assert.deepStrictEqual(res.patch, {});
  // Every count equals the current ask here too, and it is real history, not
  // a timezone shift, so the report must not excuse it.
  assert.strictEqual(looksLikeUtcKeyedStamp(res.proposals[0], res.broken), false);
});

test('a room that is not shared, or has no start, proposes nothing', () => {
  const own = { ...elqvf8Room(), habitMode: 'own' };
  const res = proposeFor({ room: own, participant: hoor('2026-09-01'), offsetMinutes: 180, createdAtById: hoorCreatedAt() });
  assert.deepStrictEqual([res.proposals, res.broken, res.patch], [[], [], {}]);
  const noStart = { ...elqvf8Room(), startDate: undefined };
  const res2 = proposeFor({ room: noStart, participant: hoor('2026-09-01'), offsetMinutes: 180, createdAtById: hoorCreatedAt() });
  assert.strictEqual(res2.startKey, null);
  assert.deepStrictEqual(res2.proposals, []);
});

test('looksLikeUtcKeyedStamp stays false unless every part of the UTC shape holds', () => {
  const pr = {
    addedAtMs: Date.parse('2026-09-08T21:48:29.651Z'), minFrom: '2026-09-08', proposed: '2026-09-09',
  };
  const onStampDay = [{ day: '2026-09-08', done: 3, asked: 2, askedBefore: 3 }];
  assert.strictEqual(looksLikeUtcKeyedStamp(pr, onStampDay), true);
  // Nothing refused, so nothing to explain.
  assert.strictEqual(looksLikeUtcKeyedStamp(pr, []), false);
  // The evidence was a habit's createdAt, not a slot's addedAt.
  assert.strictEqual(looksLikeUtcKeyedStamp({ ...pr, addedAtMs: null }, onStampDay), false);
  // addedAt's UTC date is not the stamp.
  assert.strictEqual(
    looksLikeUtcKeyedStamp({ ...pr, addedAtMs: Date.parse('2026-09-09T10:00:00Z') }, onStampDay), false);
  // The correction moves more than one day.
  assert.strictEqual(looksLikeUtcKeyedStamp({ ...pr, proposed: '2026-09-10' }, onStampDay), false);
  // A refused day other than the stamp day.
  assert.strictEqual(looksLikeUtcKeyedStamp(pr, [
    ...onStampDay, { day: '2026-09-09', done: 3, asked: 2, askedBefore: 3 },
  ]), false);
  // A stored count above what the current stamp asked.
  assert.strictEqual(
    looksLikeUtcKeyedStamp(pr, [{ day: '2026-09-08', done: 4, asked: 2, askedBefore: 3 }]), false);
});
