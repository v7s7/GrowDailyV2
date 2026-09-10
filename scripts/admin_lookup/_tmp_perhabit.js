const admin = require('firebase-admin');
const sa = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

function shape(v, depth) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return `array[${v.length}]` + (v.length ? ` e.g. ${JSON.stringify(v[0]).slice(0,120)}` : '');
  if (v && v.constructor && v.constructor.name === 'Timestamp') return 'Timestamp';
  if (typeof v === 'object') {
    const ks = Object.keys(v);
    return `map{${ks.length}} keys: ${ks.slice(0,6).join(',')}${ks.length>6?'…':''}` +
      (ks.length ? ` | sample ${JSON.stringify({[ks[0]]: v[ks[0]]}).slice(0,160)}` : '');
  }
  return `${typeof v} = ${JSON.stringify(v).slice(0,120)}`;
}

(async () => {
  const rooms = await db.collection('rooms').get();
  console.log('=== ROOMS:', rooms.size, '===');
  const summary = [];
  for (const r of rooms.docs) {
    const d = r.data();
    const parts = await r.ref.collection('participants').get();
    summary.push({ code: r.id, name: d.name, mode: d.habitMode, status: d.status, members: parts.size,
      sharedHabits: (d.sharedHabits||[]).map(h=>h.name) });
  }
  console.log(JSON.stringify(summary, null, 1));

  // Pick the room with most participants and shared mode
  const pick = rooms.docs.slice().sort((a,b)=> (b.data().memberCount||0)-(a.data().memberCount||0))[0];
  console.log('\n=== FULL KEY SET of participant docs in room', pick.id, '===');
  const parts = await pick.ref.collection('participants').get();
  const allKeys = new Set();
  for (const p of parts.docs) Object.keys(p.data()).forEach(k=>allKeys.add(k));
  console.log('UNION OF ALL PARTICIPANT KEYS:', JSON.stringify([...allKeys].sort(), null, 1));
  const p0 = parts.docs[0];
  console.log('\n--- participant', p0.id, '---');
  const d0 = p0.data();
  for (const k of Object.keys(d0).sort()) console.log(`  ${k}: ${shape(d0[k])}`);
  process.exit(0);
})().catch(e=>{console.error(e);process.exit(1);});
