'use strict';

/**
 * Styles the Sale and Creators pages share, the simple layout Aziz approved
 * on 2026-09-27 (canvas "Admin Sale and Creators, simple"): what is
 * happening now at the top, one main button per page, every other action
 * a short dialog, and no paragraphs of rules. The rules still run; a page
 * shows one only when something breaks it.
 *
 * Colours come only from the roles in lib/render.js (BASE_STYLES) and
 * lib/shell.js (THEME_STYLES), so both themes follow from the one switch in
 * the top bar. The one exception is the phone preview on the Sale page,
 * which draws the app's own paywall colours on purpose: it is a picture of
 * the phone, in either theme.
 *
 * No backtick anywhere in here: this text is interpolated into a template
 * literal (see test/inline_script.test.js for the page that went blank).
 */

const OFFERS_STYLES = `
  :root { --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif; }
  .simple { max-width: 1040px; display: flex; flex-direction: column; gap: 16px; font-size: 14px; }
  .simple h2, dialog.dlg h2 { margin: 0; padding: 0; border: 0; font-size: 16px; font-weight: 700; letter-spacing: -0.005em; }
  .ar { font-family: var(--arabic); unicode-bidi: isolate; }
  .simple .muted, dialog.dlg .muted { color: var(--text-sec); font-style: normal; }
  .faint { color: var(--text-tert); }
  .small { font-size: 12.5px; }
  .grow { flex: 1 1 auto; min-width: 0; }
  .nowrap { white-space: nowrap; }
  .loading { padding: 48px 0; text-align: center; color: var(--text-tert); }
  [hidden] { display: none !important; }

  /* ---- Buttons ------------------------------------------------------------- */
  .btn.lg { min-height: 42px; padding: 10px 18px; font-size: 14px; font-weight: 650; border-radius: 10px; }
  .btn.sm { min-height: 34px; padding: 6px 12px; font-size: 13px; font-weight: 600; border-radius: 9px; }
  .btn.ghost { background: transparent; }
  .btn.danger { color: var(--danger); border-color: var(--danger-line); background: transparent; }
  .btn.danger:hover { background: var(--danger-soft); border-color: var(--danger); }
  .btn.danger.solid { background: var(--danger); border-color: var(--danger); color: #1a0806; }
  .btn:disabled, .btn[disabled] { opacity: 0.45; cursor: default; }
  .btn svg { flex: 0 0 auto; }
  .icon-btn { width: 36px; height: 36px; display: inline-grid; place-items: center; border-radius: 9px; border: 1px solid var(--border); background: var(--surface-2); color: var(--text-sec); cursor: pointer; flex: 0 0 auto; }
  .icon-btn:hover { color: var(--text); border-color: var(--border-strong); }
  .link-btn { background: none; border: 0; padding: 0; font: inherit; font-weight: 650; color: var(--accent); cursor: pointer; }
  .link-btn:hover { color: var(--accent-hover); text-decoration: underline; }

  /* ---- Panels ---------------------------------------------------------------- */
  .panel { background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 20px 24px; }
  .panel.flush { padding: 0; overflow: hidden; }
  .panel-head { display: flex; align-items: center; gap: 12px; padding: 16px 20px; border-bottom: 1px solid var(--border-soft); }
  .row { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
  .ctl { display: flex; align-items: center; gap: 10px; flex: 0 0 auto; }
  .eyebrow { font-size: 12px; font-weight: 700; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.06em; }
  .simple .now-title { margin: 4px 0 2px; font-size: 22px; font-weight: 700; letter-spacing: -0.01em; }
  .now-foot { margin-top: 14px; padding-top: 14px; border-top: 1px solid var(--border-soft); display: flex; align-items: center; gap: 10px; flex-wrap: wrap; font-size: 13.5px; }

  /* ---- The one-line notices (only when something needs doing) --------------- */
  .notice { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-radius: 12px; border: 1px solid; font-size: 14px; line-height: 1.45; }
  .notice svg { flex: 0 0 auto; }
  .notice.warn { background: var(--warn-soft); border-color: var(--warn-line); color: var(--text); }
  .notice.warn svg { color: var(--warn); }
  .notice.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--text); }
  .notice.danger svg { color: var(--danger); }
  .notice.info { background: var(--info-soft); border-color: var(--info-line); color: var(--text); }
  .notice.info svg { color: var(--info); }
  .notice code { font-family: var(--mono); font-size: 12px; background: var(--surface); border: 1px solid var(--border-soft); border-radius: 6px; padding: 1px 5px; user-select: all; }

  /* ---- Fields ------------------------------------------------------------------ */
  .fld { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
  .fld > label, .fld > .label { font-size: 13px; font-weight: 600; color: var(--text-sec); }
  .simple .in, dialog.dlg .in { flex: none; min-width: 0; width: 100%; box-sizing: border-box; background: var(--bg); color: var(--text); border: 1px solid var(--border-strong); border-radius: 10px; padding: 10px 12px; font-size: 14.5px; font-family: inherit; min-height: 42px; }
  .simple .in:focus, dialog.dlg .in:focus { box-shadow: none; outline: 2px solid var(--accent-line); outline-offset: 1px; border-color: var(--accent); }
  dialog.dlg .in.bad { border-color: var(--danger); }
  dialog.dlg .in.mono { font-family: var(--mono); text-transform: uppercase; letter-spacing: 0.04em; }
  dialog.dlg .in.num { width: 96px; font-weight: 650; font-size: 16px; }
  .pair { display: flex; gap: 8px; }
  dialog.dlg .pair .in { width: auto; flex: 1 1 0; min-width: 0; }
  dialog.dlg .pair .in[type="time"] { flex: 0 0 104px; }
  .unit-row { display: flex; align-items: center; gap: 10px; }
  .hint { font-size: 12.5px; color: var(--text-tert); }
  .grid2 { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px 16px; }
  .more { border: 1px dashed var(--border-strong); border-radius: 12px; padding: 10px 14px; }
  .more summary { cursor: pointer; font-size: 13.5px; font-weight: 600; color: var(--text-sec); }
  .more[open] summary { margin-bottom: 12px; }

  /* ---- The on/off switch ----------------------------------------------------------- */
  .sw { position: relative; width: 52px; height: 30px; border-radius: 999px; border: 1px solid var(--border-strong); background: var(--surface-2); cursor: pointer; flex: 0 0 auto; padding: 0; }
  .sw::after { content: ''; position: absolute; top: 3px; inset-inline-start: 3px; width: 22px; height: 22px; border-radius: 50%; background: var(--text-tert); transition: inset-inline-start 0.15s ease, background-color 0.15s ease; }
  .sw[aria-checked="true"] { background: var(--accent-soft); border-color: var(--accent); }
  .sw[aria-checked="true"]::after { inset-inline-start: 25px; background: var(--accent); }
  .sw:disabled { opacity: 0.45; cursor: default; }
  .sw-label { width: 28px; font-weight: 650; color: var(--text-sec); }

  /* ---- Tiles --------------------------------------------------------------------------- */
  .tiles3 { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
  .tile { background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 16px 20px; display: flex; flex-direction: column; gap: 4px; }
  .tile .k { font-size: 13px; font-weight: 600; color: var(--text-sec); }
  .tile .v { font-size: 28px; font-weight: 700; letter-spacing: -0.01em; }
  .tile .v.good { color: var(--success); }
  .tile .of { font-size: 15px; font-weight: 600; color: var(--text-tert); }
  .tile .s { font-size: 12.5px; color: var(--text-tert); }

  /* ---- Tables ---------------------------------------------------------------------------- */
  .t { width: 100%; border-collapse: collapse; font-size: 14px; }
  .t th { text-align: start; font-size: 12px; font-weight: 700; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.05em; padding: 12px 20px; border-bottom: 1px solid var(--border-soft); white-space: nowrap; }
  .t td { padding: 14px 20px; border-bottom: 1px solid var(--border-soft); vertical-align: middle; }
  .t tbody tr:last-child td { border-bottom: 0; }
  .t .num { text-align: end; font-variant-numeric: tabular-nums; }
  .t .owed { color: var(--success); font-weight: 650; }
  .t .empty td { color: var(--text-tert); padding: 22px 20px; }
  .t tr.off td { color: var(--text-tert); }
  .t .stack { display: flex; flex-direction: column; gap: 2px; }
  .t .stack > .ar { align-self: flex-start; }
  .t .acts { display: flex; gap: 8px; justify-content: flex-end; }
  .code-chip { font-family: var(--mono); font-size: 12px; color: var(--accent); background: var(--accent-soft); border: 1px solid var(--accent-line); border-radius: 6px; padding: 1px 7px; }

  /* ---- Status chips ------------------------------------------------------------------------ */
  .chip { display: inline-flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 650; padding: 2px 9px; border-radius: 999px; border: 1px solid var(--border); color: var(--text-sec); background: var(--surface-2); white-space: nowrap; }
  .chip.ok { color: var(--success); border-color: var(--success-line); background: var(--success-soft); }
  .chip.warn { color: var(--warn); border-color: var(--warn-line); background: var(--warn-soft); }
  .chip.info { color: var(--info); border-color: var(--info-line); background: var(--info-soft); }
  .chip.bad { color: var(--danger); border-color: var(--danger-line); background: var(--danger-soft); }

  /* ---- Check lines (the rules, only as they apply) ------------------------------------------- */
  .checks { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; }
  .checks li { display: flex; gap: 10px; align-items: flex-start; font-size: 14px; line-height: 1.45; }
  .checks li .mk { flex: 0 0 auto; width: 18px; font-weight: 800; text-align: center; }
  .checks li.good .mk { color: var(--success); }
  .checks li.bad { color: var(--danger); }
  .checks li.warn .mk { color: var(--warn); }

  /* ---- Dialogs ----------------------------------------------------------------------------------- */
  dialog.dlg { width: min(680px, calc(100vw - 32px)); max-height: calc(100vh - 48px); box-sizing: border-box; padding: 0; border: 1px solid var(--border-strong); border-radius: 18px; background: var(--surface); color: var(--text); box-shadow: var(--shadow-lg); }
  dialog.dlg.narrow { width: min(460px, calc(100vw - 32px)); }
  dialog.dlg::backdrop { background: rgba(0, 0, 0, 0.55); }
  .dlg-body { padding: 26px 28px; display: flex; flex-direction: column; gap: 18px; }
  .dlg-head { display: flex; align-items: center; gap: 12px; }
  dialog.dlg .dlg-head h2 { flex: 1 1 auto; margin: 0; font-size: 21px; font-weight: 700; }
  .dlg-foot { display: flex; align-items: center; gap: 10px; justify-content: flex-end; padding-top: 16px; border-top: 1px solid var(--border-soft); flex-wrap: wrap; }
  .dlg-foot .spacer { flex: 1 1 auto; }
  .dlg p { margin: 0; line-height: 1.5; }
  .facts { display: grid; grid-template-columns: max-content 1fr; gap: 8px 18px; margin: 0; font-size: 14px; }
  .facts dt { color: var(--text-sec); }
  .facts dd { margin: 0; min-width: 0; overflow-wrap: anywhere; }

  /* ---- Add creator steps ------------------------------------------------------------------------ */
  .steps { list-style: none; margin: 0; padding: 0; display: flex; gap: 8px; }
  .steps li { flex: 1; display: flex; align-items: center; gap: 8px; font-size: 13.5px; font-weight: 600; color: var(--text-tert); padding: 9px 12px; border-radius: 10px; border: 1px dashed var(--border-strong); }
  .steps li .n { width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center; font-size: 12px; font-weight: 700; background: var(--surface-2); color: var(--text-sec); flex: 0 0 auto; }
  .steps li.done { color: var(--text-sec); border: 1px solid var(--border); background: var(--surface-2); }
  .steps li.done .n { background: var(--success); color: var(--heat-ink, #07100b); }
  .steps li.now { color: var(--text); border: 1px solid var(--accent-line); background: var(--accent-soft); font-weight: 700; }
  .steps li.now .n { background: var(--accent); color: var(--accent-ink); }
  .money4 { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; background: var(--bg); border: 1px solid var(--border); border-radius: 14px; padding: 14px 16px; }
  .money4 .k { display: block; font-size: 12.5px; color: var(--text-sec); }
  .money4 .v { display: block; font-size: 19px; font-weight: 700; margin-top: 2px; font-variant-numeric: tabular-nums; }
  .money4 .v.accent { color: var(--accent); }
  .money4 .v.good { color: var(--success); }
  .done-head { display: flex; align-items: center; gap: 14px; }
  .done-mark { width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; background: var(--success-soft); border: 1px solid var(--success-line); color: var(--success); flex: 0 0 auto; }
  .preview-lines { display: flex; flex-direction: column; gap: 10px; }
  .preview-lines details { font-size: 13px; }
  .preview-lines summary { cursor: pointer; color: var(--text-sec); }
  .preview-lines pre { font-family: var(--mono); font-size: 11.5px; background: var(--bg); border: 1px solid var(--border-soft); border-radius: 10px; padding: 10px; overflow: auto; max-height: 220px; }

  /* ---- Link boxes ---------------------------------------------------------------------------- */
  .linkbox { display: flex; align-items: center; gap: 10px; background: var(--bg); border: 1px solid var(--border); border-radius: 12px; padding: 8px 8px 8px 14px; }
  .linkbox code { flex: 1 1 auto; min-width: 0; font-family: var(--mono); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* ---- The row menu ---------------------------------------------------------------------------- */
  .menu { position: absolute; z-index: 40; min-width: 230px; background: var(--surface-2); border: 1px solid var(--border-strong); border-radius: 12px; box-shadow: var(--shadow-md); padding: 6px; display: flex; flex-direction: column; }
  .menu button { text-align: start; background: none; border: 0; border-radius: 8px; padding: 10px 12px; font: inherit; font-size: 14px; color: var(--text); cursor: pointer; }
  .menu button:hover, .menu button:focus-visible { background: var(--surface); outline: none; }
  .menu button.danger { color: var(--danger); }
  .menu hr { border: 0; border-top: 1px solid var(--border); margin: 4px 0; }

  /* ---- How it works (in a dialog) --------------------------------------------------------------- */
  .how { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 12px; counter-reset: how; }
  .how li { display: flex; gap: 12px; align-items: flex-start; counter-increment: how; }
  .how li::before { content: counter(how); flex: 0 0 auto; width: 26px; height: 26px; border-radius: 50%; display: grid; place-items: center; font-size: 13px; font-weight: 700; background: var(--accent-soft); border: 1px solid var(--accent-line); color: var(--accent); }
  .how li b { display: block; font-weight: 650; }
  .how li span { color: var(--text-sec); font-size: 13.5px; }
  .how-group { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-tert); }

  /* ---- The phone preview (the app's own colours, in either theme) ---------------------------------- */
  .phone { width: 230px; flex: 0 0 auto; box-sizing: border-box; background: #0f1512; color: #eef3ef; border: 1px solid #26332c; border-radius: 16px; padding: 14px; display: flex; flex-direction: column; gap: 8px; direction: rtl; font-family: var(--arabic); }
  .phone .p-name { font-size: 13.5px; font-weight: 700; color: #e0b764; }
  .phone .p-ends { font-size: 12px; color: #a9b8af; }
  .phone .p-price { display: flex; align-items: baseline; gap: 8px; }
  .phone .p-now { font-size: 21px; font-weight: 700; direction: ltr; }
  .phone .p-was { font-size: 13px; color: #7f9187; text-decoration: line-through; direction: ltr; }
  .phone .p-off { font-size: 12px; font-weight: 700; color: #3fcf8e; direction: ltr; }
  .phone-cap { font-size: 12px; color: var(--text-tert); text-align: center; }
  .sale-mid { display: flex; gap: 22px; align-items: flex-start; }

  /* ---- The toast ------------------------------------------------------------------------------------- */
  .toast { position: fixed; left: 50%; bottom: 28px; transform: translate(-50%, 20px); opacity: 0; pointer-events: none; background: var(--text); color: var(--bg); font-size: 14px; font-weight: 600; padding: 11px 18px; border-radius: 12px; box-shadow: var(--shadow-md); transition: opacity 0.18s ease, transform 0.18s ease; z-index: 60; max-width: min(640px, calc(100vw - 32px)); }
  .toast.show { opacity: 1; transform: translate(-50%, 0); }

  @media (max-width: 760px) {
    .tiles3 { grid-template-columns: 1fr; }
    .grid2 { grid-template-columns: 1fr; }
    .money4 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .sale-mid { flex-direction: column; }
    .phone { width: 100%; }
    .t th:nth-child(4), .t td:nth-child(4), .t th:nth-child(6), .t td:nth-child(6) { display: none; }
  }
`;

module.exports = { OFFERS_STYLES };
