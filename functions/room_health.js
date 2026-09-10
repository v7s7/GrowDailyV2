/**
 * The rules behind the rooms health sweep, kept free of Firestore so they
 * can be unit-tested and shared with the admin script.
 *
 * Two questions, asked of every active room:
 *
 * 1. Does any pause span reach today or later? A pause is only ever the
 *    dead time between a room's old finish line and the day it was
 *    extended, which by construction ends yesterday
 *    (pausedSpansAfterExtend in rooms_notifier.dart). A span that reaches
 *    the future can only come from an old build or a bug, and it silently
 *    stops every member's days from counting: on 2026-09-04 the leader of
 *    PBYAS5 tapped the 30th on the resume calendar the old build showed,
 *    and the room read موقوف for three days before anyone traced it. The
 *    sweep clips such a span to yesterday, the same cut resume_room.js
 *    makes by hand.
 *
 * 2. Does any member's stored count trail their real squares on a day that
 *    has already closed? The room's progress is written by each member's
 *    own phone (syncLinkedHabitsProgress); a phone that never opened the
 *    room, or a day held by the anti-backdating clamp, leaves the stored
 *    count at zero while the person's Grid says done. The sweep only
 *    REPORTS these, never writes them: the phone regrades the day itself
 *    once it opens (roomDayMarkedWhileOpen), and a server write would fight
 *    that sync. The report names the exact set_room_day.js command for a
 *    day that needs a hand.
 *
 * Used by index.js (roomsHealthSweep, scheduled) and by
 * scripts/admin_lookup/check_rooms.js (the same check from a terminal).
 */

const GREEN = new Set(["complete", "bonus"]); // SquareState.isGreen
const DECLINED = "__declined__";

/**
 * "YYYY-MM-DD" for a Date, in that Date's own local calendar.
 * @param {Date} d
 * @return {string}
 */
function keyOf(d) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/**
 * The day key [n] days after [key]. Pure calendar arithmetic on the key's
 * own digits, so it never depends on the machine's timezone.
 * @param {string} key "YYYY-MM-DD"
 * @param {number} n Days to add; negative to go back.
 * @return {string}
 */
function shiftKey(key, n) {
  const [y, m, d] = key.split("-").map(Number);
  const t = Date.UTC(y, m - 1, d + n);
  const out = new Date(t);
  const p = (v) => String(v).padStart(2, "0");
  return `${out.getUTCFullYear()}-${p(out.getUTCMonth() + 1)}-` +
      `${p(out.getUTCDate())}`;
}

/**
 * Today's key in a named timezone, e.g. "Asia/Bahrain". The sweep runs on
 * a server whose clock is UTC, and a pause span is a local calendar date
 * the leader's phone wrote, so "today" has to be read in the app's own
 * timezone or a span could be clipped a few hours early.
 * @param {number} nowMs
 * @param {string} timeZone
 * @return {string}
 */
function todayKeyIn(nowMs, timeZone) {
  // en-CA formats as YYYY-MM-DD, which is exactly the app's key.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(nowMs));
}

/**
 * Cuts every pause span so that none reaches [todayKey] or later. Mirrors
 * pausedSpansAfterExtend's clip in rooms_notifier.dart and resume_room.js:
 * a span that starts today or later is dropped, one that reaches today is
 * cut to yesterday.
 * @param {Array<{from: string, to: string}>} spans As stored on the room.
 * @param {string} todayKey
 * @return {{spans: Array<{from: string, to: string}>, clipped: Array<{from:
 * string, to: string}>}} The spans to keep, and the ones that were wrong.
 */
function clipSpansToPast(spans, todayKey) {
  const yesterday = shiftKey(todayKey, -1);
  const keep = [];
  const clipped = [];
  for (const s of Array.isArray(spans) ? spans : []) {
    if (!s || typeof s.from !== "string" || typeof s.to !== "string") continue;
    if (s.to < todayKey) {
      keep.push({from: s.from, to: s.to});
      continue;
    }
    clipped.push({from: s.from, to: s.to});
    if (s.from >= todayKey) continue;
    keep.push({from: s.from, to: yesterday});
  }
  return {spans: keep, clipped};
}

/**
 * The linked habit ids that actually count for a participant: every slot
 * except one the person declined and, in a shared-plan room, one the
 * leader has removed. The same filter diagnose_room.js applies.
 * @param {object} room The room doc's data.
 * @param {object} part The participant doc's data.
 * @return {Array<string>}
 */
function countingHabitIds(room, part) {
  const linked = Array.isArray(part.linkedHabitIds) ? part.linkedHabitIds : [];
  const shared = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  return linked.filter((id, i) => {
    if (id === DECLINED) return false;
    const removed = room.habitMode === "shared" && i < shared.length &&
        !!shared[i].removedAt;
    return !removed;
  });
}

/**
 * The closed days of a room worth re-checking: the last [lookback] days of
 * the room's window that ended before [lastClosedKey], skipping days the
 * room was paused on.
 * @param {{startKey: string, endKey: (string|null), pausedSpans: Array}} r
 * @param {string} lastClosedKey The newest day that has fully closed.
 * @param {number} lookback How many closed days back to look.
 * @return {Array<string>}
 */
function closedDaysToCheck(r, lastClosedKey, lookback) {
  const last = r.endKey && r.endKey < lastClosedKey ? r.endKey : lastClosedKey;
  if (last < r.startKey) return [];
  const spans = Array.isArray(r.pausedSpans) ? r.pausedSpans : [];
  const paused = (k) => spans.some((s) => s && s.from <= k && k <= s.to);
  const out = [];
  for (let k = last; k >= r.startKey && out.length < lookback;
    k = shiftKey(k, -1)) {
    if (!paused(k)) out.push(k);
  }
  return out.reverse();
}

/**
 * The days on which a member's stored done count is lower than the number
 * of counting habits their own squares say were done.
 * @param {object} args
 * @param {Array<string>} args.days The closed day keys to check.
 * @param {Array<string>} args.countingIds From [countingHabitIds].
 * @param {Object<string, object>} args.squaresByDay day key -> the day
 * doc's squareStates map (habit id -> state), or undefined for no doc.
 * @param {object} args.part The participant doc's data.
 * @return {Array<{day: string, real: number, stored: number}>}
 */
function undercountedDays({days, countingIds, squaresByDay, part}) {
  const done = part.dailyDoneCount || {};
  const scheduled = part.dailyScheduledCount || {};
  const stood = new Set(Array.isArray(part.standDownDays) ?
      part.standDownDays : []);
  // The day each habit's room rule starts - the day it was linked into the
  // plan (RoomParticipant.slotOpenBy on the client). A slot added to a
  // running room, or linked late, is not graded on the days before that,
  // so a green square there is the member's own business and not an
  // undercount; reporting it used to hand out a set_room_day.js command
  // that would have written the higher number in. No rule recorded means
  // no floor, exactly as the client fails open.
  const rules = part.habitRules || {};
  const floorOf = (id) => {
    const periods = Array.isArray(rules[id]) ? rules[id] : [];
    let floor = null;
    for (const r of periods) {
      const from = r && typeof r.from === "string" ? r.from : null;
      if (from && (floor === null || from < floor)) floor = from;
    }
    return floor;
  };
  const floors = new Map(countingIds.map((id) => [id, floorOf(id)]));
  const out = [];
  for (const day of days) {
    if (stood.has(day)) continue;
    // A day the sync recorded as owing nothing (rest day) cannot be short.
    if (scheduled[day] === 0) continue;
    const squares = squaresByDay[day] || {};
    const real = countingIds.filter((id) => {
      const floor = floors.get(id);
      if (floor !== null && floor !== undefined && day < floor) return false;
      return GREEN.has(String(squares[id]));
    }).length;
    const stored = done[day] || 0;
    if (real > stored) out.push({day, real, stored});
  }
  return out;
}

module.exports = {
  clipSpansToPast,
  closedDaysToCheck,
  countingHabitIds,
  keyOf,
  shiftKey,
  todayKeyIn,
  undercountedDays,
};
