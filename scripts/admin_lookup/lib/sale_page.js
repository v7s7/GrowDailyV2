'use strict';

/**
 * The Sale page's HTML. The behaviour is ../sale/app.js and the rules it
 * shares with the server are lib/sale_rules.js (served as /sale/rules.js),
 * both plain files, for the reason wording_page.js gives: a script inside a
 * template literal has twice shipped a page that loaded and did nothing.
 *
 * The layout follows the approved design (paywall-sale/SaleAdmin): a status
 * bar across the top, then the welcome price, the sale form and the past
 * sales on the left, and on the right the day Lifetime went to full price,
 * what phones show, the rules, and who pays full price.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar, icon } = require('./shell');
const { OFFERS_STYLES } = require('./offers_styles');

const check = icon('check', 16);

function renderSalePage({ projectId = '' } = {}) {
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
    ${topBar({ title: 'Sale', sub: 'Lifetime at a lower price for everyone between two dates, and the welcome price', live: false })}
    <div class="app-content offers-content">
      <p class="intro">Lowers Lifetime for everyone between two dates. Phones cross out the full price, show the countdown to the end, and go back to the full price by themselves when it ends. Everything here is written to <b>offers/live</b>, which every phone reads when its paywall opens.</p>

      <div id="banners"></div>

      <div class="page-body">
        <div class="status-bar" id="statusBar" aria-live="polite"><div class="loading">Loading the sale&hellip;</div></div>

        <div class="cols">
          <div class="col">
            <section class="card" aria-labelledby="welcomeTitle">
              <div class="card-head">
                <div>
                  <h2 id="welcomeTitle">Welcome price</h2>
                  <p class="note" id="welcomeNote">Everyone who hasn't bought gets the offer price once, for a set number of hours from the first time they open the paywall. The start is saved to their account, so it never restarts, and at zero the offer is gone for them.</p>
                </div>
                <label class="switch" id="welcomeSwitchLabel" for="welcomeSwitch"><input type="checkbox" id="welcomeSwitch"><span id="welcomeSwitchText">On</span></label>
              </div>
              <div class="facts">
                <div class="fld">
                  <label for="welcomeHours">Length, hours</label>
                  <input type="number" id="welcomeHours" min="24" max="168" step="1" inputmode="numeric">
                  <span class="hint">24 to 168.</span>
                </div>
                <div class="fact"><span class="k">Welcome price</span><span class="v" id="welcomePrice"></span><span class="s">Lifetime (offer), US price</span></div>
                <div class="fact"><span class="k">Windows open now</span><span class="v" id="windowsOpen">&hellip;</span><span class="s" id="windowsSub">People inside their window</span></div>
              </div>
              <div class="btn-row">
                <button type="button" class="btn primary" id="welcomeSave" disabled>Save welcome price</button>
                <span class="fine" id="welcomeMsg"></span>
              </div>
            </section>

            <section class="card" aria-labelledby="scheduleTitle">
              <h2 id="scheduleTitle">Schedule a sale</h2>
              <div class="fgrid">
                <div class="fld">
                  <label for="sNameAr">Name on phones, Arabic</label>
                  <input type="text" id="sNameAr" class="ar" dir="rtl" maxlength="40" autocomplete="off">
                </div>
                <div class="fld">
                  <label for="sNameEn">Name on phones, English</label>
                  <input type="text" id="sNameEn" maxlength="40" autocomplete="off">
                </div>
                <div class="fld">
                  <label for="sStartDay">Starts, Bahrain time</label>
                  <div class="pair">
                    <input type="date" id="sStartDay">
                    <input type="time" id="sStartTime" aria-label="Start time" value="00:00">
                  </div>
                </div>
                <div class="fld">
                  <label for="sEndDay">Ends, Bahrain time</label>
                  <div class="pair">
                    <input type="date" id="sEndDay">
                    <input type="time" id="sEndTime" aria-label="End time" value="23:59">
                  </div>
                </div>
              </div>
              <div class="facts">
                <div class="fact"><span class="k">Sale price</span><span class="v" id="factSale"></span><span class="s">Lifetime (offer), US price</span></div>
                <div class="fact"><span class="k">Full price</span><span class="v" id="factFull"></span><span class="s">Lifetime, US price</span></div>
                <div class="fact"><span class="k">Phones show</span><span class="v accent" id="factOff"></span><span class="s">Worked out from the two prices</span></div>
              </div>
              <p class="note" id="saleSummary"></p>
              <ul class="checks" id="saleChecks" aria-live="polite"></ul>
              <div class="btn-row">
                <button type="button" class="btn primary big" id="scheduleBtn" disabled>Schedule sale</button>
                <button type="button" class="btn danger-line big" id="endBtn" disabled>End the running sale now</button>
              </div>
              <p class="fine" id="endNote"></p>
            </section>

            <section class="card flush" aria-labelledby="pastTitle">
              <div class="card-head bar"><h2 id="pastTitle">Past sales</h2><span class="sub">From offer_sales, newest first</span></div>
              <div class="table-wrap">
                <table class="dtable">
                  <thead><tr><th scope="col">Sale</th><th scope="col">Dates, Bahrain</th><th scope="col">State</th><th scope="col" class="num">Price</th><th scope="col" class="num">Lifetime sales</th></tr></thead>
                  <tbody id="pastSales"></tbody>
                </table>
              </div>
            </section>
          </div>

          <div class="col">
            <section class="card" aria-labelledby="fullSinceTitle">
              <h2 id="fullSinceTitle">Full price since</h2>
              <p class="note">The day Lifetime moved to its full price in the App Store. The 30-day rule counts from here, so no sale can be scheduled until it is set.</p>
              <div class="btn-row">
                <div class="fld" style="flex: 1 1 180px;">
                  <label for="fullSince">Day, Bahrain</label>
                  <input type="date" id="fullSince">
                </div>
                <button type="button" class="btn" id="fullSinceSave" style="align-self: flex-end;" disabled>Save day</button>
              </div>
              <p class="fine" id="fullSinceMsg"></p>
            </section>

            <section class="card" aria-labelledby="phoneTitle">
              <h2 id="phoneTitle">What phones show during it</h2>
              <div id="phone"></div>
              <p class="fine">A sketch of the paywall with this form's name and dates. The app draws the real one, with each store's own prices.</p>
            </section>

            <section class="card" aria-labelledby="rulesTitle">
              <h2 id="rulesTitle">Rules this page keeps</h2>
              <ul class="rules">
                <li>${check}<span>The crossed-out price is Lifetime's full price, read by the phone from its store. Nobody types it.</span></li>
                <li>${check}<span>A countdown ends when its offer ends, and at zero the phone takes the offer price away in the same visit. A sale ends at the same moment for everyone; a welcome window never restarts.</span></li>
                <li>${check}<span>Lifetime is at full price for at least 30 days before a sale, and between sales.</span></li>
                <li>${check}<span>A sale lasts 30 days at most, and never longer than the full-price stretch before it.</span></li>
                <li>${check}<span>No more than 90 sale days in any 365.</span></li>
                <li>${check}<span>One sale at a time: phones hold the current or the next one, so the next is scheduled once this one ends.</span></li>
                <li>${check}<span>Under the buy button, phones say when the offer ends and what the price becomes.</span></li>
              </ul>
              <p class="fine">The server checks these again when you press Schedule, so a sale that breaks one is refused even if this page missed it.</p>
            </section>

            <section class="card" aria-labelledby="meterTitle">
              <h2 id="meterTitle">Who pays full price</h2>
              <div id="meter"><div class="loading">&hellip;</div></div>
              <p class="fine">If this gets close to zero, $39.99 is no longer a price people pay, and showing it crossed out stops being honest. Stop showing a crossed-out price then.</p>
            </section>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/sale/rules.js"></script>
  <script src="/sale/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderSalePage };
