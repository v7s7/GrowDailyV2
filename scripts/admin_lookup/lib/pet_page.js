'use strict';

/**
 * The «دوم» page's HTML and styles. The behaviour is in ../pet/app.js and
 * the checks in ../wording/pet_rules.js, plain files rather than template
 * literals: see wording_page.js's own doc comment for why (a backtick or
 * backslash inside an inline script has twice shipped a page that silently
 * did nothing).
 *
 * No em dash anywhere in this file, including comments.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const PAGE_STYLES = `
  .pet-content { max-width: 1080px; }
  .pet-intro { margin: 0 0 var(--s5); font-size: 13px; color: var(--text-sec); max-width: 82ch; }
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* The edition pet/app.js is written for; see EDITION there. */
    --pet-styles: '2';
  }
  /* BASE_STYLES hides every section[id] by default for the dashboard's
     hash-routed views; this page has one section and no tabs. */
  #viewPet { display: block; }

  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s4); border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn { background: var(--warn-soft, var(--info-soft)); border-color: var(--warn-line, var(--info-line)); color: var(--warn, var(--info)); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }

  .t-ar { font-family: var(--arabic); font-size: 15px; line-height: 1.6; direction: rtl; unicode-bidi: plaintext; }

  .card { border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); padding: var(--s4) var(--s5); margin-bottom: var(--s5); scroll-margin-top: var(--s4); }
  .card h2 { font-size: 15px; font-weight: 650; margin: 0 0 4px; }
  .card .about { font-size: 12.5px; color: var(--text-sec); margin: 0 0 var(--s4); max-width: 80ch; }
  .burst { padding-top: var(--s3); margin-top: var(--s3); border-top: 1px solid var(--border-soft, var(--border)); }
  .burst:first-of-type { border-top: none; margin-top: 0; padding-top: 0; }
  .burst h3 { font-size: 13.5px; font-weight: 650; margin: 0 0 2px; }
  .burst .about { margin-bottom: var(--s3); }
  .words-card { display: flex; align-items: center; gap: var(--s4); flex-wrap: wrap; }
  .words-card .grow { flex: 1 1 320px; }
  .btn-link { display: inline-flex; align-items: center; gap: 6px; padding: 7px 14px; border-radius: var(--r-md); border: 1px solid var(--accent-line); background: var(--accent-soft); color: var(--accent); font-size: 13px; font-weight: 600; text-decoration: none; }
  .btn-link:hover { background: var(--accent); color: var(--bg); }

  .num-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: var(--s4); }
  .num { display: flex; flex-direction: column; gap: 6px; }
  .num label { font-size: 13px; font-weight: 600; }
  .num .row { display: flex; align-items: center; gap: var(--s2); }
  /* BASE_STYLES grows every text box to fill its row; a number wants four digits. */
  .num input[type=text] { flex: 0 0 auto; min-width: 0; width: 96px; padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 14px; }
  .num input[type=text]:focus, .pick:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .num input[type=text].has-error { border-color: var(--danger); }
  .num .unit { font-size: 12px; color: var(--text-tert); }
  .num .help { font-size: 11.5px; color: var(--text-tert); line-height: 1.45; }

  .built-in { font-size: 11.5px; color: var(--text-tert); display: inline-flex; gap: 6px; align-items: baseline; flex-wrap: wrap; }
  .edited-dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; background: var(--accent); margin-inline-start: 6px; vertical-align: middle; }
  .link-btn { background: none; border: none; padding: 0; color: var(--accent); font: inherit; font-size: 11.5px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }

  table.pet-table { width: 100%; border-collapse: collapse; font-size: 13px; }
  .pet-table th { text-align: start; font-size: 11px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.4px; color: var(--text-tert); padding: 0 var(--s2) var(--s2); border-bottom: 1px solid var(--border); }
  .pet-table td { padding: 8px var(--s2); border-bottom: 1px solid var(--border-soft, var(--border)); vertical-align: middle; }
  .pet-table tr:last-child td { border-bottom: none; }
  .pet-table .sub { font-size: 11.5px; color: var(--text-tert); }
  /* An Arabic name lines up with the English one under it. */
  .pet-table .t-ar { text-align: left; }
  .pet-table .tag { display: inline-block; padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; border: 1px solid var(--border); color: var(--text-sec); margin-inline-start: 6px; }
  .pick { padding: 5px 8px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 13px; min-width: 210px; }
  .pick.edited { border-color: var(--accent-line); }

  /* Sticky, not fixed: it stays in the content column beside the sidebar. */
  .save-bar { position: sticky; bottom: 0; display: flex; align-items: center; gap: var(--s3); padding: var(--s3) var(--s4); margin-top: var(--s4); background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); box-shadow: var(--shadow-lg); z-index: 40; }
  .save-bar .status { flex: 1; font-size: 12.5px; color: var(--text-sec); }
  .save-bar .msgs { display: flex; flex-direction: column; gap: 2px; font-size: 12px; }
  .save-bar .msgs .err { color: var(--danger); }
  .save-bar .msgs .wrn { color: var(--warn, var(--text-sec)); }
  .btn { padding: 7px 16px; border-radius: var(--r-md); border: 1px solid var(--border); background: var(--surface); color: var(--text); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: var(--bg); }
  .btn:disabled { opacity: 0.45; cursor: default; }

  .toast { position: fixed; left: 50%; bottom: 84px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 60; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  @media (max-width: 700px) {
    .pick { min-width: 0; width: 100%; }
  }
`;

function renderPetPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Doum · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'pet', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Doum', sub: 'How the mascot talks, sleeps and praises, and the day’s confetti, live on every phone', live: false })}
    <div class="app-content pet-content">
      <p class="pet-intro">Everything about Doum that is not a sentence: how often he talks, how long a bubble stays, when he says good morning, sleeps and wakes, which praise list each habit hears, and the confetti of the day’s three moments. Press Save and every open app follows within seconds, with no new build. Each setting shows the app’s built-in value beside it, so going back is always one click. His words themselves are on the Wording page.</p>
      <div id="banners"></div>
      <section id="viewPet"><div class="loading">Loading Doum&hellip;</div></section>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/wording/pet_rules.js"></script>
  <script src="/pet/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderPetPage, PAGE_STYLES };
