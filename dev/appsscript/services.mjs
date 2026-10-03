// Utilities / PropertiesService / CacheService / LockService / HtmlService.
// Only the behaviour Code.gs relies on is implemented.
import crypto from 'node:crypto';

const DigestAlgorithm = { SHA_256: 'SHA_256', SHA_1: 'SHA_1', MD5: 'MD5' };
const Charset = { UTF_8: 'UTF_8', US_ASCII: 'US_ASCII' };

const isDate = (v) => Object.prototype.toString.call(v) === '[object Date]';

// TZ-aware formatting for the tokens Code.gs uses: yyyy MM dd HH mm ss.
function formatDate(date, tz, fmt) {
  const d = isDate(date) ? date : new Date(date);
  if (isNaN(d.getTime())) throw new Error('تاريخ غير صحيح');
  const parts = {};
  new Intl.DateTimeFormat('en-US', {
    timeZone: tz || 'UTC',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hour12: false
  }).formatToParts(d).forEach((p) => { parts[p.type] = p.value; });
  if (parts.hour === '24') parts.hour = '00';
  return String(fmt)
    .replace(/yyyy/g, parts.year)
    .replace(/MM/g, parts.month)
    .replace(/dd/g, parts.day)
    .replace(/HH/g, parts.hour)
    .replace(/mm/g, parts.minute)
    .replace(/ss/g, parts.second);
}

const newBlob = (bytes, contentType, name) => ({
  getBytes: () => Array.from(bytes),
  getContentType: () => contentType || 'application/octet-stream',
  getName: () => name || ''
});

export function createUtilities() {
  return {
    DigestAlgorithm,
    Charset,
    formatDate,
    getUuid: () => crypto.randomUUID(),
    computeDigest(algo, value, charset) {
      const name = { SHA_256: 'sha256', SHA_1: 'sha1', MD5: 'md5' }[algo] || 'sha256';
      const digest = crypto.createHash(name)
        .update(Buffer.from(String(value), charset === Charset.US_ASCII ? 'ascii' : 'utf8'))
        .digest();
      return Array.from(digest);
    },
    base64Decode: (str) => Array.from(Buffer.from(String(str || ''), 'base64')),
    base64Encode: (bytes) => Buffer.from(bytes || []).toString('base64'),
    newBlob
  };
}

export function createPropertiesService(db) {
  const props = {
    getProperty: (k) => (Object.prototype.hasOwnProperty.call(db.data.props, k) ? db.data.props[k] : null),
    setProperty(k, v) { db.data.props[k] = String(v); db.save(); return props; },
    deleteProperty(k) { delete db.data.props[k]; db.save(); return props; },
    getProperties: () => Object.assign({}, db.data.props),
    setProperties(o) { Object.assign(db.data.props, o); db.save(); return props; }
  };
  return {
    getScriptProperties: () => props,
    getUserProperties: () => props,
    getDocumentProperties: () => props
  };
}

export function createCacheService() {
  const mem = new Map();
  const api = {
    get(k) {
      const e = mem.get(k);
      if (!e) return null;
      if (e.exp && e.exp < Date.now()) { mem.delete(k); return null; }
      return e.v;
    },
    put(k, v, ttl) { mem.set(k, { v: String(v), exp: ttl ? Date.now() + ttl * 1000 : 0 }); },
    remove(k) { mem.delete(k); },
    getAll(keys) {
      const o = {};
      (keys || []).forEach((k) => { const v = api.get(k); if (v != null) o[k] = v; });
      return o;
    },
    putAll(o, ttl) { Object.keys(o || {}).forEach((k) => api.put(k, o[k], ttl)); },
    removeAll(keys) { (keys || []).forEach((k) => mem.delete(k)); }
  };
  return { getScriptCache: () => api, getUserCache: () => api, getDocumentCache: () => api };
}

export function createLockService() {
  // Node runs our request handlers synchronously on a single thread, so the
  // script lock is already exclusive for the lifetime of each call.
  const api = { waitLock: () => true, tryLock: () => true, releaseLock: () => {}, hasLock: () => true };
  return { getScriptLock: () => api, getUserLock: () => api, getDocumentLock: () => api };
}

export function createHtmlService() {
  const page = {
    setTitle() { return page; },
    addMetaTag() { return page; },
    setContent() { return page; },
    setXFrameOptionsMode() { return page; },
    getContent: () => ''
  };
  return {
    createHtmlOutputFromFile: () => page,
    createHtmlOutput: () => page,
    createTemplateFromFile: () => page,
    XFrameOptionsMode: { ALLOWALL: 'ALLOWALL', DEFAULT: 'DEFAULT', SAMEORIGIN: 'SAMEORIGIN' }
  };
}
