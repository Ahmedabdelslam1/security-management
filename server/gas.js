'use strict';
/**
 * Minimal emulation of the Google Apps Script server globals used by Code.gs:
 * SpreadsheetApp (Sheets as the database), DriveApp (image storage),
 * Utilities / CacheService / PropertiesService / LockService / HtmlService.
 *
 * Only the surface actually exercised by Code.gs is implemented.
 */
const crypto = require('crypto');

const DEFAULT_ROWS = 1000;
const DEFAULT_COLS = 26;

function makeRow(cols) {
  return new Array(cols).fill('');
}

/* ===================== Sheets ===================== */

class Range {
  constructor(sheet, row, col, numRows, numCols) {
    this.sheet = sheet;
    this.row = row;
    this.col = col;
    this.numRows = numRows;
    this.numCols = numCols;
  }

  getValues() {
    const out = [];
    for (let r = 0; r < this.numRows; r++) {
      const row = [];
      for (let c = 0; c < this.numCols; c++) row.push(this.sheet._cell(this.row + r, this.col + c));
      out.push(row);
    }
    return out;
  }

  setValues(values) {
    this.sheet._ensure(this.row + this.numRows - 1, this.col + this.numCols - 1);
    for (let r = 0; r < values.length && r < this.numRows; r++) {
      const src = values[r] || [];
      for (let c = 0; c < this.numCols; c++) this.sheet._set(this.row + r, this.col + c, src[c]);
    }
    this.sheet.store.save();
    return this;
  }

  setValue(value) {
    return this.setValues([[value]]);
  }

  /* Formatting is irrelevant for a headless data store. */
  setNumberFormat() { return this; }
  setFontWeight() { return this; }
  setFontSize() { return this; }
  setHorizontalAlignment() { return this; }

  clearContent() {
    for (let r = 0; r < this.numRows; r++) {
      for (let c = 0; c < this.numCols; c++) this.sheet._set(this.row + r, this.col + c, '');
    }
    this.sheet.store.save();
    return this;
  }
}

class Sheet {
  constructor(store, record, name) {
    this.store = store;
    this.record = record;
    this.name = name;
    if (!this.record.sheets[name]) {
      const rows = [];
      for (let i = 0; i < DEFAULT_ROWS; i++) rows.push(makeRow(DEFAULT_COLS));
      this.record.sheets[name] = rows;
      this.store.save();
    }
  }

  get _rows() {
    return this.record.sheets[this.name];
  }

  _cell(row, col) {
    const rows = this._rows;
    if (row < 1 || col < 1 || row > rows.length) return '';
    const r = rows[row - 1];
    return col > r.length ? '' : r[col - 1];
  }

  _set(row, col, value) {
    this._ensure(row, col);
    this._rows[row - 1][col - 1] = value == null ? '' : String(value);
  }

  _ensure(rowsNeeded, colsNeeded) {
    const rows = this._rows;
    const currentCols = rows[0] ? rows[0].length : 0;
    if (colsNeeded > currentCols) {
      const cols = Math.max(colsNeeded, DEFAULT_COLS);
      rows.forEach((r) => { while (r.length < cols) r.push(''); });
    }
    const cols = rows[0] ? rows[0].length : colsNeeded;
    while (rows.length < rowsNeeded) rows.push(makeRow(cols));
  }

  getName() { return this.name; }
  getMaxRows() { return this._rows.length; }
  getMaxColumns() { return this._rows[0] ? this._rows[0].length : 0; }

  getLastRow() {
    const rows = this._rows;
    for (let r = rows.length - 1; r >= 0; r--) {
      for (let c = 0; c < rows[r].length; c++) if (rows[r][c] !== '') return r + 1;
    }
    return 0;
  }

  getLastColumn() {
    const rows = this._rows;
    let last = 0;
    rows.forEach((row) => {
      for (let c = row.length - 1; c >= 0; c--) if (row[c] !== '') { if (c + 1 > last) last = c + 1; break; }
    });
    return last;
  }

  getRange(row, col, numRows, numCols) {
    return new Range(this, row, col, numRows || 1, numCols || 1);
  }

  insertRowsAfter(afterRow, howMany) {
    const rows = this._rows;
    const cols = rows[0] ? rows[0].length : DEFAULT_COLS;
    const blank = [];
    for (let i = 0; i < howMany; i++) blank.push(makeRow(cols));
    rows.splice(afterRow, 0, ...blank);
    this.store.save();
    return this;
  }

  insertColumnsAfter(afterCol, howMany) {
    const blank = [];
    for (let i = 0; i < howMany; i++) blank.push('');
    this._rows.forEach((row) => row.splice(afterCol, 0, ...blank));
    this.store.save();
    return this;
  }

  insertRowAfter(afterRow) { return this.insertRowsAfter(afterRow, 1); }
  insertColumnAfter(afterCol) { return this.insertColumnsAfter(afterCol, 1); }
  setFrozenRows() { return this; }
  setRightToLeft() { return this; }

  appendRow(values) {
    const row = this.getLastRow() + 1;
    this._ensure(row, values.length);
    for (let c = 0; c < values.length; c++) this._set(row, c + 1, values[c]);
    this.store.save();
    return this;
  }

  deleteRows(rowIndex, howMany) {
    this._rows.splice(rowIndex - 1, howMany);
    this.store.save();
    return this;
  }

  deleteColumns(columnIndex, howMany) {
    this._rows.forEach((row) => row.splice(columnIndex - 1, howMany));
    this.store.save();
    return this;
  }
}

class Spreadsheet {
  constructor(store, id, name) {
    this.store = store;
    this.id = id;
    if (!this.store.state.spreadsheets[id]) {
      this.store.state.spreadsheets[id] = { id, name: name || 'إدارة الأمن - قاعدة البيانات', sheets: {} };
      this.store.save();
    }
  }

  get _record() {
    return this.store.state.spreadsheets[this.id];
  }

  getId() { return this.id; }
  getName() { return this._record.name; }
  getUrl() { return 'http://localhost:' + (process.env.PORT || 3000) + '/'; }
  getSheets() { return Object.keys(this._record.sheets).map((n) => new Sheet(this.store, this._record, n)); }
  getSheetByName(name) { return this._record.sheets[name] ? new Sheet(this.store, this._record, name) : null; }
  insertSheet(name) { return new Sheet(this.store, this._record, name); }
}

function makeSpreadsheetApp(store) {
  function open(id, name) {
    const record = store.state.spreadsheets[id];
    return new Spreadsheet(store, id, record ? record.name : name);
  }
  return {
    openById(id) {
      if (!id) throw new Error('معرّف جدول البيانات مطلوب');
      return open(String(id));
    },
    getActiveSpreadsheet() {
      const id = store.state.spreadsheetId;
      return id ? open(id) : null;
    },
    create(name) {
      const id = 'ss' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
      store.state.spreadsheetId = id;
      store.save();
      return open(id, name);
    }
  };
}

/* ===================== Drive ===================== */

class Blob {
  constructor(bytes, contentType, name) {
    if (Buffer.isBuffer(bytes)) this._bytes = bytes;
    else if (bytes instanceof Uint8Array) this._bytes = Buffer.from(bytes);
    else if (Array.isArray(bytes)) this._bytes = Buffer.from(bytes.map((n) => n & 255));
    else this._bytes = Buffer.from(String(bytes == null ? '' : bytes), 'utf8');
    this._type = contentType || 'application/octet-stream';
    this._name = name || 'blob';
  }
  getBytes() { return this._bytes; }
  getContentType() { return this._type; }
  getName() { return this._name; }
  getDataAsString() { return this._bytes.toString('utf8'); }
}

function makeDriveApp(store) {
  const state = store.state;

  class File {
    constructor(record) { this.record = record; }
    getId() { return this.record.id; }
    getName() { return this.record.name; }
    getBlob() { return new Blob(store.readBlob(this.record.id) || Buffer.alloc(0), this.record.mimeType, this.record.name); }
    setTrashed(trashed) { this.record.trashed = !!trashed; store.save(); return this; }
  }

  class Folder {
    constructor(record) { this.record = record; }
    getId() { return this.record.id; }
    getName() { return this.record.name; }
    createFile(blob) {
      const id = 'f' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
      const record = {
        id,
        name: blob.getName(),
        mimeType: blob.getContentType(),
        folderId: this.record.id
      };
      state.files[id] = record;
      store.writeBlob(id, Buffer.from(blob.getBytes()));
      store.save();
      return new File(record);
    }
  }

  return {
    getFoldersByName(name) {
      const list = Object.values(state.folders).filter((f) => f.name === name);
      let i = 0;
      return { hasNext: () => i < list.length, next: () => new Folder(list[i++]) };
    },
    createFolder(name) {
      const id = 'd' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
      state.folders[id] = { id, name: name || 'مجلد' };
      store.save();
      return new Folder(state.folders[id]);
    },
    getFileById(id) {
      const record = state.files[String(id)];
      if (!record) throw new Error('لا يوجد ملف بهذا المعرّف');
      return new File(record);
    },
    getFilesByName(name) {
      const list = Object.values(state.files).filter((f) => f.name === name);
      let i = 0;
      return { hasNext: () => i < list.length, next: () => new File(list[i++]) };
    }
  };
}

/* ===================== Utilities ===================== */

const DIGESTS = { SHA_256: 'sha256', SHA_1: 'sha1', MD5: 'md5' };

function formatDate(date, timeZone, format) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: timeZone || 'UTC',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hour12: false
  }).formatToParts(date);
  const v = {};
  parts.forEach((p) => { v[p.type] = p.value; });
  const hour = v.hour === '24' ? '00' : v.hour;
  return String(format).replace(/yyyy|MM|dd|HH|mm|ss/g, (token) => ({
    yyyy: v.year, MM: v.month, dd: v.day, HH: hour, mm: v.minute, ss: v.second
  })[token]);
}

function toSignedBytes(buffer) {
  return Array.from(buffer).map((b) => (b > 127 ? b - 256 : b));
}

function bytesToBuffer(bytes) {
  if (Buffer.isBuffer(bytes)) return bytes;
  if (bytes instanceof Uint8Array) return Buffer.from(bytes);
  if (Array.isArray(bytes)) return Buffer.from(bytes.map((n) => n & 255));
  return Buffer.from(String(bytes == null ? '' : bytes), 'utf8');
}

const Utilities = {
  Charset: { UTF_8: 'UTF-8', US_ASCII: 'US-ASCII', UTF_8_NOSIG: 'UTF-8' },
  DigestAlgorithm: { SHA_256: 'SHA_256', SHA_1: 'SHA_1', MD5: 'MD5' },

  formatDate(date, timeZone, format) {
    return formatDate(date instanceof Date ? date : new Date(date), timeZone, format);
  },

  computeDigest(algorithm, value, charset) {
    const algo = DIGESTS[algorithm] || 'sha256';
    const input = bytesToBuffer(value).toString(charset === 'US-ASCII' ? 'ascii' : 'utf8');
    return toSignedBytes(crypto.createHash(algo).update(input, 'utf8').digest());
  },

  getUuid() {
    return crypto.randomUUID();
  },

  newBlob(bytes, contentType, name) {
    return new Blob(bytes, contentType, name);
  },

  base64Decode(encoded) {
    return toSignedBytes(Buffer.from(String(encoded || ''), 'base64'));
  },

  base64Encode(bytes) {
    return bytesToBuffer(bytes).toString('base64');
  }
};

/* ===================== Script services ===================== */

function makeCacheService() {
  const entries = new Map();
  return {
    getScriptCache() {
      return {
        get(key) {
          const entry = entries.get(String(key));
          if (!entry) return null;
          if (entry.expires && entry.expires < Date.now()) {
            entries.delete(String(key));
            return null;
          }
          return entry.value;
        },
        put(key, value, seconds) {
          entries.set(String(key), {
            value: String(value),
            expires: seconds ? Date.now() + Number(seconds) * 1000 : 0
          });
        },
        remove(key) { entries.delete(String(key)); },
        getAll(keys) {
          const out = {};
          (keys || []).forEach((k) => { const v = this.get(k); if (v !== null) out[k] = v; });
          return out;
        },
        putAll(values, seconds) {
          Object.keys(values || {}).forEach((k) => this.put(k, values[k], seconds));
        },
        removeAll(keys) { (keys || []).forEach((k) => this.remove(k)); }
      };
    }
  };
}

function makePropertiesService(store) {
  function properties() {
    return {
      getProperty(key) {
        const value = store.state.props[String(key)];
        return value === undefined ? null : value;
      },
      getProperties() { return Object.assign({}, store.state.props); },
      setProperty(key, value) { store.state.props[String(key)] = String(value); store.save(); },
      setProperties(values) {
        Object.keys(values || {}).forEach((k) => { store.state.props[k] = String(values[k]); });
        store.save();
      },
      deleteProperty(key) { delete store.state.props[String(key)]; store.save(); }
    };
  }
  return { getScriptProperties: properties, getDocumentProperties: properties, getUserProperties: properties };
}

function makeLockService() {
  let held = false;
  function lock() {
    return {
      waitLock() { held = true; },
      tryLock() { held = true; return true; },
      hasLock() { return held; },
      releaseLock() { held = false; }
    };
  }
  return { getScriptLock: lock, getDocumentLock: lock, getUserLock: lock };
}

function makeHtmlService() {
  function output() {
    const self = {
      setTitle() { return self; },
      addMetaTag() { return self; },
      setXFrameOptionsMode() { return self; },
      append() { return self; },
      getContent() { return ''; }
    };
    return self;
  }
  return {
    createHtmlOutputFromFile: output,
    createHtmlOutput: output,
    createTemplateFromFile: output,
    XFrameOptionsMode: { ALLOWALL: 'ALLOWALL', DEFAULT: 'DEFAULT' }
  };
}

/** Builds the sandbox globals handed to the vm context running Code.gs. */
function buildGlobals(store) {
  return {
    SpreadsheetApp: makeSpreadsheetApp(store),
    DriveApp: makeDriveApp(store),
    Utilities,
    CacheService: makeCacheService(),
    PropertiesService: makePropertiesService(store),
    LockService: makeLockService(),
    HtmlService: makeHtmlService()
  };
}

module.exports = { buildGlobals, Blob };
