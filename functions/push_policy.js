/**
 * The rules that decide whether ONE person may receive ONE room push right
 * now: their quiet hours, and how many pushes of each kind they have had
 * today.
 *
 * Split out of index.js for the same reason room_events.js is: requiring
 * index.js calls admin.initializeApp(), which needs credentials, so
 * anything left in there is only ever exercised in production. Everything
 * here is pure (a clock and the stored maps in, a decision out) and pinned
 * by test/push_policy.test.js.
 *
 * ── No spam, as two rules ────────────────────────────────────────────────
 *
 *  1. Quiet hours apply to EVERYONE, defaulting to the app's own default
 *     window (22:00 to 07:00) when an account has never mirrored its
 *     settings. Before this, a member whose settings had never been written
 *     (every account that had not opened notification settings on the
 *     current build) was read as "no quiet hours at all", so a Fajr habit
 *     finished at 04:30 pushed "first to finish, your turn" to their whole
 *     room at 04:30. A window can only be checked against a clock, so a
 *     member whose device has never reported its UTC offset is still sent
 *     to: the app mirrors the offset on every sign-in and resume, so this
 *     is rare and short-lived, and refusing to send at all would silence
 *     them for a guess.
 *
 *  2. At most one HEADS-UP, one NUDGE and one CELEBRATION per person per
 *     day. The three pushes fall into those three kinds: "first to finish"
 *     informs, "you're the last one" asks for something, and "perfect day"
 *     celebrates. The old rule was three of anything, first come first
 *     served, so someone in five rooms could spend all three on morning
 *     heads-ups from three rooms and then never hear the one push that
 *     actually needed them in the evening. Separate caps mean an
 *     informational push can never crowd out an actionable one. One nudge
 *     is enough: it opens the app, where every room is visible.
 *
 *     A fourth push, the evening "nobody has finished in your room yet",
 *     also took the nudge slot until it was removed on 2026-09-16. The
 *     kinds and the caps are unchanged by that: they were never a count of
 *     how many pushes exist, they are a ceiling on what one person hears.
 *
 *     The celebration has its own slot rather than sharing the heads-up's
 *     because of how a room-day actually plays out: everyone but the first
 *     finisher has already received "first to finish" by the time the last
 *     person finishes, so a shared slot would have silenced "perfect day"
 *     for the whole room on exactly the day it is earned. It is also rare
 *     by construction (every member finished), which is what makes a third
 *     slot affordable: the typical day is one push, a good day two, and a
 *     perfect day three.
 *
 *     A push counts against the day it is ABOUT, not the day it lands (see
 *     roomPushPlan's quotaDay). A push held past quiet hours used to claim
 *     the morning it was delivered on, so yesterday's news spent today's
 *     slot and blocked today's real push (نور, 2026-09-24: capped from 07:02).
 *
 *  3. A push about a day that is over is never an ask (Aziz, 2026-09-24).
 *     "You're the last one" and "first to finish" only mean something on
 *     their own day. Sent the next morning they read as today and point at
 *     the wrong day, and they went out even to someone who had finished
 *     (نور, 24 Sep 07:02, about a day finished at 23:47). So they are sent
 *     only while the reader is still on that day, and never held past it.
 *     "Perfect day" too: a celebration of yesterday arriving the next
 *     morning gives the reader nothing (Aziz, 2026-09-24: every
 *     notification has to be useful and kind). Only "a habit was added"
 *     still waits for the morning, because it is news that asks for
 *     something: linking the habit.
 */

/** The app's own default quiet window (NotificationSettings' defaults). */
const DEFAULT_QUIET_SETTINGS = Object.freeze({
  quietHoursEnabled: true,
  quietHoursStart: "22:0",
  quietHoursEnd: "7:0",
});

/**
 * "22:0" / "07:30" -> minutes since midnight, or null if unparseable.
 * @param {*} hhmm The stored string.
 * @return {number|null} Minutes, or null.
 */
function toMinutes(hhmm) {
  if (typeof hhmm !== "string") return null;
  const parts = hhmm.split(":");
  if (parts.length !== 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  return h * 60 + m;
}

/**
 * The recipient's clock, as minutes since their local midnight.
 * @param {number} tzOffsetMinutes Their device's UTC offset.
 * @param {number} nowMs The moment, as epoch milliseconds.
 * @return {number} 0..1439.
 */
function localMinutes(tzOffsetMinutes, nowMs) {
  const now = new Date(nowMs);
  const utcMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  return ((utcMinutes + tzOffsetMinutes) % 1440 + 1440) % 1440;
}

/**
 * Whether [settings] put [localMin] inside a quiet window.
 *
 * Missing settings mean the app's defaults, not "no window": see rule 1
 * above. A window whose start equals its end is zero-width and never
 * suppresses anything, matching the app's own isMinuteWithinQuietHours.
 * @param {object|undefined} settings The mirrored notificationSettings.
 * @param {number} localMin Minutes since the recipient's local midnight.
 * @return {boolean} Whether this minute is quiet for them.
 */
function isQuietAtLocalMinute(settings, localMin) {
  const s = settings || DEFAULT_QUIET_SETTINGS;
  if (s.quietHoursEnabled !== true) return false;
  const startMin = toMinutes(s.quietHoursStart);
  const endMin = toMinutes(s.quietHoursEnd);
  if (startMin === null || endMin === null || startMin === endMin) {
    return false;
  }
  if (startMin < endMin) {
    return localMin >= startMin && localMin < endMin;
  }
  // Overnight window, e.g. 22:00 -> 7:00.
  return localMin >= startMin || localMin < endMin;
}

/**
 * Whether it is quiet hours for this person right now.
 * @param {object|undefined} settings Their mirrored notificationSettings,
 *     or undefined for an account that never wrote them.
 * @param {number|undefined} tzOffsetMinutes Their device's UTC offset, or
 *     undefined if never reported (then nothing can be judged: not quiet).
 * @param {number} [nowMs] The moment; defaults to now. A parameter so the
 *     rule can be tested at every hour rather than whenever the suite runs.
 * @return {boolean} Whether to hold the push.
 */
function isQuietHoursNow(settings, tzOffsetMinutes, nowMs = Date.now()) {
  if (typeof tzOffsetMinutes !== "number") return false;
  return isQuietAtLocalMinute(settings, localMinutes(tzOffsetMinutes, nowMs));
}

/**
 * Milliseconds from [nowMs] until this person's quiet hours next end, in
 * THEIR local time — how long a held push should wait before it is worth
 * retrying.
 *
 * Quiet hours used to mean "never told," not "not right now": a push
 * suppressed here used to be dropped for good (see index.js's
 * notifyRoomFinish doc comment on the room-goes-silent cost). Scheduling
 * redelivery for the exact minute the window ends is the fix — no polling,
 * no periodic sweep re-checking everyone every few minutes forever whether
 * or not anything is actually waiting; one Cloud Task per held push, timed
 * once.
 *
 * Only meaningful to call on someone who is CURRENTLY quiet (see
 * isQuietHoursNow) — a caller that got here anyway (window disabled, or
 * malformed start/end) gets a full day back rather than zero or a negative
 * number, so nothing is ever scheduled in the past or for right now.
 * @param {object|undefined} settings Their mirrored notificationSettings.
 * @param {number} tzOffsetMinutes Their device's UTC offset.
 * @param {number} [nowMs] The moment; defaults to now.
 * @return {number} Milliseconds until quiet hours end, 60000..86400000.
 */
function msUntilQuietHoursEnd(settings, tzOffsetMinutes, nowMs = Date.now()) {
  const s = settings || DEFAULT_QUIET_SETTINGS;
  const endMin = toMinutes(s.quietHoursEnd);
  const DAY_MS = 24 * 60 * 60 * 1000;
  if (endMin === null) return DAY_MS;
  const nowLocalMin = localMinutes(tzOffsetMinutes, nowMs);
  const deltaMin = ((endMin - nowLocalMin) % 1440 + 1440) % 1440;
  // 0 means "this very minute is the boundary" - a caller asking that is
  // either racing the clock or the window is zero-width; either way, a full
  // day is the safe answer, never zero.
  return (deltaMin === 0 ? 1440 : deltaMin) * 60 * 1000;
}

/** Which kind each push is, per rule 2 above. */
const PUSH_KIND = Object.freeze({
  firstToday: "info",
  perfect: "celebrate",
  lastOne: "nudge",
});

/** How many of each kind one person may receive in one local day. */
const KIND_CAPS = Object.freeze({info: 1, nudge: 1, celebrate: 1});

/**
 * The kind of push an event produces. An unknown event is treated as
 * informational: a new push nobody has classified yet gets the plain
 * heads-up slot, never a slot of its own.
 * @param {string} event One of the PUSH_KIND keys.
 * @return {string} A KIND_CAPS key.
 */
function pushKindFor(event) {
  return PUSH_KIND[event] || "info";
}

/**
 * Pure transition on the stored per-user quota map.
 *
 * The map is `roomPushQuota: {date, info, nudge, celebrate}` on the user
 * doc. A map from an EARLIER day (or the old `{date, count}` shape) counts
 * as empty: the day rolled, so everyone starts at zero. A map already
 * counting a LATER day means this push is about a day the person has moved
 * past: it is refused, since writing it would reset the later day's counts.
 * @param {object|undefined} quota The stored map, if any.
 * @param {string} dayKey The day the push counts against, "YYYY-MM-DD"
 *     (roomPushPlan's quotaDay).
 * @param {string} kind A KIND_CAPS key; anything else is read as "info".
 * @return {{allowed: boolean, next: object}} Whether this push may go, and
 *     the map to store if it does (unchanged when it may not).
 */
function claimQuota(quota, dayKey, kind) {
  const q = quota || {};
  if (typeof q.date === "string" && q.date > dayKey) {
    return {allowed: false, next: q};
  }
  const sameDay = q.date === dayKey;
  const counts = {date: dayKey};
  for (const k of Object.keys(KIND_CAPS)) {
    counts[k] = sameDay && typeof q[k] === "number" ? q[k] : 0;
  }
  const slot = KIND_CAPS[kind] === undefined ? "info" : kind;
  if (counts[slot] >= KIND_CAPS[slot]) {
    return {allowed: false, next: counts};
  }
  return {allowed: true, next: {...counts, [slot]: counts[slot] + 1}};
}

/**
 * How long after quiet hours end a held push is delivered. Cloud Tasks has
 * second-level jitter, and firing even a minute early would land back
 * inside the window it was waiting out.
 */
const HOLD_BUFFER_MS = 2 * 60 * 1000;

/**
 * The moment a push held now for this person would be delivered.
 * @param {object|undefined} settings Their mirrored notificationSettings.
 * @param {number} tzOffsetMinutes Their device's UTC offset.
 * @param {number} [nowMs] The moment; defaults to now.
 * @return {number} Epoch milliseconds.
 */
function heldUntilMs(settings, tzOffsetMinutes, nowMs = Date.now()) {
  return nowMs + msUntilQuietHoursEnd(settings, tzOffsetMinutes, nowMs) +
    HOLD_BUFFER_MS;
}

/**
 * A person's calendar day at [nowMs], from their mirrored UTC offset (UTC
 * when they never reported one).
 * @param {number|undefined} tzOffsetMinutes Their device's UTC offset.
 * @param {number} [nowMs] The moment; defaults to now.
 * @return {string} "YYYY-MM-DD".
 */
function localDayKey(tzOffsetMinutes, nowMs = Date.now()) {
  const offset = typeof tzOffsetMinutes === "number" ? tzOffsetMinutes : 0;
  return new Date(nowMs + offset * 60 * 1000).toISOString().slice(0, 10);
}

/** [key] moved by [n] days, "YYYY-MM-DD" in and out. */
function shiftDay(key, n) {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** The pushes that only mean something on the day they are about. */
const SAME_DAY_ONLY = Object.freeze(["firstToday", "lastOne", "perfect"]);

/**
 * What to do with one room push for one reader, from the day it is about
 * and the reader's own day. Rule 3 at the top of this file.
 *
 * `quotaDay` is the day the push counts against (rule 2): the day it is
 * about, or the reader's own day when that is earlier (a reader whose clock
 * is behind the finisher's, for whom the finisher's "today" is still their
 * today).
 * @param {object} p
 * @param {string} p.event "firstToday" | "lastOne" | "perfect" |
 *     "habitAdded".
 * @param {string} p.dayKey The day the push is about, "YYYY-MM-DD".
 * @param {string} p.readerToday The reader's own calendar day now.
 * @param {boolean} [p.quiet] Whether the reader is inside quiet hours now.
 * @param {string} [p.heldUntilDay] The reader's calendar day when a push
 *     held now would be delivered (localDayKey of heldUntilMs). Read only
 *     when [p.quiet].
 * @return {{action: string, yesterday: boolean, quotaDay: string,
 *     reason: (string|undefined)}} action is "send", "hold" or "drop";
 *     yesterday is set when the reader's day has moved past [p.dayKey].
 */
function roomPushPlan({event, dayKey, readerToday, quiet = false,
  heldUntilDay}) {
  const yesterday = dayKey < readerToday;
  const quotaDay = yesterday ? dayKey : readerToday;
  const plan = (action, reason) => ({action, yesterday, quotaDay, reason});
  const sameDayOnly = SAME_DAY_ONLY.includes(event);
  if (yesterday && sameDayOnly) return plan("drop", "past-day");
  // Nothing is held for more than a day, so a push about a day before
  // yesterday is a delivery gone wrong, never news.
  if (yesterday && shiftDay(readerToday, -1) !== dayKey) {
    return plan("drop", "too-old");
  }
  if (quiet) {
    if (sameDayOnly && (heldUntilDay || readerToday) > dayKey) {
      return plan("drop", "quiet-past-its-day");
    }
    return plan("hold");
  }
  return plan("send");
}

/**
 * A device token this much older than the account's freshest one belongs to
 * an install the person no longer uses: a phone the app was deleted from, or
 * one replaced by a newer install. The app rewrites its own token's
 * updatedAt once a day while it is used (push_notification_service.dart),
 * so a gap this wide is not a device in use.
 */
const STALE_TOKEN_GAP_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Splits one account's device tokens into the ones a push goes to and the
 * stale ones to delete.
 *
 * Only ever relative to the account's own freshest token: a person using
 * none of their devices lately keeps every token, since a room push may be
 * what brings them back. نور had two, one not refreshed since 13 Sep, and
 * every push reached her twice (2026-09-24).
 * @param {Array<{updatedAtMs: (number|null|undefined)}>} tokens One entry
 *     per token doc; any other fields are carried through untouched.
 * @return {{live: Array, stale: Array}}
 */
function liveTokens(tokens) {
  if (tokens.length <= 1) return {live: tokens.slice(), stale: []};
  const ms = (t) => (typeof t.updatedAtMs === "number" ? t.updatedAtMs : 0);
  const newest = Math.max(...tokens.map(ms));
  const live = [];
  const stale = [];
  for (const t of tokens) {
    (ms(t) < newest - STALE_TOKEN_GAP_MS ? stale : live).push(t);
  }
  return {live, stale};
}

/**
 * How long after the admin sends a message to everyone a copy held for
 * quiet hours may still go out. The admin tool sends to everyone at most
 * once in this window (lib/broadcast.js), so a held copy can never land on
 * the same day as the next message.
 */
const HELD_BROADCAST_MAX_MS = 24 * 60 * 60 * 1000;

/**
 * Whether a message from the admin, held for one person's quiet hours, goes
 * out now that they have ended (index.js deliverHeldBroadcast).
 *
 * Page item 6 (Aziz, 2026-09-24): someone asleep when it was sent used to
 * never get it at all. Held to the end of their quiet hours, it is decided
 * afresh when it lands, the way a held room push is: the person may have
 * switched notifications off in between, and if they are still quiet (the
 * window was moved after it was held) it is dropped rather than chased.
 * @param {object} p
 * @param {number|null} p.sentAtMs When the admin sent it.
 * @param {object|undefined} p.settings Their mirrored notificationSettings.
 * @param {number|undefined} p.tzOffsetMinutes Their device's UTC offset.
 * @param {number} [p.nowMs] The moment; defaults to now.
 * @return {{action: string, reason: (string|undefined)}} "send" or "drop".
 */
function heldBroadcastPlan({sentAtMs, settings, tzOffsetMinutes,
  nowMs = Date.now()}) {
  if (typeof sentAtMs !== "number" ||
      nowMs - sentAtMs > HELD_BROADCAST_MAX_MS) {
    return {action: "drop", reason: "too-late"};
  }
  if (settings && settings.masterEnabled === false) {
    return {action: "drop", reason: "master-off"};
  }
  if (isQuietHoursNow(settings, tzOffsetMinutes, nowMs)) {
    return {action: "drop", reason: "still-quiet"};
  }
  return {action: "send"};
}

module.exports = {
  DEFAULT_QUIET_SETTINGS,
  HELD_BROADCAST_MAX_MS,
  HOLD_BUFFER_MS,
  KIND_CAPS,
  PUSH_KIND,
  SAME_DAY_ONLY,
  STALE_TOKEN_GAP_MS,
  claimQuota,
  heldBroadcastPlan,
  heldUntilMs,
  isQuietAtLocalMinute,
  isQuietHoursNow,
  liveTokens,
  localDayKey,
  localMinutes,
  msUntilQuietHoursEnd,
  pushKindFor,
  roomPushPlan,
  shiftDay,
};
