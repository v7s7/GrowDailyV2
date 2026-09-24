'use strict';

/**
 * The App Store Connect client (lib/asc_client.js): the ES256 token, which
 * settings are missing, and what one request sends and gets back.
 *
 * Every test signs with a throwaway key made here and answers with a fake
 * fetch. Nothing reads the real .p8 and nothing reaches Apple.
 *
 * Run with `npm test` in scripts/admin_lookup.
 */

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');

const Asc = require('../lib/asc_client');

const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const ENV = { ASC_KEY_ID: 'KEY123', ASC_ISSUER_ID: 'issuer-uuid' };

function decodePart(part) {
  return JSON.parse(Buffer.from(part.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
}

function fakeFetch(answers) {
  const calls = [];
  const fn = async (url, options) => {
    calls.push({ url, options });
    const next = answers.length ? answers.shift() : { status: 200, body: {} };
    const text = next.raw !== undefined ? next.raw : JSON.stringify(next.body);
    return { ok: next.status >= 200 && next.status < 300, status: next.status, text: async () => text };
  };
  fn.calls = calls;
  return fn;
}

function client(fetchImpl, extra = {}) {
  return Asc.createAscClient({
    env: ENV,
    fetchImpl,
    readKey: () => privateKey,
    exists: () => true,
    home: '/Users/test',
    now: () => Date.UTC(2026, 8, 22, 9, 0),
    ...extra,
  });
}

test('the token is ES256 with the key id, issuer, audience and a 15-minute life', () => {
  const nowMs = Date.UTC(2026, 8, 22, 9, 0);
  const token = Asc.makeToken({ keyId: 'KEY123', issuerId: 'issuer-uuid', privateKey, nowMs });
  const [h, c, s] = token.split('.');
  assert.deepStrictEqual(decodePart(h), { alg: 'ES256', kid: 'KEY123', typ: 'JWT' });
  const iat = Math.floor(nowMs / 1000);
  assert.deepStrictEqual(decodePart(c), { iss: 'issuer-uuid', iat, exp: iat + 900, aud: 'appstoreconnect-v1' });
  const signature = Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  assert.strictEqual(signature.length, 64, 'raw r||s, not DER');
  const ok = crypto.verify('sha256', Buffer.from(h + '.' + c), { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature);
  assert.strictEqual(ok, true);
  assert.ok(!/[=+/]/.test(token), 'base64url, unpadded');
});

test('missing settings are named one by one, and the key file is only looked for', () => {
  const none = Asc.ascConfig({}, { exists: () => true, home: '/Users/test' });
  assert.strictEqual(none.ok, false);
  assert.deepStrictEqual(none.missing, ['ASC_KEY_ID is not set', 'ASC_ISSUER_ID is not set']);
  const noIssuer = Asc.ascConfig({ ASC_KEY_ID: 'KEY123' }, { exists: () => true, home: '/Users/test' });
  assert.deepStrictEqual(noIssuer.missing, ['ASC_ISSUER_ID is not set']);
  assert.strictEqual(noIssuer.keyPath, '/Users/test/.appstoreconnect/private_keys/AuthKey_KEY123.p8');
  const noFile = Asc.ascConfig(ENV, { exists: () => false, home: '/Users/test' });
  assert.deepStrictEqual(noFile.missing, ['No key file at /Users/test/.appstoreconnect/private_keys/AuthKey_KEY123.p8']);
  assert.strictEqual(Asc.ascConfig(ENV, { exists: () => true, home: '/Users/test' }).ok, true);
});

test('with a setting missing, no request is signed or sent', async () => {
  const fetchImpl = fakeFetch([]);
  let read = 0;
  const asc = Asc.createAscClient({ env: { ASC_KEY_ID: 'KEY123' }, fetchImpl, readKey: () => { read += 1; return privateKey; }, exists: () => true });
  await assert.rejects(() => asc.get('/v2/inAppPurchases/1'), (e) => e instanceof Asc.AscConfigError && /ASC_ISSUER_ID/.test(e.message));
  assert.strictEqual(fetchImpl.calls.length, 0);
  assert.strictEqual(read, 0, 'the key is not even read');
});

test('a GET goes to the versioned path with the query and a bearer token', async () => {
  const fetchImpl = fakeFetch([{ status: 200, body: { data: [{ id: 'x' }] } }]);
  const asc = client(fetchImpl);
  const res = await asc.get('/v2/inAppPurchases/6814748258/pricePoints', { 'filter[territory]': 'USA', limit: 8000 });
  assert.deepStrictEqual(res, { data: [{ id: 'x' }] });
  const call = fetchImpl.calls[0];
  assert.strictEqual(call.url, 'https://api.appstoreconnect.apple.com/v2/inAppPurchases/6814748258/pricePoints?filter[territory]=USA&limit=8000');
  assert.strictEqual(call.options.method, 'GET');
  assert.match(call.options.headers.Authorization, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.strictEqual(call.options.body, undefined);
});

test('a POST sends JSON', async () => {
  const fetchImpl = fakeFetch([{ status: 201, body: { data: { id: 'OFFER1' } } }]);
  const res = await client(fetchImpl).post('/v1/inAppPurchaseOfferCodes', { data: { type: 'inAppPurchaseOfferCodes' } });
  assert.strictEqual(res.data.id, 'OFFER1');
  const call = fetchImpl.calls[0];
  assert.strictEqual(call.options.method, 'POST');
  assert.strictEqual(call.options.headers['Content-Type'], 'application/json');
  assert.deepStrictEqual(JSON.parse(call.options.body), { data: { type: 'inAppPurchaseOfferCodes' } });
});

test('a path without its version is refused before anything is sent', async () => {
  const fetchImpl = fakeFetch([]);
  await assert.rejects(() => client(fetchImpl).get('/inAppPurchases/1'), /starts with its version/);
  assert.strictEqual(fetchImpl.calls.length, 0);
});

test('Apple\'s refusal comes back in Apple\'s words, and never quotes the token', async () => {
  const fetchImpl = fakeFetch([{
    status: 409,
    body: { errors: [{ status: '409', code: 'ENTITY_ERROR.ATTRIBUTE.INVALID', title: 'An attribute value is invalid.', detail: 'The custom code already exists.', source: { pointer: '/data/attributes/customCode' } }] },
  }]);
  let error;
  try {
    await client(fetchImpl).post('/v1/inAppPurchaseOfferCodeCustomCodes', {});
  } catch (e) {
    error = e;
  }
  assert.ok(error instanceof Asc.AscApiError);
  assert.strictEqual(error.status, 409);
  assert.strictEqual(error.message, 'App Store Connect answered 409: ENTITY_ERROR.ATTRIBUTE.INVALID: The custom code already exists. (/data/attributes/customCode)');
  const token = fetchImpl.calls[0].options.headers.Authorization.slice('Bearer '.length);
  assert.ok(!error.message.includes(token));
});

test('a network failure and a non-JSON answer are both readable errors', async () => {
  const down = Asc.createAscClient({ env: ENV, fetchImpl: async () => { throw new Error('ENOTFOUND'); }, readKey: () => privateKey, exists: () => true });
  await assert.rejects(() => down.get('/v1/territories'), /Could not reach App Store Connect: ENOTFOUND/);
  const html = client(fakeFetch([{ status: 502, raw: '<html>Bad gateway</html>' }]));
  await assert.rejects(() => html.get('/v1/territories'), /App Store Connect answered 502\./);
});

test('getAll follows Apple\'s next links and gathers data and included', async () => {
  const fetchImpl = fakeFetch([
    { status: 200, body: { data: [{ id: 'a' }], included: [{ id: 'T1' }], links: { next: 'https://api.appstoreconnect.apple.com/v1/inAppPurchasePricePoints/P/equalizations?cursor=Mg&limit=2' } } },
    { status: 200, body: { data: [{ id: 'b' }], included: [{ id: 'T2' }], links: {} } },
  ]);
  const all = await client(fetchImpl).getAll('/v1/inAppPurchasePricePoints/P/equalizations', { limit: 2 });
  assert.deepStrictEqual(all.data.map((d) => d.id), ['a', 'b']);
  assert.deepStrictEqual(all.included.map((d) => d.id), ['T1', 'T2']);
  assert.strictEqual(fetchImpl.calls[1].url, 'https://api.appstoreconnect.apple.com/v1/inAppPurchasePricePoints/P/equalizations?cursor=Mg&limit=2');
});

test('the client module never prints: no console calls in it', () => {
  const src = require('node:fs').readFileSync(require.resolve('../lib/asc_client.js'), 'utf8');
  assert.ok(!/console\./.test(src));
});
