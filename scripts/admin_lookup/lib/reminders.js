'use strict';

/**
 * An account's reminders, and when each one next rings, worked out the way
 * the phone works them out.
 *
 * The phone never uploads what it armed. That record (armedHabitReminders
 * Json) lives in the App Group on the device, and the notifications
 * themselves live in the OS. What Firestore DOES hold is every input the
 * phone schedules from: each habit's cue, its shifts, its alarm choice and
 * its days, the task reminder moments, and the notification settings the
 * phone mirrors up. So this rebuilds the answer from those, rule for rule,
 * and every rule below names the Dart it was ported from:
 *
 *   which habits      main.dart _runRecomputeNotifications: every habit due
 *                     on any of the next 7 days
 *   which slots       NotificationService.expandStackedSlots (a clock) and
 *                     the prayer branch of _sweepHabitReminders (a prayer)
 *   when              resolveClockOccurrences, and a prayer's own day's
 *                     time plus the shift
 *   quiet hours       judged per fire, never per habit, with the three
 *                     exemptions (Allow anyway, an alarm, a prayer)
 *   done today        stands down TODAY's copies only
 *   tasks             futureTaskReminders: open tasks, master switch only
 *   evening note      reminderTime, silenced when quiet hours cover it
 *
 * Nothing here reads Firestore or writes HTML (lib/reminders_page.js draws
 * it). Every function takes its clock as an argument, so the tests can
 * stand anywhere in the day.
 *
 * What it cannot know, and the tab says so rather than guessing: whether the
 * phone allows notifications at all (the OS permission never leaves the
 * phone), settings changed on the phone while signed out (the phone's copy
 * wins, and only its uploads reach the account), and prayer times outside
 * Bahrain (lib/prayer_times.js).
 */

// The window test the server judges room pushes and admin messages by,
// written to match the app's isMinuteWithinQuietHours. Only the window: the
// phone's own switch is checked beside each use, since a push from someone
// else waits out the night even with that switch off and a reminder does
// not.
const { isMinuteInWindow } = require('../../../functions/push_policy');
const { prayerTimesFor } = require('./prayer_times');

/**
 * A stored "H:M" ("22:0", "7:30", unpadded, the way the app writes quiet
 * hours and reminderTime) as minutes since midnight, or null. The same
 * reading as push_policy.js's own toMinutes, which it does not export.
 */
function toMinutes(hhmm) {
  if (typeof hhmm !== 'string') return null;
  const parts = hhmm.split(':');
  if (parts.length !== 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (Number.isNaN(h) || Number.isNaN(m)) return null;
  return h * 60 + m;
}

// ---- The account's notification settings ----

/**
 * NotificationSettings' defaults, for any key the stored map lacks. An
 * account whose phone never mirrored its settings has no map at all; the
 * app's defaults are the honest stand-in, and readSettings says it is one.
 *
 * quietHoursEnabled is the OLD key, on by default in every build before
 * quiet hours went off by default (2026-09-28). A build since then writes
 * its switch as quietHoursOn and mirrors it on sign-in, so an account
 * without that key was last written by an older build, whose switch this
 * was. readSettings picks between the two.
 */
const SETTINGS_DEFAULTS = Object.freeze({
  masterEnabled: true,
  habitRemindersEnabled: true,
  bundleEnabled: true,
  weeklyNoteOn: false,
  quietHoursEnabled: true,
  quietHoursStart: '22:0',
  quietHoursEnd: '7:0',
  quietHoursAppliesToPrayer: false,
});

function plainMap(v) {
  return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
}

/**
 * The settings the phone schedules from, as far as the account knows them.
 *
 * `mirrored` is false when the account holds no settings at all, and then
 * every value is the app's default and `hasPlace` is unknowable, so null
 * rather than false. A key of the wrong type reads as its default, the way
 * fromMap's `as bool? ?? default` reads it.
 */
function readSettings(profile) {
  const raw = plainMap(profile && profile.notificationSettings);
  const s = { mirrored: Boolean(raw) };
  for (const [key, def] of Object.entries(SETTINGS_DEFAULTS)) {
    const v = raw ? raw[key] : undefined;
    s[key] = typeof v === typeof def ? v : def;
  }
  const loc = raw ? plainMap(raw.location) : null;
  const hasPlace = Boolean(loc && typeof loc.lat === 'number' && typeof loc.lng === 'number');
  s.hasPlace = raw ? hasPlace : null;
  // Kept for the prayer-time lookup only. Nothing below prints it, and
  // lib/reminders_page.js is never handed it (see lib/prayer_place.js).
  s.location = hasPlace ? loc : null;
  // The phone's own quiet-hours switch: quietHoursOn from a build that has
  // it, else the old key, which was an older build's switch (see
  // SETTINGS_DEFAULTS). The old key is written true by every newer build,
  // so it never answers for one.
  s.quietFromOldBuild = !(raw && typeof raw.quietHoursOn === 'boolean');
  if (!s.quietFromOldBuild) s.quietHoursEnabled = raw.quietHoursOn;
  s.quietStartMin = toMinutes(s.quietHoursStart);
  s.quietEndMin = toMinutes(s.quietHoursEnd);
  return s;
}

/**
 * The account's clock: the UTC offset the phone last reported
 * (users/{uid}.tzOffsetMinutes), or this machine's own when it never did,
 * the same fallback lib/render.js's effectiveTodayParts takes.
 */
function accountClock(profile, nowMs) {
  const reported = profile && profile.tzOffsetMinutes;
  if (typeof reported === 'number' && Number.isFinite(reported)) {
    return { offset: reported, known: true };
  }
  return { offset: -new Date(nowMs).getTimezoneOffset(), known: false };
}

// ---- Wall-clock arithmetic in one fixed offset ----

function pad2(n) {
  return String(n).padStart(2, '0');
}

/** Minutes since midnight as "HH:MM", wrapping past a day either way. */
function fmtClock(minuteOfDay) {
  const m = ((Math.round(minuteOfDay) % 1440) + 1440) % 1440;
  return `${pad2(Math.floor(m / 60))}:${pad2(m % 60)}`;
}

/** An instant's wall clock at [offset]: its day key, weekday and minute. */
function localOf(ms, offset) {
  const d = new Date(ms + offset * 60000);
  const y = d.getUTCFullYear();
  const m = d.getUTCMonth() + 1;
  const day = d.getUTCDate();
  return {
    key: `${y}-${pad2(m)}-${pad2(day)}`,
    // Dart's DateTime.weekday: 1 Monday .. 7 Sunday.
    weekday: d.getUTCDay() === 0 ? 7 : d.getUTCDay(),
    minute: d.getUTCHours() * 60 + d.getUTCMinutes(),
  };
}

/** [key] moved by [n] days. */
function addDays(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/**
 * The instant [minuteOfDay] falls at on day [key] of a clock at [offset].
 * The minute may run past either end of the day: a shift is added to the
 * day's own wall clock, exactly as resolveClockOccurrences builds the day's
 * moment first and adds the offset after.
 */
function instantOf(key, minuteOfDay, offset) {
  const [y, m, d] = key.split('-').map(Number);
  return Date.UTC(y, m - 1, d) + (minuteOfDay - offset) * 60000;
}

// ---- A habit's cue (HabitCue.fromStoredValue) ----

/**
 * HabitCue._presetSynonyms, in its order: the stable key, its old English
 * chip text, and the Arabic this app briefly stored. Any of them resolves to
 * the key, case-insensitively.
 */
const PRESET_SYNONYMS = [
  ['fajr', ['fajr', 'Fajr', 'الفجر']],
  ['dhuhr', ['dhuhr', 'Dhuhr', 'الظهر']],
  ['asr', ['asr', 'Asr', 'العصر']],
  ['maghrib', ['maghrib', 'Maghrib', 'المغرب']],
  ['isha', ['isha', 'Isha', 'العشاء']],
  ['before_sleep', ['before_sleep', 'Before sleep', 'قبل النوم']],
  ['morning', ['morning', 'Morning', 'الصباح']],
  ['afternoon', ['afternoon', 'Afternoon', 'بعد الظهر']],
  ['evening', ['evening', 'Evening', 'المساء']],
  ['after_work_school', ['after_work_school', 'After work/school', 'بعد العمل/المدرسة']],
  ['after_school_work', ['after_school_work', 'After school/work', 'بعد المدرسة/العمل']],
  ['work_block', ['work_block', 'Work block', 'وقت العمل']],
];

const PRAYER_NAMES = {
  fajr: 'Fajr', dhuhr: 'Dhuhr', asr: 'Asr', maghrib: 'Maghrib', isha: 'Isha',
};

const ROUTINE_NAMES = {
  before_sleep: 'Before sleep',
  morning: 'Morning',
  afternoon: 'Afternoon',
  evening: 'Evening',
  after_work_school: 'After work/school',
  after_school_work: 'After school/work',
  work_block: 'Work block',
};

// HabitCue._timePart, _timeEn and _timeAr.
const TIME_PART = /^(\d{2}):(\d{2})([+-]\d{1,3})?$/;

// HabitCue._prayerPart: a 'custom_time:' entry riding on a prayer instead of
// a clock, with the same optional signed shift ('fajr-30').
const PRAYER_PART = /^(fajr|dhuhr|asr|maghrib|isha)([+-]\d{1,3})?$/;

// HabitCue._prayerOrder: the order a run of prayer slots is kept in.
const PRAYER_ORDER = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
const TIME_EN = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i;
const TIME_AR = /^(\d{1,2}):(\d{2})\s*(ص|م)$/;

/** HabitCue.fromStoredValue's _asciiDigits: Arabic-Indic digits only. */
function asciiDigits(s) {
  return s.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660));
}

/** The most times one cue can carry (HabitCue._maxTimes). */
const MAX_TIMES = 12;

/**
 * [stored] read the way the phone reads it:
 *
 *   { kind: 'prayer', prayerKey }         one of the five prayers
 *   { kind: 'prayers', slots: [{prayerKey, shift}] }  a prayer per time,
 *                                         for a habit counted several times
 *                                         a day (HabitCue.prayerSlots): in
 *                                         the order of the day, then shift,
 *                                         each pair once, at most 12
 *   { kind: 'clock', times: [{at, shift}] }  picked clock time(s), `at` in
 *                                         minutes since midnight, earliest
 *                                         first, one per minute, at most 12
 *   { kind: 'routine', routineKey }       Before sleep and friends: no time
 *   { kind: 'text' }                      their own words: no time
 *   { kind: 'damaged' }                   a 'custom_time:' value the app
 *                                         cannot read, which it treats as
 *                                         no cue at all
 *   { kind: 'none' }                      no cue
 *
 * A clock's `shift` is its OWN signed shift, which the app uses only when
 * there are two or more times (HabitCue.offsetsAreOwn); habitReminder below
 * decides which shift applies.
 */
function parseCue(stored) {
  const raw = String(stored == null ? '' : stored).trim();
  if (!raw) return { kind: 'none' };

  const lower = raw.toLowerCase();
  for (const [key, synonyms] of PRESET_SYNONYMS) {
    if (synonyms.some((s) => s.toLowerCase() === lower)) {
      return PRAYER_NAMES[key] ? { kind: 'prayer', prayerKey: key } : { kind: 'routine', routineKey: key };
    }
  }

  const candidate = asciiDigits(raw);
  if (candidate.startsWith('custom_time:')) {
    const body = candidate.slice('custom_time:'.length);
    if (!body) return { kind: 'none' };
    // A run of prayers, every entry of it; one among clock times is damage.
    const parts = body.split(',');
    if (parts.every((part) => PRAYER_PART.test(part))) {
      const seen = new Set();
      const slots = [];
      for (const part of parts) {
        const m = PRAYER_PART.exec(part);
        const shift = m[2] ? Number(m[2]) : 0;
        if (Math.abs(shift) > 999 || seen.has(`${m[1]}${shift}`)) continue;
        seen.add(`${m[1]}${shift}`);
        slots.push({ prayerKey: m[1], shift });
      }
      slots.sort((a, b) => (PRAYER_ORDER.indexOf(a.prayerKey) - PRAYER_ORDER.indexOf(b.prayerKey))
        || (a.shift - b.shift));
      return slots.length ? { kind: 'prayers', slots: slots.slice(0, MAX_TIMES) } : { kind: 'none' };
    }
    const byMinute = new Map();
    for (const part of body.split(',')) {
      const m = TIME_PART.exec(part);
      if (!m) return { kind: 'damaged' };
      const h = Number(m[1]);
      const min = Number(m[2]);
      if (h > 23 || min > 59) return { kind: 'damaged' };
      const at = h * 60 + min;
      // HabitCue.timesWithOffsets: a repeated minute keeps its first shift.
      if (!byMinute.has(at)) byMinute.set(at, m[3] ? Number(m[3]) : 0);
    }
    const times = [...byMinute.keys()].sort((a, b) => a - b).slice(0, MAX_TIMES)
      .map((at) => ({ at, shift: byMinute.get(at) }));
    return { kind: 'clock', times };
  }
  // The 12-hour text an older build stored, in either language.
  const en = TIME_EN.exec(candidate);
  if (en) {
    const at = ((Number(en[1]) % 12) + (en[3].toUpperCase() === 'PM' ? 12 : 0)) * 60 + Number(en[2]);
    return { kind: 'clock', times: [{ at, shift: 0 }] };
  }
  const ar = TIME_AR.exec(candidate);
  if (ar) {
    const at = ((Number(ar[1]) % 12) + (ar[3] === 'م' ? 12 : 0)) * 60 + Number(ar[2]);
    return { kind: 'clock', times: [{ at, shift: 0 }] };
  }
  return { kind: 'text' };
}

// ---- One habit's reminders ----

/**
 * IslamicHabitTemplate._readReminderOffset: the signed shift, or the old
 * always-positive `reminderLeadMinutes` flipped, for a habit not re-saved
 * since. A preset's merge (lib/habit_catalog.js) has already chosen between
 * its override and its template.
 */
function primaryOffset(h) {
  if (Number.isInteger(h.reminderOffsetMinutes)) return h.reminderOffsetMinutes;
  if (Number.isInteger(h.reminderLeadMinutes) && h.reminderLeadMinutes !== 0) {
    return -h.reminderLeadMinutes;
  }
  return 0;
}

/**
 * IslamicHabitTemplate._readExtraOffsets: whole minutes only, each once,
 * sorted, so the same set always yields the same slots.
 */
function extraOffsets(h) {
  if (!Array.isArray(h.extraReminderOffsets)) return [];
  const out = new Set();
  for (const v of h.extraReminderOffsets) {
    if (typeof v === 'number' && Number.isFinite(v)) out.add(Math.trunc(v));
  }
  return [...out].sort((a, b) => a - b);
}

/**
 * The reminders one habit asks for, one slot per notification it arms a
 * day, in the phone's slot order (a slot's index is its notification id, so
 * the order is the phone's, not the clock's).
 *
 *   clock, one time    the habit's own shift, then its stack on top
 *                      (expandStackedSlots): each distinct shift once,
 *                      primary first, at most 12
 *   clock, 2+ times    each time with the cue's own shift for it; the
 *                      habit's shift and stack are not used at all
 *   prayer             the habit's shift, then its stack, as stored (the
 *                      prayer branch does not dedupe), at most 12
 *   prayer per time    each slot's prayer with its own shift; the habit's
 *                      shift and stack are not used at all
 *
 * `perOccurrence` is how many slots belong to ONE occurrence, which is what
 * one completion stands down (HabitReminderInput.remindersPerOccurrence).
 */
function habitReminder(h) {
  const cue = parseCue(h.cueAfter);
  const primary = primaryOffset(h);
  const extras = extraOffsets(h);
  const slots = [];
  let perOccurrence = 1;
  if (cue.kind === 'clock') {
    if (cue.times.length === 1 && extras.length) {
      const stack = [...new Set([primary, ...extras])].slice(0, MAX_TIMES);
      for (const offset of stack) slots.push({ at: cue.times[0].at, offset });
      perOccurrence = stack.length;
    } else if (cue.times.length === 1) {
      slots.push({ at: cue.times[0].at, offset: primary });
    } else {
      for (const t of cue.times) slots.push({ at: t.at, offset: t.shift });
    }
  } else if (cue.kind === 'prayer') {
    for (const offset of [primary, ...extras].slice(0, MAX_TIMES)) {
      slots.push({ prayerKey: cue.prayerKey, offset });
    }
  } else if (cue.kind === 'prayers') {
    for (const s of cue.slots) slots.push({ prayerKey: s.prayerKey, offset: s.shift });
  }
  const isQuit = h.goalType === 'quit';
  return {
    cue,
    slots,
    perOccurrence,
    // An alarm is AlarmKit on iOS 26 and newer, an alarm-sound notification
    // on Android. A quit habit's check-in never rings as one (_scheduleOne).
    alarm: h.alarm === true && !isQuit,
    ignoreQuietHours: h.ignoreQuietHours === true,
    isQuit,
    isLimit: h.reductionType === 'limit',
    weekdays: weekdaysOf(h),
    dailyTarget: h.frequencyType === 'weekly' ? 1 : Math.max(1, Number(h.frequencyTarget) || 1),
  };
}

function weekdaysOf(h) {
  if (!Array.isArray(h.scheduledWeekdays)) return [];
  return [...new Set(h.scheduledWeekdays.map(Number)
    .filter((n) => Number.isInteger(n) && n >= 1 && n <= 7))].sort((a, b) => a - b);
}

/** 90 -> "1 h 30 min", 15 -> "15 min", 120 -> "2 h". */
function fmtDuration(minutes) {
  const m = Math.abs(minutes);
  const h = Math.floor(m / 60);
  const rest = m % 60;
  if (h === 0) return `${rest} min`;
  return rest === 0 ? `${h} h` : `${h} h ${rest} min`;
}

/**
 * One slot in words: "At Fajr", "15 min before Fajr", "At 06:00",
 * "1 h after 06:00". The time it actually rings is the next column's job.
 */
function slotLabel(slot) {
  const anchor = slot.prayerKey ? PRAYER_NAMES[slot.prayerKey] : fmtClock(slot.at);
  if (!slot.offset) return `At ${anchor}`;
  return `${fmtDuration(slot.offset)} ${slot.offset < 0 ? 'before' : 'after'} ${anchor}`;
}

// ---- When a habit's reminders ring ----

/** NotificationService.kOccurrencesPerSlot: copies armed ahead per slot. */
const OCCURRENCES_PER_SLOT = 4;

/**
 * How far a walk looks for those copies: resolveClockOccurrences' own bound
 * (8 + 7 per occurrence), enough for a once-a-week habit to find all four.
 */
const WALK_DAYS = 8 + 7 * OCCURRENCES_PER_SLOT;

/**
 * The next OCCURRENCES_PER_SLOT moments one slot falls at, from [nowMs], on
 * the habit's own days. The same walk for a clock and a prayer: each day
 * builds its own moment (a clock's wall time, or that day's prayer), THEN
 * adds the shift, then asks whether the moment is still ahead and whether
 * the day it lands on is one the habit runs (_fireDayIsScheduled). So an
 * "after" shift still ringing today survives, and a shift that drags a
 * moment across midnight is judged on the day it lands.
 *
 * `unknown` is set when a prayer's time could not be looked up for a day
 * the walk needed, which stops it: nothing after that day can be trusted.
 */
function slotFires(slot, env) {
  const fires = [];
  for (let d = 0; d <= WALK_DAYS && fires.length < OCCURRENCES_PER_SLOT; d++) {
    const key = addDays(env.todayKey, d);
    let base;
    if (slot.prayerKey) {
      const day = env.dayTimes(key);
      if (!day || typeof day[slot.prayerKey] !== 'number') return { fires, unknown: true };
      base = day[slot.prayerKey];
    } else {
      base = instantOf(key, slot.at, env.offset);
    }
    const fire = base + slot.offset * 60000;
    if (fire <= env.nowMs) continue;
    if (env.weekdays.length && !env.weekdays.includes(localOf(fire, env.offset).weekday)) continue;
    fires.push(fire);
  }
  return { fires, unknown: false };
}

/**
 * How many of today's occurrences the phone counts as done, the number its
 * stand-down reads (main.dart's completedCount): zero on a day the habit is
 * not due, a quit habit answered «ما التزمت» (its square red) as fully
 * answered, otherwise today's completions.
 */
function completedToday(h, dayData, scheduledToday, plan) {
  if (!scheduledToday) return 0;
  const d = dayData || {};
  if (plan.isQuit) {
    const squares = plainMap(d.squareStates) || {};
    if (squares[h.__id] === 'failed') return plan.dailyTarget;
  }
  const comps = plainMap(d.habitCompletions) || {};
  return Number(comps[h.__id]) || 0;
}

/**
 * Whether the habit's square today is «راحة» (stored 'skipped'). The phone
 * arms nothing for a resting habit on its rest day (main.dart's
 * _excusedDaysById: nothing is owed, so nothing rings), which for today is
 * the same as every one of today's copies being answered.
 */
function restingToday(h, dayData, scheduledToday) {
  if (!scheduledToday) return false;
  const squares = plainMap((dayData || {}).squareStates) || {};
  return squares[h.__id] === 'skipped';
}

/**
 * Every slot of one habit with the moment it next rings, or why it does not.
 *
 * Slot states:
 *   rings        `next` is the moment
 *   unknown      a prayer whose time this tool cannot work out (outside
 *                Bahrain); the phone still arms it
 *   quiet        every copy the phone would arm falls inside quiet hours,
 *                so none is armed
 *   no-place     a prayer with no prayer place: the phone has nothing to
 *                time it from and arms nothing
 *   off          notifications, or habit reminders, are switched off
 *
 * Per-slot `doneToday` marks a copy that was due later today and is not
 * armed because the habit is already done today; `quietSome` a copy skipped
 * for quiet hours when a later one still rings.
 */
function resolveHabitSlots(plan, env) {
  const { settings } = env;
  const base = plan.slots.map((slot) => ({ ...slot, label: slotLabel(slot) }));
  if (!settings.masterEnabled || !settings.habitRemindersEnabled) {
    return base.map((s) => ({ ...s, state: 'off', next: null }));
  }
  const isPrayer = plan.cue.kind === 'prayer' || plan.cue.kind === 'prayers';
  if (isPrayer && !env.hasPlace) {
    return base.map((s) => ({ ...s, state: 'no-place', next: null }));
  }

  // Quiet hours, judged per fire. Three ways out: this habit's own "Allow
  // anyway", ringing as an alarm (the person asked to be woken), and being
  // a prayer while quiet hours are set to leave prayers alone.
  const exempt = plan.ignoreQuietHours || plan.alarm
    || (isPrayer && !settings.quietHoursAppliesToPrayer);
  const quietAt = (ms) => !exempt && settings.quietHoursEnabled
    && isMinuteInWindow(settings.quietHoursStart, settings.quietHoursEnd,
      localOf(ms, env.offset).minute);

  const walked = base.map((slot) => {
    const { fires, unknown } = slotFires(slot, { ...env, weekdays: plan.weekdays });
    return { slot, unknown, fires: fires.map((ms) => ({ ms, quiet: quietAt(ms), done: false })) };
  });

  // Done today stands down today's copies, and only today's.
  const todayOf = (f) => localOf(f.ms, env.offset).key === env.todayKey;
  if (plan.cue.kind === 'prayer') {
    // One prayer, one moment a day: a completion answers every shift of it.
    if (env.completed >= plan.dailyTarget) {
      for (const w of walked) for (const f of w.fires) if (todayOf(f)) f.done = true;
    }
  } else {
    // A clock habit stands down its EARLIEST still-to-come copies today, one
    // occurrence per completion, a stacked occurrence being all its slots.
    // A prayer per time counts the same way: each slot is an occurrence.
    // Only copies that survived quiet hours are counted, as the phone counts.
    const today = [];
    for (const w of walked) for (const f of w.fires) if (!f.quiet && todayOf(f)) today.push(f);
    today.sort((a, b) => a.ms - b.ms);
    const suppress = Math.min(env.completed * Math.max(1, plan.perOccurrence), today.length);
    for (let i = 0; i < suppress; i++) today[i].done = true;
  }

  return walked.map(({ slot, unknown, fires }) => {
    const live = fires.find((f) => !f.quiet && !f.done);
    const skippedDone = fires.some((f) => f.done && (!live || f.ms < live.ms));
    const skippedQuiet = fires.some((f) => f.quiet && (!live || f.ms < live.ms));
    // Every copy the phone holds for this slot right now: the whole window,
    // for comparing against what the app's own scheduler arms.
    const armed = fires.filter((f) => !f.quiet && !f.done).map((f) => f.ms);
    if (live) {
      return {
        ...slot, state: 'rings', next: live.ms, armed, doneToday: skippedDone, quietSome: skippedQuiet,
      };
    }
    if (unknown) return { ...slot, state: 'unknown', next: null, doneToday: skippedDone };
    // Copies ahead, none of them armed: quiet hours took them all, bar at
    // most today's, which done-today took.
    if (fires.length) return { ...slot, state: 'quiet', next: null, doneToday: skippedDone };
    // Nothing ahead at all, which only a habit with no day left in its
    // schedule can reach; the caller has already filtered those out.
    return { ...slot, state: 'none', next: null };
  });
}

// ---- Task reminders ----

/** A Firestore Timestamp (or a Date, in tests) as epoch ms, else null. */
function instantMs(v) {
  if (v && typeof v.toDate === 'function') {
    const d = v.toDate();
    return Number.isNaN(d.getTime()) ? null : d.getTime();
  }
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.getTime();
  return null;
}

/**
 * A task's reminder moments the way MatrixTask.fromFirestore reads them:
 * `reminderAts` whenever it is a list, even an empty one, and the old
 * single `reminderAt` only when it is not. Timestamps only, as the app's
 * parser takes only Timestamps: anything else in the list never rings.
 * Sorted, one per minute (normalizeReminders).
 */
function taskReminderTimes(t) {
  const d = t || {};
  const raw = Array.isArray(d.reminderAts) ? d.reminderAts : (d.reminderAt != null ? [d.reminderAt] : []);
  const seen = new Set();
  const out = [];
  for (const ms of raw.map(instantMs).filter((x) => x !== null).sort((a, b) => a - b)) {
    const minute = Math.floor(ms / 60000);
    if (seen.has(minute)) continue;
    seen.add(minute);
    out.push(ms);
  }
  return out;
}

/** ArmedTaskRecord's cap: the most moments one task hands the OS. */
const TASK_ARMED_CAP = 8;

/** How far back a passed reminder on an open task is still shown. */
const TASK_PASSED_DAYS = 7;

// ---- Whether the phone is still topping them up ----

/**
 * The phone arms only the next OCCURRENCES_PER_SLOT copies of each habit
 * reminder (alarms: a month, kAlarmWindowDays) and tops them up on every
 * open. A phone left closed past that runs out, and nothing rings until
 * the app is opened again. Past this many days since the phone was last
 * seen, the tab says so: four daily copies, plus the up-to-20-hours lag of
 * the push token's refresh that usually tells us when it was last open.
 */
const STALE_AFTER_DAYS = 5;

/**
 * The latest moment this account's phone is known to have been in use, or
 * null, from moments only the PHONE stamps:
 *
 *   fcmTokens/{token}.updatedAt   rewritten at most every 20 hours while the
 *                                 app is used (kPushTokenRefreshEvery), the
 *                                 best "last opened" there is
 *   daily/{day}.lastUpdated       its last mark on a day
 *   matrix_tasks createdAt, completedAt
 *
 * Never Firestore's own updateTime: the repair scripts in this folder write
 * to day docs and habits too, and would make a phone left in a drawer look
 * used on the day a script ran. Opening the app without doing anything
 * leaves no trace at all on a phone with no push token, so this can be too
 * EARLY, never too late.
 */
function lastSeenMs({ tokenDocs, dailyDocs, taskDocs }) {
  let best = null;
  const see = (v) => {
    const ms = instantMs(v);
    if (ms !== null && (best === null || ms > best)) best = ms;
  };
  const dataOf = (d) => (d && typeof d.data === 'function' ? d.data() : d) || {};
  for (const d of tokenDocs || []) see(dataOf(d).updatedAt);
  for (const d of dailyDocs || []) see(dataOf(d).lastUpdated);
  for (const d of taskDocs || []) {
    const t = dataOf(d);
    see(t.createdAt);
    see(t.completedAt);
  }
  return best;
}

// ---- The whole account ----

/**
 * Everything the Reminders tab shows, for one account at [nowMs].
 *
 * [habitDocs] is the account's whole list (lib/habit_catalog.js's
 * accountHabitDocs: presets and their own), [taskDocs] its matrix_tasks,
 * [dailyDocs] its daily docs (today's is read for what is done, all of them
 * for when the phone last wrote), [tokenDocs] its fcmTokens. [forFile] is a
 * saved report: it gets no prayer-derived clock time, since a prayer time
 * says roughly where someone is and saved reports leave the place out.
 */
function buildRemindersModel({
  profile, habitDocs, taskDocs, dailyDocs, tokenDocs, nowMs, forFile = false,
}) {
  const p = profile || {};
  const settings = readSettings(p);
  const clock = accountClock(p, nowMs);
  const todayKey = localOf(nowMs, clock.offset).key;
  const times = prayerTimesFor(settings.location);
  // Required here rather than at the top: lib/render.js requires this file
  // (task reminders in the Tasks tab), so a top-level require of it would
  // be a cycle. By the time a model is built, both are loaded.
  const { habitScheduledOnParts, dayKeyParts } = require('./render');

  const dayDoc = (dailyDocs || []).find((d) => d.id === todayKey);
  const dayData = dayDoc ? dayDoc.data() : {};

  const habits = [];
  const without = [];
  for (const doc of habitDocs || []) {
    const h = { ...doc.data(), __id: doc.id };
    // habitListProvider: the habits on today's list, not archived ones.
    if (h.archivedAt) continue;
    const plan = habitReminder(h);
    const entry = {
      id: doc.id,
      name: h.name || '(unnamed habit)',
      category: h.category || null,
      isPreset: Boolean(h.isPreset || doc.isPreset),
      cue: plan.cue,
      alarm: plan.alarm,
      isQuit: plan.isQuit,
      isLimit: plan.isLimit,
      ignoreQuietHours: plan.ignoreQuietHours,
      weekdays: plan.weekdays,
    };
    if (plan.slots.length === 0) {
      without.push(entry);
      continue;
    }
    // main.dart arms only habits due on one of the next seven days.
    const due = [];
    for (let i = 0; i < 7; i++) due.push(habitScheduledOnParts(h, dayKeyParts(addDays(todayKey, i))));
    if (!due.some(Boolean)) {
      habits.push({ ...entry, state: 'not-due', slots: plan.slots.map((s) => ({ ...s, label: slotLabel(s), state: 'not-due', next: null })) });
      continue;
    }
    const slots = resolveHabitSlots(plan, {
      settings,
      hasPlace: settings.hasPlace !== false,
      offset: clock.offset,
      nowMs,
      todayKey,
      dayTimes: forFile ? () => null : times.dayTimes,
      completed: restingToday(h, dayData, due[0])
        ? plan.dailyTarget
        : completedToday(h, dayData, due[0], plan),
    });
    habits.push({
      ...entry,
      state: 'armed',
      slots: restingToday(h, dayData, due[0])
        ? slots.map((sl) => (sl.doneToday ? { ...sl, doneToday: false, restingToday: true } : sl))
        : slots,
    });
  }

  const tasks = [];
  for (const doc of taskDocs || []) {
    const t = doc.data ? doc.data() : doc;
    if (t.isDone === true) continue; // a done task arms nothing
    const all = taskReminderTimes(t);
    if (!all.length) continue;
    const ahead = all.filter((ms) => ms > nowMs);
    const recent = all.filter((ms) => ms <= nowMs && nowMs - ms <= TASK_PASSED_DAYS * 86400000);
    if (!ahead.length && !recent.length) continue;
    tasks.push({
      id: doc.id || '',
      title: typeof t.title === 'string' && t.title.trim() ? t.title : '(untitled task)',
      alarm: t.alarm === true,
      ahead,
      recent,
      overCap: Math.max(0, ahead.length - TASK_ARMED_CAP),
    });
  }
  // Soonest first, then the ones whose moments have all passed.
  tasks.sort((a, b) => (a.ahead[0] ?? Infinity) - (b.ahead[0] ?? Infinity)
    || (b.recent[b.recent.length - 1] ?? 0) - (a.recent[a.recent.length - 1] ?? 0));

  // The evening note: one a day at the time they picked, only while
  // notifications are on, and silent when quiet hours reach over it
  // (scheduleEveningNote's `muted`). A stored time is the device's last
  // upload; the phone's own copy wins.
  const eveningMin = typeof p.reminderTime === 'string' ? toMinutes(p.reminderTime) : null;
  const evening = { at: null, state: 'none', next: null };
  if (eveningMin !== null && eveningMin >= 0 && eveningMin < 1440) {
    evening.at = eveningMin;
    if (!settings.masterEnabled) evening.state = 'off';
    else if (settings.quietHoursEnabled
      && isMinuteInWindow(settings.quietHoursStart, settings.quietHoursEnd, eveningMin)) evening.state = 'quiet';
    else {
      evening.state = 'rings';
      const todayAt = instantOf(todayKey, eveningMin, clock.offset);
      evening.next = todayAt > nowMs ? todayAt : instantOf(addDays(todayKey, 1), eveningMin, clock.offset);
    }
  }

  // The Saturday note (scheduleWeeklyDigest): chosen, notifications on, and
  // a habit for it to be about.
  const hasHabits = (habitDocs || []).some((d) => !d.data().archivedAt);
  const weekly = {
    state: !settings.weeklyNoteOn ? 'none' : (!settings.masterEnabled || !hasHabits ? 'off' : 'rings'),
  };

  const seen = lastSeenMs({ tokenDocs, dailyDocs, taskDocs });
  // Whether running out would silence anything: a habit reminder that
  // rings. Task reminders are armed whole, not topped up.
  const anyRinging = habits.some((h) => h.slots.some((s) => s.state === 'rings' || s.state === 'unknown'));
  // Copies that are still armed a whole month ahead: any alarm, so the
  // warning can say they last longer.
  const anyAlarm = habits.some((h) => h.alarm && h.state === 'armed');

  const { location, ...shownSettings } = settings;
  return {
    nowMs,
    todayKey,
    clock,
    settings: shownSettings,
    placeSource: settings.hasPlace ? times.source : null,
    placeLast: settings.hasPlace ? times.last : null,
    forFile,
    habits,
    without,
    tasks,
    evening,
    weekly,
    lastSeen: seen,
    stale: anyRinging && seen !== null && nowMs - seen > STALE_AFTER_DAYS * 86400000,
    anyAlarm,
    counts: {
      habits: habits.length,
      tasksAhead: tasks.filter((t) => t.ahead.length).length,
    },
  };
}

module.exports = {
  SETTINGS_DEFAULTS,
  OCCURRENCES_PER_SLOT,
  TASK_ARMED_CAP,
  TASK_PASSED_DAYS,
  STALE_AFTER_DAYS,
  lastSeenMs,
  PRAYER_NAMES,
  ROUTINE_NAMES,
  readSettings,
  accountClock,
  localOf,
  addDays,
  instantOf,
  fmtClock,
  fmtDuration,
  parseCue,
  primaryOffset,
  extraOffsets,
  habitReminder,
  slotLabel,
  slotFires,
  resolveHabitSlots,
  taskReminderTimes,
  buildRemindersModel,
};
