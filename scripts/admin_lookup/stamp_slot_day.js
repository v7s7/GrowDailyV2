/**
 * Stamps a shared-plan slot with the ONE day every member should grade it
 * from, and (optionally) lines up any member rule that starts before it.
 *
 * Why this exists. A slot used to carry only `addedAt`, an instant, and
 * every phone keyed it in its own timezone: ELQVF8's قراءة القرآن was added
 * at 2026-09-08T21:48Z, so one member's rule started 09-08 and the other's
 * 09-09, and the same day asked one of them for three habits and the other
 * for two. The app now stamps `addedDay` when the leader adds a habit
 * (RoomHabitTemplate.addedDay, Aziz 2026-09-18: "from the admin adding
 * habit, it start count for all, no after, no before"). Slots added before
 * that shipped have no stamp, and this is how they get one.
 *
 * SAFETY, and the reason this is not a one-liner:
 *
 *   - A member rule is only ever moved LATER, never earlier. Moving one
 *     earlier hands a member misses on days the room never asked them for,
 *     which is exactly the damage of 2026-09-09 on A8GEL7 (18 recorded days
 *     became 5, 69% to 18%). A rule that already starts after the stamped
 *     day is reported and left alone.
 *   - Moving a rule later can only REMOVE a habit from a past day's
 *     denominator, so a day can gain credit and never lose it. Every
 *     affected day is printed with its stored counts before the write.
 *   - The room write is a transaction over the whole sharedHabits array,
 *     because Firestore cannot update one element of an array. It refuses
 *     if the array changed shape since the read.
 *
 * Dry run unless --confirm.
 *
 *   node stamp_slot_day.js --room=ELQVF8 --slot=2 --day=2026-09-09
 *   node stamp_slot_day.js --room=ELQVF8 --slot=2 --day=2026-09-09 \
 *        --align-rules --confirm
 */
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({
  credential: admin.credential.cert(
      require(path.join(__dirname, 'service-account.json'))),
});
const db = admin.firestore();

const args = process.argv.slice(2);
const arg = (name) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
};
const CONFIRM = args.includes('--confirm');
const ALIGN = args.includes('--align-rules');
const code = arg('room');
const slotIndex = Number(arg('slot'));
const day = arg('day');

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
if (!code || !Number.isInteger(slotIndex) || slotIndex < 0 || !DAY_RE.test(day || '')) {
  console.error(
      'Usage:\n' +
      '  node stamp_slot_day.js --room=CODE --slot=N --day=YYYY-MM-DD \\\n' +
      '       [--align-rules] [--confirm]\n\n' +
      'Runs as a dry run unless --confirm is passed.');
  process.exit(2);
}

const keyOf = (ts) => {
  if (!ts || typeof ts.toDate !== 'function') return null;
  const d = ts.toDate();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const minFrom = (periods) => {
  if (!Array.isArray(periods) || periods.length === 0) return null;
  let min = null;
  for (const p of periods) {
    const from = p && typeof p.from === 'string' ? p.from : null;
    if (from && (min === null || from < min)) min = from;
  }
  return min;
};
const daysBetween = (fromKey, toKey) => {
  const out = [];
  const d = new Date(`${fromKey}T00:00:00Z`);
  const end = new Date(`${toKey}T00:00:00Z`);
  while (d < end) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
};

(async () => {
  const roomRef = db.collection('rooms').doc(code);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) {
    console.error(`No room ${code}`);
    process.exit(1);
  }
  const room = roomSnap.data();
  const slots = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  if (slotIndex >= slots.length) {
    console.error(`Room ${code} has ${slots.length} slot(s); no slot ${slotIndex}`);
    process.exit(1);
  }
  const slot = slots[slotIndex];
  const startKey = keyOf(room.startDate);

  console.log('='.repeat(74));
  console.log(`ROOM ${code}  ${room.name}   start ${startKey}`);
  console.log('='.repeat(74));
  console.log(`slot[${slotIndex}]  ${slot.name}`);
  console.log(`  addedAt   : ${slot.addedAt ? slot.addedAt.toDate().toISOString() : '(none)'}` +
      `${slot.addedAt ? `   keyed here as ${keyOf(slot.addedAt)}` : ''}`);
  console.log(`  addedDay  : ${slot.addedDay || '(none)'}`);
  console.log(`  -> stamp  : ${day}${slot.addedDay === day ? '   (already correct)' : ''}`);
  if (day < startKey) {
    console.error(`\nRefusing: ${day} is before the room's own start ${startKey}.`);
    process.exit(1);
  }

  const parts = await db.collection(`rooms/${code}/participants`).get();
  const ruleWrites = [];
  console.log('\nMembers:');
  for (const p of parts.docs) {
    const d = p.data();
    const linked = Array.isArray(d.linkedHabitIds) ? d.linkedHabitIds : [];
    const habitId = linked[slotIndex];
    const name = d.displayName || p.id;
    if (!habitId || habitId === '__declined__') {
      console.log(`  ${name}: has not linked this slot, nothing to line up`);
      continue;
    }
    const periods = (d.habitRules || {})[habitId];
    const from = minFrom(periods);
    if (from === null) {
      console.log(`  ${name}: no rule recorded yet, the app will seed it at ${day}`);
      continue;
    }
    if (from === day) {
      console.log(`  ${name}: already counts from ${day}`);
      continue;
    }
    if (from > day) {
      console.log(`  ${name}: counts from ${from}, LATER than the stamp. Left alone: ` +
          'moving a rule earlier would hand them misses for days the room never asked ' +
          'them for.');
      continue;
    }
    const affected = daysBetween(from, day);
    console.log(`  ${name}: counts from ${from} -> ${day}  ` +
        `(${affected.length} day(s) stop asking for this habit)`);
    for (const k of affected) {
      const done = (d.dailyDoneCount || {})[k];
      const sched = (d.dailyScheduledCount || {})[k];
      console.log(`      ${k}: stored done ${done === undefined ? '-' : done}` +
          `, scheduled ${sched === undefined ? '(not stored)' : sched}`);
    }
    const updated = periods.map((r) => (
      r && r.from === from ? {...r, from: day} : r
    ));
    ruleWrites.push({ref: p.ref, habitId, updated, name, from});
  }

  if (!ALIGN && ruleWrites.length > 0) {
    console.log('\nMember rules are NOT part of this run. Add --align-rules to move ' +
        'the ones listed above.');
  }
  if (!CONFIRM) {
    console.log('\nDRY RUN. Nothing was written. Add --confirm to apply.');
    process.exit(0);
  }

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(roomRef);
    const live = fresh.data();
    const liveSlots = Array.isArray(live.sharedHabits) ? live.sharedHabits : [];
    if (liveSlots.length !== slots.length) {
      throw new Error('sharedHabits changed shape since the read, stopping');
    }
    const next = liveSlots.map((s, i) => (i === slotIndex ? {...s, addedDay: day} : s));
    tx.update(roomRef, {sharedHabits: next});
  });
  console.log(`\nWROTE rooms/${code}.sharedHabits[${slotIndex}].addedDay = ${day}`);

  if (ALIGN) {
    for (const w of ruleWrites) {
      await w.ref.set(
          {habitRules: {[w.habitId]: w.updated}, lastUpdated: admin.firestore.Timestamp.now()},
          {merge: true});
      console.log(`WROTE ${w.name}: ${w.habitId} now counts from ${day} (was ${w.from})`);
    }
  }
  console.log('\nDone. Re-run diagnose_room.js to see the room as it now reads.');
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
