'use strict';
const path = require('path');
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname,'service-account.json'))) });
const db = admin.firestore();
const ts = v => v && v._seconds ? new Date(v._seconds*1000).toISOString() : v;

(async () => {
  const code = 'ELQVF8';
  const rd = await db.collection('rooms').doc(code).get();
  const r = rd.data();
  console.log('ROOM', code, r.name, 'mode=', r.habitMode);
  console.log('start=', ts(r.startDate), 'end=', ts(r.endDate), 'status=', r.status);
  console.log('pausedSpans=', JSON.stringify(r.pausedSpans));
  console.log('sharedHabits=', JSON.stringify(r.sharedHabits, null, 1));
  const ps = await db.collection('rooms').doc(code).collection('participants').get();
  console.log('\nPARTICIPANTS:', ps.size);
  for (const p of ps.docs) {
    const d = p.data();
    console.log('\n==== uid', p.id, '|', d.displayName || d.name);
    console.log('  linkedHabitIds  :', JSON.stringify(d.linkedHabitIds));
    console.log('  linkedHabitNames:', JSON.stringify(d.linkedHabitNames));
    console.log('  joinedAt        :', ts(d.joinedAt));
    console.log('  lastSyncedDay   :', d.lastSyncedDay, ' lastSyncedAt:', ts(d.lastSyncedAt));
    console.log('  habitRules      :', JSON.stringify(d.habitRules));
    console.log('  quotaOkWeeks    :', JSON.stringify(d.quotaOkWeeks));
    console.log('  standDownDays   :', JSON.stringify(d.standDownDays));
    console.log('  dailyDoneCount  :', JSON.stringify(d.dailyDoneCount));
    console.log('  dailySchedCount :', JSON.stringify(d.dailyScheduledCount));
    console.log('  dailyRestedCount:', JSON.stringify(d.dailyRestedCount));
    console.log('  dailyPartialCnt :', JSON.stringify(d.dailyPartialCount));
    console.log('  leftAt          :', ts(d.leftAt), 'awaySpans=', JSON.stringify(d.awaySpans));
  }
})().then(()=>process.exit(0)).catch(e=>{console.error(e);process.exit(1);});
