#!/usr/bin/env node
/**
 * Rooms that grade a member for days before their habit existed.
 *
 * A room slot's grading window is habitRules[habitId][].from. Builds before
 * 2026-09-09 stamped that at the ROOM'S START rather than the day the member
 * actually linked the habit, so a habit created later is still counted in
 * every earlier day's denominator. Aziz, 2026-09-10: "the old days still
 * count the new habit adding after".
 *
 * The contradiction is provable, which is what makes a repair safe to
 * propose: a habit cannot have been in a room before it was created. This
 * compares each slot's earliest rule against the owner's own habit
 * createdAt and reports every slot where the rule predates the habit.
 *
 * The proposed date is max(room start, habit createdAt) - the most
 * CONSERVATIVE correction that removes the contradiction. It is a lower
 * bound, not the true link day: a habit made on the 1st might have been
 * linked on the 3rd, and nothing recorded that. So this never invents a
 * later date than the evidence supports.
 *
 * Shrinking a denominator RAISES a percentage, and these rooms are ranked,
 * so this writes nothing without --apply.
 *
 *   node repair_backdated_rules.js              every room, dry run
 *   node repair_backdated_rules.js BKWVN9       one room, dry run
 *   node repair_backdated_rules.js BKWVN9 --apply
 */
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, 'service-account.json'))) });
const db = admin.firestore();

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const code = args.find(a => !a.startsWith('--'));
const key = d => d.toISOString().slice(0, 10);

(async () => {
  const rooms = code
    ? [await db.collection('rooms').doc(code).get()]
    : (await db.collection('rooms').get()).docs;

  const habitCache = new Map();
  async function createdAtOf(uid, habitId) {
    const k = `${uid}/${habitId}`;
    if (habitCache.has(k)) return habitCache.get(k);
    const d = await db.collection('users').doc(uid)
      .collection('custom_habits').doc(habitId).get();
    const raw = d.exists ? d.data().createdAt : null;
    // createdAt is a Timestamp on some documents and an ISO STRING on
    // others, which is why the first pass of this script found nothing at
    // all: it only understood Timestamps and silently skipped every habit
    // stored the other way.
    let val = null;
    if (raw && typeof raw.toDate === 'function') val = key(raw.toDate());
    else if (typeof raw === 'string' && raw.length >= 10) val = raw.slice(0, 10);
    habitCache.set(k, val);
    return val;
  }

  let findings = 0;
  for (const room of rooms) {
    if (!room.exists) { console.log(`room ${code} not found`); continue; }
    const r = room.data();
    if (r.habitMode !== 'shared') continue;
    const startKey = r.startDate && r.startDate.toDate ? key(r.startDate.toDate()) : null;
    if (!startKey) continue;
    const parts = await room.ref.collection('participants').get();
    for (const p of parts.docs) {
      const v = p.data();
      const rules = v.habitRules || {};
      const patch = {};
      const proposals = [];
      // The slot each habit sits in, so the ROOM's own record of when that
      // slot joined the plan can be used as evidence too.
      const slotOf = {};
      (v.linkedHabitIds || []).forEach((id, i) => { if (id) slotOf[id] = i; });

      for (const [habitId, list] of Object.entries(rules)) {
        if (!Array.isArray(list) || !list.length) continue;
        const minFrom = list.map(x => x.from).sort()[0];

        // Evidence 1, from the ROOM: a slot cannot count before the leader
        // added it. sharedHabits[i].addedAt is the room's own record and is
        // far stronger than the habit's createdAt, because it says when the
        // SLOT joined rather than when some habit was made.
        const slot = slotOf[habitId];
        const tmpl = slot != null ? (r.sharedHabits || [])[slot] : null;
        const addedAt = tmpl && tmpl.addedAt && tmpl.addedAt.toDate
          ? key(tmpl.addedAt.toDate()) : null;

        // Evidence 2, from the HABIT: it cannot have been linked before it
        // existed. Weaker: a habit deleted and remade carries a new
        // createdAt while the slot's history is genuinely older.
        const born = await createdAtOf(p.id, habitId);

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

        findings++;
        proposals.push({ habitId, list, minFrom, proposed, why });
      }

      // Now judge the whole patch together, because the test that matters is
      // about the DAY, not one slot: dailyDoneCount counts every habit done
      // that day, so a day where two of three were done is not evidence
      // about which two. The real question is whether the correction would
      // leave a day claiming MORE done than the plan asked for. If it would,
      // the evidence is wrong rather than the data - the shape of a habit
      // deleted and remade under a new id, whose slot history is genuinely
      // older than its createdAt.
      const patchedFrom = {};
      for (const [hid, list] of Object.entries(rules)) {
        patchedFrom[hid] = list.map(x => x.from).sort()[0];
      }
      for (const pr of proposals) patchedFrom[pr.habitId] = pr.proposed;
      const scheduledOn = day => Object.values(patchedFrom)
        .filter(f => f <= day).length;
      const done = v.dailyDoneCount || {};
      const broken = Object.entries(done)
        .filter(([d, n]) => (n || 0) > scheduledOn(d))
        .map(([d, n]) => `${d}: ${n} done vs ${scheduledOn(d)} asked`);

      for (const pr of proposals) {
        console.log(
          `${broken.length ? 'UNSAFE' : ' SAFE '} ${room.id}  ` +
          `${(v.displayName || p.id).padEnd(18)} ${pr.habitId.slice(0, 8)}  ` +
          `from ${pr.minFrom} -> ${pr.proposed}   (${pr.why})`
        );
        if (broken.length) {
          console.log(`         !! would break ${broken.length} day(s), e.g. ${broken[0]}`);
          continue;
        }
        patch[pr.habitId] = pr.list.map(x =>
          x.from < pr.proposed ? { ...x, from: pr.proposed } : x);
      }
      if (APPLY && Object.keys(patch).length) {
        const merged = { ...rules, ...patch };
        await p.ref.update({ habitRules: merged });
        console.log(`   applied to ${room.id}/${p.id}`);
      }
    }
  }
  console.log(`\n${findings} mis-stamped slot(s). ${APPLY ? 'APPLIED.' : 'Dry run, nothing written.'}`);
  console.log('A repaired slot stops counting in days before it existed, which SHRINKS');
  console.log('those days’ denominators and RAISES the percentage. Re-open the room in');
  console.log('the app afterwards so syncLinkedHabitsProgress rewrites the day counts.\n');
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
