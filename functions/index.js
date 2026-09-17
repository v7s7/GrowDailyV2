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
const {defineSecret} = require("firebase-functions/params");
const crypto = require("crypto");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {isRoomPausedOn, roomEventFor} = require("./room_events");
const {lastOneCounts, lastOneMessageFor} = require("./room_messages");
const {claimQuota, isQuietHoursNow, pushKindFor} = require("./push_policy");
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
 * Arabic verbs agree with their subject, so the finisher's gender changes
 * the sentence — «أنهى عاداته» for a man, «أنهت عاداتها» for a woman.
 *
 * The app mirrors `gender` onto the participant doc (RoomsController.
 * _profileFields) precisely so this function can pick, since it has no
 * access to the Dart character catalog. Anything other than "female" —
 * including a member whose character never loaded, and every doc written
 * before that field existed — falls to the masculine form, which is
 * Arabic's unmarked default and is what shipped previously.
 *
 * English needs none of this, which is exactly why the bug survived: the
 * table looked symmetric.
 * @param {string|undefined} gender The finisher's stored gender.
 * @return {boolean} Whether to use feminine agreement.
 */
function isFem(gender) {
  return gender === "female";
}

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
 */

/** Event A. `gender` is the FINISHER's - the sentence is about them. */
const FIRST_TODAY_MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `${finisherName} is first to finish in "${roomName}"`,
    body: "First one done today. Your turn.",
  }),
  ar: (finisherName, roomName, gender) => ({
    title: isFem(gender) ?
      `${finisherName} أول من أنهت في "${roomName}"` :
      `${finisherName} أول من أنهى في "${roomName}"`,
    body: isFem(gender) ?
      "أول وحدة تخلّص اليوم. دورك." :
      "أول واحد يخلّص اليوم. دورك.",
  }),
};

/**
 * Event B's words live in room_messages.js (lastOneMessage), where they are
 * tested: the room's own name as the title, and a body that says what the
 * room has done and asks for the reader's part, «٤ من ٥ خلّصوا اليوم. سوي
 * عادتك الحين ويصير يوم الغرفة كامل 🤝». It used to be «باقي أنت. إلى الآن
 * فيه وقت.», a verdict about the one person still to go (Aziz, 2026-09-11).
 *
 * That verdict is not gone from every push. NUDGE_MESSAGES below, sent in
 * place of this one to anyone who turned roomNudgesEnabled on, still says
 * «باقي أنت.» / «باقية أنتِ.» and "Still waiting on you.". Aziz did not pick
 * a change to that push, so it is left as it was.
 */

/** Event C. Nobody in particular is the subject, so no gender needed. */
const ROOM_PERFECT_MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `Perfect day in "${roomName}" 🎉`,
    body: "Everyone finished today.",
  }),
  ar: (finisherName, roomName) => ({
    title: `يوم كامل في "${roomName}" 🎉`,
    body: "الكل خلّص عاداته اليوم.",
  }),
};

/**
 * The opt-in playful variant of event B, sent to the last person standing
 * instead of the lastOneMessage push (room_messages.js).
 *
 * Deliberately an invitation and not a scoreboard. «الكل خلّص ـ باقي أنت»
 * reads as banter between friends; «الكل خلّص وأنت لا» reads as an
 * accusation, and these habits are صلاة and أذكار rather than gym sets.
 * Shame motivates for about a week and then people leave.
 *
 * `gender` is the RECIPIENT's: unlike events A and C, the sentence is about
 * the person reading it.
 */
const NUDGE_MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `Everyone else finished in "${roomName}" 👀`,
    body: "Still waiting on you.",
  }),
  ar: (finisherName, roomName, gender) => ({
    title: `الكل خلّص في "${roomName}" 👀`,
    body: isFem(gender) ? "باقية أنتِ." : "باقي أنت.",
  }),
};

/**
 * Above this many members the playful nudge falls back to the neutral
 * wording. Volume is no longer the reason for a size rule anywhere else in
 * this file - this one is purely about tone. Among five friends, «باقي
 * أنت 👀» is teasing. In a room of two hundred it is a stadium watching
 * one person fall behind.
 */
const NUDGE_ROOM_LIMIT = 5;

/**
 * Whether this recipient still has room for a push of [kind] today,
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
 * `dayKey` is the recipient's OWN app day, passed in by the caller, so the
 * counters roll over on their clock rather than UTC.
 * @param {string} otherUid The recipient.
 * @param {string} dayKey Their local day, "YYYY-MM-DD".
 * @param {string} kind "info" or "nudge", see pushKindFor.
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
 * The recipient's own calendar day, from their mirrored UTC offset.
 * @param {number|undefined} tzOffsetMinutes Their device offset.
 * @return {string} "YYYY-MM-DD" in their local time.
 */
function localDayKey(tzOffsetMinutes) {
  const offset = typeof tzOffsetMinutes === "number" ? tzOffsetMinutes : 0;
  const local = new Date(Date.now() + offset * 60 * 1000);
  return local.toISOString().slice(0, 10);
}

async function isEligible(otherUid, participantData) {
  if (participantData.notificationsMuted === true) {
    return {eligible: false, locale: "en"};
  }
  const userSnap = await db.collection("users").doc(otherUid).get();
  if (!userSnap.exists) return {eligible: false, locale: "en"};
  const user = userSnap.data() || {};
  const settings = user.notificationSettings;
  const locale = user.locale === "ar" ? "ar" : "en";

  if (settings && settings.masterEnabled === false) {
    return {eligible: false, locale};
  }
  if (settings && settings.roomActivityEnabled === false) {
    return {eligible: false, locale};
  }
  if (isQuietHoursNow(settings, user.tzOffsetMinutes)) {
    return {eligible: false, locale};
  }
  // The daily cap is claimed by the CALLER, after it has confirmed this
  // person actually has a device to receive on. Claiming it here would
  // spend a slot on an undeliverable push.
  return {eligible: true, locale, tzOffsetMinutes: user.tzOffsetMinutes};
}

/**
 * Whether the last person standing gets the playful wording rather than
 * the neutral one.
 *
 * Every condition exists to stop it becoming nagging:
 *  - opt-in only (`roomNudgesEnabled`), so nobody meets it by surprise;
 *  - small rooms only (see NUDGE_ROOM_LIMIT), because tone does not
 *    survive scale;
 *  - only to someone who has NOT finished today, which event B guarantees
 *    but which is re-checked here rather than assumed;
 *  - not late in their evening, when a nudge lands as a reprimand for a
 *    day already lost rather than a prompt for one still winnable.
 *
 * Quiet hours and the daily cap are applied separately in isEligible and
 * the send loop, and both still apply on top of this.
 * @param {string} otherUid The recipient.
 * @param {object} participantData Their participant doc in this room.
 * @param {number} roomSize How many members the room has.
 * @return {Promise<boolean>} Whether to use the nudge wording.
 */
async function nudgeAllowed(otherUid, participantData, roomSize) {
  if (roomSize > NUDGE_ROOM_LIMIT) return false;
  if (participantData.allDoneToday === true) return false;
  const userSnap = await db.collection("users").doc(otherUid).get();
  if (!userSnap.exists) return false;
  const user = userSnap.data() || {};
  const settings = user.notificationSettings || {};
  if (settings.roomNudgesEnabled !== true) return false;
  const offset =
    typeof user.tzOffsetMinutes === "number" ? user.tzOffsetMinutes : 0;
  const hour = new Date(Date.now() + offset * 60 * 1000).getUTCHours();
  if (hour >= 21 || hour < 8) return false;
  return true;
}

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

  const finisherName = participant.displayName || "Someone";
  // Mirrored by the app onto the participant doc so Arabic can agree with
  // the finisher — see isFem. Undefined for docs written before that field
  // existed, which falls to the masculine default.
  const finisherGender = participant.gender;
  const roomSnap = await db.collection("rooms").doc(roomCode).get();
  if (!roomSnap.exists) return {sent: 0};
  const room = roomSnap.data() || {};
  const roomName = room.name || "your room";

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
  // perfect day on a day the room is paused (see roomEventFor).
  const decision = roomEventFor(others, todayKey, room.pausedSpans);
  if (!decision) {
    const paused = isRoomPausedOn(room.pausedSpans, todayKey);
    return {sent: 0, suppressed: paused ? "room-paused" : "nobody-to-tell"};
  }
  const {event, recipients} = decision;
  // Event B says how much of the room is done, so the room is counted once,
  // here, and every recipient reads the same numbers.
  const counts = event === "lastOne" ? lastOneCounts(others, todayKey) : null;

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

  const messageFor = {
    firstToday: FIRST_TODAY_MESSAGES,
    perfect: ROOM_PERFECT_MESSAGES,
  }[event];

  const sends = [];
  // Why a recipient was skipped, counted so the log can answer "why did
  // nobody get this" without anyone's phone in hand. No names, uids or
  // tokens: counts only.
  const skipped = {ineligible: 0, noToken: 0, capped: 0};
  for (const doc of recipients) {
    const other = doc.data() || {};
    const {eligible, locale, tzOffsetMinutes} =
      await isEligible(doc.id, other);
    if (!eligible) {
      skipped.ineligible++;
      continue;
    }

    const tokensSnap = await db
        .collection("users").doc(doc.id)
        .collection("fcmTokens").get();
    // Checked BEFORE the daily slot is claimed. A person with no registered
    // device cannot receive anything, so spending one of their three daily
    // slots on an undeliverable push would silently exhaust the quota of
    // exactly the people who are already getting nothing.
    if (tokensSnap.empty) {
      skipped.noToken++;
      continue;
    }
    if (!await claimPushSlot(
        doc.id, localDayKey(tzOffsetMinutes), pushKindFor(event))) {
      skipped.capped++;
      continue;
    }

    // Only event B has a playful variant, and only for the single person
    // it goes to. Any condition failing falls back to the neutral wording,
    // which stays the default for everyone.
    const wantsNudge = event === "lastOne" &&
      // Room size for the policy is the members IN the room, not every
      // document: a departed member's record is kept (RoomParticipant.leftAt)
      // and must not make a two-person room look like three.
      await nudgeAllowed(doc.id, other, others.length + 1);
    let message;
    if (wantsNudge) {
      // The nudge's sentence is about the person reading it, so it takes
      // the RECIPIENT's gender.
      message = NUDGE_MESSAGES[locale](finisherName, roomName, other.gender);
    } else if (event === "lastOne") {
      // Worded from the stored docs, not roomName's English "your room" or
      // finisherName's "Someone" stand-ins: see lastOneMessageFor, where
      // that wiring is tested.
      message = lastOneMessageFor({
        locale,
        room,
        finisher: participant,
        counts,
        reader: other,
        todayKey,
      });
    } else {
      // Events A and C are about the finisher. Passing the wrong gender is
      // invisible in English and wrong in every Arabic sentence.
      message = messageFor[locale](finisherName, roomName, finisherGender);
    }
    const {title, body} = message;
    for (const tokenDoc of tokensSnap.docs) {
      sends.push(
          admin.messaging().send({
            token: tokenDoc.id,
            notification: {title, body},
            data: {roomCode, type: "roomFinish", event},
            apns: {payload: {aps: {sound: "default"}}},
          }).catch((err) => {
            // FirebaseError exposes the code directly as `.code` (e.g.
            // "messaging/registration-token-not-registered") - verified
            // against firebase-admin-node's own source at research
            // time. `errorInfo` is where that code originates
            // internally, not a property the public-facing error
            // itself exposes, so checking it directly would have made
            // this branch never actually match anything.
            const code = err && err.code;
            // Device uninstalled the app, or this token otherwise went
            // stale - prune it so this stops being retried forever.
            // Any other error (offline, transient) just leaves the
            // token in place for next time.
            if (
              code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token"
            ) {
              return tokenDoc.ref.delete().catch(() => {});
            }
            logger.warn("room-finish push failed", {code, uid: doc.id});
            return null;
          }),
      );
    }
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
 * "A habit was added to the plan" - sent to every member of a shared room
 * except the leader who added it.
 *
 * The in-app banner (roomNewHabitBannerBody) only reaches a member who opens
 * the app, and a slot the leader adds starts counting against an unlinked
 * member after the grace (RoomModel.kNewSlotGraceDays), so the people who
 * most need to hear are exactly the ones not looking. Warm and plain: what
 * was added, to which room, and that linking it means it counts for them
 * from today. Impersonal on purpose - no «أضاف/أضافت» about the leader -
 * so nothing has to guess a gender.
 *
 * DRAFT WORDING, Aziz picks the final Arabic.
 */
const HABIT_ADDED_MESSAGES = {
  en: (habitName, roomName) => ({
    title: `New habit in "${roomName}"`,
    body: `"${habitName}" was added to the plan. Link it on your side and ` +
      "it counts for you from today \u{1F331}",
  }),
  ar: (habitName, roomName) => ({
    title: `عادة جديدة في "${roomName}"`,
    body: `انضافت «${habitName}» للخطة. اربطها من عندك وتبدأ تنحسب لك ` +
      "من اليوم \u{1F331}",
  }),
};

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

  const roomName = room.name || "your room";
  const participantsSnap = await roomRef.collection("participants").get();
  const recipients = participantsSnap.docs.filter(
      (d) => d.id !== uid && !(d.data() || {}).leftAt);

  const sends = [];
  const skipped = {ineligible: 0, noToken: 0, capped: 0};
  for (const doc of recipients) {
    const other = doc.data() || {};
    const {eligible, locale, tzOffsetMinutes} =
      await isEligible(doc.id, other);
    if (!eligible) {
      skipped.ineligible++;
      continue;
    }
    const tokensSnap = await db
        .collection("users").doc(doc.id)
        .collection("fcmTokens").get();
    if (tokensSnap.empty) {
      skipped.noToken++;
      continue;
    }
    if (!await claimPushSlot(
        doc.id, localDayKey(tzOffsetMinutes), "info")) {
      skipped.capped++;
      continue;
    }
    const table = HABIT_ADDED_MESSAGES[locale] || HABIT_ADDED_MESSAGES.en;
    const {title, body} = table(habitName, roomName);
    for (const tokenDoc of tokensSnap.docs) {
      sends.push(
          admin.messaging().send({
            token: tokenDoc.id,
            notification: {title, body},
            data: {roomCode, type: "roomHabitAdded"},
            apns: {payload: {aps: {sound: "default"}}},
          }).catch((err) => {
            const code = err && err.code;
            if (
              code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token"
            ) {
              return tokenDoc.ref.delete().catch(() => {});
            }
            logger.warn("habit-added push failed", {code, uid: doc.id});
            return null;
          }),
      );
    }
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
            part, lastUpdatedByDay, createdByDay});
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
      // SANDBOX and TEST events look exactly like real ones. Mirroring them
      // would hand a permanent production entitlement to every TestFlight
      // tester and to anyone who can press "send test webhook" in the
      // dashboard. 200, not an error: RevenueCat should stop retrying.
      if (!isProduction(event)) {
        logger.info("revenueCatWebhook: ignoring non-production event", {
          environment: event.environment, type: event.type,
        });
        res.status(200).send("ignored: not production");
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
        res.status(200).send("nothing to mirror");
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
      res.status(200).send("ok");
    });
