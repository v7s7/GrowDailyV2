#!/usr/bin/env node
/**
 * GrowDaily admin lookup tool (live server).
 *
 * Start it once, then open the printed URL. The home page is a dashboard:
 * what happened across every account just now, who was doing it, and how
 * far back you want to look. Clicking anything opens that account's full
 * report, where the first tab is a single day (today by default) that you
 * can step backwards through. lookup_user.js (the CLI script) still exists
 * for saving one specific report as a standalone file; this is for browsing
 * without knowing who you're looking for in advance.
 *
 * Same one-time setup as lookup_user.js (see that file's own comment):
 * `npm install`, then a service-account.json key in this folder.
 *
 * Usage:
 *   node server.js
 *   PORT=5050 node server.js   (defaults to 4127)
 */

const express = require('express');
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

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

const {
  resolveAccount, loadAccountReport, loadDayFragment, searchAccounts, listAllUsers,
} = require('./lib/fetchAccount');
const { buildReportBody, pageShell, escapeHtml, BASE_STYLES } = require('./lib/render');
const { scanActivity, scanDay } = require('./lib/activity');

const PORT = process.env.PORT || 4127;
const app = express();

/**
 * True only for a date that actually exists.
 *
 * A bare /^\d{4}-\d{2}-\d{2}$/ accepts 2026-13-45, which Date.UTC then
 * normalises to a real day in February 2027: the page would be titled with
 * the impossible date while showing a completely different day's schedule.
 * Round-tripping through Date is what catches that, and catches 30 February
 * with it.
 */
function isRealDateKey(value) {
  const key = String(value || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return false;
  const [y, m, d] = key.split('-').map(Number);
  const probe = new Date(Date.UTC(y, m - 1, d));
  return probe.getUTCFullYear() === y
    && probe.getUTCMonth() === m - 1
    && probe.getUTCDate() === d;
}

// ---- Dashboard home page.
//
// One scan of the whole project (see lib/activity.js) loads into the
// browser once, and both views run against that in-memory copy: search,
// type filters, the day picker and every sort are instant instead of a
// round trip per keystroke. This is a single-admin local tool, not a public
// multi-tenant dashboard, so holding a few thousand small event rows
// client-side is the right trade.
//
// Two views, because there are exactly two questions:
//   Activity  what has been happening, newest first, on any day
//   Accounts  who exists, and how is each of them doing
// ----
app.get('/', (req, res) => {
  res.type('html').send(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GrowDaily — Admin Lookup</title>
<style>${BASE_STYLES}
  body { max-width: 1120px; padding-top: 3vh; }
  .lockup { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; }
  .lockup h1 { font-size: 22px; margin: 0; }
  .lockup p { color: var(--text-sec); font-size: 12.5px; margin: 3px 0 0; }
  .lockup .right { display: flex; align-items: center; gap: 10px; }

  .filter-bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 11px; margin-bottom: 10px; }
  .filter-bar input[type="search"] { flex: 2; min-width: 190px; }
  .filter-group { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--text-sec); }
  .filter-group input[type="date"] { padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; font-size: 12.5px; background: var(--bg); color: var(--text); font-family: inherit; }
  .chip-row { display: flex; gap: 6px; flex-wrap: wrap; }
  .chip-btn { padding: 6px 12px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; cursor: pointer; color: var(--text-sec); font-family: inherit; }
  .chip-btn:hover { border-color: var(--accent); color: var(--accent); }
  .chip-btn.active { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }

  .status-row { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; margin: 2px 2px 9px; font-size: 12px; color: var(--text-tert); flex-wrap: wrap; }

  .online-rail { display: flex; gap: 7px; flex-wrap: wrap; margin-bottom: 12px; }
  .online-pill { display: flex; align-items: center; gap: 7px; padding: 6px 13px 6px 10px; border-radius: 100px; border: 1px solid var(--success); background: rgba(31,157,108,0.08); font-size: 12.5px; cursor: pointer; font-family: inherit; color: var(--text); }
  .online-pill:hover { background: rgba(31,157,108,0.16); }
  .online-pill .nm { font-weight: 700; unicode-bidi: isolate; }
  .online-pill .ago { color: var(--text-sec); font-size: 11px; }

  /* The sticky <th> below needs a scroll container that actually scrolls.
     Setting overflow-x alone does not give it one: per spec, overflow-y
     computes from visible to auto as soon as the other axis is not visible,
     so this stayed the sticky containing block AND stayed unscrollable, and
     the header silently never pinned. A max-height is what makes the box
     genuinely scroll, so the header pins against it while 112 rows move
     underneath. */
  .user-table-wrap { border: 1px solid var(--border); border-radius: 12px; overflow: auto; max-height: 72vh; background: var(--surface); }
  table.users { width: 100%; border-collapse: collapse; font-size: 13px; }
  table.users th { text-align: left; padding: 10px 13px; background: var(--bg); border-bottom: 1px solid var(--border); font-size: 10.5px; text-transform: uppercase; letter-spacing: 0.4px; color: var(--text-sec); cursor: pointer; user-select: none; white-space: nowrap; position: sticky; top: 0; z-index: 2; }
  table.users th:hover { color: var(--accent); }
  table.users th .arrow { opacity: 0.35; margin-inline-start: 4px; }
  table.users th.sorted .arrow { opacity: 1; }
  table.users td { padding: 9px 13px; border-bottom: 1px solid var(--border); vertical-align: middle; }
  table.users tr:last-child td { border-bottom: none; }
  table.users tr.row:hover { background: var(--accent-soft); cursor: pointer; }
  .u-name { font-weight: 700; font-size: 13px; unicode-bidi: isolate; }
  .u-email { font-size: 11.5px; color: var(--text-sec); }
  .u-uid { font-family: ui-monospace, Menlo, monospace; font-size: 10.5px; color: var(--text-tert); }
  .u-date { font-size: 12.5px; white-space: nowrap; }
  .u-date .rel { color: var(--text-tert); font-size: 11px; display: block; }
  .u-did { font-size: 11.5px; color: var(--text-tert); max-width: 210px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; unicode-bidi: isolate; }
  .u-num { font-variant-numeric: tabular-nums; font-size: 12.5px; white-space: nowrap; }
  .view-btn { padding: 5px 11px; border-radius: 100px; border: 1px solid var(--border); background: var(--bg); font-size: 11.5px; font-weight: 600; color: var(--accent); white-space: nowrap; }
  .disabled-chip { display: inline-block; margin-inline-start: 6px; padding: 1px 8px; border-radius: 100px; background: rgba(255,90,82,0.14); color: #c23b34; font-size: 10px; font-weight: 700; text-transform: uppercase; }
  .empty-state { padding: 40px 20px; text-align: center; color: var(--text-tert); font-size: 13px; }
  .view { display: none; }
  .view.active { display: block; }

  .warn { display: flex; align-items: flex-start; gap: var(--s3); padding: var(--s3) var(--s4); border: 1px solid #e0847a; background: var(--danger-soft); color: var(--danger); border-radius: var(--r-md); font-size: 12.5px; margin-bottom: var(--s4); }
  .warn b { font-weight: 700; }
  .warn button { margin-inline-start: auto; flex: 0 0 auto; border: 1px solid currentColor; background: transparent; color: inherit; border-radius: var(--r-pill); padding: 2px var(--s3); font-size: 11px; cursor: pointer; font-family: inherit; }
  .warn-list { font-family: var(--mono); font-size: 10.5px; margin-top: var(--s2); white-space: pre-wrap; }

  /* What the feed does NOT contain. Without this, the last row reads as the
     beginning of history rather than as the edge of what was fetched. */
  .horizon { font-size: 11.5px; color: var(--text-tert); line-height: 1.6; margin: var(--s4) var(--s1) 0; }

  /* ---- Quick-look drawer ----------------------------------------------
     Checking five people used to be five page loads and five trips back.
     Everything shown here is already in memory from the one scan, so a row
     opens instantly and the arrow keys walk the list without ever leaving
     the dashboard. The full report is still one click away, for when the
     summary is not enough. */
  /* A click-catcher, not a modal veil.
     This panel is a peek ALONGSIDE the list, not a dialog over it: the whole
     reason it exists is comparing one account against the rows around it and
     arrowing down through them. Dimming the list would fight the feature it
     is part of. On a phone the drawer genuinely covers the content, so the
     dim comes back there and the modal reading is the correct one. */
  /* Transparent AND click-through on desktop.
     A full-screen catcher, even an invisible one, made every row behind it
     unclickable: the drawer said "peek alongside the list" while physically
     sealing the list off, so switching accounts meant closing first. Outside
     clicks are handled in JS instead, which can tell "clicked another row"
     from "clicked away". On a phone the drawer really is modal and the veil
     really should catch. */
  .scrim { position: fixed; inset: 0; background: transparent; z-index: 40; pointer-events: none; }
  @media (max-width: 640px) {
    .scrim { background: rgba(28, 38, 32, 0.28); opacity: 0; transition: opacity 0.16s ease; pointer-events: auto; }
    .scrim.open { opacity: 1; }
  }
  .drawer {
    position: fixed; inset-block: 0; inset-inline-end: 0; width: min(430px, 100vw);
    background: var(--surface); border-inline-start: 1px solid var(--border);
    box-shadow: var(--shadow-lg); z-index: 50; display: flex; flex-direction: column;
    transform: translateX(100%); transition: transform 0.2s cubic-bezier(0.32, 0.72, 0, 1);
  }
  html[dir="rtl"] .drawer { transform: translateX(-100%); }
  .drawer.open { transform: none; }
  .drawer.no-anim, .scrim.no-anim { transition: none; }
  @media (prefers-reduced-motion: reduce) {
    .drawer, .scrim { transition: none; }
  }
  /* On a phone it comes up from the bottom, which is where a thumb is. */
  @media (max-width: 640px) {
    .drawer { inset: auto 0 0 0; width: 100%; max-height: 88vh; border-inline-start: none; border-top: 1px solid var(--border); border-start-start-radius: var(--r-lg); border-start-end-radius: var(--r-lg); transform: translateY(100%); }
    html[dir="rtl"] .drawer { transform: translateY(100%); }
  }

  .dw-head { display: flex; align-items: flex-start; gap: var(--s3); padding: var(--s5) var(--s5) var(--s4); border-bottom: 1px solid var(--border); }
  .dw-head-main { flex: 1 1 auto; min-width: 0; }
  .dw-name { font-size: 17px; font-weight: 700; letter-spacing: -0.2px; unicode-bidi: isolate; overflow: hidden; text-overflow: ellipsis; }
  .dw-mail { font-size: 12.5px; color: var(--text-sec); overflow: hidden; text-overflow: ellipsis; }
  .dw-close { flex: 0 0 auto; width: 30px; height: 30px; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); cursor: pointer; font-size: 15px; line-height: 1; color: var(--text-sec); font-family: inherit; }
  .dw-close:hover { border-color: var(--accent); color: var(--accent); }
  .dw-body { flex: 1 1 auto; overflow-y: auto; padding: var(--s5); }
  .dw-foot { flex: 0 0 auto; display: flex; gap: var(--s2); padding: var(--s4) var(--s5); border-top: 1px solid var(--border); background: var(--bg); }
  .dw-foot .btn { flex: 1; text-align: center; text-decoration: none; }

  .dw-today { display: flex; align-items: center; gap: var(--s4); padding: var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--bg); margin-bottom: var(--s5); }
  .dw-ring { width: 50px; height: 50px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px; border: 3px solid var(--border); flex: 0 0 auto; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .dw-ring.today-full { border-color: var(--success); color: var(--success); }
  .dw-ring.today-partial { border-color: var(--accent); color: var(--accent); }
  .dw-ring.today-none { border-color: #e0847a; color: var(--danger); }
  .dw-today-txt { min-width: 0; }
  .dw-today-title { font-weight: 700; font-size: 13.5px; }
  .dw-today-sub { font-size: 11.5px; color: var(--text-sec); margin-top: 2px; }

  .dw-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--s2); margin-bottom: var(--s5); }
  .dw-cell { border: 1px solid var(--border); border-radius: var(--r-sm); padding: var(--s3); text-align: center; }
  .dw-cell b { display: block; font-size: 15px; font-variant-numeric: tabular-nums; }
  .dw-cell span { display: block; font-size: 9.5px; color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.4px; margin-top: 2px; }

  .dw-h { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-tert); margin: var(--s5) 0 var(--s3); }
  .dw-h:first-child { margin-top: 0; }
  .dw-line { display: flex; justify-content: space-between; gap: var(--s4); padding: var(--s2) 0; font-size: 12.5px; border-bottom: 1px solid var(--border); }
  .dw-line:last-of-type { border-bottom: none; }
  .dw-line dt { color: var(--text-tert); flex: 0 0 auto; }
  .dw-line dd { margin: 0; text-align: end; min-width: 0; unicode-bidi: isolate; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* The person's own recent history, as a timeline rather than a table:
     the whole point is reading down it fast. */
  .dw-tl { position: relative; padding-inline-start: var(--s5); }
  .dw-tl::before { content: ''; position: absolute; inset-block: 6px 6px; inset-inline-start: 5px; width: 1px; background: var(--border); }
  .dw-ev { position: relative; padding: var(--s2) 0 var(--s2) 0; font-size: 12.5px; cursor: pointer; border-radius: var(--r-sm); }
  .dw-ev:hover { background: var(--accent-soft); }
  .dw-ev::before { content: ''; position: absolute; inset-inline-start: calc(var(--s5) * -1 + 2px); top: 13px; width: 7px; height: 7px; border-radius: 50%; background: var(--border); border: 1px solid var(--surface); }
  .dw-ev.fresh::before { background: var(--success); }
  .dw-ev-top { display: flex; justify-content: space-between; gap: var(--s3); }
  .dw-ev-what { min-width: 0; unicode-bidi: isolate; }
  .dw-ev-when { flex: 0 0 auto; color: var(--text-tert); font-size: 11px; font-variant-numeric: tabular-nums; }
  .dw-ev-sub { color: var(--text-tert); font-size: 11.5px; margin-top: 1px; unicode-bidi: isolate; overflow: hidden; text-overflow: ellipsis; }

  .dw-hint { font-size: 11px; color: var(--text-tert); text-align: center; padding: var(--s3) 0 0; }
  .dw-hint kbd { font-family: var(--mono); font-size: 10px; border: 1px solid var(--border); border-radius: 4px; padding: 1px 4px; background: var(--bg); }

  /* A row currently shown in the drawer, so arrowing through the list is
     visible in the list too, not only in the panel. */
  .ev.picked, tr.row.picked > td, .rcard.picked { background: var(--accent-soft); }
  tr.row.picked > td:first-child { box-shadow: inset 3px 0 0 var(--accent); }

  /* Day roster: every account's standing on one specific day, read straight
     from that day's own documents. The activity feed only carries the recent
     window the scan pulled, so without this a day from three months ago
     looked like a day on which nobody existed. */
  .roster-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; flex-wrap: wrap; margin: 2px 2px 8px; }
  .roster-head h3 { margin: 0; }
  .roster { display: grid; grid-template-columns: repeat(auto-fill, minmax(228px, 1fr)); gap: 8px; margin-bottom: 16px; }
  .rcard { display: flex; align-items: center; gap: 10px; border: 1px solid var(--border); border-radius: 11px; padding: 9px 11px; background: var(--surface); cursor: pointer; text-align: start; font-family: inherit; color: var(--text); }
  .rcard:hover { border-color: var(--accent); background: var(--accent-soft); }
  .rcard-main { flex: 1 1 auto; min-width: 0; display: block; }
  .rcard-name { display: block; font-weight: 700; font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; unicode-bidi: isolate; }
  .rcard-sub { display: block; font-size: 11px; color: var(--text-tert); margin-top: 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
</head>
<body>
  <div class="lockup">
    <div>
      <h1>GrowDaily — Admin Lookup</h1>
      <p id="scanNote">Loading every account…</p>
    </div>
    <div class="right">
      <button class="btn primary" id="refresh" title="Re-read every account from Firestore right now">⟳ Refresh</button>
    </div>
  </div>

  <div class="live-strip" id="liveStrip"></div>
  <div class="warn" id="scanWarn" hidden></div>

  <div class="view-tabs">
    <button class="view-tab active" data-view="activity">Activity <span class="vt-count" id="cntActivity"></span></button>
    <button class="view-tab" data-view="accounts">Accounts <span class="vt-count" id="cntAccounts"></span></button>
  </div>

  <!-- ============ ACTIVITY ============ -->
  <div class="view active" id="viewActivity">
    <div class="filter-bar">
      <input id="qA" type="search" placeholder="Search person, habit, task, milestone…" autofocus>
      <div class="filter-group">
        <span>Day</span>
        <input id="feedDay" type="date" title="Show only this day">
      </div>
      <div class="chip-row" id="feedRanges">
        <button class="chip-btn active" data-days="0">All</button>
        <button class="chip-btn" data-days="1">Today</button>
        <button class="chip-btn" data-days="7">7 days</button>
        <button class="chip-btn" data-days="30">30 days</button>
      </div>
      <button class="btn" id="clearA">Clear</button>
    </div>
    <div class="chip-row" id="typeChips" style="margin-bottom:10px;">
      <button class="chip-btn active" data-type="">Everything</button>
      <button class="chip-btn" data-type="habits">Habits logged</button>
      <button class="chip-btn" data-type="task_new,task_done">Tasks</button>
      <button class="chip-btn" data-type="milestone">Milestones</button>
      <button class="chip-btn" data-type="habit_new,habit_archived">Habit edits</button>
      <button class="chip-btn" data-type="focus">Focus</button>
      <button class="chip-btn" data-type="signup,signin">Sign ups &amp; ins</button>
    </div>

    <div class="online-rail" id="onlineRail"></div>
    <div id="dayRoster" hidden></div>
    <div class="status-row"><span id="statusA">Loading…</span><span id="dayStat"></span></div>
    <div class="feed" id="feed"></div>
    <p class="horizon" id="horizon"></p>
  </div>

  <!-- ============ ACCOUNTS ============ -->
  <div class="view" id="viewAccounts">
    <div class="filter-bar">
      <input id="qU" type="search" placeholder="Search name, email, or uid…">
      <div class="filter-group">
        <span>Created</span>
        <input id="fromDate" type="date" title="Created on or after">
        <span>to</span>
        <input id="toDate" type="date" title="Created on or before">
      </div>
      <div class="chip-row" id="quickRanges">
        <button class="chip-btn active" data-days="0">Any time</button>
        <button class="chip-btn" data-days="1">Today</button>
        <button class="chip-btn" data-days="7">7 days</button>
        <button class="chip-btn" data-days="30">30 days</button>
        <button class="chip-btn" data-days="90">90 days</button>
      </div>
      <button class="chip-btn" id="onlyActive" data-on="0">Active only</button>
      <button class="btn" id="clearU">Clear</button>
    </div>
    <div class="status-row"><span id="statusU">Loading…</span></div>
    <div class="user-table-wrap">
      <table class="users">
        <thead>
          <tr>
            <th data-sort="account">Account <span class="arrow">↕</span></th>
            <th data-sort="today">Today <span class="arrow">↕</span></th>
            <th data-sort="lastActiveAt">Last active <span class="arrow">↕</span></th>
            <th data-sort="did">What they did</th>
            <th data-sort="level">Lvl <span class="arrow">↕</span></th>
            <th data-sort="currentStreak">Streak <span class="arrow">↕</span></th>
            <th data-sort="createdAt">Created <span class="arrow">↕</span></th>
            <th></th>
          </tr>
        </thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
  </div>

  <div class="scrim" id="scrim" hidden></div>
  <aside class="drawer" id="drawer" hidden aria-label="Account quick look" tabindex="-1"></aside>

<script>
(function () {
  // ---- Everything the page knows, loaded once from /api/dashboard ----
  var DATA = { accounts: [], events: [], onlineWindowMinutes: 15 };
  var EV_ICON = {
    habits: '✅', task_new: '➕', task_done: '☑️', habit_new: '⭐',
    habit_archived: '📦', milestone: '🏆', focus: '🎯', signup: '🆕', signin: '🔑'
  };

  var $ = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function ago(ms) {
    var s = Math.floor((Date.now() - ms) / 1000);
    if (s < 45) return 'just now';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    var d = Math.floor(s / 86400);
    if (d < 30) return d + 'd ago';
    return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }
  function fmtDate(iso) {
    if (!iso) return { abs: '—', rel: '' };
    var d = new Date(iso);
    if (isNaN(d.getTime())) return { abs: '—', rel: '' };
    return {
      abs: d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }),
      rel: ago(d.getTime())
    };
  }
  // Local calendar day of a timestamp, as YYYY-MM-DD. Deliberately local
  // and not toISOString(): the admin reads this page on their own clock,
  // and a UTC slice puts anything after 8pm Bahrain time on "tomorrow".
  function dayKeyOf(ms) {
    var d = new Date(ms);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0')
      + '-' + String(d.getDate()).padStart(2, '0');
  }
  function goTo(uid, day) {
    window.location.href = '/report/' + encodeURIComponent(uid) + (day ? '?day=' + day : '');
  }

  // ================= QUICK-LOOK DRAWER =================
  //
  // A row click opens this instead of navigating. Everything in it is
  // already in memory from the one scan, so it is instant, and the arrow
  // keys walk whichever list is on screen without a single page load. The
  // full report stays one click away in the footer for when the summary
  // does not settle the question.
  var drawer = $('drawer');
  var scrim = $('scrim');
  var drawerUid = null;
  var drawerDay = null;   // the day the row was clicked from, when it had one
  var lastFocus = null;

  function rowsInView() {
    var sel = currentView === 'activity'
      ? '#viewActivity .ev[data-uid], #viewActivity .rcard[data-uid]'
      : '#viewAccounts tr.row[data-uid]';
    return Array.prototype.slice.call(document.querySelectorAll(sel));
  }

  function markPicked(uid) {
    Array.prototype.forEach.call(
      document.querySelectorAll('.picked'), function (el) { el.classList.remove('picked'); });
    if (!uid) return;
    // The first row for that account, not every row: an active person has
    // dozens of feed entries, and lighting all of them says "these rows are
    // selected" when what is meant is "this is the one you are reading".
    var rows = rowsInView();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].getAttribute('data-uid') === uid) { rows[i].classList.add('picked'); return; }
    }
  }

  function drawerHtml(a) {
    var onlineMs = DATA.onlineWindowMinutes * 60000;
    var mine = DATA.events.filter(function (e) { return e.uid === a.uid; }).slice(0, 30);
    var ringCls = a.todayScheduled === 0 ? ''
      : a.todayDone === a.todayScheduled ? 'today-full'
      : a.todayDone === 0 ? 'today-none' : 'today-partial';
    var todayTitle = a.todayScheduled === 0
      ? 'Nothing due today'
      : a.todayDone + ' of ' + a.todayScheduled + ' done today';

    var line = function (k, v) {
      return '<div class="dw-line"><dt>' + esc(k) + '</dt><dd>' + v + '</dd></div>';
    };
    var cell = function (v, k) {
      return '<div class="dw-cell"><b>' + (v == null ? '—' : esc(v)) + '</b><span>' + esc(k) + '</span></div>';
    };

    return '<div class="dw-head">'
      + '<div class="dw-head-main">'
      + '<div class="dw-name">' + esc(a.displayName || '(no name set)')
      + (a.disabled ? '<span class="disabled-chip">Disabled</span>' : '') + '</div>'
      + '<div class="dw-mail">' + esc(a.email || '(no email)') + '</div>'
      + '</div>'
      + '<button class="dw-close" id="dwClose" title="Close (Esc)">✕</button>'
      + '</div>'

      + '<div class="dw-body">'
      + '<div class="dw-today"><div class="dw-ring ' + ringCls + '">'
      + (a.todayScheduled ? a.todayDone + '/' + a.todayScheduled : '—') + '</div>'
      + '<div class="dw-today-txt"><div class="dw-today-title">' + esc(todayTitle) + '</div>'
      + '<div class="dw-today-sub">' + esc(a.todayKey || '')
      + (a.lastActiveAt
          ? ' · last write ' + ago(new Date(a.lastActiveAt).getTime())
          : ' · never written') + '</div></div></div>'

      + '<div class="dw-grid">'
      + cell(a.level, 'Level') + cell(a.currentStreak, 'Streak') + cell(a.gold, 'Gold')
      + cell(a.totalHabitCompletions, 'Done') + cell(a.habitCount, 'Habits')
      + cell(a.locale || '—', 'Locale')
      + '</div>'

      + '<div class="dw-h">Account</div>'
      + line('Created', esc(fmtDate(a.createdAt).abs))
      + line('Last sign-in', a.lastSignIn ? esc(ago(new Date(a.lastSignIn).getTime())) : '<span class="muted">never</span>')
      + line('On the app now', (a.lastActiveAt && Date.now() - new Date(a.lastActiveAt).getTime() <= onlineMs)
          ? '<span class="bool true">yes</span>' : '<span class="muted">no</span>')
      + line('uid', '<button class="uid-copy" data-copy="' + esc(a.uid)
          + '"><span class="uid">' + esc(a.uid) + '</span><span class="uid-copy-ico">⧉</span></button>')

      + '<div class="dw-h">Recent activity</div>'
      + (mine.length === 0
        ? '<p class="muted">Nothing recorded for this account.</p>'
        : '<div class="dw-tl">' + mine.map(function (e) {
            var fresh = (Date.now() - e.at) <= onlineMs;
            return '<div class="dw-ev' + (fresh ? ' fresh' : '') + '" data-day="'
              + esc(e.dayKey || dayKeyOf(e.at)) + '">'
              + '<div class="dw-ev-top"><span class="dw-ev-what">'
              + (EV_ICON[e.type] || '•') + ' ' + esc(e.title) + '</span>'
              + '<span class="dw-ev-when">' + ago(e.at) + '</span></div>'
              + (e.sub ? '<div class="dw-ev-sub">' + esc(e.sub) + '</div>' : '')
              + '</div>';
          }).join('') + '</div>')
      + '<div class="dw-hint"><kbd>↑</kbd> <kbd>↓</kbd> next account · <kbd>Enter</kbd> full report · <kbd>Esc</kbd> close</div>'
      + '</div>'

      + '<div class="dw-foot">'
      + '<a class="btn" href="/report/' + encodeURIComponent(a.uid) + '">Full report</a>'
      + '<a class="btn primary" href="/report/' + encodeURIComponent(a.uid)
      + '?day=' + esc(drawerDay || a.todayKey) + '">'
      + (drawerDay && drawerDay !== a.todayKey ? 'Open ' + esc(drawerDay) : 'Open today') + '</a>'
      + '</div>';
  }

  function openDrawer(uid, dayContext) {
    drawerDay = dayContext || null;
    var a = null;
    for (var i = 0; i < DATA.accounts.length; i++) {
      if (DATA.accounts[i].uid === uid) { a = DATA.accounts[i]; break; }
    }
    if (!a) return;
    if (!drawerUid) lastFocus = document.activeElement;
    drawerUid = uid;
    drawer.innerHTML = drawerHtml(a);
    drawer.hidden = false;
    scrim.hidden = false;
    // Skip the slide entirely unless this document is actually visible.
    //
    // A transition on a hidden document does not progress: it sits pinned at
    // its start value, which for this panel means fully translated off the
    // screen. Open a row, switch away mid-animation, come back, and the
    // drawer is "open" with nothing on screen. Jumping straight to the end
    // state when there is nobody watching costs nothing and removes the
    // whole class of stuck-panel bug.
    var animate = document.visibilityState === 'visible';
    drawer.classList.toggle('no-anim', !animate);
    scrim.classList.toggle('no-anim', !animate);
    // Force a reflow so the transition has a start state, rather than
    // waiting for an animation frame: rAF does not fire in a tab that is not
    // being painted either.
    void drawer.offsetHeight;
    drawer.classList.add('open');
    scrim.classList.add('open');
    markPicked(uid);
    drawer.focus();
    // A timeline entry jumps straight to the day it happened on.
    Array.prototype.forEach.call(drawer.querySelectorAll('.dw-ev'), function (row) {
      row.addEventListener('click', function () {
        goTo(uid, row.getAttribute('data-day'));
      });
    });
    var close = $('dwClose');
    if (close) close.addEventListener('click', closeDrawer);
  }

  function closeDrawer() {
    if (!drawerUid) return;
    drawerUid = null;
    drawer.classList.remove('open');
    scrim.classList.remove('open');
    markPicked(null);
    // Kept in the DOM until the slide-out finishes, then hidden so it is out
    // of the tab order rather than sitting invisibly in it.
    setTimeout(function () {
      if (!drawerUid) { drawer.hidden = true; scrim.hidden = true; drawer.innerHTML = ''; }
    }, 200);
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function stepDrawer(delta) {
    var rows = rowsInView();
    var uids = [];
    rows.forEach(function (el) {
      var u = el.getAttribute('data-uid');
      if (uids.indexOf(u) === -1) uids.push(u);
    });
    if (uids.length === 0) return;
    var at = uids.indexOf(drawerUid);
    var next = at === -1 ? 0 : Math.min(uids.length - 1, Math.max(0, at + delta));
    if (next === at) return;
    openDrawer(uids[next], drawerDay);
    var el = rows.filter(function (r) { return r.getAttribute('data-uid') === uids[next]; })[0];
    if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' });
  }

  // Copy-to-clipboard for the uid pill in the drawer.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('[data-copy]');
    if (!btn) return;
    var done = function () {
      btn.classList.add('copied');
      setTimeout(function () { btn.classList.remove('copied'); }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(btn.getAttribute('data-copy')).then(done, function () {});
    }
  });

  scrim.addEventListener('click', closeDrawer); // the mobile veil

  // Clicking away closes; clicking another row just swaps to it, because the
  // rows keep their own handlers and this deliberately does not treat them
  // as "outside".
  document.addEventListener('click', function (e) {
    if (!drawerUid) return;
    if (!e.target.closest) return;
    if (e.target.closest('#drawer')) return;
    if (e.target.closest('[data-uid]')) return;
    closeDrawer();
  });
  document.addEventListener('keydown', function (e) {
    var tag = (e.target.tagName || '').toLowerCase();
    var typing = tag === 'input' || tag === 'textarea' || tag === 'select';
    if (e.key === 'Escape') {
      if (drawerUid) { e.preventDefault(); closeDrawer(); }
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (!drawerUid) return;
    if (e.key === 'ArrowDown' || e.key === 'j') { e.preventDefault(); stepDrawer(1); }
    else if (e.key === 'ArrowUp' || e.key === 'k') { e.preventDefault(); stepDrawer(-1); }
    else if (e.key === 'Enter') { e.preventDefault(); goTo(drawerUid); }
  });

  // ---- View tabs ----
  var currentView = 'activity';
  Array.prototype.forEach.call(document.querySelectorAll('.view-tab'), function (t) {
    t.addEventListener('click', function () {
      currentView = t.getAttribute('data-view');
      Array.prototype.forEach.call(document.querySelectorAll('.view-tab'), function (o) {
        o.classList.toggle('active', o === t);
      });
      $('viewActivity').classList.toggle('active', currentView === 'activity');
      $('viewAccounts').classList.toggle('active', currentView === 'accounts');
    });
  });

  // ================= LIVE STRIP =================
  function renderLive() {
    var now = Date.now();
    var onlineMs = DATA.onlineWindowMinutes * 60000;
    var online = [], today = [], week = [];
    DATA.accounts.forEach(function (a) {
      if (!a.lastActiveAt) return;
      var t = new Date(a.lastActiveAt).getTime();
      if (now - t <= onlineMs) online.push(a);
      if (dayKeyOf(t) === dayKeyOf(now)) today.push(a);
      if (now - t <= 7 * 86400000) week.push(a);
    });
    online.sort(function (a, b) { return new Date(b.lastActiveAt) - new Date(a.lastActiveAt); });

    var card = function (v, label, hot, dot) {
      return '<div class="live-card' + (hot ? ' hot' : '') + '">'
        + '<div class="live-value">' + (dot ? '<span class="live-dot"></span>' : '') + v + '</div>'
        + '<div class="live-label">' + label + '</div></div>';
    };
    $('liveStrip').innerHTML =
      card(online.length, 'On the app now', online.length > 0, online.length > 0)
      + card(today.length, 'Active today')
      + card(week.length, 'Active this week')
      + card(DATA.accounts.length, 'Accounts total');

    $('onlineRail').innerHTML = online.length === 0 ? '' : online.map(function (a) {
      return '<button class="online-pill" data-uid="' + esc(a.uid) + '">'
        + '<span class="live-dot"></span>'
        + '<span class="nm bidi">' + esc(a.displayName || a.email || a.uid.slice(0, 8)) + '</span>'
        + '<span class="ago">' + ago(new Date(a.lastActiveAt).getTime()) + '</span></button>';
    }).join('');
    Array.prototype.forEach.call($('onlineRail').querySelectorAll('.online-pill'), function (p) {
      p.addEventListener('click', function () { openDrawer(p.getAttribute('data-uid')); });
    });
  }

  // ================= ACTIVITY FEED =================
  var feedTypes = '';
  function feedFiltered() {
    var q = $('qA').value.trim().toLowerCase();
    var day = $('feedDay').value;
    var types = feedTypes ? feedTypes.split(',') : null;
    // Calendar days, not rolling hours. "Today" measured as now minus 24h
    // put half of yesterday under a chip labelled Today, and disagreed with
    // the Accounts view's own Today chip, which has always been calendar.
    var cutoff = 0;
    if (feedRangeDays) {
      var start = new Date();
      start.setHours(0, 0, 0, 0);
      start.setDate(start.getDate() - (feedRangeDays - 1));
      cutoff = start.getTime();
    }
    return DATA.events.filter(function (e) {
      if (types && types.indexOf(e.type) === -1) return false;
      if (day && dayKeyOf(e.at) !== day) return false;
      if (cutoff && e.at < cutoff) return false;
      if (q) {
        var hay = (e.who + ' ' + e.email + ' ' + e.title + ' ' + e.sub + ' ' + e.uid).toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });
  }
  var FEED_PAGE = 300;
  var feedShown = FEED_PAGE;
  function renderFeed() {
    var list = feedFiltered();
    $('statusA').textContent = 'Showing ' + Math.min(list.length, feedShown)
      + ' of ' + list.length + ' event' + (list.length === 1 ? '' : 's');
    var day = $('feedDay').value;
    $('dayStat').textContent = day
      ? (function () {
          var people = {};
          list.forEach(function (e) { people[e.uid] = 1; });
          return Object.keys(people).length + ' account(s) in the feed for this day';
        })()
      : '';
    if (list.length === 0) {
      $('feed').innerHTML = '<div class="empty-state">Nothing matches these filters.</div>';
      return;
    }
    var out = [], lastDay = null;
    var onlineMs = DATA.onlineWindowMinutes * 60000;
    list.slice(0, feedShown).forEach(function (e) {
      var d = dayKeyOf(e.at);
      if (d !== lastDay) {
        lastDay = d;
        var label = d === dayKeyOf(Date.now()) ? 'Today · ' + d
          : d === dayKeyOf(Date.now() - 86400000) ? 'Yesterday · ' + d : d;
        out.push('<div class="feed-day">' + esc(label) + '</div>');
      }
      var live = (Date.now() - e.at) <= onlineMs;
      out.push('<div class="ev" data-uid="' + esc(e.uid) + '" data-day="' + esc(e.dayKey || d) + '">'
        + '<div class="ev-ico">' + (EV_ICON[e.type] || '•') + '</div>'
        + '<div class="ev-main"><div class="ev-who"><span class="bidi">' + esc(e.who) + '</span>'
        + (e.email && e.email !== e.who ? '<span class="ev-mail bidi">' + esc(e.email) + '</span>' : '')
        + '</div><div class="ev-what">' + esc(e.title)
        + (e.sub ? ' <span class="ev-sub">· ' + esc(e.sub) + '</span>' : '') + '</div></div>'
        + '<div class="ev-when' + (live ? ' ev-live' : '') + '">' + ago(e.at) + '</div></div>');
    });
    if (list.length > feedShown) {
      out.push('<div class="ev" id="feedMore" style="justify-content:center;color:var(--accent);font-weight:600;">'
        + 'Show ' + Math.min(FEED_PAGE, list.length - feedShown) + ' more</div>');
    }
    $('feed').innerHTML = out.join('');
    Array.prototype.forEach.call($('feed').querySelectorAll('.ev[data-uid]'), function (row) {
      row.addEventListener('click', function (e) {
        // Cmd/ctrl click still means "take me there", the way a link does.
        if (e.metaKey || e.ctrlKey) {
          goTo(row.getAttribute('data-uid'), row.getAttribute('data-day'));
          return;
        }
        openDrawer(row.getAttribute('data-uid'), row.getAttribute('data-day'));
      });
    });
    var more = $('feedMore');
    if (more) more.addEventListener('click', function () { feedShown += FEED_PAGE; renderFeed(); });
    markPicked(drawerUid);
  }

  // ---- Day roster: one specific day, read straight from Firestore.
  //
  // The feed can only show what the scan pulled (a recent window per
  // account), so picking a day last spring would show an empty page and
  // read as "nothing happened" rather than "not loaded". This asks the
  // server for that exact day instead, so the day picker reaches the whole
  // history rather than only as far back as the cache.
  var rosterFor = null;
  function loadRoster(day) {
    var box = $('dayRoster');
    if (!day) { box.hidden = true; box.innerHTML = ''; rosterFor = null; return; }
    if (rosterFor === day) return;
    rosterFor = day;
    box.hidden = false;
    box.innerHTML = '<div class="status-row"><span>Reading ' + esc(day) + ' for every account…</span></div>';
    fetch('/api/day/' + encodeURIComponent(day))
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (rosterFor !== day) return; // a newer day was picked mid-flight
        if (d.error) throw new Error(d.error);
        var byUid = {};
        DATA.accounts.forEach(function (a) { byUid[a.uid] = a; });
        var rows = d.rows.filter(function (r) { return r.hasDoc || r.scheduled > 0; });
        rows.sort(function (a, b) {
          var ar = a.scheduled ? a.done / a.scheduled : -1;
          var br = b.scheduled ? b.done / b.scheduled : -1;
          return br - ar || b.done - a.done;
        });
        var logged = d.rows.filter(function (r) { return r.hasDoc; }).length;
        var due = d.rows.filter(function (r) { return r.scheduled > 0; }).length;
        box.innerHTML =
          '<div class="roster-head"><h3>On ' + esc(day) + '</h3><span class="muted">'
          + logged + ' of ' + d.rows.length + ' accounts logged this day · '
          + due + ' had a habit due · showing ' + rows.length + '</span></div>'
          + (rows.length === 0
            ? '<div class="empty-state">No account had a habit due or anything logged on this day.</div>'
            : '<div class="roster">' + rows.map(function (r) {
                var a = byUid[r.uid] || {};
                var cls = r.scheduled === 0 ? '' : r.done === r.scheduled ? 'today-full'
                  : r.done === 0 ? 'today-none' : 'today-partial';
                var sub = [];
                if (r.lastUpdated) {
                  sub.push('last write ' + new Date(r.lastUpdated)
                    .toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' }));
                }
                if (r.mood) sub.push(r.mood);
                if (r.nightReviewDone) sub.push('night review');
                if (r.reflection) sub.push('reflection');
                if (!r.hasDoc) sub.push('nothing logged');
                return '<button class="rcard" data-uid="' + esc(r.uid) + '">'
                  + '<span class="mini-ring ' + cls + '">'
                  + (r.scheduled ? r.done + '/' + r.scheduled : '—') + '</span>'
                  + '<span class="rcard-main"><span class="rcard-name bidi">'
                  + esc(a.displayName || a.email || r.uid.slice(0, 10)) + '</span>'
                  + '<span class="rcard-sub">' + esc(sub.join(' · ') || 'logged, no detail') + '</span></span>'
                  + '</button>';
              }).join('') + '</div>');
        Array.prototype.forEach.call(box.querySelectorAll('.rcard'), function (c) {
          c.addEventListener('click', function (e) {
            if (e.metaKey || e.ctrlKey) { goTo(c.getAttribute('data-uid'), day); return; }
            openDrawer(c.getAttribute('data-uid'), day);
          });
        });
      })
      .catch(function (e) {
        if (rosterFor !== day) return;
        box.innerHTML = '<div class="empty-state">Could not read ' + esc(day) + ': ' + esc(e.message) + '</div>';
      });
  }

  var feedRangeDays = 0;
  Array.prototype.forEach.call($('feedRanges').querySelectorAll('.chip-btn'), function (c) {
    c.addEventListener('click', function () {
      feedRangeDays = Number(c.getAttribute('data-days'));
      Array.prototype.forEach.call($('feedRanges').querySelectorAll('.chip-btn'), function (o) {
        o.classList.toggle('active', o === c);
      });
      $('feedDay').value = '';
      loadRoster('');
      feedShown = FEED_PAGE;
      renderFeed();
    });
  });
  Array.prototype.forEach.call($('typeChips').querySelectorAll('.chip-btn'), function (c) {
    c.addEventListener('click', function () {
      feedTypes = c.getAttribute('data-type') || '';
      Array.prototype.forEach.call($('typeChips').querySelectorAll('.chip-btn'), function (o) {
        o.classList.toggle('active', o === c);
      });
      feedShown = FEED_PAGE;
      renderFeed();
    });
  });
  $('qA').addEventListener('input', function () { feedShown = FEED_PAGE; renderFeed(); });
  // Picking an exact day and holding a rolling range are two answers to the
  // same question, so choosing one clears the other rather than silently
  // intersecting into an empty feed.
  $('feedDay').addEventListener('change', function () {
    loadRoster($('feedDay').value);
    feedRangeDays = 0;
    var picked = !!$('feedDay').value;
    Array.prototype.forEach.call($('feedRanges').querySelectorAll('.chip-btn'), function (o) {
      o.classList.toggle('active', !picked && o.getAttribute('data-days') === '0');
    });
    feedShown = FEED_PAGE;
    renderFeed();
  });
  $('clearA').addEventListener('click', function () {
    $('qA').value = ''; $('feedDay').value = ''; feedTypes = ''; feedRangeDays = 0;
    loadRoster('');
    Array.prototype.forEach.call($('typeChips').querySelectorAll('.chip-btn'), function (o, i) {
      o.classList.toggle('active', i === 0);
    });
    Array.prototype.forEach.call($('feedRanges').querySelectorAll('.chip-btn'), function (o, i) {
      o.classList.toggle('active', i === 0);
    });
    feedShown = FEED_PAGE;
    renderFeed();
  });

  // ================= ACCOUNTS TABLE =================
  var sortKey = 'lastActiveAt';
  var sortDir = 'desc';
  var headers = document.querySelectorAll('table.users th[data-sort]');
  var activeOnly = false;

  function userMatches(u) {
    var needle = $('qU').value.trim().toLowerCase();
    if (needle) {
      var hay = (u.email + ' ' + u.displayName + ' ' + u.uid + ' ' + (u.lastActionSub || '')).toLowerCase();
      if (hay.indexOf(needle) === -1) return false;
    }
    if (activeOnly && !u.lastActiveAt) return false;
    var from = $('fromDate').value, to = $('toDate').value;
    if (from || to) {
      if (!u.createdAt) return false;
      var c = new Date(u.createdAt).getTime();
      if (from && c < new Date(from + 'T00:00:00').getTime()) return false;
      if (to && c > new Date(to + 'T23:59:59').getTime()) return false;
    }
    return true;
  }
  function sortedUsers() {
    var list = DATA.accounts.filter(userMatches);
    list.sort(function (a, b) {
      var av, bv;
      if (sortKey === 'account') {
        av = (a.displayName || a.email || '').toLowerCase();
        bv = (b.displayName || b.email || '').toLowerCase();
      } else if (sortKey === 'today') {
        av = a.todayScheduled ? a.todayDone / a.todayScheduled : -1;
        bv = b.todayScheduled ? b.todayDone / b.todayScheduled : -1;
      } else if (sortKey === 'did') {
        av = (a.lastActionText || '').toLowerCase(); bv = (b.lastActionText || '').toLowerCase();
      } else if (sortKey === 'level' || sortKey === 'currentStreak') {
        av = a[sortKey] == null ? -1 : a[sortKey];
        bv = b[sortKey] == null ? -1 : b[sortKey];
      } else {
        av = a[sortKey] ? new Date(a[sortKey]).getTime() : 0;
        bv = b[sortKey] ? new Date(b[sortKey]).getTime() : 0;
      }
      if (av < bv) return sortDir === 'asc' ? -1 : 1;
      if (av > bv) return sortDir === 'asc' ? 1 : -1;
      return 0;
    });
    return list;
  }
  function renderUsers() {
    var list = sortedUsers();
    $('statusU').textContent = 'Showing ' + list.length + ' of ' + DATA.accounts.length
      + ' account' + (DATA.accounts.length === 1 ? '' : 's');
    if (list.length === 0) {
      $('rows').innerHTML = '<tr><td colspan="8"><div class="empty-state">No accounts match these filters.</div></td></tr>';
      return;
    }
    var onlineMs = DATA.onlineWindowMinutes * 60000;
    $('rows').innerHTML = list.map(function (u) {
      var created = fmtDate(u.createdAt);
      var active = fmtDate(u.lastActiveAt);
      var isOnline = u.lastActiveAt && (Date.now() - new Date(u.lastActiveAt).getTime()) <= onlineMs;
      // A row whose scan failed must not render as "0 done, never active":
      // that is a claim about the person, and we do not have it.
      var ring = u.scanFailed
        ? '<span class="mini-ring" title="Could not be read">?</span>'
        : u.todayScheduled > 0
          ? '<span class="mini-ring today-' + (u.todayDone === u.todayScheduled ? 'full'
              : u.todayDone === 0 ? 'none' : 'partial') + '">' + u.todayDone + '/' + u.todayScheduled + '</span>'
          : '<span class="mini-ring">—</span>';
      return '<tr class="row" data-uid="' + esc(u.uid) + '">'
        + '<td><div class="u-name">' + (isOnline ? '<span class="online-dot"></span>' : '')
          + '<span class="bidi">' + esc(u.displayName || '(no name set)') + '</span>'
          + (u.disabled ? '<span class="disabled-chip">Disabled</span>' : '') + '</div>'
          + '<div class="u-email">' + esc(u.email || '(no email)') + '</div>'
          + '<div class="u-uid">' + esc(u.uid) + '</div></td>'
        + '<td>' + ring + '</td>'
        + '<td class="u-date">' + (u.lastActiveAt ? active.rel
            : u.scanFailed ? '<span class="muted">unknown</span>' : '<span class="muted">never</span>')
          + (u.lastActiveAt ? '<span class="rel">' + active.abs + '</span>' : '') + '</td>'
        + '<td class="u-did"><span class="bidi">'
          + (u.scanFailed ? 'could not be read' : esc(u.lastActionText || '—')) + '</span>'
          + (u.lastActionSub ? ' · <span class="bidi">' + esc(u.lastActionSub) + '</span>' : '') + '</td>'
        + '<td class="u-num">' + (u.level == null ? '—' : esc(u.level)) + '</td>'
        + '<td class="u-num">' + (u.currentStreak == null ? '—' : esc(u.currentStreak)) + '</td>'
        + '<td class="u-date">' + created.abs + '<span class="rel">' + created.rel + '</span></td>'
        + '<td><span class="view-btn">View →</span></td></tr>';
    }).join('');
    markPicked(drawerUid);
    Array.prototype.forEach.call($('rows').querySelectorAll('tr.row'), function (tr) {
      tr.addEventListener('click', function (e) {
        // The explicit View button is the one that navigates; the row itself
        // peeks, so comparing several accounts costs no page loads.
        if (e.target.closest('.view-btn') || e.metaKey || e.ctrlKey) {
          goTo(tr.getAttribute('data-uid'));
          return;
        }
        openDrawer(tr.getAttribute('data-uid'));
      });
    });
  }
  function updateArrows() {
    Array.prototype.forEach.call(headers, function (th) {
      var key = th.getAttribute('data-sort');
      th.classList.toggle('sorted', key === sortKey);
      var arrow = th.querySelector('.arrow');
      if (arrow) arrow.textContent = key !== sortKey ? '↕' : (sortDir === 'asc' ? '↑' : '↓');
    });
  }
  Array.prototype.forEach.call(headers, function (th) {
    th.addEventListener('click', function () {
      var key = th.getAttribute('data-sort');
      if (sortKey === key) sortDir = sortDir === 'asc' ? 'desc' : 'asc';
      else { sortKey = key; sortDir = (key === 'account' || key === 'did') ? 'asc' : 'desc'; }
      updateArrows(); renderUsers();
    });
  });
  function setQuickRange(days) {
    Array.prototype.forEach.call($('quickRanges').querySelectorAll('.chip-btn'), function (c) {
      c.classList.toggle('active', c.getAttribute('data-days') === String(days));
    });
    if (days === 0) { $('fromDate').value = ''; $('toDate').value = ''; }
    else {
      var from = new Date();
      from.setDate(from.getDate() - (days - 1));
      $('fromDate').value = dayKeyOf(from.getTime());
      $('toDate').value = dayKeyOf(Date.now());
    }
    renderUsers();
  }
  Array.prototype.forEach.call($('quickRanges').querySelectorAll('.chip-btn'), function (c) {
    c.addEventListener('click', function () { setQuickRange(Number(c.getAttribute('data-days'))); });
  });
  $('qU').addEventListener('input', renderUsers);
  function clearQuickChips() {
    Array.prototype.forEach.call($('quickRanges').querySelectorAll('.chip-btn'), function (c) {
      c.classList.remove('active');
    });
  }
  $('fromDate').addEventListener('change', function () { clearQuickChips(); renderUsers(); });
  $('toDate').addEventListener('change', function () { clearQuickChips(); renderUsers(); });
  $('onlyActive').addEventListener('click', function () {
    activeOnly = !activeOnly;
    $('onlyActive').classList.toggle('active', activeOnly);
    renderUsers();
  });
  $('clearU').addEventListener('click', function () {
    $('qU').value = ''; activeOnly = false;
    $('onlyActive').classList.remove('active');
    setQuickRange(0);
  });

  // ================= LOAD =================
  // Say what the feed cannot show, rather than letting its last row imply
  // there is nothing older. The day picker above reads any day directly and
  // has no such horizon, so this points at the way out too.
  function renderHorizon() {
    var L = DATA.limits;
    if (!L) { $('horizon').textContent = ''; return; }
    $('horizon').textContent =
      'This feed reaches back at most ' + L.daily + ' logged days, ' + L.tasksCreated
      + ' added and ' + L.tasksCompleted + ' finished tasks, ' + L.milestones
      + ' milestones and ' + L.focusPlans + ' focus plans PER ACCOUNT. '
      + 'Anything older is not missing from the data, only from this list: '
      + 'pick a day above to read that day straight from Firestore, or open an '
      + 'account for its full history.';
  }

  function renderWarn() {
    var box = $('scanWarn');
    var f = DATA.failures || [];
    if (f.length === 0) { box.hidden = true; box.innerHTML = ''; return; }
    box.hidden = false;
    box.innerHTML = '<div><b>' + f.length + ' account' + (f.length === 1 ? '' : 's')
      + ' could not be read in full.</b> They are still listed below, from their '
      + 'Auth and profile records, but their activity and today\\'s count are blank '
      + 'rather than zero.<div class="warn-list" hidden id="warnList">'
      + f.map(function (x) { return esc(x.uid) + '  ' + esc(x.message); }).join('\\n')
      + '</div></div><button id="warnToggle">Show</button>';
    $('warnToggle').addEventListener('click', function () {
      var list = $('warnList');
      list.hidden = !list.hidden;
      this.textContent = list.hidden ? 'Show' : 'Hide';
    });
  }

  function renderAll() {
    $('cntActivity').textContent = DATA.events.length;
    $('cntAccounts').textContent = DATA.accounts.length;
    renderWarn(); renderHorizon();
    renderLive(); renderFeed(); updateArrows(); renderUsers();
  }
  function load(refresh) {
    $('scanNote').textContent = refresh
      ? 'Re-reading every account…'
      : 'Reading every account…';
    $('statusA').textContent = 'Loading…';
    fetch('/api/dashboard' + (refresh ? '?refresh=1' : ''))
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (d.error) throw new Error(d.error);
        DATA = d;
        $('scanNote').textContent = DATA.accounts.length + ' accounts scanned in '
          + (DATA.durationMs / 1000).toFixed(1) + 's · '
          + new Date(DATA.scannedAt).toLocaleTimeString()
          + ' · "on the app now" means a write in the last '
          + DATA.onlineWindowMinutes + ' min';
        renderAll();
      })
      .catch(function (e) {
        $('scanNote').textContent = 'Scan failed: ' + e.message;
        $('statusA').textContent = 'Failed to load. Check the terminal running server.js.';
      });
  }
  $('refresh').addEventListener('click', function () { load(true); });

  // Relative times go stale while the page sits open, and a dashboard whose
  // "just now" is forty minutes old is worse than one with no clock at all.
  setInterval(function () { if (DATA.events.length) { renderLive(); renderFeed(); } }, 60000);

  load(false);
})();
</script>
</body>
</html>`);
});

// ---- Dashboard data: one whole-project scan (see lib/activity.js) ----
app.get('/api/dashboard', async (req, res) => {
  try {
    res.json(await scanActivity(req.query.refresh === '1'));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Every account's completion for one specific day, however far back.
// Not used by the dashboard's own day picker (that filters the scanned
// event feed, which is instant); this is the direct read for a day older
// than the scan window. ----
app.get('/api/day/:dateKey', async (req, res) => {
  try {
    if (!isRealDateKey(req.params.dateKey)) {
      return res.status(400).json({ error: 'Expected a real YYYY-MM-DD date.' });
    }
    res.json(await scanDay(req.params.dateKey));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Flat account list, kept for any direct/scripted use ----
app.get('/api/users', async (req, res) => {
  try {
    res.json({ users: await listAllUsers(false) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/search', async (req, res) => {
  try {
    res.json({ results: await searchAccounts(String(req.query.q || '')) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/refresh', async (req, res) => {
  try {
    await Promise.all([listAllUsers(true), scanActivity(true)]);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- One day of one account, for the report page's day stepper.
// Returns the rendered fragment rather than raw data: the server already
// owns every rule that turns a day into that card (which habits were even
// due, how the task board stood), and re-implementing those in browser JS
// is exactly how the two would drift apart. ----
app.get('/api/account/:uid/day/:dateKey', async (req, res) => {
  try {
    if (!isRealDateKey(req.params.dateKey)) {
      return res.status(400).json({ error: 'Expected a real YYYY-MM-DD date.' });
    }
    const { uid, authRecord } = await resolveAccount(req.params.uid);
    const day = await loadDayFragment(uid, authRecord, req.params.dateKey);
    res.json({
      html: day.html, done: day.done, total: day.total,
      dayKey: day.dayKey, isToday: day.isToday, todayKey: day.todayKey,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Live report page. ?day=YYYY-MM-DD opens straight on that day, which
// is what makes every feed row on the dashboard a link to the exact day it
// happened rather than just to the person. ----
app.get('/report/:uid', async (req, res) => {
  const rawUid = req.params.uid;
  const day = isRealDateKey(req.query.day) ? String(req.query.day) : undefined;
  try {
    const { uid, authRecord } = await resolveAccount(rawUid);
    const report = await loadAccountReport(uid, authRecord, day);
    const { title, nav, header, stats, body } = buildReportBody(report);
    res.type('html').send(pageShell({ title, nav, header, stats, body, backHref: '/', uid }));
  } catch (e) {
    res.type('html').send(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>${BASE_STYLES}</style></head><body>
      <a class="back-link" href="/">← Back to the dashboard</a>
      <h1>Couldn't load that account</h1>
      <p class="muted">${escapeHtml(e.message)}</p>
    </body></html>`);
  }
});

// 127.0.0.1, NOT the default.
//
// `app.listen(port)` with no host binds to 0.0.0.0, so this was listening on
// every network interface: anyone on the same wifi could open
// http://<this-machine>:4127 and read every account in the project, with no
// password, no token and nothing in the logs to say they had. The tool holds
// a service-account key with full Firestore access, so that is every user's
// email, habits, notes and rooms.
//
// Binding to loopback is what makes "only me" true. It cannot be reached from
// another machine at all, which is the right guarantee for a single-admin
// local tool: a password on an open port would still be one guessed password
// away, and this way there is no door to guess at.
//
// If this ever genuinely needs to be reachable from elsewhere, do not just
// change this line. Put it behind an SSH tunnel (`ssh -L 4127:localhost:4127`)
// so the exposure decision stays with SSH rather than with a plain HTTP port.
const HOST = '127.0.0.1';
const server = app.listen(PORT, HOST, () => {
  console.log(`\nGrowDaily admin lookup running: http://localhost:${PORT}`);
  console.log(`Bound to ${HOST} only, so nothing outside this machine can reach it.\n`);
});

// A busy port is the ordinary case here, not a crash.
//
// This tool gets started and stopped constantly, and an editor or a stray
// background shell can leave the previous copy holding the port. Node's
// default for that is an unhandled 'error' event: a twenty-line stack trace
// through node:net that says EADDRINUSE somewhere in the middle and never
// says what to do about it. The two things actually worth knowing are which
// process has the port and how to get it back, so print those instead.
server.on('error', (err) => {
  if (err.code !== 'EADDRINUSE') {
    console.error(`\n${err.stack || err.message}\n`);
    process.exit(1);
  }
  console.error(`\nPort ${PORT} is already taken, most likely by a copy of this ` +
    `server that is still running.\n`);
  try {
    const { execSync } = require('child_process');
    const pids = execSync(`lsof -nP -iTCP:${PORT} -sTCP:LISTEN -t`, { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim().split('\n').filter(Boolean);
    if (pids.length) {
      console.error(`  Held by PID ${pids.join(', ')}. To take the port back:\n`);
      console.error(`    kill ${pids.join(' ')}\n`);
      console.error(`  Or just use another port:\n`);
    } else {
      console.error('  Or use another port:\n');
    }
  } catch (e) {
    // lsof missing or not permitted: the port advice below still stands.
    console.error('  Use another port:\n');
  }
  console.error(`    PORT=${Number(PORT) + 1} npm start\n`);
  process.exit(1);
});

// Ctrl-C should actually release the port before the process goes, so the
// next `npm start` a second later does not hit the message above.
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    // If a request is mid-flight and close() is still waiting on it, do not
    // hang the terminal waiting for a report to finish rendering.
    setTimeout(() => process.exit(0), 1500).unref();
  });
}
