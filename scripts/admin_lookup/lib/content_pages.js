'use strict';

/**
 * The FAQ and Premium pages' HTML and styles. The behaviour is in
 * ../content/kit.js (shared), ../content/faq.js and ../content/premium.js,
 * and the rules they share with the server in ../wording/content_rules.js,
 * all served as plain files for the reason lib/wording_page.js gives: a
 * page script inside a template literal has twice shipped a page that
 * loaded and then did nothing.
 *
 * Aziz, 2026-09-26: "make the faq, and the premium details all in the admin
 * change firebase, online change not hard code". Both pages write the same
 * document the Wording page does (wording/live), so a save reaches every
 * open app within seconds and needs no deploy, and both keep History with
 * Undo in the same log.
 *
 * The preview on the right of each page is drawn in the app's own default
 * dark colours (Emerald and Gold, theme_preset.dart), fixed on purpose: it
 * shows what a phone shows, whatever this tool's own theme is.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar } = require('./shell');

const CONTENT_STYLES = `
  :root {
    /* The Mac's own Arabic faces, as on the Wording page. */
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* Which edition of these styles this is; content/kit.js checks it
       (EDITION there, the two kept equal by the tests). */
    --content-styles: 1;
    /* The app's default dark theme, for the phone preview only. */
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
  .content-page { max-width: 1520px; }
  .page-intro { margin: 0 0 var(--s4); font-size: 13px; color: var(--text-sec); max-width: 86ch; }
  .page-intro .fine { display: block; margin-top: var(--s1); color: var(--text-tert); font-size: 12px; }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }
  .muted-note { color: var(--text-tert); font-size: 12.5px; margin: 0; }

  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s3); border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner code { font-family: var(--mono); font-size: 12px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: 6px; padding: 1px 5px; user-select: all; white-space: nowrap; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .banner .grow { flex: 1 1 auto; min-width: 0; }

  /* ---- Arabic and English text --------------------------------------- */
  .t-ar { font-family: var(--arabic); font-size: 15.5px; line-height: 1.75; direction: rtl; text-align: right; unicode-bidi: plaintext; }
  .t-en { font-size: 13.5px; line-height: 1.55; direction: ltr; text-align: left; unicode-bidi: plaintext; }
  textarea { width: 100%; resize: vertical; padding: 7px var(--s3); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--bg); color: var(--text); font-family: inherit; min-height: 38px; }
  textarea.t-ar { font-family: var(--arabic); }
  textarea:focus, select:focus, input[type="search"]:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  textarea.has-error { border-color: var(--danger); }
  select { height: 30px; padding: 0 var(--s2); border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg); color: var(--text); font: inherit; font-size: 12.5px; }
  .btn:disabled { opacity: 0.45; cursor: default; }
  .btn.small { padding: 5px var(--s3); font-size: 12px; }
  .btn.danger-soft:hover:not(:disabled) { color: var(--danger); border-color: var(--danger-line); }
  .link-btn { background: none; border: none; padding: 0; color: var(--accent); font: inherit; font-size: 12px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }
  .icon-only { width: 28px; height: 26px; display: inline-grid; place-items: center; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); color: var(--text-sec); cursor: pointer; font-family: inherit; font-size: 13px; line-height: 1; padding: 0; }
  .icon-only:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
  .icon-only:disabled { opacity: 0.35; cursor: default; }
  .msgs { display: flex; flex-direction: column; gap: 3px; margin-top: 4px; font-size: 12px; }
  .msgs:empty { display: none; }
  .msgs .err { color: var(--danger); }
  .msgs .wrn { color: var(--warn); }
  .msgs .err::before { content: '\\2715  '; }
  .msgs .wrn::before { content: '!  '; font-weight: 700; }

  .msr { font-family: 'Material Symbols Rounded'; font-weight: normal; font-style: normal; font-size: 22px; line-height: 1; letter-spacing: normal; text-transform: none; display: inline-block; white-space: nowrap; direction: ltr; font-feature-settings: 'liga'; -webkit-font-smoothing: antialiased; font-variation-settings: 'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24; }

  .badge { display: inline-block; padding: 1px 7px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 650; letter-spacing: 0.2px; border: 1px solid; white-space: nowrap; }
  .badge.edited { color: var(--accent); background: var(--accent-soft); border-color: var(--accent-line); }
  .badge.added { color: var(--success); background: var(--success-soft); border-color: var(--success-line); }
  .badge.fresh { color: var(--info); background: var(--info-soft); border-color: var(--info-line); }
  .badge.drift { color: var(--warn); background: var(--warn-soft); border-color: var(--warn-line); }
  .badge.unsaved { color: var(--undo); background: var(--undo-soft); border-color: var(--undo-line); }
  .badge.muted { color: var(--text-tert); background: var(--bg-sunken); border-color: var(--border); }

  /* ---- Layout: the editor, and the phone beside it -------------------- */
  .cgrid { display: grid; grid-template-columns: minmax(0, 1fr) 396px; gap: 28px; align-items: start; }
  .preview-col { position: sticky; top: calc(var(--topbar-h, 64px) + 14px); }
  @media (max-width: 1240px) {
    .cgrid { grid-template-columns: minmax(0, 1fr); }
    .preview-col { position: static; }
  }

  .toolbar { position: sticky; top: calc(var(--topbar-h, 64px) + 6px); z-index: 25; display: flex; flex-wrap: wrap; gap: var(--s2); align-items: center; padding: var(--s3); margin-bottom: var(--s4); border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); }
  .toolbar input[type="search"] { flex: 1 1 240px; min-width: 200px; height: 32px; padding: 0 var(--s3); border: 1px solid transparent; border-radius: var(--r-md); background: var(--bg-sunken); color: var(--text); font: inherit; font-size: 13px; }
  .toolbar .sep { width: 1px; height: 22px; background: var(--border); margin: 0 var(--s1); }

  .card { border: 1px solid var(--border); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-sm); margin-bottom: var(--s4); }
  .card-head { display: flex; align-items: center; gap: var(--s3); padding: 12px 16px; border-bottom: 1px solid var(--border-soft); flex-wrap: wrap; }
  .card-head h3 { margin: 0; font-size: 14px; font-weight: 650; color: var(--text); text-transform: none; letter-spacing: 0; }
  .card-head .sub { font-size: 12px; color: var(--text-tert); }
  .card-head .grow { flex: 1 1 auto; }
  .card-body { padding: 12px 16px 14px; }
  .card-note { margin: 0 0 var(--s3); font-size: 12.5px; color: var(--text-sec); }
  .card-note.warn { color: var(--warn); }
  details.card > summary { list-style: none; cursor: pointer; }
  details.card > summary::-webkit-details-marker { display: none; }
  details.card > summary .chev { transition: transform 0.15s ease; color: var(--text-tert); }
  details.card[open] > summary .chev { transform: rotate(180deg); }
  details.card:not([open]) > summary { border-bottom: 0; }

  /* ---- Rows that move --------------------------------------------------- */
  .grip { align-self: stretch; display: flex; justify-content: center; align-items: flex-start; padding: 9px 0 0; border: 0; border-radius: var(--r-sm); background: none; color: var(--text-tert); cursor: grab; touch-action: none; }
  .grip:hover { color: var(--accent); background: var(--accent-soft); }
  .grip:disabled { cursor: default; opacity: 0.3; background: none; }
  .is-lifted { position: fixed !important; z-index: 80; pointer-events: none; box-shadow: var(--shadow-lg) !important; background: var(--surface-2) !important; border-color: var(--accent-line) !important; }
  .drag-slot { border: 1px dashed var(--accent); border-radius: var(--r-md); background: var(--accent-soft); }
  body.rows-dragging, body.rows-dragging * { cursor: grabbing !important; -webkit-user-select: none; user-select: none; }
  .drop-here { outline: 1px dashed var(--accent-line); outline-offset: 2px; border-radius: var(--r-md); }
  .flash { animation: row-flash 1.2s ease-out; }
  @keyframes row-flash { 0%, 35% { box-shadow: 0 0 0 2px var(--accent); } 100% { box-shadow: 0 0 0 2px transparent; } }
  @media (prefers-reduced-motion: reduce) { .flash { animation: none; } }

  /* ---- FAQ groups and questions ----------------------------------------- */
  .g-card { margin-bottom: var(--s4); }
  .g-head { display: grid; grid-template-columns: auto minmax(0, 1fr) minmax(0, 1fr) auto; gap: 10px; align-items: start; padding: 10px 12px; border-bottom: 1px solid var(--border-soft); }
  .g-moves { display: flex; flex-direction: column; gap: 3px; padding-top: 2px; }
  .g-head textarea { resize: none; }
  .g-side { display: flex; flex-direction: column; align-items: flex-end; gap: 6px; padding-top: 4px; font-size: 11.5px; color: var(--text-tert); white-space: nowrap; }
  .g-side .badges { display: flex; gap: 4px; }
  .fld-head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s2); margin-bottom: 3px; }
  .fld-head .lab { font-size: 10.5px; font-weight: 650; text-transform: uppercase; letter-spacing: 0.55px; color: var(--text-tert); }
  .q-list { display: flex; flex-direction: column; gap: 6px; min-height: 48px; padding: 8px; }
  .q-empty { color: var(--text-tert); font-size: 12.5px; padding: 12px; text-align: center; border: 1px dashed var(--border); border-radius: var(--r-md); }
  .q-row { display: grid; grid-template-columns: 22px minmax(0, 1fr); gap: 6px; padding: 8px 10px 8px 3px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); }
  .q-row.open { border-color: var(--accent-line); box-shadow: var(--shadow-md); }
  .q-row.hidden-by-search { display: none; }
  .q-line { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto; gap: 14px; align-items: center; cursor: pointer; border-radius: var(--r-sm); }
  .q-line .t-ar { font-size: 15px; line-height: 1.6; }
  .q-line .t-en { color: var(--text-sec); font-size: 13px; }
  .q-line .ends { display: flex; gap: 4px; align-items: center; }
  .q-line .chev { color: var(--text-tert); transition: transform 0.15s ease; }
  .q-row.open .q-line .chev { transform: rotate(180deg); }
  .q-edit { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 12px 16px; margin-top: 10px; }
  .q-edit .full, .drift-note { grid-column: 1 / -1; }
  .drift-note { padding: var(--s2) var(--s3); border: 1px solid var(--warn-line); border-radius: var(--r-md); background: var(--warn-soft); color: var(--warn); font-size: 12.5px; }
  .drift-note .was { display: block; margin-top: 4px; color: var(--text-sec); }
  .drift-note .acts { display: flex; gap: var(--s3); margin-top: 6px; }
  .q-foot { grid-column: 1 / -1; display: flex; gap: var(--s2); align-items: center; flex-wrap: wrap; padding-top: 10px; border-top: 1px solid var(--border-soft); font-size: 12px; color: var(--text-tert); }
  .q-foot .grow { flex: 1 1 auto; }
  .g-foot { display: flex; gap: var(--s2); padding: 0 12px 12px; }
  .removed-row { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto; gap: 14px; align-items: center; padding: 8px 0; border-top: 1px solid var(--border-soft); }
  .removed-row:first-child { border-top: 0; }

  /* ---- Premium: benefit rows and string rows ---------------------------- */
  .b-list { display: flex; flex-direction: column; gap: 8px; min-height: 48px; }
  .b-row { display: grid; grid-template-columns: 22px 46px minmax(0, 1fr) auto; gap: 10px; align-items: start; padding: 10px 10px 10px 3px; border: 1px solid var(--border); border-radius: var(--r-md); background: var(--surface); }
  .b-icon { width: 46px; height: 46px; display: grid; place-items: center; border-radius: 12px; border: 1px solid var(--border); background: var(--bg); color: var(--accent); cursor: pointer; }
  .b-icon:hover { border-color: var(--accent); background: var(--accent-soft); }
  .b-fields { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 8px 12px; }
  .b-meta { grid-column: 1 / -1; display: flex; gap: 6px; flex-wrap: wrap; align-items: center; font-size: 11.5px; color: var(--text-tert); }
  .b-tools { display: flex; flex-direction: column; gap: 4px; }
  .s-row { display: grid; grid-template-columns: 210px minmax(0, 1fr) minmax(0, 1fr); gap: 12px; padding: 10px 0; border-top: 1px solid var(--border-soft); }
  .s-row:first-child { border-top: 0; padding-top: 2px; }
  .s-label b { display: block; font-size: 13px; font-weight: 600; color: var(--text); }
  .s-label code { font-family: var(--mono); font-size: 10.5px; color: var(--text-tert); }
  .s-label .also { display: block; margin-top: 3px; font-size: 11.5px; color: var(--text-tert); }
  .s-label .badges { display: flex; gap: 4px; flex-wrap: wrap; margin-top: 4px; }
  .s-fixed { grid-column: 2 / -1; font-size: 12.5px; color: var(--text-tert); }
  .parts { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; margin-top: 4px; font-size: 11.5px; color: var(--text-tert); }
  .part { font-family: var(--mono); font-size: 11px; padding: 1px 6px; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg); color: var(--text-sec); cursor: pointer; direction: ltr; }
  .part:hover { border-color: var(--accent); color: var(--accent); }
  .part.missing { border-style: dashed; color: var(--warn); }

  .icon-pop { position: absolute; z-index: 70; width: 348px; padding: 10px; border: 1px solid var(--border-strong); border-radius: var(--r-md); background: var(--surface); box-shadow: var(--shadow-lg); }
  .icon-pop .ip-head { display: flex; justify-content: space-between; align-items: baseline; padding: 2px 4px 8px; font-size: 12px; color: var(--text-sec); }
  .icon-pop .ip-name { font-family: var(--mono); font-size: 11px; color: var(--text-tert); }
  .icon-grid { display: grid; grid-template-columns: repeat(8, 1fr); gap: 4px; }
  .icon-grid button { height: 36px; display: grid; place-items: center; border-radius: 8px; border: 1px solid transparent; background: none; color: var(--text-sec); cursor: pointer; }
  .icon-grid button:hover, .icon-grid button:focus-visible { background: var(--accent-soft); color: var(--accent); outline: none; }
  .icon-grid button.on { border-color: var(--accent); color: var(--accent); }

  /* ---- The save dock ---------------------------------------------------- */
  .dock { position: sticky; bottom: 12px; z-index: 30; display: flex; gap: var(--s3); align-items: center; flex-wrap: wrap; margin-top: var(--s4); padding: 12px 16px; border: 1px solid var(--accent-line); border-radius: var(--r-lg); background: var(--surface); box-shadow: var(--shadow-md); }
  .dock[hidden] { display: none; }
  .dock .grow { flex: 1 1 auto; min-width: 0; font-size: 13px; }
  .dock .problems { color: var(--danger); }
  .dock .problems button { color: var(--danger); }
  .dock .notes { color: var(--warn); font-size: 12px; margin-top: 2px; }
  .dock kbd { font-family: var(--mono); font-size: 10.5px; border: 1px solid var(--border); border-radius: 4px; padding: 0 4px; background: var(--bg); color: var(--text-sec); }

  /* ---- History ---------------------------------------------------------- */
  .hlist { display: flex; flex-direction: column; gap: var(--s2); }
  .hrow { display: grid; grid-template-columns: 150px minmax(0, 1fr) auto; gap: var(--s4); align-items: start; padding: var(--s3) 0; border-top: 1px solid var(--border-soft); }
  .hrow:first-child { border-top: 0; }
  .hrow .when { font-size: 12px; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .hrow .what { font-size: 12.5px; font-weight: 600; }
  .hrow .detail { font-size: 12.5px; color: var(--text-sec); margin-top: 2px; }
  .hrow.undone { opacity: 0.6; }

  .toast { position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 90; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  /* ---- The phone preview ---------------------------------------------- */
  .preview-tools { display: flex; justify-content: center; gap: var(--s2); flex-wrap: wrap; margin-bottom: 10px; }
  .seg { display: inline-flex; gap: 2px; padding: 3px; border-radius: var(--r-md); background: var(--bg-sunken); border: 1px solid var(--border); }
  .seg button { padding: 4px 12px; border-radius: 8px; border: 1px solid transparent; background: none; color: var(--text-sec); font: inherit; font-size: 12px; font-weight: 550; cursor: pointer; }
  .seg button.on { background: var(--surface); border-color: var(--border); color: var(--text); }
  .phone { width: 372px; max-width: 100%; margin: 0 auto; padding: 11px; border-radius: 46px; background: #141917; box-shadow: 0 30px 60px -30px rgba(0, 0, 0, 0.85), inset 0 0 0 1px #2b312e; }
  .phone-screen { position: relative; height: min(780px, calc(100vh - 190px)); min-height: 420px; overflow-y: auto; border-radius: 36px; background: var(--app-bg); color: var(--app-text); font-family: var(--sans); scrollbar-width: thin; }
  .phone-screen[dir="rtl"] { font-family: var(--arabic); }
  .pv-status { height: 44px; }
  .pv-bar { display: flex; align-items: center; gap: 12px; padding: 4px 16px 12px; font-size: 17px; font-weight: 800; }
  .pv-bar .msr { font-size: 22px; color: var(--app-text); }
  .pv-note { margin: 10px auto 0; max-width: 360px; font-size: 11.5px; color: var(--text-tert); text-align: center; }
  .pv-label { padding: 6px 20px 10px; font-size: 11px; font-weight: 700; letter-spacing: 1.5px; color: var(--app-text-sec); }
  .phone-screen[dir="rtl"] .pv-label { letter-spacing: 0; }
  .pv-group { padding: 0 22px 8px; font-size: 11.5px; font-weight: 700; color: var(--app-text-tert); }
  .pv-card { margin: 0 16px 18px; border: 0.5px solid var(--app-border); border-radius: 16px; background: var(--app-surface); overflow: hidden; }
  .pv-q { display: block; width: 100%; padding: 14px 16px; border: 0; border-top: 0.5px solid var(--app-border); background: none; color: inherit; font: inherit; text-align: start; cursor: pointer; }
  .pv-q:first-child { border-top: 0; }
  .pv-q .row { display: flex; gap: 8px; align-items: flex-start; }
  .pv-q .qt { flex: 1 1 auto; font-size: 14px; font-weight: 600; line-height: 1.3; }
  .pv-q .msr { font-size: 20px; color: var(--app-text-tert); transition: transform 0.15s ease; }
  .pv-q.open .msr { transform: rotate(180deg); }
  .pv-q .at { margin-top: 8px; font-size: 13px; line-height: 1.5; color: var(--app-text-sec); }
  .pv-hero { margin: 8px 20px 22px; padding: 24px; border-radius: 16px; border: 1px solid rgba(228, 180, 95, 0.4); background: linear-gradient(135deg, rgba(228, 180, 95, 0.2), var(--app-surface)); text-align: center; }
  .pv-crown { width: 64px; height: 64px; display: grid; place-items: center; margin: 0 auto 14px; border-radius: 50%; background: rgba(228, 180, 95, 0.16); color: var(--app-gold); }
  .pv-crown .msr { font-size: 32px; }
  .pv-headline { font-size: 22px; font-weight: 900; line-height: 1.2; letter-spacing: -0.4px; }
  .pv-sub { margin-top: 6px; font-size: 13px; line-height: 1.4; color: var(--app-text-sec); }
  .pv-benefit { display: grid; grid-template-columns: 40px minmax(0, 1fr); gap: 14px; margin: 0 20px 12px; }
  .pv-benefit .tile { width: 40px; height: 40px; display: grid; place-items: center; border-radius: 12px; background: rgba(228, 180, 95, 0.12); color: var(--app-gold); }
  .pv-benefit .tile .msr { font-size: 20px; }
  .pv-benefit b { display: block; font-size: 14.5px; font-weight: 800; }
  .pv-benefit span { display: block; margin-top: 2px; font-size: 12.5px; line-height: 1.35; color: var(--app-text-sec); }
  .pv-benefit.lead { outline: 1px dashed rgba(228, 180, 95, 0.45); outline-offset: 5px; border-radius: 10px; }
  .pv-palette { display: flex; gap: 4px; margin-top: 10px; }
  .pv-palette i { flex: 1 1 0; height: 16px; border-radius: 5px; }
  .pv-plan { display: flex; align-items: center; gap: 12px; margin: 10px 20px 0; padding: 16px 14px; border-radius: 16px; border: 0.5px solid var(--app-border); background: var(--app-surface); }
  .pv-plan.on { border: 1.6px solid var(--app-gold); background: rgba(228, 180, 95, 0.1); }
  .pv-plan .nm { flex: 1 1 auto; font-size: 12px; font-weight: 700; letter-spacing: 0.4px; color: var(--app-text-sec); }
  .pv-plan.on .nm { color: var(--app-gold); }
  .pv-plan .bd { margin-inline-start: 7px; padding: 3px 7px; border-radius: 100px; background: rgba(46, 207, 143, 0.15); color: var(--app-emerald); font-size: 9px; font-weight: 800; }
  .pv-plan .pr { text-align: end; }
  .pv-plan .pr b { display: block; font-size: 22px; font-weight: 900; letter-spacing: -0.8px; line-height: 1; direction: ltr; }
  .pv-plan .pr span { display: block; margin-top: 3px; font-size: 11px; color: var(--app-text-tert); }
  .pv-cta { display: grid; place-items: center; height: 54px; margin: 18px 20px 0; border-radius: 12px; background: var(--app-gold); color: #1a1408; font-weight: 800; font-size: 14px; }
  .pv-links { display: flex; justify-content: center; gap: 10px; margin: 12px 20px 0; font-size: 13px; color: var(--app-gold); }
  .pv-fine { margin: 8px 24px 0; font-size: 11px; line-height: 1.35; color: var(--app-text-tert); text-align: center; }
  .pv-legal { display: flex; justify-content: center; gap: 12px; margin: 10px 20px 28px; font-size: 11px; color: var(--app-text-sec); text-decoration: underline; }

  @media (max-width: 900px) {
    .g-head { grid-template-columns: auto minmax(0, 1fr); }
    .g-head > .g-title-en, .g-head > .g-side { grid-column: 2; }
    .q-line, .removed-row { grid-template-columns: minmax(0, 1fr); gap: 4px; }
    .q-edit, .b-fields { grid-template-columns: minmax(0, 1fr); }
    .s-row { grid-template-columns: minmax(0, 1fr); }
    .s-fixed { grid-column: 1; }
    .hrow { grid-template-columns: minmax(0, 1fr); gap: var(--s2); }
  }
`;

/** The fonts: Inter and JetBrains Mono as every page has, plus the Material
 *  Symbols set the app's icons come from, filled and rounded like them. */
const FONTS = `<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,400..600,0..1,0&display=block">`;

function page({ projectId, active, title, sub, intro, fine, appId, loadingText, script }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${FONTS}
<title>${title} · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${CONTENT_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active, projectId })}
  <div class="app-main">
    ${topBar({ title, sub, live: false })}
    <div class="app-content content-page">
      <p class="page-intro">${intro}
        <span class="fine">${fine}</span></p>
      <div id="banners"></div>
      <div id="${appId}"><div class="loading">${loadingText}</div></div>
      <div class="dock" id="dock" hidden></div>
    </div>
  </div>
</div>
  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/wording/rules.js"></script>
  <script src="/wording/content_rules.js"></script>
  <script src="/content/kit.js"></script>
  <script src="/content/${script}"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

// Which phones a save reaches. String edits are read by every build since
// 1.0.0 (76), the first built after the wording layer landed (622bd72); the
// two lists are read from the first build after 1.1.0 (80).
const LIST_BUILDS = 'the first app build after 1.1.0 (80)';

function renderFaqPage({ projectId = '' } = {}) {
  return page({
    projectId,
    active: 'faq',
    title: 'FAQ',
    sub: 'The questions in Help &amp; Support, in Arabic and English, live on every phone',
    intro: 'Edit a question or an answer, drag it into place, take it off or add your own, then Save: every open app shows the new FAQ within seconds, with no new build.',
    fine: 'Phones show these edits from ' + LIST_BUILDS + '; older builds keep the built-in FAQ until they update. Questions the app adds in a later build still show, right after the question they follow in the code.',
    appId: 'faqApp',
    loadingText: 'Loading the FAQ&hellip;',
    script: 'faq.js',
  });
}

function renderPremiumPage({ projectId = '' } = {}) {
  return page({
    projectId,
    active: 'premium',
    title: 'Premium',
    sub: 'Everything the Premium page says, and its list of what Premium includes, live on every phone',
    intro: 'Change the words, the benefit list (order, icons, your own rows) and every line around the plans, then Save: every open app shows it within seconds, with no new build. Prices always come from the App Store and Google Play.',
    fine: 'Every word here reaches phones on app build 76 and later; the list&rsquo;s order, icons and added rows need ' + LIST_BUILDS + '. The words are the same strings as on the Wording page, so an edit made in either place shows in both.',
    appId: 'premiumApp',
    loadingText: 'Loading the Premium page&hellip;',
    script: 'premium.js',
  });
}

module.exports = { renderFaqPage, renderPremiumPage, CONTENT_STYLES };
