'use strict';

/**
 * A small App Store Connect API client: the signed token, one request, and
 * the answer or a readable error. Node's own crypto only, no JWT package.
 *
 * Who uses it: the Creators page, to read Lifetime's price points and to
 * make one Apple offer code per creator (lib/creators.js builds the request
 * bodies; lib/creators_admin.js decides when to send them).
 *
 * The key. App Store Connect signs in with a private key file Aziz keeps at
 * ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. It is read at
 * request time, used to sign one token, and dropped. It is never logged,
 * printed, copied, cached or returned, and neither is the token it signs:
 * a token is a password for fifteen minutes. Nothing in an error message
 * here quotes either of them.
 *
 * Settings, from the environment:
 *   ASC_KEY_ID     the key's ID (also names the .p8 file)
 *   ASC_ISSUER_ID  the issuer ID from App Store Connect, Users and Access,
 *                  Integrations
 *   ASC_KEY_PATH   optional, a different path for the .p8 file
 */

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ASC_HOST = 'https://api.appstoreconnect.apple.com';
/** Apple refuses a token that lives longer than 20 minutes. */
const TOKEN_SECONDS = 900;
const AUDIENCE = 'appstoreconnect-v1';

/** A setting is missing, so no request can be signed. Shown as it is. */
class AscConfigError extends Error {
  constructor(message, missing) {
    super(message);
    this.missing = missing || [];
  }
}

/** Apple answered, and the answer was not a success. */
class AscApiError extends Error {
  constructor(message, status, errors) {
    super(message);
    this.status = status;
    this.errors = errors || [];
  }
}

function defaultKeyPath(keyId, home = os.homedir()) {
  return path.join(home, '.appstoreconnect', 'private_keys', 'AuthKey_' + keyId + '.p8');
}

/**
 * Which settings are there, and which are missing. Looks for the key file
 * without opening it. [missing] names each gap the way the page shows it.
 */
function ascConfig(env = process.env, { exists = fs.existsSync, home = os.homedir() } = {}) {
  const keyId = String(env.ASC_KEY_ID || '').trim();
  const issuerId = String(env.ASC_ISSUER_ID || '').trim();
  const missing = [];
  if (!keyId) missing.push('ASC_KEY_ID is not set');
  if (!issuerId) missing.push('ASC_ISSUER_ID is not set');
  let keyPath = String(env.ASC_KEY_PATH || '').trim();
  if (!keyPath && keyId) keyPath = defaultKeyPath(keyId, home);
  if (keyPath && !exists(keyPath)) missing.push('No key file at ' + keyPath);
  return { ok: missing.length === 0, keyId, issuerId, keyPath, missing };
}

function base64url(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(String(input), 'utf8');
  return buf.toString('base64').replace(/=+$/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

/**
 * One signed ES256 token. [privateKey] is a KeyObject (or anything
 * crypto.sign takes as a key). The signature is the raw 64-byte r||s form
 * JWT wants, which is what dsaEncoding 'ieee-p1363' gives; Node's default
 * DER form is what makes a hand-made ES256 token fail with 401.
 */
function makeToken({ keyId, issuerId, privateKey, nowMs = Date.now() }) {
  const iat = Math.floor(nowMs / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const claims = { iss: issuerId, iat, exp: iat + TOKEN_SECONDS, aud: AUDIENCE };
  const signingInput = base64url(JSON.stringify(header)) + '.' + base64url(JSON.stringify(claims));
  const signature = crypto.sign('sha256', Buffer.from(signingInput, 'utf8'), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  return signingInput + '.' + base64url(signature);
}

/** Reads the .p8 and turns it into a key object. The text goes nowhere else. */
function readPrivateKey(keyPath) {
  return crypto.createPrivateKey(fs.readFileSync(keyPath));
}

/** Apple's own words for what went wrong, one line. */
function describeErrors(status, json) {
  const errors = json && Array.isArray(json.errors) ? json.errors : [];
  if (!errors.length) return 'App Store Connect answered ' + status + '.';
  const parts = errors.slice(0, 3).map((e) => {
    const where = e.source && (e.source.pointer || e.source.parameter);
    return [e.code, e.detail || e.title].filter(Boolean).join(': ') + (where ? ' (' + where + ')' : '');
  });
  return 'App Store Connect answered ' + status + ': ' + parts.join(' | ');
}

function queryString(query) {
  if (!query) return '';
  const parts = [];
  for (const [k, v] of Object.entries(query)) {
    if (v === undefined || v === null || v === '') continue;
    const value = Array.isArray(v) ? v.join(',') : String(v);
    parts.push(encodeURIComponent(k).replace(/%5B/g, '[').replace(/%5D/g, ']') + '=' + encodeURIComponent(value));
  }
  return parts.length ? '?' + parts.join('&') : '';
}

/**
 * The client. Everything it touches from outside comes in through the
 * options, so a test can hand it a fake fetch and a throwaway key and never
 * reach Apple or the real .p8.
 */
function createAscClient({
  env = process.env,
  fetchImpl = globalThis.fetch,
  readKey = readPrivateKey,
  exists = fs.existsSync,
  home = os.homedir(),
  now = () => Date.now(),
  timeoutMs = 30000,
} = {}) {
  function config() {
    return ascConfig(env, { exists, home });
  }

  async function request(method, pathWithVersion, { query, body } = {}) {
    if (!/^\/v\d+\//.test(String(pathWithVersion))) {
      throw new Error('An App Store Connect path starts with its version, like /v1/...: ' + pathWithVersion);
    }
    const cfg = config();
    if (!cfg.ok) throw new AscConfigError(cfg.missing.join('. ') + '.', cfg.missing);
    const token = makeToken({ keyId: cfg.keyId, issuerId: cfg.issuerId, privateKey: readKey(cfg.keyPath), nowMs: now() });
    const url = ASC_HOST + pathWithVersion + queryString(query);
    const options = {
      method,
      headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' },
    };
    if (body !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) options.signal = AbortSignal.timeout(timeoutMs);
    let res;
    try {
      res = await fetchImpl(url, options);
    } catch (e) {
      throw new AscApiError('Could not reach App Store Connect: ' + (e && e.message ? e.message : 'network error'), 0);
    }
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }
    if (!res.ok) throw new AscApiError(describeErrors(res.status, json), res.status, json && json.errors);
    return json;
  }

  /** Every page of a list. Apple's next link already carries the query. */
  async function getAll(pathWithVersion, query, { maxPages = 20 } = {}) {
    const data = [];
    const included = [];
    let page = await request('GET', pathWithVersion, { query });
    for (let i = 0; page; i++) {
      if (Array.isArray(page.data)) data.push(...page.data);
      if (Array.isArray(page.included)) included.push(...page.included);
      const next = page.links && page.links.next;
      if (!next || i + 1 >= maxPages) break;
      const u = new URL(next);
      page = await request('GET', u.pathname, { query: Object.fromEntries(u.searchParams.entries()) });
    }
    return { data, included };
  }

  return {
    config,
    request,
    getAll,
    get: (p, query) => request('GET', p, { query }),
    post: (p, body) => request('POST', p, { body }),
  };
}

module.exports = {
  ASC_HOST,
  TOKEN_SECONDS,
  AscConfigError,
  AscApiError,
  ascConfig,
  defaultKeyPath,
  base64url,
  makeToken,
  describeErrors,
  queryString,
  createAscClient,
};
