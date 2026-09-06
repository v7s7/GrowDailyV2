'use strict';

/**
 * Firebase Auth/Firestore access for the admin lookup tool.
 *
 * Assumes admin.initializeApp() has already been called by whichever entry
 * point required this module (lookup_user.js or server.js) - this file
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
  MOOD_META,
  QUADRANT_ORDER,
  toJsDate,
  effectiveTodayParts,
  calendarTodayParts,
  triageTasksForDay,
  habitScheduledOnParts,
  whyNotScheduled,
  summarizeHabitDay,
  renderDayCard,
  renderCalendarSection,
  renderUndoneSection,
  readUndoneReceipts,
  dayWriteContext,
  DAY_CUTOFF_HOUR,
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
 * authRecord: null instead of throwing - the caller falls back to
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
    throw new Error(`Nothing found for "${uid}". Checked both Firebase Auth and Firestore.`);
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
            <summary>Room ${escapeHtml(r.code)}${r.room.name ? ' · ' + escapeHtml(r.room.name) : ''}</summary>
            <div class="doc-id">${escapeHtml(r.code)}</div>
            <h3>Room</h3>
            ${renderFieldTable(r.room)}
            <h3>This account's participant entry</h3>
            ${renderFieldTable(r.participant)}
          </details>
        `).join('');
  } catch (e) {
    roomRows = [];
    roomsSectionHtml = `<p class="muted">Couldn't load this section: ${escapeHtml(e.message)}</p>`;
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
 * last-reported device offset and this app's habit day cutoff, never this
 * machine's clock), so the headline number can't disagree with what the
 * user's own phone is showing them.
 *
 * Habits and tasks run on two different clocks here, on purpose, because
 * the app itself uses two: habits on the flex day (effectiveTodayParts,
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
  // Read across all three of a habit-day's records rather than just
  // habitCompletions - see readHabitDay. A day whose square was painted
  // outside the reward window has no completion at all, and this card used
  // to render it as a flat "0/2 done" while the Rooms section on the very
  // same page credited it.
  const receiptsByKey = readUndoneReceipts(profileData);

  // Scheduled that day, by the app's own rule. summarizeHabitDay then UNIONS
  // this with every habit that left a trace on the day, so a habit archived
  // since, deleted since, or simply not due that weekday still appears if it
  // was marked. The old loop only walked custom_habits and only kept the
  // scheduled ones, so exactly those habits vanished from the card without a
  // word: the "my habit disappeared" ticket had no answer on the page.
  const scheduledIds = [];
  const habitById = {};
  for (const doc of habitDocs) {
    habitById[doc.id] = doc.data();
    if (habitScheduledOnParts(doc.data(), parts)) scheduledIds.push(doc.id);
  }
  const summary = summarizeHabitDay(dayData, scheduledIds, receiptsByKey, dayKey);
  const scheduledSet = new Set(scheduledIds);
  const habitRows = summary.rows;

  // Named, with the reason, instead of dropped. Two kinds land here: a habit
  // that exists but was not due (or not yet born, or already archived), and
  // one this account no longer has at all, which still shows up in old daily
  // docs and in undo receipts forever.
  const offSchedule = [];
  for (const doc of habitDocs) {
    if (scheduledSet.has(doc.id)) continue;
    const h = doc.data();
    const touched = habitRows.some((r) => r.habitId === doc.id && r.verdict !== 'none');
    const why = whyNotScheduled(h, parts);
    if (!why && !touched) continue;
    offSchedule.push({
      name: h.name || '(unnamed habit)',
      why: why || 'not scheduled that day',
      marked: touched,
    });
  }
  for (const r of habitRows) {
    if (scheduledSet.has(r.habitId) || habitById[r.habitId]) continue;
    offSchedule.push({
      name: `no longer in this account, ${String(r.habitId).slice(0, 8)}`,
      why: 'but it left a record on this day',
      marked: true,
    });
  }

  // The FOURTH record. habit_history is the per-habit chart mirror the app's
  // Progress and Life Timeline screens read, and the profile doc carries
  // four habitHistoryMarksV*BackfilledAt stamps, which is the app's own
  // evidence that it has drifted from the day docs before. Compared on every
  // row; the ledger prints it only where it disagrees.
  const mirror = {};
  for (const doc of (docsByCollection['habit_history'] || [])) {
    const marks = doc.data() && doc.data().marks;
    if (marks && typeof marks === 'object' && Object.prototype.hasOwnProperty.call(marks, dayKey)) {
      mirror[doc.id] = marks[dayKey] === true || marks[dayKey] === 1;
    }
  }
  const squareNotes = (dayData.squareNotes && typeof dayData.squareNotes === 'object')
    ? dayData.squareNotes : {};

  const taskDocs = docsByCollection['matrix_tasks'] || [];
  const taskParts = isToday ? calendarTodayParts(tz) : dayKeyParts(dayKey);
  const triage = triageTasksForDay(taskDocs, taskParts);

  // `allDoneToday` is a SINGLE stored flag with a single stored date beside
  // it (room_model.dart:752), so it can only ever answer for the one day it
  // was last computed. On any other day the honest answer is "this flag was
  // not about this day", and the card used to print a plain empty box, which
  // reads as "the room says they did not do it" while the banner two inches
  // above said the room counted the day. Two contradictory claims about the
  // same room on the same screen.
  //
  // Grading a past day off the room's own per-day ledger is the real fix and
  // is not in this pass; `known: false` at least stops the page asserting
  // something it cannot know.
  const rooms = roomRows.map((r) => {
    const known = r.participant.allDoneDate === dayKey;
    return {
      name: r.room.name || r.code,
      code: r.code,
      known,
      allDone: known && r.participant.allDoneToday === true,
      muted: r.participant.notificationsMuted === true,
    };
  });

  // `done` is what was PAID. The card prints it beside the room-counted
  // green squares rather than instead of them, so the two can visibly
  // disagree instead of one silently standing in for the other.
  const done = summary.done;
  const total = habitRows.length;

  return {
    id: 'today',
    label: 'Day',
    count: `${done}/${total}`,
    done,
    total,
    roomGreens: summary.roomGreens,
    // Whether this day's records disagree at all. `roomGreens > done` is NOT
    // the same question: on 2026-09-05 this account had one green square with
    // no completion AND one completion with no green square, so both numbers
    // are 2 while the two SETS are different. The tab has to flag that day.
    disagree: summary.gridOnly > 0 || summary.undone > 0,
    dayKey,
    isToday,
    todayKey: todayParts.key,
    html: renderDayCard({
      dayKey,
      isToday,
      todayKey: todayParts.key,
      habitRows,
      // Says WHICH kind of uncredited mark this is, when the day's own last
      // write can tell - see dayWriteContext. Only reaches the card when
      // there is a disagreement to explain; renderDayCard drops it otherwise.
      writeNote: (() => {
        const w = dayWriteContext(dayData, tz);
        if (!w) return '';
        if (w.key === dayKey && w.hour < DAY_CUTOFF_HOUR) {
          return `Tapped at ${w.clock}, before the ${DAY_CUTOFF_HOUR}:00 cutoff, so the app's reward day was still the day before. The Grid had already moved on to this date and put the "today" ring on it, so the square shown as today was not the day that pays.`;
        }
        if (w.key > dayKey) {
          return `Last written on ${w.key}, so this day was filled in after the fact. A backfilled square never pays, by design.`;
        }
        return '';
      })(),
      mood: dayData.mood ? MOOD_META[dayData.mood] : null,
      nightReviewDone: !!dayData.nightReviewDone,
      reflection: dayData.dailyReflection || '',
      xp: dayData.totalXpEarned || 0,
      gold: dayData.totalGoldEarned || 0,
      hasDoc: !!dayDoc,
      triage,
      taskDayKey: taskParts.key,
      rooms,
      habitCtx: raw.habitCtx,
      summary,
      offSchedule,
      mirrorFor: (id) => (Object.prototype.hasOwnProperty.call(mirror, id) ? mirror[id] : null),
      notesFor: (id) => (typeof squareNotes[id] === 'string' ? squareNotes[id] : ''),
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
  const tz = profileData && profileData.tzOffsetMinutes;

  // AUTHORED ORDER, not "whatever listCollections happened to return".
  //
  // The old order was Day, Auth, Profile, Un-marked completions, then the
  // subcollections in Firestore's own order, then Rooms. Which put the two
  // sections nobody opens (a six row Auth table, and a disclosure whose only
  // child is a raw field dump) at positions two and three, and Rooms, the
  // section every "the room disagrees" ticket ends in, at position ten,
  // off the end of a strip that could only show seven.
  //
  // Now: what happened, then the history, then the account's own things,
  // then the receipts, then everything that is a raw dump in one Raw tab.
  const sections = [];
  const day = buildDaySection(raw, dateKey);
  sections.push(day);

  const bySub = {};
  for (const col of subcollections) bySub[col.id] = col;

  // 'daily' gets a real month-by-month calendar instead of the generic flat
  // log list every other subcollection uses - see renderCalendarSection's
  // doc comment for why this one specifically has a natural calendar shape
  // the others don't.
  if (bySub.daily) {
    sections.push({
      id: 'daily',
      label: KNOWN_LABELS.daily,
      count: docsByCollection.daily.length,
      html: renderCalendarSection(
        docsByCollection.daily, docsByCollection['custom_habits'] || [], habitCtx, day.todayKey,
        readUndoneReceipts(profileData), tz),
    });
  }

  const docList = (id) => renderDocList(
    id, KNOWN_LABELS[id] || id, docsByCollection[id], { habitCtx, todayKey: day.todayKey });

  for (const id of ['custom_habits', 'matrix_tasks']) {
    if (bySub[id]) sections.push(docList(id));
  }

  sections.push({ id: 'rooms', label: 'Rooms', html: roomsSectionHtml });

  // Its own tab rather than a line inside Profile: "what did they take back"
  // is a question an admin arrives with, and burying the answer in the raw
  // field table (where it was, unlabelled, as one more map) is why nobody
  // could answer it. See renderUndoneSection for what an empty list does and
  // does not prove.
  sections.push({
    id: 'undone',
    label: 'Undo receipts',
    count: Object.keys(readUndoneReceipts(profileData)).length,
    html: renderUndoneSection(profileData, habitCtx),
  });

  // Everything whose honest description is "a raw dump of documents",
  // behind one tab instead of four. Nothing is deleted, it is demoted:
  // KNOWN_LABELS stays a purely cosmetic map with a raw-id fallback, so a
  // subcollection added to the app tomorrow still appears here on its own
  // with no change to this file.
  const rawParts = [];
  if (authRecord) {
    rawParts.push(`<h3>Sign-in account</h3><table class="fields"><tbody>
        <tr><th>uid</th><td>${escapeHtml(authRecord.uid)}</td></tr>
        <tr><th>email</th><td>${escapeHtml(authRecord.email || 'not set')}</td></tr>
        <tr><th>email verified</th><td>${authRecord.emailVerified}</td></tr>
        <tr><th>created</th><td>${escapeHtml(authRecord.metadata.creationTime)}</td></tr>
        <tr><th>last sign-in</th><td>${escapeHtml(authRecord.metadata.lastSignInTime)}</td></tr>
        <tr><th>disabled</th><td>${authRecord.disabled}</td></tr>
      </tbody></table>`);
  }
  rawParts.push('<h3>Profile document</h3>' + (profileData
    ? `<details class="doc"><summary>All raw profile fields</summary>${renderFieldTable(profileData)}</details>`
    : '<p class="muted">No Firestore profile doc.</p>'));
  for (const col of subcollections) {
    if (['daily', 'custom_habits', 'matrix_tasks'].includes(col.id)) continue;
    const listed = docList(col.id);
    rawParts.push(`<h3>${escapeHtml(listed.label)}<span class="h3-note">${listed.count} document${listed.count === 1 ? '' : 's'}</span></h3>${listed.html}`);
  }
  sections.push({ id: 'raw', label: 'Raw', html: rawParts.join('\n') });

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
 * uid + email + createdAt/lastSignIn - every real account has one) and the
 * Firestore users/{uid}.displayName field (this app never calls
 * FirebaseAuth's own updateDisplayName - confirmed by grep across lib/ - so
 * Auth's own displayName is always empty and useless for a "search by
 * name" box on its own; ProfileScreen/edit_name_sheet.dart only ever
 * read/write the Firestore field). select('displayName', 'createdAt')
 * keeps that half of the fetch to two fields per doc instead of pulling
 * every profile in full - createdAt here is only ever used as a fallback
 * (see below), Auth's own metadata.creationTime is preferred whenever it's
 * present.
 *
 * Cached for CACHE_TTL_MS so the admin lookup homepage's filter/sort table
 * doesn't re-list every account on every keystroke - pass forceRefresh to
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
