'use strict';

/**
 * The Messages page: what a message is checked against, who a notification
 * reaches (and who it deliberately skips), what a send does, what a pop-up
 * publish does to the document every app follows, and that the page and its
 * script load at all.
 *
 * Everything runs against in-memory stand-ins for Firestore and FCM, never
 * the real project. What matters about the real ones is modelled: set()
 * without merge replaces a document, a collection-group query finds every
 * fcmTokens doc with its owner as the parent's parent, and sendEach answers
 * one response per message in order.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const Broadcast = require('../lib/broadcast');
const { renderBroadcastPage } = require('../lib/broadcast_page');

const EM_DASH = String.fromCharCode(0x2014);
const FieldValue = { serverTimestamp: () => ({ __serverTimestamp: true }) };

// 2026-09-22 12:00 in Bahrain (UTC+3), a daytime minute for everyone below.
const NOON_BAHRAIN = Date.UTC(2026, 8, 22, 9, 0);
// 23:30 in Bahrain: inside the default 22:00 to 07:00 quiet window.
const LATE_BAHRAIN = Date.UTC(2026, 8, 22, 20, 30);

// ---- An in-memory Firestore, just enough for lib/broadcast.js --------------

function clone(value) {
  if (value && value.__serverTimestamp) return new Date(0);
  if (value instanceof Date) return new Date(value.getTime());
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = clone(v);
    return out;
  }
  return value;
}

function fakeDb() {
  const docs = new Map();

  function snapOf(p) {
    const data = docs.get(p);
    const parts = p.split('/');
    return {
      id: parts[parts.length - 1],
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : clone(data)),
      get: (field) => (data === undefined ? undefined : clone(data[field])),
      ref: refOf(p),
    };
  }

  function refOf(p) {
    const parts = p.split('/');
    const parentPath = parts.slice(0, -1).join('/');
    return {
      path: p,
      id: parts[parts.length - 1],
      get parent() {
        return collectionOf(parentPath);
      },
      get: async () => snapOf(p),
      set: async (data, opts) => {
        const merge = opts && opts.merge;
        docs.set(p, merge ? { ...(docs.get(p) || {}), ...clone(data) } : clone(data));
      },
      collection: (name) => collectionOf(p + '/' + name),
    };
  }

  function childrenOf(colPath) {
    const depth = colPath.split('/').length + 1;
    return Array.from(docs.keys())
      .filter((k) => k.startsWith(colPath + '/') && k.split('/').length === depth)
      .sort();
  }

  function query(listPaths, filters = [], order = null, limit = null) {
    return {
      where: (field, op, value) => {
        assert.ok(op === '==' || op === '>=', 'the fake only knows == and >=');
        return query(listPaths, [...filters, [field, op, value]], order, limit);
      },
      orderBy: (field, dir) => query(listPaths, filters, [field, dir || 'asc'], limit),
      limit: (n) => query(listPaths, filters, order, n),
      select: () => query(listPaths, filters, order, limit),
      count: () => ({
        get: async () => {
          const n = listPaths().length;
          return { data: () => ({ count: n }) };
        },
      }),
      get: async () => {
        let snaps = listPaths().map(snapOf);
        const plain = (v) => (v instanceof Date ? v.getTime() : v);
        for (const [field, op, value] of filters) {
          snaps = snaps.filter((s) => (op === '=='
            ? s.data()[field] === value
            : plain(s.data()[field]) >= plain(value)));
        }
        if (order) {
          const [field, dir] = order;
          const key = (s) => {
            const v = s.data()[field];
            return v instanceof Date ? v.getTime() : v;
          };
          snaps.sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0) * (dir === 'desc' ? -1 : 1));
        }
        if (limit != null) snaps = snaps.slice(0, limit);
        return { docs: snaps, size: snaps.length, empty: snaps.length === 0 };
      },
    };
  }

  function collectionOf(colPath) {
    const parts = colPath.split('/');
    const parentDoc = parts.length > 1 ? parts.slice(0, -1).join('/') : null;
    return {
      path: colPath,
      id: parts[parts.length - 1],
      parent: parentDoc ? refOf(parentDoc) : null,
      doc: (id) => refOf(colPath + '/' + id),
      ...query(() => childrenOf(colPath)),
    };
  }

  const db = {
    docs,
    doc: (p) => refOf(p),
    collection: (name) => collectionOf(name),
    // getAll(...refs, readOptions?) — the Admin SDK's batched read. The
    // field mask only trims what comes back over the wire, so the fake
    // ignores it and answers with the whole document.
    getAll: async (...args) => {
      const refs = args.filter((a) => a && typeof a.path === 'string');
      return refs.map((ref) => snapOf(ref.path));
    },
    collectionGroup: (name) => query(() => Array.from(docs.keys())
      .filter((k) => {
        const parts = k.split('/');
        return parts.length >= 2 && parts[parts.length - 2] === name;
      })
      .sort()),
    runTransaction: async (fn) => {
      const writes = [];
      const tx = {
        get: async (ref) => snapOf(ref.path),
        set: (ref, data) => writes.push([ref.path, clone(data)]),
      };
      const result = await fn(tx);
      for (const [p, data] of writes) docs.set(p, data);
      return result;
    },
  };
  return db;
}

/** users/{uid} and its device tokens, straight into the fake. */
function seedAccount(db, uid, { locale, tz, settings, tokens = [] } = {}) {
  const data = {};
  if (locale !== undefined) data.locale = locale;
  if (tz !== undefined) data.tzOffsetMinutes = tz;
  if (settings !== undefined) data.notificationSettings = settings;
  db.docs.set('users/' + uid, data);
  tokens.forEach((t, i) => {
    const token = typeof t === 'string' ? t : t.token;
    const updatedAt = typeof t === 'string' ? new Date(NOON_BAHRAIN - i * 1000) : t.updatedAt;
    db.docs.set('users/' + uid + '/fcmTokens/' + token, { platform: 'iOS', updatedAt });
  });
}

function fakeMessaging(answer = () => ({ success: true })) {
  const calls = [];
  return {
    calls,
    sendEach: async (messages, dryRun) => {
      calls.push({ messages, dryRun });
      return { responses: messages.map((m) => answer(m.token)) };
    },
  };
}

const MESSAGE = {
  titleAr: 'تحديث جديد',
  bodyAr: 'صار عندك تذكير لكل صلاة.',
  titleEn: 'New update',
  bodyEn: 'Every prayer can have its own reminder now.',
};

function uid(n) {
  return 'uidTestAccount' + String(n).padStart(14, '0');
}

// ---- Checking what was written --------------------------------------------

test('a message needs an Arabic title and body; English is optional but comes as a pair', () => {
  const empty = Broadcast.checkMessage('notification', {});
  assert.strictEqual(empty.ok, false);
  assert.ok(empty.errors.some((e) => e.includes('Arabic title')));
  assert.ok(empty.errors.some((e) => e.includes('Arabic message')));

  const arabicOnly = Broadcast.checkMessage('notification', { titleAr: 'عنوان', bodyAr: 'نص' });
  assert.strictEqual(arabicOnly.ok, true, arabicOnly.errors.join(' '));

  const halfEnglish = Broadcast.checkMessage('notification', { titleAr: 'عنوان', bodyAr: 'نص', titleEn: 'Title' });
  assert.strictEqual(halfEnglish.ok, false);
  assert.ok(halfEnglish.errors.some((e) => e.includes('English needs both')));
});

test('an em dash anywhere is refused, and so is text past the limit for its kind', () => {
  const dashed = Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: 'نص ' + EM_DASH + ' نص' });
  assert.strictEqual(dashed.ok, false);
  assert.ok(dashed.errors.some((e) => e.includes('em dash')));

  const longTitle = 'ا'.repeat(Broadcast.LIMITS.notification.title + 1);
  assert.strictEqual(Broadcast.checkMessage('notification', { titleAr: longTitle, bodyAr: 'نص' }).ok, false);
  assert.strictEqual(Broadcast.checkMessage('popup', { titleAr: longTitle, bodyAr: 'نص' }).ok, true,
    'a pop-up title may be longer than a lock screen allows');
});

test('a notification title is one line', () => {
  const r = Broadcast.checkMessage('notification', { titleAr: 'سطر\nسطر', bodyAr: 'نص' });
  assert.strictEqual(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('one line')));
});

test('a pop-up gets the default buttons and seven days unless told otherwise', () => {
  const r = Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: 'نص' });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.message.buttonAr, Broadcast.DEFAULT_BUTTON.ar);
  assert.strictEqual(r.message.buttonEn, Broadcast.DEFAULT_BUTTON.en);
  assert.strictEqual(r.message.days, 7);
  assert.strictEqual(Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: 'نص', days: 30 }).message.days, 30);
  const odd = Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: 'نص', days: 5 });
  assert.strictEqual(odd.ok, false, 'only the listed lengths are offered');
});

test('house-style reminders warn without blocking; Arabic-Indic digits are fine in a notification only', () => {
  const lisa = Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: 'يومك مفتوح لسا' });
  assert.strictEqual(lisa.ok, true);
  assert.ok(lisa.warnings.some((w) => w.includes('إلى الآن')));

  const digits = 'باقي ' + String.fromCharCode(0x0663) + ' أيام';
  const popup = Broadcast.checkMessage('popup', { titleAr: 'عنوان', bodyAr: digits });
  const note = Broadcast.checkMessage('notification', { titleAr: 'عنوان', bodyAr: digits });
  assert.ok(popup.warnings.some((w) => w.includes('Latin digits')));
  assert.ok(!note.warnings.some((w) => w.includes('Latin digits')));
});

test('English only for an English phone with an English version; everyone else, Arabic', () => {
  assert.strictEqual(Broadcast.languageFor('en', MESSAGE), 'en');
  assert.strictEqual(Broadcast.languageFor('ar', MESSAGE), 'ar');
  assert.strictEqual(Broadcast.languageFor(null, MESSAGE), 'ar', 'a phone that never said its language');
  assert.strictEqual(Broadcast.languageFor('en', { ...MESSAGE, titleEn: '', bodyEn: '' }), 'ar');
  assert.deepStrictEqual(Broadcast.textFor(MESSAGE, 'en'), { title: 'New update', body: MESSAGE.bodyEn });
});

test('the uid hash is plain SHA-256 hex, the same one the app computes', () => {
  // Pinned vectors: test/features/broadcast/broadcast_message_test.dart
  // asserts the very same pair on the Dart side.
  assert.strictEqual(Broadcast.uidHash('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.strictEqual(Broadcast.uidHash('aZ9TestUidForBroadcast000001'),
    '0f32428f5f9a1caa8476f46575f0b24fcd87725cbbc9af84eda946a62f737941');
});

// ---- Who a notification reaches ---------------------------------------------

test('collectAccounts reads the accounts that have a phone, and drops orphans', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['t1', 't2'] });
  seedAccount(db, uid(2), { locale: 'en', tz: 180 });
  // A token under an account document that no longer exists.
  db.docs.set('users/' + uid(9) + '/fcmTokens/orphan', { platform: 'iOS' });
  const accounts = await Broadcast.collectAccounts(db);
  const byUid = Object.fromEntries(accounts.map((a) => [a.uid, a]));
  assert.deepStrictEqual(byUid[uid(1)].tokens.map((t) => t.token).sort(), ['t1', 't2']);
  assert.strictEqual(byUid[uid(2)], undefined,
      'an account with no phone is never read: it is counted, not fetched');
  assert.strictEqual(byUid[uid(9)], undefined);
  assert.strictEqual(await Broadcast.countAccounts(db), 2);

  const only = await Broadcast.collectAccounts(db, [uid(1), uid(2)]);
  assert.deepStrictEqual(only.map((a) => a.uid).sort(), [uid(1), uid(2)].sort());
  assert.strictEqual(only.find((a) => a.uid === uid(2)).tokens.length, 0,
      'a test account with no phone comes back, with none');
});

test('a phone that changed hands is sent to under its newest account only, '
    + 'including on a test', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), {
    locale: 'ar', tz: 180,
    tokens: [{ token: 'shared', updatedAt: new Date(NOON_BAHRAIN - 60000) }],
  });
  seedAccount(db, uid(2), {
    locale: 'ar', tz: 180,
    tokens: [{ token: 'shared', updatedAt: new Date(NOON_BAHRAIN) }],
  });
  const testers = await Broadcast.collectAccounts(db, [uid(1)]);
  assert.deepStrictEqual(testers[0].tokens, [],
      'the older account no longer owns that phone, so a test to it sends nowhere');
  const everyone = await Broadcast.collectAccounts(db);
  const owner = everyone.find((a) => a.tokens.length);
  assert.strictEqual(owner.uid, uid(2));
});

test('everyone: the app switch and quiet hours are respected, people with no phone are counted', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  seedAccount(db, uid(2), { locale: 'en', tz: 180, tokens: ['b1', 'b2'] });
  seedAccount(db, uid(3), { locale: 'ar', tz: 180, settings: { masterEnabled: false }, tokens: ['c1'] });
  seedAccount(db, uid(4), { locale: 'ar', tz: 180, settings: { quietHoursEnabled: false }, tokens: ['d1'] });
  seedAccount(db, uid(5), { locale: 'ar', tokens: ['e1'] }); // never said its offset
  seedAccount(db, uid(6), { locale: 'ar', tz: 180 }); // no phone
  const accounts = await Broadcast.collectAccounts(db);
  const totalAccounts = await Broadcast.countAccounts(db);

  const noon = Broadcast.planRecipients(accounts, { nowMs: NOON_BAHRAIN, totalAccounts });
  assert.deepStrictEqual(noon.devices.map((d) => d.token).sort(), ['a1', 'b1', 'b2', 'd1', 'e1']);
  assert.strictEqual(noon.counts.off, 1);
  assert.strictEqual(noon.counts.quiet, 0);
  assert.strictEqual(noon.counts.noPhone, 1, 'uid(6), counted from the total');
  assert.strictEqual(noon.counts.accounts, 6);
  assert.strictEqual(noon.counts.withPhone, 5);
  assert.strictEqual(noon.counts.phones, 5);
  assert.strictEqual(noon.counts.en, 2);
  assert.strictEqual(noon.counts.ar, 3);

  const late = Broadcast.planRecipients(accounts, { nowMs: LATE_BAHRAIN, totalAccounts });
  assert.deepStrictEqual(late.devices.map((d) => d.token).sort(), ['d1', 'e1'],
    'only quiet hours switched off, or no clock to judge by, go through at 23:30');
  assert.strictEqual(late.counts.quiet, 2);
  assert.strictEqual(late.counts.quietPhones, 3);
  // Held, not skipped (page item 6): each until 07:02 the next morning.
  const sevenOhTwo = Date.UTC(2026, 8, 23, 4, 2);
  assert.deepStrictEqual(late.held, [
    { uid: uid(1), atMs: sevenOhTwo },
    { uid: uid(2), atMs: sevenOhTwo },
  ]);
  assert.deepStrictEqual(noon.held, []);
});

test('a test goes only to the test accounts, whatever their quiet hours or app switch', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, settings: { masterEnabled: false }, tokens: ['mine'] });
  seedAccount(db, uid(2), { locale: 'ar', tz: 180, tokens: ['theirs'] });
  const accounts = await Broadcast.collectAccounts(db);
  const plan = Broadcast.planRecipients(accounts, { audience: 'test', testUids: [uid(1)], nowMs: LATE_BAHRAIN });
  assert.deepStrictEqual(plan.devices.map((d) => d.token), ['mine']);
  assert.strictEqual(plan.counts.accounts, 1);
});

test('one phone listed under two accounts is sent to once, under the newer registration', () => {
  const accounts = [
    { uid: uid(1), locale: 'ar', tzOffsetMinutes: 180, tokens: [{ token: 'shared', updatedMs: 1000 }] },
    { uid: uid(2), locale: 'en', tzOffsetMinutes: 180, tokens: [{ token: 'shared', updatedMs: 5000 }] },
  ];
  const plan = Broadcast.planRecipients(accounts, { nowMs: NOON_BAHRAIN });
  assert.strictEqual(plan.devices.length, 1);
  assert.strictEqual(plan.devices[0].uid, uid(2));
  assert.strictEqual(plan.devices[0].locale, 'en');
  assert.strictEqual(plan.counts.noPhone, 1, 'the older account no longer holds a phone of its own');
});

// ---- Sending ---------------------------------------------------------------------

test('a send reaches each phone in its own language, in FCM\'s batches of 500, and is logged', async () => {
  const accounts = [];
  for (let i = 0; i < 1203; i++) {
    accounts.push({ uid: uid(i), locale: i % 3 === 0 ? 'en' : 'ar', tzOffsetMinutes: 180, tokens: [{ token: 'tok' + i, updatedMs: 1 }] });
  }
  const db = fakeDb();
  const messaging = fakeMessaging((token) => {
    if (token === 'tok7') return { success: false, error: { code: 'messaging/registration-token-not-registered' } };
    if (token === 'tok8') return { success: false, error: { code: 'messaging/internal-error' } };
    return { success: true };
  });
  const result = await Broadcast.sendNotification(db, messaging, {
    message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN, accounts,
  });
  assert.deepStrictEqual(messaging.calls.map((c) => c.messages.length), [500, 500, 203]);
  assert.ok(messaging.calls.every((c) => c.dryRun === false));
  assert.strictEqual(result.sent, 1201);
  assert.strictEqual(result.gone, 1);
  assert.strictEqual(result.failed, 1);
  assert.deepStrictEqual(result.errors, { 'messaging/internal-error': 1 });

  const first = messaging.calls[0].messages;
  const en = first.find((m) => m.token === 'tok0');
  const ar = first.find((m) => m.token === 'tok1');
  assert.deepStrictEqual(en.notification, { title: 'New update', body: MESSAGE.bodyEn });
  assert.deepStrictEqual(ar.notification, { title: MESSAGE.titleAr, body: MESSAGE.bodyAr });
  assert.deepStrictEqual(ar.data, { type: 'broadcast', id: result.id });
  assert.deepStrictEqual(ar.apns.payload, { aps: { sound: 'default' } });
  // A phone that is off for a day must not ring with this at midnight.
  assert.strictEqual(ar.android.ttl, Broadcast.NOTIFICATION_TTL_MS);
  assert.strictEqual(
      Number(ar.apns.headers['apns-expiration']),
      Math.floor((NOON_BAHRAIN + Broadcast.NOTIFICATION_TTL_MS) / 1000));

  const logged = db.docs.get('broadcast_log/' + result.id);
  assert.strictEqual(logged.kind, 'notification');
  assert.strictEqual(logged.audience, 'everyone');
  assert.strictEqual(logged.result.sent, 1201);
  assert.strictEqual(logged.counts.phones, 1203);
});

test('a dry run reaches FCM as a dry run and leaves no history', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  const messaging = fakeMessaging();
  const result = await Broadcast.sendNotification(db, messaging, {
    message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN, dryRun: true,
  });
  assert.strictEqual(result.dryRun, true);
  assert.strictEqual(messaging.calls[0].dryRun, true);
  assert.strictEqual(Array.from(db.docs.keys()).filter((k) => k.startsWith('broadcast_log/')).length, 0);
});

// Page item 6 (2026-09-24): there was no daily limit.
test('one notification to everyone per 24 hours, whatever it says; a test is not counted', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  const messaging = fakeMessaging();
  await Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN });
  // The same words again a minute later (a double click), and new words
  // hours later: both refused, with when the next may go.
  for (const [message, after] of [
    [{ ...MESSAGE, bodyAr: '  ' + MESSAGE.bodyAr + '  ' }, 60 * 1000],
    [{ ...MESSAGE, bodyAr: 'رسالة ثانية.' }, 20 * 60 * 60 * 1000],
  ]) {
    await assert.rejects(
      Broadcast.sendNotification(db, messaging, { message, audience: 'everyone', nowMs: NOON_BAHRAIN + after }),
      (e) => e instanceof Broadcast.BroadcastInputError && e.status === 409 &&
        /per 24 hours/.test(e.message) && /Wed 12:00/.test(e.message),
    );
  }
  await Broadcast.sendNotification(db, messaging, {
    message: MESSAGE, audience: 'test', testers: [uid(1)], nowMs: NOON_BAHRAIN + 60 * 1000,
  });
  const nextDay = await Broadcast.sendNotification(db, messaging, {
    message: { ...MESSAGE, bodyAr: 'رسالة ثانية.' },
    audience: 'everyone',
    nowMs: NOON_BAHRAIN + Broadcast.EVERYONE_GAP_MS,
  });
  assert.strictEqual(nextDay.sent, 1);
  assert.strictEqual(messaging.calls.length, 3);
});

test('people in quiet hours are held: listed on the row, then queued by holdBroadcast', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  seedAccount(db, uid(2), { locale: 'ar', tz: 180, settings: { quietHoursEnabled: false }, tokens: ['b1'] });
  const messaging = fakeMessaging();
  const asked = [];
  const result = await Broadcast.sendNotification(db, messaging, {
    message: MESSAGE,
    audience: 'everyone',
    nowMs: LATE_BAHRAIN,
    hold: async (id) => {
      // Called once the row that lists them is written.
      asked.push({ id, row: db.docs.get('broadcast_log/' + id) });
      return { queued: 1, failed: 0 };
    },
  });
  assert.strictEqual(result.sent, 1, 'the one without quiet hours, now');
  assert.deepStrictEqual(asked.map((a) => a.id), [result.id]);
  assert.deepStrictEqual(asked[0].row.held, [{ uid: uid(1), atMs: Date.UTC(2026, 8, 23, 4, 2) }]);
  assert.strictEqual(asked[0].row.sending, false);
  assert.deepStrictEqual(result.held, { people: 1, queued: 1, failed: 0 });
  const logged = db.docs.get('broadcast_log/' + result.id);
  assert.deepStrictEqual(logged.heldResult, { people: 1, queued: 1, failed: 0 });
});

test('everyone asleep is not an error: the send holds them all', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  const messaging = fakeMessaging();
  const result = await Broadcast.sendNotification(db, messaging, {
    message: MESSAGE, audience: 'everyone', nowMs: LATE_BAHRAIN,
    hold: async () => ({ queued: 1, failed: 0 }),
  });
  assert.strictEqual(result.sent, 0);
  assert.deepStrictEqual(result.held, { people: 1, queued: 1, failed: 0 });
});

test('with no hold service (not deployed yet) they are reported as skipped', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  const result = await Broadcast.sendNotification(db, fakeMessaging(), {
    message: MESSAGE, audience: 'everyone', nowMs: LATE_BAHRAIN,
    hold: async () => {
      throw new Error('holdBroadcast answered 404');
    },
  });
  assert.deepStrictEqual(result.held, { people: 1, error: 'holdBroadcast answered 404' });
  const logged = db.docs.get('broadcast_log/' + result.id);
  assert.strictEqual(logged.heldResult.error, 'holdBroadcast answered 404');
});

test('holdViaFunction calls holdBroadcast the callable way and returns its answer', async () => {
  const calls = [];
  const ok = Broadcast.holdViaFunction('grow-daily-339ef', async (url, init) => {
    calls.push({ url, init });
    return { ok: true, status: 200, json: async () => ({ result: { queued: 3, failed: 0 } }) };
  });
  assert.deepStrictEqual(await ok('n_abc_0a1b2c'), { queued: 3, failed: 0 });
  assert.strictEqual(calls[0].url, 'https://us-central1-grow-daily-339ef.cloudfunctions.net/holdBroadcast');
  assert.strictEqual(calls[0].init.method, 'POST');
  assert.deepStrictEqual(JSON.parse(calls[0].init.body), { data: { id: 'n_abc_0a1b2c' } });

  const missing = Broadcast.holdViaFunction('grow-daily-339ef', async () => (
    { ok: false, status: 404, json: async () => { throw new Error('html'); } }));
  await assert.rejects(missing('n_abc_0a1b2c'), /answered 404/);
});

test('nobody to send to, or a bad test list, is an input error and sends nothing', async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180 });
  const messaging = fakeMessaging();
  await assert.rejects(
    Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'test', testers: [uid(1)], nowMs: NOON_BAHRAIN }),
    (e) => e instanceof Broadcast.BroadcastInputError && /no|None/.test(e.message),
  );
  await assert.rejects(
    Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'test', testers: [], nowMs: NOON_BAHRAIN }),
    Broadcast.BroadcastInputError,
  );
  await assert.rejects(
    Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'test', testers: ['../users'], nowMs: NOON_BAHRAIN }),
    Broadcast.BroadcastInputError,
  );
  const six = [1, 2, 3, 4, 5, 6].map(uid);
  await assert.rejects(
    Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'test', testers: six, nowMs: NOON_BAHRAIN }),
    Broadcast.BroadcastInputError,
  );
  await assert.rejects(
    Broadcast.sendNotification(db, messaging, { message: MESSAGE, audience: 'all', nowMs: NOON_BAHRAIN }),
    Broadcast.BroadcastInputError,
  );
  assert.strictEqual(messaging.calls.length, 0);
});

test('a send that dies half way leaves a row, so a retry does not send it twice',
    async () => {
  const db = fakeDb();
  seedAccount(db, uid(1), { locale: 'ar', tz: 180, tokens: ['a1'] });
  const broken = {
    sendEach: async () => {
      throw new Error('network gone');
    },
  };
  await assert.rejects(
      Broadcast.sendNotification(db, broken, {
        message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN,
      }),
      /network gone/);
  const rows = Array.from(db.docs.entries())
      .filter(([k]) => k.startsWith('broadcast_log/'));
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0][1].sending, true, 'the row says it never finished');

  await assert.rejects(
      Broadcast.sendNotification(db, fakeMessaging(), {
        message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN + 60 * 1000,
      }),
      (e) => e instanceof Broadcast.BroadcastInputError && e.status === 409);
});

// ---- The pop-up -------------------------------------------------------------------

test('a pop-up for everyone replaces only its own slot, with a new id and an end date', async () => {
  const db = fakeDb();
  db.docs.set('broadcast/live', {
    everyone: null,
    test: { id: 'p_old_test', titleAr: 'تجربة', bodyAr: 'نص', endsAt: new Date(NOON_BAHRAIN + 1000) },
    version: 4,
  });
  const r = await Broadcast.publishPopup(db, FieldValue, {
    message: { ...MESSAGE, days: 3 }, audience: 'everyone', nowMs: NOON_BAHRAIN,
  });
  const live = db.docs.get('broadcast/live');
  assert.strictEqual(live.version, 5);
  assert.strictEqual(live.everyone.id, r.id);
  assert.ok(r.id.startsWith('p_'));
  assert.strictEqual(live.everyone.titleAr, MESSAGE.titleAr);
  assert.strictEqual(live.everyone.buttonAr, Broadcast.DEFAULT_BUTTON.ar);
  assert.strictEqual(live.everyone.startsAt.getTime(), NOON_BAHRAIN);
  assert.strictEqual(live.everyone.endsAt.getTime(), NOON_BAHRAIN + 3 * 24 * 3600 * 1000);
  assert.strictEqual(live.everyone.testUidHashes, undefined);
  assert.strictEqual(live.test.id, 'p_old_test', 'the test slot is left exactly as it was');

  const logged = db.docs.get('broadcast_log/' + r.id);
  assert.strictEqual(logged.kind, 'popup');
  assert.strictEqual(logged.days, 3);
});

test('a test pop-up stores hashes, never uids, and leaves what everyone sees alone', async () => {
  const db = fakeDb();
  await Broadcast.publishPopup(db, FieldValue, { message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN });
  const everyoneId = db.docs.get('broadcast/live').everyone.id;
  const tester = 'aZ9TestUidForBroadcast000001';
  await Broadcast.publishPopup(db, FieldValue, {
    message: { ...MESSAGE, titleAr: 'تجربة' }, audience: 'test', testers: [tester], nowMs: NOON_BAHRAIN + 1000,
  });
  const live = db.docs.get('broadcast/live');
  assert.strictEqual(live.everyone.id, everyoneId);
  assert.deepStrictEqual(live.test.testUidHashes, ['0f32428f5f9a1caa8476f46575f0b24fcd87725cbbc9af84eda946a62f737941']);
  assert.ok(!JSON.stringify(live).includes(tester), 'the public document never carries the uid itself');
});

test('the same pop-up put up to everyone twice is refused, a test is not',
    async () => {
  const db = fakeDb();
  await Broadcast.publishPopup(db, FieldValue, {
    message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN,
  });
  const first = db.docs.get('broadcast/live').everyone.id;
  await assert.rejects(
      Broadcast.publishPopup(db, FieldValue, {
        message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN + 5000,
      }),
      (e) => e instanceof Broadcast.BroadcastInputError && e.status === 409);
  assert.strictEqual(db.docs.get('broadcast/live').everyone.id, first,
      'nothing changed, so nobody sees it a second time');

  // Different words may replace it, and a test may always be repeated.
  await Broadcast.publishPopup(db, FieldValue, {
    message: { ...MESSAGE, bodyAr: 'نص ثاني' }, audience: 'everyone', nowMs: NOON_BAHRAIN + 6000,
  });
  assert.notStrictEqual(db.docs.get('broadcast/live').everyone.id, first);
  for (const at of [7000, 8000]) {
    await Broadcast.publishPopup(db, FieldValue, {
      message: MESSAGE, audience: 'test', testers: [uid(1)], nowMs: NOON_BAHRAIN + at,
    });
  }
});

test('a test pop-up is up for hours, not the days an announcement gets', async () => {
  const db = fakeDb();
  await Broadcast.publishPopup(db, FieldValue, {
    message: { ...MESSAGE, days: 30 }, audience: 'test', testers: [uid(1)], nowMs: NOON_BAHRAIN,
  });
  const popup = db.docs.get('broadcast/live').test;
  assert.strictEqual(
      popup.endsAt.getTime(),
      NOON_BAHRAIN + Broadcast.TEST_POPUP_HOURS * 60 * 60 * 1000,
      'a draft nobody approved sits in a public document while it is up');
});

test('stopping a pop-up empties its slot, keeps the other, and marks the history row', async () => {
  const db = fakeDb();
  const a = await Broadcast.publishPopup(db, FieldValue, { message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN });
  await Broadcast.publishPopup(db, FieldValue, { message: MESSAGE, audience: 'test', testers: [uid(1)], nowMs: NOON_BAHRAIN });
  const stopped = await Broadcast.stopPopup(db, FieldValue, { slot: 'everyone', nowMs: NOON_BAHRAIN + 5000 });
  assert.strictEqual(stopped.stopped, a.id);
  const live = db.docs.get('broadcast/live');
  assert.strictEqual(live.everyone, null);
  assert.ok(live.test && live.test.id);
  assert.strictEqual(db.docs.get('broadcast_log/' + a.id).stoppedAt.getTime(), NOON_BAHRAIN + 5000);

  const again = await Broadcast.stopPopup(db, FieldValue, { slot: 'everyone' });
  assert.strictEqual(again.stopped, null);
  await assert.rejects(Broadcast.stopPopup(db, FieldValue, { slot: 'all' }), Broadcast.BroadcastInputError);
});

test('readMessages says which pop-up is still up and lists the history newest first', async () => {
  const db = fakeDb();
  await Broadcast.publishPopup(db, FieldValue, { message: { ...MESSAGE, days: 1 }, audience: 'everyone', nowMs: NOON_BAHRAIN });
  const accounts = [{ uid: uid(1), locale: 'ar', tzOffsetMinutes: 180, tokens: [{ token: 'a', updatedMs: 1 }] }];
  await Broadcast.sendNotification(db, fakeMessaging(), { message: MESSAGE, audience: 'everyone', nowMs: NOON_BAHRAIN + 60000, accounts });

  const soon = await Broadcast.readMessages(db, NOON_BAHRAIN + 3600 * 1000);
  assert.strictEqual(soon.live.everyone.active, true);
  assert.deepStrictEqual(soon.history.map((row) => row.kind), ['notification', 'popup']);

  const nextWeek = await Broadcast.readMessages(db, NOON_BAHRAIN + 7 * 24 * 3600 * 1000);
  assert.strictEqual(nextWeek.live.everyone.active, false, 'past its end date');
});

test('shapePopup refuses anything without an id', () => {
  assert.strictEqual(Broadcast.shapePopup(null), null);
  assert.strictEqual(Broadcast.shapePopup({ titleAr: 'x' }), null);
  assert.strictEqual(Broadcast.shapePopup({ id: 'p_1' }).active, true, 'no dates means no window to be outside of');
});

// ---- The page ----------------------------------------------------------------------

test('the page renders with its scripts, its icons parse, and every script is valid JavaScript', () => {
  const html = renderBroadcastPage({ projectId: 'demo-project' });
  assert.ok(html.includes('<script src="/messages/app.js"></script>'));
  assert.ok(html.includes('<script src="/wording/rules.js"></script>'));
  assert.ok(html.includes('href="/messages"'), 'the sidebar links here');
  const icons = /<script type="application\/json" id="msgIcons">([\s\S]*?)<\/script>/.exec(html);
  assert.ok(icons, 'icon block present');
  const parsed = JSON.parse(icons[1]);
  assert.ok(parsed.megaphone && parsed.megaphone.startsWith('<svg'), 'icons are real SVG');

  const inline = [];
  const re = /<script(\s[^>]*)?>([\s\S]*?)<\/script>/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    if (/type="application\/json"/.test(m[1] || '') || /src=/.test(m[1] || '')) continue;
    inline.push(m[2]);
  }
  for (const body of inline) assert.doesNotThrow(() => new vm.Script(body));

  const app = fs.readFileSync(path.join(__dirname, '..', 'broadcast', 'app.js'), 'utf8');
  assert.doesNotThrow(() => new vm.Script(app, { filename: 'broadcast/app.js' }));
  assert.ok(!app.includes(EM_DASH), 'no em dash in anything the page can show');
  assert.ok(!html.includes(EM_DASH));
});
