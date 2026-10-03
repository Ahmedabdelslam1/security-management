'use strict';
/**
 * Persistence for the local Apps Script runtime.
 * Keeps the emulated spreadsheet/Drive state in a JSON file plus blob files.
 * Data lives outside the repo (DATA_DIR), so it never lands in git.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || path.join(os.tmpdir(), 'gas-preview-data');
const DB_FILE = path.join(DATA_DIR, 'db.json');
const BLOB_DIR = path.join(DATA_DIR, 'blobs');

function emptyState() {
  return { props: {}, spreadsheetId: '', spreadsheets: {}, folders: {}, files: {} };
}

class Store {
  constructor() {
    fs.mkdirSync(BLOB_DIR, { recursive: true });
    let loaded = {};
    try {
      loaded = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    } catch (e) {
      loaded = {};
    }
    this.state = Object.assign(emptyState(), loaded);
  }

  /** Synchronous write: the local dataset is small and must survive restarts. */
  save() {
    const tmp = DB_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.state));
    fs.renameSync(tmp, DB_FILE);
  }

  blobPath(id) {
    return path.join(BLOB_DIR, path.basename(String(id)) + '.bin');
  }

  writeBlob(id, buffer) {
    fs.writeFileSync(this.blobPath(id), buffer);
  }

  readBlob(id) {
    try {
      return fs.readFileSync(this.blobPath(id));
    } catch (e) {
      return null;
    }
  }

  deleteBlob(id) {
    try {
      fs.unlinkSync(this.blobPath(id));
    } catch (e) {
      /* already gone */
    }
  }
}

module.exports = { Store, DATA_DIR, DB_FILE };
