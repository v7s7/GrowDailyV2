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
  great: { emoji: '😄', label: 'Great', color: 'var(--success)' },
  good: { emoji: '🙂', label: 'Good', color: '#5DADEC' },
  neutral: { emoji: '😐', label: 'Neutral', color: '#F7C948' },
  sad: { emoji: '😔', label: 'Sad', color: '#FF8A4C' },
  exhausted: { emoji: '😩', label: 'Exhausted', color: '#FF5A52' },
};

const QUADRANT_META = {
  doFirst: { label: 'Do First', subtitle: 'Urgent · Important', color: '#FF5A52' },
  schedule: { label: 'Schedule', subtitle: 'Important, not urgent', color: '#5DADEC' },
  delegate: { label: 'Delegate', subtitle: 'Urgent, not important', color: '#FF8A4C' },
  eliminate: { label: 'Eliminate', subtitle: 'Neither', color: '#97a099' },
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
const DAY_CUTOFF_HOUR = 6;

// Same computation as DateTime.now().effectiveDay, ported to plain JS -
// see datetime_ext.dart's own doc comment for the full reasoning. Returns
// the account's own "effective today" as {year, month, day, weekday, key},
// where weekday is 1=Monday..7=Sunday (Dart's DateTime.weekday convention,
// not JS's 0=Sunday..6=Saturday - see the conversion below) so it can be
// compared directly against HabitModel.scheduledWeekdays' own stored ints.
//
// [tzOffsetMinutes] is this account's last-known device UTC offset (mirrored
// by main.dart's _syncAmbientAccountFacts to users/{uid}.tzOffsetMinutes -
// see that function's doc comment). A device that has never reported one
// (an old install, or a Firestore-only account with no matching Auth
// session) falls back to this machine's own local timezone - a reasonable
// guess for a single-admin local tool, and never worse than assuming UTC.
function effectiveTodayParts(tzOffsetMinutes) {
  const now = new Date();
  const localMs = typeof tzOffsetMinutes === 'number'
    ? now.getTime() + tzOffsetMinutes * 60000
    : now.getTime() - now.getTimezoneOffset() * 60000;
  const shifted = new Date(localMs - DAY_CUTOFF_HOUR * 3600000);
  // `shifted`'s ms value was built to represent local wall-clock time, so
  // reading it back with the UTC getters (not the local ones) gives the
  // right calendar date regardless of what timezone this Node process
  // itself happens to be running in.
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
// effectiveTodayParts above shifts by the 6 AM habit cutoff, and using it for
// tasks was a real bug in this tool: matrix_screen.dart is explicit that a
// todo board runs on the calendar day, not the flex window ("at 12 AM the
// phone says a new day, and the board should agree ... This was effectiveDay
// once, which left the board looking stuck on yesterday until 6 in the
// morning"). Between midnight and 6 AM this page was therefore showing a
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
function renderCalendarSection(dailyDocs, habitDocs, habitCtx, todayKey) {
  const byKey = new Map();
  for (const doc of dailyDocs) byKey.set(doc.id, doc.data());

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
    const cells = [];
    for (let i = 0; i < leadBlanks; i++) cells.push('<div class="cal-cell cal-empty"></div>');
    for (let day = 1; day <= daysInMonth; day++) {
      const key = `${yy}-${String(mm).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
      const data = byKey.get(key);
      let done = 0;
      let scheduled = 0;
      let moodMeta = null;
      if (data) {
        const completions = data.habitCompletions && typeof data.habitCompletions === 'object'
          ? data.habitCompletions : {};
        done = Object.values(completions).filter((c) => Number(c) > 0).length;
        scheduled = habitDocs.filter((h) => habitScheduledOnParts(h.data(), dayKeyParts(key))).length;
        moodMeta = data.mood ? MOOD_META[data.mood] : null;
        if (done > 0) { monthActiveDays += 1; monthCompletions += done; }
      }
      const level = dayHeatLevel(done, scheduled);
      const isToday = key === todayKey;
      if (data) {
        detailPanels.push(`<div class="day-detail" data-date="${key}" hidden>
          <div class="day-detail-head">
            <strong>${escapeHtml(fmtDate(new Date(Date.UTC(yy, mm - 1, day))) || key)}</strong>
            <span class="muted">${key}</span>
          </div>
          ${renderDailyDetail(key, data, { habitCtx })}
        </div>`);
      }
      cells.push(`
        <button type="button" class="cal-cell cal-day level-${level}${isToday ? ' today' : ''}"
          data-date="${key}"${data ? '' : ' disabled'}>
          <span class="cal-day-num">${day}</span>
          ${moodMeta ? `<span class="cal-mood">${moodMeta.emoji}</span>` : ''}
          ${scheduled > 0 ? `<span class="cal-ratio">${done}/${scheduled}</span>` : ''}
        </button>
      `);
    }

    return `
      <div class="cal-month">
        <div class="cal-month-head">
          <h4>${MONTH_NAMES[mm - 1]} ${yy}</h4>
          <span class="muted">${monthActiveDays} active day${monthActiveDays === 1 ? '' : 's'} &middot; ${monthCompletions} habit${monthCompletions === 1 ? '' : 's'} completed</span>
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
  return escapeHtml(String(value));
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
function renderDailyDetail(id, data, ctx) {
  const habitCtx = (ctx && ctx.habitCtx) || {};
  const mood = data.mood ? MOOD_META[data.mood] : null;
  const completions = data.habitCompletions && typeof data.habitCompletions === 'object'
    ? Object.entries(data.habitCompletions)
    : [];

  const habitRows = completions.length
    ? '<div class="stack">' + completions.map(([habitId, count]) => {
        const name = habitCtx[habitId]?.name || habitId;
        const done = Number(count) > 0;
        return `<div class="stack-item">${done ? '✅' : '⬜'} ${escapeHtml(name)}${done ? ` — done ×${escapeHtml(String(count))}` : ' — not done'}</div>`;
      }).join('') + '</div>'
    : '<span class="muted">No habit activity logged.</span>';

  const rows = [
    mood ? detailRow('Mood', `${mood.emoji} ${escapeHtml(mood.label)}`) : '',
    data.dailyReflection
      ? detailRow('Reflection', `<span class="prose">${escapeHtml(data.dailyReflection)}</span>`)
      : '',
    detailRow('Night review', data.nightReviewDone ? '<span class="bool true">✓ Done</span>' : '<span class="muted">Not done</span>'),
    detailRow('Earned', `+${data.totalXpEarned ?? 0} XP · +${data.totalGoldEarned ?? 0} gold`),
  ].join('');

  return `
    <div class="detail-rows">${rows}</div>
    <h3>Habits that day</h3>
    ${habitRows}
  `;
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
      const n = data.habitCompletions ? Object.keys(data.habitCompletions).length : 0;
      const bits = [`${n} habit${n === 1 ? '' : 's'} completed`];
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
  taskDayKey, xp, gold, hasDoc, todayKey,
}) {
  const total = habitRows.length;
  const done = habitRows.filter((h) => h.done).length;
  const pctClass = total === 0 ? 'zero' : done === total ? 'full' : done === 0 ? 'none' : 'partial';

  const habitsHtml = total === 0
    ? `<p class="muted">No habits were scheduled ${isToday ? 'today' : 'that day'}.</p>`
    : '<div class="today-habits">' + habitRows.map((h) => `
        <div class="today-habit${h.done ? ' done' : ''}">
          <span>${h.done ? '✅' : '⬜'}</span>
          <span>${h.emoji}</span>
          <span class="today-habit-name">${escapeHtml(h.name)}</span>
          ${h.count > 1 ? `<span class="today-habit-count">×${h.count}</span>` : ''}
        </div>
      `).join('') + '</div>';

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
  :root {
    --bg: #faf9f5;
    --surface: #ffffff;
    --border: #e5dfd0;
    --text: #1c2620;
    --text-sec: #66716a;
    --text-tert: #97a099;
    --accent: #b9822a;
    --accent-soft: rgba(228, 180, 95, 0.18);
    --success: #1f9d6c;
    --danger: #c23b34;
    --danger-soft: rgba(255, 90, 82, 0.13);
    --info: #2f6f9f;
    --info-soft: rgba(93, 173, 236, 0.14);

    /* One spacing ladder instead of a different hand-picked pixel value per
       rule. Everything below steps through these, so the page reads as one
       grid rather than as forty independent decisions. */
    --s1: 4px; --s2: 6px; --s3: 8px; --s4: 12px; --s5: 16px; --s6: 22px; --s7: 32px;
    --r-sm: 7px; --r-md: 10px; --r-lg: 14px; --r-pill: 100px;

    /* Borders do the separating almost everywhere; shadow is reserved for
       things that genuinely float above the page (the drawer, the sticky
       bar once it has content scrolling under it). */
    --shadow-sm: 0 1px 2px rgba(28, 38, 32, 0.05);
    --shadow-lg: 0 8px 40px rgba(28, 38, 32, 0.16);
    --mono: ui-monospace, SFMono-Regular, Menlo, monospace;
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
  /* ---- The task board: four states, side by side, so "what is late" and
     "what is coming" are answered by looking rather than by scrolling. Grid
     with auto-fit so it collapses to two columns on a narrow window and one
     on a phone, without a media query to keep in sync. ---- */
  .tboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 10px; margin-top: 6px; }
  .tcol { border: 1px solid var(--border); border-radius: 10px; background: var(--surface); overflow: hidden; display: flex; flex-direction: column; }
  .tcol-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 11px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 1px solid var(--border); }
  .tcol-head b { font-size: 13px; font-variant-numeric: tabular-nums; }
  .tcol-body { padding: 6px; display: flex; flex-direction: column; gap: 3px; }
  /* Tone carries the state. Late is the only one that gets a warm alarm
     colour; the others stay quiet, because four shouting columns is the same
     as none shouting. */
  .tone-late .tcol-head { background: rgba(255,90,82,0.10); color: #c23b34; }
  .tone-today .tcol-head { background: var(--accent-soft); color: var(--accent); }
  .tone-upcoming .tcol-head { background: rgba(93,173,236,0.12); color: #2f6f9f; }
  .tone-done .tcol-head { background: rgba(46,207,143,0.12); color: #1c7a55; }
  .tk { display: flex; align-items: center; gap: 7px; padding: 5px 7px; border-radius: 7px; font-size: 12.5px; line-height: 1.3; }
  .tk:hover { background: var(--bg); }
  .tk-dot { width: 7px; height: 7px; border-radius: 50%; flex: 0 0 auto; }
  .tk-title { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tk-when { flex: 0 0 auto; font-size: 10.5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .tone-done .tk-title { color: var(--text-sec); text-decoration: line-through; text-decoration-color: var(--border); }
  .tk-empty { padding: 10px 7px; font-size: 12px; color: var(--text-tert); }
  .tk-more { padding: 4px 7px; font-size: 11px; color: var(--text-tert); }
  .h3-note { text-transform: none; letter-spacing: 0; font-weight: 400; color: var(--text-tert); font-size: 11px; margin-inline-start: 6px; }
  body { font-family: -apple-system, "SF Pro Text", Helvetica, Arial, sans-serif; max-width: 1000px; margin: 0 auto; padding: 0 var(--s5) 60px; color: var(--text); background: var(--bg); }
  a { color: var(--accent); }
  h1 { font-size: 22px; margin: 20px 0 2px; letter-spacing: -0.2px; }
  h2 { font-size: 15px; margin-top: 0; border-bottom: 1px solid var(--border); padding-bottom: var(--s3); margin-bottom: var(--s4); letter-spacing: -0.1px; }
  h3 { font-size: 11.5px; color: var(--text-sec); margin: var(--s5) 0 var(--s1); text-transform: uppercase; letter-spacing: 0.5px; }
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
  input[type="text"], input[type="search"] { flex: 1; min-width: 160px; padding: var(--s3) var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); font-size: 13.5px; background: var(--surface); color: var(--text); font-family: inherit; }
  input[type="text"]:focus, input[type="search"]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .btn { padding: var(--s3) var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); font-size: 12.5px; background: var(--surface); cursor: pointer; color: var(--text); font-family: inherit; }
  .btn:hover { background: var(--accent-soft); border-color: var(--accent); }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: white; font-weight: 600; }
  .btn.primary:hover { opacity: 0.92; }

  /* ---- The account's numbers, as one strip ----------------------------
     Ten equal cards cost ~130px on every tab and weighted "Gold 1708" the
     same as "Theme custom". Inline pairs fit one row, and the value leads
     because the value is what is being looked up. */
  .stats { display: flex; flex-wrap: wrap; gap: var(--s1) var(--s5); align-items: baseline; padding: var(--s3) var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); margin-bottom: var(--s5); }
  .stat { display: inline-flex; align-items: baseline; gap: var(--s2); }
  .stat b { font-size: 15px; font-weight: 700; font-variant-numeric: tabular-nums; letter-spacing: -0.2px; }
  .stat span { font-size: 10.5px; color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.4px; }

  table.fields { border-collapse: collapse; width: 100%; margin: 6px 0; }
  table.fields th { text-align: left; font-weight: 600; color: var(--text-sec); padding: 5px 10px 5px 0; vertical-align: top; white-space: nowrap; width: 1%; font-size: 12.5px; }
  table.fields td { padding: 5px 0; vertical-align: top; font-size: 13px; unicode-bidi: isolate; }

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
  .pill-active, .pill-open { background: var(--accent-soft); color: #7a5a1f; }
  .pill-done { background: rgba(31,157,108,0.13); color: var(--success); }
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
  .color-dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.15); flex-shrink: 0; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 100px; color: #fff; font-size: 10px; font-weight: 700; letter-spacing: 0.4px; text-transform: uppercase; }
  details.nested.raw { display: block; margin-top: 10px; }
  details.nested.raw > summary { font-size: 11px; color: var(--text-tert); }

  details.nested { display: inline-block; }
  details.nested > summary { cursor: pointer; color: var(--text-sec); font-size: 12px; list-style: none; }
  details.nested > summary::-webkit-details-marker { display: none; }
  details.nested > summary::before { content: '▸ '; }

  .chips { display: flex; flex-wrap: wrap; gap: 5px; }
  .chip { display: inline-block; padding: 2px 9px; border-radius: 100px; background: var(--accent-soft); color: #7a5a1f; font-size: 12px; unicode-bidi: isolate; }
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
  nav.toc { display: flex; gap: var(--s2); margin-top: var(--s3); overflow-x: auto; scrollbar-width: thin; padding-bottom: var(--s1); }
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
  .toc-wrap::after { content: ''; position: absolute; inset-block: 0; inset-inline-end: 0; width: 34px; background: linear-gradient(to left, var(--bg), transparent); pointer-events: none; }
  html[dir="rtl"] .toc-wrap::after { background: linear-gradient(to right, var(--bg), transparent); }
  .tab-btn { padding: 7px 13px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; font-weight: 600; color: var(--text-sec); cursor: pointer; }
  .tab-btn:hover { border-color: var(--accent); color: var(--accent); }
  .tab-btn.active { background: var(--accent); border-color: var(--accent); color: #fff; }
  .tab-btn .tab-count { opacity: 0.75; font-weight: 500; }
  section[id] { display: none; }
  section[id].tab-active { display: block; }
  /* A non-empty search overrides tabs entirely - every section becomes
     visible so results outside the current tab are never silently
     missed (see REPORT_SCRIPT's applyFilters). */
  body.searching section[id] { display: block !important; }
  body.searching .tab-btn { opacity: 0.5; pointer-events: none; }

  /* Today pill (header) + Today hero card (first tab) - see
     renderTodayCard/buildReportBody. Answers "did this account do their
     habits today" at a glance, using the app's own scheduling rule
     (habitScheduledOnParts), not a raw habit count. */
  .today-pill { display: inline-block; padding: 4px 12px; border-radius: 100px; font-size: 12px; font-weight: 700; margin: 8px 0 2px; }
  .today-pill.today-full { background: rgba(31,157,108,0.14); color: var(--success); }
  .today-pill.today-partial { background: var(--accent-soft); color: #7a5a1f; }
  .today-pill.today-none { background: rgba(255,90,82,0.14); color: #c23b34; }
  .today-pill.today-zero { background: var(--bg); color: var(--text-tert); border: 1px solid var(--border); }

  .today-hero { border: 1px solid var(--border); border-radius: 14px; padding: 16px; margin-bottom: 4px; background: var(--surface); }
  .today-hero-top { display: flex; align-items: center; gap: 14px; margin-bottom: 14px; }
  .today-ring { width: 54px; height: 54px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px; border: 3px solid var(--border); flex-shrink: 0; }
  .today-ring.today-full { border-color: var(--success); color: var(--success); }
  .today-ring.today-partial { border-color: var(--accent); color: var(--accent); }
  .today-ring.today-none { border-color: #e0847a; color: #c23b34; }
  .today-ring.today-zero { border-color: var(--border); color: var(--text-tert); }
  .today-hero-title { font-weight: 700; font-size: 15px; }
  .today-hero-date { color: var(--text-sec); font-size: 12px; margin-top: 1px; }
  .today-habits { display: flex; flex-direction: column; gap: 4px; }
  .today-habit { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-radius: 8px; font-size: 13px; }
  .today-habit.done { background: var(--accent-soft); }
  .today-habit-name { flex: 1; unicode-bidi: isolate; }
  .today-habit-count { color: var(--text-tert); font-size: 11.5px; }
  .today-rooms { display: flex; flex-direction: column; gap: 4px; }
  .today-room { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border: 1px solid var(--border); border-radius: 8px; font-size: 13px; }
  .today-room.done { border-color: var(--success); }
  .today-room-name { unicode-bidi: isolate; }
  .today-tag { display: inline-block; background: var(--accent); color: #fff; font-size: 9.5px; font-weight: 700; letter-spacing: 0.3px; text-transform: uppercase; padding: 1px 7px; border-radius: 100px; margin-inline-end: 6px; vertical-align: 1px; }

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
  .legend-swatch.level-1 { background: #cdeadd; }
  .legend-swatch.level-2 { background: #8fd2ac; }
  .legend-swatch.level-3 { background: #4cb886; }
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
  .cal-day.level-1 { background: #cdeadd; }
  .cal-day.level-2 { background: #8fd2ac; }
  .cal-day.level-3 { background: #4cb886; }
  .cal-day.level-4 { background: var(--success); }
  .cal-day.level-3 .cal-day-num, .cal-day.level-4 .cal-day-num { color: #fff; }
  .cal-day.level-3 .cal-ratio, .cal-day.level-4 .cal-ratio { color: rgba(255,255,255,0.85); }
  .cal-day-num { font-size: 11.5px; font-weight: 700; }
  .cal-mood { position: absolute; top: 2px; inset-inline-end: 2px; font-size: 9px; }
  .cal-ratio { font-size: 8.5px; color: var(--text-tert); }

  /* Per-section status chips (Active/Archived, Open/Done - see
     SECTION_FILTERS/renderFilterChips). Deliberately not reusing .chip -
     that one's the read-only array-value pill style used inside table
     cells, this needs a clickable/active look instead. */
  .filter-chips { display: flex; flex-wrap: wrap; gap: 6px; margin: -4px 0 14px; }
  .filter-chip { padding: 5px 12px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; color: var(--text-sec); cursor: pointer; }
  .filter-chip:hover { border-color: var(--accent); color: var(--accent); }
  .filter-chip.active { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }

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
  .live-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(132px, 1fr)); gap: 9px; margin-bottom: 14px; }
  .live-card { border: 1px solid var(--border); border-radius: 12px; padding: 11px 13px; background: var(--surface); }
  .live-card.hot { border-color: var(--success); background: rgba(31,157,108,0.06); }
  .live-value { font-size: 24px; font-weight: 700; letter-spacing: -0.5px; font-variant-numeric: tabular-nums; display: flex; align-items: center; gap: 7px; }
  .live-label { font-size: 10.5px; color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.4px; margin-top: 2px; }
  .live-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--success); box-shadow: 0 0 0 0 rgba(31,157,108,0.55); animation: livepulse 2s infinite; flex: 0 0 auto; }
  @keyframes livepulse { 70% { box-shadow: 0 0 0 9px rgba(31,157,108,0); } 100% { box-shadow: 0 0 0 0 rgba(31,157,108,0); } }
  @media (prefers-reduced-motion: reduce) { .live-dot { animation: none; } }

  /* ---- Dashboard: activity feed --------------------------------------- */
  /* Not overflow:hidden. That made .feed the sticky containing block for
     .feed-day below, and since it never scrolls, the day headers silently
     never pinned. Clipping the first and last rows' corners gets the same
     rounded card without trapping them. */
  .feed { border: 1px solid var(--border); border-radius: 12px; background: var(--surface); }
  .feed > :first-child { border-start-start-radius: 11px; border-start-end-radius: 11px; }
  .feed > :last-child { border-end-start-radius: 11px; border-end-end-radius: 11px; border-bottom: none; }
  .feed-day { padding: 7px 14px; background: var(--bg); border-bottom: 1px solid var(--border); font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; color: var(--text-sec); position: sticky; top: 0; z-index: 2; }
  .feed-day + .ev { border-start-start-radius: 0; border-start-end-radius: 0; }
  .ev { display: flex; align-items: flex-start; gap: 10px; padding: 9px 14px; border-bottom: 1px solid var(--border); cursor: pointer; }
  .ev:last-child { border-bottom: none; }
  .ev:hover { background: var(--accent-soft); }
  .ev-ico { width: 26px; height: 26px; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 13px; flex: 0 0 auto; background: var(--bg); border: 1px solid var(--border); }
  .ev-main { flex: 1 1 auto; min-width: 0; }
  .ev-who { font-weight: 700; font-size: 13px; unicode-bidi: isolate; }
  .ev-who .ev-mail { font-weight: 400; color: var(--text-tert); font-size: 11.5px; margin-inline-start: 6px; unicode-bidi: isolate; }
  .ev-what { font-size: 12.5px; color: var(--text-sec); margin-top: 1px; unicode-bidi: isolate; }
  .ev-what .ev-sub { color: var(--text-tert); }
  /* A run of user-written text (a name, a habit, a task title) that may be
     Arabic, sitting inside a left-to-right row. Without isolating each run
     on its own, an Arabic display name and the Latin email beside it get
     reordered into each other. */
  .bidi { unicode-bidi: isolate; }
  .ev-when { flex: 0 0 auto; font-size: 11px; color: var(--text-tert); font-variant-numeric: tabular-nums; white-space: nowrap; padding-top: 2px; }
  .ev-live { color: var(--success); font-weight: 700; }

  /* ---- Dashboard: view tabs + shared toolbar --------------------------- */
  .view-tabs { display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap; }
  .view-tab { padding: 8px 15px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12.5px; font-weight: 600; color: var(--text-sec); cursor: pointer; }
  .view-tab:hover { border-color: var(--accent); color: var(--accent); }
  .view-tab.active { background: var(--accent); border-color: var(--accent); color: #fff; }
  .view-tab .vt-count { opacity: 0.75; font-weight: 500; margin-inline-start: 3px; }

  /* Today column in the accounts table: the same ring language the report
     uses, shrunk to a table cell so a whole roster reads at a glance. */
  .mini-ring { display: inline-flex; align-items: center; justify-content: center; min-width: 42px; padding: 2px 8px; border-radius: 100px; font-size: 11.5px; font-weight: 700; border: 1.5px solid var(--border); color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .mini-ring.today-full { border-color: var(--success); color: var(--success); background: rgba(31,157,108,0.10); }
  .mini-ring.today-partial { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }
  .mini-ring.today-none { border-color: #e0847a; color: #c23b34; }
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
