'use strict';

/**
 * Cross-account activity scan: what happened across EVERY account, newest
 * first, plus a per-account rollup of "when were they last really here and
 * what did they do".
 *
 * Why this is a fan-out and not three tidy collectionGroup queries
 * ---------------------------------------------------------------
 * The obvious version of this file is
 * `collectionGroup('daily').orderBy('lastUpdated','desc').limit(50)`, one
 * query for the whole project. Firestore refuses it: ordering a collection
 * GROUP by a field needs a COLLECTION_GROUP-scoped index for that field,
 * and this project only declares one (participants.uid, see
 * firestore.indexes.json). Every one of daily.lastUpdated,
 * milestones.occurredAt and matrix_tasks.createdAt comes back
 * FAILED_PRECONDITION.
 *
 * So this walks the accounts instead. Ordinary collection-scope queries
 * (`users/{uid}/daily` ordered by lastUpdated) ride Firestore's automatic
 * single-field indexes and need no configuration at all, which means this
 * dashboard works against the live project as it stands today, with no
 * index to deploy first and no window where the admin tool is broken
 * waiting for one to build.
 *
 * The cost is queries-per-account rather than queries-per-project, so the
 * honest question is whether that scales. Measured against the real
 * project: 103 accounts x 3 queries finished in 2.0s at concurrency 24.
 * The full scan below is 6 queries per account and lands a few seconds in,
 * cached for CACHE_TTL_MS afterward, with an explicit Refresh for when the
 * admin wants it re-read now. If this project ever grows the kind of user
 * count where that stops being true, the fix is to declare those three
 * fieldOverrides and switch the sources below to collectionGroup, not to
 * scan harder.
 *
 * Everything here is READ-ONLY. Nothing in the admin tool writes.
 */

const admin = require('firebase-admin');

const {
  toJsDate,
  effectiveTodayParts,
  habitScheduledOnParts,
  dayKeyParts,
  CATEGORY_META,
  MOOD_META,
  QUADRANT_META,
  SQUARE_META,
  summarizeHabitDay,
  readUndoneReceipts,
  habitLabel,
  fmtMinutes,
  dayWriteContext,
} = require('./render');

function db() {
  return admin.firestore();
}
function auth() {
  return admin.auth();
}

// Firestore's Node client pipelines requests over a small number of HTTP/2
// connections, so this is bounded to keep from queueing hundreds of
// requests behind each other rather than because the network can't take it.
// 24 was the value measured above; higher stopped helping.
const CONCURRENCY = 24;

// How long a completed scan is served from memory before the next request
// re-reads Firestore. Two minutes is short enough that the dashboard is
// never meaningfully stale for "who is on the app right now" and long
// enough that clicking between the two tabs doesn't re-scan the project
// every time. The Refresh button bypasses it outright.
const CACHE_TTL_MS = 2 * 60 * 1000;

// An account counts as "on the app now" if the newest write we can see from
// them landed within this window.
//
// This is NOT presence. This app has no presence system: nothing writes an
// "online" flag, and a person can sit reading their grid for an hour
// without producing a single write. What this measures is "was doing
// something here very recently", which is the strongest signal that
// actually exists in the data, and the UI says so in those words rather
// than claiming a green dot means someone is looking at the screen.
const ONLINE_WINDOW_MS = 15 * 60 * 1000;

// How far back the scan reaches per account, per source.
//
// Named here rather than inlined at the query below because the DASHBOARD
// has to be able to say it out loud. A feed that stops at these limits
// without telling anyone reads as "this is everything that ever happened",
// when it means "this is as far back as I looked" - and on an admin tool the
// difference between those two is the whole point. See the horizon note
// under the feed.
const SCAN_LIMITS = {
  daily: 14, tasksCreated: 10, tasksCompleted: 10, milestones: 10, focusPlans: 5,
};

/** Runs [fn] over [items] with at most [limit] in flight at once. */
async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let cursor = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (cursor < items.length) {
      const i = cursor++;
      out[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return out;
}

/**
 * A query that is allowed to come back empty.
 *
 * orderBy on a field silently excludes documents that don't carry it, which
 * is exactly what's wanted here (a task with no completedAt isn't a
 * finished task), but a collection that has never existed for an account
 * also throws nothing and returns nothing. Either way the answer is "no
 * rows", so a failure here degrades one source for one account instead of
 * failing the whole scan.
 */
async function safeQuery(query) {
  try {
    const snap = await query.get();
    return snap.docs;
  } catch (e) {
    return [];
  }
}

// Mirrors milestoneHeadline (milestone_event.dart) so a milestone reads in
// the feed with the same sentence the user's own Journey page shows them,
// not a raw enum name. The achievement case can't reach this app's Dart
// AchievementCatalog, so it prints the stored id; every other case is the
// full sentence.
function milestoneHeadline(type, data) {
  const d = data || {};
  switch (type) {
    case 'levelUp':
      return d.level != null ? `Reached level ${d.level}` : 'Levelled up';
    case 'streakMilestone':
      return d.days != null ? `${d.days}-day streak` : 'Streak milestone';
    case 'perfectDay':
      return 'Perfect day, every habit done';
    case 'perfectWeek':
      return 'A full perfect week';
    case 'achievementUnlocked':
      return d.achievementId ? `Unlocked "${d.achievementId}"` : 'Achievement unlocked';
    case 'roomChallengeComplete':
      return d.roomName ? `Completed "${d.roomName}" challenge` : 'Completed a room challenge';
    case 'joined':
      return 'Started their Grow Daily journey';
    default:
      return type || 'Milestone';
  }
}

// ---------------------------------------------------------------------------
// Detail chips
// ---------------------------------------------------------------------------
//
// Every event carries a `details` list alongside its one-line `sub`. The sub
// answers "what happened"; these answer "what exactly", and the dashboard
// draws them as small chips under the row.
//
// They are built HERE and not in the browser because this is the last place
// that still holds the documents: the browser only ever sees what this file
// put in the payload, so a detail not assembled here cannot be recovered
// later without another read of the project.
//
// `tone` says what a chip MEANS, never what colour it is (done, miss, warn,
// undo, note, quote, plain). The stylesheet decides how each one looks, so
// re-theming the feed never involves editing this file.

/** A chip, or null when there was nothing to say - callers filter those out. */
function chip(text, tone) {
  const t = String(text == null ? '' : text).trim();
  return t ? { text: t, tone: tone || 'plain' } : null;
}

const WEEKDAY_SHORT = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/**
 * How a habit's scheduledWeekdays reads out loud.
 *
 * Stored as Dart weekday numbers (1=Mon..7=Sun) with an EMPTY list meaning
 * every day, not "no days" - see habitScheduledOnParts, which is the test
 * this label has to agree with.
 */
function scheduleLabel(weekdays) {
  const list = Array.from(new Set(
    (Array.isArray(weekdays) ? weekdays : []).filter((d) => d >= 1 && d <= 7),
  )).sort((a, b) => a - b);
  if (list.length === 0 || list.length === 7) return 'Every day';
  const key = list.join(',');
  if (key === '1,2,3,4,5') return 'Weekdays';
  if (key === '6,7') return 'Weekends';
  return list.map((d) => WEEKDAY_SHORT[d]).join(', ');
}

/** A run of somebody's own writing, shortened to fit one feed row. */
function clip(text, max) {
  const s = String(text == null ? '' : text).replace(/\s+/g, ' ').trim();
  if (!s) return '';
  return s.length > max ? `${s.slice(0, max - 1)}\u2026` : s;
}

/** A duration in the largest unit that still says something useful. */
function humanSpan(ms) {
  // Under a minute is measured on the real value, not on the rounded one:
  // rounding first makes 30 seconds report as "1 min" and puts the
  // sub-minute case permanently out of reach.
  if (ms < 60000) return 'under a minute';
  const mins = Math.round(ms / 60000);
  if (mins < 60) return `${mins} min`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `${hours} hour${hours === 1 ? '' : 's'}`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? '' : 's'}`;
}

/**
 * Whatever plain values a document carries, as chips.
 *
 * Used for the two collections this tool has no schema for (milestones'
 * free-form `data` bag and focus_plans). Printing the fields that are
 * actually there beats hard-coding a list that silently drops any field the
 * app adds later, and skipping objects and arrays keeps a nested blob from
 * turning into "[object Object]".
 */
function scalarDetails(data, skipKeys, labels) {
  const skip = new Set(skipKeys || []);
  const names = labels || {};
  const out = [];
  for (const [k, v] of Object.entries(data && typeof data === 'object' ? data : {})) {
    if (skip.has(k) || v == null || typeof v === 'object' || typeof v === 'function') continue;
    if (v === false || v === '') continue;
    const label = names[k] || k;
    out.push(v === true ? chip(label, 'note') : chip(`${label}: ${clip(v, 70)}`, 'plain'));
  }
  return out.filter(Boolean);
}

/**
 * One logged day, spelled out habit by habit.
 *
 * The feed used to say "3 habits done" and stop, which is the one part an
 * admin can already guess from the ring on the accounts table. WHICH three,
 * at what time, and which of that day's other habits went unmarked is the
 * part that settles a support question, and all of it is already inside the
 * day document this scan has in hand.
 *
 * [sum] must come from summarizeHabitDay called WITH that day's scheduled
 * ids, so habits that were due and never touched arrive as 'none' rows and
 * can be listed. Ordered the way it gets read: what they did, then the two
 * disagreements worth chasing, then what they did not do, then the day's own
 * notes.
 */
function dailyDetails(data, sum, habitCtx, dayKey, tzOffsetMinutes) {
  const d = data || {};
  const out = [];

  const rank = { completed: 0, grid_only: 1, undone: 2, marked: 3, none: 4 };
  const rows = sum.rows.slice().sort((a, b) => {
    const byVerdict = (rank[a.verdict] === undefined ? 9 : rank[a.verdict])
      - (rank[b.verdict] === undefined ? 9 : rank[b.verdict]);
    if (byVerdict !== 0) return byVerdict;
    // Inside a verdict, the order they happened. Habits with no timestamp
    // (a Grid square carries none) sort last rather than to midnight.
    const at = (r) => (r.stampedAt === null ? Number.MAX_SAFE_INTEGER : r.stampedAt);
    return at(a) - at(b);
  });

  for (const r of rows) {
    const name = habitLabel(r.habitId, habitCtx, r.receipt ? r.receipt.category : null);
    const at = r.stampedAt !== null ? fmtMinutes(r.stampedAt) : '';
    switch (r.verdict) {
      case 'completed': {
        const times = r.count > 1 ? ` \u00d7${r.count}` : '';
        const of = r.target > 1 ? ` of ${r.target}` : '';
        out.push(chip(`\u2705 ${name}${times}${of}${at ? ` \u00b7 ${at}` : ''}`, 'done'));
        break;
      }
      case 'grid_only':
        // The disagreement from the Grid-square trap: a Room counts this,
        // the ledger paid nothing for it.
        out.push(chip(`\ud83d\udfe9 ${name} \u00b7 Grid square only, no completion`, 'warn'));
        break;
      case 'undone':
        out.push(chip(`\u21a9\ufe0f ${name} \u00b7 completed${at ? ` ${at}` : ''}, then un-marked`, 'undo'));
        break;
      case 'marked': {
        const meta = SQUARE_META[r.square] || SQUARE_META.none;
        out.push(chip(`${meta.emoji} ${name} \u00b7 ${meta.label}`, 'note'));
        break;
      }
      default:
        out.push(chip(`\u2b1c ${name} \u00b7 not marked`, 'miss'));
    }
  }

  if (d.mood && MOOD_META[d.mood]) {
    out.push(chip(`${MOOD_META[d.mood].emoji} Mood: ${MOOD_META[d.mood].label}`, 'note'));
  }
  if (d.nightReviewDone) out.push(chip('\ud83c\udf19 Night review done', 'note'));
  const reflection = clip(d.dailyReflection, 180);
  if (reflection) out.push(chip(`\u201c${reflection}\u201d`, 'quote'));

  const xp = Number(d.totalXpEarned) || 0;
  const gold = Number(d.totalGoldEarned) || 0;
  if (xp || gold) out.push(chip(`+${xp} XP \u00b7 +${gold} gold`, 'note'));

  const timers = d.timerSeconds && typeof d.timerSeconds === 'object' ? d.timerSeconds : {};
  const timerSecs = Object.values(timers).reduce((a, b) => a + (Number(b) || 0), 0);
  if (timerSecs > 0) out.push(chip(`\u23f1 ${Math.round(timerSecs / 60)} min on habit timers`, 'note'));

  // WHEN the day was written against WHICH day it was written about. A day
  // filled in the next morning is normal, not a fault, but a feed that shows
  // only one of the two timestamps invites reading it as one - which is the
  // same confusion the pre-cutoff Grid square caused.
  const write = dayWriteContext(d, tzOffsetMinutes);
  if (write) {
    out.push(write.key === dayKey
      ? chip(`Written ${write.clock}, their clock`, 'plain')
      : chip(`Written ${write.clock} on ${write.key}, their clock`, 'warn'));
  }

  return out.filter(Boolean);
}

/** A matrix task, as the board itself would describe it. */
function taskDetails(t, finished) {
  const out = [];
  const q = QUADRANT_META[t.quadrant];
  if (q) out.push(chip(`${q.label} \u00b7 ${q.subtitle}`, 'plain'));
  // 'isToday' on the wire is the star, not a due date - see MatrixTask.isFav.
  if (t.isToday) out.push(chip('\u2b50 Starred for today', 'note'));
  const desc = clip(t.description, 160);
  if (desc) out.push(chip(desc, 'quote'));
  const reminders = Array.isArray(t.reminderAts)
    ? t.reminderAts.length
    : (t.reminderAt ? 1 : 0);
  if (reminders) out.push(chip(`\u23f0 ${reminders} reminder${reminders === 1 ? '' : 's'}`, 'plain'));
  const notes = Array.isArray(t.voiceNotes) ? t.voiceNotes.length : 0;
  if (notes) out.push(chip(`\ud83c\udfa4 ${notes} voice note${notes === 1 ? '' : 's'}`, 'plain'));
  if (finished) {
    const made = toJsDate(t.createdAt);
    const done = toJsDate(t.completedAt);
    if (made && done && done >= made) {
      out.push(chip(`Open for ${humanSpan(done.getTime() - made.getTime())}`, 'plain'));
    }
    if (t.rewarded === false) out.push(chip('Finished without being paid for', 'warn'));
  }
  return out.filter(Boolean);
}

/** A habit, as its own setup sheet would describe it. */
function habitDetails(h) {
  const out = [];
  const cat = CATEGORY_META[h.category];
  if (cat) out.push(chip(`${cat.emoji} ${cat.label}`, 'plain'));
  out.push(chip(scheduleLabel(h.scheduledWeekdays), 'plain'));
  const target = Number(h.frequencyTarget) || 1;
  if (h.frequencyType === 'weekly') out.push(chip(`${target}\u00d7 a week`, 'plain'));
  else if (target > 1) out.push(chip(`${target}\u00d7 a day`, 'plain'));
  if (h.goalType === 'quit') out.push(chip('A habit they are quitting', 'note'));
  if (h.hasTimer) {
    const secs = Number(h.timerDurationSeconds) || 0;
    out.push(chip(secs ? `\u23f1 ${Math.round(secs / 60)} min timer` : '\u23f1 Has a timer', 'plain'));
  }
  out.push(chip(h.isPreset ? 'From the catalog' : 'Their own', 'plain'));
  const xp = Number(h.xpReward) || 0;
  const gold = Number(h.goldReward) || 0;
  if (xp || gold) out.push(chip(`Pays ${xp} XP \u00b7 ${gold} gold`, 'plain'));
  const cue = clip(h.cueAfter, 90);
  if (cue) out.push(chip(`After: ${cue}`, 'note'));
  const desc = clip(h.description, 160);
  if (desc) out.push(chip(desc, 'quote'));
  return out.filter(Boolean);
}

/**
 * Everything one account did recently, as feed events plus the numbers the
 * accounts table shows.
 *
 * [profile] is the users/{uid} doc's selected fields (see listAllUsers) and
 * [authRow] the Firebase Auth half; both may be missing, and this returns
 * whatever it can either way rather than throwing, same self-healing
 * posture as the rest of this tool.
 */
async function scanOneAccount(uid, profile, authRow) {
  const userRef = db().collection('users').doc(uid);

  const [habitDocs, dailyDocs, newTaskDocs, doneTaskDocs, milestoneDocs, focusDocs] =
    await Promise.all([
      // Whole collection, not a limit: this is a handful of docs per person
      // and the accounts table's "today" column needs every habit's
      // schedule to know how many were even DUE today, which a newest-first
      // slice can't answer.
      safeQuery(userRef.collection('custom_habits')),
      safeQuery(userRef.collection('daily').orderBy('lastUpdated', 'desc').limit(SCAN_LIMITS.daily)),
      safeQuery(userRef.collection('matrix_tasks').orderBy('createdAt', 'desc').limit(SCAN_LIMITS.tasksCreated)),
      safeQuery(userRef.collection('matrix_tasks').orderBy('completedAt', 'desc').limit(SCAN_LIMITS.tasksCompleted)),
      safeQuery(userRef.collection('milestones').orderBy('occurredAt', 'desc').limit(SCAN_LIMITS.milestones)),
      safeQuery(userRef.collection('focus_plans').orderBy('updatedAt', 'desc').limit(SCAN_LIMITS.focusPlans)),
    ]);

  const displayName = (profile && profile.displayName) || '';
  const email = (authRow && authRow.email) || '';
  const who = displayName || email || uid;
  const tzOffsetMinutes = profile && profile.tzOffsetMinutes;
  const events = [];
  const push = (at, type, title, sub, dayKey, details) => {
    const d = toJsDate(at);
    if (!d) return;
    events.push({
      at: d.getTime(),
      uid,
      who,
      email,
      type,
      title,
      sub: sub || '',
      dayKey: dayKey || '',
      // Always an array, never undefined: the feed maps over this on every
      // row, and one event missing the key would take the whole render down.
      details: details || [],
    });
  };

  const receiptsByKey = readUndoneReceipts(profile);

  // Habit names for every id this account still has a doc for, so a detail
  // line can say "Quran" instead of a 20-character id. A habit deleted
  // outright is not in here at all, and habitLabel says so in those words
  // rather than printing a bare id.
  const habitCtx = {};
  for (const doc of habitDocs) {
    const h = doc.data();
    habitCtx[doc.id] = { name: h.name, category: h.category };
  }

  for (const doc of dailyDocs) {
    const d = doc.data();
    // Every habit that was DUE on that day, not only the ones that left a
    // trace, so the detail list below can name what went unmarked and the
    // headline can carry an honest denominator. Feeding these to
    // summarizeHabitDay only ever ADDS 'none' rows - not one of its counts
    // moves - so the classifier reading below is the one it always was.
    const scheduledIds = habitDocs
      .filter((h) => habitScheduledOnParts(h.data(), dayKeyParts(doc.id)))
      .map((h) => h.id);
    // Through the classifier, so this line can never say "no habit
    // completions" about a day the person had actually marked. It said
    // exactly that about a day a Room was crediting, because a square
    // painted outside the reward window writes squareStates and nothing
    // else - see readHabitDay in render.js.
    const sum = summarizeHabitDay(d, scheduledIds, receiptsByKey, doc.id);
    const bits = [];
    // greens, not done: what the PERSON did, by either route. The two ways
    // those can differ are both called out on the next lines, so folding
    // them together in the headline number hides nothing.
    if (scheduledIds.length > 0) bits.push(`${sum.greens} of ${scheduledIds.length} done`);
    else if (sum.greens > 0) bits.push(`${sum.greens} done`);
    if (sum.gridOnly > 0) bits.push(`${sum.gridOnly} marked on the Grid only (no completion)`);
    if (sum.undone > 0) bits.push(`${sum.undone} completed then un-marked`);
    if (sum.marked > 0) bits.push(`${sum.marked} non-green mark${sum.marked === 1 ? '' : 's'}`);
    if (d.mood && MOOD_META[d.mood]) bits.push(`${MOOD_META[d.mood].emoji} ${MOOD_META[d.mood].label}`);
    if (d.nightReviewDone) bits.push('night review');
    if (d.dailyReflection) bits.push('wrote a reflection');
    push(d.lastUpdated, 'habits', `Logged their day (${doc.id})`,
      bits.length ? bits.join(' · ') : 'nothing marked', doc.id,
      dailyDetails(d, sum, habitCtx, doc.id, tzOffsetMinutes));
  }

  // Un-marking has no timestamp of its own anywhere - the UndoneCompletion
  // receipt stores undoneOn as a plain date key, deliberately (see that
  // class), so day is all the precision that exists. Anchored at noon of
  // that day so it sorts inside the right date heading without pretending
  // to a time it does not have.
  for (const r of Object.values(receiptsByKey)) {
    if (!r.undoneOn) continue;
    const at = new Date(`${r.undoneOn}T12:00:00`);
    if (Number.isNaN(at.getTime())) continue;
    const habit = habitDocs.find((h) => h.id === r.habitId);
    const ctx = habit ? { [habit.id]: { name: habit.data().name, category: habit.data().category } } : {};
    push(at, 'habit_undone', 'Un-marked a completion',
      `${habitLabel(r.habitId, ctx, r.category)} · for ${r.dateKey} · took back ${r.xp} XP and ${r.gold} gold`,
      r.dateKey, [
        // Only what the line above does NOT already say. The habit, the day
        // and the amount are all in the summary; repeating them as chips
        // made the row twice as tall and no clearer. This is the part that
        // is not obvious: the receipt is still sitting on the profile, so
        // marking that habit-day again REDEEMS it rather than paying twice.
        chip('Receipt outstanding, so re-marking redeems it rather than paying twice', 'note'),
      ].filter(Boolean));
  }

  for (const doc of newTaskDocs) {
    const t = doc.data();
    push(t.createdAt, 'task_new', 'Added a task', t.title || '(untitled task)', '',
      taskDetails(t, false));
  }
  for (const doc of doneTaskDocs) {
    const t = doc.data();
    if (!t.isDone) continue; // completedAt left behind on a restored task
    push(t.completedAt, 'task_done', 'Finished a task', t.title || '(untitled task)', '',
      taskDetails(t, true));
  }
  for (const doc of habitDocs) {
    const h = doc.data();
    const cat = CATEGORY_META[h.category];
    push(h.createdAt, 'habit_new', 'Created a habit',
      `${cat ? cat.emoji + ' ' : ''}${h.name || '(unnamed habit)'}`, '', habitDetails(h));
    if (h.archivedAt) {
      // What it was worth by the time they put it away, which is the whole
      // question when someone asks why a streak stopped.
      push(h.archivedAt, 'habit_archived', 'Archived a habit',
        h.name || '(unnamed habit)', '', [
          chip(`${Number(h.totalCompletions) || 0} completions in its life`, 'plain'),
          chip(`Longest streak ${Number(h.longestStreak) || 0}`, 'plain'),
          chip(`Streak was ${Number(h.currentStreak) || 0} when it was archived`, 'plain'),
        ].filter(Boolean));
    }
  }
  for (const doc of milestoneDocs) {
    const m = doc.data();
    push(m.occurredAt, 'milestone', milestoneHeadline(m.type, m.data), '', '',
      scalarDetails(m.data, [], {
        level: 'Level', days: 'Days', xp: 'XP', gold: 'Gold',
        roomName: 'Room', achievementId: 'Achievement', habitName: 'Habit',
      }));
  }
  for (const doc of focusDocs) {
    const f = doc.data();
    const bits = [];
    if (f.focusSessions) bits.push(`${f.focusSessions} session${f.focusSessions === 1 ? '' : 's'}`);
    if (f.topTask) bits.push(f.topTask);
    push(f.updatedAt, 'focus', `Worked on their focus plan (${doc.id})`, bits.join(' · '), doc.id,
      scalarDetails(f, ['uid', 'dateKey', 'createdAt', 'updatedAt'], {
        focusSessions: 'Sessions', topTask: 'Top task', focusMinutes: 'Minutes',
      }));
  }

  if (authRow && authRow.createdAt) push(authRow.createdAt, 'signup', 'Created their account', email);
  if (authRow && authRow.lastSignIn) push(authRow.lastSignIn, 'signin', 'Signed in', '');

  // ---- The accounts table's own numbers ----
  //
  // "Today" is this ACCOUNT's today (their reported device offset, and this
  // app's habit day cutoff), never this machine's, so a person in another
  // timezone is judged against the day their own phone is showing them.
  const todayParts = effectiveTodayParts(profile && profile.tzOffsetMinutes);
  const todayDoc = dailyDocs.find((d) => d.id === todayParts.key);
  const todayData = todayDoc ? todayDoc.data() : null;
  const todayCompletions = todayData && todayData.habitCompletions
      && typeof todayData.habitCompletions === 'object'
    ? todayData.habitCompletions
    : {};
  let todayScheduled = 0;
  let todayDone = 0;
  for (const doc of habitDocs) {
    if (!habitScheduledOnParts(doc.data(), todayParts)) continue;
    todayScheduled += 1;
    if (Number(todayCompletions[doc.id] || 0) > 0) todayDone += 1;
  }

  // Their last REAL action, which deliberately excludes signin: a session
  // restored in the background counts as "signed in" without the person
  // having done anything, and treating that as activity is what makes an
  // "active today" number lie upward.
  const doing = events.filter((e) => e.type !== 'signin' && e.type !== 'signup');
  doing.sort((a, b) => b.at - a.at);
  const lastAction = doing[0] || null;

  return {
    uid,
    events,
    row: {
      uid,
      email,
      displayName,
      createdAt: authRow ? authRow.createdAt : null,
      lastSignIn: authRow ? authRow.lastSignIn : null,
      disabled: !!(authRow && authRow.disabled),
      level: profile && profile.level != null ? profile.level : null,
      currentStreak: profile && profile.currentStreak != null ? profile.currentStreak : null,
      gold: profile && profile.gold != null ? profile.gold : null,
      totalHabitCompletions: profile && profile.totalHabitCompletions != null
        ? profile.totalHabitCompletions : null,
      locale: (profile && profile.locale) || '',
      habitCount: habitDocs.filter((d) => !d.data().archivedAt).length,
      todayKey: todayParts.key,
      todayDone,
      todayScheduled,
      lastActiveAt: lastAction ? new Date(lastAction.at).toISOString() : null,
      lastActionType: lastAction ? lastAction.type : '',
      lastActionText: lastAction ? lastAction.title : '',
      lastActionSub: lastAction ? lastAction.sub : '',
    },
  };
}

let _cache = null; // { at, payload }
let _inFlight = null;

/**
 * The whole dashboard's data in one object.
 *
 * Concurrent callers share one scan (_inFlight) rather than each starting
 * their own: the home page fetches this on load and the Refresh button can
 * be pressed while that's still running, and two overlapping full-project
 * scans is the one way this tool could actually put load on the project.
 */
async function scanActivity(forceRefresh) {
  if (!forceRefresh && _cache && Date.now() - _cache.at < CACHE_TTL_MS) return _cache.payload;
  if (_inFlight) return _inFlight;

  _inFlight = (async () => {
    const startedAt = Date.now();

    const authRows = new Map();
    let pageToken;
    do {
      const page = await auth().listUsers(1000, pageToken);
      for (const u of page.users) {
        authRows.set(u.uid, {
          uid: u.uid,
          email: u.email || '',
          createdAt: u.metadata.creationTime || null,
          lastSignIn: u.metadata.lastSignInTime || null,
          disabled: !!u.disabled,
        });
      }
      pageToken = page.pageToken;
    } while (pageToken);

    // One query for every account's profile highlights, rather than a
    // seventh per-account read. select() keeps it to the fields the
    // dashboard actually prints - so anything a scan reads has to be named
    // here or it silently arrives undefined, which is exactly how the
    // un-marked events came out empty on their first run.
    const profiles = new Map();
    const profileSnap = await db().collection('users')
      .select('displayName', 'createdAt', 'level', 'currentStreak', 'longestStreak',
        'gold', 'cumulativeXp', 'totalHabitCompletions', 'tzOffsetMinutes', 'locale',
        'undoneCompletions')
      .get();
    profileSnap.forEach((doc) => profiles.set(doc.id, doc.data()));

    // A Firestore profile with no Auth account (one deleted straight from
    // the console rather than through the app's own delete flow) still gets
    // scanned, so it doesn't quietly vanish from the admin's view.
    const uids = Array.from(new Set([...authRows.keys(), ...profiles.keys()]));

    // A scan that throws for one account used to return null and get
    // skipped, which meant the account disappeared from the roster
    // entirely and the only trace was a smaller total. An admin tool that
    // quietly omits people is worse than one that shows an error: you
    // cannot go looking for what you do not know is missing. So a failure
    // now degrades to the row we can still build from Auth and the profile
    // doc, flagged, and the dashboard says how many.
    const failures = [];
    const scanned = await mapLimit(uids, CONCURRENCY, async (uid) => {
      try {
        return await scanOneAccount(uid, profiles.get(uid), authRows.get(uid));
      } catch (e) {
        failures.push({ uid, message: e.message });
        const authRow = authRows.get(uid);
        const profile = profiles.get(uid) || {};
        return {
          uid,
          events: [],
          row: {
            uid,
            email: (authRow && authRow.email) || '',
            displayName: profile.displayName || '',
            createdAt: authRow ? authRow.createdAt : null,
            lastSignIn: authRow ? authRow.lastSignIn : null,
            disabled: !!(authRow && authRow.disabled),
            level: profile.level != null ? profile.level : null,
            currentStreak: profile.currentStreak != null ? profile.currentStreak : null,
            gold: profile.gold != null ? profile.gold : null,
            totalHabitCompletions: profile.totalHabitCompletions != null
              ? profile.totalHabitCompletions : null,
            locale: profile.locale || '',
            habitCount: null,
            todayKey: effectiveTodayParts(profile.tzOffsetMinutes).key,
            todayDone: 0,
            todayScheduled: 0,
            lastActiveAt: null,
            lastActionType: '',
            lastActionText: '',
            lastActionSub: '',
            scanFailed: e.message,
          },
        };
      }
    });

    const accounts = [];
    let events = [];
    for (const s of scanned) {
      if (!s) continue;
      accounts.push(s.row);
      events = events.concat(s.events);
    }
    events.sort((a, b) => b.at - a.at);

    const payload = {
      scannedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      onlineWindowMinutes: ONLINE_WINDOW_MS / 60000,
      limits: SCAN_LIMITS,
      failures,
      accounts,
      // Bounded because the browser holds the whole thing and the feed is
      // read by scrolling, not by paging. Every account's full history is
      // still one click away on its own report.
      events: events.slice(0, 4000),
    };
    _cache = { at: Date.now(), payload };
    return payload;
  })();

  try {
    return await _inFlight;
  } finally {
    _inFlight = null;
  }
}

/**
 * Per-account habit completion for ONE specific day, however far back.
 *
 * The cached scan above carries each account's most recent 14 daily docs,
 * which covers "this week" without another read but not a day last spring.
 * This reads that exact day's doc per account instead (a direct document
 * get, no query and no index), so the dashboard's day picker can go
 * anywhere in an account's history rather than only as far back as the
 * cache happens to reach.
 */
async function scanDay(dateKey) {
  const scan = await scanActivity(false);
  const uids = scan.accounts.map((a) => a.uid);

  const rows = await mapLimit(uids, CONCURRENCY, async (uid) => {
    const [dailySnap, habitDocs] = await Promise.all([
      db().collection('users').doc(uid).collection('daily').doc(dateKey).get()
        .catch(() => null),
      safeQuery(db().collection('users').doc(uid).collection('custom_habits')),
    ]);
    const data = dailySnap && dailySnap.exists ? dailySnap.data() : null;
    const parts = dayKeyParts(dateKey);
    const scheduledIds = habitDocs
      .filter((doc) => habitScheduledOnParts(doc.data(), parts))
      .map((doc) => doc.id);
    // Through the same classifier the report uses, so this table and a
    // person's own report can never disagree about one day. `done` is every
    // green square by either route - what the person marked, and what a Room
    // credits - with the two disagreements carried alongside rather than
    // folded in. Counting only habitCompletions here read a marked day as a
    // flat zero, which is how a Room and this dashboard came to report
    // different numbers for the same person on the same day.
    const sum = summarizeHabitDay(data, scheduledIds, {}, dateKey);
    return {
      uid,
      done: sum.greens,
      completed: sum.done,
      gridOnly: sum.gridOnly,
      undone: sum.undone,
      scheduled: scheduledIds.length,
      mood: data && data.mood ? data.mood : '',
      nightReviewDone: !!(data && data.nightReviewDone),
      reflection: (data && data.dailyReflection) || '',
      lastUpdated: data && data.lastUpdated && data.lastUpdated.toDate
        ? data.lastUpdated.toDate().toISOString() : null,
      hasDoc: !!data,
    };
  });

  return { dateKey, rows };
}

module.exports = {
  scanActivity,
  SCAN_LIMITS,
  scanDay,
  milestoneHeadline,
  mapLimit,
  ONLINE_WINDOW_MS,
  // Exported for the tests, which can exercise these against a document
  // shape without a Firestore connection - the scan itself needs one.
  scheduleLabel,
  humanSpan,
  clip,
  dailyDetails,
  taskDetails,
  habitDetails,
  scalarDetails,
};
