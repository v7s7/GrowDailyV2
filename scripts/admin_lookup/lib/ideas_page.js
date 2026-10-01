'use strict';

/**
 * The Habit ideas page's HTML and styles. The behaviour is in
 * ../ideas/app.js and the rules it shares with the server in
 * ../wording/ideas_rules.js, plain files rather than template literals: see
 * wording_page.js's own doc comment for why (a backtick or backslash inside
 * an inline script has twice shipped a page that silently did nothing).
 *
 * The card preview is drawn in the app's own default dark colours (Emerald
 * and Gold, as on the FAQ and Premium pages' phone), fixed on purpose: it
 * shows what a phone shows, whatever this tool's own theme is.
 *
 * No em dash anywhere in this file, including comments.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const PAGE_STYLES = `
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* The edition ideas/app.js is written for; see EDITION there. */
    --ideas-styles: '1';
    /* The app's default dark theme, for the card preview only. */
    --app-bg: #07100D;
    --app-surface: #101B17;
    --app-raised: #17251F;
    --app-border: #2D4037;
    --app-text: #F7F3E8;
    --app-text-sec: #B5BCA8;
    --app-text-tert: #6F7A70;
    --app-gold: #E4B45F;
    --app-emerald: #2ECF8F;
  }
  .ideas-content { max-width: 1560px; }
  .page-intro { margin: 0 0 var(--s4); font-size: 13px; color: var(--text-sec); max-width: 92ch; }
  .page-intro .fine { display: block; margin-top: var(--s1); color: var(--text-tert); font-size: 12px; }
  /* BASE_STYLES hides every section[id] by default for the dashboard's
     hash-routed views; this page shows its own. */
  #viewIdeas { display: block; }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }
  .muted-note { color: var(--text-tert); font-size: 12.5px; margin: 0; }

  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s3); border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner .grow { flex: 1 1 auto; min-width: 0; }
  .banner code { font-family: var(--mono); font-size: 12px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: 6px; padding: 1px 5px; user-select: all; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .banner ul { margin: 6px 0 0; padding-inline-start: 18px; }
  .banner li { margin: 2px 0; }
  details.notes { margin-bottom: var(--s3); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); font-size: 12.5px; }
  details.notes > summary { cursor: pointer; padding: 8px 12px; color: var(--text-sec); }
  details.notes ul { margin: 0; padding: 0 16px 10px 32px; color: var(--text-sec); }
  details.notes li { margin: 3px 0; }

  .t-ar { font-family: var(--arabic); direction: rtl; text-align: right; unicode-bidi: plaintext; }
  .t-en { direction: ltr; text-align: left; unicode-bidi: plaintext; }

  /* ---- Tabs and toolbar ------------------------------------------------- */
  .tabs { display: inline-flex; gap: 2px; padding: 3px; margin-bottom: var(--s4); border-radius: var(--r-md); background: var(--bg-sunken); border: 1px solid var(--border); }
  .tabs button { padding: 6px 18px; border-radius: 8px; border: 1px solid transparent; background: none; color: var(--text-sec); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .tabs button[aria-selected="true"] { background: var(--surface); border-color: var(--border); color: var(--text); }
  .tabs .count { margin-inline-start: 6px; font-size: 11px; font-weight: 500; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  /* Not sticky: the editor beside the list is, and the two would overlap. */
  .toolbar { display: flex; flex-wrap: wrap; gap: var(--s2); align-items: center; padding: 10px var(--s3); margin-bottom: var(--s3); border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); }
  .toolbar input[type="search"] { flex: 1 1 200px; min-width: 160px; height: 32px; padding: 0 var(--s3); border: 1px solid transparent; border-radius: var(--r-md); background: var(--bg-sunken); color: var(--text); font: inherit; font-size: 13px; }
  .toolbar input[type="search"]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .toolbar .sep { width: 1px; height: 22px; background: var(--border); margin: 0 var(--s1); }
  .seg { display: inline-flex; gap: 2px; padding: 3px; border-radius: var(--r-md); background: var(--bg-sunken); border: 1px solid var(--border); }
  .seg button { padding: 4px 12px; border-radius: 8px; border: 1px solid transparent; background: none; color: var(--text-sec); font: inherit; font-size: 12.5px; font-weight: 550; cursor: pointer; }
  .seg button[aria-pressed="true"] { background: var(--surface); border-color: var(--border); color: var(--text); }
  .seg button:disabled { opacity: 0.45; cursor: default; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { padding: 4px 11px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--surface); color: var(--text-sec); font: inherit; font-size: 12px; cursor: pointer; }
  .chip .n { margin-inline-start: 5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .chip[aria-pressed="true"] { background: var(--accent-soft); border-color: var(--accent); color: var(--accent); font-weight: 650; }
  .chip[aria-pressed="true"] .n { color: var(--accent); }
  .toolbar-row2 { display: flex; flex-wrap: wrap; gap: 6px; width: 100%; }

  /* ---- Buttons, badges, switches ---------------------------------------- */
  .btn { padding: 7px 16px; border-radius: var(--r-md); border: 1px solid var(--border); background: var(--surface); color: var(--text); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-ink, var(--bg)); }
  .btn.small { padding: 5px var(--s3); font-size: 12px; }
  .btn.danger-soft:hover:not(:disabled) { color: var(--danger); border-color: var(--danger-line); }
  .btn:disabled { opacity: 0.45; cursor: default; }
  .link-btn { background: none; border: none; padding: 0; color: var(--accent); font: inherit; font-size: 11.5px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }
  .icon-only { width: 26px; height: 24px; display: inline-grid; place-items: center; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); color: var(--text-sec); cursor: pointer; font-family: inherit; font-size: 12px; line-height: 1; padding: 0; }
  .icon-only:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
  .icon-only:disabled { opacity: 0.3; cursor: default; }
  .star { width: 30px; height: 28px; display: inline-grid; place-items: center; border-radius: var(--r-sm); border: 1px solid transparent; background: none; color: var(--text-tert); cursor: pointer; font-size: 17px; line-height: 1; padding: 0; }
  .star:hover { border-color: var(--border); color: var(--accent); }
  .star[aria-pressed="true"] { color: var(--accent); }
  .badge { display: inline-block; padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; letter-spacing: 0.2px; border: 1px solid; white-space: nowrap; }
  .badge.edited { color: var(--accent); background: var(--accent-soft); border-color: var(--accent-line); }
  .badge.added { color: var(--success); background: var(--success-soft); border-color: var(--success-line); }
  .badge.unsaved { color: var(--undo); background: var(--undo-soft); border-color: var(--undo-line); }
  .badge.hidden { color: var(--text-tert); background: var(--bg-sunken); border-color: var(--border); }
  .badge.error { color: var(--danger); background: var(--danger-soft); border-color: var(--danger-line); }
  .badge.muted { color: var(--text-tert); background: var(--bg-sunken); border-color: var(--border); }
  .switch { display: inline-flex; align-items: center; gap: 8px; font-size: 12px; font-weight: 600; cursor: pointer; color: var(--text-sec); }
  .switch input { position: absolute; opacity: 0; width: 0; height: 0; }
  .switch .track { width: 34px; height: 19px; border-radius: 999px; background: var(--border-strong, var(--border)); position: relative; transition: background 0.14s ease; flex: 0 0 auto; }
  .switch .track::after { content: ''; position: absolute; top: 2px; left: 2px; width: 15px; height: 15px; border-radius: 50%; background: var(--surface); box-shadow: 0 1px 2px rgba(0,0,0,0.3); transition: transform 0.14s ease; }
  .switch input:checked + .track { background: var(--accent); }
  .switch input:checked + .track::after { transform: translateX(15px); }
  .switch input:focus-visible + .track { box-shadow: 0 0 0 3px var(--accent-soft); }
  .switch input:disabled + .track { opacity: 0.4; }
  @media (prefers-reduced-motion: reduce) { .switch .track, .switch .track::after { transition: none; } }

  /* ---- Habits: the list and the editor ---------------------------------- */
  .igrid { display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 7fr); gap: 20px; align-items: start; }
  @media (max-width: 1180px) { .igrid { grid-template-columns: minmax(0, 1fr); } }
  .i-list { display: flex; flex-direction: column; gap: 6px; }
  .i-empty { color: var(--text-tert); font-size: 12.5px; padding: 18px; text-align: center; border: 1px dashed var(--border); border-radius: var(--r-md); }
  .i-row { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; gap: 10px; align-items: center; padding: 8px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); cursor: pointer; }
  .i-row:hover { border-color: var(--border-strong, var(--border)); }
  .i-row.sel { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent-soft); }
  .i-row.off .i-names { opacity: 0.5; }
  .i-moves { display: flex; flex-direction: column; gap: 3px; align-items: center; }
  .i-moves .pos { font-size: 10.5px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .i-names { min-width: 0; display: flex; flex-direction: column; gap: 1px; }
  .i-names .t-ar { font-size: 15px; line-height: 1.5; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .i-names .t-en { font-size: 12.5px; color: var(--text-sec); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .i-meta { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; margin-top: 3px; font-size: 11px; color: var(--text-tert); }
  .i-meta .cat { padding: 0 6px; border-radius: var(--r-pill); border: 1px solid var(--border); color: var(--text-sec); }
  .i-ends { display: flex; gap: 6px; align-items: center; }
  .list-note { margin: 8px 2px 0; font-size: 11.5px; color: var(--text-tert); }

  /* Pinned under the shell's top bar (66px; BASE_STYLES' --topbar-h is the
     report's, 150px, so it is not used here), and ending above the publish
     dock, whose height ideas/app.js keeps in --dock-h (it grows with its
     messages). */
  .editor { position: sticky; top: 78px; max-height: calc(100vh - 78px - var(--dock-h, 72px) - 28px); overflow-y: auto; border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); scrollbar-width: thin; }
  @media (max-width: 1180px) { .editor { position: static; max-height: none; } }
  .ed-head { position: sticky; top: 0; z-index: 2; display: flex; flex-wrap: wrap; gap: var(--s2) var(--s3); align-items: center; padding: 12px 16px; border-bottom: 1px solid var(--border-soft); background: var(--surface); }
  .ed-head h3 { margin: 0; font-size: 14px; font-weight: 650; text-transform: none; letter-spacing: 0; }
  .ed-head code { font-family: var(--mono); font-size: 11px; color: var(--text-tert); }
  .ed-head .grow { flex: 1 1 auto; }
  .ed-body { padding: 14px 16px 18px; display: flex; flex-direction: column; gap: 16px; }
  .ed-empty { padding: 48px 20px; text-align: center; color: var(--text-tert); font-size: 13px; }
  .sect h4 { margin: 0 0 8px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-tert); }
  .pair { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 10px 14px; }
  @media (max-width: 760px) { .pair { grid-template-columns: minmax(0, 1fr); } }
  .fld { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
  .fld-head { display: flex; align-items: baseline; gap: 8px; }
  .fld-head .lab { font-size: 12px; font-weight: 600; color: var(--text-sec); }
  .fld-head .grow { flex: 1 1 auto; }
  .fld-head .cnt { font-size: 11px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .fld-head .cnt.over { color: var(--danger); font-weight: 650; }
  .dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; background: var(--accent); }
  .inp, .ta, .sel-box { width: 100%; padding: 6px 10px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--bg); color: var(--text); font: inherit; font-size: 13.5px; min-width: 0; }
  .inp.t-ar, .ta.t-ar { font-family: var(--arabic); font-size: 15px; }
  .ta { resize: vertical; min-height: 64px; line-height: 1.55; }
  .inp:focus, .ta:focus, .sel-box:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .inp.has-error, .ta.has-error { border-color: var(--danger); }
  .inp.short { width: 90px; flex: 0 0 auto; }
  .sel-box { width: auto; height: 32px; padding: 0 8px; font-size: 13px; }
  .row-line { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  .row-line .unit { font-size: 12px; color: var(--text-tert); }
  .builtin { font-size: 11.5px; color: var(--text-tert); }
  .msgs { display: flex; flex-direction: column; gap: 2px; font-size: 12px; }
  .msgs:empty { display: none; }
  .msgs .err { color: var(--danger); }
  .msgs .wrn { color: var(--warn); }
  .hint { font-size: 11.5px; color: var(--text-tert); line-height: 1.45; }
  .ways { display: flex; flex-direction: column; gap: 6px; }
  .way { display: flex; gap: 6px; align-items: center; }
  .way .num { font-size: 11px; color: var(--text-tert); width: 14px; text-align: center; flex: 0 0 auto; }
  .day-chips { display: inline-flex; gap: 4px; flex-wrap: wrap; }
  .day-chips .chip { padding: 3px 9px; }

  /* ---- The card preview, in the app's colours ----------------------------- */
  .pv { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 12px; }
  @media (max-width: 760px) { .pv { grid-template-columns: minmax(0, 1fr); } }
  .pv-screen { padding: 12px; border-radius: 16px; background: var(--app-bg); color: var(--app-text); }
  .pv-screen[dir="rtl"] { font-family: var(--arabic); }
  .pv-label { font-size: 10.5px; font-weight: 700; letter-spacing: 1px; color: var(--app-text-sec); margin: 0 4px 8px; }
  .pv-screen[dir="rtl"] .pv-label { letter-spacing: 0; }
  .pv-card { display: grid; grid-template-columns: 40px minmax(0, 1fr) auto; gap: 12px; align-items: center; padding: 12px; border: 0.5px solid var(--app-border); border-radius: 14px; background: var(--app-surface); }
  .pv-tile { width: 40px; height: 40px; display: grid; place-items: center; border-radius: 12px; background: rgba(46, 207, 143, 0.12); color: var(--app-emerald); font-size: 15px; font-weight: 800; }
  .pv-tile.quit { background: rgba(228, 180, 95, 0.14); color: var(--app-gold); }
  .pv-name { display: block; font-size: 14.5px; font-weight: 800; line-height: 1.3; }
  .pv-short { display: block; margin-top: 3px; font-size: 12.5px; line-height: 1.4; color: var(--app-text-sec); }
  .pv-star { color: var(--app-gold); font-size: 15px; }
  .pv-empty { color: var(--app-text-tert); font-style: italic; }
  .pv-meta { grid-column: 1 / -1; margin-top: 2px; font-size: 11.5px; color: var(--text-tert); }

  /* ---- Plans -------------------------------------------------------------- */
  .p-list { display: flex; flex-direction: column; gap: 12px; }
  .p-card { border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); }
  .p-card.off .p-body { opacity: 0.55; }
  .p-head { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; padding: 10px 14px; border-bottom: 1px solid var(--border-soft); }
  .p-head .pos { font-size: 12px; color: var(--text-tert); font-variant-numeric: tabular-nums; width: 18px; text-align: end; }
  .p-head .nm { font-weight: 650; font-size: 13.5px; }
  /* margin-left, not -inline-start: the Arabic name runs right to left. */
  .p-head .nm .t-ar { font-weight: 650; margin-left: 10px; }
  .p-head code { font-family: var(--mono); font-size: 11px; color: var(--text-tert); }
  .p-head .grow { flex: 1 1 auto; }
  .p-body { padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 12px; }
  .p-habits { display: flex; flex-wrap: wrap; gap: 6px; }
  .p-habit { padding: 3px 10px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--bg-sunken); font-size: 12px; color: var(--text-sec); }
  .p-habit .t-ar { font-size: 13px; }
  .p-habit.missing { border-style: dashed; color: var(--warn); }

  /* ---- History ------------------------------------------------------------ */
  .card { border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); margin-top: var(--s5); }
  .card-head { display: flex; align-items: center; gap: var(--s3); padding: 12px 16px; border-bottom: 1px solid var(--border-soft); flex-wrap: wrap; }
  .card-head h3 { margin: 0; font-size: 14px; font-weight: 650; text-transform: none; letter-spacing: 0; }
  .card-head .sub { font-size: 12px; color: var(--text-tert); }
  .card-body { padding: 12px 16px 14px; }
  .hlist { display: flex; flex-direction: column; }
  .hrow { display: grid; grid-template-columns: 150px minmax(0, 1fr) auto; gap: var(--s4); align-items: start; padding: var(--s3) 0; border-top: 1px solid var(--border-soft); }
  .hrow:first-child { border-top: 0; }
  .hrow .when { font-size: 12px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .hrow .what { font-size: 12.5px; font-weight: 600; }
  .hrow .detail { font-size: 12.5px; color: var(--text-sec); margin-top: 2px; }
  .hrow.undone { opacity: 0.6; }

  /* ---- The publish dock ---------------------------------------------------- */
  .dock { position: sticky; bottom: 12px; z-index: 30; display: flex; gap: var(--s3); align-items: center; flex-wrap: wrap; margin-top: var(--s4); padding: 12px 16px; border: 1px solid var(--accent-line); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-md); }
  .dock .grow { flex: 1 1 auto; min-width: 0; font-size: 13px; }
  .dock .problems { margin-top: 3px; display: flex; flex-direction: column; gap: 2px; font-size: 12px; }
  .dock .problems .err { color: var(--danger); }
  .dock .problems .wrn { color: var(--warn); }
  .dock .problems button { background: none; border: 0; padding: 0; color: inherit; font: inherit; text-align: start; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .dock kbd { font-family: var(--mono); font-size: 10.5px; border: 1px solid var(--border); border-radius: 4px; padding: 0 4px; background: var(--bg); color: var(--text-sec); }

  .toast { position: fixed; left: 50%; bottom: 90px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 90; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }

  @media (max-width: 900px) {
    .hrow { grid-template-columns: minmax(0, 1fr); gap: var(--s2); }
  }
`;

function renderIdeasPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Habit ideas · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'ideas', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Habit ideas', sub: 'The ideas and ready-made plans in Add Habit, in Arabic and English, live on every phone', live: false })}
    <div class="app-content ideas-content">
      <p class="page-intro">Show or hide an idea, star it to show it first in its list, move it up or down, change its words and schedule, or add your own. The Plans tab does the same for the ready-made plans. Press Publish and every open app shows it within seconds, with no new build.
        <span class="fine">The built-in ideas are the app&rsquo;s assets/data/habit_ideas.json and the plans its habit_plans.dart; this page only stores what you change, so an idea the app adds in a later build still shows. Built-in ideas are hidden, never deleted; your own ideas can be deleted.</span></p>
      <div id="banners"></div>
      <section id="viewIdeas"><div class="loading">Loading the ideas&hellip;</div></section>
    </div>
  </div>
</div>
  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/wording/rules.js"></script>
  <script src="/wording/ideas_rules.js"></script>
  <script src="/ideas/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderIdeasPage, PAGE_STYLES };
