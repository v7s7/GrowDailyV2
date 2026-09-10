#!/usr/bin/env node
/**
 * Who cleared a square.
 *
 * A stored square records the VALUE and never the writer, which is why
 * "the previous day resets after 00:00" could not be answered from noor's
 * account on 2026-09-10: her walk was completed at 15:38, paid 20 XP, then
 * reversed, and nothing said by what. The app now writes a row to
 * users/{uid}/square_audit every time a square LOSES credit (cleared,
 * downgraded, or turned red), carrying the source that wrote it.
 *
 * The column to read is dateKey vs appDay. A square for the 9th cleared
 * while the app believed it was the 10th IS "the previous day reset after
 * midnight", stated rather than inferred.
 *
 * Usage:
 *   node square_trail.js someone@example.com [--habit <id>] [--limit 60]
 */
const admin = require('firebase-admin');
const path = require('path');

const args = process.argv.slice(2);
const who = args.find(a => !a.startsWith('--'));
const flag = name => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? null : args[i + 1];
};
if (!who) {
  console.error('\nUsage: node square_trail.js <email|uid> [--habit <id>] [--limit 60]\n');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, 'service-account.json'))),
});
const db = admin.firestore();

(async () => {
  const uid = who.includes('@') ? (await admin.auth().getUserByEmail(who)).uid : who;
  const limit = Number(flag('limit') || 60);
  const habit = flag('habit');

  const names = new Map();
  const habits = await db.collection('users').doc(uid).collection('custom_habits').get();
  habits.forEach(d => names.set(d.id, d.data().name || d.id));

  let q = db.collection('users').doc(uid).collection('square_audit');
  if (habit) q = q.where('habitId', '==', habit);
  const snap = await q.get();

  const rows = snap.docs.map(d => d.data());
  // Sorted client-side so no composite index is needed for a one-off read.
  rows.sort((a, b) => String(b.localAt || '').localeCompare(String(a.localAt || '')));

  if (!rows.length) {
    console.log(`\nNo square_audit rows for ${uid}.`);
    console.log('Either nothing has lost credit since the trail shipped, or the');
    console.log('device is still on an older build.\n');
    process.exit(0);
  }

  console.log(`\n${rows.length} row(s) for ${uid}, newest first:\n`);
  const pad = (s, n) => String(s ?? '').padEnd(n);
  console.log(pad('WHEN (device)', 22), pad('DAY CHANGED', 12), pad('APP THOUGHT', 12),
    pad('FROM→TO', 18), pad('SOURCE', 15), 'HABIT');
  console.log('-'.repeat(110));
  for (const r of rows.slice(0, limit)) {
    const crossed = r.dateKey !== r.appDayKey ? ' *' : '';
    console.log(
      pad(r.localAt, 22),
      pad(r.dateKey, 12),
      pad((r.appDayKey || '') + crossed, 12),
      pad(`${r.from} → ${r.to}`, 18),
      pad(r.source, 15),
      names.get(r.habitId) || r.habitId,
    );
  }
  console.log('\n  * = a PAST day was changed while the app was on a later day.\n');
  process.exit(0);
})().catch(e => {
  console.error('\nERROR:', e.message, '\n');
  process.exit(1);
});
