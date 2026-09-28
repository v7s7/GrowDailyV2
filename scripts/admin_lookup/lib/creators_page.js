'use strict';

/**
 * The Creators page's HTML. The behaviour is ../creators/app.js, and the
 * money and code rules it shares with the server are lib/creators.js
 * (served as /creators/rules.js), both plain files for the reason
 * wording_page.js gives.
 *
 * The simple layout Aziz approved on 2026-09-27: three numbers (owed now,
 * code sales, Apple codes used), one list of creators with Copy link, Pay
 * and a menu on each row, and Add creator as three short steps in a
 * dialog (name and code, the deal, the Apple code), ending on the two
 * links to send. Pay, Change share, their page link, details and Stop
 * open as small dialogs built by the script into #dlg.
 */

const { BASE_STYLES } = require('./render');
const { THEME_STYLES, SHELL_STYLES, SHELL_HEAD, sidebar, topBar, icon } = require('./shell');
const { OFFERS_STYLES } = require('./offers_styles');

function renderCreatorsPage({ projectId = '' } = {}) {
  const add = `<button type="button" class="btn primary lg" id="addBtn" disabled>${icon('plus', 16)}Add creator</button>`;
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
    ${topBar({ title: 'Creators', sub: 'A code for each creator, and what they have earned', live: false, actions: add })}
    <div class="app-content">
      <div class="simple">
        <div id="banners"></div>

        <div class="tiles3">
          <div class="tile">
            <span class="k">Owed now</span>
            <span class="v good" id="tOwed">&hellip;</span>
            <span class="s" id="tOwedSub"></span>
          </div>
          <div class="tile">
            <span class="k">Code sales, 30 days</span>
            <span class="v" id="tSales">&hellip;</span>
            <span class="s" id="tSalesSub"></span>
          </div>
          <div class="tile">
            <span class="k">Apple codes used</span>
            <span class="v"><span id="tOffers">&hellip;</span> <span class="of">of <span id="tOffersMax">10</span></span></span>
            <span class="s" id="tOffersSub"></span>
          </div>
        </div>

        <section class="panel flush" aria-label="Creators">
          <table class="t">
            <thead>
              <tr>
                <th scope="col">Creator</th>
                <th scope="col">Deal</th>
                <th scope="col" class="num">Sales</th>
                <th scope="col" class="num">Earned</th>
                <th scope="col" class="num">Owed</th>
                <th scope="col">Code ends</th>
                <th scope="col"><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody id="creatorRows"><tr class="empty"><td colspan="7">Loading&hellip;</td></tr></tbody>
          </table>
        </section>
        <p class="muted small">Money is Owed 60 days after a sale. Pay by bank, then press Pay. <button type="button" class="link-btn" id="howBtn">How it works</button></p>
      </div>
    </div>
  </div>
</div>

<div class="menu" id="rowMenu" role="menu" hidden></div>

<dialog class="dlg" id="addDialog" aria-labelledby="addTitle">
  <div class="dlg-body">
    <div class="dlg-head">
      <h2 id="addTitle">Add creator</h2>
      <button type="button" class="icon-btn" id="addClose" aria-label="Close">${icon('x', 16)}</button>
    </div>
    <ol class="steps" id="addSteps" aria-label="Steps">
      <li><span class="n">1</span><span>Name and code</span></li>
      <li><span class="n">2</span><span>The deal</span></li>
      <li><span class="n">3</span><span>Apple code</span></li>
    </ol>

    <div id="addPane1">
      <div class="grid2">
        <div class="fld">
          <label for="cName">Creator name</label>
          <input type="text" class="in" id="cName" maxlength="80" placeholder="The name you pay them under" autocomplete="off">
        </div>
        <div class="fld">
          <label for="cCode">Code</label>
          <input type="text" class="in mono" id="cCode" maxlength="64" autocomplete="off" spellcheck="false" autocapitalize="characters" placeholder="SARA">
          <span class="hint">Latin letters and digits.</span>
        </div>
      </div>
      <p class="muted small" style="margin-top: 14px;">Their link: <span id="codeLink" class="faint"></span></p>
    </div>

    <div id="addPane2" hidden>
      <div class="grid2">
        <div class="fld">
          <label for="cOff">Discount for their followers</label>
          <div class="unit-row"><input type="number" class="in num" id="cOff" min="1" max="90" step="1" value="20" inputmode="numeric"><span class="muted">% off Lifetime</span></div>
        </div>
        <div class="fld">
          <label for="cShare">Their share of each sale</label>
          <div class="unit-row"><input type="number" class="in num" id="cShare" min="0" max="100" step="0.5" value="25" inputmode="decimal"><span class="muted">% of what Apple sends you</span></div>
        </div>
        <div class="fld">
          <label for="cUntil">Code ends on</label>
          <input type="date" class="in" id="cUntil">
          <span class="hint">6 months at most.</span>
        </div>
        <div class="fld">
          <label for="cUses">Uses allowed</label>
          <input type="number" class="in" id="cUses" min="1" max="25000" step="1" value="1000" inputmode="numeric">
        </div>
      </div>
      <details class="more" style="margin-top: 14px;">
        <summary>More options</summary>
        <div class="grid2">
          <div class="fld">
            <label for="cBase">Discount off</label>
            <select class="in" id="cBase">
              <option value="growdaily_lifetime">Lifetime</option>
              <option value="growdaily_lifetime_offer">Lifetime offer product</option>
            </select>
          </div>
          <div class="fld">
            <label for="cRate">Apple's cut, for these numbers</label>
            <select class="in" id="cRate">
              <option value="0.70">30%, today</option>
              <option value="0.85">15%, with the Small Business Program</option>
            </select>
          </div>
        </div>
      </details>
      <div class="money4" aria-live="polite" style="margin-top: 14px;">
        <div><span class="k">Buyer pays</span><span class="v" id="mBuyer"></span></div>
        <div><span class="k">Apple sends you</span><span class="v" id="mApple"></span></div>
        <div><span class="k">They get <span id="mShareLabel"></span></span><span class="v accent" id="mCreator"></span></div>
        <div><span class="k">You keep</span><span class="v good" id="mKeep"></span></div>
      </div>
    </div>

    <div id="addPane3" hidden>
      <div class="preview-lines" id="previewBox" aria-live="polite"></div>
    </div>

    <div id="addDone" hidden>
      <div class="done-head">
        <span class="done-mark">${icon('check', 22)}</span>
        <div class="grow">
          <h2 id="doneTitle" style="font-size: 21px;"></h2>
          <p class="muted" id="doneSub"></p>
        </div>
      </div>
      <div id="doneLinks">
      <p style="font-weight: 650; margin: 16px 0 8px;">Send them these two links</p>
      <div class="fld">
        <span class="label">1. The link their followers tap</span>
        <div class="linkbox"><code id="doneLink"></code><button type="button" class="btn sm primary" id="doneCopy">Copy</button></div>
      </div>
      <div class="fld" style="margin-top: 12px;">
        <span class="label">2. Their private earnings page</span>
        <div class="linkbox" id="donePageBox" hidden><code id="donePageLink"></code><button type="button" class="btn sm primary" id="donePageCopy">Copy</button></div>
        <div><button type="button" class="btn sm" id="donePageBtn">Make their page link</button></div>
        <span class="hint">Shown once. Lost it? Make a new one from their row.</span>
      </div>
      </div>
    </div>

    <ul class="checks" id="formErrors" aria-live="polite"></ul>
    <div class="dlg-foot">
      <button type="button" class="btn ghost lg" id="addBack">Back</button>
      <span class="spacer"></span>
      <button type="button" class="btn lg" id="addSaveOnly" hidden>Save without the Apple code</button>
      <button type="button" class="btn primary lg" id="addNext">Next</button>
    </div>
  </div>
</dialog>

<dialog class="dlg narrow" id="dlg" aria-labelledby="dlgTitle">
  <div class="dlg-body" id="dlgBody"></div>
</dialog>

<dialog class="dlg" id="howDialog" aria-labelledby="howTitle">
  <div class="dlg-body">
    <div class="dlg-head">
      <h2 id="howTitle">How creator codes work</h2>
      <button type="button" class="icon-btn" id="howClose" aria-label="Close">${icon('x', 16)}</button>
    </div>
    <ol class="how">
      <li><div><b>Add creator: a name and a code</b><span>Letters and digits, like SARA.</span></div></li>
      <li><div><b>The deal</b><span>Their followers get a discount. They get a share of what Apple sends you, after Apple's cut and VAT.</span></div></li>
      <li><div><b>Make the Apple code</b><span>One press. It uses 1 of your 10 Apple codes.</span></div></li>
      <li><div><b>Send them two links</b><span>The code link their followers tap to buy, and their private earnings page.</span></div></li>
      <li><div><b>Sales count themselves</b><span>Every purchase with the code lands on their row. Refunds come off.</span></div></li>
      <li><div><b>Pay after 60 days</b><span>Money shows as Owed. Pay by bank transfer, then press Pay.</span></div></li>
      <li><div><b>Stop a code</b><span>The menu on their row, then Stop. It is switched off at Apple too.</span></div></li>
    </ol>
    <p class="muted small">Creator codes work on iPhone. Google Play has no discount codes for a one-time purchase.</p>
  </div>
</dialog>

  <div class="toast" id="toast" role="status" aria-live="polite"></div>
  <noscript><div class="notice danger">This page needs JavaScript.</div></noscript>
  <script src="/creators/rules.js"></script>
  <script src="/creators/app.js"></script>
  <script src="/static/shell.js"></script>
</body>
</html>`;
}

module.exports = { renderCreatorsPage };
