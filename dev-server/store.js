'use strict';
/**
 * Simple JSON-file persistence for the local Apps Script runtime.
 * Lives outside the repo (DATA_DIR is a docker volume) so the
 * simulated spreadsheet / Drive / script properties are never committed.
 */
const fs = require('fs');
const path = require('path');

const DIR = process.env.DATA_DIR || path.join(__dirname, '.data');
const DRIVE = path.join(DIR, 'drive');

fs.mkdirSync(DRIVE, { recursive: true });

function file(name) {
  return path.join(DIR, name);
}

function load(name, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file(name), 'utf8'));
  } catch (e) {
    return fallback;
  }
}

function save(name, data) {
  const tmp = file(name) + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, file(name));
}

module.exports = { DIR, DRIVE, load, save };
