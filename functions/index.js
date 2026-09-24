/**
 * Grow Daily Cloud Functions.
 *
 * The room-finish push notification's server half — see
 * lib/core/services/push_notification_service.dart for the client half, and
 * lib/features/settings/models/notification_settings.dart's
 * roomActivityEnabled doc comment for the feature end to end. This is the
 * ONE server-side component this app has; everything else the app does
 * (habit reminders, the evening note, celebrations) is scheduled or shown
 * entirely on-device by NotificationService, with no backend involved at
 * all.
 *
 * Every push sent from here is caused by a PERSON DOING SOMETHING: someone
 * finishing their day, or a room's habit being added. Nothing fires from
 * inactivity. The one exception was the evening reminder to a room where
 * nobody had finished yet, removed on 2026-09-16 (Aziz) as part of cutting
 * notification spam. Keep it that way: a push nobody's action caused has to
 * justify itself against the evening note the app already sends.
 *
 * Originally a Firestore-triggered function (onDocumentWritten on
 * rooms/{code}/participants/{uid}), edge-detected off allDoneToday flipping
 * false -> true. That was abandoned after a real, confirmed deploy-time
 * wall: a Firestore trigger's Eventarc plumbing MUST live in the exact same
 * region as the Firestore database itself (me-central2 here, firebase.json's
 * "firestore.location" - Eventarc has no cross-region option for Firestore
 * triggers), and creating any resource in me-central2 for this project
 * returns 403 "Permission denied on 'locations/me-central2' (or it may not
 * exist)" - reproduced repeatedly, with a confirmed-correct Owner account,
 * not fixed by retrying. Since the function's own region can't be chosen
 * independently of the trigger's forced region for a Firestore trigger, no
 * region choice could have worked around this.
 *
 * This is now a plain HTTPS Callable function instead - notifyRoomFinish,
 * called directly by RoomsController (_notifyRoomFinish in
 * rooms_notifier.dart) the instant this device's own write flips
 * allDoneToday to true for today, rather than something watching Firestore
 * for that change. Callable functions have no Eventarc trigger at all, so
 * they deploy to any working region - us-central1, confirmed to work for
 * this project. Everyone else in the room still gets pushed, except the
 * finisher themselves, anyone who's muted this specific room, and anyone
 * whose account-level settings say no (master switch off, this category
 * off, or it's currently inside their quiet hours) — see [isEligible] below.
 *
 * Trusting the caller: the callable only ever acts on the CALLER's own
 * participant doc (request.auth.uid, Firebase Auth-verified by the callable
 * framework itself), and re-reads allDoneToday/allDoneDate from Firestore
 * server-side before sending anything rather than trusting request.data's
 * claim - the same doc a caller could only have gotten into this state on by
 * already being isOwner(uid) under firestore.rules. There's no way to spoof
 * "someone else finished," or "I finished" when the stored doc disagrees.
 */

const {onCall, HttpsError, onRequest} =
    require("firebase-functions/v2/https");
const {onTaskDispatched} = require("firebase-functions/v2/tasks");
const {defineSecret} = require("firebase-functions/params");
const crypto = require("crypto");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {getFunctions} = require("firebase-admin/functions");
const {
  isRoomPausedOn,
  roomEventFor,
  slotPendingFor,
} = require("./room_events");
const {lastOneCounts, roomPushMessage} = require("./room_messages");
const {
  claimQuota,
  heldBroadcastPlan,
  heldUntilMs,
  isQuietHoursNow,
  liveTokens,
  localDayKey,
  pushKindFor,
  roomPushPlan,
} = require("./push_policy");
const {
  clipSpansToPast,
  closedDaysToCheck,
  countingHabitIds,
  todayKeyIn,
  undercountedDays,
} = require("./room_health");
const {
  isProduction,
  premiumFromCustomerInfo,
  shouldWrite,
  uidsToRefresh,
} = require("./revenuecat_webhook");
const {
  factDocId,
  ledgerRowFor,
  offerRefOf,
  purchaseKindOf,
  purchaseLogRow,
  saleLookupKeys,
} = require("./purchase_facts");

/**
 * The shared secret RevenueCat sends as the Authorization header. Set with
 * `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET`.
 */
const revenueCatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

/**
 * A RevenueCat SECRET API key (sk_, created for API v1), used only to read
 * a customer's record back after a webhook. See uidsToRefresh in
 * revenuecat_webhook.js for why the event alone cannot be trusted.
 *
 * Secret, not the public SDK key the apps ship: RevenueCat says secret keys
 * are project-wide and belong on servers, and this one never leaves Secret
 * Manager. It can also grant and delete, so it is never logged.
 *
 * DEPLOY ORDER MATTERS. The Firebase CLI resolves every declared secret
 * before it picks which functions to deploy, so until this secret exists
 * even `--only functions:notifyRoomFinish` stops at a masked prompt.
 */
const revenueCatApiKey = defineSecret("REVENUECAT_API_KEY");

/**
 * GET /v1/subscribers/{uid}: RevenueCat's own answer for this customer.
 *
 * No X-Platform header, as RevenueCat asks for informational reads, so this
 * never moves the customer's last_seen. The timeout keeps one slow call
 * well inside RevenueCat's 60 second delivery window; a throw becomes a 500
 * and RevenueCat retries the whole event, which re-reading makes safe.
 */
async function fetchCustomerInfo(uid, apiKey) {
  const url = "https://api.revenuecat.com/v1/subscribers/" +
      encodeURIComponent(uid);
  const res = await fetch(url, {
    headers: {Authorization: `Bearer ${apiKey}`},
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) {
    throw new Error(`RevenueCat GET subscribers answered ${res.status}`);
  }
  return res.json();
}

/**
 * Constant-time string compare, so a wrong Authorization header cannot be
 * discovered a byte at a time by timing the response. Length is compared
 * first because timingSafeEqual throws on a length mismatch; the length of
 * a secret is not the secret.
 */
function timingSafeEqualStr(a, b) {
  const ab = Buffer.from(String(a), "utf8");
  const bb = Buffer.from(String(b), "utf8");
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

admin.initializeApp();
const db = admin.firestore();

// us-central1: the oldest, most universally-supported Cloud Functions
// region - chosen after me-central2 (this project's own Firestore
// location) turned out to reject resource creation outright for this
// project (see this file's top doc comment). A callable function has no
// Eventarc trigger tying it to Firestore's own region, so this cross-region
// read to Firestore just adds a few ms to an RPC nobody's blocked on
// synchronously - functionally identical to same-region either way.
setGlobalOptions({region: "us-central1", maxInstances: 10});

/**
 * ── The three room events ─────────────────────────────────────────────
 *
 * A room notifies on distinct EVENTS, not once per person who finishes.
 *
 * The per-finisher model this replaced had three problems, and only the
 * first was about volume:
 *
 *  1. It was quadratic. Every member finishing notified every other
 *     member, so an N-person room where everyone finishes sends
 *     N x (N-1) pushes a day: 30 at six people, ~39,800 at two hundred.
 *  2. Capping it moved the cliff rather than removing it. Any "small
 *     rooms fan out, big rooms don't" rule means one member joining can
 *     drop a room from N-1 pushes to 1 overnight.
 *  3. Most of it said nothing. In a five-person room you received four
 *     messages all reading "someone finished, your turn". The second,
 *     third and fourth carried no information the first hadn't.
 *
 * So the unit is the event, and there are exactly three a day:
 *
 *   A. FIRST_TODAY   - someone opened the day. Goes to everyone still
 *                      unfinished. Answers "is anyone moving today",
 *                      which is the only thing the 2nd-Nth finisher was
 *                      ever really telling you.
 *   B. LAST_ONE      - everyone except one person is done. Goes to that
 *                      one person, and to nobody else. This is the only
 *                      genuinely actionable message in the whole system,
 *                      and giving it its own event is what stops it
 *                      losing a race for a shared daily slot against
 *                      messages that merely inform.
 *   C. ROOM_PERFECT  - every member finished. Goes to everyone. Rare by
 *                      construction, and the one worth interrupting for.
 *
 * They are mutually exclusive per finish and each is claimed once per room
 * per day (see claimRoomEvent), so a room emits at most three pushes per
 * member per day at ANY size. Two people or two hundred, the numbers are
 * the same, which is why there is no member limit in this file any more.
 *
 * Every word of every room push lives in room_messages.js (roomPushMessage),
 * where it is tested. All three are only sent while the reader is still on
 * the day they are about, and never held past it: news about yesterday
 * gives the reader nothing to do (Aziz, 2026-09-24). See push_policy.js
 * roomPushPlan.
 *
 * The opt-in playful variant of B («الكل خلّص في "X" 👀 / باقي أنت.», the
 * roomNudgesEnabled switch) was removed on 2026-09-24: nobody had it on, and
 * it was the last push still wording the reader as the one behind.
 */

/**
 * Whether this recipient still has room for a push of [kind] on [dayKey],
 * spending the slot when they do. See push_policy.js for the three kinds
 * and why they are capped separately: one heads-up, one nudge and one
 * celebration per person per day, so a morning "first to finish" can never
 * use up the evening "you're the last one", and neither can silence a
 * "perfect day".
 *
 * Kept in a transaction because a person in several rooms can legitimately
 * be sent to by two finishers in different rooms at the same moment, and a
 * plain read-modify-write would let both through.
 *
 * `dayKey` is the day the push counts against, roomPushPlan's quotaDay: the
 * day the push is ABOUT, on the recipient's clock, and never the day it
 * lands on. A push held overnight used to spend the next morning's slot, so
 * yesterday's news capped today's real push (نور, 2026-09-24).
 * @param {string} otherUid The recipient.
 * @param {string} dayKey "YYYY-MM-DD".
 * @param {string} kind "info", "nudge" or "celebrate", see pushKindFor.
 * @return {Promise<boolean>} Whether a push may be sent.
 */
async function claimPushSlot(otherUid, dayKey, kind) {
  const ref = db.collection("users").doc(otherUid);
  try {
    return await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      const decision =
        claimQuota((snap.data() || {}).roomPushQuota, dayKey, kind);
      if (!decision.allowed) return false;
      txn.set(ref, {roomPushQuota: decision.next}, {merge: true});
      return true;
    });
  } catch (err) {
    // A failed claim must not silence the room: fall back to sending. The
    // cap is a courtesy, not a correctness guarantee.
    logger.warn("push quota claim failed", otherUid, err);
    return true;
  }
}

/**
 * @return {Promise<{eligible: boolean, locale: string, tzOffsetMinutes:
 *     (number|undefined), reason: (string|undefined), settings:
 *     (object|undefined)}>} `reason` is only set when ineligible, and is
 *     "muted" | "master-off" | "room-off" | "no-user" | "quiet-hours".
 *     `settings` and `tzOffsetMinutes` come back on the "quiet-hours"
 *     reason too (not just when eligible) — the only reason a caller ever
 *     needs them for an ineligible person, to schedule deferRoomPush.
 */
async function isEligible(otherUid, participantData) {
  if (participantData.notificationsMuted === true) {
    return {eligible: false, locale: "en", reason: "muted"};
  }
  const userSnap = await db.collection("users").doc(otherUid).get();
  if (!userSnap.exists) {
    return {eligible: false, locale: "en", reason: "no-user"};
  }
  const user = userSnap.data() || {};
  const settings = user.notificationSettings;
  const locale = user.locale === "ar" ? "ar" : "en";

  if (settings && settings.masterEnabled === false) {
    return {eligible: false, locale, reason: "master-off"};
  }
  if (settings && settings.roomActivityEnabled === false) {
    return {eligible: false, locale, reason: "room-off"};
  }
  if (isQuietHoursNow(settings, user.tzOffsetMinutes)) {
    // Not dropped: see deferRoomPush. Only THIS reason carries settings
    // and the offset back on the ineligible path, because only this
    // reason is ever retried rather than simply skipped.
    return {
      eligible: false, locale, reason: "quiet-hours",
      settings, tzOffsetMinutes: user.tzOffsetMinutes,
    };
  }
  // The daily cap is claimed by the CALLER, after it has confirmed this
  // person actually has a device to receive on. Claiming it here would
  // spend a slot on an undeliverable push.
  return {eligible: true, locale, tzOffsetMinutes: user.tzOffsetMinutes};
}

/**
 * Epoch milliseconds of a Firestore Timestamp, or null.
 * @param {*} v A stored field.
 * @return {?number}
 */
function millisOf(v) {
  return v && typeof v.toMillis === "function" ? v.toMillis() : null;
}

/**
 * The device tokens a push to [uid] goes to.
 *
 * A token left behind by an install the person no longer uses is deleted
 * here instead of sent to (push_policy.js liveTokens): one person, one
 * banner, not one per install they ever had.
 * @param {string} uid The recipient.
 * @return {Promise<Array>} Their live fcmTokens docs.
 */
async function deliverableTokens(uid) {
  const snap = await db.collection("users").doc(uid)
      .collection("fcmTokens").get();
  const {live, stale} = liveTokens(snap.docs.map(
      (doc) => ({doc, updatedAtMs: millisOf(doc.get("updatedAt"))})));
  if (stale.length > 0) {
    await Promise.all(stale.map((t) => t.doc.ref.delete().catch(() => {})));
    logger.info("pruned stale device tokens",
        {uid, pruned: stale.length, kept: live.length});
  }
  return live.map((t) => t.doc);
}

/**
 * Sends one notification to each of [tokenDocs]. A token FCM calls
 * unregistered or invalid (the app was deleted, the token rotated) is
 * deleted so it stops being tried; any other error (offline, transient)
 * leaves it in place for next time.
 *
 * FirebaseError exposes the code directly as `.code` (e.g.
 * "messaging/registration-token-not-registered"), verified against
 * firebase-admin-node's own source. `errorInfo` is where that code
 * originates internally, not a property the public error exposes, so
 * checking it would never match anything.
 *
 * [ttlMs], when given, is how long FCM may hold the message for a phone that
 * is off: past it, the message is dropped rather than delivered late. The
 * admin's messages carry one (see deliverHeldBroadcast); room pushes do not.
 * @param {string} uid The recipient, for the log.
 * @param {Array} tokenDocs From deliverableTokens.
 * @param {{title: string, body: string, data: object, ttlMs: number=}} message
 * @return {Array<Promise>} One per token.
 */
function sendToTokens(uid, tokenDocs, {title, body, data, ttlMs}) {
  const expiry = typeof ttlMs === "number" ? {
    android: {ttl: ttlMs},
    apnsHeaders: {
      "apns-expiration": String(Math.floor((Date.now() + ttlMs) / 1000)),
    },
  } : null;
  return tokenDocs.map((tokenDoc) => admin.messaging().send({
    token: tokenDoc.id,
    notification: {title, body},
    data,
    ...(expiry ? {android: expiry.android} : {}),
    apns: {
      ...(expiry ? {headers: expiry.apnsHeaders} : {}),
      payload: {aps: {sound: "default"}},
    },
  }).catch((err) => {
    const code = err && err.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      return tokenDoc.ref.delete().catch(() => {});
    }
    logger.warn("room push failed", {code, uid});
    return null;
  }));
}

/**
 * Queues one held push for the minute [p.otherUid]'s quiet hours end.
 *
 * Deliberately a single scheduled Cloud Task, not a periodic sweep polling
 * "is anyone's quiet hours over yet" every few minutes forever: that would
 * cost something (however small) around the clock whether or not a push is
 * ever actually waiting, and would need re-tuning as the number of rooms
 * grows. One task per held push costs nothing when nothing is held, which
 * is true most of every day. See msUntilQuietHoursEnd's own doc comment.
 *
 * The task carries what the push is ABOUT (room, event, day, finisher or
 * slot), never its words: deliverDeferredRoomPush decides afresh whether it
 * is still true and words it for the moment it lands. The first version
 * carried a finished title and body, and delivered «سوي عادتك الحين» to نور
 * at 07:02 on 24 Sep about a day she had finished at 23:47 the night before.
 *
 * Failure here must not throw into the caller's send loop - a lost defer
 * costs exactly one push, the same cost claimPushSlot already accepts for
 * the same reason (see its own comment).
 * @param {object} p
 * @param {string} p.otherUid Recipient.
 * @param {string} p.roomCode
 * @param {string} p.event "firstToday" | "lastOne" | "perfect" |
 *     "habitAdded".
 * @param {string} p.dayKey The day the push is about.
 * @param {number} p.deliverAtMs From heldUntilMs.
 * @param {string} [p.finisherUid] Room-finish events: whose finish it was.
 * @param {string} [p.habitName] habitAdded: the slot's name.
 * @param {number} [p.slotIndex] habitAdded: the slot's index.
 * @return {Promise<void>}
 */
async function deferRoomPush(p) {
  try {
    const queue = getFunctions().taskQueue("deliverDeferredRoomPush");
    await queue.enqueue(
        {
          v: 2,
          otherUid: p.otherUid,
          roomCode: p.roomCode,
          event: p.event,
          dayKey: p.dayKey,
          finisherUid: p.finisherUid || null,
          habitName: p.habitName || null,
          slotIndex: typeof p.slotIndex === "number" ? p.slotIndex : null,
        },
        {
          scheduleDelaySeconds:
            Math.max(60, Math.round((p.deliverAtMs - Date.now()) / 1000)),
        },
    );
  } catch (err) {
    logger.warn("defer room push failed",
        {otherUid: p.otherUid, roomCode: p.roomCode, err: String(err)});
  }
}

/**
 * The redelivery half of deferRoomPush, dispatched by Cloud Tasks at the
 * moment the recipient's quiet hours were due to end.
 *
 * Decides everything afresh rather than trusting the moment it was queued:
 * settings can change in the hours between, a token can go stale, the
 * person can leave the room, and the day it is about has usually closed.
 * roomPushPlan drops any room event whose day the reader has moved past
 * (Aziz, 2026-09-24: a push about yesterday never goes), and a push still
 * on its day is dropped when the room's own decision for that day, run
 * again now, no longer sends it to this reader (they finished, someone else
 * is last). "A habit was added" is the one push that may land the next
 * morning, and it goes only while the slot still waits for them. If they
 * are STILL quiet (their window changed after this was scheduled) or
 * ineligible for any other reason by now, this drops the push rather than
 * re-queuing it: one retry is the promise, not an indefinite chase.
 *
 * maxAttempts: 1 - a delivery failure here (a transient FCM error, say)
 * is the same one-push cost every other skip in this file already accepts,
 * not worth Cloud Tasks' own retry-with-backoff machinery for.
 */
exports.deliverDeferredRoomPush = onTaskDispatched(
    {retryConfig: {maxAttempts: 1}, rateLimits: {maxConcurrentDispatches: 6}},
    async (req) => {
      const task = req.data || {};
      const {otherUid, roomCode} = task;
      if (!otherUid || !roomCode) return;
      const event = task.v === 2 ? task.event : (task.data || {}).type;
      const drop = (why) =>
        logger.info("held room push dropped", {roomCode, otherUid, event, why});

      // Queued by the first version: finished words and no day, so nothing
      // can tell whether they are still true. Only the one push whose words
      // cannot go stale overnight is delivered. At most one night of these
      // exists, the night this version is deployed.
      if (task.v !== 2) {
        if (event !== "roomHabitAdded" || !task.title || !task.body) {
          return drop("queued-by-old-version");
        }
      }

      const roomRef = db.collection("rooms").doc(roomCode);
      const [roomSnap, readerSnap] = await Promise.all([
        roomRef.get(),
        roomRef.collection("participants").doc(otherUid).get(),
      ]);
      if (!roomSnap.exists || !readerSnap.exists) return drop("gone");
      const room = roomSnap.data() || {};
      const reader = readerSnap.data() || {};
      if (reader.leftAt) return drop("left");

      const elig = await isEligible(otherUid, reader);
      if (!elig.eligible) return drop(elig.reason);
      const readerToday = localDayKey(elig.tzOffsetMinutes);

      let message;
      let data;
      let plan;
      if (task.v !== 2) {
        plan = {quotaDay: readerToday, yesterday: false};
        message = {title: task.title, body: task.body};
        data = {roomCode, type: "roomHabitAdded"};
      } else {
        plan = roomPushPlan({event, dayKey: task.dayKey, readerToday});
        if (plan.action !== "send") return drop(plan.reason);
        if (event === "habitAdded") {
          // Answered since (linked or declined), or taken back out of the
          // plan: nothing left to ask.
          if (!slotPendingFor(room, reader, task.slotIndex)) {
            return drop("slot-answered");
          }
          message = roomPushMessage({
            event, locale: elig.locale, room, habitName: task.habitName,
          });
          data = {roomCode, type: "roomHabitAdded"};
        } else {
          // The room's own decision for that day, run again now, has to
          // still send this event to this reader.
          const partsSnap = await roomRef.collection("participants").get();
          const finisherDoc =
            partsSnap.docs.find((d) => d.id === task.finisherUid);
          const others = partsSnap.docs.filter((d) =>
            d.id !== task.finisherUid && !(d.data() || {}).leftAt);
          const decision =
            roomEventFor(others, task.dayKey, room.pausedSpans, room);
          if (!decision || decision.event !== event ||
              !decision.recipients.some((d) => d.id === otherUid)) {
            return drop("no-longer-true");
          }
          message = roomPushMessage({
            event,
            locale: elig.locale,
            room,
            finisher: finisherDoc ? finisherDoc.data() || {} : {},
            reader,
            counts: event === "lastOne" ?
              lastOneCounts(others, task.dayKey, room) : null,
            todayKey: task.dayKey,
          });
          data = {roomCode, type: "roomFinish", event};
        }
      }

      const tokens = await deliverableTokens(otherUid);
      if (tokens.length === 0) return drop("no-token");
      const kind = task.v === 2 ? pushKindFor(event) : "info";
      if (!await claimPushSlot(otherUid, plan.quotaDay, kind)) {
        return drop("capped");
      }
      const sends = sendToTokens(otherUid, tokens, {...message, data});
      await Promise.all(sends);
      logger.info("deliverDeferredRoomPush", {
        roomCode, otherUid, event, sent: sends.length,
        yesterday: plan.yesterday,
      });
    },
);

/**
 * ── The admin's message, held for quiet hours ─────────────────────────────
 *
 * The admin tool (scripts/admin_lookup, lib/broadcast.js) sends a message
 * to everyone straight from the Admin SDK. Someone inside their quiet hours
 * at that moment used to be skipped for good: the tool runs on a Mac and
 * cannot wake at 07:00 (page item 6, Aziz, 2026-09-24).
 *
 * Now the tool writes who it held, and for when, into the message's own
 * history row (broadcast_log/{id}.held: [{uid, atMs}]) and calls
 * holdBroadcast with just the id. That queues one Cloud Task per held
 * person, timed for the end of their quiet hours, the same one-task-per-
 * held-push shape as deferRoomPush: nothing runs, and nothing is paid for,
 * while nothing is held. deliverHeldBroadcast then decides afresh and sends.
 *
 * holdBroadcast needs no caller identity: all it can do is queue what the
 * admin already wrote (clients cannot write broadcast_log, firestore.rules),
 * and only once per message (heldQueuedAt, set in a transaction). The tool's
 * own account holds no Cloud Tasks role, and this way it needs none.
 */

/** How long FCM may hold a held copy for a phone that is off. */
const HELD_BROADCAST_TTL_MS = 12 * 60 * 60 * 1000;

exports.holdBroadcast = onCall(async (request) => {
  const id = request.data && request.data.id;
  if (typeof id !== "string" || !/^n_[a-z0-9]+_[0-9a-f]{6}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Not a message id.");
  }
  const ref = db.collection("broadcast_log").doc(id);
  const held = await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return null;
    const row = snap.data() || {};
    if (row.kind !== "notification" || row.audience !== "everyone" ||
        row.heldQueuedAt || !Array.isArray(row.held)) {
      return [];
    }
    txn.set(ref, {
      heldQueuedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return row.held;
  });
  if (held === null) throw new HttpsError("not-found", "No such message.");

  const queue = getFunctions().taskQueue("deliverHeldBroadcast");
  let queued = 0;
  let failed = 0;
  for (const h of held) {
    if (!h || typeof h.uid !== "string" || typeof h.atMs !== "number") {
      failed++;
      continue;
    }
    try {
      await queue.enqueue({v: 1, id, uid: h.uid}, {
        scheduleDelaySeconds:
          Math.max(60, Math.round((h.atMs - Date.now()) / 1000)),
      });
      queued++;
    } catch (err) {
      failed++;
      logger.warn("hold broadcast enqueue failed",
          {id, uid: h.uid, err: String(err)});
    }
  }
  logger.info("holdBroadcast", {id, held: held.length, queued, failed});
  return {queued, failed};
});

exports.deliverHeldBroadcast = onTaskDispatched(
    {retryConfig: {maxAttempts: 1}, rateLimits: {maxConcurrentDispatches: 6}},
    async (req) => {
      const {id, uid} = req.data || {};
      if (typeof id !== "string" || typeof uid !== "string") return;
      const logRef = db.collection("broadcast_log").doc(id);
      const tally = (key) => logRef.update({
        [`held${key}`]: admin.firestore.FieldValue.increment(1),
      }).catch(() => {});
      const drop = (why) => {
        logger.info("held broadcast dropped", {id, uid, why});
        return tally("Dropped");
      };

      const [logSnap, userSnap] = await Promise.all([
        logRef.get(),
        db.collection("users").doc(uid).get(),
      ]);
      if (!logSnap.exists) return drop("gone");
      if (!userSnap.exists) return drop("no-user");
      const row = logSnap.data() || {};
      const user = userSnap.data() || {};
      const plan = heldBroadcastPlan({
        sentAtMs: millisOf(row.at),
        settings: user.notificationSettings,
        tzOffsetMinutes: user.tzOffsetMinutes,
      });
      if (plan.action !== "send") return drop(plan.reason);

      const tokens = await deliverableTokens(uid);
      if (tokens.length === 0) return drop("no-token");
      // The admin tool's own rule (lib/broadcast.js languageFor): English
      // only for an English phone when there is an English version.
      const en = user.locale === "en" && row.bodyEn;
      await Promise.all(sendToTokens(uid, tokens, {
        title: en ? row.titleEn : row.titleAr,
        body: en ? row.bodyEn : row.bodyAr,
        data: {type: "broadcast", id},
        ttlMs: HELD_BROADCAST_TTL_MS,
      }));
      logger.info("deliverHeldBroadcast", {id, uid, sent: tokens.length});
      return tally("Sent");
    },
);

/**
 * Claim one of the room's three daily events, so it fires exactly once.
 *
 * Every member's finish races for these: two people finishing in the same
 * second would both compute "I am the first" from a plain read, so the
 * check and the write have to be one transaction.
 *
 * Fails CLOSED, unlike claimPushSlot which falls back to sending. The
 * asymmetry is deliberate: a lost per-user quota claim costs at most one
 * extra push to one person, while a lost event claim would let a whole
 * room be notified twice for the same event.
 * @param {string} roomCode The room.
 * @param {string} event One of "firstToday", "lastOne", "perfect".
 * @param {string} dayKey The room day being claimed, "YYYY-MM-DD".
 * @return {Promise<boolean>} True if this caller won the claim.
 */
async function claimRoomEvent(roomCode, event, dayKey) {
  const roomRef = db.collection("rooms").doc(roomCode);
  try {
    return await db.runTransaction(async (txn) => {
      const fresh = await txn.get(roomRef);
      if (!fresh.exists) return false;
      const claimed = (fresh.data() || {}).pushEventDays || {};
      if (claimed[event] === dayKey) return false;
      txn.set(roomRef, {pushEventDays: {[event]: dayKey}}, {merge: true});
      return true;
    });
  } catch (err) {
    logger.warn("room event claim failed", {roomCode, event, err});
    return false;
  }
}

exports.notifyRoomFinish = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const roomCode = request.data && request.data.roomCode;
  if (typeof roomCode !== "string" || roomCode.length === 0) {
    throw new HttpsError("invalid-argument", "roomCode is required.");
  }

  const participantRef = db.collection("rooms").doc(roomCode)
      .collection("participants").doc(uid);
  const participantSnap = await participantRef.get();
  if (!participantSnap.exists) return {sent: 0};
  const participant = participantSnap.data();

  // Re-verify server-side - the caller's own request.data is never trusted
  // on its own; only the doc's own current allDoneToday/allDoneDate (the
  // exact pair RoomsController's transaction just wrote, right before
  // calling this) decides whether there's anything to announce.
  const todayKey = participant.allDoneDate;
  if (participant.allDoneToday !== true || !todayKey) {
    return {sent: 0};
  }

  // Idempotency: this callable can legitimately fire more than once for one
  // real finish (a later syncLinkedHabitsProgress room-open resync, two
  // devices racing, a retried call) - lastFinishNotifiedDate is a small
  // marker separate from allDoneToday/allDoneDate, purely for this
  // function's own bookkeeping (the Dart client never reads or writes it),
  // so a resync later today can never re-trigger a push for a day already
  // pushed for.
  if (participant.lastFinishNotifiedDate === todayKey) {
    return {sent: 0, alreadyNotified: true};
  }
  await participantRef.set(
      {lastFinishNotifiedDate: todayKey}, {merge: true});

  const roomSnap = await db.collection("rooms").doc(roomCode).get();
  if (!roomSnap.exists) return {sent: 0};
  const room = roomSnap.data() || {};

  const participantsSnap = await db
      .collection("rooms").doc(roomCode).collection("participants").get();

  // ── Which of the three events did this finish just cause? ─────────────
  // See the message tables at the top of this file for why the unit is an
  // event and not a finisher. `others` excludes the caller, whose own
  // finish is what got us here.
  // A member who left keeps their document (RoomParticipant.leftAt, a soft
  // departure so a rejoin cannot reset their score) but is not in the room,
  // and must not be pushed about it.
  const others = participantsSnap.docs.filter(
      (d) => d.id !== uid && !(d.data() || {}).leftAt);
  // Null for a solo room; for a day where nobody is left to tell once the
  // members standing down today are set aside; and for a last-one or
  // perfect day on a day the room is paused (see roomEventFor). The room is
  // passed so a member whose phone has already moved past todayKey (a day
  // finished after midnight) is read from that day's own numbers.
  const decision = roomEventFor(others, todayKey, room.pausedSpans, room);
  if (!decision) {
    const paused = isRoomPausedOn(room.pausedSpans, todayKey);
    return {sent: 0, suppressed: paused ? "room-paused" : "nobody-to-tell"};
  }
  const {event, recipients} = decision;
  // Event B says how much of the room is done, so the room is counted once,
  // here, and every recipient reads the same numbers.
  const counts =
    event === "lastOne" ? lastOneCounts(others, todayKey, room) : null;

  // Claimed BEFORE checking whether anyone can actually receive it. The
  // alternative - claim only once a deliverable recipient is found - would
  // reopen the race this closes, since two simultaneous finishers would
  // both get that far. The cost is that an event whose whole audience is
  // asleep, muted or device-less is spent rather than retried, which is
  // intended: a "first to finish today" that goes out on the fifth
  // person's finish is no longer true.
  //
  // So a room whose whole audience was inside quiet hours when the first
  // person finished hears nothing from the server that day. The evening
  // reminder used to be the floor under that; it was removed on 2026-09-16
  // and nothing replaced it, deliberately. Everyone still has the app's own
  // evening note, which is about their own board rather than the room's.
  if (!await claimRoomEvent(roomCode, event, todayKey)) {
    return {sent: 0, suppressed: event + "-already-sent-today"};
  }

  const kind = pushKindFor(event);
  const sends = [];
  // Why a recipient was skipped, counted so the log can answer "why did
  // nobody get this" without anyone's phone in hand. No names, uids or
  // tokens: counts only. "deferred" is not a loss - see deferRoomPush.
  // "pastDay" is a push about a day the reader has moved past, or would
  // have by the time their quiet hours end: never sent (roomPushPlan).
  const skipped =
    {ineligible: 0, deferred: 0, pastDay: 0, noToken: 0, capped: 0};
  for (const doc of recipients) {
    const other = doc.data() || {};
    const elig = await isEligible(doc.id, other);
    const quiet = !elig.eligible && elig.reason === "quiet-hours";
    if (!elig.eligible && !quiet) {
      skipped.ineligible++;
      continue;
    }
    const deliverAtMs =
      quiet ? heldUntilMs(elig.settings, elig.tzOffsetMinutes) : null;
    const plan = roomPushPlan({
      event,
      dayKey: todayKey,
      readerToday: localDayKey(elig.tzOffsetMinutes),
      quiet,
      heldUntilDay:
        quiet ? localDayKey(elig.tzOffsetMinutes, deliverAtMs) : undefined,
    });
    if (plan.action === "drop") {
      skipped.pastDay++;
      continue;
    }
    if (plan.action === "hold") {
      await deferRoomPush({
        otherUid: doc.id, roomCode, event, dayKey: todayKey,
        finisherUid: uid, deliverAtMs,
      });
      skipped.deferred++;
      continue;
    }

    // Checked BEFORE the daily slot is claimed. A person with no registered
    // device cannot receive anything, so spending one of their three daily
    // slots on an undeliverable push would silently exhaust the quota of
    // exactly the people who are already getting nothing.
    const tokens = await deliverableTokens(doc.id);
    if (tokens.length === 0) {
      skipped.noToken++;
      continue;
    }
    if (!await claimPushSlot(doc.id, plan.quotaDay, kind)) {
      skipped.capped++;
      continue;
    }
    // Worded per reader: the last-one push counts the reader's own habits
    // left, and events A and C take the FINISHER's gender (passing the
    // wrong one is invisible in English and wrong in every Arabic
    // sentence). See roomPushMessage.
    const message = roomPushMessage({
      event,
      locale: elig.locale,
      room,
      finisher: participant,
      reader: other,
      counts,
      todayKey,
    });
    sends.push(...sendToTokens(doc.id, tokens,
        {...message, data: {roomCode, type: "roomFinish", event}}));
  }
  await Promise.all(sends);
  logger.info("notifyRoomFinish", {
    roomCode,
    event,
    recipients: recipients.length,
    sent: sends.length,
    ...skipped,
  });
  return {sent: sends.length, event};
});

/**
 * Callable: the leader's device fires this right after addSharedHabit lands
 * a new slot (RoomsController._notifyRoomHabitAdded). Re-verified against
 * the room document, never trusted from request.data alone: the caller must
 * be the room's creator, and a live slot with that name must carry an
 * addedAt from the last few minutes. Idempotent per slot through a marker
 * on the room doc, so a retry or a second device cannot send it twice.
 * Recipients are the members IN the room (a departed record is skipped),
 * each under the same quiet-hours check and per-kind daily cap as every
 * other push here ("info").
 */
exports.notifyRoomHabitAdded = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const roomCode = request.data && request.data.roomCode;
  const habitName = request.data && request.data.habitName;
  if (typeof roomCode !== "string" || roomCode.length === 0 ||
      typeof habitName !== "string" || habitName.length === 0) {
    throw new HttpsError("invalid-argument",
        "roomCode and habitName are required.");
  }

  const roomRef = db.collection("rooms").doc(roomCode);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) return {sent: 0};
  const room = roomSnap.data() || {};
  if (room.createdBy !== uid) return {sent: 0, suppressed: "not-leader"};
  if (room.habitMode !== "shared") return {sent: 0, suppressed: "own-mode"};

  // The slot itself, by name, live, and genuinely just added. A slot with
  // no addedAt is one the room was created with; nobody is told about
  // those, they were on the invite.
  const shared = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  const nowMs = Date.now();
  const FRESH_MS = 15 * 60 * 1000;
  let slotIndex = -1;
  let addedMs = 0;
  for (let i = shared.length - 1; i >= 0; i--) {
    const s = shared[i] || {};
    if (s.name !== habitName || s.removedAt || !s.addedAt) continue;
    const ms = s.addedAt.toMillis ? s.addedAt.toMillis() : 0;
    if (nowMs - ms > FRESH_MS) continue;
    slotIndex = i;
    addedMs = ms;
    break;
  }
  if (slotIndex < 0) return {sent: 0, suppressed: "no-fresh-slot"};

  // Once per slot. The marker is the slot's own addedAt, so a second slot
  // with the same name later gets its own announcement.
  const marker = `${slotIndex}:${addedMs}`;
  const claimed = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(roomRef);
    const sent = Array.isArray((fresh.data() || {}).habitAddedNotified) ?
      fresh.data().habitAddedNotified : [];
    if (sent.includes(marker)) return false;
    tx.set(roomRef, {
      habitAddedNotified: admin.firestore.FieldValue.arrayUnion(marker),
    }, {merge: true});
    return true;
  });
  if (!claimed) return {sent: 0, alreadyNotified: true};

  const participantsSnap = await roomRef.collection("participants").get();
  const recipients = participantsSnap.docs.filter(
      (d) => d.id !== uid && !(d.data() || {}).leftAt);

  const sends = [];
  // "deferred" is not a loss - see deferRoomPush.
  const skipped = {ineligible: 0, deferred: 0, noToken: 0, capped: 0};
  for (const doc of recipients) {
    const other = doc.data() || {};
    const elig = await isEligible(doc.id, other);
    const quiet = !elig.eligible && elig.reason === "quiet-hours";
    if (!elig.eligible && !quiet) {
      skipped.ineligible++;
      continue;
    }
    const readerToday = localDayKey(elig.tzOffsetMinutes);
    if (quiet) {
      // Still news in the morning, unlike a "last one": held, and checked
      // again when it lands (deliverDeferredRoomPush drops it if the slot
      // was answered or taken out of the plan in between).
      await deferRoomPush({
        otherUid: doc.id, roomCode, event: "habitAdded", dayKey: readerToday,
        habitName, slotIndex,
        deliverAtMs: heldUntilMs(elig.settings, elig.tzOffsetMinutes),
      });
      skipped.deferred++;
      continue;
    }

    const tokens = await deliverableTokens(doc.id);
    if (tokens.length === 0) {
      skipped.noToken++;
      continue;
    }
    if (!await claimPushSlot(doc.id, readerToday, "info")) {
      skipped.capped++;
      continue;
    }
    const message = roomPushMessage(
        {event: "habitAdded", locale: elig.locale, room, habitName});
    sends.push(...sendToTokens(doc.id, tokens,
        {...message, data: {roomCode, type: "roomHabitAdded"}}));
  }
  await Promise.all(sends);
  logger.info("notifyRoomHabitAdded", {
    roomCode,
    slotIndex,
    recipients: recipients.length,
    sent: sends.length,
    ...skipped,
  });
  return {sent: sends.length};
});

// REMOVED 2026-09-16: the evening reminder, a push sent to a room where
// nobody had finished yet. It was the only push here not caused by someone
// finishing, and the only one triggered by inactivity. Aziz removed it as
// part of cutting notification spam: a member of a silent room was hearing
// it between 19:00 and 21:00 on top of the app's own evening note, and a
// room going quiet for a day is not by itself worth a notification.
//
// Every push this file still sends is caused by a person doing something.

/**
 * Every room that is live, the way the APP decides that.
 *
 * RoomModel.fromFirestore reads `status` as `(d['status'] as String?) ??
 * 'active'` - a MISSING status field means active, because rooms predate the
 * lobby era and were born running. A `where("status", "==", "active")` query
 * cannot see those documents at all: Firestore matches on stored fields, and
 * a room with no status field is simply not in the index. On 2026-09-12 that
 * hid rooms ZCNGFT and 5S84CL, plus five empty room documents, from the
 * scheduled functions and from check_rooms.js, so their pause spans and
 * undercounts were never swept.
 *
 * Reading the whole collection and filtering here is the only way to apply
 * the app's own default. The collection is small (single digits per this
 * project's whole history), so the cost is a rounding error against being
 * wrong about which rooms exist.
 * @return {Promise<{docs: Array, size: number}>} The same shape a query
 * snapshot exposes to the caller below.
 */
async function activeRooms() {
  const all = await db.collection("rooms").get();
  const docs = all.docs.filter((d) => {
    const status = (d.data() || {}).status;
    return status === undefined || status === null || status === "active";
  });
  return {docs, size: docs.length};
}

const DAY_MS = 24 * 60 * 60 * 1000;

// ── Rooms health sweep ─────────────────────────────────────────────────────
//
// Once a week, every active room is checked for the two ways a room quietly
// stops telling the truth (room_health.js has the rules and the story):
//
//  1. A pause span that reaches today or later. Clipped to yesterday on
//     the spot and logged as a warning, since nothing in the current app
//     can write one and it stops every member's days from counting.
//  2. A member whose stored count on a closed day is lower than their own
//     squares say. Logged only, with the exact admin command that fixes
//     it: the member's phone regrades the day itself on its next open, and
//     a server write would fight that sync.
//
// The sweep is a scheduled function rather than a Firestore trigger for
// the reason at the top of this file: this project cannot create Eventarc
// resources in me-central2, so nothing can watch rooms/{code} for writes.
// Mondays at 04:00 in Bahrain, the app's home timezone, when yesterday is
// still open (the day rolls at midnight and stays payable until 10:00) and
// the day before is fully closed, which is why the undercount check stops
// two days back. HEALTH_LOOKBACK_DAYS is wider than the weekly gap, so a
// day is never skipped between runs.
const HEALTH_TZ = "Asia/Bahrain";
const HEALTH_LOOKBACK_DAYS = 10;

/**
 * "YYYY-MM-DD" of a Firestore Timestamp (or anything with toDate), read in
 * the app's timezone, or null.
 * @param {*} v
 * @return {?string}
 */
function healthKeyOf(v) {
  if (!v || typeof v.toDate !== "function") return null;
  return todayKeyIn(v.toDate().getTime(), HEALTH_TZ);
}

exports.roomsHealthSweep = onSchedule(
    // Weekly, not daily. Nothing here is user-facing: it clips a pause span
    // no current build can even write, and otherwise only LOGS undercounts
    // with the admin command that fixes them. A daily run of a diagnostic
    // nobody reads daily is seven reads of every room for one look. The
    // lookback below is wider than the gap, so nothing falls through.
    {schedule: "every monday 04:00", timeZone: HEALTH_TZ},
    async () => {
      const todayKey = todayKeyIn(Date.now(), HEALTH_TZ);
      // The newest day that has fully closed: not today, not yesterday
      // (still payable until 10:00), the day before.
      const lastClosed = todayKeyIn(Date.now() - 2 * DAY_MS, HEALTH_TZ);
      const roomsSnap = await activeRooms();

      let clippedRooms = 0;
      let undercounts = 0;
      for (const roomDoc of roomsSnap.docs) {
        const room = roomDoc.data() || {};
        const code = roomDoc.id;

        // 1. Spans.
        const {spans, clipped} = clipSpansToPast(room.pausedSpans, todayKey);
        if (clipped.length > 0) {
          await roomDoc.ref.set({pausedSpans: spans}, {merge: true});
          clippedRooms++;
          logger.warn("roomsHealthSweep clipped a pause that reached the " +
              "future", {room: code, name: room.name, was: clipped, now: spans});
        }

        // 2. Counts, on closed days only.
        const startKey = healthKeyOf(room.startDate);
        if (!startKey) continue;
        const days = closedDaysToCheck({
          startKey,
          endKey: healthKeyOf(room.endDate),
          pausedSpans: spans,
        }, lastClosed, HEALTH_LOOKBACK_DAYS);
        if (days.length === 0) continue;

        const partsSnap = await roomDoc.ref.collection("participants").get();
        for (const partDoc of partsSnap.docs) {
          const part = partDoc.data() || {};
          // Departed (RoomParticipant.leftAt): still stored, not in the room.
          // Their days stopped being graded when they left, so a stale count
          // here is expected rather than an undercount worth reporting.
          if (part.leftAt) continue;
          const countingIds = countingHabitIds(room, part);
          if (countingIds.length === 0) continue;
          const daySnaps = await Promise.all(days.map((d) => db
              .collection("users").doc(partDoc.id)
              .collection("daily").doc(d).get()));
          const squaresByDay = {};
          // The day document's own write times, which are what tell a day the
          // room is HOLDING on purpose from one it genuinely missed. See
          // undercountedDays: without them this sweep logged the app's
          // anti-backdating clamp working as designed, with a repair command
          // beside it.
          const lastUpdatedByDay = {};
          const createdByDay = {};
          days.forEach((d, i) => {
            if (!daySnaps[i].exists) return;
            squaresByDay[d] = (daySnaps[i].data() || {}).squareStates || {};
            lastUpdatedByDay[d] = (daySnaps[i].data() || {}).lastUpdated;
            createdByDay[d] = daySnaps[i].createTime;
          });
          const short = undercountedDays({days, countingIds, squaresByDay,
            part, lastUpdatedByDay, createdByDay, room});
          for (const u of short) {
            if (u.held) {
              logger.info("roomsHealthSweep saw a closed day the room is " +
                  "holding on purpose, no action", {
                room: code,
                name: room.name,
                member: part.displayName || partDoc.id,
                uid: partDoc.id,
                day: u.day,
                stored: u.stored,
                squares: u.real,
                why: u.why,
              });
              continue;
            }
            undercounts++;
            logger.warn("roomsHealthSweep found a closed day whose stored " +
                "count trails the member's squares", {
              room: code,
              name: room.name,
              member: part.displayName || partDoc.id,
              uid: partDoc.id,
              day: u.day,
              stored: u.stored,
              real: u.real,
              fix: `node set_room_day.js --room=${code} --user=${partDoc.id} ` +
                  `--date=${u.day} --done=${u.real} --confirm`,
            });
          }
        }
      }
      logger.info("roomsHealthSweep swept", {
        rooms: roomsSnap.size,
        clippedRooms,
        undercounts,
      });
    });

// ── Purchase facts ─────────────────────────────────────────────────────────
//
// Two collections revenueCatWebhook writes beside the Premium mirror, both
// server-only: firestore.rules has no match for either, so its closing
// deny-all refuses every client read and write.
//
//  - purchase_log/{eventId}: one row per sale or refund of a Lifetime, at
//    either price (growdaily_lifetime is the regular one,
//    growdaily_lifetime_offer the welcome-window and sale one), for the
//    admin tool's "who pays full price" meter.
//  - creator_ledger/{eventId}: one row per sale or refund of any product
//    bought through a creator's Apple offer code, with what that creator
//    earned from it. creators/{id}.offerRef names the creator's offer. A
//    refund follows its sale's row there (same transaction), so it reaches
//    the creator with or without an offer code and takes back exactly what
//    the sale paid.
//
// Both are keyed by RevenueCat's event id and written with create(), so a
// retried delivery finds its row already there and changes nothing, the
// creator's share percent included. Sandbox events are recorded too, marked
// by their `environment`, so a sandbox purchase can prove the pipe; the
// admin tool hides them by default. purchase_facts.js has the rules and
// their tests.

/** gRPC's ALREADY_EXISTS, what create() throws when the row is there. */
const ALREADY_EXISTS = 6;

/**
 * Creates [ref] with [data], or leaves it alone when it already exists.
 * @param {object} ref A Firestore DocumentReference.
 * @param {object} data The row to write.
 * @return {Promise<boolean>} False when the row was already there.
 */
async function createOnce(ref, data) {
  try {
    await ref.create(data);
    return true;
  } catch (e) {
    // A redelivery of an event already recorded: the first row stands.
    if (e && e.code === ALREADY_EXISTS) return false;
    throw e;
  }
}

/**
 * The creator_ledger SALE row filed under the first of [keys] that has one,
 * or null. See saleLookupKeys for which transaction ids a refund tries.
 * @param {string[]} keys Transaction ids, in the order to try them.
 * @return {Promise<?object>} That sale row's data.
 */
async function findLedgerSale(keys) {
  for (const key of keys) {
    // eslint-disable-next-line no-await-in-loop
    const found = await db.collection("creator_ledger")
        .where("transactionId", "==", key)
        .where("kind", "==", "sale")
        .limit(1).get();
    if (!found.empty) return found.docs[0].data();
  }
  return null;
}

/**
 * Writes the purchase facts [event] carries: its purchase_log row, and its
 * creator_ledger row when it came through an offer code or refunds a sale
 * that did. Throws when a read or write fails, so revenueCatWebhook can
 * answer 500 and be retried.
 *
 * A refund looks for its sale's ledger row first and, when there is one,
 * follows it: same creator, same offer, the percent the sale paid, whether
 * or not the refund event carries an offer code (see refundLedgerRow).
 * Only a refund with no ledgered sale, and every sale, go by their own
 * offer code, so the creator is looked up only then, and an ordinary
 * purchase costs no extra read at all. An offer code no creator claims
 * still gets its ledger row, with no creator and needsReview set, so the
 * sale is not lost while the creator's record is added or fixed.
 * @param {object} event RevenueCat's webhook event.
 * @return {Promise<void>}
 */
async function recordPurchaseFacts(event) {
  const logRow = purchaseLogRow(event);
  const offerRef = offerRefOf(event);
  // Refunds only: where the refunded sale may be filed in creator_ledger.
  const saleKeys = saleLookupKeys(event);
  const ledgerDue = purchaseKindOf(event) !== null &&
      (offerRef !== null || saleKeys.length > 0);
  if (!logRow && !ledgerDue) return;

  // The event id is what makes a retry harmless, so without one nothing is
  // written rather than a sale counted once per delivery.
  const id = factDocId(event);
  if (!id) {
    logger.warn("revenueCatWebhook: purchase event without a usable id, " +
        "facts not recorded", {
      type: event.type, product: event.product_id,
      environment: event.environment,
    });
    return;
  }
  const createdAt = admin.firestore.FieldValue.serverTimestamp();
  if (logRow) {
    await createOnce(db.collection("purchase_log").doc(id),
        Object.assign({}, logRow, {createdAt}));
  }
  if (!ledgerDue) return;

  const sale = await findLedgerSale(saleKeys);
  let creator = null;
  if (sale === null && offerRef !== null) {
    const found = await db.collection("creators")
        .where("offerRef", "==", offerRef).limit(1).get();
    const creatorDoc = found.empty ? null : found.docs[0];
    if (!creatorDoc) {
      logger.warn("revenueCatWebhook: no creator claims this offer code, " +
          "ledger row flagged for review", {
        offerRef, id, environment: event.environment,
      });
    }
    // The document id wins over any stored `id` field.
    creator = creatorDoc ?
      Object.assign({}, creatorDoc.data(), {id: creatorDoc.id}) : null;
  }
  // Null for a refund with no ledgered sale and no offer code: there is no
  // creator to charge it to. A Lifetime one is still in purchase_log above.
  const row = ledgerRowFor(event, {sale, creator});
  if (row) {
    await createOnce(db.collection("creator_ledger").doc(id),
        Object.assign({}, row, {createdAt}));
  }
}

/**
 * RevenueCat's webhook: the only writer of the Premium mirror on
 * `users/{uid}`.
 *
 * WHY. RevenueCat is the source of truth for entitlement and both mobile
 * apps read its SDK directly. Flutter web has no RevenueCat SDK at all
 * (purchase_service.dart's configure() returns null on kIsWeb), so someone
 * who bought Premium on their iPhone opened grow-daily-app.web.app and read
 * as FREE, with a paywall whose buy button silently did nothing. This
 * endpoint mirrors the entitlement onto the user doc so a non-SDK client
 * can read it. It is a CACHE of RevenueCat's answer, never a second
 * authority: iOS and Android keep asking the SDK, which is fresher than any
 * webhook and works offline.
 *
 * SECURITY. The mirror fields are server-written only. firestore.rules
 * rejects any client write that so much as mentions them (premiumFieldOk),
 * so the worst a tampered client can do is read a value it could already
 * see. This endpoint authenticates RevenueCat with the shared secret set as
 * the Authorization header in their dashboard, compared in constant time,
 * and refuses everything else with 401. Without the secret configured the
 * function refuses every request rather than failing open.
 *
 * WHAT IT WRITES. The event only names the accounts to look at; the
 * verdict comes from re-reading each one's RevenueCat record
 * (fetchCustomerInfo), because a webhook describes one product's
 * transaction and Premium has two products behind it. See uidsToRefresh.
 * Before any of that it records the event's purchase facts (purchase_log,
 * creator_ledger), for sandbox events too; see recordPurchaseFacts.
 *
 * SETUP, and only Aziz can do it:
 *  1. `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET` and paste a
 *     long random string.
 *  2. `firebase functions:secrets:set REVENUECAT_API_KEY` and paste a
 *     RevenueCat secret API key created for API v1.
 *  3. Deploy: `firebase deploy --only functions:revenueCatWebhook`.
 *  4. RevenueCat dashboard -> Integrations (left menu) -> Webhooks:
 *     set the URL to the deployed https trigger and the Authorization
 *     header to the SAME string as step 1.
 * Until step 4 is done this endpoint is simply never called and nothing
 * changes for anyone; the mobile apps are unaffected either way.
 */
exports.revenueCatWebhook = onRequest(
    {secrets: [revenueCatWebhookSecret, revenueCatApiKey]},
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("POST only");
        return;
      }
      // Trimmed: a secret piped in from `openssl rand` is stored with its
      // trailing newline, and Node strips whitespace from a received header,
      // so an untrimmed compare would refuse every real delivery.
      const expected = (revenueCatWebhookSecret.value() || "").trim();
      // Fail CLOSED. An unset secret must not mean "accept anything".
      if (!expected) {
        logger.error("revenueCatWebhook: secret not configured, refusing");
        res.status(500).send("not configured");
        return;
      }
      const got = req.get("Authorization") || "";
      if (!timingSafeEqualStr(got, expected)) {
        logger.warn("revenueCatWebhook: bad Authorization header");
        res.status(401).send("unauthorized");
        return;
      }

      const event = (req.body && req.body.event) || null;
      if (!event || typeof event !== "object") {
        res.status(400).send("no event");
        return;
      }

      // Purchase facts first, ahead of the sandbox gate below, which is
      // about the MIRROR: a sandbox purchase is exactly how the fact rows
      // get tested. A failure here must not cost anyone their Premium, so
      // the mirror still runs; it only turns this delivery's 200 into a 500
      // (see `ok`), so RevenueCat retries. Retrying is safe on both sides:
      // the mirror re-reads, and the fact rows are create-only, so any that
      // did land stay exactly as they are.
      let factsFailed = false;
      try {
        await recordPurchaseFacts(event);
      } catch (e) {
        factsFailed = true;
        logger.error("revenueCatWebhook: purchase facts failed", String(e));
      }
      // Every success answer below goes through here.
      const ok = (text) => {
        if (factsFailed) {
          res.status(500).send("purchase facts failed");
          return;
        }
        res.status(200).send(text);
      };

      // SANDBOX and TEST events look exactly like real ones. Mirroring them
      // would hand a permanent production entitlement to every TestFlight
      // tester and to anyone who can press "send test webhook" in the
      // dashboard. 200, not an error: RevenueCat should stop retrying.
      // (Unless the purchase facts above failed: then 500, see `ok`.)
      if (!isProduction(event)) {
        logger.info("revenueCatWebhook: ignoring non-production event", {
          environment: event.environment, type: event.type,
        });
        ok("ignored: not production");
        return;
      }

      // Usually one account. A TRANSFER names both the account gaining the
      // purchase and the one LOSING it, and both are re-read: the loser has
      // to be revoked or one lifetime purchase mints a Premium account on
      // every transfer, and the gainer has to be granted, which the old
      // per-event verdict never did because TRANSFER carries no entitlement.
      const uids = uidsToRefresh(event);
      if (uids.length === 0) {
        // Nothing to write: only anonymous $RCAnonymousID ids, which belong
        // to no account yet. Not an error. When that guest signs in,
        // logIn MERGES the ids (an alias, and no webhook fires for it), so
        // the account is only caught up by that customer's NEXT event,
        // which lists the real uid in `aliases`. A lifetime bought as a
        // guest has no next event: a known gap this endpoint cannot close.
        ok("nothing to mirror");
        return;
      }
      const apiKey = (revenueCatApiKey.value() || "").trim();
      if (!apiKey) {
        // 500, not 200: RevenueCat keeps retrying for about two and a half
        // hours, which covers the gap if the key is set a little late.
        logger.error("revenueCatWebhook: API key not configured, refusing");
        res.status(500).send("not configured");
        return;
      }

      try {
        for (const uid of uids) {
          const ref = db.collection("users").doc(uid);
          // Checked BEFORE calling RevenueCat, not only inside the
          // transaction: GET /subscribers creates a customer that does not
          // exist, so a deleted account would otherwise be re-created on
          // RevenueCat's side just to be skipped here.
          // eslint-disable-next-line no-await-in-loop
          const existing = await ref.get();
          if (!existing.exists) {
            logger.info("revenueCatWebhook: no user doc, skipping", {
              uid, type: event.type,
            });
            continue;
          }
          // eslint-disable-next-line no-await-in-loop
          const info = await fetchCustomerInfo(uid, apiKey);
          const verdict = premiumFromCustomerInfo(info, Date.now());
          if (!verdict) throw new Error("unreadable RevenueCat customer info");
          // eslint-disable-next-line no-await-in-loop
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            // Never CREATE a user doc. A late renewal for an account that
            // was deleted (AuthNotifier.deleteAccount removes the doc) would
            // otherwise resurrect it as a ghost carrying nothing but an
            // entitlement, which then reads as a real account elsewhere.
            if (!snap.exists) return;
            if (!shouldWrite(verdict.checkedAtMs, snap.data())) {
              logger.info("revenueCatWebhook: older snapshot, skipping", {
                uid, id: event.id, type: event.type,
              });
              return;
            }
            tx.set(ref, {
              premiumActive: verdict.active,
              premiumExpiresAtMs: verdict.expiresAtMs,
              premiumEventId: String(event.id || ""),
              premiumEventMs: verdict.checkedAtMs,
              premiumUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          });
        }
      } catch (e) {
        // 500 so RevenueCat retries: losing an entitlement write is worse
        // than processing the event twice, and a re-read is idempotent.
        // Log the message only; the error never carries the API key.
        logger.error("revenueCatWebhook: refresh failed", String(e));
        res.status(500).send("refresh failed");
        return;
      }
      ok("ok");
    });
