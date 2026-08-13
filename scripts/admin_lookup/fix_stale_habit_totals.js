#!/usr/bin/env node
/**
 * Diagnose (and, with --zero, correct) stale habitTotalCompletions entries.
 *
 * habitTotalCompletions is the lifetime per-habit completion counter that
 * decides hard-delete vs. archive when a habit is removed (see
 * custom_habits_notifier.dart's archive() / habit_plans.dart's toggle() —
 * both gate on `everCompleted`, which is computed straight from this map).
 *
 * Before the dashboard_notifier_uncomplete_habit.dart fix, undoing a
 * completion with no same-session snapshot (e.g. after an app restart, or
 * undoing in a later session than the one where it was marked done) left
 * this counter stuck above zero forever — even though the habit's real
 * daily record was correctly cleared and the Grid square went back to
 * empty. A habit in that state looks, to every visible signal, like it was
 * never completed — but still refuses to hard-delete, and silently
 * soft-archives instead (shows for the rest of today via
 * habitsArchivedTodayProvider, then disappears tomorrow — easy to read as
 * "stuck, not deleting"). That code path is fixed going forward; this
 * script is for cleaning up counts that already went stale before the fix
 * shipped.
 *
 * Read-only by default: dumps every custom habit (id + name + archived
 * state), every catalog habit id this account has ever activated, and the
 * account's full habitTotalCompletions map, side by side, so you can see
 * exactly which id(s) are still carrying a stale count before touching
 * anything.
 *
 * Usage:
 *   node fix_stale_habit_totals.js --user=<email-or-uid>
 *   node fix_stale_habit_totals.js --user=<email-or-uid> --zero=<id1>,<id2>
 *   node fix_stale_habit_totals.js --user=<email-or-uid> --delete=<id1>,<id2>
 *   node fix_stale_habit_totals.js --user=<email-or-uid> --purgeFakeCatalog=<id1>,<id2>
 *
 * --purgeFakeCatalog is for a custom-habit id (a UUID, never a real
 * IslamicHabitCatalog template id) that ended up sitting in
 * activeCatalogIds/activeCatalogActivatedAt/activeCatalogArchivedAt/
 * activeCatalogStintHistory anyway - this happens if a custom habit that
 * was already soft-archived (so no longer in customHabitsProvider's
 * *active* list) got "deleted" again through a build that still had the
 * old customIds-membership routing bug: it would fall through to
 * ActiveCatalogNotifier.toggle() and get planted there as if it were a
 * real catalog id. Harmless to anything that only ever iterates real
 * IslamicHabitCatalog.templates and checks membership (habitListProvider,
 * allHabitsEverProvider both do) - a fake id with no matching template is
 * just invisible to them - but it's still garbage worth clearing out.
 * Strips the id from all four fields; leaves every other id in each
 * untouched.
 *
 * --zero removes exactly those keys from habitTotalCompletions via
 * Firestore's dotted-path .update() (a real field-path delete, one key at
 * a time — not .set(merge:true), which would treat a dotted key as a
 * literal field name instead of a path into the map; see completeHabit's
 * own doc comment for that exact distinction). Every other id already in
 * the map, and every other field on the account, is left untouched. Use
 * this for a still-*active* custom habit whose counter is wrong but that
 * you don't want removed — after this, the app's own delete flow will
 * correctly hard-delete it next time if it's genuinely never-completed.
 *
 * --delete is for a habit that's *already* soft-archived (archivedAt set)
 * with a stale counter — exactly the state a habit is left in after one
 * delete attempt already ran with the stale count still in place. Simply
 * clearing the counter on an already-archived custom habit isn't enough to
 * make the app remove it on a second try: CustomHabitsNotifier.archive()
 * only ever looks the id up in its *active* state list, so re-running
 * delete on an id that's already moved into the archived list is a no-op
 * from the app's side. --delete does directly, server-side, exactly what
 * the correct hard-delete branch would have done: removes the
 * custom_habits/{id} doc and clears habitTotalCompletions[id], as one
 * batch. Refuses (per id, others still proceed) if the doc doesn't have
 * archivedAt set — an active habit should go through the app's normal
 * delete flow instead, not a server-side force-delete.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, 'service-account.json');

function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}

if (!fs.existsSync(KEY_PATH)) {
  fail(
    'Missing scripts/admin_lookup/service-account.json.\n' +
    'See lookup_user.js\'s top-of-file comment for how to generate one.'
  );
}

const args = {};
for (const raw of process.argv.slice(2)) {
  const m = raw.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) args[m[1]] = m[2] === undefined ? true : m[2];
}
if (!args.user) {
  fail('Usage: node fix_stale_habit_totals.js --user=<email-or-uid> [--zero=<id1>,<id2>]');
}

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(KEY_PATH)) });
const db = admin.firestore();

function fmtDate(v) {
  if (!v) return '(active)';
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  return String(v);
}

(async () => {
  const { resolveAccount } = require('./lib/fetchAccount');
  const { uid } = await resolveAccount(String(args.user).trim());

  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) fail(`No users/${uid} doc.`);
  const profile = userSnap.data() || {};

  const totals = profile.habitTotalCompletions || {};
  // Real field names per ActiveCatalogNotifier._save() (habit_plans.dart) —
  // all prefixed with activeCatalog*, not the bare names an earlier version
  // of this script read (which silently fell back to {} and made every
  // catalog habit look unactivated when they weren't).
  const activeCatalogIds = new Set(profile.activeCatalogIds || []);
  const activatedAt = profile.activeCatalogActivatedAt || {};
  const catalogArchivedAt = profile.activeCatalogArchivedAt || {};
  const rawStintHistory = profile.activeCatalogStintHistory || {};

  const habitsSnap = await userRef.collection('custom_habits').get();

  console.log(`\nuid: ${uid}`);

  console.log(`\nCustom habits:`);
  console.log('-'.repeat(90));
  if (habitsSnap.docs.length === 0) {
    console.log('  (none)');
  }
  for (const doc of habitsSnap.docs) {
    const h = doc.data();
    const total = totals[doc.id];
    console.log(
      `  ${doc.id.padEnd(28)} total=${String(total ?? '(none)').padEnd(8)} ` +
      `archivedAt=${fmtDate(h.archivedAt)}  freq=${h.frequencyType}/${h.frequencyTarget} ` +
      `weekdays=${JSON.stringify(h.scheduledWeekdays || [])}  "${h.name || ''}"`
    );
  }

  const catalogIds = new Set([
    ...activeCatalogIds,
    ...Object.keys(activatedAt),
    ...Object.keys(catalogArchivedAt),
    ...Object.keys(rawStintHistory),
  ]);
  console.log(`\nCatalog habit ids (active / activatedAt / catalogArchivedAt):`);
  console.log('-'.repeat(90));
  if (catalogIds.size === 0) {
    console.log('  (none)');
  }
  for (const id of catalogIds) {
    const total = totals[id];
    console.log(
      `  ${id.padEnd(20)} active=${String(activeCatalogIds.has(id)).padEnd(6)} ` +
      `total=${String(total ?? '(none)').padEnd(8)} ` +
      `activatedAt=${activatedAt[id] || '—'}  catalogArchivedAt=${catalogArchivedAt[id] || '—'}`
    );
  }

  console.log(`\nCatalog stint history (closed windows from earlier activate/deactivate cycles):`);
  console.log('-'.repeat(90));
  const stintIds = Object.keys(rawStintHistory);
  if (stintIds.length === 0) {
    console.log('  (none)');
  }
  for (const id of stintIds) {
    for (const stint of rawStintHistory[id]) {
      console.log(`  ${id.padEnd(20)} start=${stint.start}  end=${stint.end}`);
    }
  }

  const todayKey = new Date().toISOString().slice(0, 10);
  const todaySnap = await userRef.collection('daily').doc(todayKey).get();
  console.log(`\nToday's daily doc (daily/${todayKey}):`);
  console.log('-'.repeat(90));
  if (!todaySnap.exists) {
    console.log('  (no doc for today)');
  } else {
    const d = todaySnap.data() || {};
    const squareStates = d.squareStates || {};
    const habitCompletions = d.habitCompletions || {};
    console.log('  squareStates:');
    if (Object.keys(squareStates).length === 0) console.log('    (empty)');
    for (const [id, v] of Object.entries(squareStates)) console.log(`    ${id.padEnd(20)} ${v}`);
    console.log('  habitCompletions:');
    if (Object.keys(habitCompletions).length === 0) console.log('    (empty)');
    for (const [id, v] of Object.entries(habitCompletions)) console.log(`    ${id.padEnd(20)} ${v}`);
  }

  console.log(`\nFull habitTotalCompletions map:`);
  console.log('-'.repeat(90));
  const totalKeys = Object.keys(totals);
  if (totalKeys.length === 0) {
    console.log('  (empty)');
  } else {
    for (const id of totalKeys) console.log(`  ${id.padEnd(28)} ${totals[id]}`);
  }

  if (args.zero) {
    const ids = String(args.zero).split(',').map((s) => s.trim()).filter(Boolean);
    if (ids.length === 0) fail('--zero given but no ids parsed.');
    const update = {};
    for (const id of ids) {
      update[`habitTotalCompletions.${id}`] = admin.firestore.FieldValue.delete();
    }
    await userRef.update(update);
    console.log(`\nCleared habitTotalCompletions for: ${ids.join(', ')}`);
    console.log('Re-run without --zero to confirm they no longer appear above.');
  }

  if (args.delete) {
    const ids = String(args.delete).split(',').map((s) => s.trim()).filter(Boolean);
    if (ids.length === 0) fail('--delete given but no ids parsed.');
    const deleted = [];
    const skipped = [];
    for (const id of ids) {
      const hRef = userRef.collection('custom_habits').doc(id);
      const hSnap = await hRef.get();
      if (!hSnap.exists) {
        skipped.push(`${id} (no such custom_habits doc)`);
        continue;
      }
      const h = hSnap.data() || {};
      if (!h.archivedAt) {
        skipped.push(`${id} (still active — no archivedAt; use the app's normal delete instead)`);
        continue;
      }
      const batch = db.batch();
      batch.delete(hRef);
      batch.update(userRef, {
        [`habitTotalCompletions.${id}`]: admin.firestore.FieldValue.delete(),
      });
      await batch.commit();
      deleted.push(id);
    }
    if (deleted.length) console.log(`\nHard-deleted: ${deleted.join(', ')}`);
    if (skipped.length) console.log(`\nSkipped:\n${skipped.map((s) => `  ${s}`).join('\n')}`);
  }

  if (args.purgeFakeCatalog) {
    const ids = String(args.purgeFakeCatalog).split(',').map((s) => s.trim()).filter(Boolean);
    if (ids.length === 0) fail('--purgeFakeCatalog given but no ids parsed.');
    const purged = [];
    const skipped = [];
    for (const id of ids) {
      if (!(id in activatedAt) && !(id in catalogArchivedAt) && !(id in rawStintHistory)) {
        skipped.push(`${id} (nothing to clear under activeCatalog* fields)`);
        continue;
      }
      await userRef.update({
        activeCatalogIds: admin.firestore.FieldValue.arrayRemove(id),
        [`activeCatalogActivatedAt.${id}`]: admin.firestore.FieldValue.delete(),
        [`activeCatalogArchivedAt.${id}`]: admin.firestore.FieldValue.delete(),
        [`activeCatalogStintHistory.${id}`]: admin.firestore.FieldValue.delete(),
      });
      purged.push(id);
    }
    if (purged.length) console.log(`\nPurged fake catalog entries for: ${purged.join(', ')}`);
    if (skipped.length) console.log(`\nSkipped:\n${skipped.map((s) => `  ${s}`).join('\n')}`);
  }

  if (!args.zero && !args.delete && !args.purgeFakeCatalog) {
    console.log(
      `\n(dry run — nothing changed. Re-run with --zero=<id1>,<id2> for an ` +
      `active habit's stale count, --delete=<id1>,<id2> for an ` +
      `already-archived one stuck the same way, or ` +
      `--purgeFakeCatalog=<id1>,<id2> to strip a custom-habit id that got ` +
      `planted into the catalog tracking fields by mistake.)`
    );
  }

  process.exit(0);
})().catch((e) => fail(e.stack || e.message));
