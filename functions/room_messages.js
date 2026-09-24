/**
 * The words of every room push, kept free of Firestore so they can be
 * unit-tested: requiring index.js calls admin.initializeApp(), which needs
 * credentials. roomPushMessage is the one entry point index.js uses.
 *
 * The last-one push:
 *
 * Aziz's pick of 2026-09-11, in the voice of the one reminder he loved: the
 * room's own name as the title, a true fact about the room, and one short
 * ask. «عند نورة كل شي خلص. سوي عادتك الحين ويصير يومكم كامل 🤝» in a room of
 * two, «٤ من ٥ خلّصوا اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝» in a
 * bigger one. It replaced «باقي أنت. إلى الآن فيه وقت.», a verdict about the
 * one person still to go.
 */

const {finishedOn, isStandingDownOn} = require("./room_events");
const {countingHabitIds} = require("./room_health");

/**
 * Western digits to Arabic-Indic, the port of arabicDigits in
 * lib/core/l10n/reminder_copy.dart, so a number in a room push reads the
 * same as one in a reminder.
 * @param {number} n A whole number.
 * @return {string}
 */
function arabicDigits(n) {
  return String(n).replace(/[0-9]/g,
      (d) => String.fromCharCode(d.charCodeAt(0) - 0x30 + 0x0660));
}

/**
 * Names the app writes when it has no real one: index.js's own "Someone"
 * for a doc with no name, and the "Warrior" placeholder
 * (RoomsController._profileFields) for an empty or screened one.
 */
const PLACEHOLDER_NAMES = new Set(["Someone", "Warrior"]);

/**
 * The finisher's name when it is a real one worth saying, else null.
 * @param {string|undefined} name The stored displayName.
 * @return {string|null}
 */
function usableName(name) {
  const trimmed = typeof name === "string" ? name.trim() : "";
  if (!trimmed || PLACEHOLDER_NAMES.has(trimmed)) return null;
  return trimmed;
}

/**
 * Whether the member did anything on [dayKey]. A day with nothing owed
 * also reads allDoneToday, and that member has not "finished" anything to
 * be counted for (RoomParticipant.didCompleteAnythingOn).
 * @param {object} p A participant doc's data.
 * @param {string} dayKey "YYYY-MM-DD".
 * @return {boolean}
 */
function didSomethingOn(p, dayKey) {
  const done = (p.dailyDoneCount || {})[dayKey];
  return typeof done === "number" && done > 0;
}

/**
 * Whether the member owes nothing on [dayKey]: their phone marked the day
 * done with nothing done on it. That is a rest day, a Mon/Wed habit's
 * Tuesday or a weekly quota's spare day once its target is met, which the app
 * writes as allDoneToday (rooms_notifier.dart, todayScheduled == 0).
 * @param {object} p A participant doc's data.
 * @param {string} dayKey "YYYY-MM-DD".
 * @param {object} [room] The room doc's data, see finishedOn.
 * @return {boolean}
 */
function owesNothingOn(p, dayKey, room) {
  return finishedOn(p, dayKey, room) && !didSomethingOn(p, dayKey);
}

/**
 * The room's numbers at the last-one moment, for the reader's push.
 *
 * Two kinds of member are left out of both numbers:
 *   - standing down today (isStandingDownOn): the day leaves both sides of
 *     their score;
 *   - owing nothing today (owesNothingOn). A rest day is not a finish, since
 *     nothing was done, and not a day still to go, since nothing is owed.
 *     Counted as members, it made the sum disagree with the ask: «١ من ٤
 *     خلّصوا اليوم» said three people were still out, then said the reader's
 *     habit alone completes the room's day.
 * The finisher who caused the push always counts as finished; anyone else
 * counts only if today is marked done AND they did something today.
 *
 * Called only for roomEventFor's lastOne event, which found exactly one
 * member not done among those not standing down, and a rest day is done
 * there. So members is always finished + 1, and members is 2 exactly when
 * only the finisher and the reader are left in the count.
 *
 * excluded is how many of [others] were left out. With any, a count of two
 * is not a room of two, and lastOneMessage needs to know that: «الكل خلّص.»
 * there would say the members left out finished too.
 * @param {Array<{data: function(): object}>} others Every member in the room
 * except the finisher, departed members already removed.
 * @param {string} todayKey The finisher's app day, "YYYY-MM-DD".
 * @param {object} [room] The room doc's data, see finishedOn.
 * @return {{members: number, finished: number, excluded: number}}
 */
function lastOneCounts(others, todayKey, room) {
  const counted = others.filter((d) => {
    const p = d.data() || {};
    return !isStandingDownOn(p, todayKey) &&
      !owesNothingOn(p, todayKey, room);
  });
  const finishedOthers = counted.filter((d) => {
    const p = d.data() || {};
    return finishedOn(p, todayKey, room) && didSomethingOn(p, todayKey);
  }).length;
  return {
    members: counted.length + 1,
    finished: finishedOthers + 1,
    excluded: others.length - counted.length,
  };
}

/**
 * How many habits the reader counts in this room today: today's scheduled
 * count when the reader's phone has already written it, else the habits
 * that count for them TODAY (countingHabitIds with the day, so a habit the
 * leader removed stops counting after its removal day), never
 * linkedHabitIds.length.
 * @param {object} room The room doc's data.
 * @param {object} part The reader's participant doc's data.
 * @param {string} todayKey "YYYY-MM-DD".
 * @return {number}
 */
function habitCountFor(room, part, todayKey) {
  const scheduled = (part.dailyScheduledCount || {})[todayKey];
  if (typeof scheduled === "number" && scheduled > 0) return scheduled;
  return countingHabitIds(room || {}, part, todayKey).length;
}

/**
 * How many habits the reader still has to do today, so the ask says
 * «عاداتك» only when more than one is left: habitCountFor less today's
 * dailyDoneCount, and never under 1, since this push only goes to a reader
 * who has not finished. A reader with two habits and one done has one left
 * and is asked «سوي عادتك الحين».
 * @param {object} room The room doc's data.
 * @param {object} part The reader's participant doc's data.
 * @param {string} todayKey "YYYY-MM-DD".
 * @return {number}
 */
function habitsLeftFor(room, part, todayKey) {
  const done = (part.dailyDoneCount || {})[todayKey];
  const doneToday = typeof done === "number" && done > 0 ? done : 0;
  return Math.max(1, habitCountFor(room, part, todayKey) - doneToday);
}

/**
 * The last-one push for one reader.
 * @param {object} args
 * @param {string} args.locale "ar" or "en".
 * @param {string|undefined} args.roomName The room's name, used as the
 * title; «غرفتك» / "Your room" when it has none, so an Arabic reader never
 * gets an English title.
 * @param {string|undefined} args.finisherName The finisher's displayName.
 * @param {number} args.members Members in the room today, from
 * lastOneCounts.
 * @param {number} args.finished Of those, how many finished today.
 * @param {number} [args.excluded] Members lastOneCounts left out of both
 * numbers, 0 when not given. The pair's line opens with the finisher's name,
 * or with «الكل خلّص.» only when nobody was left out. With members left out
 * and no usable name the room is counted instead, «١ من ٢ خلّص اليوم.»,
 * because «الكل» would take in the members left out.
 * @param {number} args.readerHabits How many habits the reader still has to
 * do today, from habitsLeftFor.
 * @return {{title: string, body: string}}
 */
function lastOneMessage(
    {locale, roomName, finisherName, members, finished, excluded = 0,
      readerHabits}) {
  const name = usableName(finisherName);
  const pair = members <= 2 && (name !== null || !excluded);
  const hasName = typeof roomName === "string" && roomName.trim() !== "";
  if (locale === "ar") {
    const title = hasName ? roomName : "غرفتك";
    const ask = readerHabits > 1 ? "سوي عاداتك الحين" : "سوي عادتك الحين";
    if (pair) {
      const opener = name ? `عند ${name} كل شي خلص.` : "الكل خلّص.";
      return {title, body: `${opener} ${ask} ويصير يومكم كامل 🤝`};
    }
    // The verb follows the number: «١ من ٢ خلّص اليوم.» for one, and the
    // picked plural «٤ من ٥ خلّصوا اليوم.» for every other count.
    const verb = finished === 1 ? "خلّص" : "خلّصوا";
    return {
      title,
      body: `${arabicDigits(finished)} من ${arabicDigits(members)} ${verb} ` +
        `اليوم. ${ask} ويصير يوم الغرفة كامل 🤝`,
    };
  }
  const title = hasName ? roomName : "Your room";
  if (pair) {
    const opener = name ? `${name} is all done.` : "Everyone else is done.";
    return {
      title,
      body: `${opener} Do yours now and your day together is complete 🤝`,
    };
  }
  const verb = finished === 1 ? "has" : "have";
  return {
    title,
    body: `${finished} of ${members} ${verb} finished today. Do yours now ` +
      "and the room's day is complete 🤝",
  };
}

/**
 * The last-one push for one reader, read straight off the docs index.js
 * already holds, so the wiring is tested here rather than only in the send
 * loop: the room's stored name (never index.js's English "your room"
 * stand-in), the finisher's stored displayName (never its "Someone"
 * stand-in), the room's counts and how many habits the reader still has
 * to do today.
 * @param {object} args
 * @param {string} args.locale "ar" or "en".
 * @param {object} args.room The room doc's data.
 * @param {object} args.finisher The finisher's participant doc's data.
 * @param {{members: number, finished: number, excluded: number}} args.counts
 * From lastOneCounts.
 * @param {object} args.reader The reader's participant doc's data.
 * @param {string} args.todayKey The finisher's app day, "YYYY-MM-DD".
 * @return {{title: string, body: string}}
 */
function lastOneMessageFor(
    {locale, room, finisher, counts, reader, todayKey}) {
  return lastOneMessage({
    locale,
    roomName: (room || {}).name,
    finisherName: (finisher || {}).displayName,
    members: counts.members,
    finished: counts.finished,
    excluded: counts.excluded,
    readerHabits: habitsLeftFor(room, reader || {}, todayKey),
  });
}

/**
 * Arabic verbs agree with their subject, so the finisher's gender changes
 * the sentence: «أنهى عاداته» for a man, «أنهت عاداتها» for a woman.
 *
 * The app mirrors `gender` onto the participant doc (RoomsController.
 * _profileFields) precisely so the server can pick, since it has no access
 * to the Dart character catalog. Anything other than "female", including a
 * member whose character never loaded, and every doc written before that
 * field existed, falls to the masculine form, which is Arabic's unmarked
 * default and is what shipped previously.
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
 * The room's name for a title, or the reader's own word for "your room"
 * when it has none, so an Arabic reader never gets an English title.
 * @param {object} room The room doc's data.
 * @param {string} locale "ar" or "en".
 * @return {string}
 */
function roomTitleName(room, locale) {
  const name = (room || {}).name;
  if (typeof name === "string" && name.trim() !== "") return name;
  return locale === "ar" ? "غرفتك" : "your room";
}

/**
 * Someone opened the day (index.js's event A). `gender` is the FINISHER's:
 * the sentence is about them. Only ever sent on the day it is about, see
 * push_policy.js roomPushPlan.
 */
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
 * Every member finished (event C). Nobody in particular is the subject, so
 * no gender is needed. Only ever sent on the day it celebrates: the next
 * morning it would tell the reader nothing (push_policy.js rule 3).
 */
const ROOM_PERFECT_MESSAGES = {
  en: (roomName) => ({
    title: `Perfect day in "${roomName}" 🎉`,
    body: "Everyone finished today.",
  }),
  ar: (roomName) => ({
    title: `يوم كامل في "${roomName}" 🎉`,
    body: "الكل خلّص عاداته اليوم.",
  }),
};

/**
 * "A habit was added to the plan", sent to every member of a shared room
 * except the leader who added it.
 *
 * The in-app banner (roomNewHabitBannerBody) only reaches a member who opens
 * the app, and a slot the leader adds starts counting against an unlinked
 * member after the grace (RoomModel.kNewSlotGraceDays), so the people who
 * most need to hear are exactly the ones not looking. Warm and plain: what
 * was added, to which room, and that linking it means it counts for them
 * from today. Impersonal on purpose, no «أضاف/أضافت» about the leader, so
 * nothing has to guess a gender.
 *
 * DRAFT WORDING, Aziz picks the final Arabic.
 */
const HABIT_ADDED_MESSAGES = {
  en: (habitName, roomName) => ({
    title: `New habit in "${roomName}"`,
    body: `"${habitName}" was added to the plan and counts for everyone ` +
      "from today. Link it on your side \u{1F331}",
  }),
  ar: (habitName, roomName) => ({
    title: `عادة جديدة في "${roomName}"`,
    body: `انضافت «${habitName}» للخطة وصارت تنحسب للكل من اليوم. ` +
      "اربطها من عندك \u{1F331}",
  }),
};

/**
 * The words of one room push for one reader. The single place index.js asks,
 * for a push sent now and for a held one at the moment it is delivered, so
 * the two can never word the same event differently.
 * @param {object} args
 * @param {string} args.event "firstToday" | "lastOne" | "perfect" |
 * "habitAdded".
 * @param {string} args.locale "ar" or "en" (anything else reads as "en").
 * @param {object} args.room The room doc's data.
 * @param {object} [args.finisher] The finisher's participant doc's data.
 * @param {object} [args.reader] The reader's participant doc's data.
 * @param {{members: number, finished: number, excluded: number}} [args.counts]
 * lastOne only, from lastOneCounts.
 * @param {string} [args.todayKey] The day the push is about.
 * @param {string} [args.habitName] habitAdded only.
 * @return {{title: string, body: string}}
 */
function roomPushMessage(
    {event, locale, room, finisher, reader, counts, todayKey, habitName}) {
  const lang = locale === "ar" ? "ar" : "en";
  const roomName = roomTitleName(room, lang);
  switch (event) {
    case "lastOne":
      return lastOneMessageFor(
          {locale: lang, room, finisher, counts, reader, todayKey});
    case "perfect":
      return ROOM_PERFECT_MESSAGES[lang](roomName);
    case "habitAdded":
      return HABIT_ADDED_MESSAGES[lang](habitName, roomName);
    default: {
      const f = finisher || {};
      return FIRST_TODAY_MESSAGES[lang](
          f.displayName || "Someone", roomName, f.gender);
    }
  }
}

module.exports = {
  arabicDigits,
  habitCountFor,
  habitsLeftFor,
  isFem,
  lastOneCounts,
  lastOneMessage,
  lastOneMessageFor,
  roomPushMessage,
  usableName,
};
