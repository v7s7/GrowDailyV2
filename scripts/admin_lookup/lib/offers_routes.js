'use strict';

/**
 * The Sale and Creators pages' routes, mounted from server.js with one call
 * (the way the Messages page mounts), so both features live in their own
 * files:
 *
 *   Sale      lib/sale_rules.js (the rules, shared with the browser),
 *             lib/sale_admin.js (reads and writes), lib/sale_page.js,
 *             sale/app.js
 *   Creators  lib/creators.js (money, checks, ledger sums, Apple request
 *             bodies; shared with the browser), lib/creators_admin.js,
 *             lib/asc_client.js (App Store Connect), lib/creators_page.js,
 *             creators/app.js
 *
 * Every write route sits behind the same localWriteOnly guard as Wording and
 * Achievements (a request from this tool's own page, on this machine, as
 * JSON) and answers with the page's fresh state read back after the write.
 * The Apple preview sits behind it too, though it only reads: it signs its
 * requests with the App Store Connect key.
 *
 * Writes, all of them:
 *   POST /api/sale/welcome            offers/live (welcome)
 *   POST /api/sale/full-price-since   offers/live (fullPriceSince)
 *   POST /api/sale/schedule           offer_sales/{new id} + offers/live (sale)
 *   POST /api/sale/end                offer_sales/{id} (endsAt and/or
 *                                     endedEarlyAt) + offers/live (sale)
 *   POST /api/creators/add            creators/{CODE}
 *   POST /api/creators/share          creators/{CODE}.sharePercent
 *   POST /api/creators/active         creators/{CODE}.active
 *   POST /api/creators/payout         creator_payouts/{new id}
 *   POST /api/creators/statement-link creators/{CODE}.statementKeyHash (the
 *                                     creator's own page link; the link
 *                                     itself is answered once, never kept)
 *   POST /api/creators/apple/create   App Store Connect (an offer code and a
 *                                     custom code), then creators/{CODE}
 *                                     (and the Apple ids it returned)
 */

const path = require('node:path');
const express = require('express');

const Sale = require('./sale_admin');
const CreatorsAdmin = require('./creators_admin');
const { AscConfigError, AscApiError, createAscClient } = require('./asc_client');
const { renderSalePage } = require('./sale_page');
const { renderCreatorsPage } = require('./creators_page');

const ROOT = path.join(__dirname, '..');

/** Browser files, named one by one: this folder also holds the service-account key. */
const FILES = {
  '/sale/app.js': path.join(ROOT, 'sale', 'app.js'),
  '/sale/rules.js': path.join(ROOT, 'lib', 'sale_rules.js'),
  '/creators/app.js': path.join(ROOT, 'creators', 'app.js'),
  '/creators/rules.js': path.join(ROOT, 'lib', 'creators.js'),
};

function mountOffers(app, { admin, projectId, localWriteOnly, asc = createAscClient(), now = () => Date.now() }) {
  const json = express.json({ limit: '64kb' });
  const db = () => admin.firestore();
  const deps = () => ({ Timestamp: admin.firestore.Timestamp, FieldValue: admin.firestore.FieldValue });

  function fail(res, e, tag) {
    if (e instanceof Sale.SaleInputError || e instanceof CreatorsAdmin.CreatorsInputError) {
      return res.status(e.status).json({ ok: false, error: e.message, errors: e.errors || [], ascMissing: e.ascMissing || null });
    }
    if (e instanceof AscConfigError) return res.status(400).json({ ok: false, error: e.message, ascMissing: e.missing });
    if (e instanceof AscApiError) return res.status(502).json({ ok: false, error: e.message });
    console.error(`[${tag}] ${e.stack || e.message}`);
    res.status(500).json({ ok: false, error: e.message });
  }

  for (const [route, file] of Object.entries(FILES)) {
    app.get(route, (req, res) => res.type('application/javascript').sendFile(file));
  }

  // ---- Sale ----------------------------------------------------------------
  const saleState = () => Sale.readSaleState(db(), { nowMs: now(), Timestamp: admin.firestore.Timestamp });

  app.get('/sale', (req, res) => {
    res.type('html').send(renderSalePage({ projectId }));
  });

  app.get('/api/sale', async (req, res) => {
    try {
      res.json({ ok: true, state: await saleState() });
    } catch (e) {
      fail(res, e, 'sale');
    }
  });

  function saleWrite(route, action) {
    app.post(route, localWriteOnly, json, async (req, res) => {
      try {
        const result = await action(req.body || {});
        res.json({ ok: true, ...result, state: await saleState() });
      } catch (e) {
        fail(res, e, 'sale');
      }
    });
  }

  saleWrite('/api/sale/welcome', (b) => Sale.saveWelcome(db(), deps(), { enabled: b.enabled, hours: b.hours }));
  saleWrite('/api/sale/full-price-since', (b) => Sale.setFullPriceSince(db(), deps(), { date: b.date }, now()));
  saleWrite('/api/sale/schedule', (b) => Sale.scheduleSale(db(), deps(), {
    nameAr: b.nameAr, nameEn: b.nameEn, startDate: b.startDate, startTime: b.startTime, endDate: b.endDate, endTime: b.endTime,
  }, now()));
  saleWrite('/api/sale/end', (b) => Sale.endSale(db(), deps(), { id: b.id }, now()));

  // ---- Creators --------------------------------------------------------------
  const creatorsState = () => CreatorsAdmin.readCreatorsState(db(), { nowMs: now(), ascConfig: asc.config() });

  app.get('/creators', (req, res) => {
    res.type('html').send(renderCreatorsPage({ projectId }));
  });

  app.get('/api/creators', async (req, res) => {
    try {
      res.json({ ok: true, state: await creatorsState() });
    } catch (e) {
      fail(res, e, 'creators');
    }
  });

  // What App Store Connect says about the two Lifetime products. Read-only.
  app.get('/api/creators/apple-status', async (req, res) => {
    try {
      const cfg = asc.config();
      if (!cfg.ok) return res.status(400).json({ ok: false, error: cfg.missing.join('. ') + '.', ascMissing: cfg.missing });
      res.json({ ok: true, status: await CreatorsAdmin.readAppleStatus(asc) });
    } catch (e) {
      fail(res, e, 'creators');
    }
  });

  function creatorWrite(route, action) {
    app.post(route, localWriteOnly, json, async (req, res) => {
      try {
        const result = await action(req.body || {});
        res.json({ ok: true, ...result, state: await creatorsState() });
      } catch (e) {
        fail(res, e, 'creators');
      }
    });
  }

  creatorWrite('/api/creators/add', (b) => CreatorsAdmin.addCreator(db(), deps(), {
    name: b.name, code: b.code, discountPercent: b.discountPercent, discountOff: b.discountOff,
    sharePercent: b.sharePercent, codeEndsOn: b.codeEndsOn, usesAllowed: b.usesAllowed,
  }, now()));
  creatorWrite('/api/creators/share', (b) => CreatorsAdmin.setShare(db(), deps(), { code: b.code, sharePercent: b.sharePercent }));
  creatorWrite('/api/creators/active', (b) => CreatorsAdmin.setActive(db(), deps(), { code: b.code, active: b.active }));
  creatorWrite('/api/creators/payout', (b) => CreatorsAdmin.recordPayout(db(), deps(), { code: b.code, amountUsd: b.amountUsd, note: b.note }, now()));
  creatorWrite('/api/creators/statement-link', (b) => CreatorsAdmin.makeStatementLink(db(), deps(), { code: b.code }));

  // Step one: build and show the exact requests. Reads from Apple, writes nothing.
  app.post('/api/creators/apple/preview', localWriteOnly, json, async (req, res) => {
    try {
      const b = req.body || {};
      const preview = await CreatorsAdmin.previewAppleCode(db(), asc, { input: b.input, code: b.code }, now());
      res.json({ ok: true, preview });
    } catch (e) {
      fail(res, e, 'creators');
    }
  });

  // Step two: send exactly what was previewed, once.
  app.post('/api/creators/apple/create', localWriteOnly, json, async (req, res) => {
    try {
      const result = await CreatorsAdmin.createAppleCode(db(), deps(), asc, { planId: (req.body || {}).planId }, now());
      res.status(result.ok ? 200 : 502).json({ ...result, state: await creatorsState() });
    } catch (e) {
      fail(res, e, 'creators');
    }
  });
}

module.exports = { mountOffers, FILES };
