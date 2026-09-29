'use strict';

/**
 * A room shaped like PBYAS5 on 2026-09-28: seven shared habits, slots 3
 * «سنة الظهر البعدية» and 6 «الوتر» removed by the leader on the 26th, so
 * they count through the 26th and from the 27th (stopsOn) for nobody.
 *
 * The member's phone last graded the room at 20:00 on the 26th (+180), so
 * the 25th is observed (it closed at 10:00 that morning) and the 26th
 * (still open then), 27th and 28th are not. Nothing is stored for any of
 * those three days: the shape the app's day card read as «0 من 7 عادات»
 * until RoomParticipant.unsyncedPlanInference.
 *
 * Shared by test/day_rules.test.js and test/set_room_day.test.js. Each call
 * returns fresh objects, so a test may edit its copy.
 */

function removedHabitRoom() {
  const removedAt = new Date('2026-09-26T15:00:00Z');
  return {
    habitMode: 'shared',
    status: 'active',
    startDate: new Date('2026-09-13T21:00:00Z'), // 2026-09-14 at +180
    endDate: new Date('2026-10-12T21:00:00Z'),
    sharedHabits: [
      { name: 'سنة الفجر', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'الضحى', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'سنة الظهر القبلية', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'سنة الظهر البعدية', frequencyType: 'daily', frequencyTarget: 1,
        removedAt, removedBy: 'leader', stopsOn: '2026-09-27' },
      { name: 'سنة المغرب', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'سنة العشاء', frequencyType: 'daily', frequencyTarget: 1 },
      { name: 'الوتر', frequencyType: 'daily', frequencyTarget: 1,
        removedAt, removedBy: 'leader', stopsOn: '2026-09-27' },
    ],
  };
}

function removedHabitMember() {
  const ids = ['fajr', 'duha', 'dhuhrPre', 'dhuhrPost', 'maghrib', 'isha', 'witr'];
  const rules = {};
  for (const id of ids) {
    rules[id] = [{ from: '2026-09-14', frequencyType: 'daily', frequencyTarget: 1 }];
  }
  return {
    displayName: 'Member',
    joinedAt: new Date('2026-09-13T21:00:00Z'),
    linkedHabitIds: ids,
    habitRules: rules,
    dailyDoneCount: { '2026-09-24': 6, '2026-09-25': 7 },
    dailyPartialCount: {},
    dailyScheduledCount: {},
    standDownDays: [],
    quotaOkWeeks: [],
    lastSyncedDay: '2026-09-26',
    lastSyncedAt: new Date('2026-09-26T17:00:00Z'),
  };
}

module.exports = { removedHabitRoom, removedHabitMember };
