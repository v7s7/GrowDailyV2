'use strict';

/**
 * diagnose_room.js prints a set_room_day.js --confirm line for every day its
 * undercount check flags, so the check has to read each day the way the app
 * graded it. After a member changed which habit fills a plan slot
 * (RoomsController.relinkPlanHabit), that means the habit in the slot THAT
 * day: undercountedDays only asks it when it is handed the room, which the
 * nightly sweep (functions/index.js) and check_rooms.js already do.
 *
 * The script itself runs against production on load, so its call is read
 * from the source, and what the room changes is shown on room_health.js.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { countingHabitIds, undercountedDays } = require(
    path.join(__dirname, '..', '..', '..', 'functions', 'room_health.js'));

const SOURCE = fs.readFileSync(
    path.join(__dirname, '..', 'diagnose_room.js'), 'utf8');

test('diagnose_room.js checks each day against the habits in the plan that ' +
    'day', () => {
  const call = SOURCE.match(/undercountedDays\(\{([\s\S]*?)\}\);/);
  assert.ok(call, 'the undercount check is still there');
  assert.match(call[1], /^\s*room,?\s*$/m, 'it hands the check the room');

  // Why. Without the room, a relinked slot reads the new habit back over the
  // days before the change, and the old one after. «تمرين» filled slot 0
  // until 07-10 and was not done; «صلاة الضحى», done every day, fills it
  // from 07-11. Both days are stored correctly.
  const room = { habitMode: 'shared', sharedHabits: [{ name: 'الضحى' }] };
  const part = {
    linkedHabitIds: ['m-duha'],
    slotHabitHistory: { 0: [{ habitId: 'm-wrong', until: '2026-07-10' }] },
    dailyDoneCount: { '2026-07-12': 1 },
  };
  const squaresByDay = {
    '2026-07-09': { 'm-duha': 'complete' },
    '2026-07-12': { 'm-duha': 'complete', 'm-wrong': 'complete' },
  };
  const args = {
    days: ['2026-07-09', '2026-07-12'],
    countingIds: countingHabitIds(room, part),
    squaresByDay,
    part,
  };
  assert.deepStrictEqual(
      undercountedDays(args).map((s) => s.day),
      ['2026-07-09', '2026-07-12'],
      'each day would have been handed a repair command');
  assert.deepStrictEqual(undercountedDays({ ...args, room }), []);
});
