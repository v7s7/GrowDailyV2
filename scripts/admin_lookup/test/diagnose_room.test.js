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

test('diagnose_room.js leaves a rest day out of the own-days line', () => {
  // It printed "rest, full credit" and added a whole day to both sides, the
  // model from before 2026-09-09: YW68B9's Aziz read 58% beside a board of
  // 39%. The line now asks the same verdict the admin day card asks.
  assert.match(SOURCE, /roomDayVerdict/);
  assert.doesNotMatch(SOURCE, /rest, full credit/);
  const restBranch = SOURCE.match(
      /else if \(!roomDayVerdict\(stored\)\.counts\) \{([\s\S]*?)\} else \{/);
  assert.ok(restBranch, 'the rest branch is still there');
  assert.doesNotMatch(restBranch[1], /storedTotal|gradedDays/,
      'and adds to neither side');
});

test('diagnose_room.js keeps a removed slot\'s column through its last day', () => {
  // PBYAS5 2026-09-24 printed 6/7 over five columns: the two habits the
  // leader removed on the 26th counted until then, and were not on the page.
  assert.match(SOURCE, /if \(!isDeclined && \(!removed \|\| stops\)\)/);
  assert.match(SOURCE, /if \(c\.stops && dk >= c\.stops\) return 'removed'/);
});

test('diagnose_room.js grades a member from the day they joined', () => {
  // RoomParticipant.countedStartIn: the later of the room's start and the
  // join day. ZCNGFT's Aziz joined on 07-16 of a room begun on 07-14 and
  // read 12 of 30 here against 10 of 28 on the board, and the undercount
  // check could have printed a repair for a day before he was in the room.
  assert.match(SOURCE, /const joinKey = storedDateKey\(p\.joinedAt, ROOM_OFFSET_MINUTES\);/);
  assert.match(SOURCE, /const mdays = days\.filter\(\(dk\) => dk >= fromKey\);/);
  const check = SOURCE.match(/undercountedDays\(\{([\s\S]*?)\}\);/);
  assert.match(check[1], /days: mdays,/, 'the undercount check reads their days');
  const table = SOURCE.match(/for \(let i = 0; i < (\w+)\.length; i\+\+\) \{\n\s+const dk = \1\[i\];/);
  assert.equal(table && table[1], 'mdays', 'and so does the day table');
});

test('diagnose_room.js reads an unsynced day after a removal the way the board does', () => {
  // PBYAS5 2026-09-28 printed 0/7 beside a board of 0 of 5: the record's
  // fallback cannot see the two removed habits. roomDayCounts now carries
  // the board's inference (planInferredScheduledOn) and says when it did,
  // and the column says so too rather than calling the plan's count stored.
  assert.match(SOURCE, /const unsynced = stored\.planInferred \?/);
  assert.match(SOURCE, /the record alone says \$\{stored\.recorded\}/);
  assert.match(SOURCE, /still open\$\{unsynced\}/);
  // `asked` is the stored count, or the weighted demand on a shared quota
  // half's day (halves add up, 2026-10-03).
  const graded = SOURCE.match(/\} else \{\n\s+countsCell = `\$\{num\(credited\)\}\/\$\{asked\}` \+([\s\S]*?);\n/);
  assert.match(SOURCE, /const asked = weighted \? num\(demandW\) : stored\.scheduled;/);
  assert.ok(graded, 'the graded branch is still there');
  assert.match(graded[1], /unsynced/);
});
