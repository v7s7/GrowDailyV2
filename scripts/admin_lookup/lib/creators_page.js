'use strict';

/**
 * The Creators page's HTML. The behaviour is ../creators/app.js, and the
 * money and code rules it shares with the server are lib/creators.js
 * (served as /creators/rules.js), both plain files for the reason
 * wording_page.js gives.
 *
 * The layout follows the approved design (paywall-sale/Creators): four
 * tiles, then the creators table and how paying works on the left, and the
 * Add a creator form with its money preview, share link and the two-step
 * Apple code on the right.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar, icon } = require('./shell');
const { OFFERS_STYLES } = require('./offers_styles');

function renderCreatorsPage({ projectId = '' } = {}) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;550;600;650;700&family=JetBrains+Mono:wght@400;500&display=swap">
<title>Creators · GrowDaily Admin</title>
${SHELL_HEAD}
<style>${BASE_STYLES}
${THEME_STYLES}
${SHELL_STYLES}
${OFFERS_STYLES}</style>
</head>
<body class="app-body">
<div class="app">
  ${sidebar({ active: 'creators', projectId })}
  <div class="app-main">
    ${topBar({ title: 'Creators', sub: 'One Apple offer code per creator, and what each has earned', live: false })}
    <div class="app-content offers-content">
      <p class="intro">Each creator gets their own code. Their followers pay less for Lifetime, and the creator earns a share of what Apple sends you for every sale made with it, after Apple's cut and VAT, minus refunds.</p>

      <div id="banners"></div>

      <div class="page-body">
        <div class="tiles" id="tiles">
          <div class="tile">
            <span class="k">Apple offers in use</span>
            <span class="v"><span id="tOffers">&hellip;</span> <span class="of">of <span id="tOffersMax">10</span></span></span>
            <div class="bar-mini"><i id="tOffersBar" style="width:0%"></i></div>
            <span class="s" id="tOffersSub">One per creator. Apple allows 10 per app.</span>
          </div>
          <div class="tile">
            <span class="k">Code sales, last 30 days</span>
            <span class="v" id="tSales">&hellip;</span>
            <span class="s" id="tSalesSub"></span>
          </div>
          <div class="tile">
            <span class="k">Owed now</span>
            <span class="v good" id="tOwed">&hellip;</span>
            <span class="s">Sales older than 60 days, minus what you paid</span>
          </div>
          <div class="tile">
            <span class="k">Waiting</span>
            <span class="v" id="tWaiting">&hellip;</span>
            <span class="s">Payable after the 60-day wait</span>
          </div>
        </div>

        <div class="cols wide-left">
          <div class="col">
            <section class="card flush" aria-labelledby="listTitle">
              <div class="card-head bar">
                <h2 id="listTitle">Creators</h2>
                <span class="sub">Shares are worked out on each real sale, from RevenueCat's tax and Apple-cut figures. Production sales only.</span>
              </div>
              <div class="table-wrap">
                <table class="dtable tight">
                  <thead>
                    <tr>
                      <th scope="col">Creator</th>
                      <th scope="col">Deal</th>
                      <th scope="col" class="num">Sales</th>
                      <th scope="col" class="num">Earned</th>
                      <th scope="col" class="num">Paid</th>
                      <th scope="col" class="num">Waiting</th>
                      <th scope="col" class="num">Owed</th>
                      <th scope="col">Code ends</th>
                      <th scope="col"><span class="sr-only">Actions</span></th>
                    </tr>
                  </thead>
                  <tbody id="creatorRows"><tr class="empty-row"><td colspan="9">Loading the creators&hellip;</td></tr></tbody>
                  <tfoot id="creatorFoot"></tfoot>
                </table>
              </div>
            </section>
            <div id="ledgerNotes"></div>
            <div class="banner info">
              ${icon('info', 16)}
              <div class="grow"><b>How paying works.</b> A sale counts as Owed once it is 60 days old, so most refunds have already happened. You pay by bank transfer, then press Mark paid. A refund that comes after a payment is taken off the next one. The shares come from RevenueCat's estimates; Apple's own proceeds report stays the record before money moves.</div>
            </div>
          </div>

          <div class="col">
            <section class="card" aria-labelledby="addTitle">
              <h2 id="addTitle">Add a creator</h2>
              <div class="fgrid">
                <div class="fld span2">
                  <label for="cName">Creator name</label>
                  <input type="text" id="cName" maxlength="80" placeholder="The name you pay them under" autocomplete="off">
                </div>
                <div class="fld">
                  <label for="cCode">Code</label>
                  <input type="text" id="cCode" class="mono" maxlength="64" autocomplete="off" spellcheck="false" autocapitalize="characters">
                  <span class="hint">Latin letters and digits. Short is easier to type.</span>
                </div>
                <div class="fld">
                  <label for="cOff">Buyer discount, %</label>
                  <input type="number" id="cOff" min="1" max="90" step="1" value="20" inputmode="numeric">
                </div>
                <div class="fld">
                  <label for="cBase">Discount off</label>
                  <select id="cBase">
                    <option value="growdaily_lifetime_offer">Lifetime, $29.99</option>
                    <option value="growdaily_lifetime">Lifetime, $39.99</option>
                  </select>
                </div>
                <div class="fld">
                  <label for="cShare">Creator share, %</label>
                  <input type="number" id="cShare" min="0" max="100" step="0.5" value="25" inputmode="decimal">
                  <span class="hint">Of what Apple sends you. 25 by default.</span>
                </div>
                <div class="fld">
                  <label for="cUntil">Code ends on</label>
                  <input type="date" id="cUntil">
                  <span class="hint" id="cUntilHint">Apple allows 6 months, then renew it. It stops at 00:00 Pacific time that day.</span>
                </div>
                <div class="fld">
                  <label for="cUses">Uses allowed</label>
                  <input type="number" id="cUses" min="1" max="25000" step="1" value="1000" inputmode="numeric">
                  <span class="hint">Up to 25,000 at a time.</span>
                </div>
                <div class="fld span2">
                  <label for="cRate">Apple's cut, for this preview</label>
                  <select id="cRate">
                    <option value="0.70">30%, what Apple takes today</option>
                    <option value="0.85">15%, once the Small Business Program starts</option>
                  </select>
                </div>
              </div>

              <div class="money" aria-live="polite">
                <span class="head">One sale with this code, US buyer</span>
                <div class="line"><span>Buyer pays</span><b id="mBuyer"></b></div>
                <div class="line"><span>Apple sends you</span><b id="mApple"></b></div>
                <div class="line"><span>Creator gets <span id="mShareLabel"></span></span><b class="accent" id="mCreator"></b></div>
                <div class="line total"><span>You keep</span><b id="mKeep"></b></div>
                <span class="fine" id="mPlainNote"></span>
              </div>

              <div class="fld">
                <span class="label">Link the creator shares</span>
                <div class="linkbox">
                  <code id="cLink"></code>
                  <button type="button" class="icon-btn" id="copyLink" aria-label="Copy the link" title="Copy the link">${icon('copy', 14)}</button>
                </div>
                <span class="hint">Opens the App Store with the code filled in, and installs the app first if needed.</span>
              </div>

              <ul class="checks" id="formErrors" aria-live="polite"></ul>
              <div id="ascNote"></div>
              <div class="btn-row">
                <button type="button" class="btn primary big" id="previewBtn">Preview the Apple code</button>
                <button type="button" class="btn ghost" id="saveOnlyBtn">Save without the Apple code</button>
              </div>
              <p class="fine" id="createNote"></p>
            </section>

            <div id="previewBox"></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="banner danger">This page needs JavaScript.</div></noscript>
  <script src="/creators/rules.js"></script>
  <script src="/creators/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderCreatorsPage };
