'use strict';
/**
 * Local development shim for the Google Apps Script runtime.
 *
 * The project (Code.gs) is written for Google Apps Script, which only runs on
 * Google's servers. This module emulates the services Code.gs actually uses
 * (SpreadsheetApp, DriveApp, CacheService, PropertiesService, Utilities,
 * Session, HtmlService) so the very same Code.gs can be executed locally and
 * previewed in the browser.
 *
 * Data lives outside the repository (APP_DATA_DIR, defaults to /data in the
 * container) so nothing generated at runtime is committed:
 *   database.json   sheets, one spreadsheet
 *   properties.json script properties (DB_ID, IMG_FOLDER)
 *   files.json      uploaded images metadata
 *   files/<id>      uploaded image bytes
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const CODE_FILE = path.join(ROOT, 'Code.gs');
const DATA_DIR = process.env.APP_DATA_DIR || path.join(__dirname, '.data');
const FILES_DIR = path.join(DATA_DIR, 'files');

fs.mkdirSync(FILES_DIR, { recursive: true });

const DB_FILE = path.join(DATA_DIR, 'database.json');
const PROPS_FILE = path.join(DATA_DIR, 'properties.json');
const FILES_FILE = path.join(DATA_DIR, 'files.json');

/* ===================== persistence helpers ===================== */

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return fallback;
  }
}

let db = readJson(DB_FILE, { spreadsheets: {} });
let props = readJson(PROPS_FILE, {});
let filesMeta = readJson(FILES_FILE, {});

const saveDb = () => fs.writeFileSync(DB_FILE, JSON.stringify(db));
const saveProps = () => fs.writeFileSync(PROPS_FILE, JSON.stringify(props));
const saveFiles = () => fs.writeFileSync(FILES_FILE, JSON.stringify(filesMeta));

/* ===================== SpreadsheetApp ===================== */

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
      const line = this.sheet._rows[this.row - 1 + r] || [];
      const rowOut = [];
      for (let c = 0; c < this.numCols; c++) {
        const v = line[this.col - 1 + c];
        rowOut.push(v === undefined ? '' : v);
      }
      out.push(rowOut);
    }
    return out;
  }

  setValues(values) {
    for (let r = 0; r < values.length; r++) {
      const src = values[r] || [];
      for (let c = 0; c < src.length; c++) {
        this.sheet._setCell(this.row - 1 + r, this.col - 1 + c, src[c]);
      }
    }
    this.sheet._save();
  }

  setValue(value) {
    this.setValues([[value]]);
  }
}

class Sheet {
  constructor(ss, name) {
    this.ss = ss;
    this.name = name;
  }

  get _rows() {
    return this.ss._sheets[this.name];
  }

  _setCell(rowIdx, colIdx, value) {
    const rows = this._rows;
    while (rows.length <= rowIdx) rows.push([]);
    const line = rows[rowIdx];
    while (line.length <= colIdx) line.push('');
    line[colIdx] = value;
  }

  _save() {
    saveDb();
  }

  getName() {
    return this.name;
  }

  getLastRow() {
    return this._rows.length;
  }

  getLastColumn() {
    return this._rows.reduce((max, line) => Math.max(max, line.length), 0);
  }

  getRange(row, col, numRows, numCols) {
    return new Range(this, row, col, numRows === undefined ? 1 : numRows,
      numCols === undefined ? 1 : numCols);
  }

  getDataRange() {
    return new Range(this, 1, 1, Math.max(this.getLastRow(), 1), Math.max(this.getLastColumn(), 1));
  }

  appendRow(values) {
    const line = [];
    (Array.isArray(values) ? values : [values]).forEach((v) => line.push(v));
    this._rows.push(line);
    this._save();
  }

  deleteRow(row) {
    this._rows.splice(row - 1, 1);
    this._save();
  }
}

class Spreadsheet {
  constructor(id, name) {
    this.id = id;
    this.name = name;
  }

  get _sheets() {
    return db.spreadsheets[this.id].sheets;
  }

  getId() {
    return this.id;
  }

  getName() {
    return this.name;
  }

  getSheetByName(name) {
    return this._sheets[name] ? new Sheet(this, name) : null;
  }

  insertSheet(name) {
    if (!this._sheets[name]) this._sheets[name] = [];
    saveDb();
    return new Sheet(this, name);
  }
}

const SpreadsheetApp = {
  create(name) {
    const id = Utilities.getUuid();
    db.spreadsheets[id] = { name: String(name || ''), sheets: {} };
    saveDb();
    return new Spreadsheet(id, name);
  },
  openById(id) {
    if (!db.spreadsheets[id]) throw new Error('لم يتم العثور على قاعدة البيانات');
    return new Spreadsheet(id, db.spreadsheets[id].name);
  },
};

/* ===================== DriveApp ===================== */

function fileObject(id) {
  return {
    getId: () => id,
    getName: () => (filesMeta[id] || {}).name || '',
    setSharing: () => fileObject(id),
  };
}

function folderObject(id) {
  return {
    getId: () => id,
    getName: () => (db.folders[id] || {}).name || '',
    createFile(blob) {
      const fileId = Utilities.getUuid();
      const bytes = blob && blob.bytes ? blob.bytes : Buffer.alloc(0);
      fs.writeFileSync(path.join(FILES_DIR, fileId), bytes);
      filesMeta[fileId] = {
        name: (blob && blob.name) || 'image.jpg',
        contentType: (blob && blob.contentType) || 'image/jpeg',
      };
      saveFiles();
      return fileObject(fileId);
    },
  };
}

const DriveApp = {
  Access: { ANYONE_WITH_LINK: 'ANYONE_WITH_LINK', ANYONE: 'ANYONE', PRIVATE: 'PRIVATE' },
  Permission: { VIEW: 'VIEW', EDIT: 'EDIT' },
  getFolderById(id) {
    if (!db.folders[id]) throw new Error('المجلد غير موجود');
    return folderObject(id);
  },
  getFoldersByName(name) {
    const found = Object.keys(db.folders).filter((id) => db.folders[id].name === name);
    let i = 0;
    return { hasNext: () => i < found.length, next: () => folderObject(found[i++]) };
  },
  createFolder(name) {
    const id = Utilities.getUuid();
    db.folders = db.folders || {};
    db.folders[id] = { name: String(name) };
    saveDb();
    return folderObject(id);
  },
};

function getStoredFile(id) {
  if (!filesMeta[id]) return null;
  const file = path.join(FILES_DIR, id);
  if (!fs.existsSync(file)) return null;
  return { bytes: fs.readFileSync(file), contentType: filesMeta[id].contentType };
}

/* ===================== CacheService / PropertiesService ===================== */

const cacheStore = new Map();

const CacheService = {
  getScriptCache: () => ({
    put(key, value, seconds) {
      const ttl = (Number(seconds) || 600) * 1000;
      cacheStore.set(String(key), { value: String(value), expires: Date.now() + ttl });
    },
    get(key) {
      const entry = cacheStore.get(String(key));
      if (!entry) return null;
      if (entry.expires < Date.now()) {
        cacheStore.delete(String(key));
        return null;
      }
      return entry.value;
    },
    remove(key) {
      cacheStore.delete(String(key));
    },
  }),
};

const PropertiesService = {
  getScriptProperties: () => ({
    getProperty: (key) => (props[key] === undefined ? null : props[key]),
    setProperty(key, value) {
      props[key] = String(value);
      saveProps();
    },
    deleteProperty(key) {
      delete props[key];
      saveProps();
    },
  }),
};

/* ===================== Utilities / Session / HtmlService ===================== */

function formatDate(date, tz, format) {
  const d = date instanceof Date ? date : new Date(date);
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz || 'UTC',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).formatToParts(d);
  const get = (type) => (parts.find((p) => p.type === type) || {}).value || '';
  const values = {
    yyyy: get('year'), MM: get('month'), dd: get('day'),
    HH: get('hour') === '24' ? '00' : get('hour'),
    mm: get('minute'), ss: get('second'),
  };
  return String(format).replace(/yyyy|MM|dd|HH|mm|ss/g, (token) => values[token]);
}

const Utilities = {
  DigestAlgorithm: { MD5: 'MD5', SHA_1: 'SHA_1', SHA_256: 'SHA_256' },
  computeDigest(algorithm, value) {
    const alg = String(algorithm).toLowerCase().replace(/_/g, '');
    return Array.from(crypto.createHash(alg === 'sha256' ? 'sha256' : 'sha1').update(String(value)).digest());
  },
  getUuid: () => crypto.randomUUID(),
  formatDate,
  base64Decode: (b64) => Buffer.from(String(b64), 'base64'),
  newBlob(bytes, contentType, name) {
    const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
    return { bytes: buf, contentType, name, getBytes: () => buf };
  },
};

const Session = {
  getScriptTimeZone: () => process.env.TZ || 'Africa/Cairo',
  getActiveUser: () => ({ getEmail: () => 'dev@localhost' }),
};

const HtmlService = {
  XFrameOptionsMode: { ALLOWALL: 'ALLOWALL', DEFAULT: 'DEFAULT' },
  createTemplateFromFile: () => ({
    setTitle() { return this; },
    addMetaTag() { return this; },
    setXFrameOptionsMode() { return this; },
    evaluate() { return { getContent: () => '' }; },
  }),
  createHtmlOutputFromFile: (name) => ({ getContent: () => `<!-- ${name} -->` }),
};

/* ===================== runtime ===================== */

let context = null;
let loadedMtimeMs = 0;

function load() {
  const code = fs.readFileSync(CODE_FILE, 'utf8');
  context = vm.createContext({
    console,
    SpreadsheetApp, DriveApp, CacheService, PropertiesService, Utilities, Session, HtmlService,
  });
  vm.runInContext(code, context, { filename: 'Code.gs' });
  loadedMtimeMs = fs.statSync(CODE_FILE).mtimeMs;
  return context;
}

/** Reloads Code.gs automatically when the file changes on disk. */
function appContext() {
  const mtimeMs = fs.statSync(CODE_FILE).mtimeMs;
  if (!context || mtimeMs !== loadedMtimeMs) {
    load();
    console.log('[dev-server] loaded Code.gs');
  }
  return context;
}

/** Runs a server-side function from Code.gs the way google.script.run does. */
function callFunction(name, args) {
  const fn = appContext()[name];
  if (typeof fn !== 'function') throw new Error('دالة غير معروفة: ' + name);
  return fn.apply(null, args || []);
}

module.exports = { callFunction, getStoredFile, DATA_DIR };
