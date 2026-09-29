'use strict';

/**
 * The account page's day card, for a room day the member's phone has not
 * graded since the leader removed a habit. It printed "the room stored 0
 * of 7" (and "PBYAS5 0/7" in the ledger) beside a board reading 0 of 5,
 * and "stored" was not even true: nothing was stored for the day.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const { buildDaySection } = require('../lib/fetchAccount');
const { removedHabitRoom, removedHabitMember } = require('./support/removed_habit_room');

const doc = (id, data) => ({ id, data: () => data });

function rawFor(part) {
  return {
    profileData: { tzOffsetMinutes: 180 },
    docsByCollection: {
      custom_habits: part.linkedHabitIds.map((id) => doc(id, {
        name: id, frequencyType: 'daily', frequencyTarget: 1,
        createdAt: '2026-09-01T00:00:00.000',
      })),
      // The square is green, but the phone never synced the room after it.
      daily: [doc('2026-09-27', { squareStates: { fajr: 'complete' } })],
    },
    roomRows: [{ code: 'PBYAS5', room: removedHabitRoom(), participant: part }],
  };
}

test('an unsynced day after a removal reads the plan and says it is not stored', () => {
  const html = buildDaySection(rawFor(removedHabitMember()), '2026-09-27').html;
  assert.match(html, /nothing stored yet, their phone has not graded this day: 0 of 5/);
  assert.match(html, /the record alone says 7/);
  assert.doesNotMatch(html, /the room stored 0 of 7/);
  assert.match(html, /PBYAS5 0\/5 \(not synced\)/, 'the ledger tag');
});

test('a day the room stored reads as stored', () => {
  const html = buildDaySection(rawFor(removedHabitMember()), '2026-09-25').html;
  assert.match(html, /the room stored 7 of 7/);
  assert.match(html, /PBYAS5 7\/7/);
  assert.doesNotMatch(html, /not synced/);
});
