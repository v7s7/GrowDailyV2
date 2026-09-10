const admin = require('firebase-admin');
const sa = require('./service-account.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const d = (t) => {
  if (!t) return null;
  if (typeof t.toDate === 'function') return t.toDate().toISOString();
  if (t instanceof Date) return t.toISOString();
  return String(t);
};
const key = (t) => {
  if (!t) return null;
  const dt = typeof t.toDate === 'function' ? t.toDate() : t;
  const p = (n) => String(n).padStart(2, '0');
  return `${dt.getFullYear()}-${p(dt.getMonth() + 1)}-${p(dt.getDate())}`;
};

(async () => {
  const snap = await db.collection('rooms').get();
  const out = [];
  for (const doc of snap.docs) {
    const r = doc.data();
    const parts = await doc.ref.collection('participants').get();
    out.push({
      code: doc.id,
      raw: r,
      keys: Object.keys(r).sort(),
      startKey: key(r.startDate),
      endKey: key(r.endDate),
      createdKey: key(r.createdAt),
      participants: parts.docs.map((p) => ({
        uid: p.id,
        data: p.data(),
      })),
    });
  }
  console.log(JSON.stringify(out, (k, v) => {
    if (v && typeof v === 'object' && v._seconds !== undefined) {
      return new Date(v._seconds * 1000).toISOString();
    }
    return v;
  }, 2));
})().catch((e) => { console.error(e); process.exit(1); });
