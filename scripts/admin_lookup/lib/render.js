'use strict';

/**
 * Shared HTML-rendering helpers for the admin lookup tool.
 *
 * Used by both lookup_user.js (writes one standalone report file) and
 * server.js (renders the same report live, on demand, plus a searchable
 * home page) — kept in one module so the two never drift into showing
 * different things for the same account. Nothing in this file touches
 * Firestore/Auth directly; it only turns already-fetched data into HTML.
 */

// Friendlier section titles for the subcollections known to exist today
// (see firestore.rules' top-of-file doc comment for the canonical map).
// Anything not listed here still shows up — just titled with its raw
// collection name — since the section list itself comes from
// listCollections(), not from this map. Add a new subcollection anywhere
// in the app and the report picks it up automatically; this map is purely
// cosmetic, never a filter.
const KNOWN_LABELS = {
  daily: 'Daily activity (Grid, intentions, night review)',
  custom_habits: 'Custom habits',
  focus_plans: 'Focus sessions',
  matrix_tasks: 'Matrix tasks',
  weekly_challenges: 'Weekly challenges',
  milestones: 'Milestone events',
};

// Known users/{uid} fields worth pulling into the always-visible header
// stat row, in display order — everything else on the profile doc (there's
// a lot: per-habit streak maps, notification settings, catalog history...)
// stays reachable in the "All profile fields" details block instead of
// crowding this into a wall of numbers. Purely a display allowlist — it
// never filters what's actually captured, only what's promoted to the
// header.
const HIGHLIGHT_FIELDS = [
  ['level', 'Level'],
  ['currentStreak', 'Streak'],
  ['longestStreak', 'Best streak'],
  ['gold', 'Gold'],
  ['cumulativeXp', 'Total XP'],
  ['totalHabitCompletions', 'Completions'],
  ['totalGreenSquares', 'Green squares'],
  ['streakFreezes', 'Freezes'],
  ['themePreset', 'Theme'],
  ['premiumActive', 'Premium'],
];

// Per-collection display metadata, mirroring this app's own enums exactly
// (habit_model.dart's HabitCategory, night_review/models/mood.dart's Mood,
// matrix/models/matrix_task.dart's MatrixQuadrant) so a habit/task/mood
// here reads with the same label and color family the app itself shows the
// user - just an emoji standing in for a Flutter IconData, since this is a
// plain HTML page with no Material icon font loaded. Colors are the same
// hex values GameColors defines (lib/core/theme/game_theme.dart), not
// invented ones, so e.g. "DO FIRST" here is the same red the app's own
// Matrix screen paints it.
const CATEGORY_META = {
  faith: { emoji: '📖', label: 'Faith' },
  quran: { emoji: '📖', label: 'Faith' },
  athkar: { emoji: '📖', label: 'Faith' },
  fasting: { emoji: '📖', label: 'Faith' },
  sadaqah: { emoji: '📖', label: 'Faith' },
  health: { emoji: '💪', label: 'Health' },
  fitness: { emoji: '💪', label: 'Health' },
  learning: { emoji: '🎓', label: 'Learning' },
  focus: { emoji: '🎯', label: 'Focus' },
  sleep: { emoji: '🌙', label: 'Sleep' },
  money: { emoji: '💰', label: 'Money' },
  mind: { emoji: '🧠', label: 'Mind' },
  social: { emoji: '👥', label: 'Social' },
  custom: { emoji: '⭐', label: 'Custom' },
};

const MOOD_META = {
  great: { emoji: '😄', label: 'Great', color: 'var(--mood-great)' },
  good: { emoji: '🙂', label: 'Good', color: 'var(--mood-good)' },
  neutral: { emoji: '😐', label: 'Neutral', color: 'var(--mood-neutral)' },
  sad: { emoji: '😔', label: 'Sad', color: 'var(--mood-sad)' },
  exhausted: { emoji: '😩', label: 'Exhausted', color: 'var(--mood-exhausted)' },
};

const QUADRANT_META = {
  doFirst: { label: 'Do First', subtitle: 'Urgent · Important', color: 'var(--q-do)' },
  schedule: { label: 'Schedule', subtitle: 'Important, not urgent', color: 'var(--q-sched)' },
  delegate: { label: 'Delegate', subtitle: 'Urgent, not important', color: 'var(--q-deleg)' },
  eliminate: { label: 'Eliminate', subtitle: 'Neither', color: 'var(--q-elim)' },
};

const WEEKDAY_ABBR = { 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun' };

// Reads a date out of any of the three shapes this schema actually uses -
// a Firestore Timestamp (matrix_tasks' createdAt/completedAt/reminderAt),
// a plain ISO-8601 string (custom_habits' createdAt/archivedAt - see
// IslamicHabitTemplate.toFirestore's own comment on why: that exact map is
// reused for the guest Hive store, which can't serialize a Timestamp), or
// already a native Date - so every caller below can just ask for a date
// without needing to know which one a given field happens to use.
function toJsDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

// Mirrors lib/core/extensions/datetime_ext.dart's kDayCutoffHour exactly -
// a habit finished at 2am still belongs to "yesterday" for streak/scheduling
// purposes, not to a fresh, unstarted "today". Kept as its own named
// constant (not inlined below) so a future change to the app's own cutoff
// is a one-line update here too.
//
// It sat at 6 after the app had already moved to 10, which is the exact
// failure that comment was written to prevent. The cost was four hours a
// day: between 06:00 and 10:00 local this report called it a new day while
// the phone in the person's hand was still finishing the old one, so the
// Day tab showed an empty board for a day they had not reached yet and
// scored yesterday's real work as missed. Anything comparing this constant
// against the app must read the Dart file, not this line's history.
const DAY_CUTOFF_HOUR = 10;

// Same computation as DateTime.now().effectiveDay, ported to plain JS.
//
// ── THIS USED TO SHIFT BACK BY DAY_CUTOFF_HOUR, AND NO LONGER DOES ──
//
// datetime_ext.dart's effectiveDay is now a plain `startOfDay`: the app's
// new day starts at midnight, everywhere, with no exception. What the
// cutoff bought is kept explicitly instead, as the PREVIOUS day staying
// open for marking until kDayCutoffHour (isOpenDay / isInGraceWindow), so
// a night owl still finishes yesterday and still earns its streak point.
//
// This tool kept subtracting the ten hours after the app stopped, which
// meant that between 00:00 and 09:59 local it called yesterday "today":
// a report opened at 01:07 on 6 September headed itself "Sep 5, 2026 ·
// today" while its own task board, four inches lower, said "calendar day
// 2026-09-06". Two different days on one screen, one of them labelled
// today, and the habit board showing the wrong one.
//
// DAY_CUTOFF_HOUR is still the right constant and still lives above,
// because dayWriteContext needs it to recognise a mark made before the
// app's own fix landed. It just no longer decides which day is today.
//
// [tzOffsetMinutes] is this account's last-known device UTC offset (mirrored
// by main.dart's _syncAmbientAccountFacts to users/{uid}.tzOffsetMinutes -
// see that function's doc comment). A device that has never reported one
// (an old install, or a Firestore-only account with no matching Auth
// session) falls back to this machine's own local timezone - a reasonable
// guess for a single-admin local tool, and never worse than assuming UTC.
//
// Returns {year, month, day, weekday, key}, where weekday is
// 1=Monday..7=Sunday (Dart's DateTime.weekday convention, not JS's
// 0=Sunday..6=Saturday - see the conversion below) so it can be compared
// directly against HabitModel.scheduledWeekdays' own stored ints.
function effectiveTodayParts(tzOffsetMinutes) {
  const now = new Date();
  const localMs = typeof tzOffsetMinutes === 'number'
    ? now.getTime() + tzOffsetMinutes * 60000
    : now.getTime() - now.getTimezoneOffset() * 60000;
  // `localMs` was built to represent local wall-clock time, so reading it
  // back with the UTC getters (not the local ones) gives the right calendar
  // date regardless of what timezone this Node process itself is running in.
  const shifted = new Date(localMs);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const day = shifted.getUTCDate();
  const jsWeekday = shifted.getUTCDay(); // 0=Sun..6=Sat
  const weekday = jsWeekday === 0 ? 7 : jsWeekday; // -> Dart's 1=Mon..7=Sun
  const key = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return { year, month, day, weekday, key };
}

// The TASK board's today, which is not the habit board's today.
//
// effectiveTodayParts above shifts by the habit cutoff (DAY_CUTOFF_HOUR),
// and using it for
// tasks was a real bug in this tool: matrix_screen.dart is explicit that a
// todo board runs on the calendar day, not the flex window ("at 12 AM the
// phone says a new day, and the board should agree ... This was effectiveDay
// once, which left the board looking stuck on yesterday until 6 in the
// morning"). Between midnight and the cutoff this page was therefore showing a
// different board than the user's own phone was.
function calendarTodayParts(tzOffsetMinutes) {
  const now = new Date();
  const localMs = typeof tzOffsetMinutes === 'number'
    ? now.getTime() + tzOffsetMinutes * 60000
    : now.getTime() - now.getTimezoneOffset() * 60000;
  const d = new Date(localMs);
  const year = d.getUTCFullYear();
  const month = d.getUTCMonth() + 1;
  const day = d.getUTCDate();
  const key = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return { year, month, day, key, startMs: Date.UTC(year, month - 1, day) };
}

/// The earliest reminder a task carries, or null.
///
/// Reads `reminderAts` (the list the app writes now) and falls back to the
/// singular `reminderAt` it still mirrors for older clients. The previous
/// version of this file only ever read the singular one, so a task with three
/// reminders showed one and a task written by a newer client showed whichever
/// the mirror happened to hold.
function earliestReminder(t) {
  const all = [];
  if (Array.isArray(t.reminderAts)) {
    for (const r of t.reminderAts) {
      const d = toJsDate(r);
      if (d) all.push(d);
    }
  }
  const legacy = toJsDate(t.reminderAt);
  if (legacy) all.push(legacy);
  if (all.length === 0) return null;
  all.sort((a, b) => a - b);
  return all[0];
}

/// Sorts every task into the four buckets an admin actually wants, using the
/// app's OWN rules rather than inventing new ones:
///
///   done      isDone, completed on the day being viewed
///   late      open on that day, created before it  (matrix_screen.dart
///             calls this "carried over" and the board has a chip for it)
///   upcoming  open, earliest reminder lands on a later day
///   today     open, created on that day
///
/// Precedence matters and follows the app: a future-dated task LEAVES today
/// even if it was created weeks ago, because "filing by the creation day
/// means a task you dated two weeks out sits in Today for two weeks, shouting
/// at you every morning about something you already decided wasn't for now".
/// So upcoming is tested first, and the four buckets are a clean partition.
///
/// [parts] is any day, not only today (see calendarTodayParts / dayKeyParts),
/// which is what lets the report's day picker show the board AS IT STOOD on
/// an old day instead of only the live one. The reconstruction is honest
/// about what the stored data can actually support:
///
///   - a task created after that day did not exist yet, so it is invisible
///   - a task finished before that day was already off the board
///   - a task finished AFTER that day was open on it, and shows as open
///
/// The one thing no reconstruction can recover is a task that was deleted:
/// this app writes no tombstone, so a task made and thrown away last March
/// leaves nothing behind to find. The day view says so out loud rather than
/// implying the history is complete (see renderDayCard's board note).
function triageTasksForDay(taskDocs, parts) {
  const out = { today: [], late: [], upcoming: [], done: [], noDate: [] };
  const dayStart = parts.startMs !== undefined
    ? parts.startMs
    : Date.UTC(parts.year, parts.month - 1, parts.day);
  const dayOf = (d) => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());

  for (const doc of taskDocs) {
    const t = doc.data ? doc.data() : doc;
    const row = { id: doc.id || '', data: t, reminder: earliestReminder(t) };

    const created = toJsDate(t.createdAt);
    const createdDay = created ? dayOf(created) : null;
    // Not born yet on the day being viewed.
    if (createdDay !== null && createdDay > dayStart) continue;

    // completedAt is only trusted when isDone agrees with it: MatrixTask.
    // toFirestore deletes the field on restore, but a doc written by an
    // older client can still carry a stale one, and reading it regardless
    // would file a live open task as finished.
    if (t.isDone) {
      const completed = toJsDate(t.completedAt);
      if (!completed) continue; // finished at an unknown time, unplaceable
      const completedDay = dayOf(completed);
      if (completedDay === dayStart) { out.done.push(row); continue; }
      if (completedDay < dayStart) continue; // already gone from that board
      // Finished later than the day being viewed, so it was still open then.
    }

    if (row.reminder && dayOf(row.reminder) > dayStart) {
      out.upcoming.push(row);
      continue;
    }
    if (createdDay === null) { out.noDate.push(row); continue; }
    if (createdDay < dayStart) out.late.push(row);
    else out.today.push(row);
  }

  const byQuadrant = (a, b) =>
    (QUADRANT_ORDER[a.data.quadrant] ?? 9) - (QUADRANT_ORDER[b.data.quadrant] ?? 9);
  const byReminder = (a, b) => (a.reminder || 0) - (b.reminder || 0);
  out.today.sort(byQuadrant);
  out.late.sort(byQuadrant);
  out.noDate.sort(byQuadrant);
  out.upcoming.sort(byReminder);
  return out;
}

/// The live board. Kept as its own name because that is what every existing
/// caller and test asks for; triageTasksForDay with today's parts is the
/// same computation.
function triageTasks(taskDocs, parts) {
  return triageTasksForDay(taskDocs, parts);
}

// Ports IslamicHabitTemplate.isScheduledFor (islamic_habit_catalog.dart)
// verbatim: never before the habit's own createdAt date, never after its
// archivedAt date (the archive day itself still counts), and on
// scheduledWeekdays only when a specific schedule is set - empty means
// every day. This is the exact rule the app itself uses to decide "is this
// habit even due today", so the admin Today card can't disagree with what
// the user's own app would show them.
function habitScheduledOnParts(habitData, parts) {
  const dayUtc = Date.UTC(parts.year, parts.month - 1, parts.day);
  const born = toJsDate(habitData.createdAt);
  if (born) {
    const bornUtc = Date.UTC(born.getFullYear(), born.getMonth(), born.getDate());
    if (dayUtc < bornUtc) return false;
  }
  const died = toJsDate(habitData.archivedAt);
  if (died) {
    const diedUtc = Date.UTC(died.getFullYear(), died.getMonth(), died.getDate());
    if (dayUtc > diedUtc) return false;
  }
  const weekdays = Array.isArray(habitData.scheduledWeekdays) ? habitData.scheduledWeekdays : [];
  return weekdays.length === 0 || weekdays.includes(parts.weekday);
}

// Parses a `daily/{key}` document id (always "YYYY-MM-DD" - see
// DateTimeGameExt.toDateKey on the Dart side, the exact format every write
// site uses) into the same {year, month, day, weekday, key} shape
// effectiveTodayParts returns for "today" - no cutoff-hour shifting needed
// here, since a stored key already IS the account's own effective day, not
// a raw clock reading that still needs adjusting. weekday is 1=Mon..7=Sun
// (Dart's DateTime.weekday convention), same conversion effectiveTodayParts
// uses, so this can feed habitScheduledOnParts identically for any
// historical date, not just "now".
function dayKeyParts(key) {
  const [y, m, d] = key.split('-').map(Number);
  const jsWeekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=Sun..6=Sat
  const weekday = jsWeekday === 0 ? 7 : jsWeekday;
  return { year: y, month: m, day: d, weekday, key };
}

// 0 (nothing done) to 4 (fully done) for one day's real completion ratio -
// the same graduated heat-tier idea as heatmapLevelFor (rooms_notifier.dart,
// the app's own Rooms feature) and heatLevel (monthly_heatmap_screen.dart,
// the app's own Grid heatmap): a day with SOME but not all scheduled habits
// done reads visibly lighter than a fully perfect one, never identical
// all-or-nothing shading. `scheduled` of 0 (a day nothing was actually due,
// or an account with no habits yet at all) reads as level 0, not a false
// "full" - there's nothing here to call complete either way.
function dayHeatLevel(done, scheduled) {
  if (scheduled <= 0 || done <= 0) return 0;
  const ratio = Math.min(1, done / scheduled);
  return Math.min(4, Math.max(1, Math.ceil(ratio * 4)));
}


// ── What a habit-day actually says, across all three of its records ──────
//
// The app writes THREE independent things for one habit on one day, from
// different code paths, and they do not always agree. This tool used to read
// only the first one, which made two real situations completely invisible.
// Everything here that counts or lists a habit-day goes through
// [readHabitDay] so they can never diverge again.
//
//   habitCompletions[h]    The reward-backed completion. Written by
//                          DashboardNotifier.completeHabit, DELETED by
//                          uncompleteHabit. The only one of the three that
//                          means XP, gold and the streak were actually paid.
//
//   completedAtMinutes[h]  Stamped by completeHabit (minutes since local
//                          midnight) and removed by NOTHING in the app, so
//                          it outlives an undo. Present with no completion
//                          beside it is the permanent fingerprint of
//                          "completed, then un-marked" - and unlike the
//                          undoneCompletions receipt, which is swept after
//                          kUndoneCompletionRetentionDays (365), it still
//                          reads correctly years later.
//
//   squareStates[h]        The Grid square the person actually sees, and the
//                          ONLY thing a Room grades off: see
//                          RoomsController.syncLinkedHabitsProgress, which
//                          reads squareStates and never once looks at
//                          habitCompletions.
//
// The gap between the first and the third is not theoretical. A square
// painted on a day the app did not consider "today" - which is every day
// between midnight and the 10 AM cutoff, since the Grid opens on the real
// calendar week while effectiveDay is still on yesterday - takes
// WeeklyGridNotifier.setSquare's anti-backdating branch. That branch writes
// squareStates and habit_history and returns: no XP, no gold, no streak, no
// habitCompletions. So the square scores in a Room while paying its owner
// nothing, and every completion-based surface, this report included, drew
// the day as empty. Room said "1 done", this page said "0/2", and both were
// faithfully reporting the field they read.

const SQUARE_META = {
  complete: { emoji: '🟩', label: 'done' },
  bonus: { emoji: '🟦', label: 'bonus' },
  partial: { emoji: '🟨', label: 'partly done' },
  failed: { emoji: '🟥', label: 'missed' },
  skipped: { emoji: '⬛', label: 'skipped' },
  none: { emoji: '⬜', label: 'empty' },
};

// SquareState.isGreen (square_state.dart) - complete||bonus, nothing else.
// This is the exact test a Room's sync applies, so it is the exact test for
// "will this square score somewhere the person can see".
const GREEN_SQUARES = new Set(['complete', 'bonus']);

// A cleared mark is stored as the literal string 'none' rather than removed
// (WeeklyGridNotifier._persistSquare writes value.toJson() whatever it is),
// so an absent key and a stored 'none' have to mean the same thing here.
function squareOf(dayData, habitId) {
  const raw = dayData && dayData.squareStates;
  if (!raw || typeof raw !== 'object') return 'none';
  const v = raw[habitId];
  return typeof v === 'string' && SQUARE_META[v] ? v : 'none';
}

// 908 -> "15:08". The stamp is minutes since the account's own local
// midnight (minutesSinceMidnight in dashboard_notifier_complete_habit.dart),
// already in their wall clock, so it needs no timezone maths - which is the
// whole reason it is stored this way rather than as an instant.
function fmtMinutes(mins) {
  if (!Number.isFinite(mins)) return '';
  const h = Math.floor(mins / 60) % 24;
  const m = Math.floor(mins) % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/**
 * Every outstanding undo receipt on the profile doc, keyed exactly the way
 * UndoneCompletion.keyFor writes it ('<habitId>|<dayKey>'), so a day can
 * look its own up without scanning the map.
 *
 * These are the app's own record of "marked, then un-marked": written by
 * uncompleteHabit whenever an undo takes a habit's LAST completion of a day
 * away, and removed again by restoreUndoneCompletion when the same habit-day
 * is marked back. So an empty map means one of three things, not one - never
 * undone, undone and already corrected, or undone over a year ago and swept
 * - which is exactly why readHabitDay leans on completedAtMinutes for the
 * durable answer and treats a receipt as the extra detail on top.
 */
function readUndoneReceipts(profileData) {
  const raw = profileData && profileData.undoneCompletions;
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [key, value] of Object.entries(raw)) {
    if (!value || typeof value !== 'object') continue;
    const habitId = value.habitId;
    const dateKey = value.dateKey;
    if (typeof habitId !== 'string' || !habitId) continue;
    if (typeof dateKey !== 'string' || !dateKey) continue;
    out[`${habitId}|${dateKey}`] = {
      habitId,
      dateKey,
      category: typeof value.category === 'string' ? value.category : null,
      xp: Number(value.xp) || 0,
      gold: Number(value.gold) || 0,
      streak: Number(value.streak) || 0,
      longest: Number(value.longest) || 0,
      undoneOn: typeof value.undoneOn === 'string' ? value.undoneOn : '',
      finished: value.finished !== false,
      key,
    };
  }
  return out;
}

/**
 * One habit on one day, read across all three records above.
 *
 * `verdict` is what happened, `rewarded` is whether the account was actually
 * paid for it, and `roomCounts` is whether a Room will credit it. Those last
 * two are separate booleans and not one flag on purpose: every confusing
 * case this function exists for is a case where they disagree.
 *
 *   'completed'  a live completion. Paid, and (normally) green.
 *   'undone'     completed at some point and then un-marked. The stamp
 *                proves it even after the receipt is gone.
 *   'grid_only'  a green Grid square with no completion behind it. Scores in
 *                Rooms, pays nothing, and is what an admin reading only
 *                habitCompletions would have seen as an empty day.
 *   'marked'     a non-green deliberate mark (partly done, missed, skipped).
 *   'none'       nothing recorded at all.
 */
function readHabitDay(dayData, habitId, receipt) {
  const d = dayData || {};
  const comps = d.habitCompletions && typeof d.habitCompletions === 'object' ? d.habitCompletions : {};
  const stamps = d.completedAtMinutes && typeof d.completedAtMinutes === 'object' ? d.completedAtMinutes : {};
  const targets = d.habitTargets && typeof d.habitTargets === 'object' ? d.habitTargets : {};

  const count = Number(comps[habitId]) || 0;
  const square = squareOf(d, habitId);
  const rawStamp = stamps[habitId];
  const stampedAt = typeof rawStamp === 'number' && Number.isFinite(rawStamp) ? rawStamp : null;
  const target = Number(targets[habitId]) || 1;
  const roomCounts = GREEN_SQUARES.has(square);

  const base = { count, target, square, stampedAt, receipt: receipt || null, roomCounts };

  if (count > 0) return { ...base, verdict: 'completed', rewarded: true };
  if (stampedAt !== null || receipt) return { ...base, verdict: 'undone', rewarded: false };
  if (roomCounts) return { ...base, verdict: 'grid_only', rewarded: false };
  if (square !== 'none') return { ...base, verdict: 'marked', rewarded: false };
  return { ...base, verdict: 'none', rewarded: false };
}

// Every habit id that left ANY trace on this day, across the three records,
// so a day list can never omit a habit just because the record this tool
// happens to read first is the one that is missing.
function habitIdsTouchedOn(dayData) {
  const d = dayData || {};
  const ids = new Set();
  for (const field of ['habitCompletions', 'completedAtMinutes', 'squareStates']) {
    const map = d[field];
    if (map && typeof map === 'object') for (const k of Object.keys(map)) ids.add(k);
  }
  return ids;
}

/**
 * The whole-day rollup every count on this page is built from.
 *
 * `done` stays what it always meant, the reward-backed completions, so the
 * XP and gold beside it still add up. `greens` is what the PERSON did: every
 * habit showing a green square by either route, which is also exactly what a
 * Room credits them for. When those two differ the day carries at least one
 * `gridOnly`, and that difference is the thing worth showing.
 */
function summarizeHabitDay(dayData, scheduledIds, receiptsByKey, dayKey) {
  const ids = new Set(scheduledIds || []);
  for (const id of habitIdsTouchedOn(dayData)) ids.add(id);

  const rows = [];
  let done = 0, greens = 0, roomGreens = 0, gridOnly = 0, undone = 0, marked = 0;
  for (const id of ids) {
    const receipt = (receiptsByKey || {})[`${id}|${dayKey}`] || null;
    const r = readHabitDay(dayData, id, receipt);
    r.habitId = id;
    rows.push(r);
    if (r.rewarded) done += 1;
    if (r.rewarded || r.roomCounts) greens += 1;
    // `greens` above is a UNION, so it counts a completion whose square was
    // never written green - which a Room does NOT credit. It stays as it is
    // because lib/activity.js's feed and accounts table are both built on
    // it and this is not their redesign. `roomGreens` is the strict answer
    // to "what would a Room actually see", and it is the one the day card
    // prints, so the copy beside the number stops being wrong in the exact
    // case the tool exists to explain.
    if (r.roomCounts) roomGreens += 1;
    if (r.verdict === 'grid_only') gridOnly += 1;
    if (r.verdict === 'undone') undone += 1;
    if (r.verdict === 'marked') marked += 1;
  }
  return { rows, done, greens, roomGreens, gridOnly, undone, marked };
}

/**
 * Where one habit-day actually counted, from the two booleans readHabitDay
 * keeps apart. This is the whole point of the tool in five words, so it is
 * one function and every surface reads it rather than each writing its own
 * sentence about the same pair of flags.
 */
function ledgerTag(row) {
  if (row.rewarded && row.roomCounts) return { where: 'Room and XP', cls: 'w-both' };
  if (row.roomCounts) return { where: 'Room only', cls: 'w-room' };
  if (row.rewarded) return { where: 'XP only', cls: 'w-xp' };
  return { where: 'Neither', cls: 'w-none' };
}

// Printed once per day card and once per calendar day panel. Says what the
// three columns ARE, so the columns themselves never have to re-explain
// themselves per row, which is what the old per-row notes were doing.
const LEDGER_LEGEND = '<p class="lg-legend"><b>Completion</b> pays XP, gold and the streak. '
  + '<b>Square</b> is what a Room grades off. <b>Stamp</b> is never deleted, so a Stamp with '
  + 'no Completion means it was completed and then un-marked. Three separate records, so they '
  + 'can disagree.</p>';

/**
 * The day in three numbers, where 113 words of amber prose used to be.
 *
 * `why` is the one line that appears only when the records disagree. Its
 * opening clause and the literal class string `day-warn calm` are both
 * pinned by test/habit_day.test.js, so a rewrite of the surrounding card
 * can never quietly drop the distinction between "this is a bug" and "this
 * is the designed behaviour".
 */
function renderDayTally({ scheduled, paid, roomCounted, why, calm }) {
  const short = typeof roomCounted === 'number' && paid < roomCounted;
  const items = [
    `<div class="ty"><b>${scheduled}</b><span>scheduled</span></div>`,
    `<div class="ty paid${short ? ' short' : ''}"><b>${paid}</b><span>completions paid</span></div>`,
    typeof roomCounted === 'number'
      ? `<div class="ty room"><b>${roomCounted}</b><span>green squares, what a room counts</span></div>`
      : '',
  ].filter(Boolean).join('');
  const line = why
    ? `<div class="day-warn${calm ? ' calm' : ''}"><b>The square and the completion disagree on this day.</b> ${why}</div>`
    : '';
  return `<div class="tally${why && !calm ? ' disagree' : ''}">${items}${line}</div>`;
}

/**
 * The evidence: one row per habit, the three records as VALUES rather than
 * as a paragraph asserting what they say, and a last column naming where
 * the habit counted.
 *
 * The only tinted cells the day card paints are the two that disagree on a
 * row, which is what makes the odd habit findable without reading anything.
 *
 * [mirrorFor] optionally answers "what does habit_history say for this
 * habit on this day", the FOURTH record, which the app's Progress and Life
 * Timeline screens read. It is compared on every row and printed only when
 * it disagrees with the square: the profile doc carries four
 * habitHistoryMarksV*BackfilledAt stamps, which is evidence it has drifted
 * before. [notesFor] is the person's own note on the square, which this
 * tool has never shown at all.
 */
function renderRecordLedger(rows, opts) {
  const { habitCtx, mirrorFor, notesFor } = opts || {};
  if (!rows.length) return '<p class="muted">Nothing recorded on this day.</p>';

  const cell = (value, cls) => value === null || value === undefined || value === ''
    ? `<td class="${cls}"><span class="lg-none">none</span></td>`
    : `<td class="${cls}"><span class="lg-val">${value}</span></td>`;

  const body = rows.map((r) => {
    const tag = ledgerTag(r);
    const disagrees = r.rewarded !== r.roomCounts;
    const meta = SQUARE_META[r.square] || SQUARE_META.none;
    const label = habitLabel(r.habitId, habitCtx, r.receipt && r.receipt.category);
    const comp = r.count > 0
      ? escapeHtml(String(r.count)) + (r.target > 1 ? ` of ${escapeHtml(String(r.target))}` : '')
      : null;

    const subs = [];
    if (r.verdict === 'grid_only') {
      subs.push(['warn', 'A green square, no completion behind it. Rooms count it, XP does not.']);
    } else if (r.verdict === 'undone') {
      subs.push(['undo', r.receipt
        ? `Completed, then un-marked. ${escapeHtml(String(r.receipt.xp))} XP and ${escapeHtml(String(r.receipt.gold))} gold taken back, receipt still outstanding. Marking it again redeems the receipt instead of paying twice.`
        : 'Completed, then un-marked. No receipt left, the Stamp is the proof.']);
      if (r.roomCounts) subs.push(['warn', 'Square still green, so Rooms still count it.']);
    } else if (r.verdict === 'completed' && !r.roomCounts) {
      subs.push(['warn', 'Completion recorded, square not green. XP counted it, Rooms do not.']);
    }
    if (mirrorFor) {
      const mirror = mirrorFor(r.habitId);
      if (mirror != null && mirror !== GREEN_SQUARES.has(r.square)) {
        subs.push(['warn', `Chart mirror says ${mirror ? 'complete' : 'not complete'}, the square says ${escapeHtml(meta.label)}. Progress and Life Timeline read the mirror.`]);
      }
    }
    const note = notesFor && notesFor(r.habitId);
    if (note) subs.push(['', `Their note: <span class="lg-note">${escapeHtml(note)}</span>`]);

    const span = subs.map(([tone, html]) =>
      `<tr class="lg-sub${tone ? ' ' + tone : ''}"><td></td><td colspan="4">${html}</td></tr>`).join('');

    return `<tr class="lg-row v-${escapeHtml(r.verdict)}${disagrees ? ' disagree' : ''}">
        <th scope="row" class="lg-habit"><span class="lg-emo">${label.emoji}</span><span class="lg-name">${escapeHtml(label.name)}</span></th>
        ${cell(comp, 'lg-c-comp')}
        ${cell(r.stampedAt === null ? null : escapeHtml(fmtMinutes(r.stampedAt)), 'lg-c-stamp')}
        ${cell(r.square === 'none' ? null : escapeHtml(meta.label), 'lg-c-sq')}
        <td class="lg-where ${tag.cls}">${tag.where}</td>
      </tr>${span}`;
  }).join('');

  // The schema tour that used to be in a TAB LABEL lives here instead, as
  // the title on the column that reads each field.
  return `<div class="lg-wrap"><table class="ledger">
      <thead><tr>
        <th class="lg-habit">Habit</th>
        <th title="habitCompletions. This is what pays XP, gold and the streak.">Completion</th>
        <th title="completedAtMinutes. Nothing in the app deletes this, so it outlives an undo.">Stamp</th>
        <th title="squareStates. The only record a Room grades off.">Square</th>
        <th>Counts where</th>
      </tr></thead>
      <tbody>${body}</tbody>
    </table></div>`;
}

const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];
const CAL_WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// A real month-by-month calendar for the 'daily' subcollection - what an
// admin actually wants when checking "how has this account been doing":
// each day as its own cell, shaded by how much of that day's real schedule
// got done (see dayHeatLevel), a mood dot when one was logged, today
// outlined, and older months still just a scroll away underneath - not a
// flat alphabetical/reverse-chronological list of collapsed one-line log
// entries (what this replaced; see renderDocList, still used for every
// other subcollection, where a flat list is the right call since there's no
// natural calendar shape to a habit or a task).
//
// Clicking a day (see REPORT_SCRIPT's calendar click handler) fills the
// shared #dayDetailPanel with that day's already-curated renderDailyDetail
// output - the exact same mood/reflection/night-review/habit breakdown the
// old flat list showed inside each entry's own <details>, just reached by
// clicking a colored square instead of scanning a wall of text summaries.
// Every real day's detail markup still lives on the page (in the hidden
// #dayDetailData block), just not shown until picked, so nothing about the
// underlying data access changes - only how it's found and read.
//
// Only renders months that actually have at least one daily doc, plus the
// current month even when it's still empty (so "today" is always on the
// calendar to click) - same "don't draw a wall of empty history" reasoning
// LifeTimelineScreen documents on the Dart side, just grouped by month here
// instead of by year.
function renderCalendarSection(dailyDocs, habitDocs, habitCtx, todayKey, receiptsByKey, tzOffsetMinutes) {
  const byKey = new Map();
  for (const doc of dailyDocs) byKey.set(doc.id, doc.data());
  const receipts = receiptsByKey || {};

  const monthKeys = new Set();
  for (const doc of dailyDocs) monthKeys.add(doc.id.slice(0, 7));
  monthKeys.add(todayKey.slice(0, 7));
  const months = Array.from(monthKeys).sort().reverse();

  const detailPanels = [];
  const monthBlocks = months.map((monthKey) => {
    const [yy, mm] = monthKey.split('-').map(Number);
    const daysInMonth = new Date(Date.UTC(yy, mm, 0)).getUTCDate();
    const firstWeekdayJs = new Date(Date.UTC(yy, mm - 1, 1)).getUTCDay();
    const leadBlanks = firstWeekdayJs === 0 ? 6 : firstWeekdayJs - 1; // Monday-first, matching startOfWeek elsewhere in this app

    let monthActiveDays = 0;
    let monthCompletions = 0;
    let monthGridOnly = 0;
    let monthUndone = 0;
    const cells = [];
    for (let i = 0; i < leadBlanks; i++) cells.push('<div class="cal-cell cal-empty"></div>');
    for (let day = 1; day <= daysInMonth; day++) {
      const key = `${yy}-${String(mm).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
      const data = byKey.get(key);
      let greens = 0;
      let scheduled = 0;
      let gridOnly = 0;
      let undone = 0;
      let moodMeta = null;
      if (data) {
        const parts = dayKeyParts(key);
        const scheduledIds = habitDocs
          .filter((h) => habitScheduledOnParts(h.data(), parts))
          .map((h) => h.id);
        scheduled = scheduledIds.length;
        // greens, not the reward-backed count: a day whose square was
        // painted outside the reward window has no completion at all, and
        // shading it as an empty day is precisely how a marked day became
        // invisible here. The flags below say which kind of green it was.
        const sum = summarizeHabitDay(data, scheduledIds, receipts, key);
        greens = sum.greens;
        gridOnly = sum.gridOnly;
        undone = sum.undone;
        moodMeta = data.mood ? MOOD_META[data.mood] : null;
        if (greens > 0) { monthActiveDays += 1; monthCompletions += sum.done; }
        monthGridOnly += gridOnly;
        monthUndone += undone;
      }
      const level = dayHeatLevel(greens, scheduled);
      const isToday = key === todayKey;
      if (data) {
        detailPanels.push(`<div class="day-detail" data-date="${key}" hidden>
          <div class="day-detail-head">
            <strong>${escapeHtml(fmtDate(new Date(Date.UTC(yy, mm - 1, day))) || key)}</strong>
            <span class="muted">${key}</span>
          </div>
          ${renderDailyDetail(key, data, { habitCtx, receiptsByKey: receipts, tzOffsetMinutes })}
        </div>`);
      }
      const flags = [
        gridOnly > 0 ? '<span class="cal-flag warn" title="Marked on the Grid with no completion behind it">&#9888;</span>' : '',
        undone > 0 ? '<span class="cal-flag undo" title="Completed, then un-marked">&#8617;</span>' : '',
      ].join('');
      cells.push(`
        <button type="button" class="cal-cell cal-day level-${level}${isToday ? ' today' : ''}"
          data-date="${key}"${data ? '' : ' disabled'}>
          <span class="cal-day-num">${day}</span>
          ${moodMeta ? `<span class="cal-mood">${moodMeta.emoji}</span>` : ''}
          ${flags}
          ${scheduled > 0 ? `<span class="cal-ratio">${greens}/${scheduled}</span>` : ''}
        </button>
      `);
    }

    return `
      <div class="cal-month">
        <div class="cal-month-head">
          <h4>${MONTH_NAMES[mm - 1]} ${yy}</h4>
          <span class="muted">${monthActiveDays} active day${monthActiveDays === 1 ? '' : 's'} &middot; ${monthCompletions} habit${monthCompletions === 1 ? '' : 's'} completed${monthGridOnly ? ` &middot; <b class="flag-warn">${monthGridOnly} Grid-only</b>` : ''}${monthUndone ? ` &middot; <b class="flag-undo">${monthUndone} un-marked</b>` : ''}</span>
        </div>
        <div class="cal-weekdays">${CAL_WEEKDAY_LABELS.map((w) => `<span>${w}</span>`).join('')}</div>
        <div class="cal-grid">${cells.join('')}</div>
      </div>
    `;
  }).join('');

  return `
    <div class="cal-legend">
      <span class="muted">Less</span>
      <span class="legend-swatch level-0"></span>
      <span class="legend-swatch level-1"></span>
      <span class="legend-swatch level-2"></span>
      <span class="legend-swatch level-3"></span>
      <span class="legend-swatch level-4"></span>
      <span class="muted">More</span>
      <span class="muted cal-legend-hint">Click any day for its full breakdown.</span>
    </div>
    <div class="cal-legend-note muted">
      The ratio counts every GREEN GRID SQUARE, which is also exactly what a Room
      credits. <b class="flag-warn">&#9888;</b> means at least one of them has no completion
      record behind it, so it earned no XP, gold or streak even though the Room counted it.
      <b class="flag-undo">&#8617;</b> means a habit was completed that day and then un-marked.
      Open the day for the habit-by-habit breakdown.
    </div>
    <div id="dayDetailPanel" class="day-detail-panel">
      <p class="muted">Click a day below to see mood, tasks, and habits for that day.</p>
    </div>
    ${monthBlocks}
    <div id="dayDetailData" hidden>${detailPanels.join('')}</div>
  `;
}

function fmtDate(value, withTime) {
  const d = toJsDate(value);
  if (!d) return null;
  return withTime
    ? d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
    : d.toLocaleDateString(undefined, { dateStyle: 'medium' });
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// A CSS colour value is not a string escapeHtml can make safe: the value lands
// inside style="background:...", where escapeHtml's job (neutralising & < > ")
// leaves every CSS metacharacter (; : ( ) /) untouched, so a user-set
// iconColorHex of `red;background-image:url(//attacker/beacon.png)` still makes
// the admin's browser fetch the attacker's URL. iconColorHex is written by the
// account owner, so it has to be validated as an actual colour before it can go
// near a style attribute. Accepts only a #hex literal (3/4/6/8 digits); anything
// else returns null and the caller drops the swatch.
function safeCssColor(raw) {
  const v = String(raw == null ? '' : raw).trim();
  return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v)
    ? v
    : null;
}

// Past this many characters a single scalar stops being printed in full.
// See the comment at the tail of renderValue for what one unbroken base64
// string does to the layout of every other section on the page.
const LONG_VALUE_CHARS = 400;

// Renders any Firestore value - including Timestamps, arrays, and nested
// maps - as readable HTML. One generic renderer so every field, in every
// subcollection, current or future, shows up without this tool needing a
// per-feature update. Nested objects with more than a handful of keys
// (this schema's per-habit maps - habitStreakCounts and friends - can run
// well into the dozens) collapse behind their own <details> instead of
// sprawling inline, so one busy field can't dominate the whole table.
function renderValue(value) {
  if (value === null || value === undefined) return '<span class="muted">—</span>';
  if (value && typeof value.toDate === 'function') {
    return escapeHtml(value.toDate().toLocaleString());
  }
  if (typeof value === 'boolean') {
    return `<span class="bool ${value}">${value ? 'Yes' : 'No'}</span>`;
  }
  if (Array.isArray(value)) {
    if (value.length === 0) return '<span class="muted">empty</span>';
    const allPrimitive = value.every(
      (v) => v === null || typeof v !== 'object' || (v && typeof v.toDate === 'function')
    );
    if (allPrimitive) {
      return '<div class="chips">' +
        value.map((v) => `<span class="chip">${renderValue(v)}</span>`).join('') +
        '</div>';
    }
    return '<div class="stack">' +
      value.map((v) => `<div class="stack-item">${renderValue(v)}</div>`).join('') +
      '</div>';
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value);
    if (keys.length === 0) return '<span class="muted">empty</span>';
    const table = renderFieldTable(value);
    if (keys.length > 4) {
      return `<details class="nested"><summary>${keys.length} fields</summary>${table}</details>`;
    }
    return table;
  }
  const str = String(value);
  // A base64 blob has no break opportunity anywhere in it, so a cell holding
  // one sets the table's minimum width to the blob's own rendered length and
  // takes the whole document with it. One real matrix_tasks voice note is
  // 293,436 characters; the page it lands in lays out ~2.3 MILLION pixels
  // wide, which is a horizontal scrollbar under every other section on the
  // page and no way to read any of them. Truncating loses nothing an admin
  // was going to read anyway, and the length is the part that is actually
  // diagnostic. Still escaped, on the slice, so the guarantee
  // test/escaping.test.js exists to pin is unchanged.
  if (str.length > LONG_VALUE_CHARS) {
    return `<details class="nested raw"><summary>${str.length.toLocaleString()} characters, first ${LONG_VALUE_CHARS} shown</summary>`
      + `<code class="longval">${escapeHtml(str.slice(0, LONG_VALUE_CHARS))}…</code></details>`;
  }
  return escapeHtml(str);
}

function renderFieldTable(data) {
  const keys = Object.keys(data).sort();
  if (keys.length === 0) return '<span class="muted">empty</span>';
  return '<table class="fields"><tbody>' +
    keys.map((k) =>
      `<tr><th>${escapeHtml(k)}</th><td>${renderValue(data[k])}</td></tr>`
    ).join('') +
    '</tbody></table>';
}

function detailRow(label, valueHtml) {
  if (valueHtml === null || valueHtml === undefined || valueHtml === '') return '';
  return `<div class="detail-row"><span class="detail-label">${escapeHtml(label)}</span><span class="detail-value">${valueHtml}</span></div>`;
}

// Curated, human-readable view of one custom_habits/{id} doc - mirrors
// exactly the field set IslamicHabitTemplate.toFirestore (islamic_habit_
// catalog.dart) writes, labeled the way the app's own Add/Edit Habit sheet
// would show them, instead of a flat A-Z field dump. [data.iconColorHex],
// when the user picked one, renders as a real color swatch - the same
// per-habit color the app itself paints, not a generic admin-tool color.
function renderHabitDetail(data) {
  const cat = CATEGORY_META[data.category] || { emoji: '⭐', label: data.category || 'Custom' };
  const freq = data.frequencyType === 'weekly'
    ? `${data.frequencyTarget || 1}× per week`
    : 'Every day';
  const days = Array.isArray(data.scheduledWeekdays) && data.scheduledWeekdays.length
    ? data.scheduledWeekdays.map((d) => WEEKDAY_ABBR[d] || d).join(', ')
    : (data.frequencyType === 'weekly' ? 'any days' : null);
  const goal = data.goalType === 'quit'
    ? (data.reductionType === 'limit'
        ? `Quit habit — limit to ${data.limitAmount ?? '?'} ${escapeHtml(String(data.customUnitLabel || data.limitUnit || ''))}/day`
        : 'Quit habit — avoid entirely')
    : 'Build habit';
  const swatchColor = safeCssColor(data.iconColorHex);
  const swatch = swatchColor
    ? `<span class="color-dot" style="background:${swatchColor}"></span>`
    : '';

  const rows = [
    detailRow('Category', `<span class="emo">${cat.emoji}</span>${escapeHtml(cat.label)}`),
    detailRow('Frequency', escapeHtml(freq) + (days ? ` <span class="muted">(${escapeHtml(days)})</span>` : '')),
    detailRow('Goal', escapeHtml(goal)),
    data.cueAfter ? detailRow('Cue', `After ${escapeHtml(data.cueAfter)}`) : '',
    data.hasTimer ? detailRow('Timer', `${Math.round((data.timerDurationSeconds || 0) / 60)} min`) : '',
    detailRow('Rewards', `+${data.xpReward ?? 0} XP · +${data.goldReward ?? 0} gold per completion`),
    detailRow('Created', fmtDate(data.createdAt) || '<span class="muted">not recorded</span>'),
    data.archivedAt ? detailRow('Archived', fmtDate(data.archivedAt)) : '',
  ].join('');

  return `
    <div class="detail-title">${swatch}${escapeHtml(data.name || '(unnamed habit)')}</div>
    ${data.description ? `<div class="detail-desc">${escapeHtml(data.description)}</div>` : ''}
    <div class="detail-rows">${rows}</div>
  `;
}

// Curated view of one matrix_tasks/{id} doc - mirrors MatrixTask.toFirestore
// (matrix_task.dart). Quadrant renders as the same colored badge the app's
// own Matrix board uses (see QUADRANT_META), not the raw 'doFirst' wire
// value.
function renderTaskDetail(data) {
  const q = QUADRANT_META[data.quadrant] || { label: data.quadrant || 'Task', subtitle: '', color: '#b9822a' };
  const status = data.isDone ? '<span class="bool true">✓ Done</span>' : '<span class="muted">Open</span>';
  const voiceCount = Array.isArray(data.voiceNotes) ? data.voiceNotes.length : 0;

  const rows = [
    detailRow('Status', status),
    // Wire/Firestore key is still 'isToday', not 'isFav' - MatrixTask.
    // toFirestore/fromFirestore rename it on the Dart side only (see
    // matrix_task.dart's isFav doc comment); this reads the raw doc
    // directly, so it has to match the actual stored key.
    data.isToday ? detailRow('Favorited', '★ Yes') : '',
    data.reminderAt ? detailRow('Reminder', fmtDate(data.reminderAt, true)) : '',
    voiceCount ? detailRow('Voice notes', `${voiceCount} recorded`) : '',
    detailRow('Created', fmtDate(data.createdAt, true) || '<span class="muted">not recorded</span>'),
    data.completedAt ? detailRow('Completed', fmtDate(data.completedAt, true)) : '',
  ].join('');

  return `
    <div class="detail-title">
      <span>${data.isDone ? '☑' : '☐'} ${escapeHtml(data.title || '(untitled task)')}</span>
      <span class="badge" style="background:${q.color}">${escapeHtml(q.label)}</span>
    </div>
    ${q.subtitle ? `<div class="detail-subtitle">${escapeHtml(q.subtitle)}</div>` : ''}
    ${data.description ? `<div class="detail-desc">${escapeHtml(data.description)}</div>` : ''}
    <div class="detail-rows">${rows}</div>
  `;
}

// Curated view of one daily/{YYYY-MM-DD} doc - habitCompletions/
// timerSeconds/xp/gold per daily_log_model.dart, mood/dailyReflection/
// nightReviewDone per night_review_notifier.dart (written to this exact
// same document, never a separate one). ctx.habitCtx (built by
// buildHabitContext from this same account's own custom_habits docs)
// resolves each habitId to its real name so this reads as "Fajr Prayer -
// done x1" instead of a bare id - the same cross-reference GridJournal
// Screen itself does at render time; a habit id with no match (deleted
// since, or never existed) just falls back to showing the bare id.
/**
 * When this day document was last written, in the ACCOUNT's own wall clock,
 * and what that says about a Grid-only mark on it.
 *
 * A green square with no completion behind it has two very different
 * causes, and they need different words:
 *
 *   backfilled  the day was coloured in later, from an older week. Earning
 *               nothing is the DESIGNED behaviour there - see
 *               WeeklyGridNotifier.setSquare's anti-backdating comment. Not
 *               a bug, just worth knowing the Room counts it.
 *   pre-cutoff  the square was painted on its own calendar date but before
 *               DAY_CUTOFF_HOUR, when the app's reward day was still
 *               yesterday. The person tapped the square under the gold
 *               "today" ring and got a rewardless one. That IS the trap.
 *
 * Inferred from lastUpdated, which is the day's LAST write and not
 * necessarily the mark's own, so it is reported as "last written", never as
 * "marked at". Null when the day carries no usable timestamp.
 */
function dayWriteContext(data, tzOffsetMinutes) {
  const at = toJsDate(data && data.lastUpdated);
  if (!at) return null;
  const localMs = typeof tzOffsetMinutes === 'number'
    ? at.getTime() + tzOffsetMinutes * 60000
    : at.getTime() - at.getTimezoneOffset() * 60000;
  const d = new Date(localMs);
  const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
  const hour = d.getUTCHours();
  const clock = `${String(hour).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
  return { key, hour, clock };
}

function renderDailyDetail(id, data, ctx) {
  const habitCtx = (ctx && ctx.habitCtx) || {};
  const receipts = (ctx && ctx.receiptsByKey) || {};
  const write = dayWriteContext(data, ctx && ctx.tzOffsetMinutes);
  // Painted on its own date, before the reward day had rolled over to it.
  const preCutoff = !!write && write.key === id && write.hour < DAY_CUTOFF_HOUR;
  const backfilled = !!write && write.key > id;
  const mood = data.mood ? MOOD_META[data.mood] : null;

  // Every habit that left ANY trace, not just the ones with a completion.
  // Reading habitCompletions alone is what made a painted-but-uncredited day
  // render as "No habit activity logged" while a Room was crediting it - see
  // readHabitDay's comment block.
  const sum = summarizeHabitDay(data, [], receipts, id);
  const seen = sum.rows.filter((r) => r.verdict !== 'none' || r.square !== 'none');

  const nameOf = (habitId) => {
    const r = sum.rows.find((row) => row.habitId === habitId);
    return habitLabel(habitId, habitCtx, r && r.receipt ? r.receipt.category : null);
  };
  const sq = (state) => {
    const meta = SQUARE_META[state] || SQUARE_META.none;
    return `${meta.emoji} ${escapeHtml(meta.label)}`;
  };

  const line = (r) => {
    const name = escapeHtml(nameOf(r.habitId));
    const at = r.stampedAt !== null ? fmtMinutes(r.stampedAt) : '';
    const receipt = r.receipt;
    switch (r.verdict) {
      case 'completed': {
        const times = r.count > 1 ? ` &times;${escapeHtml(String(r.count))}` : '';
        const target = r.target > 1 ? ` of ${escapeHtml(String(r.target))}` : '';
        const when = at ? ` &middot; marked ${escapeHtml(at)}` : '';
        // A completion whose square is not green is the mirror of the bug
        // this section exists for, and just as worth saying out loud.
        const mismatch = r.roomCounts ? '' :
          `<div class="stack-note warn">Completion recorded, but the Grid square reads ${sq(r.square)}. Rooms grade off the SQUARE, so this one does not count there.</div>`;
        return `<div class="stack-item">&#9989; ${name} &mdash; completed${times}${target}${when} &middot; square ${sq(r.square)}</div>${mismatch}`;
      }
      case 'undone': {
        const when = at ? ` at ${escapeHtml(at)}` : '';
        const bits = [`<div class="stack-item">&#8617;&#65039; ${name} &mdash; completed${when}, then <b>un-marked</b> &middot; square now ${sq(r.square)}</div>`];
        if (receipt) {
          const undoneOn = receipt.undoneOn && receipt.undoneOn !== id
            ? ` on ${escapeHtml(receipt.undoneOn)}` : '';
          bits.push(`<div class="stack-note undo">Undo receipt still outstanding: took back ${escapeHtml(String(receipt.xp))} XP and ${escapeHtml(String(receipt.gold))} gold${undoneOn}. Marking this habit-day again redeems it rather than paying twice.</div>`);
        } else {
          // completedAtMinutes survives forever; the receipt does not. Say
          // which of the two is speaking so the absence is not read as doubt.
          bits.push('<div class="stack-note undo">No receipt left (already corrected, or swept after a year). The completion timestamp above is what still proves it happened.</div>');
        }
        if (r.roomCounts) {
          bits.push('<div class="stack-note warn">The Grid square is still green, so a Room will keep counting this day even though the completion is gone.</div>');
        }
        return bits.join('');
      }
      case 'grid_only': {
        const why = preCutoff
          ? ` Tapped at <b>${escapeHtml(write.clock)}</b>, before the ${DAY_CUTOFF_HOUR}:00 cutoff, so the app's reward day was still the day BEFORE. The Grid had already moved on to this date and put the "today" ring on it, so the square shown as today was not the day that pays.`
          : backfilled
            ? ` Last written on ${escapeHtml(write.key)}, so this day was filled in after the fact. A backfilled square never pays, by design, or anyone could colour in last month and farm XP.`
            : '';
        return `<div class="stack-item">${sq(r.square)} ${name} &mdash; <b>green square, no completion</b></div>`
          + `<div class="stack-note warn">The person marked it; the app did not credit it. No XP, no gold, no streak, and Today still shows it unchecked. A Room reads the square, so the Room counts it.${why}</div>`;
      }
      case 'marked':
        return `<div class="stack-item">${sq(r.square)} ${name} &mdash; Grid mark only, no completion</div>`;
      default:
        return `<div class="stack-item">&#11036; ${name} &mdash; mark cleared (square written back to empty)</div>`;
    }
  };

  const habitRows = seen.length
    ? '<div class="stack">' + seen.map(line).join('') + '</div>'
    : '<span class="muted">No habit activity logged.</span>';

  const banner = (sum.gridOnly > 0 || sum.undone > 0)
    ? `<div class="day-warn${preCutoff && sum.gridOnly > 0 ? '' : ' calm'}">
        <b>The square and the completion disagree on this day.</b> ${
        [
          sum.gridOnly ? `${sum.gridOnly === 1 ? 'One habit is' : `${sum.gridOnly} habits are`} green with no completion written` : '',
          sum.undone ? `${sum.undone} ${sum.undone === 1 ? 'was' : 'were'} completed and then un-marked` : '',
        ].filter(Boolean).join(', and ')
      }. A Room reads the square; XP, gold and the streak read the completion, so the two will report different numbers for this day.${
        preCutoff && sum.gridOnly > 0
          ? ' This is the pre-cutoff case (tapped before the day rolled over), not an ordinary backfill.'
          : ''
      }</div>`
    : '';

  const rows = [
    mood ? detailRow('Mood', `${mood.emoji} ${escapeHtml(mood.label)}`) : '',
    data.dailyReflection
      ? detailRow('Reflection', `<span class="prose">${escapeHtml(data.dailyReflection)}</span>`)
      : '',
    detailRow('Night review', data.nightReviewDone ? '<span class="bool true">&#10003; Done</span>' : '<span class="muted">Not done</span>'),
    detailRow('Earned', `+${data.totalXpEarned ?? 0} XP &middot; +${data.totalGoldEarned ?? 0} gold`),
    detailRow('Counted', `${sum.done} completed &middot; ${sum.greens} green square${sum.greens === 1 ? '' : 's'} (what a Room credits)`),
  ].join('');

  return `
    ${banner}
    <div class="detail-rows">${rows}</div>
    <h3>Habits that day</h3>
    ${habitRows}
  `;
}

/**
 * A habit id turned into something a person can read.
 *
 * buildHabitContext only knows this account's CURRENT custom_habits, so an
 * id it cannot resolve is a habit that has since been deleted (or a catalog
 * habit, which lives in the app's own asset list and not in Firestore at
 * all). Those still appear in old daily docs and in undo receipts forever,
 * and printing the bare uuid there - which is what this did - reads as a
 * rendering fault rather than as the fact it is. Still shows the id, since
 * an admin sometimes needs it, just no longer ONLY the id.
 */
function habitLabel(habitId, habitCtx, category) {
  const known = habitCtx && habitCtx[habitId];
  if (known && known.name) {
    const cat = CATEGORY_META[known.category];
    return `${cat ? cat.emoji + ' ' : ''}${known.name}`;
  }
  const cat = category ? CATEGORY_META[category] : null;
  const short = String(habitId).slice(0, 8);
  return `${cat ? cat.emoji + ' ' : ''}(habit no longer in this account · ${short})`;
}

/**
 * The account's outstanding "marked, then un-marked" receipts, as their own
 * section.
 *
 * Every other surface in this report answers "what does this day say"; this
 * one answers "what did they take back", which was not visible anywhere at
 * all before. Each entry is a real UndoneCompletion written by
 * DashboardNotifier.uncompleteHabit when an undo removed a habit-day's last
 * completion, carrying exactly what the undo clawed back.
 *
 * Two things to read carefully rather than at a glance:
 *
 *   - An entry DISAPPEARS when the same habit-day is marked again
 *     (restoreUndoneCompletion redeems it), and again after
 *     kUndoneCompletionRetentionDays (365) when the load sweep drops it. So
 *     an empty list is not proof nothing was ever undone. The day view's own
 *     "completed, then un-marked" verdict is the durable answer, because it
 *     reads completedAtMinutes, which nothing ever deletes.
 *   - The XP and gold shown are what the undo ACTUALLY removed, not what the
 *     completion was worth: both floor at zero, so an account that had
 *     already spent its gold hands back less than it was paid.
 */
function renderUndoneSection(profileData, habitCtx) {
  const receipts = Object.values(readUndoneReceipts(profileData));
  if (!receipts.length) {
    return `<p class="muted">No outstanding undo receipts. That means one of three things, not one:
      nothing was ever un-marked, everything un-marked has since been marked back
      (which redeems the receipt), or it was un-marked more than a year ago and swept.
      Open a day in Daily activity to see the durable per-day verdict.</p>`;
  }
  receipts.sort((a, b) => (a.dateKey < b.dateKey ? 1 : a.dateKey > b.dateKey ? -1 : 0));
  const ctx = habitCtx || {};
  const items = receipts.map((r) => {
    const label = habitLabel(r.habitId, ctx, r.category);
    const undoneOn = r.undoneOn && r.undoneOn !== r.dateKey
      ? ` &middot; undone on ${escapeHtml(r.undoneOn)}` : ' &middot; undone the same day';
    return `<div class="doc">
      <div class="stack-item">&#8617;&#65039; ${escapeHtml(label)}
        &mdash; completion on <b>${escapeHtml(r.dateKey)}</b> was un-marked${undoneOn}</div>
      <div class="stack-note undo">Took back ${escapeHtml(String(r.xp))} XP and ${escapeHtml(String(r.gold))} gold.
        Streak at the time: ${escapeHtml(String(r.streak))} (best ${escapeHtml(String(r.longest))}).
        ${r.finished ? 'The day had reached its target, so the lifetime counters were reversed too.'
                     : 'The day had NOT reached its target, so the lifetime counters were never paid and are not reversed.'}
        Marking this habit-day again redeems this receipt instead of paying a second time.</div>
    </div>`;
  }).join('');
  return `<p class="muted">${receipts.length} outstanding receipt${receipts.length === 1 ? '' : 's'}.
    A receipt disappears once the habit-day is marked back, so this list is what is still un-corrected right now.</p>
    ${items}`;
}

// Dispatches to a curated, schema-aware detail view for the collections
// this tool specifically knows about, or the plain generic field table for
// anything else (weekly_challenges, focus_plans, milestones, or any future
// subcollection this tool hasn't been taught about yet) - same
// "correct-by-default, nicer where it's worth the effort" split
// summarizeDoc already uses one level up. Never the only view for a
// curated type either - renderDocList still appends the full raw field
// table underneath, collapsed, so nothing is ever actually hidden, only
// de-emphasized.
function renderDocDetail(collectionId, id, data, ctx) {
  switch (collectionId) {
    case 'custom_habits':
      return renderHabitDetail(data);
    case 'matrix_tasks':
      return renderTaskDetail(data);
    case 'daily':
      return renderDailyDetail(id, data, ctx);
    default:
      return renderFieldTable(data);
  }
}

// Builds the habitId -> {name, category} lookup renderDailyDetail cross-
// references, from this same account's own custom_habits docs - never a
// separate query. A daily doc referencing a habit id not in this map
// (deleted since, or never existed) just falls back to the bare id in
// renderDailyDetail, same "explain, don't hide" spirit as GridJournal
// Screen's own deleted-habit fallback.
function buildHabitContext(habitDocs) {
  const ctx = {};
  for (const doc of habitDocs || []) {
    const d = doc.data();
    ctx[doc.id] = { name: d.name || doc.id, category: d.category };
  }
  return ctx;
}

// A short, human line per document so a whole collection can be *scanned*
// (35 days of activity, a dozen tasks...) before ever opening one. Falls
// back to just the doc id for anything not special-cased - still correct,
// just less descriptive - so an unrecognized or future collection is never
// broken, only plainer.
function summarizeDoc(collectionId, id, data) {
  switch (collectionId) {
    case 'daily': {
      // Through the classifier, so a one-line summary can never claim a day
      // was empty when the person had marked it - see readHabitDay.
      const sum = summarizeHabitDay(data, [], {}, id);
      const n = sum.done;
      const bits = [`${n} habit${n === 1 ? '' : 's'} completed`];
      if (sum.gridOnly) bits.push(`${sum.gridOnly} marked on the Grid only`);
      if (sum.undone) bits.push(`${sum.undone} un-marked`);
      const mood = data.mood ? MOOD_META[data.mood] : null;
      if (mood) bits.push(`mood: ${mood.emoji} ${mood.label}`);
      else if (data.mood) bits.push(`mood: ${data.mood}`);
      if (data.nightReviewDone) bits.push('night review done');
      return `${id} — ${bits.join(' · ')}`;
    }
    case 'custom_habits': {
      const cat = CATEGORY_META[data.category];
      const freq = data.frequencyType === 'weekly' ? `${data.frequencyTarget || 1}×/week` : 'daily';
      return `${cat ? cat.emoji + ' ' : ''}${data.name || '(unnamed habit)'} · ${freq}${data.archivedAt ? ' · archived' : ''}`;
    }
    case 'matrix_tasks': {
      const q = QUADRANT_META[data.quadrant];
      return `${data.isDone ? '☑' : '☐'} ${data.title || '(untitled task)'}${q ? ' · ' + q.label : ''}`;
    }
    case 'milestones':
      return `${data.type || 'milestone'} — ${id}`;
    default:
      return id;
  }
}

// One collapsed <details> per document - id/name always visible via
// summarizeDoc, full detail only rendered once opened (it still exists in
// the page's text either way, so the search box can still find it while
// collapsed). `ctx` (currently just { habitCtx }) is optional data other
// collections' curated views need to cross-reference - see
// renderDailyDetail/buildHabitContext.
// The on/off state each filterable collection's chip row (see
// SECTION_FILTERS/renderFilterChips) matches against - stamped onto each
// .doc as a data-status attribute so REPORT_SCRIPT's chip click handler can
// just compare attributes instead of re-deriving status from the raw data
// again on the client. Returns '' (no attribute written at all) for
// anything without a chip row - an empty data-status wouldn't break the
// chip filter either way (there's no chip to select it with), but leaving
// the attribute off entirely keeps the markup honest about which
// collections actually have a state to filter by.
function docStatus(collectionId, data) {
  if (collectionId === 'custom_habits') return data.archivedAt ? 'archived' : 'active';
  if (collectionId === 'matrix_tasks') return data.isDone ? 'done' : 'open';
  if (collectionId === 'daily') {
    const completions = data.habitCompletions && typeof data.habitCompletions === 'object'
      ? Object.values(data.habitCompletions) : [];
    return completions.some((c) => Number(c) > 0) ? 'active' : 'none';
  }
  return '';
}

// Human wording for the values docStatus returns, so the pill reads
// "Archived" rather than the raw attribute the chip filter matches on.
const STATUS_LABELS = {
  active: 'Active', archived: 'Archived', open: 'Open', done: 'Done', none: 'Empty',
};

function renderDocList(id, label, docs, ctx) {
  const count = docs.length;
  if (count === 0) {
    return { id, label, count, html: '<p class="muted">Nothing here.</p>' };
  }
  const curated = id === 'custom_habits' || id === 'matrix_tasks' || id === 'daily';
  const todayKey = ctx && ctx.todayKey;
  const html = docs.map((doc) => {
    const data = doc.data();
    const status = docStatus(id, data);
    const isToday = id === 'daily' && todayKey && doc.id === todayKey;
    // The status rides on the CLOSED summary line, not only inside the open
    // card. Scanning forty habits for the archived ones used to mean opening
    // forty of them; now it is one glance down a column of pills, and the
    // chip filter above is for narrowing rather than for finding.
    return `
      <details class="doc"${status ? ` data-status="${escapeHtml(status)}"` : ''}>
        <summary>
          <span class="doc-sum">${isToday ? '<span class="today-tag">Today</span> ' : ''}${escapeHtml(summarizeDoc(id, doc.id, data))}</span>
          ${status ? `<span class="pill pill-${escapeHtml(status)}">${escapeHtml(STATUS_LABELS[status] || status)}</span>` : ''}
        </summary>
        <div class="detail-card">
          ${renderDocDetail(id, doc.id, data, ctx)}
          ${curated ? `<details class="nested raw"><summary>All raw fields</summary>${renderFieldTable(data)}</details>` : ''}
          <button type="button" class="doc-id" data-copy="${escapeHtml(doc.id)}" title="Copy this id">${escapeHtml(doc.id)} <span>⧉</span></button>
        </div>
      </details>
    `;
  }).join('');
  return { id, label, count, html };
}

// The account's numbers as ONE strip, not ten equal cards.
//
// As cards they cost about 130px of vertical space on every tab, on a page
// whose entire job is showing detail underneath, and gave "Gold 1708" and
// "Theme custom" identical visual weight so nothing was findable at a
// glance. Inline pairs read left to right in a fifth of the height, and the
// value leads because the value is what is being looked up.
function renderHighlights(profileData) {
  if (!profileData) return '';
  const items = HIGHLIGHT_FIELDS
    .filter(([key]) => profileData[key] !== undefined && profileData[key] !== null)
    .map(([key, label]) => {
      const raw = profileData[key];
      const display = typeof raw === 'boolean' ? (raw ? 'Yes' : 'No') : escapeHtml(String(raw));
      return `<div class="stat"><b>${display}</b><span>${escapeHtml(label)}</span></div>`;
    }).join('');
  return items ? `<div class="stats">${items}</div>` : '';
}

// Status filter-chip rows for the two collections it's actually useful to
// narrow down by state - see renderDocList's data-status tagging on each
// .doc for what these match against. Anything else (daily, milestones,
// rooms...) has no natural on/off state to filter by, so it gets no chip
// row at all rather than a row of options that would never do anything.
// 'daily' deliberately has no entry here anymore - it moved from a flat,
// chip-filterable list of <details> to renderCalendarSection's month
// grid (see that function's doc comment), which has no per-entry
// data-status attribute for a chip to filter by; the calendar's own color
// shading already shows active-vs-not at a glance across a whole month,
// which is strictly more than a binary chip gave.
const SECTION_FILTERS = {
  custom_habits: [
    ['', 'All'],
    ['active', 'Active'],
    ['archived', 'Archived'],
  ],
  matrix_tasks: [
    ['', 'All'],
    ['open', 'Open'],
    ['done', 'Done'],
  ],
};

function renderFilterChips(sectionId) {
  const options = SECTION_FILTERS[sectionId];
  if (!options) return '';
  // filter-chip, not .chip - .chip is already the read-only array-value
  // pill style used inside renderValue; this needs its own clickable/
  // active-state look instead of inheriting that one.
  const chips = options.map(([status, label], i) =>
    `<button type="button" class="filter-chip${i === 0 ? ' active' : ''}" data-status="${escapeHtml(status)}">${escapeHtml(label)}</button>`
  ).join('');
  return `<div class="filter-chips" data-filter-scope="${escapeHtml(sectionId)}">${chips}</div>`;
}

// Quadrant display order for the Today card's "still open" task list - the
// same urgency ordering the app's own Matrix board uses (Do First first),
// not creation order or alphabetical.
const QUADRANT_ORDER = { doFirst: 0, schedule: 1, delegate: 2, eliminate: 3 };

// The account's own "did they do their habits on this day" view, for ANY
// day, not only today.
//
// fetchAccount.js builds the answer with habitScheduledOnParts (the exact
// scheduling rule the app itself uses) rather than a raw count of every
// habit that exists, so a habit that wasn't due that day (wrong weekday,
// not created yet, already archived) never counts against them. This is the
// FIRST tab in the report (see buildReportBody) precisely so an admin
// opening any account lands on "what actually happened" before anything
// else, and the stepper at the top of it is how they walk backwards through
// the history without leaving the tab.
function renderDayCard({
  dayKey, isToday, habitRows, mood, nightReviewDone, reflection, triage, rooms,
  taskDayKey, xp, gold, hasDoc, todayKey, writeNote,
}) {
  const total = habitRows.length;
  const done = habitRows.filter((h) => h.done).length;
  const pctClass = total === 0 ? 'zero' : done === total ? 'full' : done === 0 ? 'none' : 'partial';

  // A row says which of the three records it came from, because "done" and
  // "paid for" are not the same claim - see readHabitDay. Falls back to the
  // old two-state rendering for any caller still passing bare rows.
  const VERDICT_MARK = {
    completed: '&#9989;',
    undone: '&#8617;&#65039;',
    grid_only: '&#128994;',
    marked: '&#128993;',
    none: '&#11036;',
  };
  const rowNote = (h) => {
    if (h.verdict === 'grid_only') {
      return '<div class="today-habit-note warn">Green square, no completion. The person marked it; the app did not credit it. No XP, no gold, no streak, and Today shows it unchecked. Rooms read the square, so Rooms count it.</div>';
    }
    if (h.verdict === 'undone') {
      const back = h.receipt
        ? ` Receipt outstanding: ${h.receipt.xp} XP and ${h.receipt.gold} gold taken back.`
        : '';
      const still = h.roomCounts
        ? ' The Grid square is still green, so Rooms keep counting it.'
        : '';
      return `<div class="today-habit-note undo">Completed, then un-marked.${escapeHtml(back)}${still}</div>`;
    }
    if (h.verdict === 'completed' && h.roomCounts === false) {
      return '<div class="today-habit-note warn">Completion recorded but the Grid square is not green, so Rooms do not count it.</div>';
    }
    return '';
  };
  const habitsHtml = total === 0
    ? `<p class="muted">No habits were scheduled ${isToday ? 'today' : 'that day'}.</p>`
    : '<div class="today-habits">' + habitRows.map((h) => `
        <div class="today-habit${h.done ? ' done' : ''}">
          <span>${VERDICT_MARK[h.verdict] || (h.done ? '&#9989;' : '&#11036;')}</span>
          <span>${h.emoji}</span>
          <span class="today-habit-name">${escapeHtml(h.name)}</span>
          ${h.count > 1 ? `<span class="today-habit-count">×${h.count}</span>` : ''}
        </div>
        ${rowNote(h)}
      `).join('') + '</div>';

  // The ring counts green squares; this says how many of them were actually
  // paid for. Only rendered when they disagree, so an ordinary day is
  // unchanged.
  const paid = habitRows.filter((h) => h.rewarded).length;
  const unpaid = habitRows.filter((h) => h.done && !h.rewarded).length;
  const dayWarn = unpaid > 0
    ? `<div class="day-warn">
        <b>Marked ${done} of ${total}. Completions recorded: ${paid}.</b>
        Those are two different records, and they disagree here.
        ${unpaid === 1 ? 'One square is' : `${unpaid} squares are`} green because the person tapped
        ${unpaid === 1 ? 'it' : 'them'}, but the app never wrote a completion, so
        ${unpaid === 1 ? 'it' : 'they'} earned no XP, no gold and no streak, and Today still shows
        ${unpaid === 1 ? 'it' : 'them'} unchecked. A Room reads the SQUARE, so the Room counts this
        day as done while this account's own XP does not.${writeNote ? ` ${writeNote}` : ''}</div>`
    : '';

  const rows = [
    mood ? detailRow('Mood', `${mood.emoji} ${escapeHtml(mood.label)}`) : '',
    detailRow('Night review', nightReviewDone
      ? '<span class="bool true">✓ Done</span>'
      : `<span class="muted">Not done${isToday ? ' yet' : ''}</span>`),
    reflection ? detailRow('Reflection', `<span class="prose">${escapeHtml(reflection)}</span>`) : '',
    (xp || gold) ? detailRow('Earned', `+${xp || 0} XP · +${gold || 0} gold`) : '',
  ].join('');

  // The board, in the four states an admin actually asks about. This used to
  // be two flat lists: "completed today", and "still open" — where "still
  // open" meant every open task the account had ever made, newest last,
  // truncated at eight. Which is to say the two questions that matter most,
  // what is LATE and what is COMING, were the two you could not answer.
  const taskCol = (key, label, tone, rows, empty, showWhen) => {
    const items = rows.length
      ? rows.slice(0, 12).map((r) => {
          const t = r.data;
          const q = QUADRANT_META[t.quadrant];
          const when = showWhen ? showWhen(r) : '';
          return `<div class="tk">
            <span class="tk-dot" style="background:${q ? q.color : 'var(--text-tert)'}"
                  title="${q ? escapeHtml(q.label) : ''}"></span>
            <span class="tk-title">${escapeHtml(t.title || '(untitled task)')}</span>
            ${when ? `<span class="tk-when">${escapeHtml(when)}</span>` : ''}
          </div>`;
        }).join('')
        + (rows.length > 12
            ? `<div class="tk-more">+${rows.length - 12} more</div>` : '')
      : `<div class="tk-empty">${escapeHtml(empty)}</div>`;
    return `<div class="tcol tone-${tone}">
      <div class="tcol-head"><span>${escapeHtml(label)}</span><b>${rows.length}</b></div>
      <div class="tcol-body">${items}</div>
    </div>`;
  };

  // Distances are measured from the day being VIEWED, not from the real
  // today: on an old day, "3d ago" has to mean three days before that day,
  // or a task's age reads as nonsense the further back you walk.
  const anchorKey = taskDayKey || dayKey;
  const [ay, am, ad] = anchorKey.split('-').map(Number);
  const anchorUtc = Date.UTC(ay, am - 1, ad);
  const dayDiff = (d) => {
    if (!d) return '';
    const days = Math.round(
      (Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - anchorUtc) / 86400000);
    if (days === 0) return 'that day';
    if (days === 1) return 'next day';
    if (days > 1) return `+${days}d`;
    return `${-days}d earlier`;
  };

  const board = `<div class="tboard">
    ${taskCol('late', 'Late', 'late', triage.late,
        'Nothing overdue.',
        (r) => dayDiff(toJsDate(r.data.createdAt)))}
    ${taskCol('today', isToday ? 'Today' : 'Added that day', 'today', triage.today,
        'Nothing added that day.')}
    ${taskCol('upcoming', 'Upcoming', 'upcoming', triage.upcoming,
        'Nothing scheduled ahead.',
        (r) => dayDiff(r.reminder))}
    ${taskCol('done', isToday ? 'Done today' : 'Finished that day', 'done', triage.done,
        'Nothing finished.')}
  </div>
  ${triage.noDate.length ? `<div class="tk-more" style="margin-top:8px;">${triage.noDate.length} open task${triage.noDate.length === 1 ? '' : 's'} with no creation date, not shown above</div>` : ''}
  ${isToday ? '' : '<div class="tk-more" style="margin-top:8px;">Rebuilt from each task\'s own created/completed timestamps. A task that was deleted since leaves no record, so it cannot appear here.</div>'}`;

  const roomsHtml = rooms.length
    ? '<div class="today-rooms">' + rooms.map((r) => `
        <div class="today-room${r.allDone ? ' done' : ''}">
          <span>${r.allDone ? '✅' : '⬜'}</span>
          <span class="today-room-name">${escapeHtml(r.name)}</span>
          ${r.muted ? '<span class="muted" style="margin-inline-start:auto;">muted</span>' : ''}
        </div>
      `).join('') + '</div>'
    : '<p class="muted">Not in any rooms.</p>';

  const when = isToday ? 'today' : 'that day';
  const title = total === 0
    ? `No habits scheduled ${when}`
    : done === total
      ? (isToday ? 'All done for today' : 'Everything done')
      : `${done} of ${total} habit${total === 1 ? '' : 's'} done ${when}`;

  const pretty = fmtDate(new Date(`${dayKey}T12:00:00Z`)) || dayKey;
  const canGoForward = !todayKey || dayKey < todayKey;

  return `<div class="day-body">
    <div class="day-stepper" data-day="${escapeHtml(dayKey)}"${todayKey ? ` data-today="${escapeHtml(todayKey)}"` : ''}>
      <button type="button" class="btn step" data-step="-1" title="Previous day">‹</button>
      <input type="date" id="dayPick" value="${escapeHtml(dayKey)}"${todayKey ? ` max="${escapeHtml(todayKey)}"` : ''}>
      <button type="button" class="btn step" data-step="1" title="Next day"${canGoForward ? '' : ' disabled'}>›</button>
      <button type="button" class="btn" data-step="today"${isToday ? ' disabled' : ''}>Today</button>
      <span class="day-stepper-label">${escapeHtml(pretty)}${isToday ? ' <b>· today</b>' : ''}</span>
      <span class="day-stepper-spin" hidden>loading…</span>
    </div>
    <div class="today-hero">
      <div class="today-hero-top">
        <div class="today-ring today-${pctClass}">${total === 0 ? '—' : `${done}/${total}`}</div>
        <div>
          <div class="today-hero-title">${escapeHtml(title)}</div>
          <div class="today-hero-date">${escapeHtml(dayKey)}${hasDoc ? '' : ' · nothing was logged'}</div>
        </div>
      </div>
      ${dayWarn}
      ${habitsHtml}
    </div>
    <h3>Tasks <span class="h3-note">calendar day ${escapeHtml(taskDayKey || dayKey)}</span></h3>
    ${board}
    <h3>Mood &amp; reflection</h3>
    <div class="detail-rows">${rows}</div>
    <h3>Rooms</h3>
    ${roomsHtml}
  </div>`;
}

/// Today, specifically. Kept so nothing that already asks for a "today card"
/// has to know about the stepper; renderDayCard is the same view for any day.
function renderTodayCard(opts) {
  return renderDayCard({ ...opts, dayKey: opts.todayKey, isToday: true });
}

// Builds the {title, nav, body} pieces for one account's report - shared by
// lookup_user.js (drops it into a standalone file) and server.js (serves
// it live at /report/:uid). `sections` is the [{id,label,html,count?}] list
// both entry points build the same way via fetchAccount.js. `nav` renders
// as clickable tab buttons (see REPORT_SCRIPT's setActiveTab) rather than
// anchor links - only one section shows at a time in normal browsing, so
// this reads as an app with sections to switch between instead of one long
// document to scroll through; a non-empty search still reveals every
// section at once (see REPORT_SCRIPT's applyFilters), so nothing becomes
// harder to find because of this.
function buildReportBody({ uid, authRecord, profileData, sections, todaySummary, dayKey, isToday }) {
  const title = authRecord?.email || profileData?.displayName || uid;
  const nav = sections.map((s) =>
    `<button type="button" class="tab-btn" data-target="${escapeHtml(s.id)}">${escapeHtml(s.label)}${s.count !== undefined ? ` <span class="tab-count"${s.id === 'today' ? ' id="dayTabCount"' : ''}>${s.count}</span>` : ''}</button>`
  ).join('');
  const sectionsHtml = sections.map((s) => `
    <section id="${escapeHtml(s.id)}">
      <h2>${escapeHtml(s.label)}${s.count !== undefined ? ` <span class="count"${s.id === 'today' ? ' id="dayHeadCount"' : ''}>${s.count}</span>` : ''}</h2>
      ${renderFilterChips(s.id)}
      ${s.html}
    </section>
  `).join('\n');

  // Named after the day actually being shown, not always "today". Opening a
  // report from an activity-feed row lands on ?day=<that day>, so this is the
  // common path into the page rather than an edge case, and a past day
  // labelled "Today" is a page that states a false fact in its loudest
  // element. The day stepper keeps this in step on every later switch (see
  // REPORT_SCRIPT's loadDay); this is the first paint.
  const pillClass = !todaySummary || todaySummary.total === 0
    ? 'zero'
    : todaySummary.done === todaySummary.total
      ? 'full'
      : todaySummary.done === 0 ? 'none' : 'partial';
  const dayIsToday = isToday !== false;
  const pillWhen = dayIsToday ? 'Today' : (dayKey || 'That day');
  const pillText = !todaySummary || todaySummary.total === 0
    ? `No habits scheduled ${dayIsToday ? 'today' : 'on ' + (dayKey || 'that day')}`
    : `${pillWhen}: ${todaySummary.done}/${todaySummary.total} done`;

  // Who this is, kept in the sticky bar rather than scrolled off the top.
  //
  // The name, the uid and the day's headline number used to sit in a ~290px
  // block above the tabs, which meant that the moment you scrolled into any
  // section you no longer knew whose data you were reading. On a tool whose
  // whole purpose is opening one account after another, that is the one
  // thing that should never leave the screen.
  const who = profileData?.displayName
    ? escapeHtml(profileData.displayName)
    : escapeHtml(authRecord?.email || uid);
  const sub = profileData?.displayName && authRecord?.email ? escapeHtml(authRecord.email) : '';
  const header = `
    <div class="idline">
      <div class="idline-who">
        <h1 class="idline-name bidi">${who}</h1>
        ${sub ? `<span class="idline-mail">${sub}</span>` : ''}
      </div>
      <button type="button" class="uid-copy" data-copy="${escapeHtml(uid)}" title="Copy this uid">
        <span class="uid">${escapeHtml(uid)}</span><span class="uid-copy-ico">⧉</span>
      </button>
      <div class="today-pill today-${pillClass}" id="dayPill">${escapeHtml(pillText)}</div>
    </div>
  `;
  return { title, nav, header, stats: renderHighlights(profileData), body: sectionsHtml };
}

// Colors pulled from this app's own default theme preset
// (lib/core/theme/theme_preset.dart) so this tool reads as part of the same
// product instead of generic admin-panel gray, tuned a shade darker where
// needed for text-on-light contrast.
const BASE_STYLES = `
  /* =====================================================================
     Design tokens
     =====================================================================
     Three rules hold this tool together, and every value below exists to
     serve one of them.

     1. TYPE CARRIES THE HIERARCHY, NOT BOXES. The old sheet said everything
        at 11 to 13px and then tried to rank it with borders, so the page was
        a grid of equally loud outlined rectangles. Size, weight and colour
        rank things now; a border only ever means "these are separate".

     2. THE ACCENT IS FOR INTERACTION. Gold marks what you can act on: the
        active tab, the primary button, a link, a focus ring. It never means
        anything about the data. When gold was also the colour of a warning
        chip and a partial day and a filter pill, none of them stood out.

     3. MEANING HAS ITS OWN SET. Green paid, amber disagreed, red taken
        back, violet undone, blue noted - each as a soft tint with a matching
        ink, never as a heavy border competing with the layout.

     Both themes define the same role names. Nothing below this block names
     a raw colour, which is what makes the dark theme a matter of repointing
     eleven roles rather than auditing seven hundred lines. */
  :root {
    color-scheme: light;

    --bg: #faf8f3;
    --bg-sunken: #f3efe6;
    --surface: #ffffff;
    --surface-2: #faf8f3;
    --border: #e8e2d5;
    --border-soft: #f0ebe0;
    --border-strong: #d6cdb9;
    --text: #191813;
    --text-sec: #5c564b;
    /* Was #8b8477, 3.49:1 on --bg, and it carries h3, .cal-ratio and
       .detail-label at sizes down to 10px. */
    --text-tert: #756f62;

    /* Gold, dark enough to read as text on paper AND to carry white on a
       fill, so one token serves both and links stop being decorative. */
    /* Was #a3701c: 3.81:1 as ink on its own tint, 4.29:1 for white on the
       fill. Both under AA, on the one colour the sheet uses to say "you can
       act on this". This is 5.05:1 and 5.69:1 with no other change. */
    --accent: #8a5e13;
    --accent-hover: #6f4b0e;
    --accent-ink: #ffffff;
    --accent-soft: rgba(138, 94, 19, 0.10);
    --accent-line: rgba(138, 94, 19, 0.34);

    --success: #15805a; --success-soft: rgba(21, 128, 90, 0.10); --success-line: rgba(21, 128, 90, 0.30);
    --danger:  #b03a30; --danger-soft:  rgba(176, 58, 48, 0.10); --danger-line:  rgba(176, 58, 48, 0.30);
    --warn:    #91620d; --warn-soft:    rgba(190, 138, 30, 0.14); --warn-line:   rgba(190, 138, 30, 0.38);
    --info:    #2b6b96; --info-soft:    rgba(43, 107, 150, 0.10); --info-line:   rgba(43, 107, 150, 0.28);
    --undo:    #6d28d9; --undo-soft:    rgba(109, 40, 217, 0.09); --undo-line:   rgba(109, 40, 217, 0.26);

    /* The calendar's four completion tiers, as one ramp rather than four
       unrelated greens picked at four different times. */
    --heat-1: #d4ecdf; --heat-2: #97d6b4; --heat-3: #4bb98a; --heat-4: var(--success);
    --heat-ink: #ffffff;

    /* One spacing ladder instead of a different hand-picked pixel value per
       rule. Everything below steps through these, so the page reads as one
       grid rather than as forty independent decisions. */
    --s0: 2px; --s1: 4px; --s2: 6px; --s3: 8px; --s2b: 10px; --s4: 12px; --s5: 16px; --s6: 22px; --s7: 32px;

    /* A real type scale. Two thirds of this sheet's type used to sit inside
       a 2.5px band (11, 11.5, 12, 12.5, 13, 13.5), so six of its sizes
       ranked nothing against each other and rule 1 above was a claim the
       sheet did not keep. Seven rungs, each a visible step from the last. */
    --t-1: 11px; --t-2: 12px; --t-3: 13px; --t-4: 14px;
    --t-5: 16px; --t-6: 20px; --t-7: 26px;

    /* QUADRANT_META's and MOOD_META's raw hex, promoted to roles. They were
       the one palette that named colours outside this block, which is why
       they were also the one palette the dark repoint never reached. */
    --q-do: #b03a30; --q-sched: #2b6b96; --q-deleg: #a3560f; --q-elim: #6f6a5e;
    --mood-great: var(--success); --mood-good: var(--info);
    --mood-neutral: var(--warn); --mood-sad: #a3560f; --mood-exhausted: var(--danger);

    /* REPORT_SCRIPT overwrites this with the top bar's measured height on
       load and on resize. The literal is the no-JS fallback. */
    --topbar-h: 150px;
    --r-sm: 8px; --r-md: 12px; --r-lg: 16px; --r-pill: 999px;

    /* Borders do the separating almost everywhere; shadow is reserved for
       things that genuinely float above the page (the drawer, the sticky
       bar once it has content scrolling under it). */
    --shadow-sm: 0 1px 2px rgba(25, 24, 20, 0.04);
    --shadow-md: 0 1px 2px rgba(25, 24, 20, 0.04), 0 10px 26px -14px rgba(25, 24, 20, 0.16);
    --shadow-lg: 0 28px 64px -24px rgba(25, 24, 20, 0.34);

    /* Inter if the machine has it or can fetch it, the platform's own face
       otherwise. The fallbacks are listed in full rather than left to a bare
       sans-serif, because this tool is opened on a laptop that is sometimes
       offline and a fallback to Times is its own kind of broken. */
    --sans: 'Inter', -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }

  /* The same eleven roles, repointed. Warm dark rather than neutral grey,
     so the tool still reads as the same product with the lights off, and
     every accent lifted a few steps because a colour that carries on paper
     disappears on ink. */
  @media (prefers-color-scheme: dark) {
    :root {
      color-scheme: dark;

      --bg: #14130f;
      --bg-sunken: #100f0c;
      --surface: #1c1b16;
      --surface-2: #232119;
      --border: #403b30;      /* was #302d25, 1.25:1 on --surface */
      --border-soft: #322e24; /* was #262319, 1.10:1, so a row had no rule */
      --border-strong: #454034;
      --text: #f0ece2;
      --text-sec: #aaa396;
      --text-tert: #8e8779;
      --q-do: #f0897f; --q-sched: #79bcea; --q-deleg: #e2ad4e; --q-elim: #8e8779;
      --mood-sad: #e0a06a;

      --accent: #dda849;
      --accent-hover: #eec06b;
      --accent-ink: #1a1710;
      --accent-soft: rgba(221, 168, 73, 0.14);
      --accent-line: rgba(221, 168, 73, 0.40);

      --success: #4ec596; --success-soft: rgba(78, 197, 150, 0.13); --success-line: rgba(78, 197, 150, 0.34);
      --danger:  #f0897f; --danger-soft:  rgba(240, 137, 127, 0.13); --danger-line: rgba(240, 137, 127, 0.34);
      --warn:    #e2ad4e; --warn-soft:    rgba(226, 173, 78, 0.14); --warn-line:   rgba(226, 173, 78, 0.36);
      --info:    #79bcea; --info-soft:    rgba(121, 188, 234, 0.13); --info-line:  rgba(121, 188, 234, 0.32);
      --undo:    #b493f5; --undo-soft:    rgba(180, 147, 245, 0.13); --undo-line:  rgba(180, 147, 245, 0.32);

      --heat-1: #1d3f33; --heat-2: #2a6149; --heat-3: #348766; --heat-4: #3fa87c;
      --heat-ink: #0f120f;

      --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4);
      --shadow-md: 0 1px 2px rgba(0, 0, 0, 0.4), 0 10px 26px -14px rgba(0, 0, 0, 0.7);
      --shadow-lg: 0 28px 64px -24px rgba(0, 0, 0, 0.8);
    }
  }
  * { box-sizing: border-box; }

  /* Every interactive thing gets the same visible focus ring. The tool is
     heavily keyboard-driven now (day stepper arrows, drawer navigation) and
     the browser default outline disappears against this cream background. */
  :where(a, button, input, summary, [tabindex]):focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
    border-radius: var(--r-sm);
  }
  /* Motion is a hint that something responded, never an animation to watch:
     nothing here runs longer than a sixth of a second, and the whole lot is
     switched off for anyone who asked for less of it. */
  @media (prefers-reduced-motion: no-preference) {
    .btn, .chip-btn, .view-tab, .ev, .ev-run, .live-card, .chip-d.more,
    table.users tr.row, .rcard, .online-pill {
      transition: background-color 0.12s ease, border-color 0.12s ease, color 0.12s ease, box-shadow 0.12s ease;
    }
  }
  /* ---- The task board: four states, side by side, so "what is late" and
     "what is coming" are answered by looking rather than by scrolling. Grid
     with auto-fit so it collapses to two columns on a narrow window and one
     on a phone, without a media query to keep in sync. ---- */
  /* Four, then two, then one. auto-fit gave three plus an orphan below
     about 837px, which is a layout that looks like a bug. */
  .tboard {
    display: grid; grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--s2b); margin-top: var(--s2); align-items: start;
  }
  @media (max-width: 900px) { .tboard { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
  @media (max-width: 520px) { .tboard { grid-template-columns: 1fr; } }
  .tcol { border: 1px solid var(--border); border-radius: 10px; background: var(--surface); overflow: hidden; display: flex; flex-direction: column; }
  .tcol-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 11px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 1px solid var(--border); }
  .tcol-head b { font-size: 13px; font-variant-numeric: tabular-nums; }
  /* A forty item column scrolls inside its own box rather than hiding 28
     records behind a line of grey text with no handler on it. */
  .tcol-body { padding: var(--s2); display: flex; flex-direction: column; gap: 3px; max-height: 340px; overflow-y: auto; }
  .tcol.capped .tcol-body { max-height: none; }
  /* Tone carries the state. Late is the only one that gets a warm alarm
     colour; the others stay quiet, because four shouting columns is the same
     as none shouting. */
  .tone-late .tcol-head { background: var(--danger-soft); color: var(--danger); }
  .tone-today .tcol-head { background: var(--bg-sunken); color: var(--text-sec); }
  .tone-upcoming .tcol-head { background: var(--info-soft); color: var(--info); }
  .tone-done .tcol-head { background: var(--success-soft); color: var(--success); }
  .tk { display: flex; align-items: center; gap: 7px; padding: 5px 7px; border-radius: 7px; font-size: 12.5px; line-height: 1.3; }
  .tk:hover { background: var(--bg); }
  .tk-dot { width: 7px; height: 7px; border-radius: 50%; flex: 0 0 auto; }
  /* plaintext, not isolate: this cell is its own flex item with its own
     edge, so the box direction follows the first strong character and the
     ellipsis lands on the tail. Under a forced ltr an Arabic title was
     clipped at its own OPENING words, which is the half you need. */
  .tk-title {
    flex: 1 1 auto; min-width: 0; overflow: hidden;
    text-overflow: ellipsis; white-space: nowrap;
    unicode-bidi: plaintext; text-align: start;
  }
  .tk-when { flex: 0 0 auto; font-size: 10.5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .tone-done .tk-title { color: var(--text-sec); text-decoration: line-through; text-decoration-color: var(--border); }
  button.tk-more { cursor: pointer; font-family: inherit; background: none; border: none; text-align: start; }
  button.tk-more:hover { color: var(--accent); }
  .tk-more { padding: 4px 7px; font-size: 11px; color: var(--text-tert); }
  .h3-note { text-transform: none; letter-spacing: 0; font-weight: 400; color: var(--text-tert); font-size: 11px; margin-inline-start: 6px; }
  /* ---- The type scale ------------------------------------------------
     Everything used to be said at 11 to 13px, which is why the page needed
     a border around each thing to tell one from another. A real scale ranks
     them without any boxes at all: a heading is a heading because it is
     bigger, not because it sits in a rectangle. Numbers are tabular
     everywhere they appear, so a column of them lines up on the digit. */
  html { -webkit-text-size-adjust: 100%; }
  body {
    font-family: var(--sans);
    font-size: 14px;
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    max-width: 1000px; margin: 0 auto; padding: 0 var(--s5) 72px;
    color: var(--text); background: var(--bg);
  }
  a { color: var(--accent); text-underline-offset: 2px; }
  a:hover { color: var(--accent-hover); }
  h1 { font-size: 25px; font-weight: 700; margin: 24px 0 2px; letter-spacing: -0.5px; }
  h2 { font-size: 16px; font-weight: 650; margin-top: 0; border-bottom: 1px solid var(--border); padding-bottom: var(--s3); margin-bottom: var(--s4); letter-spacing: -0.2px; }
  /* h3 was 11px --text-tert: smaller AND fainter than the 12px paragraphs
     and 13px rows it is meant to rank above, so it read as a footnote
     introducing its own content. */
  h3 {
    font-size: var(--t-2); font-weight: 650; color: var(--text-sec);
    margin: var(--s6) 0 var(--s3); padding-bottom: var(--s2);
    border-bottom: 1px solid var(--border-soft);
    text-transform: uppercase; letter-spacing: 0.6px;
  }
  .h3-note.warn { color: var(--warn); font-weight: 600; }
  /* The section's own <h2> repeated the tab button 30px above it on all ten
     tabs. It stays in the DOM for the document outline and for screen
     readers, and comes back visibly the moment a search reveals every
     section at once, which is the only time it distinguishes anything. */
  .sr-only {
    position: absolute; width: 1px; height: 1px; margin: -1px;
    overflow: hidden; clip-path: inset(50%); white-space: nowrap;
  }
  body.searching section[id] > h2.sr-only {
    position: static; width: auto; height: auto; margin: 0 0 var(--s4);
    overflow: visible; clip-path: none;
  }
  section { margin-top: var(--s6); }
  .count { font-weight: normal; color: var(--text-tert); font-size: 12.5px; }
  .muted { color: var(--text-tert); font-style: italic; }
  .back-link { display: inline-flex; align-items: center; font-size: 12px; color: var(--text-sec); text-decoration: none; padding: 2px 0; }
  .back-link:hover { color: var(--accent); }

  /* ---- Sticky top bar -------------------------------------------------
     Identity, search and the tab strip travel together. Whose account this
     is used to sit in a tall block above the bar and scrolled away the
     moment you opened any section, which on a tool built for moving between
     accounts is exactly the fact that must never leave the screen. */
  .topbar { position: sticky; top: 0; background: var(--bg); padding: var(--s3) 0 var(--s3); border-bottom: 1px solid var(--border); z-index: 20; margin-bottom: var(--s4); }
  .topbar::after { content: ''; position: absolute; inset-inline: 0; bottom: -12px; height: 12px; background: linear-gradient(var(--bg), transparent); pointer-events: none; }
  .idline { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; margin: var(--s2) 0 var(--s3); }
  .idline-who { display: flex; align-items: baseline; gap: var(--s2); min-width: 0; }
  .idline-name { font-size: 17px; font-weight: 700; letter-spacing: -0.2px; margin: 0; }
  .idline-mail { font-size: 12.5px; color: var(--text-sec); }
  .uid-copy { display: inline-flex; align-items: center; gap: var(--s1); padding: 3px var(--s2); border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--surface); cursor: pointer; color: var(--text-tert); font-family: inherit; }
  .uid-copy:hover { border-color: var(--accent); color: var(--accent); }
  .uid-copy .uid { font-family: var(--mono); font-size: 10.5px; }
  .uid-copy-ico { font-size: 10px; opacity: 0.7; }
  .uid-copy.copied { border-color: var(--success); color: var(--success); }
  .idline .today-pill { margin: 0; margin-inline-start: auto; }

  .toolbar-row { display: flex; gap: var(--s2); align-items: center; flex-wrap: wrap; }
  input[type="text"], input[type="search"] { flex: 1; min-width: 160px; padding: 9px var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); font-size: 13.5px; background: var(--surface); color: var(--text); font-family: inherit; }
  input[type="text"]::placeholder, input[type="search"]::placeholder { color: var(--text-tert); }
  input[type="text"]:focus, input[type="search"]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .btn { display: inline-flex; align-items: center; justify-content: center; gap: var(--s2); padding: 8px var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); font-size: 12.5px; font-weight: 500; background: var(--surface); cursor: pointer; color: var(--text); font-family: inherit; box-shadow: var(--shadow-sm); }
  .btn:hover { background: var(--surface-2); border-color: var(--border-strong); }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); font-weight: 600; }
  .btn.primary:hover { background: var(--accent-hover); border-color: var(--accent-hover); }

  /* ---- The account's numbers, as one strip ----------------------------
     Ten equal cards cost ~130px on every tab and weighted "Gold 1708" the
     same as "Theme custom". Inline pairs fit one row, and the value leads
     because the value is what is being looked up. */
  /* Nine equal-weight numbers in an undifferentiated row said nothing about
     which of them matter together. Three groups now, separated by a rule
     rather than by more space. */
  .stats {
    display: flex; flex-wrap: wrap; gap: var(--s2) 0; align-items: baseline;
    padding: var(--s3) var(--s4); border: 1px solid var(--border);
    border-radius: var(--r-md); background: var(--surface); margin-bottom: var(--s5);
  }
  .stat {
    display: inline-flex; align-items: baseline; gap: 3px;
    padding-inline: var(--s5); border-inline-start: 1px solid var(--border-soft);
  }
  .stat:first-child, .stat.group-start { border-inline-start: none; padding-inline-start: 0; }
  .stat b { font-size: var(--t-5); font-weight: 700; letter-spacing: -0.2px; font-variant-numeric: tabular-nums; }
  .stat span { font-size: var(--t-1); color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.4px; }
  .stat.text b { font-size: var(--t-2); font-weight: 600; color: var(--text-sec); font-variant-numeric: normal; }
  .stat.gap b { color: var(--warn); }

  table.fields { border-collapse: collapse; width: 100%; margin: 6px 0; }
  table.fields th { text-align: left; font-weight: 600; color: var(--text-sec); padding: 5px 10px 5px 0; vertical-align: top; white-space: nowrap; width: 1%; font-size: 12.5px; }
  table.fields td { padding: 5px 0; vertical-align: top; font-size: var(--t-3); unicode-bidi: isolate; overflow-wrap: anywhere; }
  .longval {
    display: block; max-height: 120px; overflow: auto;
    font-family: var(--mono); font-size: var(--t-1); word-break: break-all;
  }

  /* ---- One document, closed and open ----------------------------------
     The summary line is what gets scanned; the card underneath is what gets
     read. So the summary carries a status pill (Active/Archived, Open/Done)
     and the card carries the rest, which means most questions are answered
     without opening anything at all. */
  details.doc { border: 1px solid var(--border); border-radius: var(--r-md); margin: var(--s2) 0; background: var(--surface); box-shadow: var(--shadow-sm); }
  details.doc[open] { border-color: var(--accent); }
  details.doc > summary { display: flex; align-items: center; gap: var(--s3); padding: var(--s3) var(--s4); cursor: pointer; font-weight: 600; font-size: 13.5px; list-style: none; border-radius: var(--r-md); }
  details.doc[open] > summary { border-end-start-radius: 0; border-end-end-radius: 0; border-bottom: 1px solid var(--border); }
  details.doc > summary::-webkit-details-marker { display: none; }
  details.doc > summary::before { content: '\\25B8'; flex: 0 0 auto; color: var(--accent); transition: transform 0.15s; font-size: 11px; }
  details.doc[open] > summary::before { transform: rotate(90deg); }
  details.doc > summary:hover { background: var(--accent-soft); }
  /* isolate, not plaintext: this is a fixed left-to-right list, and an
     Arabic habit name under plaintext flipped its own row's alignment while
     every neighbouring row stayed left. */
  .doc-sum { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; unicode-bidi: isolate; }
  .pill { flex: 0 0 auto; padding: 2px var(--s3); border-radius: var(--r-pill); font-size: 9.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; border: 1px solid transparent; }
  .pill-active, .pill-open { background: var(--info-soft); color: var(--info); }
  .pill-done { background: var(--success-soft); color: var(--success); }
  .pill-archived, .pill-none { background: var(--bg); color: var(--text-tert); border-color: var(--border); }
  details.doc > table.fields { padding: 0 var(--s4) var(--s4); margin-top: var(--s3); }
  details.doc > .detail-card { padding: var(--s4); }
  /* The uuid is an identifier you occasionally need to copy, not a heading.
     It used to sit above the title in the reading position. */
  .doc-id { display: inline-flex; align-items: center; gap: var(--s1); margin-top: var(--s4); padding: 2px var(--s2); border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg); font-size: 10px; color: var(--text-tert); font-family: var(--mono); cursor: pointer; }
  .doc-id:hover { border-color: var(--accent); color: var(--accent); }
  .doc-id.copied { border-color: var(--success); color: var(--success); }

  /* Curated per-type detail cards (habits/tasks/daily) - see render.js's
     renderHabitDetail/renderTaskDetail/renderDailyDetail. The label/value
     row pair mirrors this app's own detail-sheet rows (e.g. TaskDetailSheet)
     rather than a raw key/value table. */
  .detail-title { font-size: 15px; font-weight: 700; margin: 0 0 var(--s1); display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; }
  .detail-title > span:first-child { unicode-bidi: isolate; min-width: 0; }
  .detail-subtitle { font-size: 11.5px; color: var(--text-sec); margin: 0 0 var(--s2); }
  /* Direction, decided once for the whole tool:
       isolate  for anything in a fixed left-to-right structure (names,
                titles, short field values). The Arabic renders correctly
                inside its own run and the column keeps a straight edge.
       plaintext for real paragraphs only (.prose below, i.e. a reflection),
                where an Arabic block genuinely should right-align.
     Mixing the two per element is what made one card show a left-aligned
     title above a right-aligned description. */
  .detail-desc { font-size: 13px; color: var(--text-sec); margin: var(--s2) 0 var(--s4); line-height: 1.5; unicode-bidi: isolate; }
  .prose { unicode-bidi: plaintext; display: block; line-height: 1.6; white-space: pre-wrap; }
  /* A grid, not a stack of flex rows: every label column is the same width
     down the whole card, so values form a straight edge you can read down. */
  .detail-rows { display: grid; grid-template-columns: minmax(88px, max-content) 1fr; gap: 0 var(--s4); margin-top: var(--s3); }
  .detail-row { display: contents; }
  .detail-label { color: var(--text-tert); font-size: 10px; text-transform: uppercase; letter-spacing: 0.4px; padding: var(--s2) 0; align-self: start; line-height: 1.6; }
  .detail-value { color: var(--text); font-size: 13px; padding: var(--s2) 0; min-width: 0; unicode-bidi: isolate; }
  .detail-row + .detail-row > .detail-label,
  .detail-row + .detail-row > .detail-value { border-top: 1px solid var(--border); }
  .emo { display: inline-block; margin-inline-end: var(--s2); }
  .color-dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; border: 1px solid var(--border-strong); flex-shrink: 0; }
  /* White measured 2.34:1 on the delegate orange and 2.43:1 on the
     schedule blue. Dark ink clears every one of the four. */
  .badge { display: inline-block; padding: 3px 10px; border-radius: 100px; color: #191813; font-size: 10px; font-weight: 700; letter-spacing: 0.4px; text-transform: uppercase; }
  details.nested.raw { display: block; margin-top: 10px; }
  details.nested.raw > summary { font-size: 11px; color: var(--text-tert); }

  details.nested { display: inline-block; }
  details.nested > summary { cursor: pointer; color: var(--text-sec); font-size: 12px; list-style: none; }
  details.nested > summary::-webkit-details-marker { display: none; }
  details.nested > summary::before { content: '▸ '; }

  .chips { display: flex; flex-wrap: wrap; gap: 5px; }
  .chip { display: inline-block; padding: 2px 9px; border-radius: var(--r-pill); background: var(--bg-sunken); color: var(--text-sec); font-size: var(--t-2); unicode-bidi: isolate; }
  .stack-item { border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; margin: 4px 0; }

  .bool.true { color: var(--success); font-weight: 600; }
  .bool.false { color: var(--text-tert); }

  [hidden] { display: none !important; }
  .generated { color: var(--text-tert); font-size: 11px; margin-top: 40px; }

  /* Tabs (nav.toc buttons - see buildReportBody) - only the active
     section's <section> shows at a time (see section/section.tab-active
     below), so this reads as switching between app screens instead of
     scrolling one long document. */
  /* One row that scrolls sideways, not two wrapped rows. Eleven chips
     wrapping made the sticky bar 40px taller and moved a tab's position
     every time a count changed width. */
  nav.toc { display: flex; gap: var(--s2); margin-top: var(--s3); overflow-x: auto; scrollbar-width: thin; padding-bottom: var(--s1); scroll-behavior: smooth; flex-wrap: nowrap; }
  nav.toc::-webkit-scrollbar { height: 5px; }
  nav.toc::-webkit-scrollbar-thumb { background: var(--border); border-radius: var(--r-pill); }
  nav.toc .tab-btn { flex: 0 0 auto; }

  /* On a phone the sticky bar was taking better than a quarter of the
     screen on a page whose entire job is the content underneath it. The
     identity, the search box and the tabs all have to stay; Expand/Collapse
     all is the one thing there that is a desktop convenience, so that is
     what goes, along with a tighter rhythm. */
  @media (max-width: 640px) {
    .topbar { padding-top: var(--s2); }
    .idline { margin: var(--s1) 0 var(--s2); }
    .idline-name { font-size: 15.5px; }
    .idline .today-pill { margin-inline-start: 0; }
    #expandAll, #collapseAll { display: none; }
    .toolbar-row input[type="search"] { padding: var(--s2) var(--s3); }
    nav.toc { margin-top: var(--s2); }
  }
  /* A fade at the trailing edge, so a strip that continues past the fold
     looks like it continues rather than like it ends there. */
  .toc-wrap { position: relative; }
  /* 34px of gradient sat on top of the last partly-visible tab, hiding the
     thing the fade exists to hint at. */
  .toc-wrap::after { content: ''; position: absolute; inset-block: 0; inset-inline-end: 0; width: 18px; background: linear-gradient(to left, var(--bg), transparent); pointer-events: none; }
  /* Below this the strip wraps onto a second line instead of hiding tabs
     behind a scroll nobody discovers. */
  @media (max-width: 1040px) {
    nav.toc { flex-wrap: wrap; overflow-x: visible; }
    .toc-wrap::after { display: none; }
  }
  .tab-btn { padding: 7px 13px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; font-weight: 600; color: var(--text-sec); cursor: pointer; }
  .tab-btn:hover { border-color: var(--accent); color: var(--accent); }
  .tab-btn.active { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }
  .tab-btn .tab-count { opacity: 0.75; font-weight: 500; }
  section[id] { display: none; }
  section[id].tab-active { display: block; }
  /* A non-empty search overrides tabs entirely - every section becomes
     visible so results outside the current tab are never silently
     missed (see REPORT_SCRIPT's applyFilters). */
  /* Search IS the navigation now: only sections with a hit are shown, and
     the tabs stay live so you can still cross to one. Switching every tab
     off mid-search was the old behaviour, and it meant typing a word cost
     you the ability to navigate at all. */
  body.searching section[id].has-hits { display: block !important; }
  body.searching .tab-btn.no-hits { opacity: 0.45; }
  .hit { box-shadow: 0 0 0 2px var(--accent-line); border-radius: var(--r-sm); }
  #searchCount { flex: 0 0 auto; font-size: var(--t-2); color: var(--text-tert); white-space: nowrap; }
  .tab-btn .tab-count.gap { color: var(--warn); opacity: 1; font-weight: 700; }
  .tab-btn.active .tab-count.gap { color: var(--accent-ink); }

  /* Today pill (header) + Today hero card (first tab) - see
     renderTodayCard/buildReportBody. Answers "did this account do their
     habits today" at a glance, using the app's own scheduling rule
     (habitScheduledOnParts), not a raw habit count. */
  .today-pill { display: inline-block; padding: 4px 12px; border-radius: 100px; font-size: 12px; font-weight: 700; margin: 8px 0 2px; }
  .today-pill.today-full { background: var(--success-soft); color: var(--success); }
  .today-pill.today-partial { background: var(--warn-soft); color: var(--warn); }
  .today-pill.today-none { background: var(--danger-soft); color: var(--danger); }
  .today-pill.today-zero { background: var(--bg); color: var(--text-tert); border: 1px solid var(--border); }

  /* =====================================================================
     THE TALLY and THE LEDGER
     =====================================================================
     These two replace 113 words of amber prose that ASSERTED what the
     three records said without ever printing one of their values.

     The tally is the day in three numbers. The ledger is the evidence:
     habit down the side, the three records across the top, real values in
     the cells, and a last column naming where each habit actually counted.
     The only tinted cells anywhere on the day card are the two that
     disagree, so the eye lands on the answer before deciding to read. */
  .tally {
    display: flex; flex-wrap: wrap; align-items: baseline; gap: var(--s2) var(--s5);
    padding: var(--s3) var(--s4); border: 1px solid var(--border);
    border-radius: var(--r-md); background: var(--surface); margin-bottom: var(--s3);
  }
  .tally.disagree { border-color: var(--warn-line); background: var(--warn-soft); }
  .ty { display: inline-flex; align-items: baseline; gap: var(--s2); }
  .ty + .ty { padding-inline-start: var(--s5); border-inline-start: 1px solid var(--border-soft); }
  .ty b {
    font-size: var(--t-6); font-weight: 700; line-height: 1;
    letter-spacing: -0.5px; font-variant-numeric: tabular-nums;
  }
  .ty span {
    font-size: var(--t-1); color: var(--text-sec);
    text-transform: uppercase; letter-spacing: 0.4px;
  }
  .ty.paid b { color: var(--success); }
  .ty.paid.short b { color: var(--warn); }
  .ty.room b { color: var(--info); }
  /* Same class name the calm-versus-loud distinction already used, restyled
     from its own box into one line inside the tally, so a disagreement is
     part of the numbers rather than a second competing block above them. */
  .tally .day-warn {
    flex: 1 1 100%; border: none; background: none; padding: 0; margin: 0;
    font-size: var(--t-2); line-height: 1.5; color: var(--warn);
  }
  .tally .day-warn.calm { color: var(--text-sec); }
  .tally .day-warn b { font-weight: 650; }

  .lg-wrap {
    overflow-x: auto; border: 1px solid var(--border);
    border-radius: var(--r-md); background: var(--surface);
  }
  table.ledger { border-collapse: collapse; width: 100%; font-size: var(--t-3); }
  table.ledger th, table.ledger td {
    text-align: start; padding: var(--s2) var(--s3);
    vertical-align: middle; white-space: nowrap;
  }
  table.ledger thead th {
    font-size: var(--t-1); font-weight: 650; color: var(--text-sec);
    text-transform: uppercase; letter-spacing: 0.5px; white-space: normal;
    background: var(--bg-sunken); border-bottom: 1px solid var(--border);
  }
  /* The habit name stays put while the three records scroll under it, so a
     horizontal scroll never costs a row its identity. */
  .lg-habit {
    position: sticky; inset-inline-start: 0; z-index: 1;
    background: var(--surface); font-weight: 600; white-space: normal;
    min-width: 150px; max-width: 280px; border-inline-end: 1px solid var(--border-soft);
  }
  thead .lg-habit { background: var(--bg-sunken); }
  .lg-name { unicode-bidi: isolate; }
  .lg-emo { margin-inline-end: var(--s2); }
  table.ledger tbody tr + tr th, table.ledger tbody tr + tr td { border-top: 1px solid var(--border-soft); }
  /* The verdict as a rail on the name cell, so a row is readable without
     reaching the "Counts where" column on a narrow window. */
  table.ledger tbody .lg-row th.lg-habit {
    border-inline-start: 3px solid transparent;
    padding-inline-start: calc(var(--s3) - 3px);
  }
  .lg-row.v-completed th.lg-habit { border-inline-start-color: var(--success); }
  .lg-row.v-grid_only th.lg-habit { border-inline-start-color: var(--warn); }
  .lg-row.v-undone th.lg-habit { border-inline-start-color: var(--undo); }
  .lg-row.v-marked th.lg-habit { border-inline-start-color: var(--border-strong); }
  .lg-val { font-variant-numeric: tabular-nums; }
  .lg-none { color: var(--text-tert); }
  .lg-row.disagree td.lg-c-comp, .lg-row.disagree td.lg-c-sq { background: var(--warn-soft); }
  .lg-where { font-size: var(--t-2); font-weight: 650; white-space: nowrap; }
  .w-both { color: var(--success); }
  .w-room, .w-xp { color: var(--warn); }
  .w-none { color: var(--text-tert); font-weight: 400; }
  /* A receipt, a mirror disagreement, or the person's own square note,
     hanging under its own row instead of floating as a paragraph. */
  .lg-sub td {
    font-size: var(--t-2); color: var(--text-sec);
    white-space: normal; padding-top: 0; border-top: none;
  }
  table.ledger tbody tr.lg-sub td { border-top: none; }
  .lg-sub.undo td { color: var(--undo); }
  .lg-sub.warn td { color: var(--warn); }
  .lg-note { unicode-bidi: plaintext; display: block; white-space: pre-wrap; line-height: 1.6; }
  .lg-legend { font-size: var(--t-2); line-height: 1.55; color: var(--text-sec); margin: var(--s3) 0 var(--s5); }
  .lg-legend b { color: var(--text); font-weight: 650; }
  /* The habits the card used to drop without a word, which is exactly what
     "my habit disappeared" arrives asking about. */
  .offsched { margin: 0 0 var(--s5); font-size: var(--t-2); color: var(--text-tert); }
  .offsched b { color: var(--text-sec); font-weight: 600; }
  .offsched ul { margin: var(--s1) 0 0; padding-inline-start: var(--s5); }
  .offsched li { unicode-bidi: isolate; }

  /* Rooms on this day: the same table shape as the ledger, because the room
     is the fourth column of the same comparison. */
  table.rmday { border-collapse: collapse; width: 100%; font-size: var(--t-3); margin-bottom: var(--s3); }
  table.rmday th, table.rmday td { text-align: start; padding: var(--s2) var(--s3); white-space: nowrap; }
  table.rmday thead th {
    font-size: var(--t-1); font-weight: 650; color: var(--text-sec);
    text-transform: uppercase; letter-spacing: 0.5px; white-space: normal;
    border-bottom: 1px solid var(--border);
  }
  table.rmday tbody tr + tr td { border-top: 1px solid var(--border-soft); }
  .rm-name { font-weight: 650; unicode-bidi: isolate; }
  .rm-n { font-variant-numeric: tabular-nums; }
  .rmday tr.disagree td.rm-mine, .rmday tr.disagree td.rm-theirs { background: var(--warn-soft); color: var(--warn); }
  .rm-code { font-family: var(--mono); font-size: var(--t-1); color: var(--text-tert); margin-inline-start: var(--s2); }
  .rm-note { color: var(--text-sec); font-size: var(--t-2); }
  .rm-note.stale { color: var(--warn); }

  .raw-maps { margin-top: var(--s6); }
  .raw-maps > summary { font-size: var(--t-2); color: var(--text-sec); cursor: pointer; }

  .today-hero { border: 1px solid var(--border); border-radius: 14px; padding: 16px; margin-bottom: 4px; background: var(--surface); }
  .today-hero-top { display: flex; align-items: center; gap: 14px; margin-bottom: 14px; }
  .today-ring { width: 54px; height: 54px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px; border: 3px solid var(--border); flex-shrink: 0; }
  .today-ring.today-full { border-color: var(--success); color: var(--success); }
  .today-ring.today-partial { border-color: var(--accent); color: var(--accent); }
  .today-ring.today-none { border-color: var(--danger-line); color: var(--danger); }
  .today-ring.today-zero { border-color: var(--border); color: var(--text-tert); }
  .today-hero-title { font-weight: 700; font-size: 15px; }
  .today-hero-date { color: var(--text-sec); font-size: 12px; margin-top: 1px; }
  .today-habits { display: flex; flex-direction: column; gap: 4px; }
  .today-habit { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-radius: 8px; font-size: 13px; }
  .today-habit.done { background: var(--accent-soft); }
  .today-habit-name { flex: 1; unicode-bidi: isolate; }
  /* Hangs under its own .today-habit row: indented past the two glyph
     columns so it reads as that row's footnote, not as another habit. */
  .today-habit-note { font-size: 11.5px; line-height: 1.5; padding: 0 8px 6px 34px; margin-top: -4px; }
  .today-habit-note.warn { color: var(--warn); }
  .today-habit-note.undo { color: var(--undo); }
  .today-habit-count { color: var(--text-tert); font-size: 11.5px; }
  .today-rooms { display: flex; flex-direction: column; gap: 4px; }
  .today-room { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border: 1px solid var(--border); border-radius: 8px; font-size: 13px; }
  .today-room.done { border-color: var(--success); }
  .today-room-name { unicode-bidi: isolate; }
  .today-tag { display: inline-block; background: var(--accent); color: var(--accent-ink); font-size: 9.5px; font-weight: 700; letter-spacing: 0.3px; text-transform: uppercase; padding: 1px 7px; border-radius: 100px; margin-inline-end: 6px; vertical-align: 1px; }

  /* Daily activity calendar (renderCalendarSection) - a real month grid
     instead of a flat list of collapsed log lines. Heat levels reuse the
     app's own green scale (--success), same idea as GameColors.emerald's
     0-4 opacity ladder (monthly_heatmap_screen.dart/rooms_notifier.dart),
     just expressed as flat colors here since there's no CSS opacity-on-a-
     themed-color equivalent worth fighting for in a plain admin page. */
  .cal-legend { display: flex; align-items: center; gap: 6px; font-size: 11.5px; margin-bottom: 14px; flex-wrap: wrap; }
  .cal-legend-hint { margin-inline-start: auto; }
  .legend-swatch { width: 13px; height: 13px; border-radius: 3px; display: inline-block; border: 1px solid var(--border); }
  .legend-swatch.level-0 { background: var(--bg); }
  .legend-swatch.level-1 { background: var(--heat-1); }
  .legend-swatch.level-2 { background: var(--heat-2); }
  .legend-swatch.level-3 { background: var(--heat-3); }
  .legend-swatch.level-4 { background: var(--success); }

  .day-detail-panel { border: 1px solid var(--border); border-radius: 12px; padding: 14px 16px; background: var(--surface); margin-bottom: 22px; scroll-margin-top: 90px; }
  .day-detail-head { display: flex; align-items: baseline; gap: 8px; margin-bottom: 8px; }
  .day-detail-head strong { font-size: 14px; }

  .cal-month { margin-bottom: 26px; }
  .cal-month-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; margin-bottom: 8px; flex-wrap: wrap; }
  .cal-month-head h4 { margin: 0; font-size: 13.5px; font-weight: 700; }
  .cal-weekdays { display: grid; grid-template-columns: repeat(7, 1fr); gap: 5px; margin-bottom: 4px; }
  .cal-weekdays span { text-align: center; font-size: 10px; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.4px; }
  .cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 5px; }
  .cal-cell { aspect-ratio: 1; border-radius: 8px; }
  .cal-empty { background: transparent; }
  .cal-day {
    border: 1px solid var(--border); background: var(--bg); cursor: pointer; padding: 4px;
    display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1px;
    font-family: inherit; position: relative;
  }
  .cal-day:disabled { cursor: default; opacity: 0.55; }
  .cal-day:not(:disabled):hover { border-color: var(--accent); }
  .cal-day.today { box-shadow: 0 0 0 2px var(--accent) inset; }
  .cal-day.selected { box-shadow: 0 0 0 2px var(--text) inset; }
  .cal-day.level-0 { background: var(--bg); }
  .cal-day.level-1 { background: var(--heat-1); }
  .cal-day.level-2 { background: var(--heat-2); }
  .cal-day.level-3 { background: var(--heat-3); }
  .cal-day.level-4 { background: var(--success); }
  .cal-day.level-3 .cal-day-num, .cal-day.level-4 .cal-day-num { color: var(--heat-ink); }
  .cal-day.level-3 .cal-ratio, .cal-day.level-4 .cal-ratio { color: var(--heat-ink); opacity: 0.85; }
  .cal-day-num { font-size: 11.5px; font-weight: 700; }
  .cal-mood { position: absolute; top: 2px; inset-inline-end: 2px; font-size: 9px; }
  .cal-ratio { font-size: 8.5px; color: var(--text-tert); }

  /* The two disagreements a day can carry (see readHabitDay). Pinned to the
     START corner because .cal-mood already owns the END one, and kept to a
     single glyph so a month of cells stays scannable: the day panel is where
     the explanation lives, this is only the thing that makes you click. */
  .cal-flag { position: absolute; top: 2px; inset-inline-start: 3px; font-size: 9px; line-height: 1; font-weight: 700; }
  .cal-flag.warn { color: var(--warn); }
  .cal-flag.undo { color: var(--undo); }
  .cal-day.level-3 .cal-flag, .cal-day.level-4 .cal-flag { color: var(--heat-ink); }
  .flag-warn { color: var(--warn); }
  .flag-undo { color: var(--undo); }
  .cal-legend-note { font-size: 11.5px; line-height: 1.55; margin: -8px 0 14px; }

  /* A note that belongs to the .stack-item above it: same left edge, no box
     of its own, so a row and its explanation read as one thing rather than
     two list entries. */
  .stack-note { font-size: 11.5px; line-height: 1.5; padding: 2px 10px 8px; margin: -2px 0 6px; color: var(--text-sec); border-inline-start: 2px solid transparent; }
  .stack-note.warn { border-inline-start-color: var(--warn); color: var(--warn); }
  .stack-note.undo { border-inline-start-color: var(--undo); color: var(--undo); }
  .day-warn { border: 1px solid var(--warn-line); background: var(--warn-soft); color: var(--warn); border-radius: 8px; padding: 8px 10px; font-size: 12px; line-height: 1.5; margin-bottom: 10px; }
  /* A backfilled day disagrees for a designed reason, so it states the fact
     without the alarm colour the pre-cutoff case earns. */
  .day-warn.calm { border-color: var(--border); background: var(--bg); color: var(--text-sec); }

  /* Per-section status chips (Active/Archived, Open/Done - see
     SECTION_FILTERS/renderFilterChips). Deliberately not reusing .chip -
     that one's the read-only array-value pill style used inside table
     cells, this needs a clickable/active look instead. */
  .filter-chips { display: flex; flex-wrap: wrap; gap: 6px; margin: -4px 0 14px; }
  .filter-chip { padding: 5px 12px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; color: var(--text-sec); cursor: pointer; }
  .filter-chip:hover { border-color: var(--accent); color: var(--accent); }
  .filter-chip.active { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); font-weight: 600; }

  /* ---- Day stepper (renderDayCard) ------------------------------------
     The control that turns the report's first tab from "today" into "any
     day". Sticky under the toolbar because it is the thing you keep
     reaching for while reading the day below it. */
  .day-stepper { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 9px 11px; border: 1px solid var(--border); border-radius: 11px; background: var(--surface); margin-bottom: 12px; }
  .day-stepper input[type="date"] { padding: 7px 10px; border: 1px solid var(--border); border-radius: 8px; font-size: 12.5px; background: var(--bg); color: var(--text); font-family: inherit; }
  .day-stepper .btn.step { min-width: 34px; font-size: 15px; line-height: 1; padding: 8px 10px; }
  .day-stepper .btn:disabled { opacity: 0.4; cursor: default; }
  .day-stepper .btn:disabled:hover { background: var(--surface); border-color: var(--border); }
  .day-stepper-label { font-size: 12.5px; color: var(--text-sec); margin-inline-start: auto; }
  .day-stepper-label b { color: var(--accent); font-weight: 700; }
  .day-stepper-spin { font-size: 12px; color: var(--text-tert); }
  .day-body.loading { opacity: 0.45; transition: opacity 0.12s; }

  /* ---- Dashboard: live strip ------------------------------------------
     Four numbers, biggest first, that answer "is anything happening" from
     across the room. .live-dot only ever appears on the first one, because
     it is the only one making a claim about right now. */
  .live-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: var(--s3); margin-bottom: var(--s5); }
  .live-card { border: 1px solid var(--border); border-radius: var(--r-lg); padding: var(--s4) var(--s5); background: var(--surface); box-shadow: var(--shadow-sm); }
  .live-card.hot { border-color: var(--success-line); background: var(--success-soft); box-shadow: none; }
  .live-value { font-size: 32px; font-weight: 700; line-height: 1.1; letter-spacing: -1.2px; font-variant-numeric: tabular-nums; display: flex; align-items: center; gap: var(--s3); }
  .live-label { font-size: 10px; font-weight: 600; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.7px; margin-top: var(--s2); }
  .live-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--success); box-shadow: 0 0 0 0 var(--success-line); animation: livepulse 2s infinite; flex: 0 0 auto; }
  @keyframes livepulse { 70% { box-shadow: 0 0 0 9px transparent; } 100% { box-shadow: 0 0 0 0 transparent; } }
  @media (prefers-reduced-motion: reduce) { .live-dot { animation: none; } }

  /* ---- Dashboard: activity feed --------------------------------------- */
  /* Not overflow:hidden. That made .feed the sticky containing block for
     .feed-day below, and since it never scrolls, the day headers silently
     never pinned. Clipping the first and last rows' corners gets the same
     rounded card without trapping them. */
  .feed { border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); }
  .feed > :first-child { border-start-start-radius: 15px; border-start-end-radius: 15px; }
  .feed > :last-child { border-end-start-radius: 15px; border-end-end-radius: 15px; border-bottom: none; }
  /* Sunken rather than raised, and no uppercase shouting: a date is a place
     marker in the list, not a headline competing with the rows under it. */
  .feed-day { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s4); padding: var(--s3) var(--s5); background: var(--bg-sunken); border-bottom: 1px solid var(--border); border-top: 1px solid var(--border); font-size: 12px; font-weight: 650; letter-spacing: -0.1px; color: var(--text-sec); position: sticky; top: 0; z-index: 3; }
  .feed > .feed-day:first-child { border-top: none; }
  .feed-day .fd-count { font-weight: 450; color: var(--text-tert); flex: 0 0 auto; font-variant-numeric: tabular-nums; font-size: 11.5px; }
  .feed-day + .ev, .feed-day + .ev-run { border-start-start-radius: 0; border-start-end-radius: 0; }

  /* One person's uninterrupted burst gets ONE name, not a name per row.
     Four tasks added in the same minute used to repeat a display name and a
     full email address four times over, and that repetition was most of what
     the eye had to wade through to find the four things that actually
     differed. A run re-announces itself every few rows (see RUN_MAX), so
     landing mid-scroll never leaves a row belonging to nobody. */
  .ev-run { display: flex; align-items: center; gap: var(--s3); padding: var(--s4) var(--s5) var(--s2); cursor: pointer; }
  .ev-run:hover .nm { color: var(--accent); }
  .ev-run .nm { font-weight: 650; font-size: 13.5px; letter-spacing: -0.1px; unicode-bidi: isolate; flex: 0 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ev-run .ml { font-size: 11.5px; color: var(--text-tert); unicode-bidi: isolate; flex: 0 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ev-run .cnt { margin-inline-start: auto; flex: 0 0 auto; font-size: 11px; color: var(--text-tert); font-variant-numeric: tabular-nums; }

  /* An initial in a tinted disc, coloured from the uid (see avatarFor).
     Two people whose names start alike are still told apart at a glance, and
     a run of rows gets an anchor the eye can come back to after scrolling,
     which a line of text alone never gave it. */
  .avatar { flex: 0 0 auto; width: 26px; height: 26px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; letter-spacing: 0; color: var(--surface); text-transform: uppercase; unicode-bidi: isolate; }
  @media (prefers-color-scheme: dark) { .avatar { color: var(--bg); } }

  /* A row is a timeline entry, not a table row: the clock time runs down its
     own column, because "4h ago" printed four times in a row says nothing
     about what happened in which order, and the order is the question. The
     relative age stays underneath it, smaller, for the glance that only
     wants to know how stale this is. */
  .ev { display: grid; grid-template-columns: 46px 22px minmax(0, 1fr); align-items: start; gap: var(--s4); padding: var(--s3) var(--s5); border-bottom: 1px solid var(--border-soft); cursor: pointer; }
  .ev:last-child { border-bottom: none; }
  .ev:hover { background: var(--surface-2); }
  .ev-time { text-align: end; font-variant-numeric: tabular-nums; padding-top: 1px; }
  .ev-time b { display: block; font-size: 12.5px; font-weight: 600; color: var(--text-sec); letter-spacing: -0.2px; }
  .ev-time .rel { display: block; font-size: 10px; color: var(--text-tert); margin-top: 1px; }
  .ev.live .ev-time b { color: var(--success); }

  /* A rail, not a row of boxed icons. Every row used to carry a 26px
     bordered square, so nine rows read as nine more rectangles stacked on
     the ones already there. The emoji still says what KIND of event this is;
     it just no longer needs a frame to be seen. A rule between the marks
     joins the run into one thread. */
  .ev-ico { position: relative; width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; font-size: 13px; flex: 0 0 auto; line-height: 1; }
  .ev.in-run .ev-ico::before { content: ''; position: absolute; inset-inline-start: 50%; top: -14px; bottom: 18px; width: 1px; background: var(--border); transform: translateX(-0.5px); }

  .ev-main { min-width: 0; }
  .ev-who { display: flex; align-items: center; gap: var(--s2); font-weight: 650; font-size: 13.5px; letter-spacing: -0.1px; min-width: 0; unicode-bidi: isolate; }
  .ev-who > .bidi { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ev-who .avatar { width: 20px; height: 20px; font-size: 9.5px; }
  .ev-who .ev-mail { font-weight: 400; color: var(--text-tert); font-size: 11.5px; unicode-bidi: isolate; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  /* Inside a run the name is already overhead, so the row leads with the
     thing that is different about it. */
  .ev.in-run .ev-who { display: none; }
  .ev-what { font-size: 13px; color: var(--text); margin-top: 1px; line-height: 1.45; unicode-bidi: isolate; }
  .ev-what .ev-sub { color: var(--text-sec); }

  /* The detail chips. Tone says what a chip MEANS (built in activity.js);
     only this block decides what that looks like. Nothing here is decoration:
     a green chip is a paid completion, a dashed grey one is a habit that was
     due and never marked, amber is the Grid-square disagreement and red the
     un-marking, which are the two an admin is usually hunting for. */
  /* Tint, not outline. Twelve outlined pills under one row drew twelve more
     rectangles and made the row they belong to harder to find, so the border
     is gone and the tint alone carries the tone. A miss is the exception: it
     is the absence of something, so it gets no fill at all and recedes,
     which is exactly the weight "they did not do this" should have. */
  .ev-chips { display: flex; flex-wrap: wrap; gap: var(--s1); margin-top: var(--s2); }
  .chip-d { font-size: 11.5px; line-height: 1.5; padding: 1px 9px; border-radius: var(--r-sm); border: 1px solid transparent; background: var(--bg-sunken); color: var(--text-sec); unicode-bidi: isolate; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .chip-d.done { background: var(--success-soft); color: var(--success); }
  .chip-d.miss { background: none; border-color: var(--border); color: var(--text-tert); }
  .chip-d.warn { background: var(--warn-soft); color: var(--warn); font-weight: 500; }
  .chip-d.undo { background: var(--danger-soft); color: var(--danger); font-weight: 500; }
  .chip-d.note { background: var(--info-soft); color: var(--info); }
  .chip-d.quote { white-space: normal; background: none; border-color: var(--border); font-style: italic; color: var(--text-sec); }
  .chip-d.more { cursor: pointer; font-family: inherit; font-weight: 600; color: var(--accent); background: var(--accent-soft); }
  .chip-d.more:hover { background: var(--accent); color: var(--accent-ink); }

  /* The paging control is a button, not another .ev: once .ev became a
     three-column grid, a centred row inside it was no longer expressible. */
  .feed-more { display: block; width: 100%; padding: var(--s4); border: none; border-top: 1px solid var(--border); background: var(--surface); color: var(--accent); font-family: inherit; font-size: 12.5px; font-weight: 600; cursor: pointer; border-end-start-radius: 15px; border-end-end-radius: 15px; }
  .feed-more:hover { background: var(--accent-soft); }

  @media (max-width: 640px) {
    .ev { grid-template-columns: 44px 22px minmax(0, 1fr); gap: 8px; }
    .ev-run .ml { display: none; }
  }
  /* A run of user-written text (a name, a habit, a task title) that may be
     Arabic, sitting inside a left-to-right row. Without isolating each run
     on its own, an Arabic display name and the Latin email beside it get
     reordered into each other. */
  .bidi { unicode-bidi: isolate; }

  /* ---- Dashboard: view tabs + shared toolbar --------------------------- */
  /* A segmented control, not two loose pills. These two are one choice
     between two states, and drawing them as separate buttons said they were
     two separate things you could each turn on. The track makes the choice
     visible: one of these is always selected, and it is the one on the
     raised tile. */
  .view-tabs { display: inline-flex; gap: 2px; margin-bottom: var(--s5); padding: 3px; border-radius: var(--r-md); background: var(--bg-sunken); border: 1px solid var(--border); }
  .view-tab { padding: 6px var(--s5); border-radius: 9px; border: 1px solid transparent; background: none; font-size: 12.5px; font-weight: 550; color: var(--text-sec); cursor: pointer; font-family: inherit; }
  .view-tab:hover { color: var(--text); }
  .view-tab.active { background: var(--surface); border-color: var(--border); color: var(--text); font-weight: 650; box-shadow: var(--shadow-sm); }
  .view-tab .vt-count { color: var(--text-tert); font-weight: 500; margin-inline-start: var(--s2); font-variant-numeric: tabular-nums; }
  .view-tab.active .vt-count { color: var(--accent); }

  /* Today column in the accounts table: the same ring language the report
     uses, shrunk to a table cell so a whole roster reads at a glance. */
  .mini-ring { display: inline-flex; align-items: center; justify-content: center; min-width: 42px; padding: 2px 8px; border-radius: 100px; font-size: 11.5px; font-weight: 700; border: 1.5px solid var(--border); color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .mini-ring.today-full { border-color: var(--success-line); color: var(--success); background: var(--success-soft); }
  .mini-ring.today-partial { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }
  .mini-ring.today-none { border-color: var(--danger-line); color: var(--danger); }
  .online-dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; background: var(--success); margin-inline-end: 6px; vertical-align: 1px; }
`;

// Inline script shared by every report page: expand/collapse-all, tab
// switching (one section visible at a time), per-section status chip
// filtering, and a search box that overrides both - it shows every
// section and filters top-level entries (details.doc) by their full text
// content, including whatever's inside them while still collapsed -
// textContent reads collapsed descendants fine, only the visual open/
// closed state is affected by [open]. A match auto-opens itself so it's
// obvious why it matched instead of just appearing blank.
const REPORT_SCRIPT = `
(function () {
  var expandAll = document.getElementById('expandAll');
  var collapseAll = document.getElementById('collapseAll');
  var search = document.getElementById('search');
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.tab-btn'));
  var sections = Array.prototype.slice.call(document.querySelectorAll('section[id]'));

  function allDetails() {
    return Array.prototype.slice.call(document.querySelectorAll('details'));
  }

  if (expandAll) expandAll.addEventListener('click', function () {
    allDetails().forEach(function (d) { d.open = true; });
  });
  if (collapseAll) collapseAll.addEventListener('click', function () {
    allDetails().forEach(function (d) { d.open = false; });
  });

  // ---- Tabs: exactly one section visible at a time in normal browsing.
  function setActiveTab(id) {
    tabs.forEach(function (t) { t.classList.toggle('active', t.getAttribute('data-target') === id); });
    sections.forEach(function (s) { s.classList.toggle('tab-active', s.id === id); });
  }
  tabs.forEach(function (t) {
    t.addEventListener('click', function () { setActiveTab(t.getAttribute('data-target')); });
  });
  if (tabs.length) setActiveTab(tabs[0].getAttribute('data-target'));

  // ---- Per-section status chips - each scope (section id) tracks its
  // own picked status independently of every other section's chips.
  var chipScopes = {};
  Array.prototype.forEach.call(document.querySelectorAll('.filter-chips'), function (row) {
    var scope = row.getAttribute('data-filter-scope');
    chipScopes[scope] = '';
    Array.prototype.forEach.call(row.querySelectorAll('.filter-chip'), function (chip) {
      chip.addEventListener('click', function () {
        chipScopes[scope] = chip.getAttribute('data-status') || '';
        Array.prototype.forEach.call(row.querySelectorAll('.filter-chip'), function (c) {
          c.classList.toggle('active', c === chip);
        });
        applyFilters();
      });
    });
  });

  // ---- Combined visibility: a .doc shows only if it matches BOTH the
  // current search text and its own section's chip filter (if that
  // section has one and it isn't "All"). A non-empty search also forces
  // every section visible, ignoring the active tab, so a match outside
  // the current tab is never silently hidden.
  var items = allDetails().filter(function (d) { return d.classList.contains('doc'); });
  function applyFilters() {
    var q = search ? search.value.trim().toLowerCase() : '';
    document.body.classList.toggle('searching', !!q);
    items.forEach(function (el) {
      var parentSection = el.closest('section[id]');
      var scope = parentSection ? parentSection.id : null;
      var wantStatus = scope ? chipScopes[scope] : '';
      var statusOk = !wantStatus || el.getAttribute('data-status') === wantStatus;
      var textOk = !q || el.textContent.toLowerCase().indexOf(q) !== -1;
      var show = statusOk && textOk;
      el.hidden = !show;
      if (show && q) el.open = true;
    });
  }
  if (search) search.addEventListener('input', applyFilters);
  applyFilters();

  // ---- Daily activity calendar: click a day cell, see its full breakdown
  // in the shared panel pinned above the month grids (see
  // renderCalendarSection's doc comment for why this reads from data
  // already sitting on the page in #dayDetailData rather than fetching
  // anything). Scrolled into view on every click since the panel sits
  // above the grids - clicking a day in an older month, further down the
  // page, would otherwise change a panel the person can no longer see.
  var dayDetailPanel = document.getElementById('dayDetailPanel');
  var dayDetailData = document.getElementById('dayDetailData');
  if (dayDetailPanel && dayDetailData) {
    var dayButtons = Array.prototype.slice.call(document.querySelectorAll('.cal-day'));
    dayButtons.forEach(function (btn) {
      if (btn.disabled) return;
      btn.addEventListener('click', function () {
        var date = btn.getAttribute('data-date');
        var source = dayDetailData.querySelector('.day-detail[data-date="' + date + '"]');
        if (!source) return;
        // The full day (habits + the task board as it stood + rooms) lives
        // on the Day tab, so the calendar hands off to it rather than
        // growing a second, thinner copy of the same view.
        dayDetailPanel.innerHTML = source.innerHTML
          + '<button type="button" class="btn" data-open-day="' + date
          + '" style="margin-top:10px;">Open the full day, with tasks →</button>';
        dayButtons.forEach(function (b) { b.classList.toggle('selected', b === btn); });
        dayDetailPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });
  }

  // ---- Copy buttons (the uid in the top bar, each document's id).
  // Delegated so ids inside sections rendered later, or a day card swapped
  // in by the stepper, work without rebinding.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('[data-copy]');
    if (!btn) return;
    var value = btn.getAttribute('data-copy');
    var done = function () {
      btn.classList.add('copied');
      setTimeout(function () { btn.classList.remove('copied'); }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(value).then(done, function () {});
    } else {
      var ta = document.createElement('textarea');
      ta.value = value;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); done(); } catch (err) {}
      document.body.removeChild(ta);
    }
  });

  // ---- Day stepper: the same report, any day.
  //
  // The uid is stamped on <body> only when a server is serving this page.
  // lookup_user.js writes a standalone file with no server behind it, so
  // there is nothing to ask for another day; the stepper hides itself
  // rather than sitting there as a control that silently does nothing.
  var reportUid = document.body.getAttribute('data-uid');
  if (!reportUid) {
    Array.prototype.forEach.call(document.querySelectorAll('.day-stepper'), function (el) {
      el.hidden = true;
    });
  } else {
    var shiftDay = function (key, delta) {
      var p = key.split('-').map(Number);
      var d = new Date(Date.UTC(p[0], p[1] - 1, p[2]));
      d.setUTCDate(d.getUTCDate() + delta);
      return d.toISOString().slice(0, 10);
    };
    var dayLoading = false;
    var loadDay = function (key) {
      if (dayLoading || !key) return;
      var section = document.getElementById('today');
      var body = section && section.querySelector('.day-body');
      if (!body) return;
      dayLoading = true;
      body.classList.add('loading');
      var spin = body.querySelector('.day-stepper-spin');
      if (spin) spin.hidden = false;
      fetch('/api/account/' + encodeURIComponent(reportUid) + '/day/' + key)
        .then(function (r) { return r.json(); })
        .then(function (d) {
          if (d.error) throw new Error(d.error);
          body.outerHTML = d.html;
          ['dayTabCount', 'dayHeadCount'].forEach(function (id) {
            var el = document.getElementById(id);
            if (el) el.textContent = d.done + '/' + d.total;
          });
          var pill = document.getElementById('dayPill');
          if (pill) {
            var cls = d.total === 0 ? 'zero'
              : d.done === d.total ? 'full' : d.done === 0 ? 'none' : 'partial';
            pill.className = 'today-pill today-' + cls;
            pill.textContent = d.total === 0
              ? 'No habits scheduled ' + (d.isToday ? 'today' : 'that day')
              : (d.isToday ? 'Today: ' : d.dayKey + ': ') + d.done + '/' + d.total + ' done';
          }
          // Keep the address bar honest, so a reload or a shared link opens
          // the day being looked at instead of jumping back to today.
          var url = new URL(window.location.href);
          if (d.isToday) url.searchParams.delete('day');
          else url.searchParams.set('day', d.dayKey);
          window.history.replaceState({}, '', url);
        })
        .catch(function (e) {
          body.classList.remove('loading');
          var s2 = body.querySelector('.day-stepper-spin');
          if (s2) { s2.hidden = false; s2.textContent = 'could not load: ' + e.message; }
        })
        .then(function () { dayLoading = false; });
    };

    // Delegated, because loadDay replaces the stepper along with the rest of
    // the card: a handler bound to the buttons themselves would work exactly
    // once.
    document.addEventListener('click', function (e) {
      var open = e.target.closest && e.target.closest('[data-open-day]');
      if (open) {
        setActiveTab('today');
        loadDay(open.getAttribute('data-open-day'));
        window.scrollTo({ top: 0, behavior: 'smooth' });
        return;
      }
      var btn = e.target.closest && e.target.closest('.day-stepper [data-step]');
      if (!btn || btn.disabled) return;
      var stepper = btn.closest('.day-stepper');
      var step = btn.getAttribute('data-step');
      loadDay(step === 'today'
        ? stepper.getAttribute('data-today')
        : shiftDay(stepper.getAttribute('data-day'), Number(step)));
    });
    document.addEventListener('change', function (e) {
      if (e.target && e.target.id === 'dayPick') loadDay(e.target.value);
    });
    // Arrow keys, for walking a month back without aiming at a button. Skipped
    // while typing in the search box, which owns those keys itself.
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      var tag = (e.target.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea' || tag === 'select') return;
      var stepper = document.querySelector('#today.tab-active .day-stepper');
      if (!stepper) return;
      var next = shiftDay(stepper.getAttribute('data-day'), e.key === 'ArrowLeft' ? -1 : 1);
      var today = stepper.getAttribute('data-today');
      if (today && next > today) return;
      e.preventDefault();
      loadDay(next);
    });
  }
})();
`;

// Wraps a report's {title, nav, header, body} into a full HTML document.
// `backHref`, when given (server.js's live view, never lookup_user.js's
// standalone file), adds a small "back to search" link up top.
function pageShell({ title, nav, header, stats, body, backHref, uid }) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<!-- Without this the browser lays the page out at a virtual desktop width
     and scales the result down, so the task board's auto-fit grid never
     collapses: four columns just get narrower and the text turns to grey
     mush. With it, the columns actually stack on a narrow window. -->
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- Inter and JetBrains Mono, with the platform's own faces listed behind
     them in --sans and --mono. This tool is opened on a laptop that is
     sometimes offline, so display=swap plus a full fallback stack means a
     failed fetch costs the page its typeface and nothing else. -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>GrowDaily — ${escapeHtml(title)}</title>
<style>${BASE_STYLES}</style>
</head>
<body${uid ? ` data-uid="${escapeHtml(uid)}"` : ''}>
  <div class="topbar">
    ${backHref ? `<a class="back-link" href="${escapeHtml(backHref)}">← Dashboard</a>` : ''}
    ${header}
    <div class="toolbar-row">
      <input id="search" type="search" placeholder="Search everything on this page…">
      <button class="btn" id="expandAll">Expand all</button>
      <button class="btn" id="collapseAll">Collapse all</button>
    </div>
    <div class="toc-wrap"><nav class="toc">${nav}</nav></div>
  </div>

  ${stats || ''}

  ${body}

  <p class="generated">Generated ${new Date().toLocaleString()}</p>

<script>${REPORT_SCRIPT}</script>
</body>
</html>`;
}

module.exports = {
  REPORT_SCRIPT,
  KNOWN_LABELS,
  HIGHLIGHT_FIELDS,
  CATEGORY_META,
  MOOD_META,
  QUADRANT_META,
  escapeHtml,
  safeCssColor,
  fmtDate,
  toJsDate,
  effectiveTodayParts,
  calendarTodayParts,
  triageTasks,
  triageTasksForDay,
  earliestReminder,
  habitScheduledOnParts,
  dayKeyParts,
  dayHeatLevel,
  renderCalendarSection,
  SQUARE_META,
  GREEN_SQUARES,
  squareOf,
  fmtMinutes,
  readUndoneReceipts,
  readHabitDay,
  habitIdsTouchedOn,
  summarizeHabitDay,
  ledgerTag,
  renderDayTally,
  renderRecordLedger,
  LEDGER_LEGEND,
  habitLabel,
  dayWriteContext,
  DAY_CUTOFF_HOUR,
  renderUndoneSection,
  renderValue,
  renderFieldTable,
  renderHabitDetail,
  renderTaskDetail,
  renderDailyDetail,
  renderDocDetail,
  renderTodayCard,
  renderDayCard,
  QUADRANT_ORDER,
  buildHabitContext,
  summarizeDoc,
  renderDocList,
  renderHighlights,
  buildReportBody,
  BASE_STYLES,
  pageShell,
};
