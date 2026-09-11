/**
 * The last-one room push, in Aziz's picked voice (2026-09-11): the room's
 * name as the title, a true fact about the room, one ask, and never a
 * verdict about the one person still to go.
 */

const test = require("node:test");
const assert = require("node:assert");
const {
  arabicDigits,
  habitCountFor,
  habitsLeftFor,
  lastOneCounts,
  lastOneMessage,
  lastOneMessageFor,
  usableName,
} = require("../room_messages");
const {roomEventFor} = require("../room_events");

const DAY = "2026-09-11";
const ROOM = "نادي الفجر";

/**
 * Words that make a push a verdict or a threat, and the spellings the house
 * style bars. First the app's own list, entry for entry (blame in
 * test/core/daily_reminder_copy_test.dart), then the words this push used
 * to say.
 */
const BANNED = [
  "لا تكسر",
  "على المحك",
  "لم يُلوَّن",
  "لا تتوقف",
  "تنتظرك",
  "لا تفقد",
  "ما سويت",
  "بانتظارك",
  "تنتظر",
  "خسارة",
  "يفوت",
  "تفوت",
  "فات",
  "لسا",
  "لسه",
  "لسّه",
  "لسّا",
  "لسة",
  "هذي",
  "باچر",
  "\u2014",
  "Don't break",
  "on the line",
  "No days colored",
  "Don't stop",
  "waiting for you",
  "Don't lose",
  "waiting",
  "slip",
  "A shame",
  // What this push used to say.
  "باقي أنت",
  "باقية أنتِ",
  "last one",
  "Still time",
];

/**
 * «لسا» and «هذي» are barred as words, and «لسا» is also the middle of
 * «السادسة» and «السابعة», as «لسة» is of «جلسة». As in the app's sweep,
 * these six spellings are matched only with no Arabic letter on either side;
 * every other entry is matched anywhere, so a stem like «تنتظر» still
 * catches «تنتظرك».
 *
 * Every barred spelling of «لسا» is here, including the two no line has ever
 * used: «لسّا», which the plain entry cannot catch because the shadda sits
 * inside the word, and «لسة».
 */
const WHOLE_WORDS = new Set(["لسا", "لسه", "لسّه", "لسّا", "لسة", "هذي"]);

/**
 * Whether [line] says [word], by the app's sweep rule.
 * @param {string} line The title or body.
 * @param {string} word An entry of BANNED.
 * @return {boolean}
 */
function says(line, word) {
  if (!WHOLE_WORDS.has(word)) return line.includes(word);
  return new RegExp(`(^|[^\u0600-\u06FF])${word}([^\u0600-\u06FF]|$)`)
      .test(line);
}

const doc = (id, data) => ({id, data: () => data});
const done = (extra = {}) => ({
  allDoneToday: true,
  allDoneDate: DAY,
  dailyDoneCount: {[DAY]: 1},
  ...extra,
});
/** A day with nothing owed: marked done, with nothing done on it. */
const restDay = (extra = {}) => ({
  allDoneToday: true,
  allDoneDate: DAY,
  dailyDoneCount: {},
  ...extra,
});
/**
 * The Arabic body at [counts], for a reader with one habit left.
 * @param {{members: number, finished: number, excluded: number}} counts
 * From lastOneCounts.
 * @param {string} finisherName نورة unless given.
 * @return {string}
 */
const arBody = (counts, finisherName = "نورة") => lastOneMessage({
  locale: "ar",
  roomName: ROOM,
  finisherName,
  members: counts.members,
  finished: counts.finished,
  excluded: counts.excluded,
  readerHabits: 1,
}).body;

test("arabicDigits matches the app's reminder digits", () => {
  assert.strictEqual(arabicDigits(4), "٤");
  assert.strictEqual(arabicDigits(12), "١٢");
  assert.strictEqual(arabicDigits(105), "١٠٥");
});

test("a room of two names the finisher and asks for the reader's part", () => {
  const ar = lastOneMessage({
    locale: "ar",
    roomName: ROOM,
    finisherName: "نورة",
    members: 2,
    finished: 1,
    readerHabits: 1,
  });
  assert.deepStrictEqual(ar, {
    title: ROOM,
    body: "عند نورة كل شي خلص. سوي عادتك الحين ويصير يومكم كامل 🤝",
  });
  const en = lastOneMessage({
    locale: "en",
    roomName: "Fajr Club",
    finisherName: "Noura",
    members: 2,
    finished: 1,
    readerHabits: 1,
  });
  assert.deepStrictEqual(en, {
    title: "Fajr Club",
    body: "Noura is all done. Do yours now and your day together is " +
      "complete 🤝",
  });
});

test("a placeholder or missing name is never said out loud", () => {
  for (const finisherName of ["Warrior", "Someone", "", "  ", undefined]) {
    const {body} = lastOneMessage({
      locale: "ar",
      roomName: ROOM,
      finisherName,
      members: 2,
      finished: 1,
      readerHabits: 1,
    });
    assert.strictEqual(
        body, "الكل خلّص. سوي عادتك الحين ويصير يومكم كامل 🤝",
        `name ${JSON.stringify(finisherName)}`);
  }
  assert.strictEqual(usableName(" نورة "), "نورة");
});

test("«الكل خلّص.» is said only when nobody was left out of the count", () => {
  const args = {
    roomName: ROOM,
    finisherName: "Warrior",
    members: 2,
    finished: 1,
    readerHabits: 1,
  };
  // Three in the room and one standing down: two in the count, but «الكل»
  // would say the member standing down finished too. The room is counted.
  assert.strictEqual(
      lastOneMessage({...args, locale: "ar", excluded: 1}).body,
      "١ من ٢ خلّص اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
  assert.strictEqual(
      lastOneMessage({...args, locale: "en", excluded: 1}).body,
      "1 of 2 has finished today. Do yours now and the room's day is " +
      "complete 🤝");
  // A real room of two keeps «الكل خلّص.».
  assert.strictEqual(
      lastOneMessage({...args, locale: "ar", excluded: 0}).body,
      "الكل خلّص. سوي عادتك الحين ويصير يومكم كامل 🤝");
  // A usable name says something true of that one person, so it stays.
  assert.strictEqual(lastOneMessage({
    ...args,
    locale: "ar",
    finisherName: "نورة",
    excluded: 1,
  }).body, "عند نورة كل شي خلص. سوي عادتك الحين ويصير يومكم كامل 🤝");
  // Read off the docs: a member standing down, and no displayName.
  const others = [doc("paused", {standDownDays: [DAY]}), doc("reader", {})];
  const counts = lastOneCounts(others, DAY);
  assert.deepStrictEqual(counts, {members: 2, finished: 1, excluded: 1});
  assert.strictEqual(lastOneMessageFor({
    locale: "ar",
    room: {name: ROOM},
    finisher: {},
    counts,
    reader: {linkedHabitIds: ["a"]},
    todayKey: DAY,
  }).body, "١ من ٢ خلّص اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
});

test("a room of three or more counts the room in Arabic-Indic digits", () => {
  const {title, body} = lastOneMessage({
    locale: "ar",
    roomName: ROOM,
    finisherName: "نورة",
    members: 5,
    finished: 4,
    readerHabits: 1,
  });
  assert.strictEqual(title, ROOM);
  assert.strictEqual(body,
      "٤ من ٥ خلّصوا اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
  assert.strictEqual(lastOneMessage({
    locale: "en",
    roomName: "Fajr Club",
    finisherName: "Noura",
    members: 5,
    finished: 4,
    readerHabits: 1,
  }).body, "4 of 5 have finished today. Do yours now and the room's day " +
    "is complete 🤝");
});

test("the verb follows the number, in both languages", () => {
  // Aziz's plural is for every count but one. One finisher happens in a room
  // counted as two once members are left out, with no usable name to say.
  const body = (locale, members, finished) => lastOneMessage({
    locale,
    roomName: ROOM,
    finisherName: "Warrior",
    members,
    finished,
    excluded: 1,
    readerHabits: 1,
  }).body;
  assert.strictEqual(body("ar", 2, 1),
      "١ من ٢ خلّص اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
  assert.strictEqual(body("en", 2, 1),
      "1 of 2 has finished today. Do yours now and the room's day is " +
      "complete 🤝");
  assert.strictEqual(body("ar", 5, 4),
      "٤ من ٥ خلّصوا اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
  assert.strictEqual(body("en", 5, 4),
      "4 of 5 have finished today. Do yours now and the room's day is " +
      "complete 🤝");
  // Every other count keeps the plural.
  for (let finished = 2; finished <= 12; finished++) {
    const members = finished + 1;
    const label = `${finished} of ${members}`;
    assert.ok(body("ar", members, finished).startsWith(
        `${arabicDigits(finished)} من ${arabicDigits(members)} ` +
        "خلّصوا اليوم."), label);
    assert.ok(body("en", members, finished).startsWith(
        `${finished} of ${members} have finished today.`), label);
  }
});

test("a reader with more than one habit is asked for عاداتك", () => {
  for (const members of [2, 6]) {
    const {body} = lastOneMessage({
      locale: "ar",
      roomName: ROOM,
      finisherName: "نورة",
      members,
      finished: members - 1,
      readerHabits: 3,
    });
    assert.ok(body.includes("سوي عاداتك الحين"), body);
    assert.ok(!body.includes("سوي عادتك الحين"), body);
  }
});

test("the ask counts the reader's habits still left today", () => {
  const reader = (extra) => ({linkedHabitIds: ["a", "b"], ...extra});
  // Two today, none done: two left.
  assert.strictEqual(habitsLeftFor({},
      reader({dailyScheduledCount: {[DAY]: 2}}), DAY), 2);
  // Two today, one done: one left.
  assert.strictEqual(habitsLeftFor({}, reader({
    dailyScheduledCount: {[DAY]: 2},
    dailyDoneCount: {[DAY]: 1},
  }), DAY), 1);
  // Yesterday's count takes nothing off today.
  assert.strictEqual(habitsLeftFor({}, reader({
    dailyScheduledCount: {[DAY]: 2},
    dailyDoneCount: {"2026-09-10": 2},
  }), DAY), 2);
  // Never under one: the push only goes to a reader still to finish.
  assert.strictEqual(habitsLeftFor({}, reader({
    dailyScheduledCount: {[DAY]: 2},
    dailyDoneCount: {[DAY]: 5},
  }), DAY), 1);
  // Through the docs: a room of five, and a reader with two habits today
  // and one of them done hears عادتك, not عاداتك.
  assert.strictEqual(lastOneMessageFor({
    locale: "ar",
    room: {name: ROOM},
    finisher: {displayName: "نورة"},
    counts: {members: 5, finished: 4, excluded: 0},
    reader: reader({
      dailyScheduledCount: {[DAY]: 2},
      dailyDoneCount: {[DAY]: 1},
    }),
    todayKey: DAY,
  }).body, "٤ من ٥ خلّصوا اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
});

test("no last-one push carries a word of blame", () => {
  for (const locale of ["ar", "en"]) {
    for (const members of [2, 3, 5, 12, 200]) {
      for (const excluded of [0, 1]) {
        for (const finisherName of ["نورة", "Noura", "Warrior", undefined]) {
          for (const readerHabits of [1, 2, 11]) {
            const {title, body} = lastOneMessage({
              locale,
              roomName: ROOM,
              finisherName,
              members,
              finished: members - 1,
              excluded,
              readerHabits,
            });
            for (const word of BANNED) {
              assert.ok(!says(body, word), `"${body}" says "${word}"`);
              assert.ok(!says(title, word), `"${title}" says "${word}"`);
            }
          }
        }
      }
    }
  }
  // The sweep's own rule, so a broken matcher cannot pass everything.
  assert.ok(says("لسا ما خلّص", "لسا"));
  assert.ok(!says("الساعة السادسة", "لسا"));
  assert.ok(says("لسّا ما خلّص", "لسّا"));
  assert.ok(says("لسة ما خلّص", "لسة"));
  assert.ok(!says("جلسة الصباح", "لسة"));
  assert.ok(says("عاداتك تنتظرك", "تنتظر"));
  // A whole word swept but not banned would sweep for nothing.
  for (const word of WHOLE_WORDS) assert.ok(BANNED.includes(word), word);
});

test("the counts skip members standing down today", () => {
  const others = [
    doc("u1", done()),
    doc("u2", {standDownDays: [DAY]}),
    doc("u3", {}),
  ];
  // The finisher, u1 and u3 are in today's room; u2 is standing down.
  assert.deepStrictEqual(
      lastOneCounts(others, DAY), {members: 3, finished: 2, excluded: 1});
  // Standing down on another day changes nothing about today.
  const otherDay = [doc("u1", done()), doc("u2", {standDownDays: ["2026-09-10"]})];
  assert.deepStrictEqual(
      lastOneCounts(otherDay, DAY), {members: 3, finished: 2, excluded: 0});
});

test("finished means did something today", () => {
  // The reader's phone marked yesterday done; today they have not finished.
  const others = [
    doc("did", done()),
    doc("reader", {
      allDoneToday: true,
      allDoneDate: "2026-09-10",
      dailyDoneCount: {"2026-09-10": 2},
    }),
  ];
  assert.deepStrictEqual(
      lastOneCounts(others, DAY), {members: 3, finished: 2, excluded: 0});
});

test("a member who owes nothing today is in neither number", () => {
  // A quota rest day, or a Mon/Wed habit's Tuesday: the app writes
  // allDoneToday with nothing done (rooms_notifier.dart, todayScheduled 0).
  // Three in the room, one resting: only the finisher and the reader owe
  // today, so the reader hears the pair's line, not «١ من ٣».
  const three = [doc("rest", restDay()), doc("reader", {})];
  assert.deepStrictEqual(
      lastOneCounts(three, DAY), {members: 2, finished: 1, excluded: 1});
  assert.strictEqual(arBody(lastOneCounts(three, DAY)),
      "عند نورة كل شي خلص. سوي عادتك الحين ويصير يومكم كامل 🤝");
  // Four, one resting: two of three finished, and the sum adds up.
  const four = [
    doc("did", done()),
    doc("rest", restDay({dailyDoneCount: {[DAY]: 0}})),
    doc("reader", {}),
  ];
  assert.deepStrictEqual(
      lastOneCounts(four, DAY), {members: 3, finished: 2, excluded: 1});
  assert.strictEqual(arBody(lastOneCounts(four, DAY)),
      "٢ من ٣ خلّصوا اليوم. سوي عادتك الحين ويصير يوم الغرفة كامل 🤝");
  // Four, two resting: the pair's line again, never «١ من ٤».
  const twoResting = [
    doc("r1", restDay()),
    doc("r2", restDay()),
    doc("reader", {}),
  ];
  assert.deepStrictEqual(
      lastOneCounts(twoResting, DAY), {members: 2, finished: 1, excluded: 2});
  // A rest day stamped yesterday excuses nothing today.
  const stale = [
    doc("did", done()),
    doc("reader", restDay({allDoneDate: "2026-09-10"})),
  ];
  assert.deepStrictEqual(
      lastOneCounts(stale, DAY), {members: 3, finished: 2, excluded: 0});
});

test("a pause no sync has lifted is left out of the counts", () => {
  // Paused on the 8th and not opened since: no key for today, but the last
  // day the phone synced was the stand-down itself.
  const others = [
    doc("did", done()),
    doc("paused", {
      standDownDays: ["2026-09-08"],
      lastSyncedDay: "2026-09-08",
    }),
    doc("reader", {lastSyncedDay: DAY}),
  ];
  assert.deepStrictEqual(
      lastOneCounts(others, DAY), {members: 3, finished: 2, excluded: 1});
});

test("the two numbers always leave exactly the reader still to go", () => {
  const kinds = {
    done: () => done(),
    resting: () => restDay(),
    standingDown: () => ({standDownDays: [DAY], lastSyncedDay: DAY}),
    pausedEarlier: () => ({
      standDownDays: ["2026-09-08"],
      lastSyncedDay: "2026-09-08",
    }),
    open: () => ({lastSyncedDay: DAY}),
    doneYesterday: () => ({
      allDoneToday: true,
      allDoneDate: "2026-09-10",
      dailyDoneCount: {"2026-09-10": 1},
    }),
  };
  const names = Object.keys(kinds);
  let lastOnes = 0;
  // Every room of one to five other members, each of one kind above.
  const visit = (room) => {
    if (room.length > 0) {
      const others = room.map((kind, i) => doc(`u${i}`, kinds[kind]()));
      const decision = roomEventFor(others, DAY);
      if (decision && decision.event === "lastOne") {
        lastOnes++;
        const label = room.join(",");
        const counts = lastOneCounts(others, DAY);
        assert.strictEqual(counts.members, counts.finished + 1, label);
        assert.strictEqual(
            counts.members + counts.excluded, others.length + 1, label);
        const body = arBody(counts);
        // The same room with no usable finisher name.
        const unnamed = arBody(counts, "Warrior");
        if (counts.members === 2) {
          assert.ok(body.startsWith("عند نورة كل شي خلص."), label);
          assert.ok(unnamed.startsWith(counts.excluded === 0 ?
            "الكل خلّص." : "١ من ٢ خلّص اليوم."), label);
        } else {
          assert.ok(counts.finished >= 2, label);
          assert.ok(body.startsWith(
              `${arabicDigits(counts.finished)} من ` +
              `${arabicDigits(counts.members)} خلّصوا اليوم.`), label);
          assert.strictEqual(unnamed, body, label);
        }
      }
    }
    if (room.length === 5) return;
    for (const kind of names) visit([...room, kind]);
  };
  visit([]);
  assert.ok(lastOnes > 0);
});

test("an unnamed room is titled in the reader's own language", () => {
  for (const roomName of [undefined, "", "   "]) {
    const args = {
      roomName,
      finisherName: "نورة",
      members: 2,
      finished: 1,
      readerHabits: 1,
    };
    assert.strictEqual(lastOneMessage({...args, locale: "ar"}).title, "غرفتك");
    assert.strictEqual(
        lastOneMessage({...args, locale: "en"}).title, "Your room");
  }
});

test("lastOneMessageFor words the push from the stored docs", () => {
  // No stored room name and no displayName: «غرفتك» and «الكل خلّص.», never
  // index.js's "your room" and "Someone" stand-ins.
  assert.deepStrictEqual(lastOneMessageFor({
    locale: "ar",
    room: {},
    finisher: {},
    counts: {members: 2, finished: 1, excluded: 0},
    reader: {linkedHabitIds: ["a"]},
    todayKey: DAY,
  }), {
    title: "غرفتك",
    body: "الكل خلّص. سوي عادتك الحين ويصير يومكم كامل 🤝",
  });
  // The room's name, the finisher's name, the counts, and the reader's own
  // two habits today, neither done yet.
  assert.deepStrictEqual(lastOneMessageFor({
    locale: "ar",
    room: {name: ROOM},
    finisher: {displayName: "نورة"},
    counts: {members: 5, finished: 4, excluded: 0},
    reader: {dailyScheduledCount: {[DAY]: 2}},
    todayKey: DAY,
  }), {
    title: ROOM,
    body: "٤ من ٥ خلّصوا اليوم. سوي عاداتك الحين ويصير يوم الغرفة كامل 🤝",
  });
  assert.strictEqual(lastOneMessageFor({
    locale: "en",
    room: {name: "Fajr Club"},
    finisher: {displayName: "Noura"},
    counts: {members: 2, finished: 1, excluded: 0},
    reader: {linkedHabitIds: ["a"]},
    todayKey: DAY,
  }).body, "Noura is all done. Do yours now and your day together is " +
    "complete 🤝");
});

test("the reader's habit count prefers today's scheduled count", () => {
  const room = {habitMode: "shared", sharedHabits: [{}, {removedAt: 1}, {}]};
  assert.strictEqual(
      habitCountFor(room, {dailyScheduledCount: {[DAY]: 2},
        linkedHabitIds: ["a", "b", "c"]}, DAY), 2);
  // Not written yet today: the habits that count, a removed slot left out.
  assert.strictEqual(
      habitCountFor(room, {linkedHabitIds: ["a", "b", "c"]}, DAY), 2);
  assert.strictEqual(
      habitCountFor({}, {linkedHabitIds: ["a", "__declined__"]}, DAY), 1);
});
