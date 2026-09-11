/**
 * Which of the room's three daily push events a finish just caused.
 *
 * Split out of index.js purely so it can be tested: requiring index.js
 * calls admin.initializeApp(), which needs credentials, so the one piece
 * of real branching logic in this feature would otherwise only ever be
 * exercised in production. See index.js's message tables for why the unit
 * is an event rather than a finisher.
 */

/**
 * @param {Array<{id: string, data: function(): object}>} others Every
 * participant doc EXCEPT the caller, whose own finish is what got us here.
 * @param {string} todayKey The finisher's app day, "YYYY-MM-DD".
 * @param {Array<{from: string, to: string}>} [pausedSpans] The room doc's
 * pausedSpans field, as stored. See isRoomPausedOn.
 * @return {{event: string, recipients: Array}|null} The event and exactly
 * who should hear about it, or null when nobody should.
 */
function roomEventFor(others, todayKey, pausedSpans) {
  if (others.length === 0) return null;
  // A day inside the room's paused spans (RoomModel.pausedSpans: the dead
  // days between a room ending and its leader extending it) is a day the
  // room does not count. RoomModel.memberCountsOn skips it for everyone, so
  // teamDayResult reads it as no day at all. The last-one push promises
  // «ويصير يوم الغرفة كامل 🤝» and the perfect push announces «يوم كامل», a
  // complete room day the app will never show, so neither is sent. The
  // first-to-finish push still is: it says only who finished first today,
  // and promises nothing about the room's day.
  const paused = isRoomPausedOn(pausedSpans, todayKey);
  // A member standing down today (RoomParticipant.standDownDays, a paused
  // habit: the day leaves both sides of their score) is asked nothing today.
  // Their phone never marks such a day finished, so counting them as
  // unfinished used to make them the "last one left" and hand them an ask
  // about a day they were excused from.
  const present = others.filter(
      (d) => !isStandingDownOn(d.data() || {}, todayKey));
  const standingDown = others.length - present.length;
  const unfinished = present.filter((d) => {
    const p = d.data() || {};
    return !(p.allDoneToday === true && p.allDoneDate === todayKey);
  });
  // Order matters where two events could apply at once. In a two-person
  // room the very first finish is ALSO the moment one person is left
  // standing, and "you're the last one" is the more useful of the two - so
  // firstToday is the fallback, checked last, not the default.
  if (unfinished.length === 0) {
    // A perfect day still means everyone, so a day someone stands down is
    // not one (unchanged from before they were skipped here). Nor is a day
    // the room is paused.
    return standingDown > 0 || paused ?
      null : {event: "perfect", recipients: others};
  }
  if (unfinished.length === 1) {
    // No fallback to firstToday: in a room of three or more, others have
    // already finished, and "first one done today" would be false.
    return paused ? null : {event: "lastOne", recipients: unfinished};
  }
  return {event: "firstToday", recipients: unfinished};
}

/**
 * Whether [dayKey] falls inside one of the room's paused spans, read the
 * way the app reads them (RoomModel.isPausedOn and RoomModel.spansFrom in
 * lib/features/rooms/models/room_model.dart): `[{from, to}]` date keys,
 * both ends inclusive, compared as strings. An entry that is not an object
 * with a string from and a string to, or whose from is after its to, is
 * skipped, as the app drops it when the room loads.
 * @param {Array<{from: string, to: string}>|undefined} pausedSpans The room
 * doc's pausedSpans field, as stored.
 * @param {string} dayKey "YYYY-MM-DD".
 * @return {boolean}
 */
function isRoomPausedOn(pausedSpans, dayKey) {
  if (!Array.isArray(pausedSpans)) return false;
  return pausedSpans.some((s) => s !== null && typeof s === "object" &&
    typeof s.from === "string" && typeof s.to === "string" &&
    s.from <= s.to && s.from <= dayKey && dayKey <= s.to);
}

/**
 * Whether a member is standing down on [dayKey], the finisher's today.
 *
 * Two ways to know, because nothing on the server writes standDownDays: only
 * the member's own phone does, and only for the days its sync grades.
 *   - Their phone wrote today's key. Both syncs grade today and record it
 *     (rooms_notifier.dart syncTodayForHabit and syncLinkedHabitsProgress).
 *   - Their phone has not synced today, and the last day it did sync
 *     (lastSyncedDay) was itself a stand-down: every counted habit paused.
 *
 * The second is the member a pause is for. Paused on Monday and not opened
 * since, they have no key for Thursday, and reading only today's key made
 * them the "last one left" and asked them for a habit they had paused. A
 * pause only ends inside the app, by hand or by a booked return that
 * main.dart's _maybeAutoResumeDueHabits applies when the app opens, and
 * opening the app resyncs every room (main.dart _resyncMyRooms), which moves
 * lastSyncedDay to today. So until that sync lands, the pause still stands.
 *
 * Two readings this still gets wrong, both because the server only sees what
 * a sync wrote:
 *   - a booked return date that passed while the app stayed closed. The
 *     habit is due again once the app opens, but the booking lives only on
 *     the phone;
 *   - a pause no sync has seen. Pausing a habit writes nothing to the room;
 *     the key lands on the next sync (a return to the app, opening the room,
 *     or a Grid tap on a counted habit, rooms_notifier.dart syncHabitDay). A
 *     member who paused after their last sync that day and closed the app
 *     still reads as present until their phone syncs again.
 * @param {object} p A participant doc's data.
 * @param {string} dayKey "YYYY-MM-DD".
 * @return {boolean}
 */
function isStandingDownOn(p, dayKey) {
  const days = Array.isArray(p.standDownDays) ? p.standDownDays : [];
  if (days.includes(dayKey)) return true;
  const synced = p.lastSyncedDay;
  return typeof synced === "string" && synced < dayKey &&
    days.includes(synced);
}

module.exports = {isRoomPausedOn, isStandingDownOn, roomEventFor};
