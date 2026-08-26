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
  const events = [];
  const push = (at, type, title, sub, dayKey) => {
    const d = toJsDate(at);
    if (!d) return;
    events.push({ at: d.getTime(), uid, who, email, type, title, sub: sub || '', dayKey: dayKey || '' });
  };

  for (const doc of dailyDocs) {
    const d = doc.data();
    const completions = d.habitCompletions && typeof d.habitCompletions === 'object'
      ? Object.values(d.habitCompletions).filter((c) => Number(c) > 0).length
      : 0;
    const bits = [];
    if (completions > 0) bits.push(`${completions} habit${completions === 1 ? '' : 's'} done`);
    if (d.mood && MOOD_META[d.mood]) bits.push(`${MOOD_META[d.mood].emoji} ${MOOD_META[d.mood].label}`);
    if (d.nightReviewDone) bits.push('night review');
    if (d.dailyReflection) bits.push('wrote a reflection');
    push(d.lastUpdated, 'habits', `Logged their day (${doc.id})`,
      bits.length ? bits.join(' · ') : 'no habit completions', doc.id);
  }

  for (const doc of newTaskDocs) {
    const t = doc.data();
    push(t.createdAt, 'task_new', 'Added a task', t.title || '(untitled task)');
  }
  for (const doc of doneTaskDocs) {
    const t = doc.data();
    if (!t.isDone) continue; // completedAt left behind on a restored task
    push(t.completedAt, 'task_done', 'Finished a task', t.title || '(untitled task)');
  }
  for (const doc of habitDocs) {
    const h = doc.data();
    const cat = CATEGORY_META[h.category];
    push(h.createdAt, 'habit_new', 'Created a habit',
      `${cat ? cat.emoji + ' ' : ''}${h.name || '(unnamed habit)'}`);
    if (h.archivedAt) {
      push(h.archivedAt, 'habit_archived', 'Archived a habit', h.name || '(unnamed habit)');
    }
  }
  for (const doc of milestoneDocs) {
    const m = doc.data();
    push(m.occurredAt, 'milestone', milestoneHeadline(m.type, m.data), '');
  }
  for (const doc of focusDocs) {
    const f = doc.data();
    const bits = [];
    if (f.focusSessions) bits.push(`${f.focusSessions} session${f.focusSessions === 1 ? '' : 's'}`);
    if (f.topTask) bits.push(f.topTask);
    push(f.updatedAt, 'focus', `Worked on their focus plan (${doc.id})`, bits.join(' · '), doc.id);
  }

  if (authRow && authRow.createdAt) push(authRow.createdAt, 'signup', 'Created their account', email);
  if (authRow && authRow.lastSignIn) push(authRow.lastSignIn, 'signin', 'Signed in', '');

  // ---- The accounts table's own numbers ----
  //
  // "Today" is this ACCOUNT's today (their reported device offset, and this
  // app's 6 AM habit cutoff), never this machine's, so a person in another
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
    // dashboard actually prints.
    const profiles = new Map();
    const profileSnap = await db().collection('users')
      .select('displayName', 'createdAt', 'level', 'currentStreak', 'longestStreak',
        'gold', 'cumulativeXp', 'totalHabitCompletions', 'tzOffsetMinutes', 'locale')
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
    const completions = data && data.habitCompletions && typeof data.habitCompletions === 'object'
      ? data.habitCompletions : {};
    let scheduled = 0;
    let done = 0;
    for (const doc of habitDocs) {
      if (!habitScheduledOnParts(doc.data(), parts)) continue;
      scheduled += 1;
      if (Number(completions[doc.id] || 0) > 0) done += 1;
    }
    return {
      uid,
      done,
      scheduled,
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
};
