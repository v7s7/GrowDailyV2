'use strict';

/**
 * The control-room frame every live page of this tool sits in: a sidebar
 * with the destinations, a top bar that always says where the data comes
 * from and how fresh it is, and the dark theme the whole tool now opens in.
 *
 * Aziz, 2026-09-18: "make the design better, like a real web control room,
 * it's like html now". The pages used to be documents: a centred column on a
 * cream page, a title, and everything else scrolling underneath. A control
 * room is the opposite shape. The frame stays put, the destinations are
 * always one click away, the environment is always named (this reads and,
 * on the Wording page, writes the PRODUCTION project), and the page itself
 * uses the whole window.
 *
 * What is here:
 *   THEME_STYLES   the control-room colours, laid over BASE_STYLES' tokens
 *   SHELL_STYLES   the frame: sidebar, top bar, command palette
 *   THEME_BOOT     a head script that applies the saved theme before paint
 *   sidebar()      the destinations
 *   topBar()       title, freshness line, search, live pill, theme switch
 *   icon()         a Lucide icon, inlined from node_modules
 *
 * The behaviour (theme switch, the Cmd+K account search) is static/shell.js,
 * a plain file like the Wording page's scripts, for the same reason: code in
 * a template literal has twice shipped a page that silently did nothing.
 *
 * The standalone report file (lookup_user.js) does not use this frame: it is
 * saved to disk and opened without the server, where every sidebar link
 * would be dead.
 */

const fs = require('node:fs');
const path = require('node:path');

const ICON_DIR = path.join(__dirname, '..', 'node_modules', 'lucide-static', 'icons');
const iconCache = new Map();

/**
 * A Lucide icon as inline SVG, [size] pixels square, or an empty string when
 * the name does not exist (a missing icon costs its glyph, never the page).
 * Inline rather than an icon font or a script: it renders with no request
 * and no JavaScript, and takes currentColor from whatever it sits in.
 */
function icon(name, size = 16) {
  const key = name + '@' + size;
  if (iconCache.has(key)) return iconCache.get(key);
  let svg = '';
  try {
    svg = fs.readFileSync(path.join(ICON_DIR, name + '.svg'), 'utf8')
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/\s+/g, ' ')
      .replace(/width="24"/, `width="${size}"`)
      .replace(/height="24"/, `height="${size}"`)
      .replace('<svg ', '<svg aria-hidden="true" focusable="false" ')
      .trim();
  } catch {
    svg = '';
  }
  iconCache.set(key, svg);
  return svg;
}

/**
 * The control-room theme, laid over BASE_STYLES' own tokens. BASE_STYLES
 * already names every colour through a role, so this is a repointing of those
 * roles, not a second stylesheet. Dark is the default whatever the machine's
 * setting; the light theme is BASE_STYLES' own, one click away in the top bar
 * and remembered.
 *
 * The chart series are the data-viz reference palette's first five slots,
 * validated (scripts/validate_palette.js) against these exact surfaces:
 * dark on #111814 passes every check (worst adjacent CVD delta E 8.4); light
 * on #ffffff passes with three slots under 3:1, which is why every chart
 * here has a table view.
 */
const THEME_STYLES = `
  :root {
    --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a; --series-4: #eda100; --series-5: #e87ba4;
    --chart-grid: #ece7dc; --chart-axis: #d6cdb9; --chart-deemph: #b3ab9c;
    --side-bg: #f3efe6; --top-bg: rgba(250, 248, 243, 0.86);
    --brand-tile: #16382a; --brand-sq: #3fcf8e;
  }
  :root:not([data-theme="light"]) {
    color-scheme: dark;

    /* Green-black, the app's own dark ground, rather than a neutral grey:
       the tool should read as part of the same product. */
    --bg: #0a0f0d;
    --bg-sunken: #070b09;
    --surface: #111814;
    --surface-2: #16201b;
    --border: #223029;
    --border-soft: #1a251f;
    --border-strong: #2e3f36;
    --text: #e8efea;          /* 15.4:1 on --surface */
    --text-sec: #a7b6ad;      /*  8.5:1 */
    --text-tert: #7f9187;     /*  5.4:1, still AA at the small sizes it carries */

    /* Gold, the app's own action colour (its add-habit button), for
       everything you can act on. 8.4:1 on the panel, 8.6:1 for its ink. */
    --accent: #d9aa55;
    --accent-hover: #e8c070;
    --accent-ink: #1a1408;
    --accent-soft: rgba(217, 170, 85, 0.12);
    --accent-line: rgba(217, 170, 85, 0.38);

    --success: #3fcf8e; --success-soft: rgba(63, 207, 142, 0.12); --success-line: rgba(63, 207, 142, 0.34);
    --danger:  #f08a7e; --danger-soft:  rgba(240, 138, 126, 0.12); --danger-line: rgba(240, 138, 126, 0.34);
    --warn:    #e2ad4e; --warn-soft:    rgba(226, 173, 78, 0.13);  --warn-line:   rgba(226, 173, 78, 0.36);
    --info:    #79bcea; --info-soft:    rgba(121, 188, 234, 0.12); --info-line:  rgba(121, 188, 234, 0.32);
    --undo:    #b493f5; --undo-soft:    rgba(180, 147, 245, 0.12); --undo-line:  rgba(180, 147, 245, 0.32);

    --heat-1: #173a2c; --heat-2: #1f5c42; --heat-3: #2c8a60; --heat-4: #3fcf8e;
    --heat-ink: #07100b;
    --q-do: #f08a7e; --q-sched: #79bcea; --q-deleg: #e2ad4e; --q-elim: #8e9a93;
    --mood-sad: #e0a06a;

    --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.45);
    --shadow-md: 0 1px 2px rgba(0, 0, 0, 0.45), 0 12px 28px -14px rgba(0, 0, 0, 0.75);
    --shadow-lg: 0 28px 64px -24px rgba(0, 0, 0, 0.85);

    --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --series-4: #c98500; --series-5: #d55181;
    --chart-grid: #1c2621; --chart-axis: #2e3f36; --chart-deemph: #56675e;
    --side-bg: #080d0b; --top-bg: rgba(10, 15, 13, 0.84);
    --brand-tile: #0f2a1f; --brand-sq: #3fcf8e;
  }
`;

const SHELL_STYLES = `
  /* ---- The frame -------------------------------------------------------
     Sidebar and main area side by side, the sidebar pinned while the page
     scrolls. The page no longer caps its own width: a control room uses the
     window, and each view sets the measure its content actually needs. */
  body.app-body { max-width: none; margin: 0; padding: 0; min-height: 100vh; }
  .app { display: grid; grid-template-columns: 232px minmax(0, 1fr); min-height: 100vh; }

  .side {
    position: sticky; top: 0; height: 100vh; overflow-y: auto;
    display: flex; flex-direction: column; gap: 2px;
    padding: 18px 12px 14px; background: var(--side-bg);
    border-inline-end: 1px solid var(--border);
  }
  .brand { display: flex; align-items: center; gap: 10px; padding: 2px 8px 18px; color: var(--text); text-decoration: none; }
  .brand:hover { color: var(--text); }
  /* The app's own mark, four squares, one of them gold. */
  .brand-mark { width: 30px; height: 30px; flex: 0 0 auto; display: grid; grid-template-columns: 1fr 1fr; gap: 3px; padding: 6px; border-radius: 9px; background: var(--brand-tile); box-shadow: inset 0 0 0 1px var(--border-strong); }
  .brand-mark i { display: block; border-radius: 2px; background: var(--brand-sq); }
  .brand-mark i:nth-child(2) { background: var(--accent); }
  .brand-name { display: block; font-size: 14px; font-weight: 700; letter-spacing: -0.2px; line-height: 1.15; }
  .brand-sub { display: block; font-size: 10.5px; font-weight: 650; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.7px; }
  .nav-label { font-size: 10.5px; font-weight: 650; color: var(--text-tert); text-transform: uppercase; letter-spacing: 0.7px; margin: 14px 10px 6px; }
  .nav-item {
    display: flex; align-items: center; gap: 10px; width: 100%;
    padding: 8px 10px; border: 0; border-radius: var(--r-sm); background: none;
    color: var(--text-sec); font: inherit; font-size: 13px; font-weight: 550;
    text-align: start; text-decoration: none; cursor: pointer;
  }
  .nav-item:hover { background: var(--surface-2); color: var(--text); }
  .nav-item.active { background: var(--accent-soft); color: var(--text); box-shadow: inset 2px 0 0 var(--accent); }
  html[dir="rtl"] .nav-item.active { box-shadow: inset -2px 0 0 var(--accent); }
  .nav-item svg { flex: 0 0 auto; opacity: 0.9; }
  .nav-item.active svg { color: var(--accent); opacity: 1; }
  .nav-count { margin-inline-start: auto; font-size: 11px; font-weight: 500; color: var(--text-tert); font-variant-numeric: tabular-nums; }
  .side-foot { margin-top: auto; padding: 14px 10px 2px; border-top: 1px solid var(--border); font-size: 11.5px; color: var(--text-tert); line-height: 1.55; }
  .env-pill { display: inline-flex; align-items: center; gap: 6px; padding: 2px 8px; border-radius: var(--r-pill); border: 1px solid var(--danger-line); background: var(--danger-soft); color: var(--danger); font-size: 10.5px; font-weight: 700; letter-spacing: 0.6px; margin-bottom: 6px; }
  .side-foot code { font-family: var(--mono); font-size: 10.5px; color: var(--text-sec); }

  .app-main { min-width: 0; display: flex; flex-direction: column; }
  .app-top {
    position: sticky; top: 0; z-index: 35;
    display: flex; align-items: center; gap: 14px; min-height: 64px;
    padding: 10px 28px; background: var(--top-bg);
    -webkit-backdrop-filter: saturate(140%) blur(10px); backdrop-filter: saturate(140%) blur(10px);
    border-bottom: 1px solid var(--border);
  }
  .app-top .t-main { min-width: 0; }
  .app-top h1 { font-size: 17px; font-weight: 700; margin: 0; letter-spacing: -0.2px; }
  .app-top .t-sub { font-size: 12px; color: var(--text-tert); margin-top: 1px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .top-actions { margin-inline-start: auto; display: flex; align-items: center; gap: 8px; flex: 0 0 auto; }
  .cmdk-btn {
    display: inline-flex; align-items: center; gap: 8px; width: 250px;
    padding: 7px 10px; border: 1px solid var(--border); border-radius: var(--r-md);
    background: var(--surface); color: var(--text-tert); font: inherit; font-size: 12.5px; cursor: pointer;
  }
  .cmdk-btn:hover { border-color: var(--border-strong); color: var(--text-sec); }
  .cmdk-btn kbd, .cmdk kbd { margin-inline-start: auto; font-family: var(--mono); font-size: 10.5px; padding: 1px 5px; border: 1px solid var(--border); border-radius: 5px; color: var(--text-tert); background: var(--bg); }
  .live-pill { display: inline-flex; align-items: center; gap: 7px; padding: 5px 10px; border-radius: var(--r-pill); border: 1px solid var(--border); background: var(--surface); color: var(--text-sec); font-size: 12px; font-weight: 600; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .live-pill.on { border-color: var(--success-line); background: var(--success-soft); color: var(--success); }
  .pulse { width: 8px; height: 8px; border-radius: 50%; background: currentColor; flex: 0 0 auto; }
  @media (prefers-reduced-motion: no-preference) {
    .live-pill.on .pulse { animation: gd-pulse 1.8s ease-out infinite; }
  }
  @keyframes gd-pulse {
    0% { box-shadow: 0 0 0 0 var(--success-line); }
    70% { box-shadow: 0 0 0 7px transparent; }
    100% { box-shadow: 0 0 0 0 transparent; }
  }
  .icon-button { display: inline-grid; place-items: center; width: 34px; height: 34px; border-radius: var(--r-md); border: 1px solid var(--border); background: var(--surface); color: var(--text-sec); cursor: pointer; }
  .icon-button:hover { border-color: var(--border-strong); color: var(--text); }
  .app-top .btn { white-space: nowrap; }
  .icon-button .when-light, :root[data-theme="light"] .icon-button .when-dark { display: none; }
  :root[data-theme="light"] .icon-button .when-light { display: inline-flex; }
  .icon-button .when-dark { display: inline-flex; }
  /* Initials sit on a mid-tone disc coloured from the uid; white reads on
     every one of those in both themes. */
  :root body.app-body .avatar { color: #fff; }
  .app-content { padding: 22px 28px 64px; width: 100%; max-width: 1640px; }

  /* ---- Cmd+K: find an account from anywhere --------------------------- */
  .cmdk-scrim { position: fixed; inset: 0; z-index: 90; display: flex; align-items: flex-start; justify-content: center; padding-top: 12vh; background: rgba(4, 7, 6, 0.55); }
  .cmdk { width: min(620px, 92vw); overflow: hidden; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 14px; box-shadow: var(--shadow-lg); }
  .cmdk-head { display: flex; align-items: center; gap: 10px; padding: 4px 16px; border-bottom: 1px solid var(--border); color: var(--text-tert); }
  /* :focus too: the base search-field focus ring would draw a box inside the
     dialog, which is itself the focused thing. */
  .cmdk-head input, .cmdk-head input:focus { flex: 1; min-width: 0; border: 0; padding: 14px 0; font: inherit; font-size: 15px; background: transparent; color: var(--text); outline: none; box-shadow: none; }
  .cmdk-list { max-height: 52vh; overflow-y: auto; padding: 6px; }
  .cmdk-item { display: flex; align-items: center; gap: 10px; padding: 8px 10px; border-radius: var(--r-sm); cursor: pointer; color: var(--text); }
  .cmdk-item.sel { background: var(--accent-soft); }
  .cmdk-item .who { min-width: 0; flex: 1; }
  .cmdk-item .nm { display: block; font-size: 13.5px; font-weight: 600; unicode-bidi: plaintext; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .cmdk-item .ml { display: block; font-size: 11.5px; color: var(--text-tert); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .cmdk-item .go { color: var(--text-tert); }
  .cmdk-empty { padding: 26px 12px; text-align: center; color: var(--text-tert); font-size: 13px; }
  .cmdk-foot { display: flex; gap: 14px; padding: 8px 14px; border-top: 1px solid var(--border); font-size: 11px; color: var(--text-tert); }

  /* ---- Narrow windows: the sidebar becomes a strip across the top ----- */
  @media (max-width: 960px) {
    .app { grid-template-columns: 1fr; }
    .side { position: static; height: auto; flex-direction: row; flex-wrap: wrap; align-items: center; gap: 4px; padding: 10px 12px; border-inline-end: 0; border-bottom: 1px solid var(--border); }
    .brand { padding: 0 8px 0 0; }
    .nav-label, .side-foot { display: none; }
    .nav-item { width: auto; }
    .app-top { position: static; flex-wrap: wrap; padding: 10px 16px; }
    .cmdk-btn { width: auto; }
    .app-content { padding: 16px 16px 48px; }
  }
`;

/**
 * Runs in <head>, before anything paints, so a light-theme choice never
 * flashes dark first. Wrapped in try: storage can be blocked, and the answer
 * then is simply the default.
 */
const THEME_BOOT = "(function(){try{var t=localStorage.getItem('gd-admin-theme');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t);}catch(e){}})();";

/**
 * The destinations. On the dashboard, Overview / Activity / Accounts are
 * views of one page ([inPageViews]); everywhere else they are links back to
 * it, landing on the right view by its hash.
 */
function sidebar({ active, inPageViews = false, projectId = '', counts = {} } = {}) {
  const view = (id, label, iconName, countId) => {
    const on = active === id ? ' active' : '';
    const count = countId ? `<span class="nav-count" id="${countId}">${counts[id] == null ? '' : counts[id]}</span>` : '';
    if (inPageViews) {
      return `<button type="button" class="nav-item view-tab${on}" data-view="${id}">${icon(iconName)}<span>${label}</span>${count}</button>`;
    }
    return `<a class="nav-item${on}" href="/#${id}">${icon(iconName)}<span>${label}</span>${count}</a>`;
  };
  return `<aside class="side" aria-label="Sections">
    <a class="brand" href="/#overview" title="Grow Daily control room">
      <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
      <span><span class="brand-name">Grow Daily</span><span class="brand-sub">Control room</span></span>
    </a>
    <div class="nav-label">Watch</div>
    ${view('overview', 'Overview', 'layout-dashboard')}
    ${view('activity', 'Activity', 'activity', inPageViews ? 'cntActivity' : null)}
    ${view('accounts', 'Accounts', 'users', inPageViews ? 'cntAccounts' : null)}
    <div class="nav-label">Change</div>
    <a class="nav-item${active === 'wording' ? ' active' : ''}" href="/wording">${icon('languages')}<span>Wording</span></a>
    <a class="nav-item${active === 'achievements' ? ' active' : ''}" href="/achievements">${icon('trophy')}<span>Achievements</span></a>
    <a class="nav-item${active === 'creators' ? ' active' : ''}" href="/creators">${icon('ticket')}<span>Creators</span></a>
    <a class="nav-item${active === 'sale' ? ' active' : ''}" href="/sale">${icon('tag')}<span>Sale</span></a>
    <a class="nav-item${active === 'messages' ? ' active' : ''}" href="/messages">${icon('megaphone')}<span>Messages</span></a>
    <div class="side-foot">
      <span class="env-pill">${icon('radio', 12)} PRODUCTION</span><br>
      ${projectId ? `<code>${projectId}</code><br>` : ''}
      Local tool, this Mac only
    </div>
  </aside>`;
}

/**
 * The bar across the top of the main area. [actions] is extra markup for the
 * right-hand side (a Refresh button, say); search, the live pill and the
 * theme switch are always there. The live pill is filled in by the page
 * (#livePill), because only the page knows how fresh its data is.
 */
function topBar({ title, sub = '', titleId = '', subId = '', actions = '', live = true } = {}) {
  return `<header class="app-top">
    <div class="t-main">
      <h1${titleId ? ` id="${titleId}"` : ''}>${title}</h1>
      <div class="t-sub"${subId ? ` id="${subId}"` : ''}>${sub}</div>
    </div>
    <div class="top-actions">
      <button type="button" class="cmdk-btn" id="cmdkOpen" title="Find any account">${icon('search', 15)}<span>Find an account</span><kbd>⌘K</kbd></button>
      ${live ? `<span class="live-pill" id="livePill"><span class="pulse"></span><span id="livePillText">Connecting…</span></span>` : ''}
      ${actions}
      <button type="button" class="icon-button" id="themeToggle" title="Switch between dark and light" aria-label="Switch between dark and light"><span class="when-dark">${icon('sun', 16)}</span><span class="when-light">${icon('moon', 16)}</span></button>
    </div>
  </header>`;
}

/** Everything a page puts in <head> to wear the frame, after BASE_STYLES. */
const SHELL_HEAD = `<script>${THEME_BOOT}</script>`;

module.exports = {
  THEME_STYLES,
  SHELL_STYLES,
  THEME_BOOT,
  SHELL_HEAD,
  icon,
  sidebar,
  topBar,
};
