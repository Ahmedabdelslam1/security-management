'use strict';
/*
 * Local emulation of the Google Apps Script services used by Code.gs
 * (SpreadsheetApp, PropertiesService, DriveApp, Utilities, Session, CacheService).
 *
 * Nothing here changes the application code: Code.gs runs verbatim inside a vm
 * context with these globals injected. All state is persisted as JSON so the
 * "spreadsheet" survives container restarts.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = process.env.HARNESS_DATA_DIR || path.join(__dirname, '..', '.base44-data');
const DB_FILE = path.join(DATA_DIR, 'gas-db.json');
const IMG_DIR = path.join(DATA_DIR, 'images');
const TZ = process.env.HARNESS_TZ || 'Africa/Cairo';

/* ===================== persistence ===================== */

function encodeCell(v) {
  if (v instanceof Date) return { __t: 'date', v: v.toISOString() };
  if (Buffer.isBuffer(v)) return { __t: 'buf', v: v.toString('base64') };
  return v;
}

function decodeCell(v) {
  if (v && typeof v === 'object' && v.__t === 'date') return new Date(v.v);
  if (v && typeof v === 'object' && v.__t === 'buf') return Buffer.from(v.v, 'base64');
  return v;
}

const store = { props: {}, sheets: {}, cache: {}, files: {} };

function load() {
  try {
    const raw = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    store.props = raw.props || {};
    store.cache = raw.cache || {};
    store.files = raw.files || {};
    store.sheets = {};
    Object.keys(raw.sheets || {}).forEach(function (name) {
      store.sheets[name] = (raw.sheets[name] || []).map(function (row) {
        return (row || []).map(decodeCell);
      });
    });
  } catch (e) {
    /* fresh database */
  }
}

let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(function () {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    const out = { props: store.props, cache: store.cache, files: store.files, sheets: {} };
    Object.keys(store.sheets).forEach(function (name) {
      out.sheets[name] = store.sheets[name].map(function (row) {
        return (row || []).map(encodeCell);
      });
    });
    const tmp = DB_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, DB_FILE);
  }, 5);
}

load();
fs.mkdirSync(IMG_DIR, { recursive: true });

/* ===================== Spreadsheet ===================== */

function isBlank(c) {
  return c === '' || c === null || c === undefined;
}

class Range {
  constructor(sheet, row, col, numRows, numCols) {
    this.sheet = sheet;
    this.row = row;
    this.col = col;
    this.numRows = numRows;
    this.numCols = numCols;
  }
  _ensure(r, c) {
    const d = this.sheet.cells();
    while (d.length < r) d.push([]);
    const row = d[r - 1];
    while (row.length < c) row.push('');
  }
  getValues() {
    const d = this.sheet.cells();
    const out = [];
    for (let i = 0; i < this.numRows; i++) {
      const row = d[this.row - 1 + i] || [];
      const line = [];
      for (let j = 0; j < this.numCols; j++) {
        const v = row[this.col - 1 + j];
        line.push(v === undefined ? '' : v);
      }
      out.push(line);
    }
    return out;
  }
  setValue(v) {
    this._ensure(this.row, this.col);
    this.sheet.cells()[this.row - 1][this.col - 1] = v;
    save();
    return this;
  }
  setValues(matrix) {
    for (let i = 0; i < matrix.length; i++) {
      for (let j = 0; j < matrix[i].length; j++) {
        this._ensure(this.row + i, this.col + j);
        this.sheet.cells()[this.row - 1 + i][this.col - 1 + j] = matrix[i][j];
      }
    }
    save();
    return this;
  }
  clearContent() {
    for (let i = 0; i < this.numRows; i++) {
      for (let j = 0; j < this.numCols; j++) {
        const d = this.sheet.cells();
        if (d[this.row - 1 + i]) d[this.row - 1 + i][this.col - 1 + j] = '';
      }
    }
    save();
    return this;
  }
}

class Sheet {
  constructor(store_, name) {
    this.store = store_;
    this.name = name;
  }
  cells() {
    if (!this.store.sheets[this.name]) this.store.sheets[this.name] = [];
    return this.store.sheets[this.name];
  }
  getName() { return this.name; }
  getLastRow() {
    const d = this.cells();
    let last = 0;
    for (let i = 0; i < d.length; i++) {
      if ((d[i] || []).some(function (c) { return !isBlank(c); })) last = i + 1;
    }
    return last;
  }
  getLastColumn() {
    let last = 0;
    this.cells().forEach(function (row) {
      (row || []).forEach(function (c, j) {
        if (!isBlank(c) && j + 1 > last) last = j + 1;
      });
    });
    return last;
  }
  getDataRange() {
    return new Range(this, 1, 1, Math.max(this.getLastRow(), 1), Math.max(this.getLastColumn(), 1));
  }
  getRange(row, col, numRows, numCols) {
    return new Range(this, row, col, numRows === undefined ? 1 : numRows, numCols === undefined ? 1 : numCols);
  }
  appendRow(row) {
    this.cells().push(Array.isArray(row) ? row.slice() : [row]);
    save();
    return this;
  }
  deleteRow(row) {
    if (row >= 1 && row <= this.cells().length) this.cells().splice(row - 1, 1);
    save();
    return this;
  }
  clear() {
    this.store.sheets[this.name] = [];
    save();
    return this;
  }
}

class Spreadsheet {
  constructor(id) { this.id = id; }
  getId() { return this.id; }
  getSheetByName(name) {
    return store.sheets[name] ? new Sheet(store, name) : null;
  }
  insertSheet(name) {
    if (!store.sheets[name]) store.sheets[name] = [];
    save();
    return new Sheet(store, name);
  }
  getSheets() {
    return Object.keys(store.sheets).map(function (n) { return new Sheet(store, n); });
  }
}

/* ===================== Drive (images) ===================== */

class DriveFile {
  constructor(id) { this.id = id; }
  getId() { return this.id; }
  setSharing() { return this; }
}

class DriveFolder {
  constructor(id) { this.id = id; }
  getId() { return this.id; }
  createFile(blob) {
    const id = 'img_' + crypto.randomUUID();
    const bytes = blob && blob.bytes ? Buffer.from(blob.bytes) : Buffer.alloc(0);
    fs.writeFileSync(path.join(IMG_DIR, id), bytes);
    store.files[id] = { name: (blob && blob.name) || id, type: (blob && blob.type) || 'image/jpeg' };
    save();
    return new DriveFile(id);
  }
}

/* ===================== Utilities / Session / Cache ===================== */

function formatDate(date, tz, fmt) {
  const d = date instanceof Date ? date : new Date(date);
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz || TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
  }).formatToParts(d);
  const m = {};
  parts.forEach(function (p) { m[p.type] = p.value; });
  const hour = m.hour === '24' ? '00' : m.hour;
  return String(fmt)
    .replace(/yyyy/g, m.year).replace(/MM/g, m.month).replace(/dd/g, m.day)
    .replace(/HH/g, hour).replace(/mm/g, m.minute).replace(/ss/g, m.second);
}

const Utilities = {
  DigestAlgorithm: { SHA_256: 'SHA_256' },
  computeDigest(alg, value) {
    return Array.from(crypto.createHash('sha256').update(String(value), 'utf8').digest());
  },
  formatDate: formatDate,
  getUuid() { return crypto.randomUUID(); },
  base64Decode(data) {
    return Array.from(Buffer.from(String(data).replace(/^data:[^;]+;base64,/, ''), 'base64'));
  },
  newBlob(bytes, type, name) {
    return { bytes: Buffer.from(bytes || []), type: type, name: name };
  },
  sleep() {}
};

const DriveApp = {
  Access: { ANYONE_WITH_LINK: 'ANYONE_WITH_LINK' },
  Permission: { VIEW: 'VIEW' },
  getFolderById(id) { return new DriveFolder(id); },
  createFolder() { return new DriveFolder('folder_' + crypto.randomUUID()); },
  getFoldersByName() {
    return { hasNext: function () { return false; }, next: function () { return null; } };
  }
};

const SpreadsheetApp = {
  openById(id) { return new Spreadsheet(id); },
  create() {
    const id = 'sheet_' + crypto.randomUUID();
    return new Spreadsheet(id);
  }
};

const PropertiesService = {
  getScriptProperties() {
    return {
      getProperty(k) { const v = store.props[k]; return v === undefined ? null : v; },
      setProperty(k, v) { store.props[k] = v; save(); return this; },
      deleteProperty(k) { delete store.props[k]; save(); return this; }
    };
  }
};

const Session = {
  getScriptTimeZone() { return TZ; },
  getActiveUser() { return { getEmail() { return 'local@base44.dev'; } }; }
};

const CacheService = {
  getScriptCache() {
    return {
      get(k) {
        const e = store.cache[k];
        if (!e) return null;
        if (e.exp && Date.now() > e.exp) { delete store.cache[k]; save(); return null; }
        return e.v;
      },
      put(k, v, ttl) {
        store.cache[k] = { v: String(v), exp: ttl ? Date.now() + ttl * 1000 : 0 };
        save();
        return this;
      },
      remove(k) { delete store.cache[k]; save(); return this; }
    };
  }
};

/* ===================== sandbox ===================== */

function createSandbox() {
  return {
    SpreadsheetApp: SpreadsheetApp,
    PropertiesService: PropertiesService,
    DriveApp: DriveApp,
    Utilities: Utilities,
    Session: Session,
    CacheService: CacheService,
    Logger: { log: function () {} },
    console: console
  };
}

module.exports = { createSandbox, DATA_DIR: DATA_DIR, IMG_DIR: IMG_DIR, DB_FILE: DB_FILE };
