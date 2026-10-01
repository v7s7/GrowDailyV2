'use strict';

/**
 * The launch splash page's HTML and styles. The behaviour is in ../splash/app.js and
 * the checks in ../wording/splash_rules.js, plain files rather than template
 * literals: see wording_page.js's own doc comment for why (a backtick or
 * backslash inside an inline script has twice shipped a page that silently
 * did nothing).
 *
 * No em dash anywhere in this file, including comments.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const PAGE_STYLES = `
  .splash-content { max-width: 1080px; }
  .splash-intro { margin: 0 0 var(--s5); font-size: 13px; color: var(--text-sec); max-width: 82ch; }
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* The edition splash/app.js is written for; see EDITION there. */
    --splash-styles: '3';
  }
  /* BASE_STYLES hides every section[id] by default for the dashboard's
     hash-routed views; this page has one section and no tabs. */
  #viewSplash { display: block; }

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

  .tag { display: inline-block; padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; border: 1px solid var(--border); color: var(--text-sec); margin-inline-start: 6px; }
  .tag.off { color: var(--danger); border-color: var(--danger-line); }

  .scene { border-top: 1px solid var(--border-soft, var(--border)); padding: var(--s4) 0; }
  .scene:first-of-type { border-top: none; padding-top: 0; }
  .scene.is-off .scene-body { opacity: 0.5; }
  .scene-head { display: flex; align-items: flex-start; gap: var(--s3); flex-wrap: wrap; }
  .scene-head .grow { flex: 1 1 280px; min-width: 0; }
  .scene h3 { font-size: 14px; font-weight: 650; margin: 0 0 2px; }
  .scene .line { font-size: 13px; color: var(--text); margin: 0 0 2px; }
  .scene .when { font-size: 12px; color: var(--text-sec); margin: 0; max-width: 78ch; }
  .scene-body { display: flex; flex-direction: column; gap: var(--s3); margin-top: var(--s3); }
  .field-row { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; }
  .field-row .name { font-size: 12.5px; font-weight: 600; min-width: 62px; }
  .hours input[type=text], .force-row input[type=text], .preview-row input[type=text] { flex: 0 0 auto; min-width: 0; width: 64px; padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 14px; }
  .force-row input[type=text], .preview-row input[type=text].date { width: 130px; }
  .hours input[type=text]:focus, .force-row input[type=text]:focus, .preview-row input[type=text]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  input[type=text].has-error { border-color: var(--danger); }
  .field { display: flex; flex-direction: column; gap: 4px; }
  .hint { font-size: 11.5px; color: var(--text-tert); line-height: 1.45; }
  .share input[type=text] { flex: 0 0 auto; min-width: 0; width: 64px; padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 14px; }
  .share input[type=text]:focus, .line-box:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .line-row { flex-wrap: nowrap; }
  .line-box { flex: 1 1 auto; min-width: 0; max-width: 520px; padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 14px; }
  .count { flex: 0 0 auto; font-size: 11.5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .count.over { color: var(--danger); font-weight: 650; }
  .line-issue { font-size: 12px; min-height: 0; }
  .line-issue:empty { display: none; }
  .line-issue.err { color: var(--danger); }
  .line-issue.wrn { color: var(--warn, var(--text-sec)); }
  .pool-bars { display: flex; flex-direction: column; gap: 6px; margin: var(--s3) 0; }
  .pool-row { display: grid; grid-template-columns: minmax(110px, 160px) minmax(60px, 1fr) 44px minmax(0, auto); align-items: center; gap: var(--s3); font-size: 13px; }
  .pool-row.is-off { opacity: 0.5; }
  .pool-row .nm { font-weight: 600; }
  .pool-row .bar { height: 8px; border-radius: 999px; background: var(--border); overflow: hidden; }
  .pool-row .fill { display: block; height: 100%; background: var(--accent); border-radius: 999px; }
  .pool-row .pc { text-align: end; font-variant-numeric: tabular-nums; font-weight: 650; }
  .pool-row .sh { font-size: 12px; color: var(--text-tert); }
  .days-strip { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; }
  .days-strip:empty { display: none; }
  .days-label { font-size: 11.5px; color: var(--text-tert); }
  .days { display: inline-flex; gap: 4px; flex-wrap: wrap; }
  .day { display: inline-flex; flex-direction: column; align-items: center; gap: 2px; width: 18px; }
  .day .dot { width: 10px; height: 10px; border-radius: 50%; border: 1.5px solid var(--text-tert); box-sizing: border-box; }
  .day.on .dot { background: var(--accent); border-color: var(--accent); }
  .day .dn { font-size: 9.5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .result .small.skip { color: var(--warn, var(--text-sec)); }
  .preview-sub { font-size: 12px; font-weight: 650; color: var(--text-sec); margin: var(--s3) 0 6px; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { padding: 4px 11px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--surface); color: var(--text-sec); font: inherit; font-size: 12.5px; cursor: pointer; }
  .chip[aria-pressed=true] { background: var(--accent-soft); border-color: var(--accent); color: var(--accent); font-weight: 650; }

  .switch-box { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; }
  .switch { display: inline-flex; align-items: center; gap: 8px; font-size: 12.5px; font-weight: 600; cursor: pointer; }
  .switch input { position: absolute; opacity: 0; width: 0; height: 0; }
  .switch .track { width: 36px; height: 20px; border-radius: 999px; background: var(--border); position: relative; transition: background 0.14s ease; flex: 0 0 auto; }
  .switch .track::after { content: ''; position: absolute; top: 2px; left: 2px; width: 16px; height: 16px; border-radius: 50%; background: var(--surface); box-shadow: 0 1px 2px rgba(0,0,0,0.3); transition: transform 0.14s ease; }
  .switch input:checked + .track { background: var(--accent); }
  .switch input:checked + .track::after { transform: translateX(16px); }
  .switch input:focus-visible + .track { box-shadow: 0 0 0 3px var(--accent-soft); }
  @media (prefers-reduced-motion: reduce) { .switch .track, .switch .track::after { transition: none; } }

  .order-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }
  .order-item { display: flex; align-items: center; gap: var(--s3); padding: 7px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); cursor: grab; }
  .order-item.dragging { opacity: 0.4; }
  .order-item.over { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .order-item .pos { width: 22px; font-size: 12px; color: var(--text-tert); text-align: end; font-variant-numeric: tabular-nums; }
  .order-item .nm { flex: 1; font-size: 13px; font-weight: 600; }
  .order-item .grip { color: var(--text-tert); font-size: 14px; letter-spacing: -2px; user-select: none; }
  .order-item button { padding: 2px 9px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font: inherit; font-size: 13px; cursor: pointer; }
  .order-item button:disabled { opacity: 0.35; cursor: default; }
  .order-note { font-size: 12px; color: var(--text-tert); margin: var(--s3) 0 0; }

  .force-warn { margin-bottom: var(--s4); }
  .preview-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 8px var(--s4); margin: var(--s3) 0; }
  .check { display: flex; align-items: center; gap: 8px; font-size: 13px; }
  .preview-row { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; }
  .result { margin-top: var(--s3); padding: var(--s3) var(--s4); border-radius: var(--r-md); border: 1px solid var(--accent-line); background: var(--accent-soft); }
  .result .big { font-size: 15px; font-weight: 650; }
  .result .small { font-size: 12.5px; color: var(--text-sec); margin-top: 2px; }
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
    .pool-row { grid-template-columns: 1fr 44px; }
    .pool-row .bar, .pool-row .sh { grid-column: 1 / -1; }
    .line-row { flex-wrap: wrap; }
    .pick { min-width: 0; width: 100%; }
  }
`;

function renderSplashPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Splash · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'splash', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Splash', sub: 'Which scene Doum plays on the opening curtain, and when, live on every phone', live: false })}
    <div class="app-content splash-content">
      <p class="splash-intro">The curtain Doum plays while the app opens. Choose which scenes are on, the hours and months each one plays in, its line under Doum, which wins when two could play, what the anytime list plays when none of them can, how long the curtain stays, or play one scene for everyone for a few days. Press Save and every open app follows within seconds, with no new build. Each setting shows the app’s built-in value beside it, so going back is always one click. The rule behind each scene (once after a full day, the very first launch, and so on) is in the app and is shown in plain words, but is not changed here.</p>
      <div id="banners"></div>
      <section id="viewSplash"><div class="loading">Loading the splash&hellip;</div></section>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/wording/splash_rules.js"></script>
  <script src="/splash/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderSplashPage, PAGE_STYLES };
