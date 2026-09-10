#!/usr/bin/env node
/**
 * Withdraw a duplicate shared-plan slot, and move anyone linked to it onto
 * the twin that stays.
 *
 * Why this exists. A shared room's plan is a list of slots, and every member
 * fills each slot with one of their own habits. Nothing used to stop a
 * leader adding a habit the plan already asked for (RoomsController.
 * addSharedHabit had no duplicate guard, unlike joinRoom, resolvePlanHabit
 * and addMyLinkedHabit, which all refuse a repeat). Room A8GEL7 is the
 * result: «تمرين» weekly/4 is slot 0 AND slot 1, added 2026-08-19.
 *
 * It cannot be repaired from inside the app, because the two members are
 * linked to DIFFERENT copies. Aziz declined slot 0 and linked slot 1; Perla
 * linked slot 0 and never answered slot 1. Withdrawing either slot from the
 * plan chip takes away one of their only counting habits and drops them to
 * 0%. The unresolved twin is meanwhile charged against both of them as a
 * phantom, which is why one of them reads 31% for work worth 69%.
 *
 * What it changes, all in one batch:
 *   rooms/{code}.sharedHabits[keep]    untouched
 *   rooms/{code}.sharedHabits[drop]    gains removedAt (a soft withdraw, the
 *                                      same stamp removeSharedHabit writes)
 *   each participant                   a habit sitting in [drop] moves to
 *                                      [keep] when [keep] is free for them,
 *                                      and [drop] becomes __declined__
 *                                      slotDeclinedFrom/slotPriorHabitIds
 *                                      for [drop] are cleared, since the slot
 *                                      is gone rather than skipped
 *
 * It never touches dailyDoneCount, dailyScheduledCount, habitRules or any
 * other stored progress: the app regrades from each member's own squares on
 * its next sync.
 *
 * Refuses unless the two slots really are twins (same name, cadence and
 * target) and unless every member ends up with at most one habit id in the
 * plan, so it cannot be used to merge two genuinely different habits.
 *
 * Usage (dry run, prints what it WOULD do and changes nothing):
 *   node dedupe_plan_slot.js --room=A8GEL7 --drop=1 --keep=0
 *
 * Add --confirm to actually write:
 *   node dedupe_plan_slot.js --room=A8GEL7 --drop=1 --keep=0 --confirm
 */

'use strict';

const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, 'service-account.json');
const DECLINED = '__declined__';

function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}
if (!fs.existsSync(KEY_PATH)) {
  fail('Missing scripts/admin_lookup/service-account.json.');
}

const args = {};
for (const raw of process.argv.slice(2)) {
  const m = raw.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) args[m[1]] = m[2] === undefined ? true : m[2];
}
const roomCode = args.room && String(args.room).trim().toUpperCase();
const drop = Number.parseInt(args.drop, 10);
const keep = Number.parseInt(args.keep, 10);
const confirm = args.confirm === true || args.confirm === 'true';
if (!roomCode || Number.isNaN(drop) || Number.isNaN(keep)) {
  fail('Usage: node dedupe_plan_slot.js --room=CODE --drop=N --keep=M [--confirm]');
}
if (drop === keep) fail('--drop and --keep must be different slots.');

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(KEY_PATH)) });
const db = admin.firestore();

/** Same identity test the app's new guard uses: name plus cadence. */
function sameSlot(a, b) {
  return String(a.name || '').trim() === String(b.name || '').trim() &&
      a.frequencyType === b.frequencyType &&
      a.frequencyTarget === b.frequencyTarget;
}

(async () => {
  const roomRef = db.collection('rooms').doc(roomCode);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) fail(`No room "${roomCode}".`);
  const room = roomSnap.data() || {};
  if (room.habitMode !== 'shared') {
    fail(`Room ${roomCode} is not a shared-plan room.`);
  }
  const shared = Array.isArray(room.sharedHabits) ? room.sharedHabits : [];
  if (drop >= shared.length || keep >= shared.length || drop < 0 || keep < 0) {
    fail(`Room ${roomCode} has ${shared.length} slot(s); --drop/--keep out of range.`);
  }
  if (shared[drop].removedAt) fail(`Slot ${drop} is already withdrawn.`);
  if (shared[keep].removedAt) fail(`Slot ${keep} is withdrawn; keep a live slot.`);
  if (!sameSlot(shared[drop], shared[keep])) {
    fail(`Slots ${drop} and ${keep} are not duplicates:\n` +
        `  [${drop}] ${shared[drop].name} ${shared[drop].frequencyType}/${shared[drop].frequencyTarget}\n` +
        `  [${keep}] ${shared[keep].name} ${shared[keep].frequencyType}/${shared[keep].frequencyTarget}\n` +
        'This script only ever collapses genuine twins.');
  }

  console.log(`\n${'='.repeat(70)}`);
  console.log(`ROOM ${roomCode}  ${room.name || ''}`);
  console.log(`  withdrawing slot [${drop}] "${shared[drop].name}", keeping [${keep}]`);
  console.log(`${'='.repeat(70)}`);

  const partsSnap = await roomRef.collection('participants').get();
  const writes = [];
  for (const doc of partsSnap.docs) {
    const p = doc.data() || {};
    const ids = Array.isArray(p.linkedHabitIds) ? [...p.linkedHabitIds] : [];
    const names = Array.isArray(p.linkedHabitNames) ? [...p.linkedHabitNames] : [];
    while (ids.length < shared.length) ids.push(DECLINED);
    while (names.length < ids.length) names.push('');

    const before = `[${ids.join(', ')}]`;
    const dropped = ids[drop];
    let moved = false;
    if (dropped && dropped !== DECLINED) {
      if (!ids[keep] || ids[keep] === DECLINED) {
        // Their habit was in the slot being withdrawn: move it to the twin.
        ids[keep] = dropped;
        names[keep] = names[drop] || '';
        moved = true;
      } else if (ids[keep] === dropped) {
        // Already in both. Just vacate the one going away.
        moved = true;
      } else {
        fail(`${p.displayName || doc.id} has DIFFERENT habits in slots ` +
            `${keep} and ${drop} (${ids[keep]} vs ${dropped}). Refusing: ` +
            'collapsing them would silently discard one habit\'s grading.');
      }
    }
    ids[drop] = DECLINED;
    names[drop] = '';

    const update = { linkedHabitIds: ids, linkedHabitNames: names };
    // The slot is gone, not skipped, so a decline stamp for it would keep
    // charging a phantom that no longer exists.
    if (p.slotDeclinedFrom && p.slotDeclinedFrom[String(drop)] !== undefined) {
      update[`slotDeclinedFrom.${drop}`] = admin.firestore.FieldValue.delete();
    }
    if (p.slotPriorHabitIds && p.slotPriorHabitIds[String(drop)] !== undefined) {
      update[`slotPriorHabitIds.${drop}`] = admin.firestore.FieldValue.delete();
    }
    // A decline stamp on the slot they are moving INTO is just as stale.
    if (p.slotDeclinedFrom && p.slotDeclinedFrom[String(keep)] !== undefined &&
        moved) {
      update[`slotDeclinedFrom.${keep}`] = admin.firestore.FieldValue.delete();
    }

    console.log(`\n  ${p.displayName || doc.id}`);
    console.log(`    before: ${before}`);
    console.log(`    after : [${ids.join(', ')}]${moved ? '   (moved to the kept slot)' : ''}`);
    writes.push({ ref: doc.ref, update });
  }

  const newShared = shared.map((h, i) =>
      i === drop ? { ...h, removedAt: admin.firestore.Timestamp.now() } : h);

  if (!confirm) {
    console.log('\nDRY RUN. Nothing was written. Re-run with --confirm.\n');
    process.exit(0);
  }
  const batch = db.batch();
  batch.set(roomRef, { sharedHabits: newShared }, { merge: true });
  for (const w of writes) batch.update(w.ref, w.update);
  await batch.commit();
  console.log('\nWritten. Every member regrades from their own squares on ' +
      'their next sync.\n');
  process.exit(0);
})().catch((e) => fail(e.message));
