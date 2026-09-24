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
// RoomHabitMark.rest.code: the habit was in the plan that day but its own
// schedule asked nothing of it (room_model.dart, enum RoomHabitMark).
const REST_MARK = "r";
const DECLINED = "__declined__";

// lib/core/extensions/datetime_ext.dart's kDayCutoffHour: a day stays open
// for marking until this hour the NEXT morning, and a mark made in that tail
// is paid in full by the Grid.
const DAY_CUTOFF_HOUR = 10;

// Asia/Bahrain, +180 with no daylight saving, the calendar every room key is
// written on. Used only to place a day's close on the real clock.
const APP_OFFSET_MINUTES = 180;

const HOUR_MS = 60 * 60 * 1000;

/**
 * The real instant [key] stops being open, for comparing against a Firestore
 * Timestamp without moving the timestamp into anybody's calendar first.
 *
 * 2026-09-10 at +180 closes at 2026-09-11T07:00Z, which is 10:00 the next
 * morning on the member's own clock.
 * @param {string} key "YYYY-MM-DD"
 * @param {number} [offsetMinutes] Phone offset, positive east of UTC.
 * @return {number} Epoch milliseconds.
 */
function closesAtInstantMs(key, offsetMinutes) {
  const off = typeof offsetMinutes === "number" && Number.isFinite(offsetMinutes) ?
      offsetMinutes : APP_OFFSET_MINUTES;
  const [y, m, d] = String(key).split("-").map(Number);
  return Date.UTC(y, m - 1, d) - off * 60 * 1000 + (24 + DAY_CUTOFF_HOUR) * HOUR_MS;
}

/** Epoch ms of anything Firestore hands back as a time, or null. */
function instantMsOf(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") {
    const d = v.toDate();
    return d && typeof d.getTime === "function" ? d.getTime() : null;
  }
  if (v instanceof Date) return v.getTime();
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

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
 * Whether shared slot [i] of [room] is in the plan on [dayKey] as far as the
 * leader's plan edits go: RoomHabitTemplate.liveOn in the app. Not inside an
 * `offSpans` stretch, and before `stopsOn` if the leader removed it. A
 * removal with no `stopsOn` is a legacy one (before 2026-09-22, or
 * dedupe_plan_slot.js) and counts on no day at all.
 * @param {object} room The room doc's data.
 * @param {number} i The slot index.
 * @param {string} dayKey "YYYY-MM-DD".
 * @return {boolean}
 */
function slotLiveOn(room, i, dayKey) {
  if (room.habitMode !== "shared") return true;
  const shared = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  if (i < 0 || i >= shared.length) return true;
  const t = shared[i] || {};
  const spans = Array.isArray(t.offSpans) ? t.offSpans : [];
  if (spans.some((s) => s && s.from <= dayKey && dayKey <= s.to)) return false;
  if (!t.removedAt) return true;
  if (typeof t.stopsOn !== "string") return false;
  return dayKey < t.stopsOn;
}

/**
 * The habits a relinked shared slot held before its current one, for slot
 * [i]: `part.slotHabitHistory["i"]`, each `{habitId, until}` with `until`
 * the last day (inclusive) it filled the slot, oldest first. The mirror of
 * RoomParticipant.slotHabitHistory in the app; malformed entries are
 * dropped the way the app drops them.
 * @param {object} part The participant doc's data.
 * @param {number} i The slot.
 * @return {Array<{habitId: string, until: string}>}
 */
function slotHistory(part, i) {
  const all = part.slotHabitHistory;
  const list = all && typeof all === "object" ? all[String(i)] : null;
  if (!Array.isArray(list)) return [];
  return list
      .filter((h) => h && typeof h.habitId === "string" && h.habitId !== "" &&
          typeof h.until === "string" && h.until !== "")
      .sort((a, b) => (a.until < b.until ? -1 : a.until > b.until ? 1 : 0));
}

/**
 * The linked habit ids that actually count for a participant: every slot
 * except one the person declined and, in a shared-plan room, one the leader
 * has taken out of the plan. The same filter diagnose_room.js applies.
 *
 * With [dayKey], the ids whose slot is in the plan THAT day (a habit the
 * leader removed still counts on its removal day and the days before, see
 * slotLiveOn), each slot answered by the habit that filled it that day: a
 * slot the member relinked (RoomsController.relinkPlanHabit) names its
 * earlier habit on the days before the change, as RoomParticipant.
 * habitInSlotOn does in the app. Without that, the sweep read the new
 * habit's squares back over days it was not in the slot and logged them as
 * undercounts, with a repair command that would have re-scored those days.
 *
 * Without [dayKey], every id graded on SOME day: all but a legacy removal,
 * and the habits a relinked slot held before.
 * @param {object} room The room doc's data.
 * @param {object} part The participant doc's data.
 * @param {string} [dayKey] "YYYY-MM-DD".
 * @return {Array<string>}
 */
function countingHabitIds(room, part, dayKey) {
  const linked = Array.isArray(part.linkedHabitIds) ? part.linkedHabitIds : [];
  const shared = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  const isShared = room.habitMode === "shared";
  const legacyRemoved = (i) => {
    const t = shared[i] || {};
    return !!(t.removedAt && typeof t.stopsOn !== "string");
  };
  if (dayKey !== undefined) {
    const out = [];
    linked.forEach((id, i) => {
      if (!isShared || i >= shared.length) {
        if (id !== DECLINED) out.push(id);
        return;
      }
      if (!slotLiveOn(room, i, dayKey)) return;
      const held = slotHistory(part, i).find((h) => dayKey <= h.until);
      if (held) {
        out.push(held.habitId);
        return;
      }
      if (id !== DECLINED) out.push(id);
    });
    return out;
  }
  const out = linked.filter((id, i) => {
    if (id === DECLINED) return false;
    if (!isShared || i >= shared.length) return true;
    return !legacyRemoved(i);
  });
  if (isShared) {
    linked.forEach((_, i) => {
      if (i >= shared.length || legacyRemoved(i)) return;
      for (const h of slotHistory(part, i)) {
        if (!out.includes(h.habitId)) out.push(h.habitId);
      }
    });
  }
  return out;
}

/**
 * How long after its last day an ended room is still checked. Two weekly runs
 * at least (the lookback is wider than the gap between runs), after which a
 * room that ended keeps nothing new to find.
 */
const ENDED_ROOM_CHECK_DAYS = 14;

/**
 * The closed days of a room worth re-checking: the last [lookback] days of
 * the room's window that ended before [lastClosedKey], skipping days the
 * room was paused on.
 *
 * Nothing for a room that ended more than ENDED_ROOM_CHECK_DAYS before
 * [lastClosedKey]. No room is ever marked ended, so every room ever finished
 * came back each Monday to have its same last days re-read for every member,
 * a cost that grew with every room forever (2026-09-22). Its final days were
 * already checked by at least two earlier runs, and a room its leader
 * extends has a later endKey and is checked again.
 * @param {{startKey: string, endKey: (string|null), pausedSpans: Array}} r
 * @param {string} lastClosedKey The newest day that has fully closed.
 * @param {number} lookback How many closed days back to look.
 * @return {Array<string>}
 */
function closedDaysToCheck(r, lastClosedKey, lookback) {
  if (r.endKey &&
      r.endKey < shiftKey(lastClosedKey, -ENDED_ROOM_CHECK_DAYS)) {
    return [];
  }
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
 *
 * ── HELD days, and why they must never be "fixed" ─────────────────────────
 *
 * A lower stored count is not automatically a fault. The rooms' own
 * anti-backdating clamp HOLDS a closed day at the count it already had,
 * deliberately, so nobody colours in last month for room credit
 * (syncLinkedHabitsProgress, rooms_notifier.dart). This check ignored the
 * clamp entirely and so reported the app working as designed: room ELQVF8,
 * Aziz, 2026-09-10, "stored 2, squares say 3", where square_audit shows the
 * تمرين square was painted after the day had closed, carried no completion
 * and paid no XP. The report printed a set_room_day.js --confirm line for
 * it, and running that would have written the day up and lifted him from
 * 65.9% to 68.9% on a ranked board for a day he did not train.
 *
 * The clamp stands aside for exactly one case, roomDayMarkedWhileOpen: a day
 * whose document was LAST written before it closed can only hold marks made
 * on time, so the room missed them rather than the person making them late.
 * The day's `lastUpdated` is a server timestamp and cannot be moved by a
 * device clock, which is what makes it usable as evidence here.
 *
 * So a day is HELD, and gets no repair command, when both are true:
 *   1. the day document's last write landed at or after the day's close, and
 *   2. the room had already graded that day (lastSyncedAt at or after the
 *      same close, RoomParticipant.wasObservedOn).
 *
 * Absent evidence never produces a HELD verdict: a caller that passes no
 * [lastUpdatedByDay] gets exactly the old behaviour, because claiming the
 * app is holding a day when we cannot see when it was written would hide a
 * real undercount. Reporting is the safe side, since nothing here writes.
 *
 * @param {object} args
 * @param {Array<string>} args.days The closed day keys to check.
 * @param {Array<string>} args.countingIds From [countingHabitIds].
 * @param {Object<string, object>} args.squaresByDay day key -> the day
 * doc's squareStates map (habit id -> state), or undefined for no doc.
 * @param {object} args.part The participant doc's data.
 * @param {Object<string, *>} [args.lastUpdatedByDay] day key -> that day
 * document's `lastUpdated` (Timestamp, Date or epoch ms). The evidence for
 * rule 1 above.
 * @param {Object<string, *>} [args.createdByDay] day key -> the document's
 * Firestore createTime. Never changes a verdict; it only lets the report say
 * that a held day was first opened on time.
 * @param {number} [args.offsetMinutes] The member's phone offset, positive
 * east of UTC. Defaults to Asia/Bahrain.
 * @param {object} [args.room] The room doc's data. When given, each day is
 * checked against the habits in the plan that day (slotLiveOn).
 * @return {Array<{day: string, real: number, stored: number, held: boolean,
 * why: string}>} `held` days are reported for information and must never be
 * handed a set_room_day.js command.
 */
function undercountedDays({days, countingIds, squaresByDay, part,
  lastUpdatedByDay, createdByDay, offsetMinutes, room}) {
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
  // What the member's own device decided each habit was worth that day.
  // A habit marked REST was not in the day's denominator: a day off its
  // named weekdays, or a session past a weekly quota the member had
  // already banked. Its square can be green and earn nothing, exactly as
  // the app grades it.
  const marks = part.dailyHabitMarks || {};
  const restedOn = (day, id) => {
    const forDay = marks[day];
    return !!forDay && String(forDay[id]) === REST_MARK;
  };
  const out = [];
  for (const day of days) {
    if (stood.has(day)) continue;
    // A day the sync recorded as owing nothing (rest day) cannot be short.
    if (scheduled[day] === 0) continue;
    const squares = squaresByDay[day] || {};
    // Only the habits in the plan that day: one the leader removed is not
    // owed after its removal day, and its green square there is the
    // member's own business. Without [room] every day reads the same set,
    // as before.
    const dayIds = room ?
      countingHabitIds(room, part, day).filter((id) => countingIds.includes(id)) :
      countingIds;
    const real = dayIds.filter((id) => {
      const floor = floors.get(id);
      if (floor !== null && floor !== undefined && day < floor) return false;
      // The whole-day rest test above only catches a day where EVERY habit
      // rested. A single habit resting inside a working day is the common
      // case for a weekly quota, and counting its green square as owed was
      // reporting a shortfall that does not exist and printing a repair
      // command that would have paid for a day the room never asked for.
      if (restedOn(day, id)) return false;
      return GREEN.has(String(squares[id]));
    }).length;
    const stored = done[day] || 0;
    if (real <= stored) continue;

    // The two pieces of evidence the clamp itself turns on. `syncedMs` is
    // read the same way RoomParticipant.wasObservedOn reads it, falling back
    // to the day watermark for a document written before the instant was
    // recorded.
    const closes = closesAtInstantMs(day, offsetMinutes);
    const writtenMs = instantMsOf((lastUpdatedByDay || {})[day]);
    const syncedMs = instantMsOf(part.lastSyncedAt);
    const observed = syncedMs !== null ? syncedMs >= closes :
        (typeof part.lastSyncedDay === "string" && day <= part.lastSyncedDay);
    const writtenLate = writtenMs !== null && writtenMs >= closes;

    if (writtenLate && observed) {
      const madeMs = instantMsOf((createdByDay || {})[day]);
      const opened = madeMs !== null && madeMs < closes ?
        " The day document was first written while the day was still open, " +
        "so the room graded what was there at the time." : "";
      out.push({
        day, real, stored, held: true,
        why: "the room is holding this day on purpose: its record was last " +
            `written ${new Date(writtenMs).toISOString()}, after the day ` +
            `closed ${new Date(closes).toISOString()}, and the room had ` +
            "already graded it. A square painted after a day closes earns " +
            `nothing in the app either.${opened}`,
      });
      continue;
    }
    out.push({day, real, stored, held: false, why: ""});
  }
  return out;
}

module.exports = {
  clipSpansToPast,
  closedDaysToCheck,
  countingHabitIds,
  slotLiveOn,
  keyOf,
  shiftKey,
  todayKeyIn,
  undercountedDays,
};
