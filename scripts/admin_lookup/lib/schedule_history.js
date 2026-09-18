'use strict';

/**
 * The pure half of stamp_schedule_history.js: reading a schedule off the
 * command line, and working out the history a habit should carry once the
 * schedule it had before its last change is stamped in.
 *
 * Why the stamp exists at all. Since 2026-09-18 the app records a habit's
 * old schedule itself the moment it is changed (habit_cadence.dart,
 * pastCadencesAfterChange), so every past day is judged by the schedule it
 * had then. A change made BEFORE that shipped was never written down, and a
 * habit's document only ever held its current schedule, so nothing on the
 * server can say what the old one was or when it ended. Aziz's own habit is
 * one: "i had a habit that is spec days, and after some weeks, i made it
 * daily habit, it should still for the previous days that is spec days". The
 * person who made the change knows both answers; this writes them down in
 * exactly the shape the app would have.
 *
 * No Firestore here, so every rule below is testable
 * (test/stamp_schedule_history.test.js).
 */

const { shiftKey, weekdayOf } = require('./day_rules');

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const WEEKDAYS = { mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6, sun: 7 };
const WEEKDAY_ABBR = { 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun' };

/**
 * A schedule as the command line spells it, in the shape the habit document
 * stores it:
 *
 *   daily        every day, once          -> daily / 1
 *   daily:3      every day, three times   -> daily / 3
 *   weekly:4     four times a week, any   -> weekly / 4
 *   mon,thu      those weekdays only      -> weekly / 2 / [1, 4]
 *
 * The last is how Add Habit stores "Specific days": weekly, the weekdays
 * set, and a target equal to how many there are. Throws on anything else.
 */
function parseSchedule(spec) {
  const s = String(spec || '').trim().toLowerCase();
  let m = s.match(/^daily(?::(\d+))?$/);
  if (m) {
    const n = m[1] === undefined ? 1 : Number(m[1]);
    if (!(n >= 1 && n <= 24)) throw new Error(`"${spec}": times a day must be 1 to 24`);
    return { frequencyType: 'daily', frequencyTarget: n, scheduledWeekdays: [] };
  }
  m = s.match(/^weekly:(\d+)$/);
  if (m) {
    const n = Number(m[1]);
    if (!(n >= 1 && n <= 7)) throw new Error(`"${spec}": times a week must be 1 to 7`);
    return { frequencyType: 'weekly', frequencyTarget: n, scheduledWeekdays: [] };
  }
  const names = s.split(',').map((x) => x.trim()).filter(Boolean);
  if (names.length === 0) throw new Error('no schedule given');
  const days = new Set();
  for (const name of names) {
    const d = WEEKDAYS[name.slice(0, 3)];
    if (!d) {
      throw new Error(`"${name}" is not a weekday; use daily, daily:N, weekly:N or mon,tue,...`);
    }
    days.add(d);
  }
  const scheduledWeekdays = [...days].sort((a, b) => a - b);
  return { frequencyType: 'weekly', frequencyTarget: scheduledWeekdays.length, scheduledWeekdays };
}

/** A schedule read out loud, the way the admin pages print one. */
function describeSchedule(c) {
  if (!c) return 'unknown';
  const days = Array.isArray(c.scheduledWeekdays) ? c.scheduledWeekdays : [];
  if (days.length) return days.map((d) => WEEKDAY_ABBR[d] || d).join(', ');
  if (c.frequencyType === 'weekly') return `${Number(c.frequencyTarget) || 1}x a week, any days`;
  const n = Number(c.frequencyTarget) || 1;
  return n > 1 ? `every day, ${n}x` : 'every day';
}

/** The same days asked for: type, target and the weekday SET. */
function sameSchedule(a, b) {
  if (!a || !b) return false;
  if ((a.frequencyType || 'daily') !== (b.frequencyType || 'daily')) return false;
  if ((Number(a.frequencyTarget) || 1) !== (Number(b.frequencyTarget) || 1)) return false;
  const x = new Set((a.scheduledWeekdays || []).map(Number));
  const y = new Set((b.scheduledWeekdays || []).map(Number));
  if (x.size !== y.size) return false;
  for (const d of x) if (!y.has(d)) return false;
  return true;
}

/**
 * The habit's history once [was] is recorded as its schedule up to the day
 * before [changedKey], or a thrown Error saying why not.
 *
 *  - [changedKey] is the first day of the schedule it has now, the day the
 *    change was saved, which follows the NEW schedule (the app's own rule).
 *    It cannot be after [todayKey].
 *  - A period that ends before the habit was born would govern no day.
 *  - Only ever appended after what is already recorded: a period slotted in
 *    between two others would silently move where the later one starts.
 *  - [was] must differ from the schedule that follows it, or the stamp says
 *    nothing: [current] for a first period. [current] is null when the tool
 *    cannot know it (a preset still on its catalog default), and then this
 *    one check is skipped.
 */
function historyWithPeriod({ history, current, was, changedKey, bornKey, todayKey }) {
  if (!DAY_RE.test(changedKey || '')) throw new Error('--changed must be YYYY-MM-DD');
  if (changedKey > todayKey) {
    throw new Error(`--changed=${changedKey} is after today (${todayKey})`);
  }
  const until = shiftKey(changedKey, -1);
  if (bornKey && until < bornKey) {
    throw new Error(`the habit was born ${bornKey}, so a schedule that ended ${until} ` +
      'governed none of its days');
  }
  const existing = (Array.isArray(history) ? history : [])
    .filter((p) => p && typeof p.until === 'string' && DAY_RE.test(p.until))
    .slice()
    .sort((a, b) => (a.until < b.until ? -1 : a.until > b.until ? 1 : 0));
  const last = existing[existing.length - 1];
  if (last && until <= last.until) {
    throw new Error(`the history already runs to ${last.until}; a new period has to end after it`);
  }
  if (!last && current && sameSchedule(was, current)) {
    throw new Error(`${describeSchedule(was)} is the schedule it has now; nothing would change`);
  }
  const period = {
    until,
    frequencyType: was.frequencyType,
    frequencyTarget: was.frequencyTarget,
  };
  if (was.scheduledWeekdays && was.scheduledWeekdays.length) {
    period.scheduledWeekdays = was.scheduledWeekdays.slice();
  }
  return [...existing, period];
}

/**
 * The days from [fromKey] to [untilKey], inclusive, that [schedule] asks for
 * by the calendar alone. Null for a flexible quota, whose owed days depend
 * on the week's own sessions and so cannot be listed without them.
 *
 * Asked of both schedules, it gives the dry run's two lists: the days the
 * stamp turns back into rest, and the days it makes owed again.
 */
function askedDaysIn({ fromKey, untilKey, schedule }) {
  const days = Array.isArray(schedule.scheduledWeekdays) ? schedule.scheduledWeekdays : [];
  if (schedule.frequencyType === 'weekly' && days.length === 0) return null;
  const out = [];
  for (let k = fromKey; k <= untilKey; k = shiftKey(k, 1)) {
    if (days.length === 0 || days.includes(weekdayOf(k))) out.push(k);
  }
  return out;
}

module.exports = {
  DAY_RE,
  parseSchedule,
  describeSchedule,
  sameSchedule,
  historyWithPeriod,
  askedDaysIn,
};
