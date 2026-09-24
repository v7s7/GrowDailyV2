'use strict';

/**
 * An in-memory stand-in for the parts of Firestore the Sale and Creators
 * pages use, so their writes are tested without the real project.
 *
 * What is modelled because the code depends on it: a transaction's writes
 * land together after its reads, or not at all when it throws; set()
 * without merge replaces the whole document; create() refuses a document
 * that exists; serverTimestamp() becomes the fake clock's time; where()
 * compares numbers and timestamps; count() counts.
 *
 * Not a test file itself (no .test.js), so `npm test` does not run it.
 */

class FakeTimestamp {
  constructor(ms) {
    this.ms = ms;
  }

  static fromMillis(ms) {
    return new FakeTimestamp(ms);
  }

  toMillis() {
    return this.ms;
  }

  toDate() {
    return new Date(this.ms);
  }
}

const SERVER_TIME = { __serverTimestamp: true };
const FieldValue = { serverTimestamp: () => SERVER_TIME };
const Timestamp = FakeTimestamp;

function copy(value, nowMs) {
  if (value === SERVER_TIME || (value && value.__serverTimestamp)) return new FakeTimestamp(nowMs);
  if (value instanceof FakeTimestamp) return new FakeTimestamp(value.ms);
  if (Array.isArray(value)) return value.map((v) => copy(v, nowMs));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = copy(v, nowMs);
    return out;
  }
  return value;
}

function comparable(v) {
  if (v instanceof FakeTimestamp) return v.ms;
  return v;
}

function matches(data, filters) {
  return filters.every(({ field, op, value }) => {
    const a = comparable(data[field]);
    const b = comparable(value);
    if (a === undefined || a === null) return false;
    switch (op) {
      case '==': return a === b;
      case '>': return a > b;
      case '>=': return a >= b;
      case '<': return a < b;
      case '<=': return a <= b;
      default: throw new Error('fake firestore: unsupported op ' + op);
    }
  });
}

function fakeDb({ nowMs = Date.UTC(2026, 8, 22, 9, 0) } = {}) {
  const docs = new Map();
  let nextId = 1;
  const state = { nowMs, writes: 0, transactions: 0 };

  function snapOf(path) {
    const data = docs.get(path);
    return { id: path.split('/').pop(), exists: data !== undefined, data: () => (data === undefined ? undefined : copy(data, state.nowMs)) };
  }

  function docRef(path) {
    return {
      path,
      id: path.split('/').pop(),
      get: async () => snapOf(path),
      set: async (data) => {
        docs.set(path, copy(data, state.nowMs));
        state.writes += 1;
      },
      update: async (patch) => {
        if (!docs.has(path)) throw Object.assign(new Error('NOT_FOUND: ' + path), { code: 5 });
        docs.set(path, { ...docs.get(path), ...copy(patch, state.nowMs) });
        state.writes += 1;
      },
      create: async (data) => {
        if (docs.has(path)) throw Object.assign(new Error('ALREADY_EXISTS: ' + path), { code: 6 });
        docs.set(path, copy(data, state.nowMs));
        state.writes += 1;
      },
    };
  }

  function query(collection, filters) {
    const run = () => [...docs.keys()]
      .filter((p) => p.startsWith(collection + '/') && p.split('/').length === collection.split('/').length + 1)
      .sort()
      .filter((p) => matches(docs.get(p), filters))
      .map((p) => ({ id: p.split('/').pop(), exists: true, data: () => copy(docs.get(p), state.nowMs) }));
    return {
      __query: true,
      run,
      where: (field, op, value) => query(collection, filters.concat([{ field, op, value }])),
      get: async () => {
        const list = run();
        return { docs: list, size: list.length, empty: list.length === 0 };
      },
      count: () => ({ get: async () => ({ data: () => ({ count: run().length }) }) }),
    };
  }

  const db = {
    docs,
    state,
    doc: (path) => docRef(path),
    collection: (name) => ({
      ...query(name, []),
      doc: (id) => docRef(name + '/' + (id || 'auto' + String(nextId++).padStart(4, '0'))),
    }),
    async runTransaction(fn) {
      state.transactions += 1;
      const writes = [];
      const tx = {
        get: async (target) => {
          if (target && target.__query) {
            const list = target.run();
            return { docs: list, size: list.length, empty: list.length === 0 };
          }
          return snapOf(target.path);
        },
        set: (ref, data) => { writes.push(['set', ref.path, data]); },
        update: (ref, patch) => { writes.push(['update', ref.path, patch]); },
        create: (ref, data) => { writes.push(['create', ref.path, data]); },
      };
      const result = await fn(tx);
      for (const [kind, path] of writes) {
        if (kind === 'create' && docs.has(path)) throw Object.assign(new Error('ALREADY_EXISTS: ' + path), { code: 6 });
        if (kind === 'update' && !docs.has(path)) throw Object.assign(new Error('NOT_FOUND: ' + path), { code: 5 });
      }
      for (const [kind, path, data] of writes) {
        if (kind === 'update') docs.set(path, { ...docs.get(path), ...copy(data, state.nowMs) });
        else docs.set(path, copy(data, state.nowMs));
        state.writes += 1;
      }
      return result;
    },
  };
  return db;
}

module.exports = { fakeDb, FakeTimestamp, Timestamp, FieldValue };
