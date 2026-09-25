'use strict';

/**
 * The Overview's numbers: every tile, chart and panel on the control room's
 * first view, computed from the same scan the Activity and Accounts views
 * read (lib/activity.js), so the three can never disagree.
 *
 * Pure: a scan and a clock in, plain data out, no Firestore. That is what
 * lets test/overview.test.js pin every number against a scan it wrote.
 *
 * Two limits of the scan decide what the charts are allowed to show:
 *
 *   - Habit days, tasks and milestones come from each account's most recent
 *     documents only (scan.limits: the last 14 daily documents, the last ten
 *     tasks and milestones). A chart of habit activity over 30 or 90 days
 *     would show a cliff at day 15 that is the edge of the scan, not a drop
 *     in use. So every activity trend here is TREND_DAYS long.
 *   - Sign-ups and account creation come from Firebase Auth, which has all of
 *     them. The growth line is the one chart that goes back to the start.
 *
 * Days are Bahrain days (the app's fallback zone, lib/day_key.js), the same
 * clock the rest of the tool uses for "today".
 */

const { keyAtOffset, APP_FALLBACK_OFFSET_MINUTES } = require('./day_key');

const DAY_MS = 86400000;
const MINUTE_MS = 60000;

/** Days in every activity trend. Must not exceed scan.limits.daily. */
const TREND_DAYS = 14;

/**
 * What the stacked activity chart counts, in slot order (the palette's first
 * five categorical slots, validated in lib/shell.js). Five, not the ten raw
 * event types: past five a stacked bar stops being readable, so the small
 * ones fold into Other.
 */
const CATEGORIES = [
  { id: 'habits', label: 'Days logged', types: ['habits'] },
  { id: 'tasks', label: 'Tasks', types: ['task_new', 'task_done'] },
  { id: 'milestones', label: 'Milestones', types: ['milestone'] },
  { id: 'signups', label: 'New accounts', types: ['signup'] },
  { id: 'other', label: 'Other', types: null },
];

/**
 * Event types that are not someone doing something, left out of every count
 * here. A sign-in is Auth's lastSignIn: ONE per account, the latest, and a
 * phone restoring its session in the background produces one without anybody
 * opening the app. Charted per day it would be "accounts whose last sign-in
 * fell that day", which looks like a trend and is not one. lib/activity.js
 * leaves it out of lastActiveAt for the same reason.
 */
const NOT_AN_ACTION = new Set(['signin']);

/**
 * Event types that do not make someone "active": the sign-in above, and the
 * sign-up, which lastActiveAt also skips. Kept identical to lastActiveAt's
 * rule so "Active today" here and on the Accounts view are the same people.
 */
const NOT_ACTIVITY = new Set(['signin', 'signup']);

const LEADERS = 8;
const BOARD = 12;

/** Epoch milliseconds from a number or an ISO string, else null. */
function msOf(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value) {
    const t = Date.parse(value);
    return Number.isFinite(t) ? t : null;
  }
  return null;
}

function nameOf(a) {
  return a.displayName || a.email || String(a.uid || '').slice(0, 8);
}

function categoryOf(type) {
  for (const c of CATEGORIES) {
    if (c.types && c.types.includes(type)) return c.id;
  }
  return 'other';
}

/**
 * Everything the Overview shows.
 * @param {{accounts: object[], events: object[], onlineWindowMinutes?: number}} scan
 * @param {number} now Epoch milliseconds.
 * @param {number} offset Minutes east of UTC for "a day" (Bahrain by default).
 */
function buildOverview(scan, now = Date.now(), offset = APP_FALLBACK_OFFSET_MINUTES) {
  const accounts = (scan && scan.accounts) || [];
  const events = (scan && scan.events) || [];
  const dayKey = (ms) => keyAtOffset(ms, offset);
  const hourOf = (ms) => new Date(ms + offset * MINUTE_MS).getUTCHours();

  const today = dayKey(now);
  const yesterday = dayKey(now - DAY_MS);
  // Bahrain keeps no daylight saving, so stepping whole days back from now
  // always lands on consecutive dates.
  const days = [];
  for (let i = TREND_DAYS - 1; i >= 0; i--) days.push(dayKey(now - i * DAY_MS));
  const indexOfDay = new Map(days.map((d, i) => [d, i]));

  // ---- Tiles ----------------------------------------------------------
  const onlineMs = (scan && scan.onlineWindowMinutes ? scan.onlineWindowMinutes : 15) * MINUTE_MS;
  const kpis = {
    onlineNow: 0,
    activeToday: 0,
    activeYesterday: 0,
    activeWeek: 0,
    newWeek: 0,
    newPrevWeek: 0,
    accountsTotal: accounts.length,
    // Accounts with no creation date (no Auth record left), which the growth
    // line cannot place. Said beside the line, so its last point and the
    // total above it never look like they disagree.
    undatedAccounts: 0,
    squaresDone: 0,
    squaresScheduled: 0,
    peopleScheduledToday: 0,
  };
  for (const a of accounts) {
    const last = msOf(a.lastActiveAt);
    if (last !== null) {
      if (now - last <= onlineMs) kpis.onlineNow++;
      if (now - last <= 7 * DAY_MS) kpis.activeWeek++;
    }
    const created = msOf(a.createdAt);
    if (created !== null) {
      if (now - created <= 7 * DAY_MS) kpis.newWeek++;
      else if (now - created <= 14 * DAY_MS) kpis.newPrevWeek++;
    }
    if (a.todayKey === today && (a.todayScheduled || 0) > 0) {
      kpis.squaresDone += a.todayDone || 0;
      kpis.squaresScheduled += a.todayScheduled || 0;
      kpis.peopleScheduledToday++;
    }
  }

  // ---- Series ---------------------------------------------------------
  const activeSets = days.map(() => new Set());
  const byCategory = CATEGORIES.map((c) => ({ id: c.id, label: c.label, counts: days.map(() => 0) }));
  const categoryIndex = new Map(CATEGORIES.map((c, i) => [c.id, i]));
  const hours = new Array(24).fill(0);
  for (const e of events) {
    const at = msOf(e.at);
    if (at === null || NOT_AN_ACTION.has(e.type)) continue;
    const i = indexOfDay.get(dayKey(at));
    if (i === undefined || at > now) continue;
    if (e.uid && !NOT_ACTIVITY.has(e.type)) activeSets[i].add(e.uid);
    byCategory[categoryIndex.get(categoryOf(e.type))].counts[i]++;
    // A dayOnly event (lib/activity.js) counts for its day but has no hour:
    // its anchor would pile every undo onto 12:00 and every preset onto 00:00.
    if (!e.dayOnly) hours[hourOf(at)]++;
  }
  const activeByDay = activeSets.map((s) => s.size);
  // The tile and the chart's last bar are one number, read from the same
  // events by the same rule as lastActiveAt, so they cannot disagree.
  kpis.activeToday = activeByDay[days.length - 1];
  kpis.activeYesterday = activeByDay[days.length - 2] || 0;

  const signupsByDay = days.map(() => 0);
  const createdDays = [];
  for (const a of accounts) {
    const created = msOf(a.createdAt);
    if (created === null || created > now) {
      kpis.undatedAccounts++;
      continue;
    }
    createdDays.push(dayKey(created));
    const i = indexOfDay.get(dayKey(created));
    if (i !== undefined) signupsByDay[i]++;
  }

  // Accounts that existed at the end of each week, counted back from today
  // to the week of the first account. Weekly rather than daily: a year and a
  // half of daily points is noise at the size this is drawn.
  createdDays.sort();
  const growth = [];
  if (createdDays.length) {
    const first = createdDays[0];
    for (let back = 0; ; back += 7) {
      const day = dayKey(now - back * DAY_MS);
      let total = 0;
      for (const d of createdDays) {
        if (d <= day) total++;
        else break;
      }
      growth.unshift({ day, total });
      if (day < first) break;
    }
  }

  // ---- Panels ---------------------------------------------------------
  const streakLeaders = accounts
    .filter((a) => (a.currentStreak || 0) > 0)
    .sort((a, b) => (b.currentStreak || 0) - (a.currentStreak || 0) || (b.level || 0) - (a.level || 0))
    .slice(0, LEADERS)
    .map((a) => ({ uid: a.uid, name: nameOf(a), streak: a.currentStreak || 0, level: a.level || 0 }));

  const board = accounts
    .filter((a) => a.todayKey === today && (a.todayScheduled || 0) > 0)
    .map((a) => ({
      uid: a.uid,
      name: nameOf(a),
      done: Math.min(a.todayDone || 0, a.todayScheduled),
      scheduled: a.todayScheduled,
    }))
    .sort((a, b) => b.done / b.scheduled - a.done / a.scheduled || b.done - a.done || a.name.localeCompare(b.name));

  // How recently each account last did something (lastActiveAt, which skips
  // sign-ins). The shape of the whole user base in four numbers: who is
  // using the app, who is drifting, who has gone, who never started.
  const recency = [
    { id: 'week', label: 'Active in the last 7 days', count: 0 },
    { id: 'month', label: '8 to 30 days ago', count: 0 },
    { id: 'older', label: 'More than 30 days ago', count: 0 },
    { id: 'never', label: 'Nothing recorded yet', count: 0 },
  ];
  for (const a of accounts) {
    const last = msOf(a.lastActiveAt);
    const bucket = last === null ? 3 : now - last <= 7 * DAY_MS ? 0 : now - last <= 30 * DAY_MS ? 1 : 2;
    recency[bucket].count++;
  }

  return {
    today,
    yesterday,
    days,
    trendDays: TREND_DAYS,
    kpis,
    series: { activeByDay, signupsByDay, byCategory, hours, growth },
    panels: {
      streakLeaders,
      todayBoard: board.slice(0, BOARD),
      todayBoardTotal: board.length,
      recency,
    },
  };
}

module.exports = { buildOverview, CATEGORIES, TREND_DAYS };
