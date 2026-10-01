'use strict';

/**
 * The Reminders tab (lib/reminders.js, lib/reminders_page.js): when each of
 * an account's reminders next rings, worked out with the phone's own rules.
 *
 * Every clock here is pinned. NOW is Sunday 27 September 2026, 03:00 in
 * Bahrain (UTC+3), when Fajr is 04:11 by the official table the app ships
 * (and 04:11 again on the 28th). Default quiet hours are 22:00 to 07:00.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');

const R = require('../lib/reminders');
const { renderRemindersSection, utcLabel } = require('../lib/reminders_page');
const { bahrainDay, isInBahrain, prayerTimesFor, bahrainTable } = require('../lib/prayer_times');
const { catalogHabitDocs } = require('../lib/habit_catalog');
const { renderTaskDetail, buildReportBody } = require('../lib/render');

const H = 3600000;
const D = 24 * H;
const BH = 180; // Bahrain, UTC+3
/** A Bahrain wall-clock moment on a September/October 2026 day. */
const bh = (day, hh, mm = 0, month = 9) => Date.UTC(2026, month - 1, day, hh, mm) - BH * 60000;
const NOW = bh(27, 3); // Sunday 27 Sep 2026, 03:00

// Bahrain coordinates for the lookup only; the tests below check they never
// reach the page.
const MANAMA = { lat: 26.2285, lng: 50.586, label: 'المنامة، البحرين', auto: true };
const DUBAI = { lat: 25.2048, lng: 55.2708, label: 'دبي', auto: true };

const ts = (ms) => ({ toDate: () => new Date(ms) });
const doc = (id, data, extra) => ({ id, data: () => ({ ...data }), ...extra });

function profile(settings, extra) {
  return {
    tzOffsetMinutes: BH,
    locale: 'ar',
    notificationSettings: settings === undefined
      ? { masterEnabled: true, habitRemindersEnabled: true, location: MANAMA }
      : settings,
    ...extra,
  };
}

function habit(id, data) {
  return doc(id, { name: id, createdAt: '2026-09-01T00:00:00.000', frequencyType: 'daily', frequencyTarget: 1, ...data });
}

function model(habits, opts = {}) {
  return R.buildRemindersModel({
    profile: opts.profile || profile(),
    habitDocs: habits,
    taskDocs: opts.tasks || [],
    dailyDocs: opts.daily || [],
    tokenDocs: opts.tokens || [],
    nowMs: opts.now || NOW,
    forFile: opts.forFile || false,
  });
}

const slotsOf = (m, id) => m.habits.find((h) => h.id === id).slots;
const whenOf = (m, ms) => `${R.localOf(ms, m.clock.offset).key} ${R.fmtClock(R.localOf(ms, m.clock.offset).minute)}`;

// ---- The cue, read the way HabitCue.fromStoredValue reads it ----

test('a prayer cue is recognised in every form the app ever stored', () => {
  for (const v of ['fajr', 'Fajr', ' FAJR ', 'الفجر']) {
    assert.deepStrictEqual(R.parseCue(v), { kind: 'prayer', prayerKey: 'fajr' }, v);
  }
  assert.deepStrictEqual(R.parseCue('المغرب'), { kind: 'prayer', prayerKey: 'maghrib' });
});

test('a routine has no clock time, and neither do their own words', () => {
  assert.deepStrictEqual(R.parseCue('before_sleep'), { kind: 'routine', routineKey: 'before_sleep' });
  assert.deepStrictEqual(R.parseCue('قبل النوم'), { kind: 'routine', routineKey: 'before_sleep' });
  assert.deepStrictEqual(R.parseCue('after my coffee'), { kind: 'text' });
  assert.deepStrictEqual(R.parseCue(''), { kind: 'none' });
  assert.deepStrictEqual(R.parseCue(null), { kind: 'none' });
  assert.deepStrictEqual(R.parseCue('custom_time:'), { kind: 'none' });
});

test('picked times come back earliest first, one per minute, the first shift of a repeat kept', () => {
  assert.deepStrictEqual(R.parseCue('custom_time:06:00'), { kind: 'clock', times: [{ at: 360, shift: 0 }] });
  assert.deepStrictEqual(R.parseCue('custom_time:20:00+10,08:00-15,08:00+5'), {
    kind: 'clock', times: [{ at: 480, shift: -15 }, { at: 1200, shift: 10 }],
  });
  // Arabic-Indic digits are read as digits, as the phone reads them.
  assert.deepStrictEqual(R.parseCue('custom_time:٠٦:٣٠'), { kind: 'clock', times: [{ at: 390, shift: 0 }] });
});

test('a prayer per time comes back in the order of the day, each pair once', () => {
  assert.deepStrictEqual(R.parseCue('custom_time:isha,fajr+30,fajr-30,isha'), {
    kind: 'prayers',
    slots: [
      { prayerKey: 'fajr', shift: -30 },
      { prayerKey: 'fajr', shift: 30 },
      { prayerKey: 'isha', shift: 0 },
    ],
  });
  // A prayer among clock times is not something the app writes: damage.
  assert.deepStrictEqual(R.parseCue('custom_time:fajr,07:30'), { kind: 'damaged' });
  // Each slot is its own reminder, with its own shift; the habit's are unused.
  const plan = R.habitReminder({
    cueAfter: 'custom_time:fajr-30,fajr+30', reminderOffsetMinutes: 15, extraReminderOffsets: [5],
  });
  assert.deepStrictEqual(plan.slots, [
    { prayerKey: 'fajr', offset: -30 },
    { prayerKey: 'fajr', offset: 30 },
  ]);
});

test('a custom_time the app cannot read is damage, never their own words', () => {
  for (const v of ['custom_time:25:00', 'custom_time:6:00', 'custom_time:06:00x', 'custom_time:06:60']) {
    assert.deepStrictEqual(R.parseCue(v), { kind: 'damaged' }, v);
  }
});

test('the 12-hour text an older build stored still reads as a time, in both languages', () => {
  assert.deepStrictEqual(R.parseCue('7:30 PM'), { kind: 'clock', times: [{ at: 1170, shift: 0 }] });
  assert.deepStrictEqual(R.parseCue('12:15 am'), { kind: 'clock', times: [{ at: 15, shift: 0 }] });
  assert.deepStrictEqual(R.parseCue('٧:٣٠ م'), { kind: 'clock', times: [{ at: 1170, shift: 0 }] });
  assert.deepStrictEqual(R.parseCue('12:00 ص'), { kind: 'clock', times: [{ at: 0, shift: 0 }] });
});

// ---- A habit's slots, in the phone's slot order ----

test('one time with a stack: the habit\'s shift first, then each other shift once', () => {
  const r = R.habitReminder({ cueAfter: 'custom_time:09:00', reminderOffsetMinutes: -10, extraReminderOffsets: [30, 0, -10, 0] });
  assert.deepStrictEqual(r.slots.map((s) => [s.at, s.offset]), [[540, -10], [540, 0], [540, 30]]);
  assert.strictEqual(r.perOccurrence, 3);
});

test('two or more times answer from their own shifts, and the habit\'s shift and stack are not used', () => {
  const r = R.habitReminder({ cueAfter: 'custom_time:08:00-15,20:00', reminderOffsetMinutes: 30, extraReminderOffsets: [5] });
  assert.deepStrictEqual(r.slots.map((s) => [s.at, s.offset]), [[480, -15], [1200, 0]]);
  assert.strictEqual(r.perOccurrence, 1);
});

test('a prayer takes the habit\'s shift and then its stack', () => {
  const r = R.habitReminder({ cueAfter: 'fajr', reminderOffsetMinutes: -15, extraReminderOffsets: [0, 30] });
  assert.deepStrictEqual(r.slots.map((s) => [s.prayerKey, s.offset]), [['fajr', -15], ['fajr', 0], ['fajr', 30]]);
});

test('the old reminderLeadMinutes counts backwards, and only when the new field is missing', () => {
  assert.strictEqual(R.primaryOffset({ reminderLeadMinutes: 20 }), -20);
  assert.strictEqual(R.primaryOffset({ reminderLeadMinutes: 20, reminderOffsetMinutes: 0 }), 0);
  assert.strictEqual(R.primaryOffset({}), 0);
});

test('a quit habit never rings as an alarm, and a weekly habit is one a day', () => {
  const quit = R.habitReminder({ cueAfter: 'custom_time:21:00', goalType: 'quit', alarm: true });
  assert.strictEqual(quit.alarm, false);
  assert.strictEqual(quit.isQuit, true);
  assert.strictEqual(R.habitReminder({ frequencyType: 'weekly', frequencyTarget: 3 }).dailyTarget, 1);
  assert.strictEqual(R.habitReminder({ frequencyType: 'daily', frequencyTarget: 3 }).dailyTarget, 3);
});

test('a slot in words', () => {
  assert.strictEqual(R.slotLabel({ prayerKey: 'fajr', offset: 0 }), 'At Fajr');
  assert.strictEqual(R.slotLabel({ prayerKey: 'isha', offset: -15 }), '15 min before Isha');
  assert.strictEqual(R.slotLabel({ at: 360, offset: 90 }), '1 h 30 min after 06:00');
  assert.strictEqual(R.slotLabel({ at: 360, offset: -120 }), '2 h before 06:00');
});

// ---- Prayer times ----

test('the Bahrain table gives the phone\'s own instants', () => {
  const day = bahrainDay('2026-09-27');
  assert.strictEqual(day.fajr, bh(27, 4, 11));
  assert.strictEqual(day.isha, bh(27, 18, 45));
  assert.strictEqual(bahrainDay('2030-01-01'), null);
  assert.ok(isInBahrain(MANAMA.lat, MANAMA.lng));
  assert.ok(!isInBahrain(DUBAI.lat, DUBAI.lng));
  assert.strictEqual(prayerTimesFor(DUBAI).dayTimes('2026-09-27'), null);
  assert.strictEqual(prayerTimesFor(null).source, 'none');
  assert.ok(bahrainTable().last >= '2027-01-01');
});

// ---- When they ring ----

test('a prayer reminder rings at that day\'s prayer plus its shift', () => {
  const m = model([habit('sunnah', { cueAfter: 'fajr', reminderOffsetMinutes: -15, extraReminderOffsets: [0] })]);
  const [before, at] = slotsOf(m, 'sunnah');
  assert.strictEqual(before.state, 'rings');
  assert.strictEqual(before.next, bh(27, 3, 56));
  assert.strictEqual(at.next, bh(27, 4, 11));
});

test('done today takes down today\'s prayer reminders only', () => {
  const daily = [doc('2026-09-27', { habitCompletions: { sunnah: 1 } })];
  const m = model([habit('sunnah', { cueAfter: 'fajr', reminderOffsetMinutes: -15 })], { daily });
  const [slot] = slotsOf(m, 'sunnah');
  assert.strictEqual(slot.next, bh(28, 3, 56));
  assert.strictEqual(slot.doneToday, true);
});

test('a quit habit answered «ما التزمت» today counts as answered', () => {
  const daily = [doc('2026-09-27', { squareStates: { smoke: 'failed' } })];
  const m = model([habit('smoke', { cueAfter: 'custom_time:21:00', goalType: 'quit' })], { daily, now: bh(27, 12) });
  const [slot] = slotsOf(m, 'smoke');
  assert.strictEqual(slot.next, bh(28, 21));
  assert.strictEqual(slot.doneToday, true);
});

test('a habit resting today («راحة», stored skipped) rings from tomorrow, and says why', () => {
  // The phone puts a rested day with the covered days (main.dart's
  // _excusedDaysById): nothing is owed on it, so nothing rings on it.
  const daily = [doc('2026-09-27', { squareStates: { walk: 'skipped' } })];
  const m = model([habit('walk', { cueAfter: 'custom_time:21:00' })], { daily, now: bh(27, 12) });
  const [slot] = slotsOf(m, 'walk');
  assert.strictEqual(slot.next, bh(28, 21));
  assert.strictEqual(slot.restingToday, true);
  assert.ok(!slot.doneToday, 'resting is not done');
  const { html } = renderRemindersSection(m);
  assert.match(html, /resting today \(راحة\)/);
  assert.doesNotMatch(html, /done today, so/);
});

test('a rest on another habit, or on another day, takes nothing down', () => {
  const daily = [
    doc('2026-09-27', { squareStates: { other: 'skipped' } }),
    doc('2026-09-26', { squareStates: { walk: 'skipped' } }),
  ];
  const m = model([habit('walk', { cueAfter: 'custom_time:21:00' })], { daily, now: bh(27, 12) });
  const [slot] = slotsOf(m, 'walk');
  assert.strictEqual(slot.next, bh(27, 21));
  assert.ok(!slot.restingToday);
});

test('a clock reminder inside quiet hours never rings, unless it is an alarm or allowed anyway', () => {
  const m = model([
    habit('early', { cueAfter: 'custom_time:05:00' }),
    habit('alarm', { cueAfter: 'custom_time:05:00', alarm: true }),
    habit('allowed', { cueAfter: 'custom_time:05:00', ignoreQuietHours: true }),
  ]);
  assert.strictEqual(slotsOf(m, 'early')[0].state, 'quiet');
  assert.strictEqual(slotsOf(m, 'alarm')[0].next, bh(27, 5));
  assert.strictEqual(slotsOf(m, 'allowed')[0].next, bh(27, 5));
});

test('prayer reminders ring through quiet hours unless quiet hours are set to cover prayers', () => {
  const fajr = habit('fajr_h', { cueAfter: 'fajr' });
  assert.strictEqual(slotsOf(model([fajr]), 'fajr_h')[0].next, bh(27, 4, 11));
  const covered = profile({ masterEnabled: true, location: MANAMA, quietHoursAppliesToPrayer: true });
  assert.strictEqual(slotsOf(model([fajr], { profile: covered }), 'fajr_h')[0].state, 'quiet');
});

test('a build since quiet hours went off by default answers with its own key', () => {
  // Such a build writes its switch as quietHoursOn and the old key as true,
  // for the server; the old key alone is an older build's switch, on by
  // default (every other test here reads one of those).
  const newOff = profile({ masterEnabled: true, location: MANAMA, quietHoursOn: false, quietHoursEnabled: true });
  const newOn = profile({ masterEnabled: true, location: MANAMA, quietHoursOn: true, quietHoursEnabled: true });
  const early = habit('early', { cueAfter: 'custom_time:05:00' });
  assert.strictEqual(slotsOf(model([early], { profile: newOff }), 'early')[0].next, bh(27, 5));
  assert.strictEqual(slotsOf(model([early], { profile: newOn }), 'early')[0].state, 'quiet');
  const evening = (p) => model([habit('h', {})], { profile: { ...p, reminderTime: '22:0' } }).evening.state;
  assert.strictEqual(evening(newOff), 'rings', 'the 22:00 note the old default swallowed');
  assert.strictEqual(evening(newOn), 'quiet');

  // The tab says which build's reading it is, and that pushes from others
  // still wait out the night.
  const offHtml = renderRemindersSection(model([early], { profile: newOff })).html;
  assert.match(offHtml, /Off: every reminder rings at its time\. Room pushes and your messages still wait out the night, 22:00 to 07:00\./);
  assert.doesNotMatch(offHtml, /as a build before quiet hours went off by default reads it/);
  const oldHtml = renderRemindersSection(model([early])).html;
  assert.match(oldHtml, /22:00 to 07:00\.[^<]*Room pushes and your messages wait until it ends\. <span class="rem-why">as a build before quiet hours went off by default reads it/);
});

test('a reminder lands on the habit\'s own days, judged on the day the shift lands it', () => {
  // Mondays only. From Sunday 03:00: Sunday 23:40 is Monday's 00:10 pulled
  // back into Sunday, not a Monday, so the first one is Monday 23:40.
  // "Allow anyway", or quiet hours would silence every one of them.
  const m = model([habit('mon', {
    cueAfter: 'custom_time:00:10', reminderOffsetMinutes: -30, scheduledWeekdays: [1], ignoreQuietHours: true,
  })]);
  assert.strictEqual(slotsOf(m, 'mon')[0].next, bh(28, 23, 40));
  const quiet = model([habit('mon', { cueAfter: 'custom_time:00:10', reminderOffsetMinutes: -30, scheduledWeekdays: [1] })]);
  assert.strictEqual(slotsOf(quiet, 'mon')[0].state, 'quiet');
  const m2 = model([habit('mon2', { cueAfter: 'custom_time:20:00', scheduledWeekdays: [1] })]);
  assert.strictEqual(slotsOf(m2, 'mon2')[0].next, bh(28, 20));
});

test('an "after" shift still to come today rings today', () => {
  const m = model([habit('after', { cueAfter: 'custom_time:09:00', reminderOffsetMinutes: 30 })], { now: bh(27, 9, 10) });
  assert.strictEqual(slotsOf(m, 'after')[0].next, bh(27, 9, 30));
});

test('one completion of a several-times habit takes down its earliest copy still to come today', () => {
  // The phone's rule exactly: at 10:00 with one done, the 12:00 copy goes,
  // though the completion was for the morning.
  const daily = [doc('2026-09-27', { habitCompletions: { water: 1 } })];
  const m = model([habit('water', { cueAfter: 'custom_time:08:00,12:00,16:00', frequencyTarget: 3 })], { daily, now: bh(27, 10) });
  const [eight, noon, four] = slotsOf(m, 'water');
  assert.strictEqual(eight.next, bh(28, 8));
  assert.strictEqual(eight.doneToday, false);
  assert.strictEqual(noon.next, bh(28, 12));
  assert.strictEqual(noon.doneToday, true);
  assert.strictEqual(four.next, bh(27, 16));
});

test('one completion of a stacked reminder takes down the whole stack for today', () => {
  const daily = [doc('2026-09-27', { habitCompletions: { walk: 1 } })];
  const m = model([habit('walk', { cueAfter: 'custom_time:09:00', reminderOffsetMinutes: -10, extraReminderOffsets: [0, 30] })], { daily, now: bh(27, 8) });
  for (const slot of slotsOf(m, 'walk')) {
    assert.strictEqual(R.localOf(slot.next, BH).key, '2026-09-28', slot.label);
    assert.strictEqual(slot.doneToday, true);
  }
});

test('a prayer habit with no prayer place never rings; unknown when settings were never uploaded', () => {
  const noPlace = profile({ masterEnabled: true });
  assert.strictEqual(slotsOf(model([habit('p', { cueAfter: 'asr' })], { profile: noPlace }), 'p')[0].state, 'no-place');
  const never = profile(null);
  assert.strictEqual(slotsOf(model([habit('p', { cueAfter: 'asr' })], { profile: never }), 'p')[0].state, 'unknown');
});

test('outside Bahrain a prayer reminder is armed, but its time is not worked out here', () => {
  const dubai = profile({ masterEnabled: true, location: DUBAI });
  const m = model([habit('p', { cueAfter: 'fajr' })], { profile: dubai });
  assert.strictEqual(slotsOf(m, 'p')[0].state, 'unknown');
  assert.strictEqual(m.placeSource, 'none');
});

test('switches in the app turn habit reminders off, and only them where it says so', () => {
  const off = model([habit('h', { cueAfter: 'custom_time:09:00' })], { profile: profile({ masterEnabled: false }) });
  assert.strictEqual(slotsOf(off, 'h')[0].state, 'off');
  const habitsOff = model([habit('h', { cueAfter: 'custom_time:09:00' })], {
    profile: { ...profile({ habitRemindersEnabled: false }), reminderTime: '21:0' },
  });
  assert.strictEqual(slotsOf(habitsOff, 'h')[0].state, 'off');
  assert.strictEqual(habitsOff.evening.state, 'rings');
});

test('archived habits are left out, habits with no time are listed as such, and one not yet due arms nothing', () => {
  const m = model([
    habit('gone', { cueAfter: 'custom_time:09:00', archivedAt: '2026-09-20T00:00:00.000' }),
    habit('bare', {}),
    habit('sleep', { cueAfter: 'before_sleep' }),
    habit('later', { cueAfter: 'custom_time:09:00', createdAt: '2026-10-20T00:00:00.000' }),
  ]);
  assert.ok(!m.habits.some((h) => h.id === 'gone') && !m.without.some((h) => h.id === 'gone'));
  assert.deepStrictEqual(m.without.map((h) => [h.id, h.cue.kind]), [['bare', 'none'], ['sleep', 'routine']]);
  assert.strictEqual(m.habits.find((h) => h.id === 'later').state, 'not-due');
});

test('a saved report gets no prayer-derived time', () => {
  const m = model([habit('p', { cueAfter: 'fajr' }), habit('c', { cueAfter: 'custom_time:09:00' })], { forFile: true });
  assert.strictEqual(slotsOf(m, 'p')[0].state, 'unknown');
  assert.strictEqual(slotsOf(m, 'c')[0].next, bh(27, 9));
  assert.match(renderRemindersSection(m).html, /Left out of saved reports/);
});

// ---- Presets carry their reminder choices ----

test('a preset carries the stack, "Allow anyway" and the alarm choice from its override', () => {
  const p = {
    activeCatalogIds: ['prayer_fajr', 'tahajjud'],
    catalog_habit_overrides_v1: {
      prayer_fajr: { reminderOffsetMinutes: -10, extraReminderOffsets: [15, 15, 'x'], ignoreQuietHours: true, alarm: true },
      tahajjud: { extraReminderOffsets: [], alarm: false },
    },
  };
  const byId = Object.fromEntries(catalogHabitDocs(p).map((d) => [d.id, d.data()]));
  assert.deepStrictEqual(byId.prayer_fajr.extraReminderOffsets, [15]);
  assert.strictEqual(byId.prayer_fajr.ignoreQuietHours, true);
  assert.strictEqual(byId.prayer_fajr.alarm, true);
  assert.strictEqual(byId.tahajjud.extraReminderOffsets, undefined);
  assert.strictEqual(byId.tahajjud.alarm, undefined);
  // The template's own shift: tahajjud is 45 minutes before its anchor.
  assert.strictEqual(byId.tahajjud.reminderOffsetMinutes, -45);
});

// ---- Tasks ----

test('a task\'s list wins over the old single field, and moments are sorted, one per minute', () => {
  assert.deepStrictEqual(R.taskReminderTimes({ reminderAts: [], reminderAt: ts(NOW) }), []);
  assert.deepStrictEqual(R.taskReminderTimes({ reminderAt: ts(NOW) }), [NOW]);
  assert.deepStrictEqual(
    R.taskReminderTimes({ reminderAts: [ts(NOW + H), ts(NOW), ts(NOW + 20000), 'not a timestamp'] }),
    [NOW, NOW + H]);
});

test('open tasks show what is ahead and what passed this week; finished ones show nothing', () => {
  const tasks = [
    doc('soon', { title: 'Call', reminderAts: [ts(NOW - D), ts(NOW + H)], alarm: true }),
    doc('done', { title: 'Done', isDone: true, reminderAts: [ts(NOW + H)] }),
    doc('old', { title: 'Old', reminderAts: [ts(NOW - 10 * D)] }),
    doc('many', { title: 'Many', reminderAts: Array.from({ length: 10 }, (_, i) => ts(NOW + (i + 1) * H)) }),
  ];
  const m = model([], { tasks });
  assert.deepStrictEqual(m.tasks.map((t) => t.id), ['soon', 'many']);
  assert.deepStrictEqual(m.tasks[0].recent, [NOW - D]);
  assert.strictEqual(m.tasks[0].alarm, true);
  assert.strictEqual(m.tasks[1].overCap, 2);
  assert.strictEqual(m.counts.tasksAhead, 2);
});

test('the Tasks tab lists every reminder a task has, not just the first', () => {
  const html = renderTaskDetail({ title: 'x', reminderAts: [ts(NOW), ts(NOW + H)], reminderAt: ts(NOW), alarm: true });
  assert.match(html, /Reminders/);
  assert.strictEqual((html.match(/<br>/g) || []).length, 1);
  assert.match(html, /Rings as/);
});

// ---- The evening note, the Saturday note, the clock ----

test('the evening note rings at the time they picked, unless quiet hours reach over it', () => {
  const at = (reminderTime, settings) => model([habit('h', {})], { profile: { ...profile(settings), reminderTime } }).evening;
  const nine = at('21:0');
  assert.strictEqual(nine.state, 'rings');
  assert.strictEqual(nine.next, bh(27, 21));
  assert.strictEqual(at('23:30').state, 'quiet');
  assert.strictEqual(at('21:0', { masterEnabled: false }).state, 'off');
  assert.strictEqual(at(undefined).state, 'none');
});

test('the Saturday note goes out only when chosen, with notifications on and a habit', () => {
  assert.strictEqual(model([habit('h', {})], { profile: profile({ weeklyNoteOn: true }) }).weekly.state, 'rings');
  assert.strictEqual(model([], { profile: profile({ weeklyNoteOn: true }) }).weekly.state, 'off');
  assert.strictEqual(model([habit('h', {})]).weekly.state, 'none');
});

test('times are on the account\'s own clock, and the fallback says so', () => {
  const m = model([habit('c', { cueAfter: 'custom_time:09:00' })], { profile: profile(undefined, { tzOffsetMinutes: 240 }) });
  assert.deepStrictEqual(m.clock, { offset: 240, known: true });
  assert.strictEqual(whenOf(m, slotsOf(m, 'c')[0].next), '2026-09-27 09:00');
  const unknown = model([], { profile: { notificationSettings: {} } });
  assert.strictEqual(unknown.clock.known, false);
  assert.strictEqual(utcLabel(180), 'UTC+3');
  assert.strictEqual(utcLabel(-420), 'UTC-7');
  assert.strictEqual(utcLabel(330), 'UTC+5:30');
});

// ---- Whether the phone is still topping them up ----

test('a phone not seen for days is flagged, from its push token or what it stamped', () => {
  const token = (ms) => doc('tok', { updatedAt: ts(ms) });
  const rings = [habit('c', { cueAfter: 'custom_time:09:00' })];
  assert.strictEqual(model(rings, { tokens: [token(NOW - 6 * D)] }).stale, true);
  assert.strictEqual(model(rings, { tokens: [token(NOW - 6 * D)], daily: [doc('2026-09-26', { lastUpdated: ts(NOW - D) })] }).stale, false);
  const task = doc('t', { title: 't', createdAt: ts(NOW - 2 * D), completedAt: ts(NOW - H), isDone: true });
  assert.strictEqual(model(rings, { tokens: [token(NOW - 6 * D)], tasks: [task] }).lastSeen, NOW - H);
  // A script's write (Firestore's own updateTime) is not the phone.
  assert.strictEqual(model(rings, { tokens: [token(NOW - 6 * D)], daily: [doc('2026-09-26', {}, { updateTime: ts(NOW) })] }).stale, true);
  // Nothing to run out: no warning, only the Last seen line.
  assert.strictEqual(model([], { tokens: [token(NOW - 6 * D)] }).stale, false);
  assert.strictEqual(model([]).lastSeen, null);
  assert.strictEqual(model([]).stale, false);
});

// ---- The page ----

test('the tab never prints the prayer place, and escapes what the person typed', () => {
  const m = model([
    habit('x', { name: '<img src=x onerror=alert(1)>', cueAfter: 'fajr' }),
  ], { tasks: [doc('t', { title: '<script>bad()</script>', reminderAts: [ts(NOW + H)] })] });
  const { html } = renderRemindersSection(m);
  assert.ok(!html.includes('<img src=x'), 'habit name escaped');
  assert.ok(!html.includes('<script>bad'), 'task title escaped');
  for (const leak of ['26.2285', '50.586', 'المنامة']) {
    assert.ok(!html.includes(leak), `${leak} must not reach the page`);
  }
  assert.ok(!/[—]/.test(html), 'no em dash');
  assert.strictEqual(m.settings.location, undefined);
});

test('the tab reads right: the next ring, the reasons, and an amber count when switches stop it', () => {
  const m = model([
    habit('sunnah', { name: 'سنة الفجر', cueAfter: 'fajr', reminderOffsetMinutes: -15 }),
    habit('early', { name: 'Early', cueAfter: 'custom_time:05:00' }),
  ], { profile: { ...profile(), reminderTime: '21:0' } });
  const section = renderRemindersSection(m);
  assert.strictEqual(section.id, 'reminders');
  assert.strictEqual(section.count, 2);
  assert.strictEqual(section.alert, false);
  assert.match(section.html, /15 min before Fajr/);
  assert.match(section.html, /Today 03:56/);
  assert.match(section.html, /Quiet hours 22:00 to 07:00[^"]*">Never: in quiet hours</);
  assert.match(section.html, /21:00 every evening/);
  assert.match(section.html, /official timetable/);

  const off = renderRemindersSection(model([habit('h', { cueAfter: 'custom_time:09:00' })], { profile: profile({ masterEnabled: false }) }));
  assert.strictEqual(off.alert, true);
  assert.match(off.html, /All notifications are switched off/);
  const body = buildReportBody({ uid: 'u', authRecord: null, profileData: {}, sections: [off], place: null });
  assert.match(body.nav, /tab-count gap/);
});

// ---- The port against the app's own scheduler ----

// Every case here was run through NotificationService.scheduleSmartReminders
// itself (the fixture's `how`), and `appArmed` is every notification it
// armed: all four days ahead of every slot, to the second. The cases cover
// what a support question turns on: a prayer stack, quiet hours with and
// without prayers covered, an alarm and "Allow anyway" inside them, a quit
// check-in, done today for a several-times habit and for a stack, a shift
// that lands across midnight on a one-weekday habit, the old 12-hour and
// reminderLeadMinutes forms, Arabic-Indic digits, and a daytime window. The
// prayers_ cases (2026-10-01) are a prayer per time: two around one prayer,
// one done of three, quiet hours over a prayer, and a run mixing a prayer
// with a clock, which the phone reads as damage.
// A difference here means the tab would show a time the phone never armed.
test('the tool arms exactly what the app\'s own scheduler armed, case by case', () => {
  const { cases } = require('./fixtures/reminder_parity.json');
  assert.strictEqual(cases.length, 29);
  for (const c of cases) {
    const todayKey = R.localOf(c.now, BH).key;
    const habitDoc = doc(c.id, {
      name: c.id, createdAt: '2026-09-01T00:00:00.000', frequencyType: 'daily', frequencyTarget: 1, goalType: 'build', ...c.habit,
    });
    const day = doc(todayKey, c.squareFailed
      ? { squareStates: { [c.id]: 'failed' } }
      : { habitCompletions: { [c.id]: c.completed } });
    const m = R.buildRemindersModel({
      profile: {
        tzOffsetMinutes: BH,
        notificationSettings: {
          ...c.settings, masterEnabled: true, habitRemindersEnabled: true, bundleEnabled: false, location: MANAMA,
        },
      },
      habitDocs: [habitDoc],
      dailyDocs: [day],
      nowMs: c.now,
    });
    const armed = m.habits.length ? m.habits[0].slots.flatMap((s) => s.armed || []).sort((a, b) => a - b) : [];
    assert.deepStrictEqual(armed, c.appArmed, c.id);
  }
});
