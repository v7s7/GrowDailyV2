'use strict';

/**
 * The server side of the Messages page: a message from the admin to
 * everyone, delivered one of two ways.
 *
 * Aziz, 2026-09-22: "let me as an admin send a message to all users, I
 * choose if it's a pop up when they open the app, or a notification".
 *
 *   Pop-up        broadcast/live, one public document every app follows
 *                 (lib/features/broadcast/broadcast_message.dart) and shows
 *                 ONCE, the next time it is opened. Two slots: `everyone`,
 *                 and `test` for the admin's own accounts, so trying a new
 *                 message on your own phone never takes down the one
 *                 everyone else is being shown. Anyone can read this
 *                 document, so a test audience is stored as SHA-256 hashes
 *                 of the uids, never the uids themselves.
 *   Notification  sent from THIS tool, through the Admin SDK, to every
 *                 device token the phones mirror to users/{uid}/fcmTokens
 *                 (lib/core/services/push_notification_service.dart). No
 *                 Cloud Function and no deploy: phones already in people's
 *                 hands register tokens today, so this works with every
 *                 build since 67.
 *
 * What a notification respects, person by person, the same way a room push
 * does (functions/push_policy.js is required below rather than copied, so
 * the two can never disagree): the app's own "all notifications" switch,
 * and quiet hours. Someone inside their quiet hours is HELD, not skipped
 * (page item 6, Aziz, 2026-09-24: someone asleep at the send used to never
 * get it). This tool runs on a Mac and cannot wake at 07:00, so it writes
 * who it held, and until when, into the message's history row and asks the
 * holdBroadcast Cloud Function to deliver each one when their quiet hours
 * end (functions/index.js). If that function does not answer (not deployed
 * yet), the page says those people were skipped, as before.
 *
 * One notification to everyone per 24 hours (same page item: there was no
 * daily limit). A copy held overnight lands the next morning, and the next
 * message cannot go until a day after the first, so nobody gets two in a
 * day. A test is not counted.
 *
 * Writes: broadcast/live (replaced whole inside a transaction, the same
 * rule wording.js's doc comment explains) and broadcast_log/{id}, one row
 * per send, admin only. Never an account: dead device tokens are counted
 * and reported, not pruned. The room-push functions prune them on their
 * own sends, and this tool keeps its rule of never changing an account.
 */

const crypto = require('node:crypto');

const Rules = require('../wording/rules');
// Pure (no requires of its own), so reaching into the functions package is
// just reading one more file of this repo, not loading Cloud Functions.
const { heldUntilMs, isQuietHoursNow } = require('../../../functions/push_policy');

const LIVE_DOC = 'broadcast/live';
const LOG_COLLECTION = 'broadcast_log';
const LOG_LIMIT = 40;

const KINDS = ['popup', 'notification'];
const AUDIENCES = ['everyone', 'test'];
const SLOTS = ['everyone', 'test'];

/** How long a pop-up keeps showing to people who have not opened the app yet. */
const POPUP_DAYS = [1, 3, 7, 14, 30];
const DEFAULT_POPUP_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Longest text accepted. A notification is sized to what a lock screen
 * shows before it cuts the text (a title on one line, about four lines of
 * body); a pop-up scrolls, so it can say more.
 */
const LIMITS = Object.freeze({
  popup: Object.freeze({ title: 80, body: 700, button: 24 }),
  notification: Object.freeze({ title: 60, body: 240 }),
});

const DEFAULT_BUTTON = Object.freeze({ ar: 'تمام', en: 'OK' });

/** Test accounts per send. A test is a handful of the admin's own phones. */
const MAX_TESTERS = 5;

/**
 * One notification to everyone in this long. See the file's doc comment.
 * It also covers what a shorter "same words again" window used to: a double
 * click, a second tab, a retry after a slow answer.
 */
const EVERYONE_GAP_MS = 24 * 60 * 60 * 1000;

/** FCM's own ceiling per sendEach call. */
const FCM_BATCH = 500;

/**
 * How long a notification may wait for a phone that is off or offline.
 * Without this, FCM keeps it for four weeks: a phone switched on days later
 * would ring with an old message, in the middle of the night, long after
 * the quiet-hours check that let it through.
 */
const NOTIFICATION_TTL_MS = 12 * 60 * 60 * 1000;

/**
 * How long a TEST pop-up stays up. A draft nobody has approved sits in a
 * public document while it is up, and every phone caches it, so a test is
 * two hours, never the days an announcement gets.
 */
const TEST_POPUP_HOURS = 2;

/** Answers that mean the app is gone from that device for good. */
const GONE_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** A request the page should show as a message, not as a server fault. */
class BroadcastInputError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

// ---- Checking what was written ---------------------------------------------

const EM_DASH = String.fromCharCode(0x2014);
const ARABIC_INDIC_THREE = String.fromCharCode(0x0663);

/**
 * The house-style reminders that apply to [kind]. Notifications are the one
 * place the app writes Arabic-Indic digits (see the wording rules' own
 * digits reminder), so that one reminder is dropped for them. Found by what
 * it matches rather than by its wording or position, so a reworded or
 * reordered rules file cannot silently change which one is dropped.
 */
function styleRulesFor(kind) {
  const all = Rules.ARABIC_STYLE || [];
  if (kind !== 'notification') return all;
  return all.filter((rule) => {
    rule.test.lastIndex = 0;
    return !rule.test.test(ARABIC_INDIC_THREE);
  });
}

/**
 * Checks one message before it can go anywhere.
 *
 * Arabic title and body are required: the app is Arabic first, and a
 * phone whose language is Arabic has nothing else to show. English is
 * optional, but as a pair: an English title with no English body would
 * put an Arabic body under an English heading. Left empty, English phones
 * get the Arabic.
 *
 * Returns { ok, message, errors, warnings }. [message] is what would be
 * stored and sent: every field normalized, the pop-up's button filled in
 * with the default when left empty, its days checked against POPUP_DAYS.
 */
function checkMessage(kind, raw) {
  const errors = [];
  const warnings = [];
  if (!KINDS.includes(kind)) {
    return { ok: false, message: null, errors: ['Unknown kind: ' + kind], warnings };
  }
  const src = raw && typeof raw === 'object' ? raw : {};
  const limits = LIMITS[kind];
  const message = {
    titleAr: Rules.normalizeText(src.titleAr),
    bodyAr: Rules.normalizeText(src.bodyAr),
    titleEn: Rules.normalizeText(src.titleEn),
    bodyEn: Rules.normalizeText(src.bodyEn),
  };

  if (!message.titleAr) errors.push('Write an Arabic title.');
  if (!message.bodyAr) errors.push('Write the Arabic message.');
  if (Boolean(message.titleEn) !== Boolean(message.bodyEn)) {
    errors.push('English needs both a title and a message, or neither (then English phones get the Arabic).');
  }

  const fields = [
    ['titleAr', 'Arabic title', limits.title],
    ['bodyAr', 'Arabic message', limits.body],
    ['titleEn', 'English title', limits.title],
    ['bodyEn', 'English message', limits.body],
  ];

  if (kind === 'popup') {
    message.buttonAr = Rules.normalizeText(src.buttonAr) || DEFAULT_BUTTON.ar;
    message.buttonEn = Rules.normalizeText(src.buttonEn) || DEFAULT_BUTTON.en;
    fields.push(['buttonAr', 'Arabic button', limits.button]);
    fields.push(['buttonEn', 'English button', limits.button]);
    const days = src.days == null || src.days === '' ? DEFAULT_POPUP_DAYS : Number(src.days);
    if (!POPUP_DAYS.includes(days)) {
      errors.push('Show it for one of: ' + POPUP_DAYS.join(', ') + ' days.');
    }
    message.days = POPUP_DAYS.includes(days) ? days : DEFAULT_POPUP_DAYS;
  }

  for (const [key, label, max] of fields) {
    const text = message[key];
    if (text.includes(EM_DASH)) {
      errors.push(label + ' has an em dash. Use a comma, a colon or a full stop.');
    }
    if (text.length > max) {
      errors.push(label + ' is too long: ' + text.length + ' characters, the limit is ' + max + '.');
    }
    if (kind === 'notification' && key.startsWith('title') && text.includes('\n')) {
      errors.push(label + ' is one line on a lock screen. Take out the line break.');
    }
  }

  const rules = styleRulesFor(kind);
  for (const key of ['titleAr', 'bodyAr', 'buttonAr']) {
    const text = message[key];
    if (!text) continue;
    for (const rule of rules) {
      rule.test.lastIndex = 0;
      if (rule.test.test(text) && !warnings.includes(rule.say)) warnings.push(rule.say);
    }
  }

  return { ok: errors.length === 0, message, errors, warnings };
}

/**
 * The language a person gets: English only for a phone set to English when
 * there IS an English version. Everyone else, a phone that never reported
 * its language included, gets the Arabic: 23 of the 28 accounts that do
 * report one are Arabic (2026-09-22), and every phone with a device token
 * reports one.
 */
function languageFor(locale, message) {
  return locale === 'en' && message.bodyEn ? 'en' : 'ar';
}

/** One message's text in one language. */
function textFor(message, lang) {
  const en = lang === 'en' && message.bodyEn;
  return {
    title: en ? message.titleEn : message.titleAr,
    body: en ? message.bodyEn : message.bodyAr,
  };
}

/**
 * SHA-256 of a uid, hex. What the public pop-up document holds for a test
 * audience; the app hashes its own uid the same way to ask "is this me".
 */
function uidHash(uid) {
  return crypto.createHash('sha256').update(String(uid), 'utf8').digest('hex');
}

/** Firebase uids are 28 letters and digits; this accepts a little either side. */
const UID_RE = /^[A-Za-z0-9]{10,64}$/;

function checkTesters(testers) {
  const list = Array.isArray(testers) ? testers.map(String) : [];
  const unique = Array.from(new Set(list));
  if (unique.length === 0) {
    throw new BroadcastInputError('Pick at least one account to test on.');
  }
  if (unique.length > MAX_TESTERS) {
    throw new BroadcastInputError('A test goes to at most ' + MAX_TESTERS + ' accounts.');
  }
  for (const uid of unique) {
    if (!UID_RE.test(uid)) throw new BroadcastInputError('Not an account id: ' + uid);
  }
  return unique;
}

function checkAudience(audience) {
  if (!AUDIENCES.includes(audience)) {
    throw new BroadcastInputError('Send to "everyone" or "test".');
  }
}

/** A short id that sorts by time: n_ for a notification, p_ for a pop-up. */
function newId(kind, nowMs) {
  const prefix = kind === 'popup' ? 'p_' : 'n_';
  return prefix + Math.floor(nowMs).toString(36) + '_' + crypto.randomBytes(3).toString('hex');
}

/** Same words, same key, whatever the whitespace around them. */
function contentKey(kind, message) {
  const parts = [kind, message.titleAr, message.bodyAr, message.titleEn, message.bodyEn];
  return crypto.createHash('sha256').update(JSON.stringify(parts), 'utf8').digest('hex').slice(0, 32);
}

// ---- Who a notification reaches ---------------------------------------------

/** The only account fields a send reads. */
const ACCOUNT_FIELDS = ['locale', 'tzOffsetMinutes', 'notificationSettings'];

function msOf(value) {
  if (value == null) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return null;
}

function isoOf(value) {
  const ms = msOf(value);
  return ms == null ? null : new Date(ms).toISOString();
}

/**
 * Every account that has a device, with what a send needs to know about it.
 *
 * One collection-group query finds every device token in the project (148 ms
 * for all of them, 2026-09-22) and settles who owns each one: a token listed
 * under two accounts, the phone that changed hands without the old account's
 * sign-out landing, belongs to whichever account registered it last. Only
 * those owners' account documents are then read, so the reads follow the
 * number of PHONES rather than the number of accounts (105 of 121 accounts
 * have no phone registered). A token whose owner's account document is gone
 * is dropped: that person deleted their account.
 *
 * [onlyUids] narrows the result to those accounts, for a test send. The
 * token scan still covers everyone, because "does this tester still own
 * this phone" can only be answered by looking at every account's tokens.
 */
async function collectAccounts(db, onlyUids = null) {
  const tokensSnap = await db.collectionGroup('fcmTokens').get();
  const owner = new Map();
  for (const doc of tokensSnap.docs) {
    const parent = doc.ref && doc.ref.parent && doc.ref.parent.parent;
    if (!parent) continue;
    const data = typeof doc.data === 'function' ? doc.data() || {} : {};
    const updatedMs = msOf(data.updatedAt) || 0;
    const held = owner.get(doc.id);
    if (held && held.updatedMs >= updatedMs) continue;
    owner.set(doc.id, {
      uid: parent.id,
      updatedMs,
      platform: typeof data.platform === 'string' ? data.platform : null,
    });
  }

  const uids = onlyUids
    ? Array.from(new Set(onlyUids))
    : Array.from(new Set(Array.from(owner.values(), (o) => o.uid)));
  const refs = uids.map((uid) => db.collection('users').doc(uid));
  const snaps = refs.length
    ? await db.getAll(...refs, { fieldMask: ACCOUNT_FIELDS })
    : [];

  const byUid = new Map();
  for (const snap of snaps) {
    if (!snap.exists) continue;
    const data = snap.data() || {};
    byUid.set(snap.id, {
      uid: snap.id,
      locale: typeof data.locale === 'string' ? data.locale : null,
      tzOffsetMinutes: typeof data.tzOffsetMinutes === 'number' ? data.tzOffsetMinutes : undefined,
      settings: data.notificationSettings && typeof data.notificationSettings === 'object'
        ? data.notificationSettings
        : undefined,
      tokens: [],
    });
  }
  for (const [token, held] of owner) {
    const account = byUid.get(held.uid);
    if (account) account.tokens.push({ token, platform: held.platform, updatedMs: held.updatedMs });
  }
  return Array.from(byUid.values());
}

/**
 * How many accounts exist at all, for the "no phone registered" count. One
 * aggregation query (billed as a handful of reads) rather than reading every
 * account document, which at 100,000 accounts would be a day's free quota
 * for one look at this page. Null when it cannot be counted; the page then
 * leaves that number out rather than guessing.
 */
async function countAccounts(db) {
  try {
    const snap = await db.collection('users').count().get();
    const total = snap.data().count;
    return typeof total === 'number' ? total : null;
  } catch (err) {
    return null;
  }
}

/**
 * Who gets the notification, and why everyone else does not. Pure: the
 * accounts and a clock in, a list of devices and the counts out.
 *
 * Everyone: skips an account whose app switch for all notifications is off
 * (`masterEnabled: false`), and holds one inside its quiet hours right now,
 * listing it in [held] with the moment its quiet hours end (see this file's
 * doc comment). A test: only the test accounts, and neither rule applies,
 * because the person testing asked for it now.
 *
 * A device token listed under two accounts (a phone that switched accounts
 * without the old one's sign-out landing) is sent to once, under whichever
 * account wrote it last.
 */
function planRecipients(accounts, {
  audience = 'everyone',
  testUids = [],
  nowMs = Date.now(),
  totalAccounts = null,
} = {}) {
  const testSet = new Set(testUids);
  const pool = audience === 'test'
    ? accounts.filter((a) => testSet.has(a.uid))
    : accounts;

  const counts = {
    accounts: pool.length,
    withPhone: 0,
    phones: 0,
    ar: 0,
    en: 0,
    quiet: 0,
    off: 0,
    noPhone: 0,
    quietPhones: 0,
    offPhones: 0,
  };

  const owner = new Map();
  for (const account of pool) {
    for (const t of account.tokens) {
      const held = owner.get(t.token);
      if (!held || t.updatedMs > held.updatedMs) owner.set(t.token, { uid: account.uid, updatedMs: t.updatedMs });
    }
  }

  const devices = [];
  const held = [];
  // Accounts with no phone at all never reach [accounts] (see
  // collectAccounts), so they are counted from the project's own total.
  if (audience !== 'test' && totalAccounts != null) {
    counts.accounts = totalAccounts;
    counts.noPhone += Math.max(0, totalAccounts - pool.length);
  }
  for (const account of pool) {
    const tokens = account.tokens.filter((t) => owner.get(t.token).uid === account.uid);
    if (tokens.length === 0) {
      counts.noPhone++;
      continue;
    }
    counts.withPhone++;
    if (audience !== 'test') {
      if (account.settings && account.settings.masterEnabled === false) {
        counts.off++;
        counts.offPhones += tokens.length;
        continue;
      }
      if (isQuietHoursNow(account.settings, account.tzOffsetMinutes, nowMs)) {
        counts.quiet++;
        counts.quietPhones += tokens.length;
        held.push({
          uid: account.uid,
          atMs: heldUntilMs(account.settings, account.tzOffsetMinutes, nowMs),
        });
        continue;
      }
    }
    const locale = account.locale === 'en' ? 'en' : 'ar';
    for (const t of tokens) {
      devices.push({ uid: account.uid, token: t.token, locale });
      counts.phones++;
      counts[locale]++;
    }
  }
  return { devices, counts, held };
}

/** What the page shows before anything is sent. */
function reachSummary(accounts, nowMs = Date.now(), totalAccounts = null) {
  return planRecipients(accounts, { audience: 'everyone', nowMs, totalAccounts })
    .counts;
}

/**
 * The FCM message for one device. The room pushes' own shape, plus an
 * expiry: see NOTIFICATION_TTL_MS for why an announcement must not arrive
 * days late.
 */
function fcmMessage(device, message, id, nowMs = Date.now()) {
  const { title, body } = textFor(message, languageFor(device.locale, message));
  return {
    token: device.token,
    notification: { title, body },
    data: { type: 'broadcast', id },
    android: { ttl: NOTIFICATION_TTL_MS },
    apns: {
      headers: {
        'apns-expiration': String(Math.floor((nowMs + NOTIFICATION_TTL_MS) / 1000)),
      },
      payload: { aps: { sound: 'default' } },
    },
  };
}

/**
 * Refuses a second notification to everyone inside [EVERYONE_GAP_MS] of the
 * last one, saying when the next may go (Bahrain time, the admin's clock).
 * Reads the day's history rows only: one range on `at`, no index needed.
 */
async function refuseWithinGap(db, nowMs) {
  const since = new Date(nowMs - EVERYONE_GAP_MS);
  const snap = await db.collection(LOG_COLLECTION).where('at', '>=', since).get();
  let last = null;
  for (const doc of snap.docs) {
    const row = doc.data() || {};
    if (row.kind !== 'notification' || row.audience !== 'everyone') continue;
    const at = msOf(row.at);
    if (at != null && nowMs - at < EVERYONE_GAP_MS && (last == null || at > last)) last = at;
  }
  if (last == null) return;
  const next = new Date(last + EVERYONE_GAP_MS);
  throw new BroadcastInputError(
    'One notification to everyone per 24 hours, so nobody gets two in a day. ' +
    'The last one went ' + NEXT_FMT.format(new Date(last)) + '; the next can go ' +
    NEXT_FMT.format(next) + ' (Bahrain). A test can go any time.',
    409,
  );
}

const NEXT_FMT = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Bahrain',
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

/**
 * Sends a notification to everyone, or to the test accounts.
 *
 * [messaging] is admin.messaging() (a stand-in in the tests). [dryRun]
 * asks FCM to check every message and every device token without
 * delivering anything; a dry run is never logged. [hold] asks the
 * holdBroadcast Cloud Function to queue the people held for quiet hours:
 * given the message id, it answers { queued, failed } or throws.
 *
 * Returns { ok, id, counts, sent, gone, failed, errors, held, warnings },
 * where [gone] is devices the app has been removed from, [errors] the other
 * failures by FCM's own code, and [held] what became of the people held for
 * quiet hours: { people, queued, failed } or { people, error }.
 */
async function sendNotification(db, messaging, {
  message: raw,
  audience,
  testers,
  nowMs = Date.now(),
  dryRun = false,
  accounts: givenAccounts = null,
  hold = null,
}) {
  checkAudience(audience);
  const check = checkMessage('notification', raw);
  if (!check.ok) throw new BroadcastInputError(check.errors.join(' '));
  const message = check.message;
  const testUids = audience === 'test' ? checkTesters(testers) : [];
  const key = contentKey('notification', message);
  if (audience === 'everyone' && !dryRun) {
    await refuseWithinGap(db, nowMs);
  }

  const accounts = givenAccounts ||
    await collectAccounts(db, audience === 'test' ? testUids : null);
  const totalAccounts = audience === 'test' ? null : await countAccounts(db);
  const { devices, counts, held } = planRecipients(accounts, {
    audience,
    testUids,
    nowMs,
    totalAccounts,
  });
  if (devices.length === 0 && held.length === 0) {
    throw new BroadcastInputError(audience === 'test'
      ? 'None of the test accounts has a phone registered for notifications. Open the app on that phone once, signed in, and allow notifications.'
      : 'No phone can receive it. ' + describeSkips(counts));
  }

  const id = newId('notification', nowMs);
  const row = {
    kind: 'notification',
    audience,
    titleAr: message.titleAr,
    bodyAr: message.bodyAr,
    titleEn: message.titleEn,
    bodyEn: message.bodyEn,
    at: new Date(nowMs),
    contentKey: key,
    testers: testUids,
    counts,
    // Who waits for their quiet hours to end, read by holdBroadcast.
    held,
  };
  // The history row goes in BEFORE the first message. A send that dies half
  // way (this tool stopped, the network gone) would otherwise leave nothing
  // behind, and the 24-hour check above, which reads exactly these rows,
  // would happily send the whole thing again on the next press.
  if (!dryRun) {
    await db.collection(LOG_COLLECTION).doc(id).set({ ...row, sending: true, result: null });
  }

  const result = { sent: 0, gone: 0, failed: 0, errors: {} };
  for (let i = 0; i < devices.length; i += FCM_BATCH) {
    const chunk = devices.slice(i, i + FCM_BATCH);
    const batch = await messaging.sendEach(
      chunk.map((d) => fcmMessage(d, message, id, nowMs)),
      dryRun,
    );
    (batch.responses || []).forEach((r) => {
      if (r.success) {
        result.sent++;
        return;
      }
      const code = (r.error && (r.error.code || r.error.message)) || 'unknown';
      if (GONE_CODES.has(code)) {
        result.gone++;
      } else {
        result.failed++;
        result.errors[code] = (result.errors[code] || 0) + 1;
      }
    });
  }

  if (!dryRun) {
    await db.collection(LOG_COLLECTION).doc(id)
      .set({ ...row, sending: false, result });
  }

  // The people in quiet hours, queued server side for when theirs end. Only
  // after the row above is written: holdBroadcast reads the list from it.
  let heldOutcome = null;
  if (held.length > 0 && !dryRun) {
    heldOutcome = { people: held.length };
    try {
      if (typeof hold !== 'function') throw new Error('no hold service configured');
      const answer = await hold(id);
      heldOutcome.queued = Number(answer && answer.queued) || 0;
      heldOutcome.failed = Number(answer && answer.failed) || 0;
    } catch (err) {
      heldOutcome.error = String((err && err.message) || err);
    }
    await db.collection(LOG_COLLECTION).doc(id)
      .set({ heldResult: heldOutcome }, { merge: true });
  }
  return {
    ok: true, id, dryRun, counts, ...result, held: heldOutcome, warnings: check.warnings,
  };
}

/**
 * Asks the holdBroadcast Cloud Function to queue a message's held people.
 * A plain HTTPS call in the callable protocol; the function needs no caller
 * identity (see functions/index.js). Throws when it does not answer, most
 * often because it has not been deployed yet.
 */
function holdViaFunction(projectId, fetchImpl = globalThis.fetch) {
  const url = 'https://us-central1-' + encodeURIComponent(projectId) +
    '.cloudfunctions.net/holdBroadcast';
  return async (id) => {
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { id } }),
      signal: AbortSignal.timeout(20000),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok || !body || !body.result) {
      const why = body && body.error && (body.error.message || body.error.status);
      throw new Error('holdBroadcast answered ' + res.status + (why ? ': ' + why : ''));
    }
    return body.result;
  };
}

function describeSkips(counts) {
  const parts = [];
  if (counts.off) parts.push(counts.off + ' with notifications off in the app');
  if (counts.noPhone) parts.push(counts.noPhone + ' with no phone registered');
  return parts.length ? 'Of ' + counts.accounts + ' accounts: ' + parts.join(', ') + '.' : '';
}

// ---- The pop-up ---------------------------------------------------------------

/** One stored pop-up, as the page shows it. Null when there is none. */
function shapePopup(p, nowMs = Date.now()) {
  if (!p || typeof p !== 'object' || typeof p.id !== 'string') return null;
  const endsMs = msOf(p.endsAt);
  const startsMs = msOf(p.startsAt);
  return {
    id: p.id,
    titleAr: p.titleAr || '',
    bodyAr: p.bodyAr || '',
    titleEn: p.titleEn || '',
    bodyEn: p.bodyEn || '',
    buttonAr: p.buttonAr || '',
    buttonEn: p.buttonEn || '',
    startsAt: isoOf(p.startsAt),
    endsAt: isoOf(p.endsAt),
    testers: Array.isArray(p.testUidHashes) ? p.testUidHashes.length : 0,
    active: (startsMs == null || startsMs <= nowMs) && (endsMs == null || nowMs < endsMs),
  };
}

function shapeLogRow(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    kind: d.kind === 'popup' ? 'popup' : 'notification',
    audience: d.audience === 'test' ? 'test' : 'everyone',
    titleAr: d.titleAr || '',
    bodyAr: d.bodyAr || '',
    titleEn: d.titleEn || '',
    bodyEn: d.bodyEn || '',
    at: isoOf(d.at),
    endsAt: isoOf(d.endsAt),
    stoppedAt: isoOf(d.stoppedAt),
    days: typeof d.days === 'number' ? d.days : null,
    testers: Array.isArray(d.testers) ? d.testers.length : 0,
    counts: d.counts || null,
    result: d.result || null,
    sending: d.sending === true,
    // People held for quiet hours: what the tool asked for (heldResult), and
    // what deliverHeldBroadcast has counted since, as each hold ended.
    held: d.heldResult
      ? {
        ...d.heldResult,
        sent: typeof d.heldSent === 'number' ? d.heldSent : 0,
        dropped: typeof d.heldDropped === 'number' ? d.heldDropped : 0,
      }
      : null,
  };
}

/** The live pop-ups and the history, for the page. */
async function readMessages(db, nowMs = Date.now()) {
  const [liveSnap, logSnap] = await Promise.all([
    db.doc(LIVE_DOC).get(),
    db.collection(LOG_COLLECTION).orderBy('at', 'desc').limit(LOG_LIMIT).get(),
  ]);
  const data = liveSnap.exists ? liveSnap.data() || {} : {};
  return {
    live: {
      everyone: shapePopup(data.everyone, nowMs),
      test: shapePopup(data.test, nowMs),
      version: Number.isInteger(data.version) ? data.version : 0,
    },
    history: logSnap.docs.map(shapeLogRow),
  };
}

/**
 * The stored document, ready to be written back whole. The slot not being
 * changed is carried over exactly as stored (its dates stay Firestore
 * timestamps), and a slot holding something unreadable is cleared.
 */
function liveForWrite(data) {
  const src = data && typeof data === 'object' ? data : {};
  const keep = (p) => (p && typeof p === 'object' && typeof p.id === 'string' ? p : null);
  return {
    everyone: keep(src.everyone),
    test: keep(src.test),
    version: Number.isInteger(src.version) ? src.version : 0,
  };
}

/**
 * Puts a pop-up up: for everyone (replacing the one they are shown now, if
 * any) or for the test accounts (replacing only the previous test).
 * A new id every time, so a phone that already showed the old one shows
 * this one too.
 */
async function publishPopup(db, FieldValue, {
  message: raw,
  audience,
  testers,
  nowMs = Date.now(),
}) {
  checkAudience(audience);
  const check = checkMessage('popup', raw);
  if (!check.ok) throw new BroadcastInputError(check.errors.join(' '));
  const message = check.message;
  const testUids = audience === 'test' ? checkTesters(testers) : [];
  const id = newId('popup', nowMs);
  const startsAt = new Date(nowMs);
  // A test is hours, not days: see TEST_POPUP_HOURS.
  const endsAt = new Date(nowMs + (audience === 'test'
    ? TEST_POPUP_HOURS * 60 * 60 * 1000
    : message.days * DAY_MS));

  const popup = {
    id,
    titleAr: message.titleAr,
    bodyAr: message.bodyAr,
    titleEn: message.titleEn,
    bodyEn: message.bodyEn,
    buttonAr: message.buttonAr,
    buttonEn: message.buttonEn,
    startsAt,
    endsAt,
  };
  if (audience === 'test') popup.testUidHashes = testUids.map(uidHash);

  const liveRef = db.doc(LIVE_DOC);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = liveForWrite(snap.exists ? snap.data() : null);
    // The same words, still up, put up again: a retry after a slow answer
    // or a second press. A new id means every phone that already showed it
    // shows it a second time, so this is refused rather than published.
    // A test may always be repeated; that is what testing is.
    if (audience === 'everyone' && sameWords(live.everyone, popup) &&
        isUp(live.everyone, nowMs)) {
      throw new BroadcastInputError(
        'This pop-up is already showing to everyone. Change the words to put a new one up.',
        409,
      );
    }
    live[audience] = popup;
    tx.set(liveRef, {
      everyone: live.everyone,
      test: live.test,
      version: live.version + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  await db.collection(LOG_COLLECTION).doc(id).set({
    kind: 'popup',
    audience,
    titleAr: message.titleAr,
    bodyAr: message.bodyAr,
    titleEn: message.titleEn,
    bodyEn: message.bodyEn,
    buttonAr: message.buttonAr,
    buttonEn: message.buttonEn,
    days: message.days,
    at: startsAt,
    endsAt,
    contentKey: contentKey('popup', message),
    testers: testUids,
  });
  return { ok: true, id, endsAt: endsAt.toISOString(), warnings: check.warnings };
}

/** Whether two pop-ups say exactly the same thing. */
function sameWords(a, b) {
  if (!a || !b) return false;
  return ['titleAr', 'bodyAr', 'titleEn', 'bodyEn', 'buttonAr', 'buttonEn']
    .every((key) => (a[key] || '') === (b[key] || ''));
}

/** Whether a stored pop-up is still inside its window. */
function isUp(popup, nowMs) {
  if (!popup) return false;
  const endsMs = msOf(popup.endsAt);
  return endsMs == null || nowMs < endsMs;
}

/**
 * Takes a pop-up down before its time: nobody who has not seen it yet will.
 * The history row keeps it, marked with when it was stopped.
 */
async function stopPopup(db, FieldValue, { slot, nowMs = Date.now() }) {
  if (!SLOTS.includes(slot)) throw new BroadcastInputError('Unknown pop-up: ' + slot);
  const liveRef = db.doc(LIVE_DOC);
  const stoppedId = await db.runTransaction(async (tx) => {
    const snap = await tx.get(liveRef);
    const live = liveForWrite(snap.exists ? snap.data() : null);
    const current = live[slot];
    if (!current) return null;
    live[slot] = null;
    tx.set(liveRef, {
      everyone: live.everyone,
      test: live.test,
      version: live.version + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return current.id;
  });
  if (stoppedId) {
    await db.collection(LOG_COLLECTION).doc(stoppedId).set({ stoppedAt: new Date(nowMs) }, { merge: true });
  }
  return { ok: true, stopped: stoppedId };
}

/**
 * Whether a phone can read broadcast/live right now, asked the way a phone
 * asks: with no credentials at all. 'open' (the rule is deployed; a missing
 * document still answers 404 when reading is allowed), 'closed' (403: the
 * rule is not live yet, so no pop-up can show anywhere), or 'unknown'.
 * The same check the Wording page runs for its own document.
 */
async function phonesCanRead(projectId, fetchImpl = globalThis.fetch) {
  if (!projectId || typeof fetchImpl !== 'function') return 'unknown';
  const url = 'https://firestore.googleapis.com/v1/projects/' +
    encodeURIComponent(projectId) + '/databases/(default)/documents/' + LIVE_DOC;
  try {
    const res = await fetchImpl(url, { signal: AbortSignal.timeout(6000) });
    if (res.status === 200 || res.status === 404) return 'open';
    if (res.status === 403) return 'closed';
    return 'unknown';
  } catch {
    return 'unknown';
  }
}

module.exports = {
  LIVE_DOC,
  LOG_COLLECTION,
  NOTIFICATION_TTL_MS,
  TEST_POPUP_HOURS,
  LIMITS,
  POPUP_DAYS,
  DEFAULT_POPUP_DAYS,
  DEFAULT_BUTTON,
  MAX_TESTERS,
  EVERYONE_GAP_MS,
  FCM_BATCH,
  BroadcastInputError,
  checkMessage,
  languageFor,
  textFor,
  uidHash,
  contentKey,
  collectAccounts,
  countAccounts,
  planRecipients,
  reachSummary,
  fcmMessage,
  sendNotification,
  holdViaFunction,
  shapePopup,
  readMessages,
  publishPopup,
  stopPopup,
  phonesCanRead,
};
