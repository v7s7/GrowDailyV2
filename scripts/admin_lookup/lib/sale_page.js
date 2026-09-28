'use strict';

/**
 * The Sale page's HTML. The behaviour is ../sale/app.js and the rules it
 * shares with the server are lib/sale_rules.js (served as /sale/rules.js),
 * both plain files, for the reason wording_page.js gives: a script inside a
 * template literal has twice shipped a page that loaded and did nothing.
 *
 * The simple layout Aziz approved on 2026-09-27 ("i want simple but direct,
 * i can do everything and see everything, but not a lot of notes"): what is
 * happening now, with End now and the full-price day under it; the welcome
 * price as one switch; past sales. New sale and How it works open as
 * dialogs. The rules are not listed: the dialog shows the ones a sale
 * breaks, as it is typed, and the server checks them all again.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar, icon } = require('./shell');
const { OFFERS_STYLES } = require('./offers_styles');

function renderSalePage({ projectId = '' } = {}) {
  const newSale = `<button type="button" class="btn primary lg" id="newSaleBtn" disabled>${icon('plus', 16)}New sale</button>`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Sale · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${OFFERS_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'sale', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Sale', sub: 'Lifetime at a lower price for everyone, between two dates', live: false, actions: newSale })}
    <div class="app-content">
      <div class="simple">
        <div id="banners"></div>

        <div class="notice warn" id="readyNotice" hidden>
          ${icon('circle-alert', 18)}
          <span class="grow" id="readyText"></span>
          <button type="button" class="link-btn" id="howBtn">How to start</button>
        </div>

        <section class="panel" aria-labelledby="nowTitle">
          <div class="row">
            <div class="grow">
              <span class="eyebrow">Now</span>
              <h2 class="now-title" id="nowTitle">Loading&hellip;</h2>
              <p class="muted" id="nowSub"></p>
            </div>
            <button type="button" class="btn danger lg" id="endBtn" hidden>End now</button>
          </div>
          <div class="now-foot">
            <span class="muted">Lifetime at full price since</span>
            <b id="fullSinceText">&hellip;</b>
            <button type="button" class="link-btn" id="fullSinceEdit">Change</button>
            <span class="row" id="fullSinceForm" hidden>
              <input type="date" class="in" id="fullSinceInput" aria-label="The day Lifetime went to its full price" style="width: auto;">
              <button type="button" class="btn sm primary" id="fullSinceSave">Save</button>
              <button type="button" class="btn sm ghost" id="fullSinceCancel">Cancel</button>
            </span>
          </div>
        </section>

        <section class="panel" aria-labelledby="welcomeTitle">
          <div class="row">
            <div class="grow">
              <h2 id="welcomeTitle">Welcome price</h2>
              <p class="muted" id="welcomeText"></p>
            </div>
            <div class="ctl">
              <label for="welcomeHours" class="muted">For</label>
              <select class="in" id="welcomeHours" style="width: auto;"></select>
              <button type="button" class="sw" role="switch" aria-checked="false" id="welcomeSwitch" aria-labelledby="welcomeTitle"></button>
              <span class="sw-label" id="welcomeState">Off</span>
            </div>
          </div>
        </section>

        <section class="panel flush" aria-labelledby="pastTitle">
          <div class="panel-head"><h2 id="pastTitle">Past sales</h2></div>
          <table class="t">
            <thead><tr><th scope="col">Sale</th><th scope="col">Dates, Bahrain</th><th scope="col">State</th><th scope="col" class="num">Lifetime sold</th></tr></thead>
            <tbody id="pastSales"><tr class="empty"><td colspan="4">Loading&hellip;</td></tr></tbody>
          </table>
        </section>
        <p class="muted small" id="meterLine" hidden></p>
      </div>
    </div>
  </div>
</div>

<dialog class="dlg" id="saleDialog" aria-labelledby="saleDialogTitle">
  <div class="dlg-body">
    <div class="dlg-head">
      <h2 id="saleDialogTitle">New sale</h2>
      <button type="button" class="icon-btn" id="saleClose" aria-label="Close">${icon('x', 16)}</button>
    </div>
    <div class="fld" id="askFullSince" hidden>
      <label for="dFullSince">The day Lifetime went to its full price</label>
      <input type="date" class="in" id="dFullSince">
      <span class="hint">Asked once. The 30 days at full price before a sale count from here.</span>
    </div>
    <div class="grid2">
      <div class="fld">
        <label for="sNameAr">Name in Arabic</label>
        <input type="text" class="in ar" id="sNameAr" dir="rtl" maxlength="40" autocomplete="off">
      </div>
      <div class="fld">
        <label for="sNameEn">Name in English</label>
        <input type="text" class="in" id="sNameEn" maxlength="40" autocomplete="off">
      </div>
      <div class="fld">
        <label for="sStartDay">Starts, Bahrain time</label>
        <div class="pair">
          <input type="date" class="in" id="sStartDay">
          <input type="time" class="in" id="sStartTime" aria-label="Start time" value="00:00">
        </div>
      </div>
      <div class="fld">
        <label for="sEndDay">Ends, Bahrain time</label>
        <div class="pair">
          <input type="date" class="in" id="sEndDay">
          <input type="time" class="in" id="sEndTime" aria-label="End time" value="23:59">
        </div>
      </div>
    </div>
    <div class="sale-mid">
      <div class="grow" style="display: flex; flex-direction: column; gap: 12px;">
        <div class="row small muted" id="dPrices"></div>
        <ul class="checks" id="dChecks" aria-live="polite"></ul>
      </div>
      <div>
        <div class="phone" id="dPhone" lang="ar"></div>
        <div class="phone-cap">What phones show</div>
      </div>
    </div>
    <div class="dlg-foot">
      <button type="button" class="btn ghost lg" id="saleCancel">Cancel</button>
      <button type="button" class="btn primary lg" id="scheduleBtn" disabled>Schedule sale</button>
    </div>
  </div>
</dialog>

<dialog class="dlg" id="howDialog" aria-labelledby="howTitle">
  <div class="dlg-body">
    <div class="dlg-head">
      <h2 id="howTitle">How a sale works</h2>
      <button type="button" class="icon-btn" id="howClose" aria-label="Close">${icon('x', 16)}</button>
    </div>
    <span class="how-group">Once, before the first sale</span>
    <ol class="how">
      <li><div><b>Get the sale product approved</b><span>The Lifetime offer product goes to Apple with a build.</span></div></li>
      <li><div><b>Turn the welcome price off</b><span>On this page, unless you want it. It is on until it is saved off.</span></div></li>
      <li><div><b>Raise Lifetime to its full price</b><span>App Store Connect, Lifetime, Price.</span></div></li>
      <li><div><b>Wait 30 days at full price</b><span>Set the day you raised it under Now. New sale asks for it too.</span></div></li>
    </ol>
    <span class="how-group">Every sale</span>
    <ol class="how" style="counter-reset: how 4;">
      <li><div><b>New sale: a name and two dates</b><span>Then Schedule. The page checks the rules as you type.</span></div></li>
      <li><div><b>It runs and ends by itself</b><span>Phones show the countdown with the full price crossed out. End now stops it early.</span></div></li>
    </ol>
    <p class="muted small">A sale that breaks a rule is refused: 30 days at full price before it, 30 days long at most, 90 sale days a year at most, one at a time.</p>
  </div>
</dialog>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="notice danger">This page needs JavaScript.</div></noscript>
  <script src="/sale/rules.js"></script>
  <script src="/sale/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderSalePage };
