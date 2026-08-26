'use strict';

/**
 * Firebase Auth/Firestore access for the admin lookup tool.
 *
 * Assumes admin.initializeApp() has already been called by whichever entry
 * point required this module (lookup_user.js or server.js) — this file
 * only ever reads admin.firestore()/admin.auth() lazily, never initializes
 * the app itself, so both entry points stay in charge of their own
 * credentials setup.
 */

const admin = require('firebase-admin');
const {
  KNOWN_LABELS,
  renderDocList,
  escapeHtml,
  renderFieldTable,
  buildHabitContext,
  CATEGORY_META,
  MOOD_META,
  QUADRANT_ORDER,
  toJsDate,
  effectiveTodayParts,
  calendarTodayParts,
  triageTasksForDay,
  habitScheduledOnParts,
  renderDayCard,
  renderCalendarSection,
  dayKeyParts,
} = require('./render');

function db() {
  return admin.firestore();
}
function auth() {
  return admin.auth();
}

/**
 * Resolves a query (an email or a uid) to { uid, authRecord }. Throws if
 * an email was given and no such Auth account exists. A uid that has no
 * Auth account (e.g. one manually deleted from the console) resolves with
 * authRecord: null instead of throwing — the caller falls back to
 * Firestore-only data, same self-healing spirit as the rest of this app.
 */
async function resolveAccount(query) {
  let uid = query.trim();
  let authRecord = null;

  if (uid.includes('@')) {
    authRecord = await auth().getUserByEmail(uid); // throws if not found
    uid = authRecord.uid;
  } else {
    try {
      authRecord = await auth().getUser(uid);
    } catch (e) {
      authRecord = null;
    }
  }
  return { uid, authRecord };
}

/**
 * Reads one account's whole tree once: the users/{uid} profile doc, every
 * subcollection under it (discovered live via listCollections, not
 * hardcoded, so a feature added after this tool was written still shows up
 * without a change here), and every room it participates in.
 *
 * Split out from loadAccountReport, and cached, because the day picker
 * turned one report into many: stepping back through a month used to mean
 * re-reading the entire account from Firestore per day, for data that
 * cannot have changed between two clicks a second apart. Now the read
 * happens once and each day is rendered from it.
 */
async function loadAccountRaw(uid, authRecord) {
  const userRef = db().collection('users').doc(uid);
  const userDoc = await userRef.get();
  if (!userDoc.exists && !authRecord) {
    throw new Error(`Nothing found for "${uid}" — checked both Firebase Auth and Firestore.`);
  }
  const profileData = userDoc.exists ? userDoc.data() : null;

  // Fetched up front (not inline in the render loop) so buildHabitContext
  // always has this account's full custom_habits list ready before the
  // 'daily' section renders, regardless of which order listCollections()
  // happens to return them in.
  const subcollections = await userRef.listCollections();
  const docsByCollection = {};
  for (const col of subcollections) {
    const snap = await col.get();
    docsByCollection[col.id] = snap.docs.slice().sort((a, b) => b.id.localeCompare(a.id));
  }
  const habitCtx = buildHabitContext(docsByCollection['custom_habits']);

  // Rooms this account participates in - a collectionGroup query across
  // every rooms/{code}/participants subcollection, filtered on the `uid`
  // field each participant doc already carries (see RoomParticipant.
  // toFirestore in room_model.dart) rather than the doc id, since
  // collectionGroup queries can't filter on document id across differing
  // parent paths. Needs the fieldOverrides entry in firestore.indexes.json
  // (COLLECTION_GROUP scope on participants.uid) - wrapped in its own
  // try/catch so a hiccup on just this one query degrades to a note in its
  // own section instead of losing the whole report.
  let roomRows = [];
  let roomsSectionHtml;
  try {
    const participantSnap = await db().collectionGroup('participants')
      .where('uid', '==', uid).get();
    roomRows = await Promise.all(participantSnap.docs.map(async (p) => {
      const roomRef = p.ref.parent.parent; // rooms/{code}
      const roomSnap = await roomRef.get();
      return { code: roomRef.id, room: roomSnap.data() || {}, participant: p.data() };
    }));
    roomsSectionHtml = roomRows.length === 0
      ? '<p class="muted">Not in any rooms.</p>'
      : roomRows.map((r) => `
          <details class="doc">
            <summary>Room ${escapeHtml(r.code)}${r.room.name ? ' — ' + escapeHtml(r.room.name) : ''}</summary>
            <div class="doc-id">${escapeHtml(r.code)}</div>
            <h3>Room</h3>
            ${renderFieldTable(r.room)}
            <h3>This account's participant entry</h3>
            ${renderFieldTable(r.participant)}
          </details>
        `).join('');
  } catch (e) {
    roomRows = [];
    roomsSectionHtml = `<p class="muted">Couldn't load this section — ${escapeHtml(e.message)}</p>`;
  }

  return {
    uid, authRecord, profileData, subcollections, docsByCollection,
    habitCtx, roomRows, roomsSectionHtml,
  };
}

// Short-lived so day-stepping is free while an admin is reading one
// account, and short enough that coming back to a report a minute later
// still re-reads rather than showing a frozen page.
const RAW_TTL_MS = 60 * 1000;
const _rawCache = new Map(); // uid -> { at, raw }

async function getAccountRaw(uid, authRecord, { fresh } = {}) {
  // Drop everything already past its TTL, not just this uid's entry. Each
  // value holds an account's entire document tree, so keeping expired ones
  // around means a server left running while the roster is browsed retains
  // every account it ever rendered, none of which can be read again.
  const now = Date.now();
  for (const [key, entry] of _rawCache) {
    if (now - entry.at >= RAW_TTL_MS) _rawCache.delete(key);
  }
  const hit = _rawCache.get(uid);
  if (!fresh && hit) return hit.raw;
  const raw = await loadAccountRaw(uid, authRecord);
  _rawCache.set(uid, { at: Date.now(), raw });
  return raw;
}

/**
 * The Day section, for whatever day is asked for.
 *
 * [dateKey] is 'YYYY-MM-DD', or omitted for this ACCOUNT's own today (their
 * last-reported device offset and this app's 6 AM habit cutoff, never this
 * machine's clock), so the headline number can't disagree with what the
 * user's own phone is showing them.
 *
 * Habits and tasks run on two different clocks here, on purpose, because
 * the app itself uses two: habits on the 6 AM flex day (effectiveTodayParts)
 * and the todo board on the plain calendar day (calendarTodayParts). See
 * calendarTodayParts' own comment for the bug that came of conflating them.
 */
function buildDaySection(raw, dateKey) {
  const { profileData, docsByCollection, roomRows } = raw;
  const tz = profileData && profileData.tzOffsetMinutes;
  const todayParts = effectiveTodayParts(tz);
  const isToday = !dateKey || dateKey === todayParts.key;
  const parts = isToday ? todayParts : dayKeyParts(dateKey);
  const dayKey = parts.key;

  const habitDocs = docsByCollection['custom_habits'] || [];
  const dailyDocs = docsByCollection['daily'] || [];
  const dayDoc = dailyDocs.find((d) => d.id === dayKey);
  const dayData = dayDoc ? dayDoc.data() : {};
  const completions = dayData.habitCompletions && typeof dayData.habitCompletions === 'object'
    ? dayData.habitCompletions
    : {};

  const habitRows = [];
  for (const doc of habitDocs) {
    const h = doc.data();
    if (!habitScheduledOnParts(h, parts)) continue;
    const count = Number(completions[doc.id] || 0);
    const cat = CATEGORY_META[h.category] || { emoji: '⭐' };
    habitRows.push({ name: h.name || '(unnamed habit)', emoji: cat.emoji, done: count > 0, count });
  }

  const taskDocs = docsByCollection['matrix_tasks'] || [];
  const taskParts = isToday ? calendarTodayParts(tz) : dayKeyParts(dayKey);
  const triage = triageTasksForDay(taskDocs, taskParts);

  const rooms = roomRows.map((r) => ({
    name: r.room.name || r.code,
    allDone: r.participant.allDoneToday === true && r.participant.allDoneDate === dayKey,
    muted: r.participant.notificationsMuted === true,
  }));

  const done = habitRows.filter((h) => h.done).length;
  const total = habitRows.length;

  return {
    id: 'today',
    label: '📍 Day',
    count: `${done}/${total}`,
    done,
    total,
    dayKey,
    isToday,
    todayKey: todayParts.key,
    html: renderDayCard({
      dayKey,
      isToday,
      todayKey: todayParts.key,
      habitRows,
      mood: dayData.mood ? MOOD_META[dayData.mood] : null,
      nightReviewDone: !!dayData.nightReviewDone,
      reflection: dayData.dailyReflection || '',
      xp: dayData.totalXpEarned || 0,
      gold: dayData.totalGoldEarned || 0,
      hasDoc: !!dayDoc,
      triage,
      taskDayKey: taskParts.key,
      rooms,
    }),
  };
}

/**
 * One account's full report: the Day section (for [dateKey], default their
 * today), the Auth record, the profile, every subcollection, and rooms.
 * Returns { uid, authRecord, profileData, sections, todaySummary } - the
 * shape both lookup_user.js and server.js hand straight to render.js's
 * buildReportBody.
 */
async function loadAccountReport(uid, authRecord, dateKey) {
  const raw = await getAccountRaw(uid, authRecord);
  const { profileData, subcollections, docsByCollection, habitCtx, roomsSectionHtml } = raw;

  const sections = [];
  const day = buildDaySection(raw, dateKey);
  sections.push(day);

  if (authRecord) {
    sections.push({
      id: 'auth',
      label: 'Firebase Auth account',
      html: `<table class="fields"><tbody>
          <tr><th>uid</th><td>${escapeHtml(authRecord.uid)}</td></tr>
          <tr><th>email</th><td>${escapeHtml(authRecord.email || '—')}</td></tr>
          <tr><th>email verified</th><td>${authRecord.emailVerified}</td></tr>
          <tr><th>created</th><td>${escapeHtml(authRecord.metadata.creationTime)}</td></tr>
          <tr><th>last sign-in</th><td>${escapeHtml(authRecord.metadata.lastSignInTime)}</td></tr>
          <tr><th>disabled</th><td>${authRecord.disabled}</td></tr>
        </tbody></table>`,
    });
  }

  sections.push({
    id: 'profile',
    label: 'Profile',
    html: profileData
      ? `<details class="doc"><summary>Show all raw profile fields</summary>${renderFieldTable(profileData)}</details>`
      : '<p class="muted">No Firestore profile doc.</p>',
  });

  for (const col of subcollections) {
    // 'daily' gets a real month-by-month calendar instead of the generic
    // flat log list every other subcollection uses - see
    // renderCalendarSection's doc comment for why this one specifically
    // has a natural calendar shape the others don't.
    if (col.id === 'daily') {
      sections.push({
        id: 'daily',
        label: KNOWN_LABELS.daily,
        count: docsByCollection.daily.length,
        html: renderCalendarSection(
          docsByCollection.daily, docsByCollection['custom_habits'] || [], habitCtx, day.todayKey),
      });
      continue;
    }
    sections.push(renderDocList(
      col.id,
      KNOWN_LABELS[col.id] || col.id,
      docsByCollection[col.id],
      { habitCtx, todayKey: day.todayKey },
    ));
  }

  sections.push({ id: 'rooms', label: 'Rooms', html: roomsSectionHtml });

  return {
    uid,
    authRecord,
    profileData,
    sections,
    dayKey: day.dayKey,
    isToday: day.isToday,
    todayKey: day.todayKey,
    todaySummary: { done: day.done, total: day.total },
  };
}

/** Just the Day section's HTML, for the report page's day stepper. */
async function loadDayFragment(uid, authRecord, dateKey) {
  const raw = await getAccountRaw(uid, authRecord);
  return buildDaySection(raw, dateKey);
}

// ---- Search across every account (server.js's live search box) ----

let _userCache = null; // { at: <ms>, users: [...] }
const CACHE_TTL_MS = 5 * 60 * 1000;

/**
 * Every account, merged from two sources: Firebase Auth (authoritative for
 * uid + email + createdAt/lastSignIn — every real account has one) and the
 * Firestore users/{uid}.displayName field (this app never calls
 * FirebaseAuth's own updateDisplayName — confirmed by grep across lib/ — so
 * Auth's own displayName is always empty and useless for a "search by
 * name" box on its own; ProfileScreen/edit_name_sheet.dart only ever
 * read/write the Firestore field). select('displayName', 'createdAt')
 * keeps that half of the fetch to two fields per doc instead of pulling
 * every profile in full - createdAt here is only ever used as a fallback
 * (see below), Auth's own metadata.creationTime is preferred whenever it's
 * present.
 *
 * Cached for CACHE_TTL_MS so the admin lookup homepage's filter/sort table
 * doesn't re-list every account on every keystroke — pass forceRefresh to
 * bypass it (e.g. a manual "refresh" action) right after a new signup you
 * want to find immediately.
 */
async function listAllUsers(forceRefresh) {
  if (!forceRefresh && _userCache && Date.now() - _userCache.at < CACHE_TTL_MS) {
    return _userCache.users;
  }

  const authUsers = new Map(); // uid -> {uid,email,createdAt,lastSignIn,disabled}
  let pageToken;
  do {
    const page = await auth().listUsers(1000, pageToken);
    for (const u of page.users) {
      authUsers.set(u.uid, {
        uid: u.uid,
        email: u.email || '',
        // Auth's metadata timestamps are plain date strings already (not a
        // Firestore Timestamp) - safe to hand straight to `new Date(...)`
        // client-side as-is.
        createdAt: u.metadata.creationTime || null,
        lastSignIn: u.metadata.lastSignInTime || null,
        disabled: !!u.disabled,
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);

  const namesSnap = await db().collection('users')
    .select('displayName', 'createdAt', 'level', 'currentStreak', 'gold',
      'totalHabitCompletions', 'tzOffsetMinutes', 'locale')
    .get();
  const names = new Map(); // uid -> displayName
  const firestoreCreatedAt = new Map(); // uid -> ISO string, fallback only
  namesSnap.forEach((doc) => {
    const d = doc.data();
    if (d.displayName) names.set(doc.id, d.displayName);
    if (d.createdAt) {
      const dt = typeof d.createdAt.toDate === 'function' ? d.createdAt.toDate() : new Date(d.createdAt);
      if (!Number.isNaN(dt.getTime())) firestoreCreatedAt.set(doc.id, dt.toISOString());
    }
  });

  const users = Array.from(authUsers.values()).map((u) => ({
    uid: u.uid,
    email: u.email,
    displayName: names.get(u.uid) || '',
    createdAt: u.createdAt || firestoreCreatedAt.get(u.uid) || null,
    lastSignIn: u.lastSignIn || null,
    disabled: u.disabled,
  }));
  // A Firestore profile with no matching Auth account shouldn't normally
  // happen, but a manually-deleted Auth user (e.g. via the console, not
  // this app's own deleteAccount flow) would leave one behind - include it
  // too so a search by name still finds it, uid as the only identifier
  // since there's no email to show.
  namesSnap.forEach((doc) => {
    if (!authUsers.has(doc.id)) {
      users.push({
        uid: doc.id,
        email: '',
        displayName: names.get(doc.id) || '',
        createdAt: firestoreCreatedAt.get(doc.id) || null,
        lastSignIn: null,
        disabled: false,
      });
    }
  });

  _userCache = { at: Date.now(), users };
  return users;
}

/** Substring match (case-insensitive) across email, display name, and uid. */
async function searchAccounts(q, limit = 25) {
  const users = await listAllUsers(false);
  const needle = q.trim().toLowerCase();
  if (!needle) {
    return users
      .slice()
      .sort((a, b) => (a.displayName || a.email).localeCompare(b.displayName || b.email))
      .slice(0, limit);
  }
  const scored = [];
  for (const u of users) {
    const hay = `${u.email} ${u.displayName} ${u.uid}`.toLowerCase();
    const idx = hay.indexOf(needle);
    if (idx !== -1) scored.push({ u, idx });
  }
  scored.sort((a, b) => a.idx - b.idx);
  return scored.slice(0, limit).map((s) => s.u);
}

module.exports = {
  resolveAccount,
  loadAccountRaw,
  loadAccountReport,
  loadDayFragment,
  buildDaySection,
  searchAccounts,
  listAllUsers,
};
