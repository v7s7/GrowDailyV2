'use strict';

/**
 * The decision behind repair_backdated_rules.js, with no Firestore in it:
 * for one member of one shared room, which slots carry a grading rule that
 * starts before the evidence allows, what date the evidence supports, and
 * whether the stored counts let that correction be written.
 *
 * The script does the reads (the room, the participant, users/{uid} for the
 * offset, each habit's raw createdAt), the printing and the --apply write.
 * Keeping the decision here is what lets test/backdated_rules.test.js pin it
 * against the real shapes that went wrong.
 *
 * Every day key here is the MEMBER'S PHONE date at offsetMinutes, the
 * calendar the app stamped the rules on. lib/day_key.js says why.
 */

const { keyAtOffset, storedDateKey, tsKey } = require('./day_key');

/** The earliest `from` in one slot's rule list, picked the way the script always has. */
function earliestFrom(list) {
  return list.map((x) => x.from).sort()[0];
}

function rawCreatedAt(createdAtById, habitId) {
  if (!createdAtById) return undefined;
  if (createdAtById instanceof Map) return createdAtById.get(habitId);
  return Object.prototype.hasOwnProperty.call(createdAtById, habitId)
    ? createdAtById[habitId] : undefined;
}

/**
 * @param {object} args
 * @param {object} args.room rooms/{code} data: habitMode, startDate
 *   (Timestamp), sharedHabits[i].addedAt (Timestamp, only on a slot the
 *   leader added to a running room).
 * @param {object} args.participant rooms/{code}/participants/{uid} data:
 *   habitRules (habit id -> [{from, frequencyType, frequencyTarget}]),
 *   linkedHabitIds (positional, one per plan slot), dailyDoneCount (day key
 *   -> habits done that day, as STORED).
 * @param {number} args.offsetMinutes The member's phone offset, positive
 *   east of UTC (users/{uid}.tzOffsetMinutes).
 * @param {Map<string, *>|Object<string, *>} args.createdAtById Habit id ->
 *   custom_habits/{id}.createdAt exactly as stored: a Timestamp, a string,
 *   or missing when the habit document is gone.
 * @param {boolean} [args.offsetAssumed] True when offsetMinutes is the
 *   fallback rather than the member's recorded offset. Proposals are still
 *   reported, but no patch is ever built on a guessed calendar.
 * @return {{startKey: ?string, proposals: Array<object>, broken:
 *   Array<{day: string, done: *, asked: number, askedBefore: number}>,
 *   patch: Object<string, Array<object>>}} broken lists every stored day the
 *   corrected rules would leave claiming more done than asked; asked is
 *   under the corrected rules, askedBefore under the rules as they stand.
 *   patch is empty whenever broken is not, or the offset was assumed.
 */
function proposeFor({ room, participant, offsetMinutes, createdAtById, offsetAssumed = false }) {
  const r = room || {};
  const v = participant || {};
  const startKey = tsKey(r.startDate, offsetMinutes);
  const result = { startKey, proposals: [], broken: [], patch: {} };
  if (r.habitMode !== 'shared' || !startKey) return result;

  const rules = v.habitRules || {};
  // The slot each habit sits in, so the ROOM's own record of when that
  // slot joined the plan can be used as evidence too.
  const slotOf = {};
  (v.linkedHabitIds || []).forEach((id, i) => { if (id) slotOf[id] = i; });

  for (const [habitId, list] of Object.entries(rules)) {
    if (!Array.isArray(list) || !list.length) continue;
    const minFrom = earliestFrom(list);

    // Evidence 1, from the ROOM: a slot cannot count before the leader
    // added it. sharedHabits[i].addedAt is the room's own record and is
    // far stronger than the habit's createdAt, because it says when the
    // SLOT joined rather than when some habit was made. Keyed on the
    // member's phone, the calendar planFloorFor keyed it on.
    const slot = slotOf[habitId];
    const tmpl = slot != null ? (r.sharedHabits || [])[slot] : null;
    const addedAtTs = tmpl ? tmpl.addedAt : null;
    const addedAt = tsKey(addedAtTs, offsetMinutes);
    const addedAtMs = addedAt ? addedAtTs.toDate().getTime() : null;

    // Evidence 2, from the HABIT: it cannot have been linked before it
    // existed. Weaker: a habit deleted and remade carries a new
    // createdAt while the slot's history is genuinely older.
    const born = storedDateKey(rawCreatedAt(createdAtById, habitId), offsetMinutes);

    let proposed = null;
    let why = '';
    if (addedAt && minFrom < addedAt) {
      proposed = addedAt > startKey ? addedAt : startKey;
      why = `slot joined plan ${addedAt}`;
    } else if (born && minFrom < born) {
      proposed = born > startKey ? born : startKey;
      why = `habit created ${born}`;
    }
    if (!proposed || proposed <= minFrom) continue;

    result.proposals.push({ habitId, list, minFrom, proposed, why, addedAt, addedAtMs, born });
  }

  // Now judge the whole patch together, because the test that matters is
  // about the DAY, not one slot: dailyDoneCount counts every habit done
  // that day, so a day where two of three were done is not evidence
  // about which two. The real question is whether the correction would
  // leave a day claiming MORE done than the plan asked for. If it would,
  // the evidence is wrong rather than the data - the shape of a habit
  // deleted and remade under a new id, whose slot history is genuinely
  // older than its createdAt.
  //
  // This check must read the STORED dailyDoneCount, and nothing else. A
  // recount under the corrected rule can never fail: it only counts the
  // habits that rule asks for, so every day passes by construction. On
  // 2026-09-11 a recount would have turned Aziz's 747fae86 refusals in
  // A8GEL7, BKWVN9 and YW68B9 into SAFE and erased real history, days whose
  // only record is the count the app stored at the time.
  const fromNow = {};
  for (const [hid, list] of Object.entries(rules)) {
    fromNow[hid] = Array.isArray(list) ? earliestFrom(list) : undefined;
  }
  const fromPatched = { ...fromNow };
  for (const pr of result.proposals) fromPatched[pr.habitId] = pr.proposed;
  const askedOn = (fromById, day) =>
    Object.values(fromById).filter((f) => f <= day).length;
  const done = v.dailyDoneCount || {};
  result.broken = Object.entries(done)
    .filter(([day, n]) => (n || 0) > askedOn(fromPatched, day))
    .map(([day, n]) => ({
      day,
      done: n,
      asked: askedOn(fromPatched, day),
      askedBefore: askedOn(fromNow, day),
    }));

  if (result.broken.length || offsetAssumed) return result;
  for (const pr of result.proposals) {
    result.patch[pr.habitId] = pr.list.map((x) =>
      (x.from < pr.proposed ? { ...x, from: pr.proposed } : x));
  }
  return result;
}

/** The calendar day after a YYYY-MM-DD key. */
function nextDayKey(key) {
  return keyAtOffset(Date.parse(`${key}T00:00:00Z`) + 24 * 60 * 60 * 1000, 0);
}

/**
 * True only for the shape the old UTC keying left behind: a slot added in
 * the first hours of a phone day was stamped with its UTC date, one day
 * early, and the single day the correction now refuses is that stamp day,
 * whose stored count is exactly what the stamp asked. Room ELQVF8, Hoor,
 * slot 2, stamped 2026-09-08 for an addition at 00:48 on 09-09.
 *
 * Deliberately narrow. A stored count equal to what the current stamp asked
 * is also exactly what real history looks like (A8GEL7, Aziz, 747fae86:
 * sixteen stored days before a habit remade on 09-01), so on its own it says
 * nothing about which date is right. The refusal stands either way; this
 * only lets the report say why this one line is not evidence against the
 * proposed date.
 * @param {{addedAtMs: ?number, minFrom: string, proposed: string}} proposal
 *   One entry of proposeFor's proposals.
 * @param {Array<{day: string, done: *, askedBefore: number}>} broken From
 *   proposeFor.
 * @return {boolean}
 */
function looksLikeUtcKeyedStamp(proposal, broken) {
  if (!proposal || proposal.addedAtMs == null) return false;
  if (!Array.isArray(broken) || broken.length === 0) return false;
  return keyAtOffset(proposal.addedAtMs, 0) === proposal.minFrom &&
    proposal.proposed === nextDayKey(proposal.minFrom) &&
    broken.every((b) => b.day === proposal.minFrom && b.done === b.askedBefore);
}

module.exports = { proposeFor, looksLikeUtcKeyedStamp };
