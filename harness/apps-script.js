/**
 * Local stand-ins for the Google Apps Script services used by Code.gs:
 * SpreadsheetApp, DriveApp, PropertiesService, CacheService, LockService,
 * Utilities and HtmlService.
 *
 * Only the surface that Code.gs actually calls is implemented, backed by
 * harness/store.js. Semantics mirror Google's (string cells, `getLastRow`
 * ignoring empty rows, chained Range setters, ...).
 */
const crypto = require('crypto');

const DEFAULT_ROWS = 1000;
const DEFAULT_COLS = 26;

function buildServices(store) {
  /* ===================== spreadsheet ===================== */
  function ensureSS() {
    if (!store.data.ss) {
      store.data.ss = { id: 'local-spreadsheet', url: 'http://localhost:3000/', sheets: {} };
      store.save();
    }
    return store.data.ss;
  }

  function createModel(name) {
    const ss = ensureSS();
    if (!ss.sheets[name]) {
      ss.sheets[name] = { rows: [], maxRows: DEFAULT_ROWS, maxCols: DEFAULT_COLS };
      store.save();
    }
    return ss.sheets[name];
  }

  function readBlock(model, r, c, nr, nc) {
    const out = [];
    for (let i = 0; i < nr; i++) {
      const row = model.rows[r - 1 + i] || [];
      const line = [];
      for (let j = 0; j < nc; j++) {
        const v = row[c - 1 + j];
        line.push(v === undefined ? '' : v);
      }
      out.push(line);
    }
    return out;
  }

  function writeBlock(model, r, c, values) {
    values.forEach(function (row, i) {
      const ri = r - 1 + i;
      while (model.rows.length <= ri) model.rows.push([]);
      const target = model.rows[ri];
      row.forEach(function (v, j) {
        const ci = c - 1 + j;
        while (target.length <= ci) target.push('');
        target[ci] = v == null ? '' : String(v);
      });
    });
    store.save();
  }

  function lastRow(model) {
    for (let i = model.rows.length - 1; i >= 0; i--) {
      const row = model.rows[i] || [];
      for (let j = 0; j < row.length; j++) {
        if (String(row[j] === undefined ? '' : row[j]) !== '') return i + 1;
      }
    }
    return 0;
  }

  function makeRange(model, r, c, nr, nc) {
    return {
      getValues: function () { return readBlock(model, r, c, nr, nc); },
      setValues: function (values) { writeBlock(model, r, c, values || []); return this; },
      setValue: function (v) { writeBlock(model, r, c, [[v]]); return this; },
      clearContent: function () {
        writeBlock(model, r, c, readBlock(model, r, c, nr, nc).map(function (row) {
          return row.map(function () { return ''; });
        }));
        return this;
      },
      setNumberFormat: function () { return this; },
      setFontWeight: function () { return this; }
    };
  }

  function makeSheet(name, model) {
    return {
      getName: function () { return name; },
      getMaxRows: function () { return model.maxRows; },
      getMaxColumns: function () { return model.maxCols; },
      getLastRow: function () { return lastRow(model); },
      getRange: function (r, c, nr, nc) { return makeRange(model, r, c, nr || 1, nc || 1); },
      insertRowsAfter: function (after, n) { model.maxRows += n; store.save(); },
      insertColumnsAfter: function (after, n) { model.maxCols += n; store.save(); },
      appendRow: function (values) { writeBlock(model, lastRow(model) + 1, 1, [values]); return this; },
      deleteRows: function (start, n) { model.rows.splice(start - 1, n); store.save(); return this; },
      setFrozenRows: function () { return this; },
      setRightToLeft: function () { return this; }
    };
  }

  function makeSpreadsheet(ss) {
    return {
      getId: function () { return ss.id; },
      getUrl: function () { return ss.url; },
      getSheetByName: function (n) { return ss.sheets[n] ? makeSheet(n, ss.sheets[n]) : null; },
      insertSheet: function (n) { return makeSheet(n, createModel(n)); }
    };
  }

  const SpreadsheetApp = {
    getActiveSpreadsheet: function () { return makeSpreadsheet(ensureSS()); },
    openById: function () { return makeSpreadsheet(ensureSS()); },
    create: function () { return makeSpreadsheet(ensureSS()); }
  };

  /* ===================== Drive ===================== */
  function makeBlob(data, mime, name) {
    let buf;
    if (Buffer.isBuffer(data)) buf = data;
    else buf = Buffer.from(Array.prototype.slice.call(data || []).map(function (b) { return b & 255; }));
    return {
      getBytes: function () { return buf; },
      getContentType: function () { return mime || 'application/octet-stream'; },
      getName: function () { return name || 'file'; }
    };
  }

  function makeFolder(name) {
    return {
      getName: function () { return name; },
      createFile: function (blob) {
        const id = 'f' + crypto.randomUUID();
        store.putFile(id, Buffer.from(blob.getBytes()), { name: blob.getName(), mime: blob.getContentType() });
        return { getId: function () { return id; }, getName: function () { return blob.getName(); } };
      }
    };
  }

  function iterator(items) {
    let i = 0;
    return { hasNext: function () { return i < items.length; }, next: function () { return items[i++]; } };
  }

  const DriveApp = {
    getFoldersByName: function (name) {
      return iterator(store.data.folders
        .filter(function (n) { return n === name; })
        .map(function (n) { return makeFolder(n); }));
    },
    createFolder: function (name) {
      if (store.data.folders.indexOf(name) === -1) {
        store.data.folders.push(name);
        store.save();
      }
      return makeFolder(name);
    },
    getFileById: function (id) {
      const meta = store.getFileMeta(id);
      if (!meta) throw new Error('ملف غير موجود');
      return {
        getBlob: function () { return makeBlob(store.readFileBytes(id), meta.mime, meta.name); },
        setTrashed: function () { store.trashFile(id); }
      };
    }
  };

  /* ===================== Utilities ===================== */
  function formatInZone(date, timeZone, pattern) {
    const g = {};
    new Intl.DateTimeFormat('en-GB', {
      timeZone: timeZone || 'Africa/Cairo',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
    }).formatToParts(date).forEach(function (p) { g[p.type] = p.value; });
    if (g.hour === '24') g.hour = '00';
    return String(pattern || 'yyyy-MM-dd')
      .replace(/yyyy/g, g.year).replace(/MM/g, g.month).replace(/dd/g, g.day)
      .replace(/HH/g, g.hour).replace(/mm/g, g.minute).replace(/ss/g, g.second);
  }

  function signed(bytes) {
    return Array.prototype.slice.call(bytes).map(function (b) { return b > 127 ? b - 256 : b; });
  }

  const Utilities = {
    getUuid: function () { return crypto.randomUUID(); },
    formatDate: function (date, timeZone, pattern) {
      return formatInZone(date instanceof Date ? date : new Date(date), timeZone, pattern);
    },
    computeDigest: function (algorithm, value) {
      return signed(crypto.createHash('sha256').update(String(value), 'utf8').digest());
    },
    base64Decode: function (s) { return signed(Buffer.from(String(s), 'base64')); },
    base64Encode: function (bytes) {
      return Buffer.from(Array.prototype.slice.call(bytes || []).map(function (b) { return b & 255; })).toString('base64');
    },
    newBlob: function (data, contentType, name) { return makeBlob(data, contentType, name); },
    DigestAlgorithm: { SHA_256: 'SHA_256' },
    Charset: { UTF_8: 'UTF_8' }
  };

  /* ===================== properties / cache / lock ===================== */
  const PropertiesService = {
    getScriptProperties: function () {
      return {
        getProperty: function (k) { return store.data.props[k] === undefined ? null : store.data.props[k]; },
        setProperty: function (k, v) { store.data.props[k] = String(v); store.save(); }
      };
    }
  };

  const CacheService = {
    getScriptCache: function () {
      return {
        get: function (k) {
          const entry = store.data.cache[k];
          if (!entry) return null;
          if (entry.exp && entry.exp < Date.now()) { delete store.data.cache[k]; store.save(); return null; }
          return entry.v;
        },
        put: function (k, v, ttlSeconds) {
          store.data.cache[k] = { v: String(v), exp: ttlSeconds ? Date.now() + ttlSeconds * 1000 : 0 };
          store.save();
        },
        remove: function (k) { delete store.data.cache[k]; store.save(); }
      };
    }
  };

  const LockService = {
    getScriptLock: function () { return { waitLock: function () { }, releaseLock: function () { } }; }
  };

  const HtmlService = {
    createHtmlOutputFromFile: function () {
      const self = {
        setTitle: function () { return self; },
        addMetaTag: function () { return self; },
        setXFrameOptionsMode: function () { return self; }
      };
      return self;
    },
    XFrameOptionsMode: { ALLOWALL: 'ALLOWALL' }
  };

  return { SpreadsheetApp, DriveApp, Utilities, PropertiesService, CacheService, LockService, HtmlService };
}

module.exports = { buildServices };
