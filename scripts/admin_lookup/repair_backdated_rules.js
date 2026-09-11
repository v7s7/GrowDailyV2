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
 * Date keys. Every date compared here is the day on the MEMBER'S PHONE,
 * because that is the calendar the app stamped the rules on: planFloorFor
 * runs on the member's phone and keys a slot's addedAt from the local
 * DateTime that Timestamp.toDate() gives (rooms_notifier.dart:3279-3290,
 * toDateKey at datetime_ext.dart:34-37). This script used to key every
 * Timestamp with toISOString(), a UTC date, which is a day early for
 * anything stamped between midnight and 03:00 in Bahrain. ELQVF8 slot 2 was
 * added at 2026-09-08T21:48:29.651Z, 00:48 on 2026-09-09 on Hoor's +180
 * phone, and the UTC key hid her slot from this report entirely. The offset
 * is users/{uid}.tzOffsetMinutes. A member without it is keyed at +180, the
 * line says ASSUMED, and no patch is built or written for them. A createdAt
 * string with no zone is already the phone's date and is read as written,
 * never through new Date. Every line prints the offset it used, and an
 * addedAt whose phone date and UTC date differ also prints its local time
 * and its UTC date, because that is where the two calendars part. The
 * keying lives in lib/day_key.js and the decision in lib/backdated_rules.js,
 * both tested.
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

const { keyAtOffset, localMinuteOfDay, offsetOf } = require('./lib/day_key');
const { proposeFor, looksLikeUtcKeyedStamp } = require('./lib/backdated_rules');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const code = args.find(a => !a.startsWith('--'));

const fmtOffset = m => `${m < 0 ? '' : '+'}${m}`;
const fmtMinute = m =>
  `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

(async () => {
  const rooms = code
    ? [await db.collection('rooms').doc(code).get()]
    : (await db.collection('rooms').get()).docs;

  // users/{uid}.tzOffsetMinutes, read once per member however many rooms
  // they are in.
  const tzCache = new Map();
  async function tzOf(uid) {
    if (tzCache.has(uid)) return tzCache.get(uid);
    const u = await db.collection('users').doc(uid).get();
    const tz = offsetOf(u.exists ? u.data() : null);
    tzCache.set(uid, tz);
    return tz;
  }

  // createdAt is a Timestamp on some documents and an ISO STRING on
  // others, which is why the first pass of this script found nothing at
  // all: it only understood Timestamps and silently skipped every habit
  // stored the other way. The RAW value is cached and keyed on the member's
  // calendar where it is used (storedDateKey, inside proposeFor), because
  // the same instant is a different day on a different phone.
  const habitCache = new Map();
  async function rawCreatedAtOf(uid, habitId) {
    const k = `${uid}/${habitId}`;
    if (habitCache.has(k)) return habitCache.get(k);
    const d = await db.collection('users').doc(uid)
      .collection('custom_habits').doc(habitId).get();
    const raw = d.exists ? d.data().createdAt : null;
    habitCache.set(k, raw);
    return raw;
  }

  let findings = 0;
  for (const room of rooms) {
    if (!room.exists) { console.log(`room ${code} not found`); continue; }
    const r = room.data();
    if (r.habitMode !== 'shared') continue;
    if (!r.startDate || typeof r.startDate.toDate !== 'function') continue;
    const parts = await room.ref.collection('participants').get();
    for (const p of parts.docs) {
      const v = p.data();
      const rules = v.habitRules || {};
      const tz = await tzOf(p.id);
      const createdAtById = new Map();
      for (const [habitId, list] of Object.entries(rules)) {
        if (!Array.isArray(list) || !list.length) continue;
        createdAtById.set(habitId, await rawCreatedAtOf(p.id, habitId));
      }

      // broken is judged from the STORED dailyDoneCount. Read the comment
      // above that check in lib/backdated_rules.js before changing it.
      const { proposals, broken, patch } = proposeFor({
        room: r,
        participant: v,
        offsetMinutes: tz.minutes,
        createdAtById,
        offsetAssumed: tz.assumed,
      });
      findings += proposals.length;
      const tzLabel = `tz ${fmtOffset(tz.minutes)}${tz.assumed ? ' ASSUMED' : ''}`;

      for (const pr of proposals) {
        console.log(
          `${broken.length ? 'UNSAFE' : ' SAFE '} ${room.id}  ` +
          `${(v.displayName || p.id).padEnd(18)} ${pr.habitId.slice(0, 8)}  ` +
          `from ${pr.minFrom} -> ${pr.proposed}   (${pr.why})   ${tzLabel}`
        );
        // An addedAt whose phone date and UTC date differ is exactly where the
        // two calendars part, whatever the member's offset (for +240 that is
        // 00:00 to 04:00 local), so it gets a line of its own.
        if (pr.addedAtMs != null && keyAtOffset(pr.addedAtMs, 0) !== pr.addedAt) {
          const minute = localMinuteOfDay(pr.addedAtMs, tz.minutes);
          console.log(
            `         addedAt ${pr.addedAt} ${fmtMinute(minute)} local, ` +
            `UTC date ${keyAtOffset(pr.addedAtMs, 0)}`
          );
        }
        if (tz.assumed) console.log('         offset not recorded: dry run only');
        if (broken.length) {
          const b = broken[0];
          console.log(`         !! would break ${broken.length} day(s), e.g. ${b.day}: ${b.done} done vs ${b.asked} asked`);
          if (looksLikeUtcKeyedStamp(pr, broken)) {
            console.log('         the refused day is the UTC stamp day and its count is what that stamp asked: the old UTC keying, not evidence against the date (still refused)');
          }
        }
      }
      // proposeFor builds no patch for an UNSAFE member or an assumed
      // offset. The offset is checked again here so no later change there
      // can write on a guessed calendar.
      if (APPLY && !tz.assumed && Object.keys(patch).length) {
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
