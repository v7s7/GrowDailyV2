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
 *     day. The four pushes fall into those three kinds: "first to finish"
 *     informs, "you're the last one" and the evening "nobody has finished"
 *     ask for something, and "perfect day" celebrates. The old rule was
 *     three of anything, first come first served, so someone in five rooms
 *     could spend all three on morning heads-ups from three rooms and then
 *     never hear the one push that actually needed them in the evening.
 *     Separate caps mean an informational push can never crowd out an
 *     actionable one. One nudge is enough: it opens the app, where every
 *     room is visible.
 *
 *     The celebration has its own slot rather than sharing the heads-up's
 *     because of how a room-day actually plays out: everyone but the first
 *     finisher has already received "first to finish" by the time the last
 *     person finishes, so a shared slot would have silenced "perfect day"
 *     for the whole room on exactly the day it is earned. It is also rare
 *     by construction (every member finished), which is what makes a third
 *     slot affordable: the typical day is one push, a good day two, and a
 *     perfect day three.
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

/** Which kind each push is, per rule 2 above. */
const PUSH_KIND = Object.freeze({
  firstToday: "info",
  perfect: "celebrate",
  lastOne: "nudge",
  eveningReminder: "nudge",
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
 * doc. A map from another day (or the old `{date, count}` shape) counts as
 * empty: the day rolled, so everyone starts at zero.
 * @param {object|undefined} quota The stored map, if any.
 * @param {string} dayKey The recipient's local day, "YYYY-MM-DD".
 * @param {string} kind A KIND_CAPS key; anything else is read as "info".
 * @return {{allowed: boolean, next: object}} Whether this push may go, and
 *     the map to store if it does (unchanged when it may not).
 */
function claimQuota(quota, dayKey, kind) {
  const q = quota || {};
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

module.exports = {
  DEFAULT_QUIET_SETTINGS,
  KIND_CAPS,
  PUSH_KIND,
  claimQuota,
  isQuietAtLocalMinute,
  isQuietHoursNow,
  localMinutes,
  pushKindFor,
};
