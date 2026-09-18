/**
 * Stamps the schedule a habit ran on BEFORE its last change, for a change
 * made before the app started keeping that record itself.
 *
 * Why this exists. Aziz, 2026-09-18: "i had a habit that is spec days, and
 * after some weeks, i made it daily habit, it should still for the previous
 * days that is spec days, like rest rest days and the other, and the days
 * after are daily." The app now records the old schedule the moment one is
 * changed (habit_cadence.dart), and judges every past day by the schedule it
 * had then. A change saved before that shipped left nothing behind: the
 * habit's document only ever held its current schedule. So its old off-days
 * still read as misses, until the old schedule and the day it ended are
 * written down here, in exactly the shape the app writes them.
 *
 * Two runs:
 *
 *   node stamp_schedule_history.js --user=<email or uid>
 *
 *     Lists every custom habit and every edited preset with its schedule
 *     now, the history already recorded, and every period a ROOM recorded
 *     for it. A room keeps its own frozen copy of the schedule a habit had
 *     when it was linked, which is often the only surviving record of the
 *     old one, and a later period there is often the day it changed.
 *
 *   node stamp_schedule_history.js --user=<email or uid> --habit=<id> \
 *        --changed=YYYY-MM-DD --was=<schedule> [--confirm]
 *
 *     Records that the habit ran on <schedule> up to the day before
 *     --changed, the first day of the schedule it has now. <schedule> is
 *     daily, daily:N (N times a day), weekly:N (N times a week, any days) or
 *     weekday names such as mon,thu. Dry run unless --confirm.
 *
 * SAFETY:
 *   - Reads first and prints what changes: the days that go back to being
 *     rest and the days that become owed again. Writes nothing without
 *     --confirm.
 *   - Only ever appends after the history already recorded, never before
 *     the habit was born, never a change dated after today, and never a
 *     schedule identical to the one that follows it.
 *   - The write is a transaction that refuses if the habit's schedule or its
 *     history changed since the read.
 *   - Rooms are untouched. They grade by their own frozen rules.
 *   - A phone holding this account keeps the habit in memory, and saving
 *     that habit (or, for a preset, any preset) from it writes its own copy
 *     back without this record. So close the app on every phone first, or
 *     reopen it right after, before editing anything.
 */
'use strict';

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({
  credential: admin.credential.cert(
      require(path.join(__dirname, 'service-account.json'))),
});
const db = admin.firestore();

const { resolveAccount } = require('./lib/fetchAccount');
const { habitDateKey, shiftKey } = require('./lib/day_rules');
const { keyAtOffset } = require('./lib/day_key');
const {
  parseSchedule,
  describeSchedule,
  historyWithPeriod,
  askedDaysIn,
} = require('./lib/schedule_history');

const args = process.argv.slice(2);
const arg = (name) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
};
const CONFIRM = args.includes('--confirm');

// Where a preset's per-person changes live on the user document
// (LocalStoreService.catalogOverridesKey in the app).
const OVERRIDES_FIELD = 'catalog_habit_overrides_v1';
const who = arg('user');
const habitId = arg('habit');
const changedKey = arg('changed');
const wasSpec = arg('was');

function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}

if (!who) {
  fail('Usage:\n' +
    '  node stamp_schedule_history.js --user=<email or uid>\n' +
    '  node stamp_schedule_history.js --user=<email or uid> --habit=<id> \\\n' +
    '       --changed=YYYY-MM-DD --was=<daily|daily:N|weekly:N|mon,thu> [--confirm]\n\n' +
    'The first lists the habits; the second is a dry run unless --confirm is passed.');
}

/** This Mac's own date: the tool is run from where the account lives. */
function todayKey() {
  const now = new Date();
  return keyAtOffset(now.getTime(), -now.getTimezoneOffset());
}

function scheduleOf(data) {
  if (!data) return null;
  if (!data.frequencyType) return null;
  return {
    frequencyType: data.frequencyType,
    frequencyTarget: Number(data.frequencyTarget) || 1,
    scheduledWeekdays: Array.isArray(data.scheduledWeekdays) ? data.scheduledWeekdays : [],
  };
}

function printHistory(history) {
  const list = Array.isArray(history) ? history : [];
  if (list.length === 0) {
    console.log('      history: none recorded');
    return;
  }
  for (const p of list) {
    console.log(`      history: ${describeSchedule(p)} until ${p.until}`);
  }
}

/** Every rule period each room recorded for this account's habits. */
async function roomRules(uid) {
  const out = {};
  const rooms = await db.collection('rooms').get();
  for (const room of rooms.docs) {
    const p = await room.ref.collection('participants').doc(uid).get();
    if (!p.exists) continue;
    const rules = (p.data() || {}).habitRules || {};
    for (const [id, periods] of Object.entries(rules)) {
      if (!Array.isArray(periods)) continue;
      for (const period of periods) {
        (out[id] = out[id] || []).push({
          room: room.id,
          roomName: (room.data() || {}).name || '',
          ...period,
        });
      }
    }
  }
  for (const list of Object.values(out)) {
    list.sort((a, b) => String(a.from).localeCompare(String(b.from)));
  }
  return out;
}

function printRoomRules(rules) {
  for (const r of rules || []) {
    console.log(`      room ${r.room} (${r.roomName}): ${describeSchedule(r)} from ${r.from}`);
  }
}

async function list(uid) {
  const user = (await db.collection('users').doc(uid).get()).data() || {};
  const rules = await roomRules(uid);
  const habits = await db.collection('users').doc(uid).collection('custom_habits').get();
  console.log(`\nCustom habits of ${uid}:`);
  for (const doc of habits.docs) {
    const d = doc.data();
    const state = d.archivedAt ? ` (paused ${habitDateKey(d.archivedAt)})` : '';
    console.log(`\n  ${doc.id}  ${d.name}${state}`);
    console.log(`      now: ${describeSchedule(scheduleOf(d))}, born ${habitDateKey(d.createdAt) || 'unknown'}`);
    printHistory(d.scheduleHistory);
    printRoomRules(rules[doc.id]);
  }
  const overrides = user[OVERRIDES_FIELD] || {};
  const presetIds = Object.keys(overrides);
  if (presetIds.length) {
    console.log('\nEdited presets (a preset nobody edited runs on its catalog schedule):');
    for (const id of presetIds) {
      const o = overrides[id] || {};
      const now = scheduleOf(o);
      console.log(`\n  ${id}  ${o.name || ''}`);
      console.log(`      now: ${now ? describeSchedule(now) : 'the catalog schedule'}`);
      printHistory(o.scheduleHistory);
      printRoomRules(rules[id]);
    }
  }
  console.log('\nTo stamp one: --habit=<id> --changed=<first day of the schedule it has now> ' +
    '--was=<the schedule before>\n');
}

async function stamp(uid) {
  let was;
  try {
    was = parseSchedule(wasSpec);
  } catch (e) {
    fail(`--was: ${e.message}`);
  }
  const today = todayKey();
  const userRef = db.collection('users').doc(uid);
  const habitRef = userRef.collection('custom_habits').doc(habitId);
  const habitSnap = await habitRef.get();
  const isCustom = habitSnap.exists;

  let current;
  let history;
  let bornKey;
  let name;
  if (isCustom) {
    const d = habitSnap.data();
    current = scheduleOf(d);
    history = d.scheduleHistory || [];
    bornKey = habitDateKey(d.createdAt);
    name = d.name;
  } else {
    const user = (await userRef.get()).data() || {};
    const o = (user[OVERRIDES_FIELD] || {})[habitId];
    const activated = (user.activeCatalogActivatedAt || {})[habitId];
    const isPreset = o || (Array.isArray(user.activeCatalogIds) &&
      user.activeCatalogIds.includes(habitId));
    if (!isPreset) {
      fail(`No custom habit and no preset with id "${habitId}" on this account. ` +
        'Run without --habit to list them.');
    }
    current = scheduleOf(o); // null: still the catalog schedule, unknown here
    history = (o && o.scheduleHistory) || [];
    bornKey = activated ? habitDateKey(activated) : null;
    name = (o && o.name) || habitId;
  }

  let next;
  try {
    next = historyWithPeriod({ history, current, was, changedKey, bornKey, todayKey: today });
  } catch (e) {
    fail(`Refused: ${e.message}`);
  }
  const period = next[next.length - 1];
  // The first day the new period covers: the day after the last recorded
  // one, or the habit's birth. A habit written before birth dates were
  // stored has none, and its period reaches back to the start; the preview
  // then shows the last eight weeks of it, which is what the screens show.
  const first = history.length
    ? shiftKey(history[history.length - 1].until, 1)
    : (bornKey || shiftKey(period.until, -55));

  console.log(`\n${name} (${isCustom ? 'custom habit' : 'preset'} ${habitId})`);
  console.log(`  now:    ${current ? describeSchedule(current) : 'the catalog schedule'}, ` +
    `from ${changedKey}`);
  console.log(`  before: ${describeSchedule(was)}, until ${period.until}` +
    (!history.length && !bornKey ? ' (no birth date on record, so from the start)' : ''));
  {
    const asked = askedDaysIn({ fromKey: first, untilKey: period.until, schedule: was });
    const askedNow = current
      ? askedDaysIn({ fromKey: first, untilKey: period.until, schedule: current })
      : null;
    if (asked && askedNow) {
      const nowSet = new Set(askedNow);
      const thenSet = new Set(asked);
      const rest = askedNow.filter((k) => !thenSet.has(k));
      const owed = asked.filter((k) => !nowSet.has(k));
      console.log(`  ${first} to ${period.until}: ${rest.length} day(s) go back to rest, ` +
        `${owed.length} become owed again.`);
      if (rest.length) console.log(`    back to rest: ${rest.join(' ')}`);
      if (owed.length) console.log(`    owed again:   ${owed.join(' ')}`);
    } else {
      console.log(`  ${first} to ${period.until}: judged by the week (a quota), ` +
        'so the app works out which days were owed from the sessions themselves.');
    }
  }
  console.log(`  history to write: ${JSON.stringify(next)}`);

  if (!CONFIRM) {
    console.log('\nDRY RUN. Nothing was written. Add --confirm to apply.\n');
    return;
  }

  await db.runTransaction(async (tx) => {
    if (isCustom) {
      const fresh = await tx.get(habitRef);
      const d = fresh.data() || {};
      const freshHistory = d.scheduleHistory || [];
      if (JSON.stringify(scheduleOf(d)) !== JSON.stringify(current) ||
          JSON.stringify(freshHistory) !== JSON.stringify(history)) {
        throw new Error('the habit changed since it was read; run again');
      }
      tx.update(habitRef, { scheduleHistory: next });
    } else {
      const fresh = await tx.get(userRef);
      const o = ((fresh.data() || {})[OVERRIDES_FIELD] || {})[habitId];
      const freshHistory = (o && o.scheduleHistory) || [];
      if (JSON.stringify(scheduleOf(o)) !== JSON.stringify(current) ||
          JSON.stringify(freshHistory) !== JSON.stringify(history)) {
        throw new Error('the preset changed since it was read; run again');
      }
      tx.update(userRef,
          new admin.firestore.FieldPath(OVERRIDES_FIELD, habitId, 'scheduleHistory'), next);
    }
  });
  console.log('\nWritten. Reopen GrowDaily on every phone signed in to this account ' +
    'before editing any habit, so the app reads the new record.\n');
}

(async () => {
  let uid;
  try {
    ({ uid } = await resolveAccount(who));
  } catch (e) {
    fail(`No account found for "${who}": ${e.message}`);
  }
  if (!habitId) {
    await list(uid);
  } else {
    if (!changedKey || !wasSpec) fail('--habit needs --changed=YYYY-MM-DD and --was=<schedule>.');
    await stamp(uid);
  }
  process.exit(0);
})().catch((e) => fail(e.stack || String(e)));
