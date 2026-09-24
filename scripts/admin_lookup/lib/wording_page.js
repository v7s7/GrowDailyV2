'use strict';

/**
 * The Wording page's HTML and styles. The behaviour is in ../wording/app.js
 * and the rules it shares with the server in ../wording/rules.js, both
 * served as plain files rather than written into this template.
 *
 * That split is deliberate. This tool's other pages keep their browser
 * script inside a template literal, and twice that has shipped a page that
 * loaded and then did nothing: a backtick in a CSS comment ended the
 * literal early, and a backslash in 'today\'s' was eaten on the way out
 * (see test/inline_script.test.js). A script that is a real .js file is
 * parsed by the browser exactly as written, and by the tests the same way.
 * Only CSS lives here, and the test parses it out of the rendered page.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const PAGE_STYLES = `
  .wording-content { max-width: 1240px; }
  .wording-intro { margin: 0 0 var(--s5); font-size: 13px; color: var(--text-sec); max-width: 80ch; }
  .wording-intro .fine { display: block; margin-top: var(--s1); color: var(--text-tert); font-size: 12px; }
  :root {
    /* The Mac's own Arabic faces. Inter has no Arabic, and a fallback left
       to the browser picks a different face per machine. */
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* Which edition of these styles this is; wording/app.js checks it
       (STYLES_EDITION there, the two kept equal by the tests). The styles
       are built into the page when the server starts, the script is read
       from disk on every load, so a server left running across an update
       serves the new script with the old styles. */
    --wording-styles: 2;
  }


  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s3); border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner code { font-family: var(--mono); font-size: 12px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: 6px; padding: 1px 5px; user-select: all; white-space: nowrap; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .banner.ok { background: var(--success-soft); border-color: var(--success-line); color: var(--success); }
  .banner .grow { flex: 1 1 auto; min-width: 0; }
  .banner .btn { flex: 0 0 auto; }

  .view { display: none; }
  .view.active { display: block; }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }

  /* ---- Arabic and English text, everywhere on the page ----------------
     Arabic runs right to left in its own face and a size up, because the
     same pixel size reads visibly smaller in Arabic. plaintext lets a
     {part} or a Latin word inside an Arabic sentence sit where the reader
     expects it instead of being pulled to the wrong end. */
  .t-ar { font-family: var(--arabic); font-size: 15.5px; line-height: 1.75; direction: rtl; text-align: right; unicode-bidi: plaintext; }
  .t-en { font-size: 13.5px; line-height: 1.55; direction: ltr; text-align: left; unicode-bidi: plaintext; }
  textarea { width: 100%; resize: vertical; padding: var(--s3) var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); color: var(--text); font-family: inherit; min-height: 44px; }
  textarea.t-ar { font-family: var(--arabic); }
  textarea:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  textarea.has-error { border-color: var(--danger); }

  /* ---- Daily lines ---------------------------------------------------- */
  .today { padding: var(--s5); border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); margin-bottom: var(--s5); }
  .today .label { font-size: 11px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-tert); }
  .today .t-ar { font-size: 20px; margin-top: var(--s3); }
  .today .t-en { color: var(--text-sec); margin-top: var(--s1); }
  .today .from { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; margin-top: var(--s4); padding-top: var(--s3); border-top: 1px solid var(--border-soft); font-size: 12.5px; color: var(--text-sec); }
  .today .from .grow { flex: 1 1 auto; }

  /* A line moves by its grip (drag, or click for the move menu), by its
     date (click: the same menu), by the arrows, or ticked with others.
     The list is position: relative so each row's offsetTop is measured
     from it: the drag reads rows by layout, never where they are drawn. */
  .qlist { position: relative; display: flex; flex-direction: column; gap: var(--s2); }
  .qrow { display: grid; grid-template-columns: 22px 96px 1fr 1fr auto; gap: var(--s3); align-items: start; padding: var(--s3) var(--s3) var(--s3) var(--s1); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); outline: 2px solid transparent; outline-offset: 2px; }
  .qrow.is-today { border-color: var(--accent-line); box-shadow: inset 3px 0 0 var(--accent); }
  .qrow.is-picked { border-color: var(--accent-line); background: linear-gradient(var(--accent-soft), var(--accent-soft)), var(--surface); }
  /* The gap a dragged line would drop into: the row itself, its boxes
     hidden but kept, so the text and the cursor in them survive. */
  .qrow.is-placeholder { border: 1px dashed var(--accent); background: var(--accent-soft); box-shadow: none; }
  .qrow.is-placeholder > * { visibility: hidden; }
  .qrow.is-hidden { display: none; }
  .qrow.flash { outline-color: var(--accent); }
  @media (prefers-reduced-motion: no-preference) {
    .qrow.flash { animation: q-flash 1.2s ease-out forwards; }
  }
  @keyframes q-flash { 0%, 35% { outline-color: var(--accent); } 100% { outline-color: transparent; } }

  .grip { align-self: stretch; display: flex; justify-content: center; align-items: flex-start; padding: 9px 0 0; border: 0; border-radius: var(--r-sm); background: none; color: var(--text-tert); cursor: grab; touch-action: none; }
  .qrow:hover .grip { color: var(--text-sec); }
  .grip:hover, .grip[aria-expanded="true"] { color: var(--accent); background: var(--accent-soft); }
  .qmeta { font-size: 12px; color: var(--text-tert); padding-top: var(--s2); min-width: 0; }
  .qhead { display: flex; align-items: center; gap: 7px; }
  .qmeta .num { font-size: 13px; font-weight: 700; color: var(--text); font-variant-numeric: tabular-nums; }
  .pick { width: 14px; height: 14px; margin: 0; accent-color: var(--accent); cursor: pointer; opacity: 0.45; }
  .qrow:hover .pick, .pick:checked, .pick:focus-visible, .qlist.picking .pick { opacity: 1; }
  /* The date is a button: the list is a schedule, and "when does this
     show" is the thing to change. */
  .qmeta .when { display: inline-block; margin: 3px 0 0 -5px; padding: 1px 5px; border: 0; border-radius: 6px; background: none; color: inherit; font: inherit; font-size: 12px; text-align: start; cursor: pointer; }
  .qmeta .when:hover, .qmeta .when[aria-expanded="true"] { background: var(--accent-soft); color: var(--accent); }
  .qmeta .when.now { color: var(--accent); font-weight: 650; }
  .qmeta .src { display: block; margin-top: var(--s1); font-size: 11px; line-height: 1.4; }
  .qtools { display: flex; gap: var(--s1); padding-top: 2px; }
  .icon-btn { width: 30px; height: 28px; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); color: var(--text-sec); cursor: pointer; font-family: inherit; font-size: 13px; line-height: 1; }
  .icon-btn:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
  .icon-btn.del:hover:not(:disabled) { border-color: var(--danger); color: var(--danger); }
  .icon-btn:disabled { opacity: 0.35; cursor: default; }
  .add-line { margin-top: var(--s3); }
  .list-note { font-size: 12.5px; color: var(--text-tert); margin: 0 var(--s1) var(--s3); }
  .list-note p { margin: 0; }
  .list-note p + p { margin-top: 3px; }
  .list-note svg { vertical-align: -3px; margin: 0 1px; color: var(--text-sec); }
  .list-note kbd { font-family: var(--mono); font-size: 10.5px; border: 1px solid var(--border); border-radius: 4px; padding: 0 4px; background: var(--bg); color: var(--text-sec); }

  /* While a line is dragged: the card on the pointer, and no text
     selection or I-beam anywhere. */
  body.lines-dragging, body.lines-dragging * { cursor: grabbing !important; -webkit-user-select: none; user-select: none; }
  .drag-ghost { position: fixed; top: 0; left: 0; z-index: 80; display: flex; gap: var(--s3); align-items: flex-start; width: min(520px, 46vw); padding: var(--s3) var(--s4) var(--s3) var(--s3); border: 1px solid var(--accent-line); border-radius: var(--r-md); background: var(--surface-2); box-shadow: var(--shadow-lg); pointer-events: none; }
  .drag-ghost.is-stack { box-shadow: 5px 5px 0 -1px var(--surface-2), 5px 5px 0 0 var(--accent-line), var(--shadow-lg); }
  .dg-grip { color: var(--accent); padding-top: 1px; }
  .dg-body { flex: 1 1 auto; min-width: 0; }
  .dg-head { display: flex; align-items: baseline; gap: var(--s2); font-size: 12px; color: var(--text-sec); font-variant-numeric: tabular-nums; }
  .dg-head b { color: var(--text); font-weight: 700; }
  .dg-head .dg-at { color: var(--accent); }
  .dg-more { margin-inline-start: auto; font-size: 11px; color: var(--text-tert); white-space: nowrap; }
  .drag-ghost .dg-ar { font-size: 15px; line-height: 1.6; margin-top: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .drag-ghost .dg-en { font-size: 12.5px; color: var(--text-sec); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

  /* The move menu. */
  .move-menu { position: absolute; z-index: 70; width: 304px; padding: var(--s2); border: 1px solid var(--border-strong); border-radius: var(--r-md); background: var(--surface); box-shadow: var(--shadow-lg); font-size: 13px; }
  .mm-head { padding: var(--s2) var(--s3) var(--s3); }
  .mm-head b { display: block; font-size: 13px; font-weight: 650; }
  .mm-head span { display: block; margin-top: 2px; font-size: 12px; color: var(--text-tert); }
  .mm-item { display: flex; align-items: center; justify-content: space-between; gap: var(--s4); width: 100%; padding: 7px var(--s3); border: 0; border-radius: var(--r-sm); background: none; color: var(--text); font: inherit; font-size: 13px; text-align: start; cursor: pointer; }
  .mm-item:hover:not(:disabled), .mm-item:focus-visible { background: var(--accent-soft); outline: none; }
  .mm-item:disabled { color: var(--text-tert); cursor: default; }
  .mm-hint { color: var(--text-tert); font-size: 12px; font-variant-numeric: tabular-nums; }
  .mm-sep { height: 1px; margin: var(--s2) var(--s1); background: var(--border-soft); }
  .mm-field { display: flex; align-items: center; gap: var(--s2); padding: 4px var(--s3); color: var(--text-sec); font-size: 12.5px; }
  .mm-field label { flex: 0 0 58px; }
  .mm-field input { flex: 1 1 auto; min-width: 0; height: 30px; padding: 0 var(--s2); border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg); color: var(--text); font: inherit; font-size: 12.5px; font-variant-numeric: tabular-nums; }
  .mm-field input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .mm-field .mm-of { color: var(--text-tert); white-space: nowrap; }
  .mm-go { padding: 5px var(--s3); }
  .mm-err { padding: 4px var(--s3) 2px; color: var(--danger); font-size: 12px; }
  .mm-err[hidden] { display: none; }

  /* The dock: ticked lines, then unsaved changes, one panel pinned to the
     bottom so Save is reachable from anywhere in a 36-line list. One
     panel, not two bars: a gap between two would show the rows behind. */
  .dock { position: sticky; bottom: 0; z-index: 30; margin-top: var(--s4); border: 1px solid var(--accent-line); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-md); }
  .dock[hidden] { display: none; }
  .savebar, .selbar { padding: var(--s3) var(--s4); }
  .selbar:not([hidden]) + .savebar:not([hidden]) { border-top: 1px solid var(--border-soft); }
  .savebar .row, .selbar .row { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; }
  .savebar .grow, .selbar .grow { flex: 1 1 auto; min-width: 0; font-size: 13px; }
  .selbar .sel-nums { color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .savebar .msgs { margin-top: var(--s2); }
  .btn.del-btn:hover:not(:disabled) { color: var(--danger); border-color: var(--danger-line); }

  /* ---- App text ------------------------------------------------------- */
  .filter-bar { position: sticky; top: 0; z-index: 25; display: flex; flex-wrap: wrap; gap: var(--s3); align-items: center; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: var(--s3); margin-bottom: var(--s3); box-shadow: var(--shadow-sm); }
  .filter-bar input[type="search"] { flex: 2; min-width: 220px; border-color: transparent; background: var(--bg-sunken); }
  .filter-bar input[type="search"]:focus { background: var(--surface); border-color: var(--accent); }
  .chip-row { display: flex; gap: var(--s1); flex-wrap: wrap; }
  .chip-btn { padding: 5px var(--s4); border-radius: var(--r-sm); border: 1px solid transparent; background: none; font-size: 12px; font-weight: 500; cursor: pointer; color: var(--text-sec); font-family: inherit; white-space: nowrap; }
  .chip-btn:hover { background: var(--bg-sunken); color: var(--text); }
  .chip-btn.active { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); font-weight: 600; }
  .chip-btn .n { font-variant-numeric: tabular-nums; opacity: 0.75; margin-inline-start: 4px; }
  .status-row { display: flex; justify-content: space-between; gap: var(--s4); margin: var(--s1) var(--s2) var(--s3); font-size: 12px; color: var(--text-tert); font-variant-numeric: tabular-nums; }

  .slist { display: flex; flex-direction: column; gap: var(--s2); }
  .srow { border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); padding: var(--s3) var(--s4); }
  .srow.editable:not(.open) { cursor: pointer; }
  .srow.editable:not(.open):hover { border-color: var(--border-strong); background: var(--surface-2); }
  .srow.open { border-color: var(--accent-line); box-shadow: var(--shadow-md); }
  .srow.fixed { background: var(--surface-2); }
  .srow-head { display: flex; align-items: baseline; gap: var(--s2); flex-wrap: wrap; font-size: 11.5px; color: var(--text-tert); margin-bottom: var(--s2); }
  .srow-head .where { flex: 1 1 auto; min-width: 0; }
  .srow-head .where b { color: var(--text-sec); font-weight: 600; }
  .key { font-family: var(--mono); font-size: 10.5px; color: var(--text-tert); }
  .badge { display: inline-block; padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; letter-spacing: 0.2px; border: 1px solid; white-space: nowrap; }
  .badge.edited { color: var(--accent); background: var(--accent-soft); border-color: var(--accent-line); }
  .badge.drift { color: var(--warn); background: var(--warn-soft); border-color: var(--warn-line); }
  .badge.unused { color: var(--text-tert); background: var(--bg-sunken); border-color: var(--border); }
  .badge.fixed { color: var(--text-sec); background: var(--bg-sunken); border-color: var(--border); }
  .srow-cols { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s5); }
  .srow-cols .t-en { color: var(--text-sec); }
  .cell { white-space: pre-wrap; overflow-wrap: anywhere; }
  .tok { unicode-bidi: isolate; direction: ltr; font-family: var(--mono); font-size: 0.72em; color: var(--accent); background: var(--accent-soft); border-radius: 5px; padding: 0 4px; white-space: nowrap; }
  .cell .mark { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: var(--accent); vertical-align: middle; margin-inline-end: 6px; }
  .srow.fixed .why { font-size: 12px; color: var(--text-tert); margin-top: var(--s2); }

  .editor { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s5); }
  .field-head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s2); margin-bottom: var(--s2); }
  .field-head .lang { font-size: 11px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-sec); }
  .link-btn { background: none; border: none; padding: 0; color: var(--accent); font: inherit; font-size: 12px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }
  .parts { display: flex; flex-wrap: wrap; gap: var(--s1); align-items: center; margin-top: var(--s2); font-size: 11.5px; color: var(--text-tert); }
  .part { font-family: var(--mono); font-size: 11px; padding: 2px 7px; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); color: var(--text-sec); cursor: pointer; direction: ltr; }
  .part:hover { border-color: var(--accent); color: var(--accent); }
  .part.missing { border-style: dashed; color: var(--warn); }
  .ref { margin-top: var(--s2); font-size: 12px; color: var(--text-tert); }
  .ref .t-ar { font-size: 13.5px; color: var(--text-sec); }
  .ref .t-en { font-size: 12.5px; color: var(--text-sec); }
  .msgs { display: flex; flex-direction: column; gap: 3px; margin-top: var(--s2); font-size: 12px; }
  .msgs .err { color: var(--danger); }
  .msgs .wrn { color: var(--warn); }
  .msgs .err::before { content: '\\2715  '; }
  .msgs .wrn::before { content: '!  '; font-weight: 700; }
  .editor-foot { display: flex; align-items: center; gap: var(--s3); flex-wrap: wrap; margin-top: var(--s4); padding-top: var(--s3); border-top: 1px solid var(--border-soft); }
  .editor-foot .hint { color: var(--text-tert); font-size: 11.5px; margin-inline-start: auto; }
  .editor-foot kbd { font-family: var(--mono); font-size: 10px; border: 1px solid var(--border); border-radius: 4px; padding: 1px 4px; background: var(--bg); }
  details.notes { margin-top: var(--s3); font-size: 12.5px; color: var(--text-sec); }
  details.notes summary { cursor: pointer; color: var(--text-tert); font-size: 12px; }
  details.notes p { margin: var(--s2) 0 0; max-width: 90ch; white-space: pre-wrap; }
  .more { display: flex; justify-content: center; margin-top: var(--s4); }
  .btn:disabled { opacity: 0.45; cursor: default; }

  /* ---- History -------------------------------------------------------- */
  .hlist { display: flex; flex-direction: column; gap: var(--s2); }
  .hrow { display: grid; grid-template-columns: 150px 1fr auto; gap: var(--s4); align-items: start; padding: var(--s3) var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); }
  .hrow .when { font-size: 12px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .hrow .what { font-size: 12.5px; font-weight: 600; margin-bottom: var(--s1); }
  .hrow .what .key { font-weight: 400; margin-inline-start: var(--s2); }
  .hrow del { color: var(--text-tert); text-decoration-color: var(--danger-line); }
  .hrow ins { text-decoration: none; }
  .hrow .none { color: var(--text-tert); font-style: italic; font-size: 12px; }
  .hrow .side-label { font-size: 10.5px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-tert); margin-top: var(--s2); }
  .hrow .change { white-space: pre-wrap; overflow-wrap: anywhere; }
  .hrow .change.t-ar { font-size: 14.5px; }
  .hrow.undone { opacity: 0.6; }

  .toast { position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 60; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  @media (max-width: 760px) {
    .qrow { grid-template-columns: 22px 1fr; }
    .qrow .grip { grid-row: 1 / span 4; }
    .qrow > :not(.grip) { grid-column: 2; }
    .srow-cols, .editor { grid-template-columns: 1fr; gap: var(--s3); }
    .hrow { grid-template-columns: 1fr; gap: var(--s2); }
  }
`;

function renderWordingPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Wording · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'wording', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Wording', sub: 'The app\'s text in Arabic and English, live on every phone', live: false })}
    <div class="app-content wording-content">
      <p class="wording-intro">Press Save and every open app shows the new text within seconds, with no new build.
        <span class="fine">Phones still on an app build from before this page keep their built-in text until they update.</span></p>

      <div id="banners"></div>

      <div class="view-tabs" role="tablist">
        <button class="view-tab active" role="tab" data-tab="lines">Daily lines <span class="vt-count" id="cntLines"></span></button>
        <button class="view-tab" role="tab" data-tab="text">App text <span class="vt-count" id="cntText"></span></button>
        <button class="view-tab" role="tab" data-tab="history">History <span class="vt-count" id="cntHistory"></span></button>
      </div>

      <section class="view active" id="viewLines"><div class="loading">Loading the wording&hellip;</div></section>
      <section class="view" id="viewText"></section>
      <section class="view" id="viewHistory"></section>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/wording/rules.js"></script>
  <script src="/wording/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderWordingPage, PAGE_STYLES };
