/**
 * Grow Daily Cloud Functions.
 *
 * The room-finish push notification's server half — see
 * lib/core/services/push_notification_service.dart for the client half, and
 * lib/features/settings/models/notification_settings.dart's
 * roomActivityEnabled doc comment for the feature end to end. This is the
 * ONE server-side component this app has; everything else the app does
 * (habit reminders, streak-risk nudges, celebrations) is scheduled or shown
 * entirely on-device by NotificationService, with no backend involved at
 * all.
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

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

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

const MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `${finisherName} just finished in "${roomName}"`,
    body: "Your turn - keep it going.",
  }),
  ar: (finisherName, roomName) => ({
    title: `${finisherName} أنهى عاداته في "${roomName}"`,
    body: "دورك الآن، حافظ على استمراريتك.",
  }),
};

/**
 * The once-a-day message a LARGE room sends instead of one per finisher -
 * see FANOUT_MEMBER_LIMIT for why.
 */
const FIRST_TODAY_MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `${finisherName} is first to finish in "${roomName}"`,
    body: "First one done today. Your turn.",
  }),
  ar: (finisherName, roomName) => ({
    title: `${finisherName} أول من أنهى في "${roomName}"`,
    body: "أول واحد يخلّص اليوم. دورك.",
  }),
};

/**
 * Above this many members, a room stops sending one push per finisher and
 * sends a single "first to finish today" instead.
 *
 * Per-finisher fan-out is quadratic: every member finishing notifies every
 * other member, so an N-person room where everyone finishes daily sends
 * N x (N-1) pushes a day. That is fine at 6 people (30) and unusable at 200
 * - roughly 39,800 sends, with each member's phone buzzing ~199 times, plus
 * a user-doc and token read per recipient per finish.
 *
 * The cure isn't only cost, it's meaning. In a room of six, "Ahmed just
 * finished" is a nudge from someone you know. In a room of two hundred it is
 * one of hundreds of identical pings, and the thing people actually want to
 * know - is anyone moving today - is answered just as well by the first one.
 *
 * So above the limit, exactly one push goes out per room per day, claimed by
 * whoever finishes first. That's N sends a day instead of N x (N-1): a
 * 200-person room drops from ~39,800 to 199.
 */
const FANOUT_MEMBER_LIMIT = 12;

/**
 * Whether [tzOffsetMinutes] (this user's device's UTC offset in minutes,
 * mirrored by main.dart's _syncAmbientAccountFacts - see that function's
 * own doc comment for why a plain offset rather than a full IANA timezone)
 * currently falls inside their quiet-hours window. `quietHoursStart`/`End`
 * are "H:MM" strings (see NotificationSettings._timeToMap on the Dart
 * side). Correctly handles an overnight window (e.g. 22:00 -> 7:00). Fails
 * open (never blocks) when quiet hours are off, or when this device has
 * never reported a timezone offset - guessing wrong here would silently
 * swallow a real notification, which is worse than occasionally sending
 * one during what might be quiet hours for someone whose timezone this
 * function simply doesn't know yet.
 * @param {object|undefined} settings This account's mirrored
 * NotificationSettings map, if any.
 * @param {number|undefined} tzOffsetMinutes This device's last-known UTC
 * offset in minutes.
 * @return {boolean} True if now falls inside quiet hours for this account.
 */
function isQuietHoursNow(settings, tzOffsetMinutes) {
  if (!settings || settings.quietHoursEnabled !== true) return false;
  if (typeof tzOffsetMinutes !== "number") return false;
  const start = settings.quietHoursStart;
  const end = settings.quietHoursEnd;
  if (typeof start !== "string" || typeof end !== "string") return false;

  const toMinutes = (hhmm) => {
    const parts = hhmm.split(":");
    if (parts.length !== 2) return null;
    const h = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10);
    if (Number.isNaN(h) || Number.isNaN(m)) return null;
    return h * 60 + m;
  };
  const startMin = toMinutes(start);
  const endMin = toMinutes(end);
  if (startMin === null || endMin === null || startMin === endMin) {
    return false;
  }

  const now = new Date();
  const utcMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  const localMinutes = ((utcMinutes + tzOffsetMinutes) % 1440 + 1440) % 1440;

  if (startMin < endMin) {
    return localMinutes >= startMin && localMinutes < endMin;
  }
  // Overnight window, e.g. 22:00 -> 7:00.
  return localMinutes >= startMin || localMinutes < endMin;
}

/**
 * Whether [otherUid] should receive this push, checking every gate in the
 * same order NotificationSettings declares its own fields: this specific
 * room muted, the whole category off, the master switch off, then quiet
 * hours. Missing/unsynced settings default to "send" everywhere, same
 * "helpful by default" philosophy NotificationSettings itself documents on
 * the Dart side - a user this function knows nothing about yet (no
 * mirrored settings) is exactly like a fresh install with all-defaults.
 * @param {string} otherUid The candidate recipient's uid.
 * @param {object} participantData Their own doc in this room's
 * participants subcollection.
 * @return {Promise<{eligible: boolean, locale: string}>} Whether to send,
 * and which language to send it in.
 */
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
  return {eligible: true, locale};
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
  const roomSnap = await db.collection("rooms").doc(roomCode).get();
  if (!roomSnap.exists) return {sent: 0};
  const roomName = (roomSnap.data() || {}).name || "your room";

  const participantsSnap = await db
      .collection("rooms").doc(roomCode).collection("participants").get();

  // ── Large rooms send once a day, not once per finisher ────────────────
  // See FANOUT_MEMBER_LIMIT. The claim is transactional because every
  // member's finish races for it: exactly one call may flip
  // firstFinishNotifiedDate to today, and only that call announces.
  const isLargeRoom = participantsSnap.size > FANOUT_MEMBER_LIMIT;
  if (isLargeRoom) {
    const roomRef = db.collection("rooms").doc(roomCode);
    const wonTheDay = await db.runTransaction(async (txn) => {
      const fresh = await txn.get(roomRef);
      if (!fresh.exists) return false;
      if ((fresh.data() || {}).firstFinishNotifiedDate === todayKey) {
        return false;
      }
      txn.set(roomRef, {firstFinishNotifiedDate: todayKey}, {merge: true});
      return true;
    });
    if (!wonTheDay) {
      return {sent: 0, suppressed: "large-room-already-announced-today"};
    }
  }

  const messageFor = isLargeRoom ? FIRST_TODAY_MESSAGES : MESSAGES;

  const sends = [];
  for (const doc of participantsSnap.docs) {
    if (doc.id === uid) continue;
    const {eligible, locale} = await isEligible(doc.id, doc.data());
    if (!eligible) continue;

    const tokensSnap = await db
        .collection("users").doc(doc.id)
        .collection("fcmTokens").get();
    if (tokensSnap.empty) continue;

    const {title, body} = messageFor[locale](finisherName, roomName);
    for (const tokenDoc of tokensSnap.docs) {
      sends.push(
          admin.messaging().send({
            token: tokenDoc.id,
            notification: {title, body},
            data: {roomCode, type: "roomFinish"},
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
  return {sent: sends.length};
});
