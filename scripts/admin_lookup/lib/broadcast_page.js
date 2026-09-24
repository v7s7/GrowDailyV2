'use strict';

/**
 * The Messages page's HTML and styles. The behaviour is in
 * ../broadcast/app.js, a plain file rather than a template literal, for the
 * reason wording_page.js gives (a backtick or backslash inside an inline
 * script has twice shipped a page that silently did nothing).
 *
 * One column to write in, one to check against: the left is the message
 * itself, the right is a phone showing exactly what arrives (the app's own
 * pop-up, or a lock-screen notification) with who it reaches and what it
 * costs underneath. What is showing now and what was sent before sit below
 * both.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, icon, sidebar, topBar } = require('./shell');

const PAGE_ICONS = [
  'app-window', 'bell', 'send', 'flask-conical', 'megaphone', 'circle-stop',
  'smartphone', 'clock', 'info', 'x', 'triangle-alert', 'history', 'users', 'moon-star',
];

const PAGE_STYLES = `
  :root {
    --arabic: 'SF Arabic', 'Geeza Pro', 'Noto Naskh Arabic', 'Segoe UI', Tahoma, sans-serif;
    /* The phone in the preview is always the app's own dark screen, in both
       themes of this tool: it is a picture of the app, not part of the page. */
    --ph-bg: #0b120f; --ph-card: #17211c; --ph-text: #e8efea; --ph-sec: #a7b6ad;
    --ph-gold: #d9aa55; --ph-gold-ink: #1a1408; --ph-sq: #1f5c42; --ph-sq-2: #2c8a60;
  }
  .msg-content { max-width: 1320px; }
  .msg-intro { margin: 0 0 var(--s5); font-size: 13px; color: var(--text-sec); max-width: 86ch; line-height: 1.55; }
  #viewMessages { display: block; }

  .msg-grid { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(320px, 0.9fr); gap: var(--s5); align-items: start; }
  .side-col { display: flex; flex-direction: column; gap: var(--s5); }
  .panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: var(--s5); box-shadow: var(--shadow-sm); }
  .panel h2 { font-size: 13px; font-weight: 700; margin: 0 0 var(--s4); letter-spacing: -0.1px; display: flex; align-items: center; gap: var(--s2); }
  .panel h2 svg { color: var(--text-tert); }
  .below { margin-top: var(--s5); display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr); gap: var(--s5); align-items: start; }

  /* ---- How it arrives: two cards, one choice ---- */
  .kind-choice { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s3); margin-bottom: var(--s5); }
  .kind-card { display: flex; gap: var(--s3); align-items: flex-start; text-align: start; padding: var(--s4); border: 1px solid var(--border); border-radius: var(--r-md); background: var(--bg-sunken); color: var(--text-sec); font: inherit; cursor: pointer; }
  .kind-card:hover { border-color: var(--border-strong); color: var(--text); }
  .kind-card .ic { flex: 0 0 auto; display: grid; place-items: center; width: 34px; height: 34px; border-radius: 10px; background: var(--surface-2); color: var(--text-sec); }
  .kind-card b { display: block; font-size: 13.5px; color: var(--text); margin-bottom: 2px; }
  .kind-card span.d { display: block; font-size: 12px; line-height: 1.45; }
  .kind-card[aria-checked="true"] { border-color: var(--accent); background: var(--accent-soft); box-shadow: 0 0 0 1px var(--accent) inset; }
  .kind-card[aria-checked="true"] .ic { background: var(--accent); color: var(--accent-ink); }
  .kind-card:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

  /* ---- The words ---- */
  .lang-block { border: 1px solid var(--border-soft); border-radius: var(--r-md); padding: var(--s4); margin: 0 0 var(--s4); }
  .lang-block legend { padding: 0 var(--s2); font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-sec); }
  .lang-block legend .opt { text-transform: none; letter-spacing: 0; font-weight: 500; color: var(--text-tert); margin-inline-start: var(--s2); }
  .field { display: block; margin-bottom: var(--s3); }
  .field:last-child { margin-bottom: 0; }
  .field-top { display: flex; justify-content: space-between; align-items: baseline; font-size: 11.5px; color: var(--text-tert); margin-bottom: 4px; }
  .field-top .char-count { font-variant-numeric: tabular-nums; }
  .field-top .char-count.over { color: var(--danger); font-weight: 650; }
  .field input, .field textarea, .field select {
    width: 100%; padding: 9px var(--s3); border: 1px solid var(--border); border-radius: var(--r-md);
    background: var(--bg); color: var(--text); font: inherit; font-size: 13.5px;
  }
  .field textarea { resize: vertical; min-height: 84px; line-height: 1.55; }
  .field input:focus, .field textarea:focus, .field select:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
  .field .rtl { font-family: var(--arabic); font-size: 15.5px; direction: rtl; text-align: right; }
  .field.bad input, .field.bad textarea { border-color: var(--danger); }
  .two { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s3); }
  .popup-only[hidden] { display: none !important; }
  .days-row { display: flex; gap: var(--s4); align-items: center; flex-wrap: wrap; margin-bottom: var(--s4); }
  .days-row .field { margin: 0; width: 180px; }
  .days-row .hint { font-size: 12px; color: var(--text-tert); max-width: 38ch; }

  .checks { display: flex; flex-direction: column; gap: 4px; margin: 0 0 var(--s4); font-size: 12px; }
  .checks:empty { display: none; }
  .checks .err { color: var(--danger); }
  .checks .wrn { color: var(--warn); }

  /* ---- Test accounts ---- */
  .testers { border-top: 1px solid var(--border-soft); padding-top: var(--s4); margin-top: var(--s2); }
  .testers-head { font-size: 12.5px; font-weight: 650; margin-bottom: var(--s2); }
  .testers-head span { font-weight: 450; color: var(--text-tert); margin-inline-start: var(--s2); }
  .tester-chips { display: flex; flex-wrap: wrap; gap: var(--s2); margin-bottom: var(--s2); }
  .tester-chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 6px 4px 10px; border: 1px solid var(--border); border-radius: var(--r-pill); background: var(--bg-sunken); font-size: 12px; }
  .tester-chip .nm { unicode-bidi: plaintext; max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tester-chip .ph { color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .tester-chip .ph.none { color: var(--warn); }
  .tester-chip button { display: inline-grid; place-items: center; width: 20px; height: 20px; border: 0; border-radius: 50%; background: none; color: var(--text-tert); cursor: pointer; }
  .tester-chip button:hover { background: var(--surface-2); color: var(--text); }
  .tester-add { position: relative; max-width: 360px; }
  .tester-add input { width: 100%; }
  .dropdown { position: absolute; inset-inline: 0; top: calc(100% + 4px); z-index: 30; background: var(--surface); border: 1px solid var(--border-strong); border-radius: var(--r-md); box-shadow: var(--shadow-lg); max-height: 260px; overflow-y: auto; padding: 4px; }
  .dropdown[hidden] { display: none; }
  .dd-item { display: block; width: 100%; text-align: start; padding: 7px 9px; border: 0; border-radius: var(--r-sm); background: none; color: var(--text); font: inherit; cursor: pointer; }
  .dd-item:hover, .dd-item.sel { background: var(--accent-soft); }
  .dd-item .nm { display: block; font-size: 13px; font-weight: 600; unicode-bidi: plaintext; }
  .dd-item .ml { display: block; font-size: 11.5px; color: var(--text-tert); }
  .dd-empty { padding: 10px; font-size: 12.5px; color: var(--text-tert); }

  .actions { display: flex; gap: var(--s3); justify-content: flex-end; align-items: center; margin-top: var(--s5); flex-wrap: wrap; }
  .actions .why { margin-inline-end: auto; font-size: 12px; color: var(--text-tert); }
  .btn[disabled] { opacity: 0.5; cursor: not-allowed; box-shadow: none; }
  .btn.danger { color: var(--danger); border-color: var(--danger-line); background: var(--danger-soft); }
  .btn.danger:hover { border-color: var(--danger); }
  .btn svg { flex: 0 0 auto; }

  /* ---- Preview: a phone ---- */
  .preview-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--s4); }
  .preview-head h2 { margin: 0; }
  .seg { display: inline-flex; padding: 2px; border: 1px solid var(--border); border-radius: var(--r-pill); background: var(--bg-sunken); }
  .seg button { border: 0; background: none; padding: 4px 12px; border-radius: var(--r-pill); font: inherit; font-size: 12px; color: var(--text-sec); cursor: pointer; }
  .seg button[aria-pressed="true"] { background: var(--surface-2); color: var(--text); box-shadow: var(--shadow-sm); }
  .phone { position: relative; margin: 0 auto; width: 272px; height: 540px; border-radius: 42px; padding: 11px; background: #050807; box-shadow: 0 0 0 1px var(--border-strong), var(--shadow-md); }
  .screen { position: relative; width: 100%; height: 100%; border-radius: 32px; overflow: hidden; background: var(--ph-bg); color: var(--ph-text); }
  .notch { position: absolute; top: 9px; left: 50%; transform: translateX(-50%); width: 84px; height: 24px; border-radius: 14px; background: #000; z-index: 3; }

  /* The app behind the pop-up: a dimmed board of squares. */
  .ph-app { position: absolute; inset: 0; padding: 54px 18px 18px; display: grid; grid-template-columns: repeat(7, 1fr); gap: 7px; align-content: start; opacity: 0.5; }
  .ph-app i { display: block; aspect-ratio: 1; border-radius: 6px; background: var(--ph-card); }
  .ph-app i.g { background: var(--ph-sq); }
  .ph-app i.g2 { background: var(--ph-sq-2); }
  .ph-scrim { position: absolute; inset: 0; background: rgba(0, 0, 0, 0.55); }
  .ph-dialog { position: absolute; left: 18px; right: 18px; top: 50%; transform: translateY(-50%); max-height: 78%; overflow: hidden; display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 22px 18px 16px; border-radius: 26px; background: var(--ph-card); text-align: center; box-shadow: 0 20px 50px -12px rgba(0,0,0,0.8); }
  .ph-dialog .ph-ic { color: var(--ph-gold); }
  .ph-dialog .ph-title { font-size: 16px; font-weight: 800; line-height: 1.35; overflow-wrap: anywhere; }
  .ph-dialog .ph-body { font-size: 13px; line-height: 1.6; color: var(--ph-sec); white-space: pre-wrap; overflow-wrap: anywhere; overflow-y: auto; }
  .ph-dialog .ph-btn { margin-top: 6px; padding: 9px 26px; border-radius: 999px; background: var(--ph-gold); color: var(--ph-gold-ink); font-size: 13px; font-weight: 700; }
  .ph-rtl { direction: rtl; font-family: var(--arabic); }
  .ph-empty { opacity: 0.45; font-style: italic; }

  /* The lock screen behind the notification. */
  .ph-lock { position: absolute; inset: 0; background: radial-gradient(120% 80% at 30% 10%, #1d3b2f 0%, #0b120f 60%); }
  .ph-time { position: absolute; top: 58px; left: 0; right: 0; text-align: center; font-size: 58px; font-weight: 250; letter-spacing: -1px; color: rgba(255,255,255,0.92); font-variant-numeric: tabular-nums; }
  .ph-date { position: absolute; top: 44px; left: 0; right: 0; text-align: center; font-size: 13px; font-weight: 600; color: rgba(255,255,255,0.75); }
  .ph-note { position: absolute; left: 10px; right: 10px; top: 168px; padding: 11px 12px; border-radius: 20px; background: rgba(40, 48, 44, 0.72); -webkit-backdrop-filter: blur(16px); backdrop-filter: blur(16px); color: #fff; }
  .ph-note-top { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; font-size: 11px; color: rgba(255,255,255,0.7); }
  .ph-note-top .ph-appname { flex: 1; text-transform: uppercase; letter-spacing: 0.4px; font-weight: 600; }
  .ph-appicon { width: 20px; height: 20px; border-radius: 5px; background: #16382a; display: grid; grid-template-columns: 1fr 1fr; gap: 1.5px; padding: 3.5px; }
  .ph-appicon i { display: block; border-radius: 1px; background: #3fcf8e; }
  .ph-appicon i:nth-child(2) { background: var(--ph-gold); }
  .ph-note .ph-title { font-size: 13px; font-weight: 700; line-height: 1.35; overflow-wrap: anywhere; }
  .ph-note .ph-body { font-size: 13px; line-height: 1.35; color: rgba(255,255,255,0.92); overflow-wrap: anywhere; display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; white-space: pre-wrap; }
  .preview-note { margin: var(--s4) 0 0; font-size: 11.5px; color: var(--text-tert); text-align: center; line-height: 1.5; }

  /* ---- Reach ---- */
  .big { display: flex; align-items: baseline; gap: var(--s2); margin-bottom: var(--s3); }
  .big b { font-size: 30px; font-weight: 750; letter-spacing: -0.8px; font-variant-numeric: tabular-nums; }
  .big span { font-size: 13px; color: var(--text-sec); }
  .facts { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 7px; font-size: 12.5px; color: var(--text-sec); }
  .facts li { display: flex; gap: 8px; align-items: flex-start; line-height: 1.45; }
  .facts li svg { flex: 0 0 auto; margin-top: 2px; color: var(--text-tert); }
  .facts b { color: var(--text); font-variant-numeric: tabular-nums; }
  .facts .warn svg, .facts .warn b { color: var(--warn); }
  .facts code { font-family: var(--mono); font-size: 11px; padding: 1px 5px; border-radius: 5px; background: var(--bg-sunken); color: var(--text); }
  .cost p { margin: 0 0 var(--s2); font-size: 12.5px; color: var(--text-sec); line-height: 1.55; }
  .cost p:last-child { margin-bottom: 0; }
  .cost .free { display: inline-block; padding: 1px 9px; border-radius: var(--r-pill); background: var(--success-soft); border: 1px solid var(--success-line); color: var(--success); font-weight: 700; font-size: 12px; margin-inline-end: 6px; }

  /* ---- Showing now / history ---- */
  .msg-card { border: 1px solid var(--border); border-radius: var(--r-md); padding: var(--s4); margin-bottom: var(--s3); background: var(--bg-sunken); }
  .msg-card:last-child { margin-bottom: 0; }
  .live-top { display: flex; align-items: center; gap: var(--s2); margin-bottom: var(--s2); flex-wrap: wrap; }
  .live-top .when { font-size: 11.5px; color: var(--text-tert); }
  .live-top .btn { margin-inline-start: auto; padding: 5px 10px; font-size: 12px; }
  .tag { display: inline-flex; align-items: center; gap: 4px; padding: 1px 8px; border-radius: var(--r-pill); font-size: 10.5px; font-weight: 700; letter-spacing: 0.3px; text-transform: uppercase; border: 1px solid var(--border); color: var(--text-sec); }
  .tag.everyone { color: var(--accent); border-color: var(--accent-line); background: var(--accent-soft); }
  .tag.test { color: var(--info); border-color: var(--info-line); background: var(--info-soft); }
  .tag.stopped, .tag.ended { color: var(--text-tert); }
  .live-title { font-family: var(--arabic); direction: rtl; text-align: right; font-size: 15px; font-weight: 700; unicode-bidi: plaintext; }
  .live-body { font-family: var(--arabic); direction: rtl; text-align: right; font-size: 13.5px; color: var(--text-sec); line-height: 1.6; white-space: pre-wrap; unicode-bidi: plaintext; }
  .none { font-size: 12.5px; color: var(--text-tert); }

  .hist { display: flex; flex-direction: column; }
  .hist-row { display: grid; grid-template-columns: 30px minmax(0, 1fr) auto; gap: var(--s3); align-items: center; padding: 10px 2px; border-bottom: 1px solid var(--border-soft); }
  .hist-row:last-child { border-bottom: 0; }
  .hist-row .k { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 9px; background: var(--surface-2); color: var(--text-sec); }
  .hist-row .t { min-width: 0; }
  .hist-row .t .ttl { font-family: var(--arabic); font-size: 14px; font-weight: 650; direction: rtl; text-align: right; unicode-bidi: plaintext; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .hist-row .t .meta { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; font-size: 11.5px; color: var(--text-tert); margin-top: 2px; }
  .hist-row .r { font-size: 12px; color: var(--text-sec); text-align: end; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .hist-row .r .bad { color: var(--warn); }

  .banner { display: flex; gap: var(--s3); align-items: flex-start; padding: var(--s3) var(--s4); border-radius: var(--r-md); font-size: 13px; margin-bottom: var(--s4); border: 1px solid; line-height: 1.5; }
  .banner svg { flex: 0 0 auto; margin-top: 2px; }
  .banner.danger { background: var(--danger-soft); border-color: var(--danger-line); color: var(--danger); }
  .banner.warn-b { background: var(--warn-soft); border-color: var(--warn-line); color: var(--warn); }
  .banner.info { background: var(--info-soft); border-color: var(--info-line); color: var(--info); }
  .banner code { font-family: var(--mono); font-size: 11.5px; }
  .loading { padding: 40px 0; text-align: center; color: var(--text-tert); font-size: 13px; }

  /* ---- Confirm ---- */
  .scrim { position: fixed; inset: 0; z-index: 80; display: flex; align-items: center; justify-content: center; padding: 20px; background: rgba(4, 7, 6, 0.6); }
  .scrim[hidden] { display: none; }
  .confirm { width: min(520px, 100%); max-height: 90vh; overflow-y: auto; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 16px; box-shadow: var(--shadow-lg); padding: var(--s6); }
  .confirm h3 { margin: 0 0 var(--s3); font-size: 17px; font-weight: 750; letter-spacing: -0.2px; text-transform: none; color: var(--text); padding: 0; border: 0; }
  .confirm p { margin: 0 0 var(--s4); font-size: 13px; color: var(--text-sec); line-height: 1.55; }
  .confirm .quote { border-inline-start: 3px solid var(--accent); padding: var(--s3) var(--s4); margin: 0 0 var(--s4); background: var(--bg-sunken); border-radius: var(--r-sm); }
  .confirm .actions { margin-top: var(--s4); }

  .toast { position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(12px); opacity: 0; pointer-events: none; max-width: min(640px, 92vw); padding: 10px 16px; border-radius: 14px; background: var(--text); color: var(--bg); font-size: 13px; font-weight: 550; box-shadow: var(--shadow-lg); z-index: 90; transition: opacity 0.16s ease, transform 0.16s ease; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  .toast.bad { background: var(--danger); color: #1a0806; }
  @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }

  @media (max-width: 1100px) {
    .msg-grid, .below { grid-template-columns: 1fr; }
  }
  @media (max-width: 640px) {
    .kind-choice, .two { grid-template-columns: 1fr; }
  }
`;

function renderBroadcastPage({ projectId = '' } = {}) {
  const icons = {};
  for (const name of PAGE_ICONS) icons[name] = icon(name, 16);
  // JSON inside a script tag: a closing tag in any string must not end the
  // block early, so every '<' is written as its JSON escape.
  const iconsJson = JSON.stringify(icons).replace(/</g, '\\u003c');
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700;750;800&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Messages · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${PAGE_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'messages', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Messages', sub: 'One message to everyone, as a pop-up or a notification', live: false })}
    <div class="app-content msg-content">
      <p class="msg-intro">Write it once and choose how it arrives. A <b>pop-up</b> shows once, the next time each person opens the app. A <b>notification</b> lands on their phone now, the way a room update does. Send a test to your own account first: it goes only to the accounts you pick below.</p>
      <div id="banners"></div>
      <section id="viewMessages">
        <div class="msg-grid">
          <section class="panel compose" aria-labelledby="composeTitle">
            <h2 id="composeTitle">${icon('megaphone', 15)} New message</h2>

            <div class="kind-choice" role="radiogroup" aria-label="How it arrives">
              <button type="button" class="kind-card" role="radio" aria-checked="true" data-kind="popup" aria-label="Pop-up: shows once when they open the app">
                <span class="ic">${icon('app-window', 18)}</span>
                <span><b>Pop-up</b><span class="d">Shows once when they open the app. Stays up for the days you choose.</span></span>
              </button>
              <button type="button" class="kind-card" role="radio" aria-checked="false" data-kind="notification" aria-label="Notification: lands on their phone now">
                <span class="ic">${icon('bell', 18)}</span>
                <span><b>Notification</b><span class="d">Lands on their phone now, even with the app closed.</span></span>
              </button>
            </div>

            <fieldset class="lang-block">
              <legend>Arabic</legend>
              <label class="field" data-field="titleAr">
                <span class="field-top"><span>Title</span><span class="char-count" data-count="titleAr"></span></span>
                <input type="text" id="titleAr" aria-label="Arabic title" class="rtl" dir="rtl" autocomplete="off" spellcheck="false">
              </label>
              <label class="field" data-field="bodyAr">
                <span class="field-top"><span>Message</span><span class="char-count" data-count="bodyAr"></span></span>
                <textarea id="bodyAr" aria-label="Arabic message" class="rtl" dir="rtl" rows="4" spellcheck="false"></textarea>
              </label>
              <label class="field popup-only" data-field="buttonAr">
                <span class="field-top"><span>Button</span><span class="char-count" data-count="buttonAr"></span></span>
                <input type="text" id="buttonAr" aria-label="Arabic button" class="rtl" dir="rtl" autocomplete="off" spellcheck="false">
              </label>
            </fieldset>

            <fieldset class="lang-block">
              <legend>English <span class="opt">optional: without it, English phones get the Arabic</span></legend>
              <label class="field" data-field="titleEn">
                <span class="field-top"><span>Title</span><span class="char-count" data-count="titleEn"></span></span>
                <input type="text" id="titleEn" aria-label="English title" dir="ltr" autocomplete="off">
              </label>
              <label class="field" data-field="bodyEn">
                <span class="field-top"><span>Message</span><span class="char-count" data-count="bodyEn"></span></span>
                <textarea id="bodyEn" aria-label="English message" dir="ltr" rows="3"></textarea>
              </label>
              <label class="field popup-only" data-field="buttonEn">
                <span class="field-top"><span>Button</span><span class="char-count" data-count="buttonEn"></span></span>
                <input type="text" id="buttonEn" aria-label="English button" dir="ltr" autocomplete="off">
              </label>
            </fieldset>

            <div class="days-row popup-only">
              <label class="field">
                <span class="field-top"><span>Keep it up for</span></span>
                <select id="days" aria-label="Keep it up for"></select>
              </label>
              <span class="hint">Anyone who opens the app in that time sees it once. After that it is gone, even for people who never opened the app.</span>
            </div>

            <div class="checks" id="checks" aria-live="polite"></div>

            <div class="testers">
              <div class="testers-head">Test on<span>your own accounts, before everyone</span></div>
              <div class="tester-chips" id="testerChips"></div>
              <div class="tester-add">
                <input type="search" id="testerSearch" placeholder="Add an account: name or email" autocomplete="off" aria-label="Add a test account">
                <div class="dropdown" id="testerResults" hidden></div>
              </div>
            </div>

            <div class="actions">
              <span class="why" id="actionsWhy"></span>
              <button type="button" class="btn" id="sendTest">${icon('flask-conical', 15)}<span>Send test</span></button>
              <button type="button" class="btn primary" id="sendAll">${icon('send', 15)}<span>Send to everyone</span></button>
            </div>
          </section>

          <aside class="side-col">
            <section class="panel" aria-labelledby="previewTitle">
              <div class="preview-head">
                <h2 id="previewTitle">${icon('smartphone', 15)} Preview</h2>
                <div class="seg" role="group" aria-label="Preview language">
                  <button type="button" data-lang="ar" aria-pressed="true">عربي</button>
                  <button type="button" data-lang="en" aria-pressed="false">English</button>
                </div>
              </div>
              <div class="phone"><div class="screen" id="phoneScreen"></div></div>
              <p class="preview-note" id="previewNote"></p>
            </section>

            <section class="panel" aria-labelledby="reachTitle">
              <h2 id="reachTitle">${icon('users', 15)} Who it reaches</h2>
              <div id="reach"><div class="loading">Counting phones&hellip;</div></div>
            </section>

            <section class="panel cost" aria-labelledby="costTitle">
              <h2 id="costTitle">${icon('info', 15)} What it costs</h2>
              <p><span class="free">Free</span>Notifications go through Firebase Cloud Messaging, which Google does not charge for, and they leave from this Mac, so no server function runs.</p>
              <p>Finding the phones reads one small record per account (about 140 reads today). A pop-up costs one read each time someone opens the app. Firestore gives 50,000 reads a day for free, and the whole app uses a few thousand.</p>
            </section>
          </aside>
        </div>

        <div class="below">
          <section class="panel" aria-labelledby="liveTitle">
            <h2 id="liveTitle">${icon('app-window', 15)} Pop-up showing now</h2>
            <div id="liveNow"><div class="loading">Loading&hellip;</div></div>
          </section>
          <section class="panel" aria-labelledby="histTitle">
            <h2 id="histTitle">${icon('history', 15)} Sent before</h2>
            <div id="history"><div class="loading">Loading&hellip;</div></div>
          </section>
        </div>
      </section>
    </div>
  </div>
</div>

<div class="scrim" id="confirmScrim" hidden>
  <div class="confirm" role="dialog" aria-modal="true" aria-labelledby="confirmTitle">
    <h3 id="confirmTitle"></h3>
    <div id="confirmBody"></div>
    <div class="actions">
      <button type="button" class="btn" id="confirmCancel">Cancel</button>
      <button type="button" class="btn primary" id="confirmGo"></button>
    </div>
  </div>
</div>

<div class="toast" id="toast" role="status" aria-live="polite"></div>
<noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
<script type="application/json" id="msgIcons">${iconsJson}</script>
<script src="/wording/rules.js"></script>
<script src="/messages/app.js"></script>
<script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderBroadcastPage, PAGE_STYLES };
