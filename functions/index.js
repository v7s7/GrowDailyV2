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
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {roomEventFor} = require("./room_events");

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
 * Event B. `gender` is the RECIPIENT's - «باقي أنت» for a man, «باقية
 * أنتِ» for a woman - because unlike every other message here the sentence
 * is about the person reading it, not about whoever finished.
 *
 * Deliberately says الكل خلّص rather than naming one person. Naming the
 * most recent finisher would read as though only they were done, which
 * both understates the situation and turns a fact about the room into a
 * comparison against one member.
 */
const LAST_ONE_MESSAGES = {
  en: (finisherName, roomName) => ({
    title: `Everyone else finished in "${roomName}"`,
    body: "You're the last one. Still time.",
  }),
  ar: (finisherName, roomName, gender) => ({
    title: `الكل خلّص في "${roomName}"`,
    body: isFem(gender) ?
      "باقية أنتِ. لسا في وقت." :
      "باقي أنت. لسا في وقت.",
  }),
};

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
 * instead of LAST_ONE_MESSAGES.
 *
 * Deliberately an invitation and not a scoreboard. «الكل خلّص ـ باقي أنت»
 * reads as banter between friends; «الكل خلّص وأنت لا» reads as an
 * accusation, and these habits are صلاة and أذكار rather than gym sets.
 * Shame motivates for about a week and then people leave.
 *
 * `gender` is the RECIPIENT's, as in LAST_ONE_MESSAGES.
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
 * @return {Promise<{eligible: boolean, locale: string,
 * tzOffsetMinutes: (number|undefined)}>} Whether to send, which language to
 * send it in, and the recipient's UTC offset for day-keying the cap.
 */
/**
 * The most room pushes one person may receive in a day, counted across
 * EVERY room they belong to.
 *
 * Each room used to decide alone, so nothing bounded what a single person
 * actually experienced. A member of four five-person rooms where everyone
 * finishes received sixteen pushes a day, none of which any one room could
 * see. This is the only limit that is expressed in terms of the human being
 * on the receiving end rather than the sending room.
 */
const DAILY_PUSH_CAP_PER_USER = 3;

/**
 * Whether this recipient still has room under the daily cap, incrementing
 * their counter when they do.
 *
 * Kept in a transaction because a person in several rooms can legitimately
 * be sent to by two finishers in different rooms at the same moment, and a
 * plain read-modify-write would let both through.
 *
 * `date` is the recipient's OWN app day, passed in by the caller, so the
 * counter rolls over on their clock rather than UTC.
 * @param {string} otherUid The recipient.
 * @param {string} dayKey Their local day, "YYYY-MM-DD".
 * @return {Promise<boolean>} Whether a push may be sent.
 */
async function claimDailyPushSlot(otherUid, dayKey) {
  const ref = db.collection("users").doc(otherUid);
  try {
    return await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      const quota = (snap.data() || {}).roomPushQuota || {};
      const used = quota.date === dayKey ? (quota.count || 0) : 0;
      if (used >= DAILY_PUSH_CAP_PER_USER) return false;
      txn.set(ref, {roomPushQuota: {date: dayKey, count: used + 1}},
          {merge: true});
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
 * Claim this person's single evening reminder for [dayKey], across every
 * room they are in.
 *
 * Fails CLOSED (unlike claimDailyPushSlot): this push is triggered by
 * inactivity rather than by anything the recipient did, so the cost of an
 * unnecessary one is higher than the cost of a missed one.
 * @param {string} uid The recipient.
 * @param {string} dayKey Their local day, "YYYY-MM-DD".
 * @return {Promise<boolean>} True if this caller won the claim.
 */
async function claimEveningNudge(uid, dayKey) {
  const ref = db.collection("users").doc(uid);
  try {
    return await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      if ((snap.data() || {}).eveningNudgeDate === dayKey) return false;
      txn.set(ref, {eveningNudgeDate: dayKey}, {merge: true});
      return true;
    });
  } catch (err) {
    logger.warn("evening nudge claim failed", uid, err);
    return false;
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
 * Fails CLOSED, unlike claimDailyPushSlot which falls back to sending. The
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
  const roomName = (roomSnap.data() || {}).name || "your room";

  const participantsSnap = await db
      .collection("rooms").doc(roomCode).collection("participants").get();

  // ── Which of the three events did this finish just cause? ─────────────
  // See the message tables at the top of this file for why the unit is an
  // event and not a finisher. `others` excludes the caller, whose own
  // finish is what got us here.
  const others = participantsSnap.docs.filter((d) => d.id !== uid);
  const decision = roomEventFor(others, todayKey);
  if (!decision) return {sent: 0, suppressed: "solo-room"};
  const {event, recipients} = decision;

  // Claimed BEFORE checking whether anyone can actually receive it. The
  // alternative - claim only once a deliverable recipient is found - would
  // reopen the race this closes, since two simultaneous finishers would
  // both get that far. The cost is that an event whose whole audience is
  // asleep, muted or device-less is spent rather than retried, which is
  // intended: a "first to finish today" that goes out on the fifth
  // person's finish is no longer true. roomEveningReminder is what covers
  // a room that ends up hearing nothing.
  if (!await claimRoomEvent(roomCode, event, todayKey)) {
    return {sent: 0, suppressed: event + "-already-sent-today"};
  }

  const messageFor = {
    firstToday: FIRST_TODAY_MESSAGES,
    lastOne: LAST_ONE_MESSAGES,
    perfect: ROOM_PERFECT_MESSAGES,
  }[event];

  const sends = [];
  for (const doc of recipients) {
    const other = doc.data() || {};
    const {eligible, locale, tzOffsetMinutes} =
      await isEligible(doc.id, other);
    if (!eligible) continue;

    const tokensSnap = await db
        .collection("users").doc(doc.id)
        .collection("fcmTokens").get();
    // Checked BEFORE the daily slot is claimed. A person with no registered
    // device cannot receive anything, so spending one of their three daily
    // slots on an undeliverable push would silently exhaust the quota of
    // exactly the people who are already getting nothing.
    if (tokensSnap.empty) continue;
    if (!await claimDailyPushSlot(doc.id, localDayKey(tzOffsetMinutes))) {
      continue;
    }

    // Only event B has a playful variant, and only for the single person
    // it goes to. Any condition failing falls back to the neutral wording,
    // which stays the default for everyone.
    const wantsNudge = event === "lastOne" &&
      await nudgeAllowed(doc.id, other, participantsSnap.size);
    const table = wantsNudge ? NUDGE_MESSAGES : messageFor;
    // Event B's sentence is about the person reading it; A and C are about
    // the finisher. Passing the wrong one here is invisible in English and
    // wrong in every Arabic sentence.
    const gender = event === "lastOne" ? other.gender : finisherGender;
    const {title, body} = table[locale](finisherName, roomName, gender);
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
  return {sent: sends.length, event};
});

/**
 * The evening reminder, sent to a room where NOBODY has finished today.
 *
 * The only push in this file not caused by someone finishing, and the only
 * one triggered by inactivity - which is the closest thing here to
 * nagging, so it is deliberately the narrowest. One per person per room
 * per day, only in a two-hour evening window on their own clock, only when
 * not a single member has moved, and worded as an opening rather than a
 * reprimand: "still time to be first", not "nobody has done anything".
 *
 * It also covers the one hole in the three-event model. Those events are
 * claimed once per room per day, so a room whose whole audience happened
 * to be inside quiet hours when the first person finished hears nothing at
 * all that day. This is the floor under that.
 * @param {string|undefined} gender The RECIPIENT's stored gender.
 */
const EVENING_REMINDER_MESSAGES = {
  en: (roomName) => ({
    title: `Nobody has finished in "${roomName}" yet`,
    body: "There's still time to be first today.",
  }),
  ar: (roomName, gender) => ({
    title: `ما خلّص أحد في "${roomName}" اليوم`,
    body: isFem(gender) ?
      "لسا في وقت تكونين الأولى." :
      "لسا في وقت تكون الأول.",
  }),
};

/** Local-clock window for the evening reminder, [start, end). */
const EVENING_HOUR_START = 19;
const EVENING_HOUR_END = 21;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Hourly sweep for silent rooms.
 *
 * Runs every hour rather than once a day because "evening" is each
 * member's own evening, and members of one room are not necessarily in one
 * timezone - the hour filter below is what actually picks the moment, on
 * the recipient's clock. A member whose device has never reported an
 * offset is skipped outright rather than assumed to be in UTC: guessing
 * wrong here means a push at three in the morning, which is far worse than
 * not sending one.
 */
exports.roomEveningReminder = onSchedule(
    {schedule: "every 60 minutes"},
    async () => {
      const nowMs = Date.now();
      const roomsSnap = await db
          .collection("rooms").where("status", "==", "active").get();
      // Any UTC day that could still be someone's local "today", given
      // real offsets span -12h to +14h.
      const candidateDays = new Set([-1, 0, 1].map((d) =>
        new Date(nowMs + d * DAY_MS).toISOString().slice(0, 10)));

      let sent = 0;
      for (const roomDoc of roomsSnap.docs) {
        const room = roomDoc.data() || {};
        const start = room.startDate && room.startDate.toDate ?
          room.startDate.toDate() : null;
        const end = room.endDate && room.endDate.toDate ?
          room.endDate.toDate() : null;
        // Not yet counting, or already over. endDate is the last day that
        // counts, stored at midnight, so it is live through that whole day.
        if (start && start.getTime() > nowMs) continue;
        if (end && end.getTime() + DAY_MS < nowMs) continue;

        const partsSnap = await roomDoc.ref.collection("participants").get();
        if (partsSnap.size < 2) continue;
        // Cheap pre-filter, and the reason this sweep is affordable: if
        // anyone has finished on any day that could still be current for
        // anyone, the room is not silent and no member needs the per-user
        // timezone read below. Busy rooms cost one read; only genuinely
        // dead ones pay per member.
        const someoneFinished = partsSnap.docs.some((d) => {
          const q = d.data() || {};
          return q.allDoneToday === true && candidateDays.has(q.allDoneDate);
        });
        if (someoneFinished) continue;

        const roomName = room.name || "your room";
        for (const doc of partsSnap.docs) {
          const part = doc.data() || {};
          const {eligible, locale, tzOffsetMinutes} =
            await isEligible(doc.id, part);
          if (!eligible) continue;
          if (typeof tzOffsetMinutes !== "number") continue;

          const local = new Date(nowMs + tzOffsetMinutes * 60 * 1000);
          const hour = local.getUTCHours();
          if (hour < EVENING_HOUR_START || hour >= EVENING_HOUR_END) continue;
          const dayKey = local.toISOString().slice(0, 10);

          const tokensSnap = await db
              .collection("users").doc(doc.id)
              .collection("fcmTokens").get();
          if (tokensSnap.empty) continue;
          // Claimed on the USER, not on this participant doc, so somebody
          // in three silent rooms gets one evening reminder rather than
          // three near-identical ones landing in the same minute. It also
          // covers the two-hour window being wide enough for the hourly
          // schedule to pass through it twice.
          if (!await claimEveningNudge(doc.id, dayKey)) continue;
          if (!await claimDailyPushSlot(doc.id, dayKey)) continue;
          const {title, body} =
            EVENING_REMINDER_MESSAGES[locale](roomName, part.gender);
          for (const tokenDoc of tokensSnap.docs) {
            await admin.messaging().send({
              token: tokenDoc.id,
              notification: {title, body},
              data: {
                roomCode: roomDoc.id,
                type: "roomFinish",
                event: "eveningReminder",
              },
              apns: {payload: {aps: {sound: "default"}}},
            }).then(() => {
              sent++;
            }).catch((err) => {
              const code = err && err.code;
              if (
                code === "messaging/registration-token-not-registered" ||
                code === "messaging/invalid-registration-token"
              ) {
                return tokenDoc.ref.delete().catch(() => {});
              }
              logger.warn("evening reminder push failed", {code, uid: doc.id});
              return null;
            });
          }
        }
      }
      logger.info("roomEveningReminder swept", {
        rooms: roomsSnap.size,
        sent,
      });
    });
