'use strict';

/**
 * The Achievements page's HTML and styles. The behaviour is in
 * ../achievements/app.js, a plain file rather than a template literal — see
 * wording_page.js's own doc comment for why (a backtick or backslash inside
 * an inline script has twice shipped a page that silently did nothing).
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const PAGE_STYLES = `
  .ach-content { max-width: 1080px; }
  .ach-intro { margin: 0 0 var(--s5); font-size: 13px; color: var(--text-sec); max-width: 80ch; }
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
  }

  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s4); border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }
  /* BASE_STYLES hides every section[id] by default for the dashboard's
     hash-routed views, which show themselves by adding .active (see
     .view.active there). This page has only one section and no tabs, so it
     opts back in directly rather than pretending to have a view system. */
  #viewList { display: block; }

  .t-ar { font-family: var(--arabic); font-size: 15.5px; line-height: 1.7; direction: rtl; text-align: right; unicode-bidi: plaintext; }
  .t-en { font-size: 13.5px; line-height: 1.5; direction: ltr; text-align: left; unicode-bidi: plaintext; }
  textarea { width: 100%; resize: vertical; padding: var(--s2) var(--s3); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font-family: inherit; min-height: 38px; }
  textarea.t-ar { font-family: var(--arabic); }
  textarea:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  textarea.has-error { border-color: var(--danger); }

  .jump-nav { position: sticky; top: 0; z-index: 20; display: flex; flex-wrap: wrap; gap: var(--s1); background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: var(--s2) var(--s3); margin-bottom: var(--s5); box-shadow: var(--shadow-sm); }
  .jump-nav a { padding: 5px var(--s3); border-radius: var(--r-sm); font-size: 12px; font-weight: 550; color: var(--text-sec); text-decoration: none; white-space: nowrap; }
  .jump-nav a:hover { background: var(--bg-sunken); color: var(--text); }

  .family { margin-bottom: var(--s6); scroll-margin-top: var(--s4); }
  .family-head { display: flex; align-items: baseline; gap: var(--s3); margin-bottom: var(--s3); }
  .gender-head { font-size: 12px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-tert); margin: var(--s4) 0 var(--s2); }
  .family-head .id { font-family: var(--mono); font-size: 11px; color: var(--text-tert); }
  .flist { display: flex; flex-direction: column; gap: var(--s2); }

  .frow { border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); padding: var(--s3) var(--s4); }
  .frow-head { display: flex; align-items: center; gap: var(--s2); flex-wrap: wrap; margin-bottom: var(--s2); }
  .tier-badge { display: inline-block; padding: 1px 8px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; border: 1px solid var(--border); color: var(--text-sec); }
  .badge.edited { color: var(--accent); background: var(--accent-soft); border-color: var(--accent-line); padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; border-width: 1px; border-style: solid; }
  .key { font-family: var(--mono); font-size: 10.5px; color: var(--text-tert); }

  .field { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s4); margin-top: var(--s2); }
  .field-col .lang { font-size: 10.5px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-tert); margin-bottom: 4px; display: flex; justify-content: space-between; align-items: baseline; }
  .field-col .built-in { font-size: 11px; color: var(--text-tert); margin-top: 4px; }
  .field-col .built-in .t-ar, .field-col .built-in .t-en { font-size: inherit; line-height: 1.4; color: inherit; }
  .link-btn { background: none; border: none; padding: 0; color: var(--accent); font: inherit; font-size: 11px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }
  .link-btn:disabled { color: var(--text-tert); text-decoration: none; cursor: default; }
  .msgs { display: flex; flex-direction: column; gap: 2px; margin-top: 4px; font-size: 11.5px; }
  .msgs .err { color: var(--danger); }
  .msgs .wrn { color: var(--warn); }
  .row-foot { display: flex; align-items: center; gap: var(--s3); margin-top: var(--s2); }
  .row-foot .savemsg { font-size: 11.5px; color: var(--text-tert); }

  .toast { position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 60; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  @media (max-width: 700px) {
    .field { grid-template-columns: 1fr; gap: var(--s2); }
  }
`;

function renderAchievementsPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Achievements · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'achievements', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Achievements', sub: 'Medals, characters and closet items, live on every phone', live: false })}
    <div class="app-content ach-content">
      <p class="ach-intro">Every medal, character and closet item's name and description, in one place. Press Save on a field and every open app shows the new text within seconds, with no new build.
        Every field always shows the app’s own built-in text beside it, so going back is always one click, whatever you type here.</p>

      <div id="banners"></div>
      <section id="viewList"><div class="loading">Loading the achievements&hellip;</div></section>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/achievements/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderAchievementsPage, PAGE_STYLES };
