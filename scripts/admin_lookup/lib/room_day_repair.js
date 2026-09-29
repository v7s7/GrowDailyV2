'use strict';

/**
 * What set_room_day.js writes to dailyScheduledCount beside a repaired done
 * count. Pure, so it can be tested: the script itself runs against
 * production on load.
 *
 * The rule is the sync's own (syncLinkedHabitsProgress): a day carries a
 * dailyScheduledCount key exactly when its count differs from the
 * participant-only fallback, countedHabitCountOn, which is what every reader
 * falls back to when the key is absent.
 *
 * That fallback cannot see the room, so after the leader removes a habit it
 * still counts it (lib/day_rules.js liveHabitCountOn). A day the member's
 * phone has not synced since has no key, and the repair command that
 * check_rooms.js, diagnose_room.js and the nightly roomsHealthSweep print is
 * done-only. Writing just the done count then paid the day done/7 where the
 * plan asked for 5: on PBYAS5 (slots 3 and 6 removed, stopsOn 2026-09-27) a
 * repaired 5 of 5 would have read 5 of 7, 71%. The app's read-side inference
 * (RoomParticipant.unsyncedPlanInference) cannot rescue it either, because
 * it steps aside on any day with something done.
 */

const {
  countedHabitCountOn,
  liveHabitCountOn,
  storedScheduledOn,
} = require('./day_rules');

/**
 * The dailyScheduledCount write for [dayKey] of one participant of [room],
 * next to a done count of [done]. [scheduled] is the --scheduled override,
 * or null.
 *
 * Returns `{action, value, fallback, live, readsNow, reads, why}`:
 *   action   'keep' (touch nothing), 'write' (store `value`), or 'delete'
 *            (remove the key, so reads fall back);
 *   fallback countedHabitCountOn for the day, the participant-only count;
 *   live     the plan's count that day (liveHabitCountOn);
 *   readsNow what the app's paying path reads for the day before the write
 *            (recordedScheduledCountFor), and `reads` after it;
 *   why      one line for the dry run.
 *
 *  - An override is written, except that one equal to the fallback deletes
 *    the key: the same sparse invariant the sync keeps, compared against
 *    the same participant-only count, never against the plan's.
 *  - A stored key is kept. The sync wrote it knowing the day's schedule
 *    (rest days, quota weeks), which neither count here can see.
 *  - With no key, the key is written when the plan's count differs from the
 *    fallback, unless the record excuses the day itself: after this write
 *    it would read 0 for a met quota week's blank day (storedScheduledOn),
 *    and a key would turn that rest day into a miss.
 */
function scheduledKeyPlan({ room, participant, dayKey, done, scheduled, offsetMinutes }) {
  const p = participant || {};
  const fallback = countedHabitCountOn({ participant: p, dayKey });
  const live = liveHabitCountOn({ room, participant: p, dayKey });
  const base = {
    fallback,
    live,
    readsNow: storedScheduledOn({ room, participant: p, dayKey, offsetMinutes }),
  };
  // The day as the app will read it after this write with no key for it.
  // Sparse, like the write itself: a zero is no key at all.
  const doneAfter = { ...(p.dailyDoneCount || {}) };
  if (done > 0) doneAfter[dayKey] = done;
  else delete doneAfter[dayKey];
  const scheduledAfter = { ...(p.dailyScheduledCount || {}) };
  delete scheduledAfter[dayKey];
  const recordedAfter = storedScheduledOn({
    room,
    participant: { ...p, dailyDoneCount: doneAfter, dailyScheduledCount: scheduledAfter },
    dayKey,
    offsetMinutes,
  });
  if (scheduled !== null && scheduled !== undefined) {
    if (scheduled === fallback) {
      return {
        ...base, action: 'delete', value: null, reads: recordedAfter,
        why: `equal to the ${fallback} the app falls back to without one`,
      };
    }
    return { ...base, action: 'write', value: scheduled, reads: scheduled, why: 'as given' };
  }
  const stored = (p.dailyScheduledCount || {})[dayKey];
  if (typeof stored === 'number') {
    return { ...base, action: 'keep', value: stored, reads: stored, why: 'stored by the sync' };
  }
  if (recordedAfter !== fallback) {
    return {
      ...base, action: 'keep', value: null, reads: recordedAfter,
      why: 'no key, and the record excuses this day by itself',
    };
  }
  if (live !== fallback) {
    return {
      ...base, action: 'write', value: live, reads: live,
      why: `the plan's count; without a key the app would read ${fallback}, ` +
          'counting the habits the leader took out',
    };
  }
  return { ...base, action: 'keep', value: null, reads: fallback, why: 'no key needed' };
}

module.exports = { scheduledKeyPlan };
