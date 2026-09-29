'use strict';

/**
 * set_room_day.js is the repair that check_rooms.js, diagnose_room.js and
 * the nightly roomsHealthSweep print, done-only. On a day the member's phone
 * has not synced since the leader removed a habit, a done count alone was
 * paid against the removed habits too: the fallback for a day with no
 * dailyScheduledCount key cannot see the room. The script now loads the
 * room and writes the key itself, by the sync's own rule
 * (lib/room_day_repair.js).
 *
 * The script runs against production on load, so the decision is tested on
 * its pure module and its use is read from the source.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const R = require('../lib/day_rules');
const { scheduledKeyPlan } = require('../lib/room_day_repair');
const { removedHabitRoom, removedHabitMember } = require('./support/removed_habit_room');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'set_room_day.js'), 'utf8');

/** The participant as it reads after set_room_day.js applies [plan]. */
function applied(part, dayKey, done, plan) {
  const out = {
    ...part,
    dailyDoneCount: { ...(part.dailyDoneCount || {}) },
    dailyScheduledCount: { ...(part.dailyScheduledCount || {}) },
  };
  if (done > 0) out.dailyDoneCount[dayKey] = done;
  else delete out.dailyDoneCount[dayKey];
  if (plan.action === 'write') out.dailyScheduledCount[dayKey] = plan.value;
  if (plan.action === 'delete') delete out.dailyScheduledCount[dayKey];
  return out;
}

test('a done-only repair after a removal writes the plan\'s count beside it', () => {
  // PBYAS5's shape: the member did all five habits still in the plan on the
  // 27th, the day after the removal, and their phone never synced it. The
  // undercount check prints --done=5 and nothing else.
  const room = removedHabitRoom();
  const part = removedHabitMember();
  const dayKey = '2026-09-27';
  const plan = scheduledKeyPlan({ room, participant: part, dayKey, done: 5, scheduled: null, offsetMinutes: 180 });
  assert.equal(plan.action, 'write');
  assert.equal(plan.value, 5);
  assert.equal(plan.fallback, 7, 'the participant-only count still holds the removed habits');
  assert.equal(plan.readsNow, 7);
  assert.equal(plan.reads, 5);

  // What the app reads afterwards: a full day. Without the key, 5 of 7, and
  // the board's own inference cannot step in on a day with something done.
  const after = R.roomDayCounts({
    room, participant: applied(part, dayKey, 5, plan), dayKey, offsetMinutes: 180,
  });
  assert.equal(after.scheduled, 5);
  assert.equal(after.credit, 1);
  const doneOnly = R.roomDayCounts({
    room, participant: applied(part, dayKey, 5, { action: 'keep' }), dayKey, offsetMinutes: 180,
  });
  assert.equal(doneOnly.scheduled, 7);
  assert.equal(doneOnly.planInferred, false);
  assert.equal(Math.round(doneOnly.credit * 100), 71, 'the underpayment this fixes');
});

test('the removal day and a plan nobody edited need no key', () => {
  const room = removedHabitRoom();
  const part = removedHabitMember();
  const removalDay = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-26', done: 7, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(removalDay.action, 'keep', 'the removal day still counts all seven');
  assert.equal(removalDay.reads, 7);
  const plain = { ...room, sharedHabits: room.sharedHabits.map(({ removedAt, stopsOn, ...t }) => t) };
  const untouched = scheduledKeyPlan({
    room: plain, participant: part, dayKey: '2026-09-27', done: 5, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(untouched.action, 'keep');
  assert.equal(untouched.live, 7);
});

test('a key the sync stored is kept', () => {
  // The sync knew the day's schedule (a rest weekday, a banked quota week),
  // which neither count here can see.
  const room = removedHabitRoom();
  const part = removedHabitMember();
  part.dailyScheduledCount = { '2026-09-27': 4 };
  const plan = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-27', done: 4, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(plan.action, 'keep');
  assert.equal(plan.value, 4);
  assert.equal(plan.reads, 4);
  assert.equal(plan.why, 'stored by the sync');
  // Even one equal to the participant-only count, which the sync itself
  // would not have written: a key is never replaced without --scheduled.
  part.dailyScheduledCount = { '2026-09-27': 7 };
  const equal = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-27', done: 5, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(equal.action, 'keep');
  assert.equal(equal.reads, 7);
});

test('an override equal to the participant-only count removes the key, as the sync does', () => {
  // The sparse invariant is the sync's: a key exists exactly where the count
  // differs from countedHabitCountOn, never from the plan's count.
  const room = removedHabitRoom();
  const part = removedHabitMember();
  part.dailyScheduledCount = { '2026-09-27': 5 };
  const seven = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-27', done: 5, scheduled: 7, offsetMinutes: 180,
  });
  assert.equal(seven.action, 'delete');
  assert.equal(seven.reads, 7);
  const five = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-27', done: 5, scheduled: 5, offsetMinutes: 180,
  });
  assert.equal(five.action, 'write', 'equal to the plan is not equal to the fallback');
  assert.equal(five.value, 5);

  // Against the count with its floors, the one the sync compares against:
  // a slot linked on the 27th is not part of the 26th's fallback, so an
  // override of 7 there is a real key, not a deletion.
  const late = removedHabitMember();
  late.habitRules.isha = [{ from: '2026-09-27', frequencyType: 'daily', frequencyTarget: 1 }];
  assert.equal(R.countedHabitCountOn({ participant: late, dayKey: '2026-09-26' }), 6);
  const floored = scheduledKeyPlan({
    room, participant: late, dayKey: '2026-09-26', done: 6, scheduled: 7, offsetMinutes: 180,
  });
  assert.equal(floored.action, 'write');
  assert.equal(floored.value, 7);
});

test('a met quota week\'s blank day keeps its own excuse', () => {
  // After a done=0 repair the record reads the day as 0, a rest day. A key
  // would turn it into a miss.
  const room = removedHabitRoom();
  room.sharedHabits = [room.sharedHabits[0], room.sharedHabits[3]];
  const part = {
    joinedAt: new Date('2026-09-13T21:00:00Z'),
    linkedHabitIds: ['run', 'walk'],
    habitRules: {
      run: [{ from: '2026-09-14', frequencyType: 'weekly', frequencyTarget: 3 }],
      walk: [{ from: '2026-09-14', frequencyType: 'weekly', frequencyTarget: 3 }],
    },
    quotaOkWeeks: ['2026-09-26'],
    lastSyncedAt: new Date('2026-09-26T17:00:00Z'),
  };
  const blank = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-28', done: 0, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(blank.action, 'keep');
  assert.equal(blank.reads, 0);
  // So does a deleted key: what the day reads afterwards is the record's.
  const deleted = scheduledKeyPlan({
    room, participant: { ...part, dailyScheduledCount: { '2026-09-28': 1 } },
    dayKey: '2026-09-28', done: 0, scheduled: 2, offsetMinutes: 180,
  });
  assert.equal(deleted.action, 'delete');
  assert.equal(deleted.reads, 0);
  // A session on that day ends the excuse, and the plan's count applies.
  const trained = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-28', done: 1, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(trained.action, 'write');
  assert.equal(trained.value, 1);
});

test('a member whose every link is removed keeps the fallback, never zero', () => {
  const room = removedHabitRoom();
  const part = removedHabitMember();
  part.linkedHabitIds = part.linkedHabitIds.map((id, i) => (i === 3 || i === 6 ? id : R.DECLINED_SLOT));
  const plan = scheduledKeyPlan({
    room, participant: part, dayKey: '2026-09-27', done: 0, scheduled: null, offsetMinutes: 180,
  });
  assert.equal(plan.action, 'keep');
  assert.equal(plan.reads, 2);
});

test('set_room_day.js loads the room and writes what the plan decided', () => {
  assert.match(SOURCE, /db\.collection\('rooms'\)\.doc\(roomCode\)\.get\(\)/, 'it reads rooms/{code}');
  const call = SOURCE.match(/scheduledKeyPlan\(\{([\s\S]*?)\}\);/);
  assert.ok(call, 'it asks lib/room_day_repair.js');
  assert.match(call[1], /\broom,/);
  assert.match(call[1], /participant: d,/);
  assert.match(call[1], /scheduled,/);
  assert.match(SOURCE, /if \(plan\.action === 'delete'\) \{/);
  assert.match(SOURCE, /\} else if \(plan\.action === 'write'\) \{\n\s+update\[`dailyScheduledCount\.\$\{dateKey\}`\] = plan\.value;/);
  // The old comparison against every linked slot is gone: it counted the
  // removed habits and ignored the floors.
  assert.doesNotMatch(SOURCE, /scheduled === counted/);
});
