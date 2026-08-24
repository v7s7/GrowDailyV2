#!/usr/bin/env node
/**
 * GrowDaily admin lookup tool (live server).
 *
 * Start it once, then open the printed URL in your browser: a search box
 * finds any account by name, email, or uid as you type, and clicking a
 * result opens its full report live — no per-account command, no
 * generated file to find afterward. lookup_user.js (the CLI script) still
 * exists for saving one specific report as a standalone file; this is for
 * browsing without knowing who you're looking for in advance.
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

const { resolveAccount, loadAccountReport, searchAccounts, listAllUsers } = require('./lib/fetchAccount');
const { buildReportBody, pageShell, escapeHtml, BASE_STYLES } = require('./lib/render');

const PORT = process.env.PORT || 4127;
const app = express();

// ---- Search home page: a real filterable/sortable table, not a plain
// list - every account loads once into the browser (this is a single-admin
// local tool, not a public multi-tenant dashboard, so a few thousand rows
// of {uid,email,displayName,createdAt,lastSignIn} is nothing to hold in
// memory client-side), and search/date-range/sort all run instantly against
// that in-memory list instead of round-tripping to the server on every
// keystroke. ----
app.get('/', (req, res) => {
  res.type('html').send(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GrowDaily — Admin Lookup</title>
<style>${BASE_STYLES}
  body { max-width: 1040px; padding-top: 5vh; }
  .lockup { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 18px; flex-wrap: wrap; }
  .lockup h1 { font-size: 22px; margin: 0; }
  .lockup p { color: var(--text-sec); font-size: 13px; margin: 2px 0 0; }

  /* Filter bar - the whole point of this page: search, a date-range filter
     on Created (see AskUserQuestion history: "filter by email, and
     createdAt" was the very first ask that started this tool), quick-range
     buttons, and an explicit clear. */
  .filter-bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px; margin-bottom: 10px; }
  .filter-bar input[type="search"] { flex: 2; min-width: 200px; }
  .filter-group { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--text-sec); }
  .filter-group input[type="date"] { padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; font-size: 12.5px; background: var(--surface); color: var(--text); }
  .chip-row { display: flex; gap: 6px; flex-wrap: wrap; }
  .chip { padding: 6px 12px; border-radius: 100px; border: 1px solid var(--border); background: var(--surface); font-size: 12px; cursor: pointer; color: var(--text-sec); }
  .chip:hover { border-color: var(--accent); color: var(--accent); }
  .chip.active { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }

  .status-row { display: flex; justify-content: space-between; align-items: center; margin: 4px 2px 10px; font-size: 12.5px; color: var(--text-tert); }

  /* The table itself */
  .user-table-wrap { border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--surface); }
  table.users { width: 100%; border-collapse: collapse; font-size: 13px; }
  table.users th { text-align: left; padding: 10px 14px; background: var(--bg); border-bottom: 1px solid var(--border); font-size: 11px; text-transform: uppercase; letter-spacing: 0.4px; color: var(--text-sec); cursor: pointer; user-select: none; white-space: nowrap; }
  table.users th:hover { color: var(--accent); }
  table.users th .arrow { opacity: 0.4; margin-inline-start: 4px; }
  table.users th.sorted .arrow { opacity: 1; }
  table.users td { padding: 10px 14px; border-bottom: 1px solid var(--border); vertical-align: middle; }
  table.users tr:last-child td { border-bottom: none; }
  table.users tr.row:hover { background: var(--accent-soft); cursor: pointer; }
  .u-name { font-weight: 700; font-size: 13px; }
  .u-email { font-size: 12px; color: var(--text-sec); }
  .u-uid { font-family: ui-monospace, Menlo, monospace; font-size: 11px; color: var(--text-tert); }
  .u-date { font-size: 12.5px; white-space: nowrap; }
  .u-date .rel { color: var(--text-tert); font-size: 11px; display: block; }
  .view-btn { padding: 5px 12px; border-radius: 100px; border: 1px solid var(--border); background: var(--bg); font-size: 11.5px; font-weight: 600; color: var(--accent); white-space: nowrap; }
  .disabled-chip { display: inline-block; margin-inline-start: 6px; padding: 1px 8px; border-radius: 100px; background: rgba(255,90,82,0.14); color: #c23b34; font-size: 10px; font-weight: 700; text-transform: uppercase; }
  .empty-state { padding: 40px 20px; text-align: center; color: var(--text-tert); font-size: 13px; }
</style>
</head>
<body>
  <div class="lockup">
    <div>
      <h1>GrowDaily — Admin Lookup</h1>
      <p>Every account, filterable and sortable. Click a row for the full report.</p>
    </div>
    <button class="btn primary" id="refresh" title="Re-scan every account (picks up brand-new signups immediately)">⟳ Refresh list</button>
  </div>

  <div class="filter-bar">
    <input id="q" type="search" placeholder="Search name, email, or uid…" autofocus>
    <div class="filter-group">
      <span>Created</span>
      <input id="fromDate" type="date" title="Created on or after">
      <span>–</span>
      <input id="toDate" type="date" title="Created on or before">
    </div>
    <div class="chip-row" id="quickRanges">
      <button class="chip" data-days="0">Any time</button>
      <button class="chip" data-days="1">Today</button>
      <button class="chip" data-days="7">7 days</button>
      <button class="chip" data-days="30">30 days</button>
      <button class="chip" data-days="90">90 days</button>
    </div>
    <button class="btn" id="clearFilters">Clear filters</button>
  </div>

  <div class="status-row">
    <span id="status">Loading…</span>
  </div>

  <div class="user-table-wrap">
    <table class="users">
      <thead>
        <tr>
          <th data-sort="account">Account <span class="arrow">↕</span></th>
          <th data-sort="uid">UID <span class="arrow">↕</span></th>
          <th data-sort="createdAt">Created <span class="arrow">↕</span></th>
          <th data-sort="lastSignIn">Last active <span class="arrow">↕</span></th>
          <th></th>
        </tr>
      </thead>
      <tbody id="rows"></tbody>
    </table>
  </div>

<script>
(function () {
  var q = document.getElementById('q');
  var fromDate = document.getElementById('fromDate');
  var toDate = document.getElementById('toDate');
  var rows = document.getElementById('rows');
  var status = document.getElementById('status');
  var refresh = document.getElementById('refresh');
  var clearBtn = document.getElementById('clearFilters');
  var quickRanges = document.getElementById('quickRanges');
  var headers = document.querySelectorAll('table.users th[data-sort]');

  var all = [];
  var sortKey = 'createdAt';
  var sortDir = 'desc';

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function fmtDate(iso) {
    if (!iso) return { abs: '—', rel: '' };
    var d = new Date(iso);
    if (isNaN(d.getTime())) return { abs: '—', rel: '' };
    var abs = d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
    var days = Math.floor((Date.now() - d.getTime()) / 86400000);
    var rel = days <= 0 ? 'today' : days === 1 ? '1 day ago' : days + ' days ago';
    return { abs: abs, rel: rel };
  }

  function matchesFilters(u) {
    var needle = q.value.trim().toLowerCase();
    if (needle) {
      var hay = (u.email + ' ' + u.displayName + ' ' + u.uid).toLowerCase();
      if (hay.indexOf(needle) === -1) return false;
    }
    if (fromDate.value || toDate.value) {
      if (!u.createdAt) return false;
      var created = new Date(u.createdAt).getTime();
      if (fromDate.value && created < new Date(fromDate.value + 'T00:00:00').getTime()) return false;
      if (toDate.value && created > new Date(toDate.value + 'T23:59:59').getTime()) return false;
    }
    return true;
  }

  function sortedFiltered() {
    var list = all.filter(matchesFilters);
    list.sort(function (a, b) {
      var av, bv;
      if (sortKey === 'account') {
        av = (a.displayName || a.email || '').toLowerCase();
        bv = (b.displayName || b.email || '').toLowerCase();
      } else if (sortKey === 'uid') {
        av = a.uid; bv = b.uid;
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

  function render() {
    var list = sortedFiltered();
    status.textContent = 'Showing ' + list.length + ' of ' + all.length + ' account' + (all.length === 1 ? '' : 's');
    if (list.length === 0) {
      rows.innerHTML = '<tr><td colspan="5"><div class="empty-state">No accounts match these filters.</div></td></tr>';
      return;
    }
    rows.innerHTML = list.map(function (u) {
      var name = u.displayName || '(no name set)';
      var created = fmtDate(u.createdAt);
      var lastActive = fmtDate(u.lastSignIn);
      return '<tr class="row" data-uid="' + escapeHtml(u.uid) + '">' +
        '<td><div class="u-name">' + escapeHtml(name) + (u.disabled ? '<span class="disabled-chip">Disabled</span>' : '') + '</div><div class="u-email">' + escapeHtml(u.email || '(no email)') + '</div></td>' +
        '<td class="u-uid">' + escapeHtml(u.uid) + '</td>' +
        '<td class="u-date">' + created.abs + '<span class="rel">' + created.rel + '</span></td>' +
        '<td class="u-date">' + lastActive.abs + '<span class="rel">' + lastActive.rel + '</span></td>' +
        '<td><span class="view-btn">View →</span></td>' +
        '</tr>';
    }).join('');
    Array.prototype.forEach.call(rows.querySelectorAll('tr.row'), function (tr) {
      tr.addEventListener('click', function () {
        window.location.href = '/report/' + encodeURIComponent(tr.getAttribute('data-uid'));
      });
    });
  }

  function updateHeaderArrows() {
    Array.prototype.forEach.call(headers, function (th) {
      var key = th.getAttribute('data-sort');
      th.classList.toggle('sorted', key === sortKey);
      var arrow = th.querySelector('.arrow');
      arrow.textContent = key !== sortKey ? '↕' : (sortDir === 'asc' ? '↑' : '↓');
    });
  }

  headers.forEach(function (th) {
    th.addEventListener('click', function () {
      var key = th.getAttribute('data-sort');
      if (sortKey === key) {
        sortDir = sortDir === 'asc' ? 'desc' : 'asc';
      } else {
        sortKey = key;
        sortDir = key === 'account' || key === 'uid' ? 'asc' : 'desc';
      }
      updateHeaderArrows();
      render();
    });
  });

  function setQuickRange(days) {
    Array.prototype.forEach.call(quickRanges.querySelectorAll('.chip'), function (c) {
      c.classList.toggle('active', c.getAttribute('data-days') === String(days));
    });
    if (days === 0) {
      fromDate.value = '';
      toDate.value = '';
    } else {
      var from = new Date();
      from.setDate(from.getDate() - (days - 1));
      fromDate.value = from.toISOString().slice(0, 10);
      toDate.value = new Date().toISOString().slice(0, 10);
    }
    render();
  }
  quickRanges.querySelectorAll('.chip').forEach(function (c) {
    c.addEventListener('click', function () { setQuickRange(Number(c.getAttribute('data-days'))); });
  });

  q.addEventListener('input', render);
  fromDate.addEventListener('change', function () { setActiveChipForManualRange(); render(); });
  toDate.addEventListener('change', function () { setActiveChipForManualRange(); render(); });
  function setActiveChipForManualRange() {
    Array.prototype.forEach.call(quickRanges.querySelectorAll('.chip'), function (c) { c.classList.remove('active'); });
  }

  clearBtn.addEventListener('click', function () {
    q.value = '';
    fromDate.value = '';
    toDate.value = '';
    setQuickRange(0);
  });

  function load() {
    status.textContent = 'Loading…';
    fetch('/api/users')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        all = data.users || [];
        updateHeaderArrows();
        render();
      })
      .catch(function () { status.textContent = 'Failed to load accounts — check the terminal running server.js.'; });
  }

  refresh.addEventListener('click', function () {
    status.textContent = 'Refreshing account list…';
    fetch('/api/refresh', { method: 'POST' }).then(load);
  });

  setQuickRange(0);
  load();
})();
</script>
</body>
</html>`);
});

// ---- Full account list, for the home page's client-side table ----
app.get('/api/users', async (req, res) => {
  try {
    const users = await listAllUsers(false);
    res.json({ users });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Search API (kept for any direct/scripted use; the home page itself
// filters the /api/users list client-side instead) ----
app.get('/api/search', async (req, res) => {
  try {
    const results = await searchAccounts(String(req.query.q || ''));
    res.json({ results });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/refresh', async (req, res) => {
  try {
    await listAllUsers(true);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---- Live report page ----
app.get('/report/:uid', async (req, res) => {
  const rawUid = req.params.uid;
  try {
    const { uid, authRecord } = await resolveAccount(rawUid);
    const report = await loadAccountReport(uid, authRecord);
    const { title, nav, header, body } = buildReportBody(report);
    res.type('html').send(pageShell({ title, nav, header, body, backHref: '/' }));
  } catch (e) {
    res.type('html').send(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>${BASE_STYLES}</style></head><body>
      <a class="back-link" href="/">← Back to search</a>
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
app.listen(PORT, HOST, () => {
  console.log(`\nGrowDaily admin lookup running: http://localhost:${PORT}`);
  console.log(`Bound to ${HOST} only, so nothing outside this machine can reach it.\n`);
});
