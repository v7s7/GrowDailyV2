'use strict';

/**
 * The Messages page's routes: who is allowed to ask, what happens when two
 * sends overlap, and that a write which landed is never reported as a
 * failure.
 *
 * The routes are mounted on a real Express app on a loopback port, with
 * stand-ins for Firestore and FCM (lib/broadcast.js's own tests cover what
 * those do). The write guard is the REAL one from lib/wording.js, since
 * whether a request from another site can reach these routes is the whole
 * point of this file.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const express = require('express');

const { mountBroadcast } = require('../lib/broadcast_routes');
const wording = require('../lib/wording');

const MESSAGE = {
  titleAr: 'تحديث جديد',
  bodyAr: 'صار عندك تذكير لكل صلاة.',
};

/** Enough of the Admin SDK for the routes: nothing here writes anywhere. */
function fakeAdmin({ onPopup } = {}) {
  const docs = new Map();
  const firestore = () => ({
    doc: () => ({
      get: async () => ({ exists: false, data: () => undefined }),
      set: async () => {},
    }),
    collection: () => ({
      doc: () => ({ set: async () => {} }),
      orderBy: () => ({ limit: () => ({ get: async () => ({ docs: [] }) }) }),
      where: () => ({ get: async () => ({ docs: [] }) }),
      count: () => ({ get: async () => ({ data: () => ({ count: 0 }) }) }),
    }),
    collectionGroup: () => ({ get: async () => ({ docs: [] }) }),
    getAll: async () => [],
    runTransaction: async (fn) => fn({
      get: async () => ({ exists: false, data: () => undefined }),
      set: (ref, data) => {
        docs.set('live', data);
        if (onPopup) onPopup(data);
      },
    }),
  });
  firestore.FieldValue = { serverTimestamp: () => new Date(0) };
  return {
    docs,
    firestore,
    messaging: () => ({
      sendEach: async (messages) => ({
        responses: messages.map(() => ({ success: true })),
      }),
    }),
  };
}

/** The routes on a real server, answering on 127.0.0.1. */
async function serveRoutes(options = {}) {
  const app = express();
  const admin = fakeAdmin(options);
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const port = server.address().port;
  mountBroadcast(app, {
    admin,
    projectId: 'demo-project',
    localWriteOnly: (req, res, next) => {
      if (wording.isLocalWrite(req.headers, port)) return next();
      res.status(403).json({ ok: false, error: 'not from this page' });
    },
    port,
  });
  return {
    admin,
    port,
    url: (p) => `http://127.0.0.1:${port}${p}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

test('a write route takes nothing that did not come from this page', async () => {
  const s = await serveRoutes();
  try {
    const body = JSON.stringify({ audience: 'everyone', message: MESSAGE });
    const asPage = {
      'Content-Type': 'application/json',
      Origin: `http://127.0.0.1:${s.port}`,
    };
    const refused = [
      // Another site's page, posting as a form, which needs no CORS check.
      { 'Content-Type': 'application/x-www-form-urlencoded' },
      // Another site's page that managed to send JSON.
      { 'Content-Type': 'application/json', Origin: 'https://example.com' },
    ];
    for (const headers of refused) {
      const res = await fetch(s.url('/api/messages/popup'), { method: 'POST', headers, body });
      assert.strictEqual(res.status, 403, JSON.stringify(headers));
    }
    const ok = await fetch(s.url('/api/messages/popup'), { method: 'POST', headers: asPage, body });
    assert.strictEqual(ok.status, 200);
    const answer = await ok.json();
    assert.strictEqual(answer.ok, true);
    assert.ok(answer.id.startsWith('p_'));
  } finally {
    await s.close();
  }
});

test('the reads that cost money answer this page only', async () => {
  const s = await serveRoutes();
  try {
    const cross = await fetch(s.url('/api/messages?fresh=1'), {
      headers: { 'Sec-Fetch-Site': 'cross-site' },
    });
    assert.strictEqual(cross.status, 403);
    const testers = await fetch(s.url('/api/messages/testers?uids=abcdefghij'), {
      headers: { 'Sec-Fetch-Site': 'cross-site' },
    });
    assert.strictEqual(testers.status, 403);

    const own = await fetch(s.url('/api/messages'), {
      headers: { 'Sec-Fetch-Site': 'same-origin' },
    });
    assert.strictEqual(own.status, 200);
    const data = await own.json();
    assert.strictEqual(data.ok, true);
    assert.ok(data.limits.popup.title > 0);
    assert.ok(Array.isArray(data.history));
  } finally {
    await s.close();
  }
});

test('a second send while one is still going is told to wait, not started', async () => {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  const s = await serveRoutes();
  // Hold the first publish inside its transaction, so the second arrives
  // while it is still going.
  s.admin.firestore = Object.assign(() => ({
    doc: () => ({ get: async () => ({ exists: false }), set: async () => {} }),
    collection: () => ({
      doc: () => ({ set: async () => {} }),
      orderBy: () => ({ limit: () => ({ get: async () => ({ docs: [] }) }) }),
      where: () => ({ get: async () => ({ docs: [] }) }),
      count: () => ({ get: async () => ({ data: () => ({ count: 0 }) }) }),
    }),
    collectionGroup: () => ({ get: async () => ({ docs: [] }) }),
    getAll: async () => [],
    runTransaction: async (fn) => {
      await held;
      return fn({
        get: async () => ({ exists: false, data: () => undefined }),
        set: () => {},
      });
    },
  }), { FieldValue: { serverTimestamp: () => new Date(0) } });

  try {
    const headers = {
      'Content-Type': 'application/json',
      Origin: `http://127.0.0.1:${s.port}`,
    };
    const body = JSON.stringify({ audience: 'everyone', message: MESSAGE });
    const first = fetch(s.url('/api/messages/popup'), { method: 'POST', headers, body });
    // Let the first request reach the held transaction.
    await new Promise((r) => setTimeout(r, 50));
    const second = await fetch(s.url('/api/messages/popup'), { method: 'POST', headers, body });
    assert.strictEqual(second.status, 409);
    assert.match((await second.json()).error, /still going/);
    release();
    assert.strictEqual((await first).status, 200);
  } finally {
    release();
    await s.close();
  }
});

test('a send that landed is a success even if the page cannot be read back',
    async () => {
  const s = await serveRoutes();
  const firestore = s.admin.firestore();
  s.admin.firestore = Object.assign(() => ({
    ...firestore,
    // readMessages goes through here; make it fail AFTER the write.
    collection: (name) => {
      if (name === 'broadcast_log') {
        return {
          doc: () => ({ set: async () => {} }),
          orderBy: () => ({
            limit: () => ({
              get: async () => {
                throw new Error('read back failed');
              },
            }),
          }),
          where: () => ({ get: async () => ({ docs: [] }) }),
        };
      }
      return firestore.collection(name);
    },
  }), { FieldValue: { serverTimestamp: () => new Date(0) } });

  try {
    const res = await fetch(s.url('/api/messages/popup'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: `http://127.0.0.1:${s.port}`,
      },
      body: JSON.stringify({ audience: 'everyone', message: MESSAGE }),
    });
    assert.strictEqual(res.status, 200);
    const answer = await res.json();
    assert.strictEqual(answer.ok, true, 'the pop-up is up; only the reload failed');
    assert.strictEqual(answer.reloadFailed, true);
  } finally {
    await s.close();
  }
});

test('a bad message is a message, not a server fault', async () => {
  const s = await serveRoutes();
  try {
    const res = await fetch(s.url('/api/messages/popup'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: `http://127.0.0.1:${s.port}`,
      },
      body: JSON.stringify({ audience: 'everyone', message: { titleAr: 'عنوان' } }),
    });
    assert.strictEqual(res.status, 400);
    assert.match((await res.json()).error, /Arabic message/);
  } finally {
    await s.close();
  }
});
