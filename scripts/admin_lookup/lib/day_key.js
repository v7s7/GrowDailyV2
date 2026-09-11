'use strict';

/**
 * Day keys the way the MEMBER'S OWN PHONE writes them.
 *
 * Every date key the app stores is the calendar date on the phone that wrote
 * it, never a UTC date and never this machine's date:
 *
 *   - Timestamp.toDate() gives a LOCAL DateTime, and toDateKey formats that
 *     DateTime's local year, month and day fields
 *     (lib/core/extensions/datetime_ext.dart:34-37).
 *   - A room's first day is room.startDate.toDateKey()
 *     (lib/features/rooms/notifiers/rooms_notifier.dart:3264), and a slot
 *     the leader added later floors at DateTime(added.year, added.month,
 *     added.day).toDateKey() on the addedAt that RoomHabitTemplate.fromJson
 *     read with Timestamp.toDate() (planFloorFor,
 *     rooms_notifier.dart:3279-3290; room_model.dart:218). Both run on the
 *     member's phone.
 *
 * So a script that keys a Timestamp with toISOString() is a day early for
 * anything stamped between midnight and 03:00 in Bahrain, and one that uses
 * the machine's own getDate() is only right while the machine and the member
 * share a timezone. Room ELQVF8, Hoor, slot 2: addedAt
 * 2026-09-08T21:48:29.651Z is 2026-09-09 on her +180 phone and 2026-09-08 in
 * UTC. Room ZCNGFT, mohdabood2003 (+240): startDate 2026-07-14T20:00Z is
 * 2026-07-15 on his phone and 2026-07-14 on a +180 Mac.
 *
 * The phone's offset is users/{uid}.tzOffsetMinutes, written by
 * _syncAmbientAccountFacts as DateTime.now().timeZoneOffset.inMinutes
 * (lib/main.dart:1467-1474), positive east of UTC. A key here is the instant
 * shifted by that offset, read back through its UTC fields, so the result
 * never depends on the timezone of the machine running the script.
 *
 * It is the offset at the member's LAST app open, applied to every instant,
 * so a member who has travelled, or lives in a zone with daylight saving,
 * can be keyed a day off for an instant within an hour of midnight. On
 * 2026-09-11 every member with the field is +180 or +240, neither of which
 * observes daylight saving.
 *
 * A member without the field (on 2026-09-11 the only room member without it
 * is mbuasallay, room 5S84CL) falls back to Asia/Bahrain, +180 with no
 * daylight saving, and offsetOf says so with assumed: true, so a caller can
 * refuse to write anything on a guessed calendar.
 */

const APP_FALLBACK_OFFSET_MINUTES = 180;

const MINUTE_MS = 60 * 1000;
const DAY_MS = 24 * 60 * MINUTE_MS;
// The largest instant a JS Date can hold; toISOString throws past it.
const MAX_DATE_MS = 8.64e15;

// An ISO string that names its zone: a trailing Z, or +hh:mm / +hhmm.
const ZONED_SUFFIX = /(?:[zZ]|[+-]\d\d:?\d\d)$/;

/**
 * The member's phone offset from their users/{uid} data.
 * @param {?object} u users/{uid} data, or null when there is no document.
 * @return {{minutes: number, assumed: boolean}} assumed is true when the
 *   offset was not recorded and the Asia/Bahrain fallback was used.
 */
function offsetOf(u) {
  const m = u == null ? undefined : u.tzOffsetMinutes;
  // 0 is a real offset (a phone on UTC), so test the type, not truthiness.
  if (typeof m === 'number' && Number.isFinite(m)) {
    return { minutes: m, assumed: false };
  }
  return { minutes: APP_FALLBACK_OFFSET_MINUTES, assumed: true };
}

/** The instant [ms] moved onto a phone clock [minutes] east of UTC, or null. */
function shifted(ms, minutes) {
  if (typeof ms !== 'number' || !Number.isFinite(ms)) return null;
  if (typeof minutes !== 'number' || !Number.isFinite(minutes)) return null;
  const t = ms + minutes * MINUTE_MS;
  return Math.abs(t) <= MAX_DATE_MS ? t : null;
}

/**
 * "YYYY-MM-DD" for the instant [ms] on a phone [minutes] east of UTC.
 * @param {number} ms Epoch milliseconds.
 * @param {number} minutes Offset, e.g. 180 for Bahrain.
 * @return {?string} null when [ms] is not a usable instant.
 */
function keyAtOffset(ms, minutes) {
  const t = shifted(ms, minutes);
  return t === null ? null : new Date(t).toISOString().slice(0, 10);
}

/**
 * The day key of a Firestore Timestamp on the member's phone.
 * @param {*} ts Anything with toDate(); everything else is null.
 * @param {number} minutes
 * @return {?string}
 */
function tsKey(ts, minutes) {
  if (!ts || typeof ts.toDate !== 'function') return null;
  const d = ts.toDate();
  return d && typeof d.getTime === 'function' ? keyAtOffset(d.getTime(), minutes) : null;
}

/**
 * The day key of a date field exactly as stored, which is not always a
 * Timestamp (custom_habits createdAt is a string on some documents).
 *
 *   - Timestamp or Date: an instant, keyed at [minutes].
 *   - A string that names its zone (Z or +hh:mm): also an instant.
 *   - Any other string of ten characters or more: Dart's toIso8601String()
 *     of a LOCAL DateTime, which carries no zone and whose first ten
 *     characters already ARE the phone's date. It is returned as written and
 *     never handed to new Date, which would read it in THIS machine's zone.
 *
 * @param {*} raw
 * @param {number} minutes
 * @return {?string}
 */
function storedDateKey(raw, minutes) {
  if (raw && typeof raw.toDate === 'function') return tsKey(raw, minutes);
  if (raw instanceof Date) return keyAtOffset(raw.getTime(), minutes);
  if (typeof raw !== 'string') return null;
  if (ZONED_SUFFIX.test(raw)) return keyAtOffset(Date.parse(raw), minutes);
  return raw.length >= 10 ? raw.slice(0, 10) : null;
}

/**
 * Minutes past midnight on the member's phone for the instant [ms], 0 to
 * 1439, or null when [ms] is not a usable instant.
 */
function localMinuteOfDay(ms, minutes) {
  const t = shifted(ms, minutes);
  if (t === null) return null;
  return Math.floor((((t % DAY_MS) + DAY_MS) % DAY_MS) / MINUTE_MS);
}

module.exports = {
  APP_FALLBACK_OFFSET_MINUTES,
  keyAtOffset,
  localMinuteOfDay,
  offsetOf,
  storedDateKey,
  tsKey,
};
