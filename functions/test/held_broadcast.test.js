/**
 * The admin's message to everyone, held for quiet hours (page item 6, Aziz,
 * 2026-09-24): someone asleep when it was sent used to never get it.
 *
 * Runs the REAL index.js handlers, holdBroadcast and deliverHeldBroadcast,
 * against an in-memory Firestore, a recording FCM and a recording Cloud
 * Tasks queue, injected in place of firebase-admin before index.js loads.
 * Nothing here reaches Firebase. The rule itself, heldBroadcastPlan, is
 * pinned in push_policy.test.js.
 */

const test = require("node:test");
const assert = require("node:assert");
const Module = require("node:module");
const path = require("node:path");

const FN = path.join(__dirname, "..");

// ── Clock ──────────────────────────────────────────────────────────────────
// 2026-09-24 23:30 in Bahrain (UTC+3): inside the default 22:00-07:00 window.
const SENT = Date.UTC(2026, 8, 24, 20, 30);
let NOW = SENT;
Date.now = () => NOW;

// ── In-memory Firestore ──────────────────────────────────────────────────
class Timestamp {
  constructor(ms) {
    this._ms = ms;
  }
  toMillis() {
    return this._ms;
  }
}
const store = new Map();
const INC = Symbol("increment");
const isMap = (v) => v && typeof v === "object" && !(v instanceof Timestamp) &&
  !Array.isArray(v) && !v[INC];

function merge(base, patch) {
  const out = {...base};
  for (const [k, v] of Object.entries(patch)) {
    if (v && v[INC] !== undefined) {
      out[k] = (typeof out[k] === "number" ? out[k] : 0) + v[INC];
    } else if (isMap(v) && isMap(out[k])) {
      out[k] = merge(out[k], v);
    } else {
      out[k] = v;
    }
  }
  return out;
}
class DocSnap {
  constructor(ref, d) {
    this.ref = ref;
    this.id = ref.id;
    this._d = d;
    this.exists = d !== undefined;
  }
  data() {
    return this._d === undefined ? undefined : {...this._d};
  }
  get(f) {
    return this._d ? this._d[f] : undefined;
  }
}
class DocRef {
  constructor(p) {
    this.path = p;
    this.id = p.split("/").pop();
  }
  collection(n) {
    return new ColRef(this.path + "/" + n);
  }
  async get() {
    return new DocSnap(this, store.get(this.path));
  }
  async set(d, o) {
    store.set(this.path, o && o.merge ?
      merge(store.get(this.path) || {}, d) : merge({}, d));
  }
  async update(d) {
    if (!store.has(this.path)) throw new Error("NOT_FOUND " + this.path);
    store.set(this.path, merge(store.get(this.path), d));
  }
  async delete() {
    store.delete(this.path);
  }
}
class ColRef {
  constructor(p) {
    this.path = p;
  }
  doc(id) {
    return new DocRef(this.path + "/" + id);
  }
  async get() {
    const pre = this.path + "/";
    const docs = [...store.keys()]
        .filter((k) => k.startsWith(pre) && !k.slice(pre.length).includes("/"))
        .sort().map((k) => new DocSnap(new DocRef(k), store.get(k)));
    return {docs, empty: docs.length === 0, size: docs.length};
  }
}
const db = {
  collection: (n) => new ColRef(n),
  runTransaction: async (fn) => fn({
    get: (ref) => ref.get(),
    set: (ref, d, o) => {
      ref.set(d, o);
    },
  }),
};

// ── firebase-admin and Cloud Tasks stand-ins ───────────────────────────────
const sent = [];
const enqueued = [];
const firestoreFn = () => db;
firestoreFn.FieldValue = {
  arrayUnion: (...v) => ({__arrayUnion: v}),
  serverTimestamp: () => new Timestamp(NOW),
  increment: (n) => ({[INC]: n}),
};
firestoreFn.Timestamp = Timestamp;
const adminMock = {
  initializeApp() {},
  firestore: firestoreFn,
  messaging: () => ({
    send: async (m) => {
      sent.push(m);
      return "ok";
    },
  }),
};
const tasksMock = {
  getFunctions: () => ({
    taskQueue: (name) => ({
      enqueue: async (data, opts) => {
        enqueued.push({name, data, opts});
      },
    }),
  }),
};
function inject(id, exp) {
  const file = Module._resolveFilename(id, {
    id: FN + "/index.js",
    filename: FN + "/index.js",
    paths: Module._nodeModulePaths(FN),
  });
  require.cache[file] = {id: file, filename: file, loaded: true, exports: exp};
}
inject("firebase-admin", adminMock);
inject("firebase-admin/functions", tasksMock);

// The functions log JSON lines; kept off the test output.
const origOut = process.stdout.write.bind(process.stdout);
process.stdout.write = (chunk, ...rest) =>
  (/^\{"/.test(String(chunk)) ? true : origOut(chunk, ...rest));
const origErr = process.stderr.write.bind(process.stderr);
process.stderr.write = (chunk, ...rest) =>
  (/^\{"/.test(String(chunk)) ? true : origErr(chunk, ...rest));

const fns = require(FN + "/index.js");

// ── The world ──────────────────────────────────────────────────────────────
const ID = "n_mfy2abcd_0a1b2c";
const QUIET_END = Date.UTC(2026, 8, 25, 4, 2); // 07:02 in Bahrain

function reset() {
  store.clear();
  sent.length = 0;
  enqueued.length = 0;
  NOW = SENT;
  store.set("broadcast_log/" + ID, {
    kind: "notification",
    audience: "everyone",
    titleAr: "تحديث جديد",
    bodyAr: "صار عندك تذكير لكل صلاة.",
    titleEn: "New update",
    bodyEn: "Every prayer can have its own reminder now.",
    at: new Timestamp(SENT),
    held: [
      {uid: "sleeperAr", atMs: QUIET_END},
      {uid: "sleeperEn", atMs: QUIET_END},
    ],
  });
  store.set("users/sleeperAr", {locale: "ar", tzOffsetMinutes: 180});
  store.set("users/sleeperAr/fcmTokens/tokAr",
      {updatedAt: new Timestamp(SENT)});
  store.set("users/sleeperEn", {locale: "en", tzOffsetMinutes: 180});
  store.set("users/sleeperEn/fcmTokens/tokEn",
      {updatedAt: new Timestamp(SENT)});
}

const row = () => store.get("broadcast_log/" + ID);

test("holdBroadcast queues one delivery per held person, once", async () => {
  reset();
  const first = await fns.holdBroadcast.run({data: {id: ID}});
  assert.deepStrictEqual(first, {queued: 2, failed: 0});
  assert.deepStrictEqual(enqueued.map((e) => e.name),
      ["deliverHeldBroadcast", "deliverHeldBroadcast"]);
  assert.deepStrictEqual(enqueued.map((e) => e.data.uid),
      ["sleeperAr", "sleeperEn"]);
  assert.strictEqual(enqueued[0].data.id, ID);
  assert.strictEqual(enqueued[0].opts.scheduleDelaySeconds,
      Math.round((QUIET_END - SENT) / 1000),
  "timed for the end of their quiet hours");
  assert.ok(row().heldQueuedAt, "marked, so it cannot be queued again");

  const again = await fns.holdBroadcast.run({data: {id: ID}});
  assert.deepStrictEqual(again, {queued: 0, failed: 0});
  assert.strictEqual(enqueued.length, 2);
});

test("holdBroadcast queues nothing but the admin's own message to everyone",
    async () => {
      reset();
      await assert.rejects(fns.holdBroadcast.run({data: {id: "../users"}}),
          (e) => e.code === "invalid-argument");
      await assert.rejects(
          fns.holdBroadcast.run({data: {id: "n_zzzz_ffffff"}}),
          (e) => e.code === "not-found");
      store.set("broadcast_log/" + ID, {...row(), audience: "test"});
      assert.deepStrictEqual(
          await fns.holdBroadcast.run({data: {id: ID}}),
          {queued: 0, failed: 0});
      assert.strictEqual(enqueued.length, 0);
    });

test("at 07:02 each gets it in their own language, and it is counted",
    async () => {
      reset();
      NOW = QUIET_END;
      await fns.deliverHeldBroadcast.run({data: {v: 1, id: ID, uid: "sleeperAr"}});
      await fns.deliverHeldBroadcast.run({data: {v: 1, id: ID, uid: "sleeperEn"}});
      assert.deepStrictEqual(sent.map((m) => [m.token, m.notification.title]),
          [["tokAr", "تحديث جديد"], ["tokEn", "New update"]]);
      assert.deepStrictEqual(sent[0].data, {type: "broadcast", id: ID});
      assert.strictEqual(sent[0].android.ttl, 12 * 60 * 60 * 1000);
      assert.strictEqual(sent[0].apns.headers["apns-expiration"],
          String(Math.floor((QUIET_END + 12 * 60 * 60 * 1000) / 1000)));
      assert.deepStrictEqual(sent[0].apns.payload, {aps: {sound: "default"}});
      assert.strictEqual(row().heldSent, 2);
    });

test("decided afresh when it lands: switched off, still quiet, or too late",
    async () => {
      reset();
      store.set("users/sleeperAr", {
        locale: "ar", tzOffsetMinutes: 180,
        notificationSettings: {masterEnabled: false},
      });
      NOW = QUIET_END;
      await fns.deliverHeldBroadcast.run({data: {v: 1, id: ID, uid: "sleeperAr"}});
      assert.strictEqual(sent.length, 0, "switched every notification off");

      // Their window moved after it was held: still quiet at 07:02.
      store.set("users/sleeperEn", {
        locale: "en", tzOffsetMinutes: 180,
        notificationSettings: {
          quietHoursEnabled: true, quietHoursStart: "22:0", quietHoursEnd: "9:0",
        },
      });
      await fns.deliverHeldBroadcast.run({data: {v: 1, id: ID, uid: "sleeperEn"}});
      assert.strictEqual(sent.length, 0, "not chased into the day");

      // A delivery that somehow lands a day late.
      store.set("users/sleeperEn", {locale: "en", tzOffsetMinutes: 180});
      NOW = SENT + 25 * 60 * 60 * 1000;
      await fns.deliverHeldBroadcast.run({data: {v: 1, id: ID, uid: "sleeperEn"}});
      assert.strictEqual(sent.length, 0, "never after the next message could go");
      assert.strictEqual(row().heldDropped, 3);
    });
