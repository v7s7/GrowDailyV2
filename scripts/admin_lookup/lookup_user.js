#!/usr/bin/env node
/**
 * GrowDaily admin lookup tool (CLI) — one-off standalone report.
 *
 * Looks up ONE account (by email or uid) and writes a single self-contained
 * HTML report file with everything about them. For browsing/searching
 * across every account without knowing an email upfront, use server.js
 * instead — this script and that server share the exact same rendering and
 * data-fetching code (lib/render.js, lib/fetchAccount.js), so a report
 * looks identical either way; this one just also saves a copy to disk.
 *
 * One-time setup:
 *   1. cd scripts/admin_lookup && npm install
 *   2. Firebase Console (console.firebase.google.com) -> pick the
 *      grow-daily-339ef project -> gear icon (top left) -> Project settings
 *      -> Service accounts tab -> Generate new private key -> confirm.
 *   3. Save the downloaded file as exactly:
 *        scripts/admin_lookup/service-account.json
 *      (already covered by .gitignore — never commit this file or share
 *      it; it grants full read/write access to your entire Firebase
 *      project, not just reading users).
 *
 * Usage:
 *   node lookup_user.js someone@example.com
 *   node lookup_user.js <uid>
 *
 * Writes scripts/admin_lookup/reports/<uid>.html and prints its path.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, 'service-account.json');

function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}

if (!fs.existsSync(KEY_PATH)) {
  fail(
    'Missing scripts/admin_lookup/service-account.json.\n' +
    'Get one from Firebase Console -> Project settings (gear icon) -> ' +
    'Service accounts -> Generate new private key, then save it at exactly ' +
    'that path. See the comment at the top of lookup_user.js for the full ' +
    'steps.'
  );
}

const query = process.argv[2];
if (!query) {
  fail('Usage: node lookup_user.js <email-or-uid>');
}

admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

const { resolveAccount, loadAccountReport } = require('./lib/fetchAccount');
const { buildReportBody, pageShell } = require('./lib/render');

async function main() {
  let uid, authRecord;
  try {
    ({ uid, authRecord } = await resolveAccount(query));
  } catch (e) {
    fail(`No account found for "${query}": ${e.message}`);
  }

  let report;
  try {
    report = await loadAccountReport(uid, authRecord);
  } catch (e) {
    fail(e.message);
  }

  const { title, nav, header, body } = buildReportBody(report);
  const html = pageShell({ title, nav, header, body });

  const outDir = path.join(__dirname, 'reports');
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `${uid}.html`);
  fs.writeFileSync(outPath, html);
  console.log(`\nReport written to:\n${outPath}\n`);
}

main().catch((e) => fail(e.stack || String(e)));
