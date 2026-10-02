'use strict';
/**
 * محاكاة محلية لخدمات Google Apps Script التي يستخدمها Code.gs.
 *
 * الهدف: تشغيل ملف Code.gs الحقيقي دون أي تعديل عليه خارج بيئة Google،
 * حتى يمكن استخدام البرنامج في المعاينة المحلية.
 *
 * الخدمات المُحاكاة: SpreadsheetApp (تخزين JSON)، PropertiesService،
 * CacheService، DriveApp (الملفات)، Utilities، LockService.
 *
 * هذا الملف أداة تطوير فقط: لا يُنشر ولا يؤثر على تطبيق Apps Script الفعلي.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const vm = require('vm');

const TZ = process.env.TZ || 'Africa/Cairo';

/* ------------------------------------------------------------------ */
/* التخزين (الجداول، الخصائص، الملفات)                                */
/* ------------------------------------------------------------------ */
function createStore(dataDir) {
  const file = path.join(dataDir, 'db.json');
  let db = { sheets: {}, props: {}, files: {}, folders: {}, ssId: '' };
  try {
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    db = Object.assign(db, raw);
  } catch (e) { /* أول تشغيل: قاعدة بيانات فارغة */ }
  db.sheets = db.sheets || {};
  db.props = db.props || {};
  db.files = db.files || {};
  db.folders = db.folders || {};

  let pending = false;
  function writeNow() {
    try {
      fs.mkdirSync(dataDir, { recursive: true });
      fs.writeFileSync(file, JSON.stringify(db));
    } catch (e) {
      console.error('[gas-env] تعذّر الحفظ:', e.message);
    }
  }
  function save() {
    if (pending) return;
    pending = true;
    setTimeout(function () { pending = false; writeNow(); }, 10);
  }
  return { db, save, writeNow, file };
}

/* ------------------------------------------------------------------ */
/* أدوات مساعدة                                                        */
/* ------------------------------------------------------------------ */
function formatDate(date, tz, fmt) {
  const d = (date instanceof Date) ? date : new Date(date);
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz || TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
  }).formatToParts(d).reduce(function (acc, p) { acc[p.type] = p.value; return acc; }, {});
  const map = {
    yyyy: parts.year, MM: parts.month, dd: parts.day,
    HH: parts.hour, mm: parts.minute, ss: parts.second
  };
  return String(fmt || 'yyyy-MM-dd HH:mm:ss').replace(/yyyy|MM|dd|HH|mm|ss/g, function (m) { return map[m]; });
}

function toBytes(v) {
  if (Array.isArray(v)) return v.map(function (b) { return b & 255; });
  if (v instanceof Uint8Array || Buffer.isBuffer(v)) return Array.from(v, function (b) { return b & 255; });
  return Array.from(Buffer.from(String(v), 'utf8'));
}

/* ------------------------------------------------------------------ */
/* سياق التنفيذ                                                        */
/* ------------------------------------------------------------------ */
function createContext(codeSource, dataDir, extras) {
  const store = createStore(dataDir);
  const db = store.db;
  const save = store.save;
  const cache = new Map();          // CacheService — مشتركة بين الطلبات
  const sheetCache = new Map();

  /* ---------- الجداول ---------- */
  function newSheetData() { return { maxRows: 1000, rows: [] }; }

  function sheetData(name) {
    if (!db.sheets[name]) { db.sheets[name] = newSheetData(); save(); }
    return db.sheets[name];
  }

  function cellText(v) {
    if (v == null) return '';
    if (v instanceof Date) return formatDate(v, TZ, 'yyyy-MM-dd');
    return String(v);
  }

  function makeRange(name, row, col, numRows, numCols) {
    const data = sheetData(name);
    row = Number(row) || 1; col = Number(col) || 1;
    numRows = (numRows == null) ? 1 : Number(numRows);
    numCols = (numCols == null) ? 1 : Number(numCols);
    return {
      getValues: function () {
        const out = [];
        for (let r = row; r < row + numRows; r++) {
          const line = data.rows[r - 1] || [];
          const vals = [];
          for (let c = col; c < col + numCols; c++) vals.push(cellText(line[c - 1]));
          out.push(vals);
        }
        return out;
      },
      getValue: function () { return this.getValues()[0][0]; },
      setValues: function (values) {
        (values || []).forEach(function (line, ri) {
          const at = row - 1 + ri;
          if (!data.rows[at]) data.rows[at] = [];
          (line || []).forEach(function (v, ci) {
            const idx = col - 1 + ci;
            while (data.rows[at].length < idx) data.rows[at].push('');
            data.rows[at][idx] = cellText(v);
          });
        });
        save();
        return this;
      },
      setValue: function (v) { return this.setValues([[v]]); },
      clearContent: function () {
        for (let r = row; r < row + numRows; r++) {
          const line = data.rows[r - 1];
          if (!line) continue;
          for (let c = col; c < col + numCols; c++) if (line[c - 1] !== undefined) line[c - 1] = '';
        }
        save();
        return this;
      },
      setNumberFormat: function () { return this; },
      setFontWeight: function () { return this; }
    };
  }

  function makeSheet(name) {
    if (sheetCache.has(name)) return sheetCache.get(name);
    const data = sheetData(name);
    const sheet = {
      getName: function () { return name; },
      getLastRow: function () {
        let last = 0;
        data.rows.forEach(function (line, i) {
          if (line && line.some(function (c) { return c !== '' && c != null; })) last = i + 1;
        });
        return last;
      },
      getMaxRows: function () { return Math.max(data.maxRows, data.rows.length); },
      getRange: function (r, c, nr, nc) { return makeRange(name, r, c, nr, nc); },
      appendRow: function (values) {
        data.rows.push((values || []).map(cellText));
        save();
        return sheet;
      },
      deleteRows: function (startRow, howMany) {
        data.rows.splice(Number(startRow) - 1, Number(howMany) || 1);
        save();
        return sheet;
      },
      insertRowsAfter: function (afterRow, howMany) {
        data.maxRows = Math.max(data.maxRows, Number(afterRow) || 0) + (Number(howMany) || 0);
        save();
        return sheet;
      },
      setFrozenRows: function () { return sheet; },
      setRightToLeft: function () { return sheet; }
    };
    sheetCache.set(name, sheet);
    return sheet;
  }

  let ssId = db.ssId || ('local-ss-' + crypto.randomUUID().slice(0, 8));
  db.ssId = ssId;
  const spreadsheet = {
    getId: function () { return ssId; },
    getUrl: function () { return 'local://' + ssId; },
    getName: function () { return 'إدارة الأمن - البيانات'; },
    getSheetByName: function (n) { return db.sheets[n] ? makeSheet(n) : null; },
    insertSheet: function (n) { sheetData(n); return makeSheet(n); },
    getSheets: function () { return Object.keys(db.sheets).map(makeSheet); }
  };

  /* ---------- Drive (الصور) ---------- */
  function makeFile(meta) {
    return {
      getId: function () { return meta.id; },
      getName: function () { return meta.name; },
      getBlob: function () {
        return makeBlob(Array.from(Buffer.from(meta.base64 || '', 'base64')), meta.type, meta.name);
      },
      setTrashed: function (v) {
        if (v) delete db.files[meta.id];
        save();
        return this;
      }
    };
  }

  function makeFolder(meta) {
    return {
      getId: function () { return meta.id; },
      getName: function () { return meta.name; },
      createFile: function (blob) {
        const id = 'f' + crypto.randomUUID();
        db.files[id] = {
          id: id,
          name: blob.getName ? blob.getName() : 'file',
          type: (blob.getContentType && blob.getContentType()) || 'application/octet-stream',
          base64: Buffer.from(blob.getBytes()).toString('base64')
        };
        save();
        return makeFile(db.files[id]);
      }
    };
  }

  const driveApp = {
    createFolder: function (name) {
      const id = 'd' + crypto.randomUUID();
      db.folders[id] = { id: id, name: name };
      save();
      return makeFolder(db.folders[id]);
    },
    getFoldersByName: function (name) {
      const found = Object.keys(db.folders).map(function (k) { return db.folders[k]; })
        .filter(function (f) { return f.name === name; });
      let i = 0;
      return { hasNext: function () { return i < found.length; }, next: function () { return makeFolder(found[i++]); } };
    },
    getFileById: function (id) {
      const meta = db.files[id];
      if (!meta) throw new Error('ملف غير موجود: ' + id);
      return makeFile(meta);
    },
    getFilesByName: function (name) {
      const found = Object.keys(db.files).map(function (k) { return db.files[k]; })
        .filter(function (f) { return f.name === name; });
      let i = 0;
      return { hasNext: function () { return i < found.length; }, next: function () { return makeFile(found[i++]); } };
    }
  };

  /* ---------- Blob و Utilities ---------- */
  function makeBlob(bytes, type, name) {
    return {
      getBytes: function () { return bytes; },
      getContentType: function () { return type || 'application/octet-stream'; },
      getName: function () { return name || 'blob'; }
    };
  }

  const utilities = {
    formatDate: formatDate,
    getUuid: function () { return crypto.randomUUID(); },
    computeDigest: function (algo, value) {
      const h = crypto.createHash(algo === 'MD5' ? 'md5' : 'sha256').update(String(value), 'utf8').digest();
      return Array.from(h).map(function (b) { return b > 127 ? b - 256 : b; });
    },
    DigestAlgorithm: { MD5: 'MD5', SHA_256: 'SHA_256' },
    Charset: { UTF_8: 'UTF_8' },
    newBlob: makeBlob,
    base64Decode: function (s) { return Array.from(Buffer.from(String(s), 'base64')); },
    base64Encode: function (b) { return Buffer.from(toBytes(b)).toString('base64'); }
  };

  /* ---------- Cache و Properties و Lock ---------- */
  const scriptCache = {
    get: function (k) {
      const e = cache.get(k);
      if (!e) return null;
      if (e.exp && e.exp < Date.now()) { cache.delete(k); return null; }
      return e.v;
    },
    put: function (k, v, seconds) {
      cache.set(k, { v: String(v), exp: seconds ? Date.now() + seconds * 1000 : 0 });
    },
    remove: function (k) { cache.delete(k); },
    getAll: function (keys) {
      const out = {};
      (keys || []).forEach(function (k) { const v = scriptCache.get(k); if (v !== null) out[k] = v; }, this);
      return out;
    }
  };

  const scriptProperties = {
    getProperty: function (k) { return db.props[k] === undefined ? null : String(db.props[k]); },
    setProperty: function (k, v) { db.props[k] = String(v); save(); },
    deleteProperty: function (k) { delete db.props[k]; save(); },
    getProperties: function () { return Object.assign({}, db.props); }
  };

  const sandbox = {
    console: console,
    Logger: { log: function () { console.log.apply(console, arguments); } },
    SpreadsheetApp: {
      getActiveSpreadsheet: function () { return null; },
      openById: function () { return spreadsheet; },
      create: function () { return spreadsheet; }
    },
    DriveApp: driveApp,
    Utilities: utilities,
    PropertiesService: { getScriptProperties: function () { return scriptProperties; } },
    CacheService: { getScriptCache: function () { return scriptCache; } },
    LockService: {
      getScriptLock: function () {
        return { waitLock: function () { }, tryLock: function () { return true; }, releaseLock: function () { }, hasLock: function () { return true; } };
      }
    },
    HtmlService: {
      createHtmlOutputFromFile: function () { return { getContent: function () { return ''; }, setTitle: function () { return this; }, addMetaTag: function () { return this; }, setXFrameOptionsMode: function () { return this; } }; },
      XFrameOptionsMode: { ALLOWALL: 'ALLOWALL' }
    },
    Session: { getActiveUser: function () { return { getEmail: function () { return 'dev@local'; } }; } },
    __gas: { db: db, store: store, cache: cache }
  };

  vm.createContext(sandbox);
  vm.runInContext(codeSource, sandbox, { filename: 'Code.gs' });

  return {
    sandbox: sandbox,
    store: store,
    db: db,
    call: function (fn, args) {
      if (typeof sandbox[fn] !== 'function') throw new Error('دالة غير معروفة: ' + fn);
      return sandbox[fn].apply(null, args || []);
    },
    file: function (id) { return db.files[id] || null; },
    sheets: function () { return Object.keys(db.sheets); },
    extras: extras || {}
  };
}

module.exports = { createContext: createContext, formatDate: formatDate };
