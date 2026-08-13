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
  const swatch = data.iconColorHex
    ? `<span class="color-dot" style="background:${escapeHtml(String(data.iconColorHex))}"></span>`
    : '';

  const rows = [
    detailRow('Category', `${cat.emoji} ${escapeHtml(cat.label)}`),
    detailRow('Frequency', escapeHtml(freq) + (days ? ` <span class="muted">(${escapeHtml(days)})</span>` : '')),
    detailRow('Goal', escapeHtml(goal)),
    data.cueAfter ? detailRow('Cue', `After ${escapeHtml(data.cueAfter)}`) : '',
    data.hasTimer ? detailRow('Timer', `${Math.round((data.timerDurationSeconds || 0) / 60)} min`) : '',
    detailRow('Rewards', `+${data.xpReward ?? 0} XP · +${data.goldReward ?? 0} gold per completion`),
    detailRow('Created', fmtDate(data.createdAt) || '<span class="muted">—</span>'),
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
    detailRow('Created', fmtDate(data.createdAt, true) || '<span class="muted">—</span>'),
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
    data.dailyReflection ? detailRow('Reflection', escapeHtml(data.dailyReflection)) : '',
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
    return `
      <details class="doc"${status ? ` data-status="${escapeHtml(status)}"` : ''}>
        <summary>${isToday ? '<span class="today-tag">Today</span> ' : ''}${escapeHtml(summarizeDoc(id, doc.id, data))}</summary>
        <div class="doc-id">${escapeHtml(doc.id)}</div>
        <div class="detail-card">
          ${renderDocDetail(id, doc.id, data, ctx)}
          ${curated ? `<details class="nested raw"><summary>All raw fields</summary>${renderFieldTable(data)}</details>` : ''}
        </div>
      </details>
    `;
  }).join('');
  return { id, label, count, html };
}

function renderHighlights(profileData) {
  if (!profileData) return '';
  const cards = HIGHLIGHT_FIELDS
    .filter(([key]) => profileData[key] !== undefined && profileData[key] !== null)
    .map(([key, label]) => {
      const raw = profileData[key];
      const display = typeof raw === 'boolean' ? (raw ? 'Yes' : 'No') : escapeHtml(String(raw));
      return `<div class="stat"><div class="stat-value">${display}</div><div class="stat-label">${escapeHtml(label)}</div></div>`;
    }).join('');
  return cards ? `<div class="stats">${cards}</div>` : '';
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

// The account's own "did they do their habits today" view - fetchAccount.js
// builds this account's real answer using habitScheduledOnParts (the exact
// scheduling rule the app itself uses) rather than a raw count of every
// habit that exists, so a habit that isn't due today (wrong weekday, not
// created yet, already archived) never counts against them here. This is
// the FIRST tab in the report (see buildReportBody) precisely so an admin
// opening any account lands on "what's true today" before anything else.
function renderTodayCard({
  todayKey, habitRows, mood, nightReviewDone, reflection, tasksToday, openTasks, rooms,
}) {
  const total = habitRows.length;
  const done = habitRows.filter((h) => h.done).length;
  const pctClass = total === 0 ? 'zero' : done === total ? 'full' : done === 0 ? 'none' : 'partial';

  const habitsHtml = total === 0
    ? '<p class="muted">No habits scheduled today.</p>'
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
      : '<span class="muted">Not done yet</span>'),
    reflection ? detailRow('Reflection', escapeHtml(reflection)) : '',
  ].join('');

  const tasksHtml = tasksToday.length
    ? '<div class="stack">' + tasksToday.map((t) =>
        `<div class="stack-item">✅ ${escapeHtml(t.title || '(untitled task)')}</div>`
      ).join('') + '</div>'
    : '<p class="muted">No tasks completed today yet.</p>';

  const openHtml = openTasks.length
    ? '<div class="stack">' + openTasks.slice(0, 8).map((t) => {
        const q = QUADRANT_META[t.quadrant];
        return `<div class="stack-item">☐ ${escapeHtml(t.title || '(untitled task)')}${q ? ` <span class="badge" style="background:${q.color}">${escapeHtml(q.label)}</span>` : ''}</div>`;
      }).join('') + (openTasks.length > 8 ? `<div class="muted" style="margin-top:6px;">+${openTasks.length - 8} more open</div>` : '') + '</div>'
    : '<p class="muted">Nothing open. 🎉</p>';

  const roomsHtml = rooms.length
    ? '<div class="today-rooms">' + rooms.map((r) => `
        <div class="today-room${r.allDone ? ' done' : ''}">
          <span>${r.allDone ? '✅' : '⬜'}</span>
          <span class="today-room-name">${escapeHtml(r.name)}</span>
          ${r.muted ? '<span class="muted" style="margin-inline-start:auto;">muted</span>' : ''}
        </div>
      `).join('') + '</div>'
    : '<p class="muted">Not in any rooms.</p>';

  const title = total === 0
    ? 'No habits scheduled today'
    : done === total
      ? 'All done for today'
      : `${done} of ${total} habit${total === 1 ? '' : 's'} done today`;

  return `
    <div class="today-hero">
      <div class="today-hero-top">
        <div class="today-ring today-${pctClass}">${total === 0 ? '—' : `${done}/${total}`}</div>
        <div>
          <div class="today-hero-title">${escapeHtml(title)}</div>
          <div class="today-hero-date">${escapeHtml(todayKey)}</div>
        </div>
      </div>
      ${habitsHtml}
    </div>
    <h3>Mood &amp; reflection</h3>
    <div class="detail-rows">${rows}</div>
    <h3>Tasks completed today</h3>
    ${tasksHtml}
    <h3>Still open</h3>
    ${openHtml}
    <h3>Rooms</h3>
    ${roomsHtml}
  `;
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
function buildReportBody({ uid, authRecord, profileData, sections, todaySummary }) {
  const title = authRecord?.email || profileData?.displayName || uid;
  const nav = sections.map((s) =>
    `<button type="button" class="tab-btn" data-target="${escapeHtml(s.id)}">${escapeHtml(s.label)}${s.count !== undefined ? ` <span class="tab-count">${s.count}</span>` : ''}</button>`
  ).join('');
  const sectionsHtml = sections.map((s) => `
    <section id="${escapeHtml(s.id)}">
      <h2>${escapeHtml(s.label)}${s.count !== undefined ? ` <span class="count">${s.count}</span>` : ''}</h2>
      ${renderFilterChips(s.id)}
      ${s.html}
    </section>
  `).join('\n');
  // A same-glance answer to "did they do their habits today" right under
  // the name/email, so an admin never has to click into the Today tab just
  // to see the headline number - the tab is still there for the full
  // breakdown (mood, tasks, rooms).
  const pillClass = !todaySummary || todaySummary.total === 0
    ? 'zero'
    : todaySummary.done === todaySummary.total
      ? 'full'
      : todaySummary.done === 0 ? 'none' : 'partial';
  const pillText = !todaySummary || todaySummary.total === 0
    ? 'No habits scheduled today'
    : `Today: ${todaySummary.done}/${todaySummary.total} done`;
  const header = `
    <h1>${escapeHtml(title)}</h1>
    <div class="subtitle">
      ${authRecord?.email ? escapeHtml(authRecord.email) + ' · ' : ''}<span class="uid">${escapeHtml(uid)}</span>
    </div>
    <div class="today-pill today-${pillClass}">${escapeHtml(pillText)}</div>
    ${renderHighlights(profileData)}
  `;
  return { title, nav, header, body: sectionsHtml };
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
  }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, "SF Pro Text", Helvetica, Arial, sans-serif; max-width: 960px; margin: 0 auto; padding: 0 20px 60px; color: var(--text); background: var(--bg); }
  a { color: var(--accent); }
  h1 { font-size: 22px; margin: 20px 0 2px; letter-spacing: -0.2px; }
  h2 { font-size: 15px; margin-top: 0; border-bottom: 1px solid var(--border); padding-bottom: 8px; margin-bottom: 10px; letter-spacing: -0.1px; }
  h3 { font-size: 11.5px; color: var(--text-sec); margin: 12px 0 4px; text-transform: uppercase; letter-spacing: 0.5px; }
  section { margin-top: 28px; }
  .subtitle { color: var(--text-sec); font-size: 13px; margin-bottom: 16px; }
  .subtitle .uid { font-family: ui-monospace, Menlo, monospace; }
  .count { font-weight: normal; color: var(--text-tert); font-size: 12.5px; }
  .muted { color: var(--text-tert); font-style: italic; }
  .back-link { display: inline-block; font-size: 12.5px; color: var(--text-sec); text-decoration: none; margin: 14px 0 -4px; }
  .back-link:hover { color: var(--accent); }

  /* Sticky toolbar: search + expand/collapse + jump nav, always reachable */
  .topbar { position: sticky; top: 0; background: var(--bg); padding: 14px 0 10px; border-bottom: 1px solid var(--border); z-index: 10; margin-bottom: 4px; }
  .toolbar-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  input[type="text"], input[type="search"] { flex: 1; min-width: 160px; padding: 9px 13px; border: 1px solid var(--border); border-radius: 9px; font-size: 13.5px; background: var(--surface); color: var(--text); }
  input[type="text"]:focus, input[type="search"]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .btn { padding: 9px 13px; border: 1px solid var(--border); border-radius: 9px; font-size: 12.5px; background: var(--surface); cursor: pointer; color: var(--text); }
  .btn:hover { background: var(--accent-soft); border-color: var(--accent); }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: white; font-weight: 600; }
  .btn.primary:hover { opacity: 0.92; }

  /* Header stat cards - the "glance at this first" numbers */
  .stats { display: grid; grid-template-columns: repeat(auto-fill, minmax(96px, 1fr)); gap: 8px; margin: 14px 0 6px; }
  .stat { border: 1px solid var(--border); border-radius: 10px; padding: 10px 12px; background: var(--surface); }
  .stat-value { font-size: 18px; font-weight: 700; color: var(--text); }
  .stat-label { font-size: 10.5px; color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.4px; margin-top: 2px; }

  table.fields { border-collapse: collapse; width: 100%; margin: 6px 0; }
  table.fields th { text-align: left; font-weight: 600; color: var(--text-sec); padding: 5px 10px 5px 0; vertical-align: top; white-space: nowrap; width: 1%; font-size: 12.5px; }
  table.fields td { padding: 5px 0; vertical-align: top; font-size: 13px; unicode-bidi: plaintext; }

  details.doc { border: 1px solid var(--border); border-radius: 9px; margin: 8px 0; background: var(--surface); overflow: hidden; }
  details.doc > summary { padding: 10px 14px; cursor: pointer; font-weight: 600; font-size: 13.5px; list-style: none; unicode-bidi: plaintext; }
  details.doc > summary::-webkit-details-marker { display: none; }
  details.doc > summary::before { content: '▸'; display: inline-block; margin-inline-end: 8px; color: var(--accent); transition: transform 0.15s; }
  details.doc[open] > summary::before { transform: rotate(90deg); }
  details.doc > summary:hover { background: var(--accent-soft); }
  details.doc > .doc-id { padding: 0 14px; font-size: 10.5px; color: var(--text-tert); font-family: ui-monospace, Menlo, monospace; }
  details.doc > table.fields { padding: 0 14px 12px; margin-top: 0; }
  details.doc > .detail-card { padding: 2px 14px 12px; }
  details.doc[open] { padding-bottom: 4px; }

  /* Curated per-type detail cards (habits/tasks/daily) - see render.js's
     renderHabitDetail/renderTaskDetail/renderDailyDetail. The label/value
     row pair mirrors this app's own detail-sheet rows (e.g. TaskDetailSheet)
     rather than a raw key/value table. */
  .detail-title { font-size: 14.5px; font-weight: 700; margin: 2px 0 4px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; unicode-bidi: plaintext; }
  .detail-subtitle { font-size: 11.5px; color: var(--text-sec); margin: -2px 0 6px; }
  .detail-desc { font-size: 13px; color: var(--text-sec); margin: 2px 0 10px; unicode-bidi: plaintext; }
  .detail-rows { margin-top: 2px; }
  .detail-row { display: flex; gap: 10px; padding: 5px 0; font-size: 13px; }
  .detail-row + .detail-row { border-top: 1px solid var(--border); }
  .detail-label { color: var(--text-sec); min-width: 96px; flex-shrink: 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.3px; padding-top: 1px; }
  .detail-value { color: var(--text); flex: 1; unicode-bidi: plaintext; }
  .color-dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.15); flex-shrink: 0; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 100px; color: #fff; font-size: 10px; font-weight: 700; letter-spacing: 0.4px; text-transform: uppercase; }
  details.nested.raw { display: block; margin-top: 10px; }
  details.nested.raw > summary { font-size: 11px; color: var(--text-tert); }

  details.nested { display: inline-block; }
  details.nested > summary { cursor: pointer; color: var(--text-sec); font-size: 12px; list-style: none; }
  details.nested > summary::-webkit-details-marker { display: none; }
  details.nested > summary::before { content: '▸ '; }

  .chips { display: flex; flex-wrap: wrap; gap: 5px; }
  .chip { display: inline-block; padding: 2px 9px; border-radius: 100px; background: var(--accent-soft); color: #7a5a1f; font-size: 12px; unicode-bidi: plaintext; }
  .stack-item { border: 1px solid var(--border); border-radius: 6px; padding: 6px 8px; margin: 4px 0; }

  .bool.true { color: var(--success); font-weight: 600; }
  .bool.false { color: var(--text-tert); }

  [hidden] { display: none !important; }
  .generated { color: var(--text-tert); font-size: 11px; margin-top: 40px; }

  /* Tabs (nav.toc buttons - see buildReportBody) - only the active
     section's <section> shows at a time (see section/section.tab-active
     below), so this reads as switching between app screens instead of
     scrolling one long document. */
  nav.toc { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
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
  .today-habit-name { flex: 1; unicode-bidi: plaintext; }
  .today-habit-count { color: var(--text-tert); font-size: 11.5px; }
  .today-rooms { display: flex; flex-direction: column; gap: 4px; }
  .today-room { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border: 1px solid var(--border); border-radius: 8px; font-size: 13px; }
  .today-room.done { border-color: var(--success); }
  .today-room-name { unicode-bidi: plaintext; }
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
        dayDetailPanel.innerHTML = source.innerHTML;
        dayButtons.forEach(function (b) { b.classList.toggle('selected', b === btn); });
        dayDetailPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });
  }
})();
`;

// Wraps a report's {title, nav, header, body} into a full HTML document.
// `backHref`, when given (server.js's live view, never lookup_user.js's
// standalone file), adds a small "back to search" link up top.
function pageShell({ title, nav, header, body, backHref }) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>GrowDaily — ${escapeHtml(title)}</title>
<style>${BASE_STYLES}</style>
</head>
<body>
  ${backHref ? `<a class="back-link" href="${escapeHtml(backHref)}">← Back to search</a>` : ''}
  <div class="topbar">
    <div class="toolbar-row">
      <input id="search" type="text" placeholder="Search everything on this page…">
      <button class="btn" id="expandAll">Expand all</button>
      <button class="btn" id="collapseAll">Collapse all</button>
    </div>
    <nav class="toc">${nav}</nav>
  </div>

  ${header}

  ${body}

  <p class="generated">Generated ${new Date().toLocaleString()}</p>

<script>${REPORT_SCRIPT}</script>
</body>
</html>`;
}

module.exports = {
  KNOWN_LABELS,
  HIGHLIGHT_FIELDS,
  CATEGORY_META,
  MOOD_META,
  QUADRANT_META,
  escapeHtml,
  fmtDate,
  toJsDate,
  effectiveTodayParts,
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
  QUADRANT_ORDER,
  buildHabitContext,
  summarizeDoc,
  renderDocList,
  renderHighlights,
  buildReportBody,
  BASE_STYLES,
  pageShell,
};
