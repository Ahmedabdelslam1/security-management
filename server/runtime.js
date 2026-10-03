'use strict';
/**
 * Runs the repo's real Code.gs (Google Apps Script) inside a vm context with
 * emulated Apps Script globals, so the app can be exercised locally.
 * Code.gs is re-read from disk on every call: edits apply without a restart.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { buildGlobals } = require('./gas');

const CODE_FILE = path.join(__dirname, '..', 'Code.gs');

function createRuntime(store) {
  const sandbox = buildGlobals(store);
  sandbox.console = console;
  const context = vm.createContext(sandbox);
  let loadedSource = null;

  function load() {
    const source = fs.readFileSync(CODE_FILE, 'utf8');
    if (source === loadedSource) return false;
    vm.runInContext(source, context, { filename: 'Code.gs' });
    loadedSource = source;
    return true;
  }

  load();

  /* Mirrors the README's one-time `setup()` run: creates the sheets and the admin user. */
  function ensureSetup() {
    if (store.state.spreadsheetId) return false;
    if (typeof context.setup !== 'function') return false;
    context.setup();
    return true;
  }

  try {
    ensureSetup();
  } catch (e) {
    console.error('[runtime] setup() failed:', e && e.message);
  }

  function call(fnName, args) {
    if (typeof fnName !== 'string' || !/^[A-Za-z][A-Za-z0-9_]*$/.test(fnName) || fnName.endsWith('_')) {
      throw new Error('دالة غير معروفة: ' + fnName);
    }
    if (fnName === 'doGet') throw new Error('doGet ليس واجهة استدعاء');
    load(); // pick up Code.gs edits
    const fn = context[fnName];
    if (typeof fn !== 'function') throw new Error('دالة غير معروفة: ' + fnName);
    return fn.apply(null, Array.isArray(args) ? args : []);
  }

  function health() {
    try {
      load();
      return !!(store.state.spreadsheetId && typeof context.bootstrap === 'function');
    } catch (e) {
      return false;
    }
  }

  return { call, health };
}

module.exports = { createRuntime, CODE_FILE };
