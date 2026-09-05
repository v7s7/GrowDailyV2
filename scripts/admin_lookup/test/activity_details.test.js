'use strict';

/**
 * Tests for the detail chips under every feed row.
 *
 * The feed used to say "3 habits done" and stop, which is the one part an
 * admin could already guess from the ring in the accounts table. These
 * builders turn the documents the scan already holds into the part that
 * settles a question: which habits, at what time, which ones went unmarked,
 * and which of the two Grid disagreements this day is carrying.
 *
 * They are unit-testable because they take documents, not a Firestore
 * handle - scanActivity itself needs a live project, so nothing in this file
 * touches it.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  scheduleLabel,
  humanSpan,
  clip,
  dailyDetails,
  taskDetails,
  habitDetails,
  scalarDetails,
} = require('../lib/activity');
const { summarizeHabitDay, BASE_STYLES } = require('../lib/render');

const QURAN = '64954035-f900-4891-90cd-62e861e3155b';
const GYM = '93bfae4a-8c6c-4a53-8bd9-bf41f0efe1c7';
const WATER = '0d0a6a63-9d64-4e35-bd0e-6d6a9d0f2f11';

const CTX = {
  [QURAN]: { name: 'Quran', category: 'quran' },
  [GYM]: { name: 'Gym', category: 'fitness' },
  [WATER]: { name: 'Water', category: 'health' },
};

/** The chips one day produces, with that day's habits all counted as due. */
function chipsFor(day, scheduled, dayKey, tz) {
  const key = dayKey || '2026-09-05';
  const sum = summarizeHabitDay(day, scheduled || [], {}, key);
  return dailyDetails(day, sum, CTX, key, tz);
}
const textOf = (chips) => chips.map((c) => c.text);

test('a completed habit is named, with the minute it was tapped', () => {
  const chips = chipsFor({
    habitCompletions: { [QURAN]: 1 },
    completedAtMinutes: { [QURAN]: 432 },
    squareStates: { [QURAN]: 'complete' },
  }, [QURAN]);
  const done = chips.find((c) => c.tone === 'done');
  assert.ok(done, 'no completion chip');
  assert.match(done.text, /Quran/);
  assert.match(done.text, /07:12/); // 432 minutes past midnight
});

test('a habit that was due and never touched is listed, not left out', () => {
  // The whole reason the scan now passes scheduled ids in: "3 of 5 done" is
  // only meaningful if the other two can be named.
  const chips = chipsFor({ habitCompletions: { [QURAN]: 1 } }, [QURAN, GYM, WATER]);
  const missed = chips.filter((c) => c.tone === 'miss').map((c) => c.text).join(' | ');
  assert.match(missed, /Gym/);
  assert.match(missed, /Water/);
  assert.match(missed, /not marked/);
});

test('a Grid-only square is called out as paying nothing', () => {
  // The bug this tool was rebuilt around: a square painted outside the
  // reward window writes squareStates and nothing else, so a Room counts the
  // day while the ledger paid for none of it.
  const chips = chipsFor({ squareStates: { [GYM]: 'complete' } }, [GYM]);
  const warn = chips.find((c) => c.tone === 'warn');
  assert.ok(warn, 'no Grid-only chip');
  assert.match(warn.text, /Gym/);
  assert.match(warn.text, /no completion/i);
});

test('a completed-then-un-marked habit reads as taken back, not as done', () => {
  const chips = chipsFor({
    completedAtMinutes: { [QURAN]: 600 },
    squareStates: { [QURAN]: 'none' },
  }, [QURAN]);
  const undo = chips.find((c) => c.tone === 'undo');
  assert.ok(undo, 'no un-marked chip');
  assert.match(undo.text, /un-marked/);
  assert.equal(chips.filter((c) => c.tone === 'done').length, 0);
});

test('what they did comes before what they did not', () => {
  const chips = chipsFor({
    habitCompletions: { [GYM]: 1 },
    squareStates: { [GYM]: 'complete' },
  }, [QURAN, GYM]);
  const tones = chips.map((c) => c.tone);
  assert.ok(tones.indexOf('done') < tones.indexOf('miss'), 'missed habits sorted above done ones');
});

test('completions sort by the time they happened, not by habit id', () => {
  const chips = chipsFor({
    habitCompletions: { [QURAN]: 1, [GYM]: 1 },
    completedAtMinutes: { [QURAN]: 1200, [GYM]: 400 },
    squareStates: { [QURAN]: 'complete', [GYM]: 'complete' },
  }, [QURAN, GYM]);
  const done = chips.filter((c) => c.tone === 'done').map((c) => c.text);
  assert.match(done[0], /Gym/);
  assert.match(done[1], /Quran/);
});

test('the day carries its mood, night review, reflection and takings', () => {
  const texts = textOf(chipsFor({
    mood: 'great',
    nightReviewDone: true,
    dailyReflection: '  alhamdulillah,   a  good day  ',
    totalXpEarned: 40,
    totalGoldEarned: 9,
    timerSeconds: { [QURAN]: 900 },
  }, []));
  assert.ok(texts.some((t) => /Great/.test(t)), 'mood missing');
  assert.ok(texts.some((t) => /Night review/.test(t)), 'night review missing');
  // Whitespace collapsed, so somebody's newlines cannot break the row.
  assert.ok(texts.some((t) => t.includes('alhamdulillah, a good day')), 'reflection missing');
  assert.ok(texts.some((t) => /\+40 XP/.test(t)), 'earnings missing');
  assert.ok(texts.some((t) => /15 min on habit timers/.test(t)), 'timer total missing');
});

test('a day filled in the next morning says so instead of looking wrong', () => {
  // Written 08:00 UTC on the 6th, at a +180 offset, about the 5th.
  const day = { lastUpdated: new Date('2026-09-06T05:00:00Z') };
  const chips = chipsFor(day, [], '2026-09-05', 180);
  const write = chips.find((c) => /Written/.test(c.text));
  assert.ok(write, 'no write-time chip');
  assert.match(write.text, /2026-09-06/);
  assert.equal(write.tone, 'warn');
});

test('a day written on its own date is not flagged', () => {
  const day = { lastUpdated: new Date('2026-09-05T18:00:00Z') };
  const write = chipsFor(day, [], '2026-09-05', 180).find((c) => /Written/.test(c.text));
  assert.ok(write);
  assert.equal(write.tone, 'plain');
  assert.match(write.text, /21:00/);
});

test('a habit the account no longer has is still named as such', () => {
  const chips = dailyDetails(
    { habitCompletions: { 'ghost-id-here': 1 } },
    summarizeHabitDay({ habitCompletions: { 'ghost-id-here': 1 } }, [], {}, '2026-09-05'),
    CTX, '2026-09-05', 0,
  );
  assert.match(chips[0].text, /no longer in this account/);
});

test('a scheduledWeekdays list reads the way the sheet that set it does', () => {
  assert.equal(scheduleLabel([]), 'Every day');          // empty means every day
  assert.equal(scheduleLabel([1, 2, 3, 4, 5, 6, 7]), 'Every day');
  assert.equal(scheduleLabel([1, 2, 3, 4, 5]), 'Weekdays');
  assert.equal(scheduleLabel([6, 7]), 'Weekends');
  assert.equal(scheduleLabel([5, 1, 3]), 'Mon, Wed, Fri');
  assert.equal(scheduleLabel([1, 1, 9, null]), 'Mon');    // junk dropped, not printed
  assert.equal(scheduleLabel(undefined), 'Every day');
});

test('a task carries its quadrant, its star and how long it stayed open', () => {
  const t = {
    title: 'Study the lab', quadrant: 'doFirst', isToday: true, isDone: true,
    description: 'chapters 4 and 5',
    createdAt: new Date('2026-09-05T06:00:00Z'),
    completedAt: new Date('2026-09-05T09:00:00Z'),
    reminderAts: [new Date()],
  };
  const texts = textOf(taskDetails(t, true));
  assert.ok(texts.some((x) => /Do First/.test(x)), 'quadrant missing');
  assert.ok(texts.some((x) => /Starred for today/.test(x)), 'star missing');
  assert.ok(texts.some((x) => /chapters 4 and 5/.test(x)), 'description missing');
  assert.ok(texts.some((x) => /1 reminder\b/.test(x)), 'reminder count missing');
  assert.ok(texts.some((x) => /Open for 3 hours/.test(x)), 'lifetime missing');
});

test('an unfinished task is not described as having taken any time', () => {
  const texts = textOf(taskDetails({
    quadrant: 'schedule', createdAt: new Date('2026-09-05T06:00:00Z'),
  }, false));
  assert.equal(texts.some((x) => /Open for/.test(x)), false);
});

test('a habit carries the cadence it was set up with', () => {
  const texts = textOf(habitDetails({
    name: 'Quran', category: 'quran', scheduledWeekdays: [1, 3, 5],
    frequencyType: 'weekly', frequencyTarget: 3, hasTimer: true,
    timerDurationSeconds: 600, isPreset: true, xpReward: 10, goldReward: 2,
  }));
  assert.ok(texts.some((x) => /Faith/.test(x)), 'category missing');
  assert.ok(texts.some((x) => x === 'Mon, Wed, Fri'), 'schedule missing');
  assert.ok(texts.some((x) => /3× a week/.test(x)), 'weekly target missing');
  assert.ok(texts.some((x) => /10 min timer/.test(x)), 'timer missing');
  assert.ok(texts.some((x) => /Pays 10 XP/.test(x)), 'reward missing');
});

test('scalar details skip nested blobs rather than printing [object Object]', () => {
  const texts = textOf(scalarDetails(
    { level: 7, nested: { a: 1 }, list: [1, 2], empty: '', off: false, on: true },
    [], { level: 'Level' },
  ));
  assert.deepEqual(texts, ['Level: 7', 'on']);
});

test('long free text is cut with an ellipsis rather than blowing out the row', () => {
  assert.equal(clip('abcdefghij', 5), 'abcd…');
  assert.equal(clip('  spaced \n out  ', 40), 'spaced out');
  assert.equal(clip(null, 10), '');
});

test('humanSpan climbs units instead of printing 4320 minutes', () => {
  assert.equal(humanSpan(30 * 1000), 'under a minute');
  assert.equal(humanSpan(20 * 60000), '20 min');
  assert.equal(humanSpan(3 * 3600000), '3 hours');
  assert.equal(humanSpan(3 * 86400000), '3 days');
});

test('every tone these builders emit has a chip style behind it', () => {
  // The two halves live in different files on purpose (meaning here, looks
  // in the stylesheet), and a tone with no rule is an invisible-but-present
  // chip that looks like every other one. This is the seam that catches it.
  const tones = new Set();
  const collect = (chips) => chips.forEach((c) => tones.add(c.tone));
  collect(chipsFor({
    habitCompletions: { [QURAN]: 1 },
    completedAtMinutes: { [QURAN]: 432 },
    squareStates: { [QURAN]: 'complete', [GYM]: 'failed', [WATER]: 'complete' },
    mood: 'good', dailyReflection: 'x', totalXpEarned: 1,
    lastUpdated: new Date('2026-09-05T10:00:00Z'),
  }, [QURAN, GYM, WATER, 'unscheduled-extra']));
  collect(taskDetails({ quadrant: 'doFirst', description: 'x', rewarded: false, isDone: true,
    createdAt: new Date(), completedAt: new Date() }, true));
  collect(habitDetails({ name: 'x', category: 'quran', goalType: 'quit', cueAfter: 'fajr' }));
  assert.ok(tones.size >= 5, `expected several tones, saw ${Array.from(tones).join(', ')}`);
  for (const tone of tones) {
    assert.ok(BASE_STYLES.includes(`.chip-d.${tone}`) || tone === 'plain',
      `no .chip-d.${tone} rule in BASE_STYLES`);
  }
});
