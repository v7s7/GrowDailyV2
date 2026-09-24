'use strict';

/**
 * The Messages page's routes. Mounted from server.js with one line, so the
 * whole feature lives in its own files: lib/broadcast.js (what may be sent
 * and the writes), lib/broadcast_page.js (the page), broadcast/app.js (what
 * the page does).
 *
 * Every write route sits behind the same localWriteOnly guard as Wording
 * and Achievements: a request has to come from this tool's own page, on
 * this machine, as JSON. On top of that, one send at a time: a second
 * press while the first send is still going answers 409 rather than
 * starting a second fan-out, because the 24-hour check in broadcast.js
 * only sees a send once its history row is written.
 */

const path = require('node:path');
const express = require('express');

const Broadcast = require('./broadcast');
const { renderBroadcastPage } = require('./broadcast_page');

/** How long a reach count is reused. It costs one read per account. */
const REACH_TTL_MS = 60 * 1000;

function mountBroadcast(app, { admin, projectId, localWriteOnly, port }) {
  const json = express.json({ limit: '64kb' });
  const db = () => admin.firestore();

  let reachCache = { at: 0, value: null };
  let phonesCache = { at: 0, value: 'unknown' };
  let busy = false;

  async function reach(fresh) {
    if (!fresh && reachCache.value && Date.now() - reachCache.at < REACH_TTL_MS) {
      return reachCache.value;
    }
    const [accounts, total] = await Promise.all([
      Broadcast.collectAccounts(db()),
      Broadcast.countAccounts(db()),
    ]);
    const value = {
      ...Broadcast.reachSummary(accounts, Date.now(), total),
      at: new Date().toISOString(),
    };
    reachCache = { at: Date.now(), value };
    return value;
  }

  // Asked at most once a minute, and every time until it says open: the
  // answer only changes when someone deploys the rules.
  async function phones() {
    if (phonesCache.value !== 'open' || Date.now() - phonesCache.at > 60 * 1000) {
      phonesCache = { at: Date.now(), value: await Broadcast.phonesCanRead(projectId) };
    }
    return phonesCache.value;
  }

  /**
   * The GETs that cost reads answer this tool's own page only.
   *
   * They are plain GETs, so any web page open in the same browser can make
   * the browser fetch them (it cannot read the answer, but the reads are
   * spent all the same, and /api/messages?fresh=1 scans every phone). The
   * Host check is the same anti-rebinding one the write guard uses;
   * Sec-Fetch-Site, which browsers set themselves and pages cannot forge,
   * is what tells a fetch from this page apart from one from elsewhere.
   */
  function ownPageOnly(req, res, next) {
    const hosts = ['127.0.0.1:' + port, 'localhost:' + port];
    const host = String(req.headers.host || '').toLowerCase();
    const site = String(req.headers['sec-fetch-site'] || '').toLowerCase();
    const sameSite = site === '' || site === 'same-origin' || site === 'none';
    if (hosts.includes(host) && sameSite) return next();
    res.status(403).json({ ok: false, error: 'Only this tool\'s own page may ask.' });
  }

  function fail(res, e) {
    if (e instanceof Broadcast.BroadcastInputError) {
      return res.status(e.status).json({ ok: false, error: e.message });
    }
    console.error(`[messages] ${e.stack || e.message}`);
    res.status(500).json({ ok: false, error: e.message });
  }

  /** One write at a time, and the page gets a plain answer when it has to wait. */
  async function exclusive(res, work) {
    if (busy) {
      return res.status(409).json({ ok: false, error: 'Another send is still going. Wait for it to finish.' });
    }
    busy = true;
    try {
      await work();
    } catch (e) {
      fail(res, e);
    } finally {
      busy = false;
    }
  }

  app.get('/messages', (req, res) => {
    res.type('html').send(renderBroadcastPage({ projectId }));
  });

  app.get('/messages/app.js', (req, res) => {
    res.type('application/javascript').sendFile(path.join(__dirname, '..', 'broadcast', 'app.js'));
  });

  app.get('/api/messages', ownPageOnly, async (req, res) => {
    try {
      const fresh = req.query.fresh === '1';
      const [stored, reachNow, phonesNow] = await Promise.all([
        Broadcast.readMessages(db()),
        reach(fresh),
        phones(),
      ]);
      res.json({
        ok: true,
        ...stored,
        reach: reachNow,
        phones: phonesNow,
        limits: Broadcast.LIMITS,
        popupDays: Broadcast.POPUP_DAYS,
        defaultDays: Broadcast.DEFAULT_POPUP_DAYS,
        defaultButton: Broadcast.DEFAULT_BUTTON,
        maxTesters: Broadcast.MAX_TESTERS,
        testPopupHours: Broadcast.TEST_POPUP_HOURS,
      });
    } catch (e) {
      fail(res, e);
    }
  });

  // How many phones each test account has, so the page can say before a
  // test whether it can arrive at all. A handful of small reads.
  app.get('/api/messages/testers', ownPageOnly, async (req, res) => {
    try {
      const uids = String(req.query.uids || '')
        .split(',')
        .map((s) => s.trim())
        .filter((s) => /^[A-Za-z0-9]{10,64}$/.test(s))
        .slice(0, Broadcast.MAX_TESTERS);
      const accounts = uids.length ? await Broadcast.collectAccounts(db(), uids) : [];
      const byUid = new Map(accounts.map((a) => [a.uid, a]));
      res.json({
        ok: true,
        testers: uids.map((uid) => {
          const a = byUid.get(uid);
          return {
            uid,
            exists: Boolean(a),
            phones: a ? a.tokens.length : 0,
            locale: a ? a.locale : null,
          };
        }),
      });
    } catch (e) {
      fail(res, e);
    }
  });

  /**
   * Answers with the result of a write that already landed, plus the fresh
   * state of the page when that can still be read. Reading it back is not
   * part of the write: a failure there must never be shown as a send that
   * failed, or the next press sends the same thing again.
   */
  async function answerAfterWrite(res, result) {
    let stored = null;
    try {
      stored = await Broadcast.readMessages(db());
    } catch (e) {
      console.error(`[messages] done, but reading it back failed: ${e.stack || e.message}`);
    }
    res.json({ ...result, ...(stored || { reloadFailed: true }) });
  }

  app.post('/api/messages/popup', localWriteOnly, json, (req, res) => exclusive(res, async () => {
    const body = req.body || {};
    const result = await Broadcast.publishPopup(db(), admin.firestore.FieldValue, {
      message: body.message,
      audience: body.audience,
      testers: body.testers,
    });
    await answerAfterWrite(res, result);
  }));

  app.post('/api/messages/popup/stop', localWriteOnly, json, (req, res) => exclusive(res, async () => {
    const body = req.body || {};
    const result = await Broadcast.stopPopup(db(), admin.firestore.FieldValue, { slot: body.slot });
    await answerAfterWrite(res, result);
  }));

  app.post('/api/messages/notification', localWriteOnly, json, (req, res) => exclusive(res, async () => {
    const body = req.body || {};
    const result = await Broadcast.sendNotification(db(), admin.messaging(), {
      message: body.message,
      audience: body.audience,
      testers: body.testers,
      // People in quiet hours, queued server side for when theirs end.
      hold: Broadcast.holdViaFunction(projectId),
    });
    await answerAfterWrite(res, result);
  }));
}

module.exports = { mountBroadcast, REACH_TTL_MS };
