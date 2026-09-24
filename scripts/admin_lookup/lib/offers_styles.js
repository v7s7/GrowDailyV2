'use strict';

/**
 * Styles the Sale and Creators pages share: cards, form fields, fact tiles,
 * tables, status chips, the meter and the toast. Colours come only from the
 * roles in lib/render.js (BASE_STYLES) and lib/shell.js (THEME_STYLES), so
 * both themes follow from the one switch in the top bar. The one exception
 * is the phone preview on the Sale page, which draws the app's own paywall
 * colours on purpose: it is a picture of the phone, in either theme.
 *
 * No backtick anywhere in here: this text is interpolated into a template
 * literal (see test/inline_script.test.js for the page that went blank).
 */

const OFFERS_STYLES = `
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
  }
  .offers-content { max-width: 1360px; }
  .intro { margin: 0 0 var(--s5); font-size: 13.5px; line-height: 1.55; color: var(--text-sec); max-width: 86ch; }
  .intro b { color: var(--text); font-weight: 600; }
  .loading { padding: 56px 0; text-align: center; color: var(--text-tert); }
  .page-body { display: flex; flex-direction: column; gap: 18px; }
  .ar { font-family: var(--arabic); unicode-bidi: isolate; }

  /* ---- Banners (errors that stop the page, set-up notes) ---------------- */
  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; line-height: 1.5; border: 1px solid; }
  .banner b { font-weight: 650; }
  .banner code { font-family: var(--mono); font-size: 11.5px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: 6px; padding: 1px 5px; user-select: all; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .banner.ok { background: var(--success-soft); border-color: var(--success-line); color: var(--success); }
  .banner svg { flex: 0 0 auto; margin-top: 2px; }
  .banner .grow { flex: 1 1 auto; min-width: 0; }

  /* ---- The status bar at the top of the Sale page ----------------------- */
  .status-bar { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; padding: 14px 18px; border-radius: var(--r-md); background: var(--surface); border: 1px solid var(--border); }
  .status-main { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .status-icon { width: 34px; height: 34px; flex: 0 0 auto; border-radius: 9px; display: grid; place-items: center; background: var(--surface-2); color: var(--text-sec); }
  .status-icon.on { background: var(--accent-soft); color: var(--accent); }
  .status-title { display: block; font-size: 14.5px; font-weight: 650; }
  .status-sub { display: block; font-size: 12.5px; color: var(--text-sec); margin-top: 2px; }

  /* ---- Status chips --------------------------------------------------- */
  .chip-status { display: inline-flex; align-items: center; gap: 6px; min-height: 28px; padding: 3px 12px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--surface-2); color: var(--text-sec); font-size: 12.5px; font-weight: 600; white-space: nowrap; }
  .chip-status.ok { background: var(--success-soft); border-color: var(--success-line); color: var(--success); }
  .chip-status.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .chip-status.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .chip-status.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .chip-status.small { min-height: 0; padding: 1px 8px; font-size: 11px; }

  /* ---- Columns and cards ---------------------------------------------- */
  .cols { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap: 18px; align-items: start; }
  /* The Add form keeps about the design's width; the nine-column table gets the rest. */
  .cols.wide-left { grid-template-columns: minmax(0, 1fr) minmax(330px, 370px); }
  .col { display: flex; flex-direction: column; gap: 18px; min-width: 0; }
  .card { margin: 0; display: flex; flex-direction: column; gap: 14px; padding: 18px; min-width: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md); }
  .card.flush { padding: 0; gap: 0; overflow: hidden; }
  .card h2 { margin: 0; padding: 0; border: 0; font-size: 15px; font-weight: 650; letter-spacing: -0.1px; }
  .card-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
  .card-head.bar { padding: 14px 16px; border-bottom: 1px solid var(--border); align-items: center; }
  .card-head .sub { font-size: 12px; color: var(--text-tert); }
  .card p.note, .note { margin: 0; font-size: 13px; line-height: 1.55; color: var(--text-sec); }
  .fine { font-size: 12px; line-height: 1.5; color: var(--text-tert); }
  .fine code, .note code { font-family: var(--mono); font-size: 11.5px; color: var(--text-sec); }

  /* ---- Form fields ---------------------------------------------------- */
  .fgrid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
  .fgrid.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .fld { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
  .fld.span2 { grid-column: span 2; }
  .fld > label, .fld > .label { font-size: 12px; font-weight: 600; color: var(--text-sec); }
  .fld .hint { font-size: 11.5px; line-height: 1.45; color: var(--text-tert); }
  .fld input, .fld select, .inline-input {
    width: 100%; min-width: 0; flex: none; height: 36px; padding: 0 10px;
    border: 1px solid var(--border-strong); border-radius: var(--r-sm);
    background: var(--bg); color: var(--text); font: inherit; font-size: 13.5px;
  }
  .fld input:focus, .fld select:focus, .inline-input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .fld input.ar { font-family: var(--arabic); font-size: 15px; }
  .fld input.mono { font-family: var(--mono); letter-spacing: 1px; }
  .fld input.bad, .inline-input.bad { border-color: var(--danger); }
  .pair { display: flex; gap: 8px; }
  .pair input[type="date"] { flex: 1 1 auto; }
  .pair input[type="time"] { width: 104px; flex: 0 0 auto; }
  input[type="date"], input[type="time"] { direction: ltr; }
  .switch { display: inline-flex; align-items: center; gap: 8px; min-height: 30px; padding: 0 12px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--surface-2); color: var(--text-sec); font-size: 12.5px; font-weight: 600; cursor: pointer; white-space: nowrap; }
  .switch.on { background: var(--success-soft); border-color: var(--success-line); color: var(--success); }
  .switch input { margin: 0; accent-color: var(--success); }

  /* ---- Fact tiles ----------------------------------------------------- */
  .facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
  .fact { display: flex; flex-direction: column; gap: 3px; padding: 10px 12px; border-radius: 10px; background: var(--bg); border: 1px solid var(--border); min-width: 0; }
  .fact .k { font-size: 11.5px; color: var(--text-tert); }
  .fact .v { font-size: 18px; font-weight: 650; font-variant-numeric: tabular-nums; }
  .fact .v.accent { color: var(--accent); }
  .fact .s { font-size: 11.5px; color: var(--text-tert); }

  /* ---- Buttons -------------------------------------------------------- */
  .btn-row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
  .btn:disabled, .btn[aria-disabled="true"] { opacity: 0.45; cursor: not-allowed; }
  .btn.big { min-height: 38px; padding: 0 16px; font-size: 13.5px; }
  .btn.danger-line { background: transparent; border-color: var(--danger-line); color: var(--danger); box-shadow: none; }
  .btn.danger-line:hover:not(:disabled) { background: var(--danger-soft); }
  .btn.small { padding: 4px 10px; font-size: 12px; font-weight: 600; white-space: nowrap; }
  .btn.ghost { background: transparent; box-shadow: none; }
  .link-btn { background: none; border: 0; padding: 0; color: var(--accent); font: inherit; font-size: 12px; cursor: pointer; text-decoration: underline; text-underline-offset: 2px; }
  .link-btn:hover { color: var(--accent-hover); }

  /* ---- The live rule check -------------------------------------------- */
  .checks { display: flex; flex-direction: column; gap: 6px; margin: 0; padding: 0; list-style: none; font-size: 12.5px; line-height: 1.5; }
  .checks li { display: flex; gap: 8px; align-items: flex-start; }
  .checks li svg { flex: 0 0 auto; margin-top: 2px; }
  .checks .bad { color: var(--danger); }
  .checks .good { color: var(--success); }
  .checks .wait { color: var(--text-tert); }

  /* ---- Tables --------------------------------------------------------- */
  .table-wrap { overflow-x: auto; }
  table.dtable { width: 100%; border-collapse: collapse; font-size: 13px; }
  .dtable th { padding: 10px 12px; text-align: start; font-size: 11.5px; font-weight: 650; color: var(--text-tert); border-bottom: 1px solid var(--border); white-space: nowrap; }
  .dtable td { padding: 12px; border-bottom: 1px solid var(--border-soft); vertical-align: top; }
  .dtable th:first-child, .dtable td:first-child { padding-inline-start: 16px; }
  .dtable th:last-child, .dtable td:last-child { padding-inline-end: 16px; }
  .dtable .num { text-align: end; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .dtable .muted-cell { color: var(--text-sec); }
  .dtable tfoot th, .dtable tfoot td { border-bottom: 0; border-top: 1px solid var(--border); font-weight: 650; }
  .dtable tr.inactive td { opacity: 0.6; }
  .dtable .stack { display: flex; flex-direction: column; gap: 3px; }
  .dtable .sub { font-size: 12px; color: var(--text-tert); }
  .dtable .sub.bad { color: var(--danger); }
  .dtable .sub.warn { color: var(--warn); }
  .dtable code.code { font-family: var(--mono); font-size: 12px; color: var(--accent); }
  .dtable .owed { font-weight: 650; color: var(--success); }
  .dtable .actions { text-align: end; white-space: nowrap; }
  .empty-row td { text-align: center; color: var(--text-tert); padding: 22px 12px; }
  .nowrap { white-space: nowrap; }
  /* The creators table carries nine columns in the left column, as in the
     design, so its cells are tighter than the Past sales table's. */
  .dtable.tight th, .dtable.tight td { padding: 10px 7px; }
  .dtable.tight th:first-child, .dtable.tight td:first-child { padding-inline-start: 14px; }
  .dtable.tight th:last-child, .dtable.tight td:last-child { padding-inline-end: 14px; }
  .act { display: inline-flex; gap: 4px; align-items: center; }
  .more-btn { min-width: 28px; justify-content: center; padding-inline: 6px; font-size: 14px; line-height: 1; }
  .more-btn[aria-expanded="true"] { background: var(--surface-2); border-color: var(--border-strong); }
  .more-row td { background: var(--bg-sunken); }
  .more-row td > * + * { margin-top: 10px; }
  .mini-facts { display: grid; grid-template-columns: max-content 1fr; gap: 4px 14px; margin: 0; font-size: 12.5px; }
  .mini-facts dt { color: var(--text-tert); }
  .mini-facts dd { margin: 0; color: var(--text); min-width: 0; overflow-wrap: anywhere; }
  .row-form { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; padding: 10px 0 2px; }
  .row-form .inline-input { width: 110px; height: 30px; font-size: 12.5px; }
  .row-form .inline-input.note-input { width: 200px; }
  .row-form .msg { flex-basis: 100%; font-size: 12px; color: var(--danger); }
  .row-form .msg.plain { color: var(--text-tert); }

  /* ---- Tiles (Creators) ----------------------------------------------- */
  .tiles { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; }
  .tile { display: flex; flex-direction: column; gap: 6px; padding: 16px 18px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md); min-width: 0; }
  .tile .k { font-size: 12px; font-weight: 600; color: var(--text-tert); }
  .tile .v { font-size: 26px; font-weight: 650; letter-spacing: -0.4px; font-variant-numeric: tabular-nums; }
  .tile .v .of { font-size: 15px; font-weight: 500; color: var(--text-tert); }
  .tile .v.good { color: var(--success); }
  .tile .s { font-size: 12px; color: var(--text-sec); }
  .bar-mini { height: 6px; border-radius: var(--r-pill); background: var(--border-soft); overflow: hidden; }
  .bar-mini > i { display: block; height: 100%; background: var(--accent); }

  /* ---- The "Who pays full price" meter -------------------------------- */
  .meter-big { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
  .meter-big b { font-size: 26px; font-weight: 650; color: var(--success); font-variant-numeric: tabular-nums; }
  .meter-big span { font-size: 13px; color: var(--text-sec); }
  .meter-bar { display: flex; height: 10px; border-radius: var(--r-pill); overflow: hidden; background: var(--border-soft); }
  .meter-bar > i { display: block; height: 100%; }
  .meter-legend { display: flex; flex-wrap: wrap; gap: 6px 16px; margin: 0; padding: 0; list-style: none; font-size: 12px; color: var(--text-sec); }
  .meter-legend li { display: inline-flex; align-items: center; gap: 6px; }
  .meter-legend .sw { width: 10px; height: 10px; border-radius: 3px; flex: 0 0 auto; }
  .meter-legend b { color: var(--text); font-variant-numeric: tabular-nums; }
  .c-full { background: var(--success); }
  .c-welcome { background: var(--accent); }
  .c-sale { background: var(--info); }
  .c-code { background: var(--undo); }

  /* ---- "Rules this page keeps" ------------------------------------------ */
  .rules { display: flex; flex-direction: column; gap: 10px; margin: 0; padding: 0; list-style: none; }
  .rules li { display: flex; gap: 10px; align-items: flex-start; font-size: 13px; line-height: 1.55; color: var(--text-sec); }
  .rules li svg { flex: 0 0 auto; margin-top: 3px; color: var(--success); }

  /* ---- The Apple preview (Creators) ------------------------------------ */
  .money { display: flex; flex-direction: column; gap: 9px; padding: 14px; border-radius: 10px; background: var(--bg); border: 1px solid var(--border); font-variant-numeric: tabular-nums; }
  .money .head { font-size: 12px; font-weight: 650; color: var(--text-tert); }
  .money .line { display: flex; justify-content: space-between; gap: 12px; }
  .money .line span:first-child { color: var(--text-sec); }
  .money .line b { font-weight: 650; }
  .money .line b.accent { color: var(--accent); }
  .money .total { padding-top: 9px; border-top: 1px solid var(--border); align-items: baseline; }
  .money .total span:first-child { color: var(--text); font-weight: 650; }
  .money .total b { font-size: 18px; color: var(--success); }
  .linkbox { display: flex; align-items: center; gap: 8px; height: 36px; padding: 0 4px 0 10px; border-radius: var(--r-sm); border: 1px solid var(--border); background: var(--bg-sunken); min-width: 0; }
  .linkbox code { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: var(--mono); font-size: 11.5px; color: var(--text-sec); }
  .icon-btn { width: 28px; height: 28px; flex: 0 0 auto; display: grid; place-items: center; border-radius: 6px; border: 1px solid var(--border); background: var(--surface); color: var(--text-sec); cursor: pointer; }
  .icon-btn:hover { color: var(--text); border-color: var(--border-strong); }
  .preview { display: flex; flex-direction: column; gap: 12px; padding: 14px; border-radius: 10px; border: 1px solid var(--accent-line); background: var(--accent-soft); }
  .preview h3 { margin: 0; padding: 0; border: 0; font-size: 13.5px; font-weight: 650; color: var(--text); text-transform: none; letter-spacing: 0; }
  .preview dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 14px; margin: 0; font-size: 12.5px; }
  .preview dt { color: var(--text-tert); }
  .preview dd { margin: 0; color: var(--text); min-width: 0; overflow-wrap: anywhere; }
  .preview details { font-size: 12px; }
  .preview summary { cursor: pointer; color: var(--text-sec); font-weight: 600; }
  .preview pre { margin: 8px 0 0; max-height: 280px; overflow: auto; padding: 10px; border-radius: 8px; background: var(--bg-sunken); border: 1px solid var(--border); font-family: var(--mono); font-size: 11px; line-height: 1.5; color: var(--text-sec); white-space: pre; }
  .preview .blocked { color: var(--danger); font-size: 12.5px; line-height: 1.5; }
  .result { font-size: 12.5px; line-height: 1.5; padding: 10px 12px; border-radius: 8px; border: 1px solid; }
  .result.ok { color: var(--success); background: var(--success-soft); border-color: var(--success-line); }
  .result.bad { color: var(--danger); background: var(--danger-soft); border-color: var(--danger-line); }

  /* ---- The phone preview (Sale): the app's own paywall colours --------- */
  .phone { direction: rtl; display: flex; flex-direction: column; gap: 10px; padding: 16px; border-radius: 14px; background: #07100d; border: 1px solid #22352d; color: #f7f3e8; font-family: var(--arabic); }
  .phone .banner-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 12px; border-radius: 12px; background: rgba(228, 180, 95, 0.10); border: 1px solid rgba(228, 180, 95, 0.45); }
  .phone .sale-name { display: block; font-size: 13px; font-weight: 700; color: #e4b45f; }
  .phone .ends-in { display: block; font-size: 11px; color: #b5bca8; }
  .phone .clock { display: flex; gap: 5px; }
  .phone .unit { width: 40px; padding: 5px 0 4px; border-radius: 9px; background: #17251f; border: 1px solid #2d4037; display: flex; flex-direction: column; align-items: center; }
  .phone .unit b { font-size: 15px; font-weight: 700; line-height: 1.15; }
  .phone .unit span { font-size: 9.5px; color: #b5bca8; }
  .phone .plan { display: flex; align-items: center; gap: 10px; padding: 14px 12px; border-radius: 14px; background: rgba(228, 180, 95, 0.10); border: 1.6px solid #e4b45f; }
  .phone .plan-main { flex: 1 1 auto; display: flex; flex-direction: column; gap: 4px; }
  .phone .plan-title { display: flex; align-items: center; gap: 6px; font-size: 11.5px; font-weight: 700; color: #e4b45f; }
  .phone .off { direction: ltr; padding: 2px 6px; border-radius: var(--r-pill); background: #e4b45f; color: #07100d; font-size: 9px; font-weight: 700; }
  .phone .prices { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; }
  .phone .was { direction: ltr; font-size: 11.5px; color: #b5bca8; text-decoration: line-through; }
  .phone .now { direction: ltr; font-size: 20px; font-weight: 700; line-height: 1; }
  .phone .under { margin: 0; font-size: 11px; line-height: 1.55; text-align: center; color: #b5bca8; }
  .phone [dir="ltr"] { unicode-bidi: isolate; }

  /* ---- Toast ---------------------------------------------------------- */
  .toast { position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; padding: 10px 16px; border-radius: var(--r-pill); background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 60; transition: opacity 0.16s ease, transform 0.16s ease; max-width: min(640px, 92vw); }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  @media (max-width: 1180px) {
    .cols, .cols.wide-left { grid-template-columns: minmax(0, 1fr); }
    .tiles { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  }
  @media (max-width: 640px) {
    .fgrid, .fgrid.three, .facts { grid-template-columns: minmax(0, 1fr); }
    .fld.span2 { grid-column: auto; }
    .tiles { grid-template-columns: minmax(0, 1fr); }
  }
`;

module.exports = { OFFERS_STYLES };
