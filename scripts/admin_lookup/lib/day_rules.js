'use strict';

/**
 * The app's own day rules, ported once, so this tool stops inventing its own.
 *
 * ── Why this file exists ──────────────────────────────────────────────────
 *
 * Every surface of this tool used to answer "how did this day go" with its
 * own arithmetic, and each one drifted from the phone in a different
 * direction. Measured on two real accounts, 2026-09-12:
 *
 *   - an OPEN day was drawn as missed. Aziz's 2026-09-11 read "5 of 9 done"
 *     with four miss chips at 02:11 the next morning, while the app had not
 *     judged the day at all: a day stays markable until kDayCutoffHour the
 *     morning after, so until then a blank habit is in progress and owes
 *     nothing (DateTimeGameExt.isSettledAt).
 *   - a weekly quota's SPARE day was drawn as missed. Hoor's تمرين on
 *     2026-09-10 sat in a week already at 4 of 4, a day the quota had bought
 *     her (weeklyQuotaDemand).
 *   - a COUNTED habit was called done at the first tap. Hoor's «Take ur
 *     pills» is a 2x-a-day habit, tapped once on 2026-09-11 and stored as
 *     جزئي by the app itself; the tool counted it as a completion.
 *   - a DELETED habit kept scoring. Aziz's 2026-09-01 read 2 of 5 because an
 *     id no longer in custom_habits still carried a green square.
 *
 * None of those are display bugs. They are four different answers to
 * questions the app has exactly one answer for, and the owner reads this
 * tool to judge real accounts, so a wrong number here has already pointed at
 * a repair write that would have damaged good data.
 *
 * So: one module, ported from the Dart, imported by render.js, activity.js
 * and the room scripts. Where a rule here disagrees with the app, the app is
 * right and this file is the bug.
 *
 * ── The frames these functions work in ────────────────────────────────────
 *
 * A day key is the calendar date on the MEMBER'S OWN PHONE (lib/day_key.js
 * says why that is never the Mac's date and never UTC). Two different kinds
 * of number appear below and must not be mixed:
 *
 *   localMs   an instant already moved onto the phone's clock, the way
 *             day_key.js's keyAtOffset moves it, and then read through the
 *             UTC getters. Day keys live in this frame.
 *   instantMs a plain epoch instant, what Timestamp.toDate().getTime()
 *             returns. closesAtInstantMs is the one bridge between them.
 *
 * Everything that takes a clock says which of the two it wants.
 */

const { keyAtOffset, APP_FALLBACK_OFFSET_MINUTES } = require('./day_key');

// lib/core/extensions/datetime_ext.dart's kDayCutoffHour. A day runs from
// its own 00:00 until this hour the NEXT morning, so between midnight and
// 10:00 there are two open days and both pay in full. Declared here and
// re-exported by render.js so there is one copy in this tool; the test in
// test/day_rules.test.js reads the Dart file rather than trusting either.
const DAY_CUTOFF_HOUR = 10;

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const MINUTE_MS = 60 * 1000;

// SquareState.isGreen: complete || bonus, nothing else. The exact test a
// room's sync applies and the exact test for "did this discharge the day".
const GREEN_STATES = new Set(['complete', 'bonus']);

// SquareState.answersDay: a finished square or an explicit فشل settles its
// day at once, while it is still open. A blank, a جزئي and a تخطّي are all
// still finishable, so they wait for the day to close.
const ANSWERING_STATES = new Set(['complete', 'bonus', 'failed']);

const DECLINED_SLOT = '__declined__';

/** SquareState.isGreen. */
function isGreen(state) {
  return GREEN_STATES.has(String(state));
}

/** SquareState.answersDay. */
function answersDay(state) {
  return ANSWERING_STATES.has(String(state));
}

/**
 * How much of a day's obligation one square discharges: markCredit in
 * lib/features/milestones/reports/habit_day_marks.dart.
 *
 * جزئي is 0.5 and is 0.5 EVERYWHERE (SquareState.xpValue pays it 5 against
 * complete's 10, RoomParticipant.creditFor weighs it half a habit, the
 * reports credit it 0.5). Rooms was the last surface scoring it as nothing,
 * and this tool was the one after that.
 */
function markCredit(state) {
  const s = String(state);
  if (GREEN_STATES.has(s)) return 1;
  return s === 'partial' ? 0.5 : 0;
}

/**
 * Only تخطّي. A rested habit leaves the denominator entirely rather than
 * scoring zero in it, which is the whole point of having the state.
 */
function isRestMark(state) {
  return String(state) === 'skipped';
}

/**
 * What one habit's day asked of it, as recorded ON THE DAY ITSELF.
 *
 * Never the habit's CURRENT frequencyTarget: somebody who later changes a
 * habit from once to four times a day must not have last month's finished
 * days re-graded as part-done. A day with no stamp falls back to 1, the only
 * value any habit could have had before counting existed. dayTargetOf in
 * habit_day_marks.dart.
 */
function dayTargetOf(dayData, habitId) {
  const targets = dayData && dayData.habitTargets;
  const raw = targets && typeof targets === 'object' ? targets[habitId] : undefined;
  return typeof raw === 'number' && Number.isFinite(raw) && raw >= 1
    ? Math.floor(raw) : 1;
}

/**
 * The square one habit really wore on one day, across the records that
 * disagree: dayMark in habit_day_marks.dart, ported whole.
 *
 * "Any count at all means complete" was written when a habit could only be
 * done once a day. A habit counted twice a day breaks it: one tap is a
 * part-done day, not a finished one. Hoor's «Take ur pills» on 2026-09-11
 * is exactly that shape, and the app had already written جزئي on it while
 * this tool was calling it a completion.
 */
function dayMark(dayData, habitId) {
  const d = dayData || {};
  const squares = d.squareStates && typeof d.squareStates === 'object' ? d.squareStates : {};
  const painted = String(squares[habitId] === undefined ? 'none' : squares[habitId]);
  if (isGreen(painted)) return painted;
  const comps = d.habitCompletions && typeof d.habitCompletions === 'object' ? d.habitCompletions : {};
  const count = comps[habitId];
  if (typeof count === 'number' && Number.isFinite(count) && count > 0) {
    return count >= dayTargetOf(dayData, habitId) ? 'complete' : 'partial';
  }
  return painted;
}

// ── The day window ───────────────────────────────────────────────────────

/** Plain calendar arithmetic on a key's own digits, timezone-free. */
function shiftKey(key, n) {
  const [y, m, d] = String(key).split('-').map(Number);
  return keyAtOffset(Date.UTC(y, m - 1, d + n), 0);
}

/** Midnight at the start of [key], in the localMs frame. */
function dayStartLocalMs(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

/**
 * The instant [key] stops being open, in the localMs frame:
 * DateTimeGameExt.closesAt, its own start plus one day and the cutoff.
 */
function closesAtLocalMs(key) {
  return dayStartLocalMs(key) + DAY_MS + DAY_CUTOFF_HOUR * HOUR_MS;
}

/**
 * The same close as a REAL epoch instant, for comparing against a Firestore
 * Timestamp without moving the timestamp into anybody's frame first.
 *
 * [offsetMinutes] is the phone's offset, positive east of UTC. Aziz's
 * 2026-09-10 at +180 closes at 2026-09-11T07:00Z, which is 10:00 on his own
 * clock the next morning.
 */
function closesAtInstantMs(key, offsetMinutes) {
  const off = typeof offsetMinutes === 'number' && Number.isFinite(offsetMinutes)
    ? offsetMinutes : APP_FALLBACK_OFFSET_MINUTES;
  return dayStartLocalMs(key) - off * MINUTE_MS + DAY_MS + DAY_CUTOFF_HOUR * HOUR_MS;
}

/** An instant moved onto the phone's clock, the frame day keys live in. */
function localNowMs(instantMs, offsetMinutes) {
  const off = typeof offsetMinutes === 'number' && Number.isFinite(offsetMinutes)
    ? offsetMinutes : APP_FALLBACK_OFFSET_MINUTES;
  return instantMs + off * MINUTE_MS;
}

/**
 * DateTimeGameExt.isOpenDayAt. Tomorrow is never open, so nothing can be
 * marked ahead of the day it belongs to.
 */
function isOpenDayAt(key, nowLocalMs) {
  return nowLocalMs >= dayStartLocalMs(key) && nowLocalMs < closesAtLocalMs(key);
}

/**
 * DateTimeGameExt.isSettledAt: whether a habit-day may be COUNTED yet, i.e.
 * entered into a percentage or drawn as missed.
 *
 * This is the rule the tool broke most often. A day counts once it is
 * ANSWERED (finished, or an explicit فشل somebody chose to record) or once
 * it has CLOSED, whichever comes first. A blank habit on a day still open is
 * in progress, not missed.
 */
function isSettledAt(key, nowLocalMs, { answered = false } = {}) {
  return nowLocalMs >= dayStartLocalMs(key) && (answered || !isOpenDayAt(key, nowLocalMs));
}

/**
 * The newest day that has FULLY closed at [nowLocalMs].
 *
 * Yesterday is still payable until the cutoff, so before 10:00 that is the
 * day before yesterday and from 10:00 onward it is yesterday. check_rooms.js
 * used a flat "now minus two days", which is right for ten hours a day and a
 * day short for the other fourteen.
 */
function newestClosedKey(nowLocalMs) {
  const today = keyAtOffset(nowLocalMs, 0);
  const yesterday = shiftKey(today, -1);
  return nowLocalMs >= closesAtLocalMs(yesterday) ? yesterday : shiftKey(today, -2);
}

// ── Weekly quotas ────────────────────────────────────────────────────────

/**
 * weeklyQuotaDemand in lib/features/habits/models/weekly_quota_plan.dart,
 * ported exactly, including the clamp of [target] into the week's length.
 *
 * The question is DAY-LOCAL, which is the whole point: what a Tuesday was
 * asking is fixed by what was banked before it and how many days followed
 * it, so a resolved day's verdict never flips later.
 *
 *   'done'   recorded on this day
 *   'owed'   load-bearing: skip it and the target is out of reach
 *   'spare'  not needed yet, enough days remain
 *   'earned' not needed at all, the target was already met
 */
function weeklyQuotaDemand({ dayCount, doneDays, target }) {
  if (!(dayCount > 0)) return [];
  const done = doneDays instanceof Set ? doneDays : new Set(doneDays || []);
  const effectiveTarget = Math.min(Math.max(target, 1), dayCount);
  const out = [];
  let doneBefore = 0;
  for (let i = 0; i < dayCount; i++) {
    const need = effectiveTarget - doneBefore;
    if (need <= 0) {
      out.push(done.has(i) ? 'done' : 'earned');
    } else if (done.has(i)) {
      out.push('done');
    } else {
      const remaining = dayCount - i; // includes this day
      out.push(remaining - need <= 0 ? 'owed' : 'spare');
    }
    if (done.has(i)) doneBefore++;
  }
  return out;
}

/** Nothing was owed, so an empty square is not a miss. DayDemand.isRest. */
function demandIsRest(demand) {
  return demand === 'spare' || demand === 'earned';
}

/**
 * The SATURDAY week containing [key], matching
 * DateTimeGameExt.startOfDisplayWeek, which is the week the Grid actually
 * draws. Using the ISO Monday week here instead is how "4 times this week"
 * once meant a different seven days than the week the person was looking at.
 */
function displayWeekStartKey(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  const jsDow = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=Sun..6=Sat
  const iso = jsDow === 0 ? 7 : jsDow; // 1=Mon..7=Sun
  return shiftKey(key, -((iso - 6 + 7) % 7));
}

/**
 * A FLEXIBLE weekly quota ("N times a week, any days"), which is the only
 * cadence whose empty square is ambiguous.
 *
 * Deliberately not `frequencyType === 'weekly'` alone: "Specific Days" is
 * also stored as weekly and is told apart only by scheduledWeekdays being
 * set. Getting that wrong turns a Mon/Wed/Fri habit into a quota.
 */
function isFlexibleQuota(habitData) {
  const h = habitData || {};
  const weekdays = Array.isArray(h.scheduledWeekdays) ? h.scheduledWeekdays : [];
  return h.frequencyType === 'weekly' && weekdays.length === 0;
}

/**
 * missIsAttributable in reports/report_period.dart: whether a blank day can
 * be pinned on this habit at all. A flexible quota owes no PARTICULAR day,
 * so nobody owed Tuesday and a blank Tuesday is not a miss.
 */
function missIsAttributable(habitData) {
  const h = habitData || {};
  const target = Number(h.frequencyTarget) || 0;
  return !(isFlexibleQuota(h) && target > 0);
}

/**
 * What a flexible quota was asking of [dayKey], resolved across that day's
 * whole Saturday week.
 *
 * [isGreenOn] answers "was this habit green on that key", which is what the
 * Grid row itself feeds weeklyQuotaDemand. Returns null for any habit that
 * is not a flexible quota, so a caller can tell "no demand rule applies"
 * from "the rule says spare".
 */
function quotaDemandOn({ habitData, dayKey, isGreenOn }) {
  if (!isFlexibleQuota(habitData)) return null;
  const weekStart = displayWeekStartKey(dayKey);
  const days = [];
  for (let i = 0; i < 7; i++) days.push(shiftKey(weekStart, i));
  const doneDays = new Set();
  days.forEach((k, i) => { if (isGreenOn(k)) doneDays.add(i); });
  const demand = weeklyQuotaDemand({
    dayCount: 7,
    doneDays,
    target: Number(habitData.frequencyTarget) || 1,
  });
  return demand[days.indexOf(dayKey)] || null;
}

/**
 * isCoveredDay in lib/features/grid/models/covered_day.dart: a day the habit
 * asked NOTHING of, so an empty square on it is covered rather than missing.
 *
 * Never a day before the habit existed or after it was archived, never a
 * future day, and never a day carrying any mark, because a real colour is a
 * record and stays what it is. Today's spare day is not covered either: it
 * is still open, which is the one meaning a plain square is left with.
 */
function isCoveredDay({ habitData, dayKey, todayKey, square, demand }) {
  if (String(square) !== 'none') return false;
  if (dayKey > todayKey) return false;
  const h = habitData || {};
  const born = habitDateKey(h.createdAt);
  if (born && dayKey < born) return false;
  const died = habitDateKey(h.archivedAt);
  if (died && dayKey > died) return false;
  const weekdays = Array.isArray(h.scheduledWeekdays) ? h.scheduledWeekdays : [];
  if (weekdays.length > 0) return !weekdays.includes(weekdayOf(dayKey));
  if (!demand) return false;
  if (demand === 'earned') return true;
  return demand === 'spare' && dayKey < todayKey;
}

/**
 * A habit's createdAt/archivedAt as a day key. These are stored two ways on
 * real documents: a Timestamp, and a bare local ISO string with no zone
 * (Dart's toIso8601String of a local DateTime), whose first ten characters
 * already ARE the phone's date. Handing the second to new Date() reads it in
 * THIS machine's zone, which is how a habit born at 00:30 lost a day.
 */
function habitDateKey(raw) {
  if (!raw) return null;
  if (typeof raw.toDate === 'function') {
    const d = raw.toDate();
    return d ? keyAtOffset(d.getTime(), 0) : null;
  }
  if (raw instanceof Date) return keyAtOffset(raw.getTime(), 0);
  if (typeof raw === 'string' && raw.length >= 10) return raw.slice(0, 10);
  return null;
}

/** 1=Monday..7=Sunday, Dart's DateTime.weekday convention. */
function weekdayOf(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  const jsDow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return jsDow === 0 ? 7 : jsDow;
}

/**
 * IslamicHabitTemplate.isScheduledFor: existence bounds plus named weekdays.
 * The archive day itself still counts.
 */
function habitScheduledOn(habitData, dayKey) {
  const h = habitData || {};
  const born = habitDateKey(h.createdAt);
  if (born && dayKey < born) return false;
  const died = habitDateKey(h.archivedAt);
  if (died && dayKey > died) return false;
  const weekdays = Array.isArray(h.scheduledWeekdays) ? h.scheduledWeekdays : [];
  return weekdays.length === 0 || weekdays.includes(weekdayOf(dayKey));
}

// ── Scoring one day ──────────────────────────────────────────────────────

/**
 * dayScoreFor in reports/day_score.dart, against the habits that were alive
 * on the day.
 *
 * [habits] is the account's CURRENT custom_habits as `{id, data}`. A
 * hard-deleted habit is absent from it and therefore leaves BOTH sides of
 * the ratio, which is the app's own long-documented behaviour and the fix
 * for Aziz's 2026-09-01 reading 2 of 5 where the app read 1 of 5: an id no
 * longer in the account still carried a green square, and the tool counted
 * it.
 *
 * [nowLocalMs] is the clock in the phone's frame. Passing null scores every
 * day as closed, which is the older reading and the one that called an open
 * day missed, so callers that have a clock must pass it.
 *
 * Returns the same two numbers DayScore keeps apart: [done] is the integer
 * a chart prints, [credit] carries جزئي at 0.5. [settledOwed]/[settledCredit]
 * are the part that may be judged yet.
 */
function scoreDay({ habits, dayData, dayKey, nowLocalMs, todayKey }) {
  const list = habits || [];
  const today = todayKey || (nowLocalMs == null ? dayKey : keyAtOffset(nowLocalMs, 0));
  const isGreenOn = (id) => (key) => isGreen(dayMark(key === dayKey ? dayData : null, id));

  const rows = [];
  let done = 0, failed = 0, rested = 0, owed = 0, covered = 0;
  let credit = 0, settledOwed = 0, settledCredit = 0;

  for (const h of list) {
    const mark = dayMark(dayData, h.id);
    const due = missIsAttributable(h.data) && habitScheduledOn(h.data, dayKey);
    // The demand rule only ever needs THIS day's week, and the caller may
    // supply a week-aware lookup; without one a quota day can still be
    // resolved from the day document alone, which is enough to tell an
    // `earned` day from an `owed` one whenever the week's marks are present.
    const demand = quotaDemandOn({
      habitData: h.data,
      dayKey,
      isGreenOn: h.isGreenOn || isGreenOn(h.id),
    });

    if (isRestMark(mark)) {
      rested++;
      rows.push({ habitId: h.id, mark, due, demand, counts: false, rested: true });
      continue;
    }
    const earned = markCredit(mark);
    // Credit is checked BEFORE the due test on purpose: a quota habit that
    // was actually done adds 1 to both sides and can only pull the day up,
    // while leaving it out of the denominator would let a 3-of-2 day exist.
    // An explicit فشل enters too, because recording a failure is somebody
    // telling the app that day was owed.
    const counts = earned > 0 || mark === 'failed' || due;
    if (!counts) {
      if (isCoveredDay({ habitData: h.data, dayKey, todayKey: today, square: mark, demand })) {
        covered++;
      }
      rows.push({ habitId: h.id, mark, due, demand, counts: false, rested: false });
      continue;
    }
    owed++;
    credit += earned;
    if (isGreen(mark)) done++;
    if (mark === 'failed') failed++;
    const settled = nowLocalMs == null ||
      isSettledAt(dayKey, nowLocalMs, { answered: answersDay(mark) });
    if (settled) {
      settledOwed++;
      settledCredit += earned;
    }
    rows.push({ habitId: h.id, mark, due, demand, counts: true, settled, credit: earned });
  }

  const isOpen = nowLocalMs != null && isOpenDayAt(dayKey, nowLocalMs);
  return {
    rows, done, credit, owed, failed, rested, covered,
    settledOwed, settledCredit, isOpen,
    // A day still open with something on it not yet answered is in progress,
    // so nothing may judge it yet.
    isPending: isOpen && settledOwed < owed,
    // Null when the day asked for nothing, which is NOT the same as 0%. A
    // caller rendering `rate ?? 0` puts back exactly the lie this return
    // type exists to prevent.
    rate: owed <= 0 ? null : Math.min(1, credit / owed),
  };
}

/**
 * 0 (nothing) to 4 (everything owed discharged), on the app's OWN tiers:
 * heatLevel in lib/features/grid/screens/monthly_heatmap_screen.dart.
 *
 * The thresholds matter and a plausible-looking `ceil(ratio * 4)` does not
 * reproduce them. Under that formula anything from 0.76 upward lands on 4,
 * so Aziz's 2026-09-10 at 7 of 9 was painted the identical solid colour as a
 * spotless day. The app reserves the top tier for a day that discharged
 * EVERYTHING and steps down at 0.8 and 0.5, which is why 7 of 9 reads
 * visibly lighter on his phone than it did on this page.
 *
 * Fed weighted [credit] over [owed] rather than green squares over habits
 * scheduled, so a جزئي moves the colour by half a habit. A day that owed
 * nothing stays level 0: there is nothing there to call complete.
 */
function heatLevel(credit, owed) {
  if (!(credit > 0)) return 0;
  if (!(owed > 0)) return 0;
  const pct = credit / owed;
  if (pct >= 1) return 4;
  if (pct >= 0.8) return 3;
  if (pct >= 0.5) return 2;
  return 1;
}

// ── What a day actually paid ─────────────────────────────────────────────

/**
 * The real XP and gold a day paid, from the per-day ledger.
 *
 * `totalXpEarned` / `totalGoldEarned` are DEAD. daily_log_model.dart still
 * declares them and nothing in the app has written them since the per-day
 * paid ledger landed, so every "Earned" line in this tool printed +0 XP for
 * days that really paid hundreds. Aziz's 2026-09-10 paid 235 XP and 80 gold.
 *
 * The live fields:
 *
 *   habitPaidXp / habitPaidGold  per habit, what that habit actually paid on
 *                                this day, boost and daily cap already
 *                                applied. This is the receipt an undo
 *                                reverses exactly, so it is the honest total.
 *   squareFlatXp                 what a square painted directly on the Grid
 *                                paid, a separate path from completeHabit.
 *                                Aziz's 2026-09-03 جزئي on تمرين paid 5 this
 *                                way and nothing else.
 *   dayEarnedXp / dayEarnedGold  a RUNNING TOTAL for the grace window, kept
 *                                for the daily cap, not a delta. Adding it to
 *                                the per-habit sums double counts, so it is
 *                                reported separately and never folded in.
 */
function dayPayout(dayData) {
  const d = dayData || {};
  const sumOf = (field) => {
    const map = d[field];
    if (!map || typeof map !== 'object') return { total: 0, present: false, per: {} };
    let total = 0;
    const per = {};
    for (const [id, v] of Object.entries(map)) {
      const n = Number(v);
      if (!Number.isFinite(n)) continue;
      total += n;
      per[id] = n;
    }
    return { total, present: true, per };
  };
  const paidXp = sumOf('habitPaidXp');
  const paidGold = sumOf('habitPaidGold');
  const flat = sumOf('squareFlatXp');
  const graceXp = Number(d.dayEarnedXp);
  const graceGold = Number(d.dayEarnedGold);
  return {
    xp: paidXp.total + flat.total,
    gold: paidGold.total,
    perHabitXp: paidXp.per,
    perHabitGold: paidGold.per,
    flatXp: flat.per,
    // False for a day written before the ledger existed, so a caller can say
    // "not recorded" instead of asserting a confident zero.
    hasLedger: paidXp.present || paidGold.present || flat.present,
    graceXp: Number.isFinite(graceXp) ? graceXp : null,
    graceGold: Number.isFinite(graceGold) ? graceGold : null,
  };
}

/**
 * Whether a habit's payout on a day was the 2x room boost, and from where.
 *
 * roomBoostedReward (rooms_notifier.dart) doubles XP and gold while a habit
 * is linked in a RUNNING room. The tool cannot re-derive the exact figure,
 * because the daily cap and the level curve both move it, so this never
 * predicts a number: it reports the boost that was in force, beside whatever
 * the ledger actually recorded.
 */
function boostRoomsFor({ roomRows, habitId, dayKey }) {
  const out = [];
  for (const r of roomRows || []) {
    if (!roomCountsHabitOn({ room: r.room, participant: r.participant, habitId, dayKey })) {
      continue;
    }
    if (!roomWasRunningOn(r.room, dayKey)) continue;
    out.push(r.code);
  }
  return out;
}

// ── What a room really counted ───────────────────────────────────────────

/** The room's own window, on the keys themselves. */
function roomWasRunningOn(room, dayKey) {
  const r = room || {};
  const start = habitDateKey(r.startDate);
  const end = habitDateKey(r.endDate);
  if (start && dayKey < start) return false;
  if (end && dayKey > end) return false;
  const spans = Array.isArray(r.pausedSpans) ? r.pausedSpans : [];
  return !spans.some((s) => s && s.from <= dayKey && dayKey <= s.to);
}

/**
 * The first day a member's room rule for [habitId] applies: the earliest
 * `from` across their habitRules periods, or null when none is recorded,
 * which fails open exactly as the client does. RoomParticipant.slotOpenBy.
 */
function slotFloorFor(participant, habitId) {
  const rules = (participant && participant.habitRules) || {};
  const periods = Array.isArray(rules[habitId]) ? rules[habitId] : [];
  let floor = null;
  for (const p of periods) {
    const from = p && typeof p.from === 'string' ? p.from : null;
    if (from && (floor === null || from < floor)) floor = from;
  }
  return floor;
}

/**
 * Whether this room counted [habitId] for this member on [dayKey]: linked,
 * not declined, not withdrawn from a shared plan by the leader, and past the
 * day its own rule starts.
 *
 * This is the question the ledger's "Counts where" column was never asking.
 * It printed "Rooms count it" for any green square, so Hoor's المشي on
 * 2026-09-05 was tagged as counting in a room although no room links that
 * habit at all, and Aziz's جزئي تمرين on 2026-09-03 was tagged "Neither"
 * although ELQVF8 stored it as a partial worth 0.5 that day.
 */
function roomCountsHabitOn({ room, participant, habitId, dayKey }) {
  const p = participant || {};
  const linked = Array.isArray(p.linkedHabitIds) ? p.linkedHabitIds : [];
  const shared = Array.isArray((room || {}).sharedHabits) ? room.sharedHabits : [];
  const i = linked.indexOf(habitId);
  if (i < 0 || habitId === DECLINED_SLOT) return false;
  if ((room || {}).habitMode === 'shared' && i < shared.length && shared[i] && shared[i].removedAt) {
    return false;
  }
  if (p.leftAt) return false;
  const floor = slotFloorFor(p, habitId);
  if (floor && dayKey < floor) return false;
  return true;
}

/**
 * RoomParticipant.countedHabitCountOn: how many slots had actually joined
 * the plan by [dayKey]. The denominator the stored scheduled count falls
 * back to.
 *
 * Never zero while anything is linked, because a zero denominator is FULL
 * credit in creditFor and that would pay a member 1.0 a day for days before
 * their only slot joined.
 */
function countedHabitCountOn({ participant, dayKey }) {
  const linked = Array.isArray((participant || {}).linkedHabitIds)
    ? participant.linkedHabitIds : [];
  let open = 0;
  let counted = 0;
  for (const id of linked) {
    if (id === DECLINED_SLOT) continue;
    counted++;
    const floor = slotFloorFor(participant, id);
    if (!floor || floor <= dayKey) open++;
  }
  return open === 0 ? counted : open;
}

/** RoomParticipant.wasObservedOn: graded only once the day had CLOSED. */
function wasObservedOn({ participant, dayKey, offsetMinutes }) {
  const p = participant || {};
  const at = p.lastSyncedAt;
  const ms = at && typeof at.toDate === 'function' ? at.toDate().getTime()
    : (at instanceof Date ? at.getTime() : null);
  if (ms !== null) return ms >= closesAtInstantMs(dayKey, offsetMinutes);
  const through = p.lastSyncedDay;
  return typeof through === 'string' ? dayKey <= through : false;
}

/**
 * RoomParticipant.scheduledCountFor, as the document records it.
 *
 * An explicit stored entry always wins: the sync knows more than any
 * inference, withdrawn slots included. The quotaOkWeeks arm below is the
 * app's own inference for a day no sync ever reached, and it only runs on a
 * purely weekly plan, because quotaOkWeeks attests to quota habits and to
 * nothing else.
 */
function storedScheduledOn({ room, participant, dayKey, offsetMinutes }) {
  const p = participant || {};
  const stored = (p.dailyScheduledCount || {})[dayKey];
  if (typeof stored === 'number') return stored;
  const done = (p.dailyDoneCount || {})[dayKey] || 0;
  const partial = (p.dailyPartialCount || {})[dayKey] || 0;
  if (!wasObservedOn({ participant: p, dayKey, offsetMinutes }) &&
      done === 0 && partial === 0 &&
      everyCountedHabitIsWeeklyOn({ room, participant: p, dayKey }) &&
      (Array.isArray(p.quotaOkWeeks) ? p.quotaOkWeeks : [])
        .includes(displayWeekStartKey(dayKey))) {
    return 0;
  }
  return countedHabitCountOn({ participant: p, dayKey });
}

/** RoomParticipant._everyCountedHabitIsWeeklyOn. */
function everyCountedHabitIsWeeklyOn({ room, participant, dayKey }) {
  const p = participant || {};
  const linked = Array.isArray(p.linkedHabitIds) ? p.linkedHabitIds : [];
  let sawOne = false;
  for (const id of linked) {
    if (id === DECLINED_SLOT) continue;
    sawOne = true;
    const rule = ruleForOn(p, id, dayKey);
    if (!rule || rule.frequencyType !== 'weekly') return false;
  }
  return sawOne;
}

/** RoomParticipant.ruleFor: the latest period already started by [dayKey]. */
function ruleForOn(participant, habitId, dayKey) {
  const rules = ((participant || {}).habitRules || {})[habitId];
  if (!Array.isArray(rules) || rules.length === 0) return null;
  let best = null;
  let earliest = null;
  for (const r of rules) {
    if (!r || typeof r.from !== 'string') continue;
    if (!earliest || r.from < earliest.from) earliest = r;
    if (r.from <= dayKey && (!best || r.from > best.from)) best = r;
  }
  return best || earliest;
}

/**
 * RoomParticipant.creditFor, from the STORED counts: 0.0 to 1.0, with a
 * جزئي habit worth half a habit.
 *
 * A day nothing was scheduled on is full credit, not zero: there was nothing
 * to fall short of. A stood-down day is worth nothing and is excluded from
 * both sides elsewhere, so it never reaches this.
 */
function creditForStored({ done, partial, scheduled, demand, credit }) {
  if (scheduled === 0) return 1;
  if (!(scheduled > 0)) return 0;
  // The WEIGHTED pair when the grader recorded one, exactly as the Dart does
  // (RoomParticipant.creditFor). A flexible quota on a mixed plan carries
  // target/D of a closed week on every day of it rather than a whole slot on
  // the days it is answerable for, so the day's demand is not a whole number
  // of habits any more. Absent means "use the counts", which is every day
  // graded before the ruling and every plan with no quota in it.
  const d = typeof demand === 'number' && demand > 0 ? demand : scheduled;
  const c = typeof credit === 'number'
    ? credit
    : (done || 0) + (partial || 0) * 0.5;
  return Math.max(0, Math.min(1, c / d));
}

/**
 * Everything one room stored about one member on one day, which is what the
 * day card should print instead of `allDoneToday`.
 *
 * `allDoneToday` is a SINGLE flag with a SINGLE date beside it, so it can
 * only ever answer for the one day it was last computed. The card read it
 * for every day and said "the room did not count this day" about days the
 * room had scored 2 of 3.
 */
function roomDayCounts({ room, participant, dayKey, offsetMinutes }) {
  const p = participant || {};
  const stoodDown = (Array.isArray(p.standDownDays) ? p.standDownDays : []).includes(dayKey);
  const done = (p.dailyDoneCount || {})[dayKey] || 0;
  const partial = (p.dailyPartialCount || {})[dayKey] || 0;
  const scheduled = storedScheduledOn({ room, participant: p, dayKey, offsetMinutes });
  const running = roomWasRunningOn(room, dayKey);
  return {
    done,
    partial,
    scheduled,
    stoodDown,
    running,
    // A day the whole plan was stood down is worth nothing and is excluded
    // from both sides of the ratio, so it must not read as finished.
    credit: stoodDown
      ? 0
      : creditForStored({
        done,
        partial,
        scheduled,
        demand: (p.dailyScheduledWeight || {})[dayKey],
        credit: (p.dailyDoneWeight || {})[dayKey],
      }),
    isRest: !stoodDown && scheduled === 0,
  };
}

module.exports = {
  DAY_CUTOFF_HOUR,
  DECLINED_SLOT,
  GREEN_STATES,
  isGreen,
  answersDay,
  markCredit,
  isRestMark,
  dayTargetOf,
  dayMark,
  shiftKey,
  dayStartLocalMs,
  closesAtLocalMs,
  closesAtInstantMs,
  localNowMs,
  isOpenDayAt,
  isSettledAt,
  newestClosedKey,
  weeklyQuotaDemand,
  demandIsRest,
  displayWeekStartKey,
  isFlexibleQuota,
  missIsAttributable,
  quotaDemandOn,
  isCoveredDay,
  habitDateKey,
  weekdayOf,
  habitScheduledOn,
  scoreDay,
  heatLevel,
  dayPayout,
  boostRoomsFor,
  roomWasRunningOn,
  slotFloorFor,
  roomCountsHabitOn,
  countedHabitCountOn,
  wasObservedOn,
  storedScheduledOn,
  ruleForOn,
  creditForStored,
  roomDayCounts,
};
