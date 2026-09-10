const admin = require('firebase-admin');
const sa = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const UID = '5rLsgWgriLa7qaRDeZ3wdPfHgQl2';

(async () => {
  // 2. habit_history shape
  const hist = await db.collection('users').doc(UID).collection('habit_history').limit(5).get();
  console.log('=== habit_history docs for', UID, ':', hist.size, '(showing up to 5) ===');
  for (const h of hist.docs) {
    const d = h.data();
    console.log('\n--- habit_history/' + h.id + ' ---');
    console.log('  top-level keys:', Object.keys(d));
    for (const k of Object.keys(d)) {
      const v = d[k];
      if (v && typeof v === 'object' && !Array.isArray(v)) {
        const ks = Object.keys(v).sort();
        console.log(`  ${k}: map with ${ks.length} entries`);
        const slice = ks.slice(-12);
        console.log('    last 12:', JSON.stringify(Object.fromEntries(slice.map(x=>[x,v[x]]))));
      } else {
        console.log(`  ${k}:`, JSON.stringify(v).slice(0,200));
      }
    }
  }

  // 3. daily/{dateKey}.squareStates
  console.log('\n\n=== daily docs (last 4) ===');
  const daily = await db.collection('users').doc(UID).collection('daily')
      .orderBy(admin.firestore.FieldPath.documentId(), 'desc').limit(4).get();
  for (const dd of daily.docs) {
    const d = dd.data();
    console.log('\n--- daily/' + dd.id + ' ---');
    console.log('  keys:', Object.keys(d).sort().join(', '));
    for (const k of ['squareStates','habitCompletions','habitTargets','squareNotes']) {
      if (d[k] !== undefined) console.log(`  ${k}:`, JSON.stringify(d[k]).slice(0,400));
    }
  }
  process.exit(0);
})().catch(e=>{console.error(e);process.exit(1);});
