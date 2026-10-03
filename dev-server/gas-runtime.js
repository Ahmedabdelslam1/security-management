'use strict';
/**
 * Minimal local emulation of the Google Apps Script runtime.
 *
 * Code.gs runs unmodified inside a `vm` context where the Google globals it
 * uses (SpreadsheetApp, DriveApp, Utilities, CacheService, LockService,
 * PropertiesService, HtmlService) are provided by this module. Persistence is
 * JSON on disk, so the simulated spreadsheet / Drive / script properties
 * survive restarts. Every request re-compiles Code.gs, which mirrors Apps
 * Script's per-execution sandbox and makes backend edits live.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const store = require('./store');
const { SHIM_SRC } = require('./client-shim');

const REPO = path.resolve(__dirname, '..');
const DEFAULT_MAX_ROWS = 1000;
const DEFAULT_MAX_COLS = 26;

/* ------------------------------------------------------------------ */
/* spreadsheet                                                         */
/* ------------------------------------------------------------------ */

class Sheet {
  constructor(data) {
    this.data = data;
    if (!this.data.rows) this.data.rows = [];
    if (!this.data.maxRows) this.data.maxRows = DEFAULT_MAX_ROWS;
    if (!this.data.maxCols) this.data.maxCols = DEFAULT_MAX_COLS;
  }
  getId() { return 0; }
  getName() { return this.data.name || ''; }
  getMaxRows() { return this.data.maxRows; }
  getMaxColumns() { return this.data.maxCols; }
  _row(i) { const r = this.data.rows; while (r.length <= i) r.push([]); return r[i]; }
  getLastRow() {
    const r = this.data.rows;
    let last = 0;
    for (let i = 0; i < r.length; i++) {
      const row = r[i] || [];
      for (let j = 0; j < row.length; j++) {
        if (row[j] !== '' && row[j] != null) { last = i + 1; break; }
      }
    }
    return last;
  }
  getLastColumn() {
    const r = this.data.rows;
    let last = 0;
    for (let i = 0; i < r.length; i++) {
      const row = r[i] || [];
      for (let j = 0; j < row.length; j++) {
        if (row[j] !== '' && row[j] != null) last = Math.max(last, j + 1);
      }
    }
    return last;
  }
  getRange(row, col, numRows, numColumns) {
    return new Range(this, row, col, numRows == null ? 1 : numRows, numColumns == null ? 1 : numColumns);
  }
  insertRowsAfter(afterRow, howMany) {
    this.data.maxRows = Math.max(this.data.maxRows, afterRow) + howMany;
  }
  insertColumnsAfter(afterColumn, howMany) {
    this.data.maxCols = Math.max(this.data.maxCols, afterColumn) + howMany;
  }
  deleteRows(rowPosition, howMany) {
    this.data.rows.splice(rowPosition - 1, howMany);
  }
  insertRowBefore() { return this; }
  appendRow(values) {
    const at = this.getLastRow();
    this.getRange(at + 1, 1, 1, values.length).setValues([values]);
  }
  setFrozenRows() { }
  setRightToLeft() { }
  setColumnWidth() { }
}

class Range {
  constructor(sheet, row, col, numRows, numColumns) {
    this.sheet = sheet;
    this.row = row;
    this.col = col;
    this.numRows = numRows;
    this.numColumns = numColumns;
  }
  getValues() {
    const out = [];
    for (let i = 0; i < this.numRows; i++) {
      const row = this.sheet.data.rows[this.row - 1 + i] || [];
      const line = [];
      for (let j = 0; j < this.numColumns; j++) {
        const v = row[this.col - 1 + j];
        line.push(v == null ? '' : v);
      }
      out.push(line);
    }
    return out;
  }
  setValues(values) {
    for (let i = 0; i < values.length; i++) {
      const row = this.sheet._row(this.row - 1 + i);
      for (let j = 0; j < values[i].length; j++) {
        const v = values[i][j];
        row[this.col - 1 + j] = v == null ? '' : (v instanceof Date ? v : String(v));
      }
    }
    return this;
  }
  getValue() {
    const row = this.sheet.data.rows[this.row - 1] || [];
    const v = row[this.col - 1];
    return v == null ? '' : v;
  }
  setValue(value) {
    const row = this.sheet._row(this.row - 1);
    row[this.col - 1] = value == null ? '' : String(value);
    return this;
  }
  clearContent() {
    for (let i = 0; i < this.numRows; i++) {
      const row = this.sheet.data.rows[this.row - 1 + i];
      if (!row) continue;
      for (let j = 0; j < this.numColumns; j++) row[this.col - 1 + j] = '';
    }
    return this;
  }
  /* formatting calls the app only uses for chaining */
  setNumberFormat() { return this; }
  setFontWeight() { return this; }
  setFontSize() { return this; }
  setFontColor() { return this; }
  setBackground() { return this; }
  setHorizontalAlignment() { return this; }
  setVerticalAlignment() { return this; }
  setWrap() { return this; }
  setValuesFormat() { return this; }
}

class Spreadsheet {
  constructor(state) {
    if (!state.ss) {
      state.ss = {
        id: 'ss' + crypto.randomUUID().replace(/-/g, '').slice(0, 16),
        name: 'إدارة الأمن - البيانات',
        url: 'https://docs.google.com/spreadsheets/d/local',
        sheets: {}
      };
    }
    if (!state.ss.sheets) state.ss.sheets = {};
    this.state = state;
  }
  getId() { return this.state.ss.id; }
  getName() { return this.state.ss.name; }
  getUrl() { return this.state.ss.url; }
  getSheetByName(name) {
    const data = this.state.ss.sheets[name];
    if (!data) return null;
    data.name = name;
    return new Sheet(data);
  }
  insertSheet(name) {
    if (this.state.ss.sheets[name]) throw new Error('A sheet with the name "' + name + '" already exists.');
    this.state.ss.sheets[name] = { name, maxRows: DEFAULT_MAX_ROWS, maxCols: DEFAULT_MAX_COLS, rows: [] };
    return new Sheet(this.state.ss.sheets[name]);
  }
  getSheets() { return Object.keys(this.state.ss.sheets).map((n) => this.getSheetByName(n)); }
  deleteSheet() { }
}

/* ------------------------------------------------------------------ */
/* Drive                                                               */
/* ------------------------------------------------------------------ */

class Blob {
  constructor(bytes, contentType, name) {
    this.bytes = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
    this.contentType = contentType || 'application/octet-stream';
    this.name = name || '';
  }
  getBytes() { return Array.from(this.bytes); }
  getContentType() { return this.contentType; }
  getName() { return this.name; }
  getDataAsString() { return this.bytes.toString('utf8'); }
}

class DriveFile {
  constructor(state, meta) { this.state = state; this.meta = meta; }
  getId() { return this.meta.id; }
  getName() { return this.meta.name; }
  getBlob() {
    const p = path.join(store.DRIVE, this.meta.id);
    return new Blob(fs.readFileSync(p), this.meta.contentType, this.meta.name);
  }
  setTrashed() {
    try { fs.unlinkSync(path.join(store.DRIVE, this.meta.id)); } catch (e) { /* already gone */ }
    this.state.drive.files = this.state.drive.files.filter((f) => f.id !== this.meta.id);
    return this;
  }
}

class DriveFolder {
  constructor(state, meta) { this.state = state; this.meta = meta; }
  getId() { return this.meta.id; }
  getName() { return this.meta.name; }
  createFile(blob) {
    const id = 'f' + crypto.randomUUID().replace(/-/g, '').slice(0, 20);
    fs.writeFileSync(path.join(store.DRIVE, id), blob.bytes);
    const meta = { id, name: blob.getName(), contentType: blob.getContentType(), folderId: this.meta.id };
    this.state.drive.files.push(meta);
    return new DriveFile(this.state, meta);
  }
}

function makeDriveApp(state, props) {
  const drive = state.drive;
  const folderByName = (name) => drive.folders.filter((f) => f.name === name);
  return {
    getFoldersByName(name) {
      const list = folderByName(name);
      let i = 0;
      return { hasNext: () => i < list.length, next: () => new DriveFolder(state, list[i++]) };
    },
    createFolder(name) {
      const meta = { id: 'd' + crypto.randomUUID().replace(/-/g, '').slice(0, 20), name };
      drive.folders.push(meta);
      return new DriveFolder(state, meta);
    },
    getFolderById(id) {
      const meta = drive.folders.filter((f) => f.id === id)[0];
      if (!meta) throw new Error('No item with the given ID could be found.');
      return new DriveFolder(state, meta);
    },
    getFileById(id) {
      const meta = drive.files.filter((f) => f.id === id)[0];
      if (!meta) throw new Error('No item with the given ID could be found.');
      return new DriveFile(state, meta);
    },
    createFile(blob) {
      let meta = drive.folders.filter((f) => f.name === 'root')[0];
      if (!meta) { meta = { id: 'droot', name: 'root' }; drive.folders.push(meta); }
      return new DriveFolder(state, meta).createFile(blob);
    }
  };
}

/* ------------------------------------------------------------------ */
/* Utilities                                                           */
/* ------------------------------------------------------------------ */

function formatDate(date, tz, fmt) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz || 'Etc/UTC', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
  }).formatToParts(date);
  const p = {};
  parts.forEach((x) => { p[x.type] = x.value; });
  const hh = p.hour === '24' ? '00' : p.hour;
  return String(fmt)
    .replace(/yyyy/g, p.year).replace(/MM/g, p.month).replace(/dd/g, p.day)
    .replace(/HH/g, hh).replace(/mm/g, p.minute).replace(/ss/g, p.second);
}

const Utilities = {
  DigestAlgorithm: { MD5: 'MD5', SHA_1: 'SHA_1', SHA_256: 'SHA_256', SHA_384: 'SHA_384', SHA_512: 'SHA_512' },
  Charset: { UTF_8: 'UTF_8', US_ASCII: 'US_ASCII', ISO_8859_1: 'ISO_8859_1' },
  getUuid: () => crypto.randomUUID(),
  computeDigest(algorithm, value) {
    const alg = { MD5: 'md5', SHA_1: 'sha1', SHA_256: 'sha256', SHA_384: 'sha384', SHA_512: 'sha512' }[algorithm] || 'sha256';
    const buf = crypto.createHash(alg).update(typeof value === 'string' ? value : Buffer.from(value)).digest();
    return Array.from(buf).map((b) => (b > 127 ? b - 256 : b)); // Apps Script returns signed bytes
  },
  base64Encode(bytes) { return Buffer.from(bytes || []).toString('base64'); },
  base64Decode(str) { return Array.from(Buffer.from(String(str || ''), 'base64')).map((b) => (b > 127 ? b - 256 : b)); },
  newBlob(bytes, contentType, name) { return new Blob(Buffer.from(bytes || []), contentType, name); },
  formatDate,
  sleep: () => { }
};

/* ------------------------------------------------------------------ */
/* cache / properties / locks / html                                   */
/* ------------------------------------------------------------------ */

const cacheStore = new Map(); // survives across executions, like script cache

function makeCacheService() {
  return {
    getScriptCache() {
      return {
        get(key) {
          const hit = cacheStore.get(key);
          if (!hit) return null;
          if (hit.exp && hit.exp < Date.now()) { cacheStore.delete(key); return null; }
          return hit.v;
        },
        put(key, value, seconds) {
          cacheStore.set(key, { v: String(value), exp: seconds ? Date.now() + seconds * 1000 : 0 });
        },
        remove(key) { cacheStore.delete(key); },
        removeAll(keys) { (keys || []).forEach((k) => cacheStore.delete(k)); }
      };
    },
    getUserCache() { return this.getScriptCache(); }
  };
}

function makePropertiesService(state) {
  const read = (k) => (state.props[k] === undefined ? null : state.props[k]);
  return {
    getScriptProperties: () => ({
      getProperty: read,
      setProperty(k, v) { state.props[k] = String(v); },
      deleteProperty(k) { delete state.props[k]; },
      getProperties: () => Object.assign({}, state.props)
    }),
    getUserProperties: () => ({ getProperty: () => null, setProperty: () => { }, getProperties: () => ({}) }),
    getDocumentProperties: () => ({ getProperty: () => null, setProperty: () => { }, getProperties: () => ({}) })
  };
}

const LockService = {
  getScriptLock: () => ({ waitLock: () => true, tryLock: () => true, releaseLock: () => { }, hasLock: () => true }),
  getUserLock: () => ({ waitLock: () => true, tryLock: () => true, releaseLock: () => { } }),
  getDocumentLock: () => ({ waitLock: () => true, tryLock: () => true, releaseLock: () => { } })
};

/* ------------------------------------------------------------------ */
/* HTML service                                                        */
/* ------------------------------------------------------------------ */

function readHtmlSource(name) {
  const wanted = String(name).toLowerCase() + '.html';
  const files = fs.readdirSync(REPO).filter((f) => fs.statSync(path.join(REPO, f)).isFile());
  const hit = files.filter((f) => f.toLowerCase() === wanted)[0]
    || files.filter((f) => f.toLowerCase() === 'index.html')[0];
  if (!hit) throw new Error('HTML file not found: ' + name);
  return fs.readFileSync(path.join(REPO, hit), 'utf8');
}

function injectShim(html) {
  const tag = '<script>' + SHIM_SRC + '</script>';
  if (/<head[^>]*>/i.test(html)) return html.replace(/<head[^>]*>/i, (m) => m + '\n' + tag);
  if (/<body[^>]*>/i.test(html)) return html.replace(/<body[^>]*>/i, (m) => m + '\n' + tag);
  return tag + html;
}

function makeHtmlService() {
  const mk = (html) => ({
    _html: html,
    setTitle() { return this; },
    addMetaTag() { return this; },
    setFaviconUrl() { return this; },
    setXFrameOptionsMode() { return this; },
    setSandboxMode() { return this; },
    getContent() { return this._html; }
  });
  return {
    XFrameOptionsMode: { ALLOWALL: 'ALLOWALL', DEFAULT: 'DEFAULT' },
    SandboxMode: { IFRAME: 'IFRAME', EMULATED: 'EMULATED', NATIVE: 'NATIVE' },
    createHtmlOutputFromFile: (name) => mk(injectShim(readHtmlSource(name))),
    createHtmlOutput: (html) => mk(injectShim(String(html))),
    createTemplateFromFile: (name) => mk(injectShim(readHtmlSource(name)))
  };
}

/* ------------------------------------------------------------------ */
/* execution                                                           */
/* ------------------------------------------------------------------ */

function loadState() {
  return {
    ss: store.load('ss.json', null),
    drive: store.load('drive.json', { folders: [], files: [] }),
    props: store.load('props.json', {})
  };
}

function saveState(state) {
  if (state.ss) store.save('ss.json', state.ss);
  store.save('drive.json', state.drive);
  store.save('props.json', state.props);
}

function compile(state) {
  const spreadsheet = new Spreadsheet(state);
  const sandbox = {
    console,
    SpreadsheetApp: {
      getActiveSpreadsheet: () => spreadsheet,
      getActive: () => spreadsheet,
      openById: () => spreadsheet,
      create: () => spreadsheet
    },
    DriveApp: makeDriveApp(state, state.props),
    Utilities,
    CacheService: makeCacheService(),
    PropertiesService: makePropertiesService(state),
    LockService,
    HtmlService: makeHtmlService(),
    Logger: { log: () => { } }
  };
  vm.createContext(sandbox);
  const code = fs.readFileSync(path.join(REPO, 'Code.gs'), 'utf8');
  vm.runInContext(code, sandbox, { filename: 'Code.gs' });
  return sandbox;
}

/** Run one Apps Script function the way a google.script.run call would. */
function callFunction(name, args) {
  const state = loadState();
  const sandbox = compile(state);
  if (typeof sandbox[name] !== 'function') throw new Error('Unknown server function: ' + name);
  const result = sandbox[name].apply(null, args || []);
  saveState(state);
  return result;
}

/** Render the web app entry point (doGet), falling back to the raw HTML file. */
function renderPage() {
  const state = loadState();
  try {
    const sandbox = compile(state);
    const out = sandbox.doGet();
    saveState(state);
    return out.getContent();
  } catch (e) {
    return injectShim(readHtmlSource('index'));
  }
}

function errorMessage(e) {
  if (!e) return 'خطأ غير معروف';
  return String((e && e.message) || e).replace(/^Error:\s*/, '');
}

module.exports = { callFunction, renderPage, readHtmlSource, injectShim, errorMessage, REPO };
