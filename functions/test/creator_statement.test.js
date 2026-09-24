/**
 * A creator's own statement (creator_statement.js): the numbers on the
 * private page each creator opens from their link.
 *
 * Two promises are pinned here. The creator sees exactly the numbers Aziz
 * sees on the admin tool's Creators page, so the admin tool's own sums
 * (scripts/admin_lookup/lib/creators.js) are run on the same rows and must
 * agree, on hand-made cases and on a thousand random ledgers. And the page
 * never shows a buyer: no account id, no store transaction id.
 */

const test = require("node:test");
const assert = require("node:assert");
const crypto = require("crypto");
const {
  OWED_AFTER_DAYS,
  RECENT_LIMIT,
  bahrainMonthKey,
  buildStatement,
  shareLinkFor,
  statementKeyHash,
} = require("../creator_statement");
const AdminCreators = require("../../scripts/admin_lookup/lib/creators");
const AdminCreatorsServer =
  require("../../scripts/admin_lookup/lib/creators_admin");

const NOW = Date.UTC(2026, 8, 24, 9, 0);
const DAY = 86400000;
const UID = "5rLsgWgriLa7qaRDeZ3wdPfHgQl2";

const SARA = {
  name: "Sara",
  code: "SARA",
  offerRef: "creator-sara",
  sharePercent: 25,
  discountPercent: 20,
  offerPriceUsd: 23.99,
  active: true,
  codeEndsAt: {toMillis: () => NOW + 120 * DAY},
  appleOfferCodeId: "O1",
  appleCustomCodeId: "C1",
  statementKeyHash: "x",
};

let seq = 0;
/** One creator_ledger row as the webhook writes it. */
function row(kind, shareUsd, ageDays, over) {
  seq += 1;
  return Object.assign({
    creatorId: "SARA",
    offerRef: "creator-sara",
    kind,
    productId: "growdaily_lifetime_offer",
    store: "APP_STORE",
    environment: "PRODUCTION",
    priceUsd: kind === "refund" ? -23.99 : 23.99,
    taxPct: 0,
    commissionPct: 0.3,
    netUsd: kind === "refund" ? -16.79 : 16.79,
    sharePct: 25,
    shareUsd,
    needsReview: false,
    eventAtMs: NOW - ageDays * DAY,
    appUserId: UID,
    transactionId: "20000009" + String(seq).padStart(8, "0"),
  }, over);
}

function statementOf(ledger, payouts = []) {
  return buildStatement({
    id: "SARA", creator: SARA, ledger, payouts, nowMs: NOW,
  });
}

function adminSums(ledger, payouts = []) {
  return AdminCreators.creatorTotals({
    creators: [{id: "SARA"}], ledger, payouts, nowMs: NOW,
  }).rows[0];
}

// ---- The key ---------------------------------------------------------------

test("a statement key hashes the same here as in the admin tool", () => {
  for (let i = 0; i < 50; i++) {
    const key = crypto.randomBytes(32).toString("base64url");
    assert.strictEqual(key.length, 43);
    assert.strictEqual(statementKeyHash(key),
        AdminCreatorsServer.statementKeyHash(key));
    assert.strictEqual(statementKeyHash(key),
        crypto.createHash("sha256").update(key).digest("hex"));
  }
  const made = AdminCreatorsServer.newStatementKey();
  assert.ok(statementKeyHash(made), "a key the admin tool makes is accepted");
});

test("anything that is not a well-formed key is refused before any lookup",
    () => {
      for (const bad of [
        undefined, null, 42, {}, [], "", "short",
        "A".repeat(42), "A".repeat(44), "A".repeat(42) + "=",
        "A".repeat(42) + "/", "A".repeat(42) + " ", "A".repeat(42) + "é",
      ]) {
        assert.strictEqual(statementKeyHash(bad), null, String(bad));
      }
    });

// ---- The money agrees with the admin tool ----------------------------------

test("earned, paid, ready and on hold match the Creators page", () => {
  const ledger = [
    row("sale", 4.2, 90),
    row("sale", 4.2, 70),
    row("sale", 4.2, 10),
  ];
  const payouts = [{creatorId: "SARA", amountUsd: 5, paidAt: NOW - DAY}];
  const s = statementOf(ledger, payouts);
  const a = adminSums(ledger, payouts);
  assert.deepStrictEqual(s.money, {
    earnedCents: 1260,
    paidCents: 500,
    owedCents: 340,
    waitingCents: 420,
    nextReadyAtMs: NOW - 10 * DAY + OWED_AFTER_DAYS * DAY,
  });
  assert.strictEqual(a.earnedCents, s.money.earnedCents);
  assert.strictEqual(a.paidCents, s.money.paidCents);
  assert.strictEqual(a.owedCents, s.money.owedCents);
  assert.strictEqual(a.waitingCents, s.money.waitingCents);
});

test("the two agree on a thousand random ledgers", () => {
  // A small seeded generator, so a failure can be replayed.
  let state = 20260924;
  const rand = () => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648;
  };
  for (let run = 0; run < 1000; run++) {
    const ledger = [];
    const sales = [];
    const n = Math.floor(rand() * 12);
    for (let i = 0; i < n; i++) {
      const age = Math.floor(rand() * 200);
      const share = Math.round(rand() * 800) / 100;
      const extra = {};
      const r = rand();
      if (r < 0.1) extra.environment = "SANDBOX";
      else if (r < 0.2) Object.assign(extra, {needsReview: true, shareUsd: null});
      else if (r < 0.25) extra.creatorId = "OTHER";
      const sale = row("sale", share, age, extra);
      ledger.push(sale);
      sales.push(sale);
    }
    for (const sale of sales) {
      if (rand() < 0.25) {
        const refundAge = Math.floor(rand() * 60);
        // Refunds are written negative by the webhook; unsigned must agree.
        const signed = rand() < 0.8 ? -1 : 1;
        ledger.push(row("refund", sale.shareUsd === null ?
          null : signed * sale.shareUsd, refundAge, {
          transactionId: sale.transactionId,
          creatorId: sale.creatorId,
          environment: sale.environment,
          needsReview: sale.needsReview,
        }));
      }
    }
    if (rand() < 0.1) {
      // A refund of a sale the ledger never saw ages from its own date.
      ledger.push(row("refund", -Math.round(rand() * 500) / 100,
          Math.floor(rand() * 90)));
    }
    const payouts = [];
    const p = Math.floor(rand() * 3);
    for (let i = 0; i < p; i++) {
      payouts.push({
        creatorId: rand() < 0.9 ? "SARA" : "OTHER",
        amountUsd: Math.round(rand() * 2000) / 100,
        paidAt: NOW - Math.floor(rand() * 100) * DAY,
      });
    }
    const s = statementOf(ledger, payouts);
    const a = adminSums(ledger, payouts);
    const label = "run " + run;
    assert.strictEqual(s.money.earnedCents, a.earnedCents, label);
    assert.strictEqual(s.money.paidCents, a.paidCents, label);
    assert.strictEqual(s.money.owedCents, a.owedCents, label);
    assert.strictEqual(s.money.waitingCents, a.waitingCents, label);
    assert.strictEqual(s.counts.sales, a.sales, label);
    assert.strictEqual(s.counts.refunds, a.refunds, label);
    assert.strictEqual(s.counts.sales30, a.sales30, label);
    assert.strictEqual(s.counts.refunds30, a.refunds30, label);
    assert.strictEqual(s.counts.needsReview, a.needsReview, label);
    if (s.money.earnedCents >= s.money.paidCents) {
      assert.strictEqual(s.money.paidCents + s.money.owedCents +
        s.money.waitingCents, s.money.earnedCents, label);
    }
  }
});

// ---- What the page lists ---------------------------------------------------

test("each row says where it stands, and a refund points back at its sale",
    () => {
      const old = row("sale", 4.2, 75);
      const young = row("sale", 4.2, 12);
      const gone = row("sale", 4.2, 40);
      const back = row("refund", -4.2, 20, {transactionId: gone.transactionId});
      const unknown = row("sale", null, 5, {needsReview: true});
      const s = statementOf([old, young, gone, back, unknown]);
      const byAge = new Map(s.recent.map((r) => [Math.round((NOW - r.atMs) / DAY), r]));
      assert.strictEqual(byAge.get(75).status, "cleared");
      assert.strictEqual(byAge.get(75).readyAtMs, null);
      assert.strictEqual(byAge.get(12).status, "waiting");
      assert.strictEqual(byAge.get(12).readyAtMs, NOW + 48 * DAY);
      assert.strictEqual(byAge.get(40).status, "refunded");
      assert.strictEqual(byAge.get(20).status, "refund");
      assert.strictEqual(byAge.get(20).shareCents, -420);
      assert.strictEqual(byAge.get(5).status, "review");
      assert.strictEqual(byAge.get(5).shareCents, null);
      // Newest first.
      assert.deepStrictEqual(s.recent.map((r) => r.atMs),
          [...s.recent.map((r) => r.atMs)].sort((x, y) => y - x));
      // The refunded sale never counts as the next money to come in.
      assert.strictEqual(s.money.nextReadyAtMs, NOW + 48 * DAY);
    });

test("no buyer is ever in the statement", () => {
  const ledger = [row("sale", 4.2, 3), row("sale", 4.2, 90)];
  const json = JSON.stringify(statementOf(ledger));
  assert.ok(!json.includes(UID), "no account id");
  for (const r of ledger) {
    assert.ok(!json.includes(r.transactionId), "no store transaction id");
  }
  assert.ok(!json.includes("statementKeyHash"));
  assert.ok(!json.includes("offerRef"));
});

test("sandbox rows and other creators' rows stay out", () => {
  const s = statementOf([
    row("sale", 4.2, 3),
    row("sale", 9.99, 3, {environment: "SANDBOX"}),
    row("sale", 9.99, 3, {creatorId: "OTHER"}),
  ]);
  assert.strictEqual(s.counts.sales, 1);
  assert.strictEqual(s.money.earnedCents, 420);
  assert.strictEqual(s.recent.length, 1);
});

test("months are Bahrain months, newest first, net of refunds", () => {
  // 30 September 22:00 UTC is 1 October 01:00 in Bahrain.
  const lateSept = Date.UTC(2026, 8, 30, 22, 0);
  assert.strictEqual(bahrainMonthKey(lateSept), "2026-10");
  assert.strictEqual(bahrainMonthKey(Date.UTC(2026, 8, 30, 20, 59)),
      "2026-09");
  const s = buildStatement({
    id: "SARA",
    creator: SARA,
    ledger: [
      row("sale", 4.2, 0, {eventAtMs: lateSept, transactionId: "T1"}),
      row("sale", 4.2, 0, {eventAtMs: Date.UTC(2026, 8, 10), transactionId: "T2"}),
      row("refund", -4.2, 0, {eventAtMs: Date.UTC(2026, 8, 12), transactionId: "T2"}),
    ],
    payouts: [],
    nowMs: Date.UTC(2026, 9, 5),
  });
  assert.deepStrictEqual(s.months, [
    {month: "2026-10", sales: 1, refunds: 0, shareCents: 420},
    {month: "2026-09", sales: 1, refunds: 1, shareCents: 0},
  ]);
});

test("payouts are listed newest first with the note Aziz wrote", () => {
  const s = statementOf([row("sale", 30, 100)], [
    {creatorId: "SARA", amountUsd: 10, paidAt: {toMillis: () => NOW - 30 * DAY},
      note: "Transfer 1"},
    {creatorId: "SARA", amountUsd: 12.5, paidAt: {toMillis: () => NOW - DAY},
      note: "Transfer 2"},
    {creatorId: "OTHER", amountUsd: 99, paidAt: {toMillis: () => NOW}},
  ]);
  assert.deepStrictEqual(s.payouts, [
    {paidAtMs: NOW - DAY, amountCents: 1250, note: "Transfer 2"},
    {paidAtMs: NOW - 30 * DAY, amountCents: 1000, note: "Transfer 1"},
  ]);
  assert.strictEqual(s.money.paidCents, 2250);
  assert.strictEqual(s.money.owedCents, 750);
});

test("the deal on the page: code, link, share and whether the code still works",
    () => {
      const s = statementOf([]);
      assert.deepStrictEqual(s.creator, {
        name: "Sara",
        code: "SARA",
        sharePercent: 25,
        discountPercent: 20,
        offerPriceUsd: 23.99,
        codeEndsAtMs: NOW + 120 * DAY,
        codeEnded: false,
        active: true,
        hasAppleCode: true,
        shareLink: "https://apps.apple.com/redeem?ctx=offercodes&id=6788149393&code=SARA",
      });
      assert.strictEqual(s.money.nextReadyAtMs, null, "nothing waiting");
      assert.strictEqual(shareLinkFor("SARA"),
          AdminCreators.shareLinkFor("SARA"), "the same link the admin shows");
      const ended = buildStatement({
        id: "OLD1",
        creator: {name: "Old", codeEndsAt: {toMillis: () => NOW - DAY}},
        ledger: [], payouts: [], nowMs: NOW,
      });
      assert.strictEqual(ended.creator.codeEnded, true);
      assert.strictEqual(ended.creator.code, "OLD1", "the id stands in for a missing code");
      assert.strictEqual(ended.creator.hasAppleCode, false);
    });

test("the list stops at the newest " + RECENT_LIMIT + " rows; the totals do not",
    () => {
      const many = Array.from({length: RECENT_LIMIT + 15},
          (_, i) => row("sale", 1, 100 + i));
      const s = statementOf(many);
      assert.strictEqual(s.recent.length, RECENT_LIMIT);
      assert.strictEqual(s.counts.sales, RECENT_LIMIT + 15);
      assert.strictEqual(s.money.earnedCents, (RECENT_LIMIT + 15) * 100);
    });

test("the hold matches the admin tool's", () => {
  assert.strictEqual(OWED_AFTER_DAYS, AdminCreators.OWED_AFTER_DAYS);
});
