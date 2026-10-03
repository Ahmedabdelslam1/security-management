// Loads the project's real Code.gs inside a Node VM with emulated Google
// globals, and exposes its functions over a tiny call() API.
// Code.gs is executed as-is: no porting, no rewriting.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { openDb } from './store.mjs';
import { createSpreadsheetApp } from './sheets.mjs';
import { createDriveApp } from './drive.mjs';
import {
  createUtilities,
  createPropertiesService,
  createCacheService,
  createLockService,
  createHtmlService
} from './services.mjs';

// Never reachable from the browser: these would let a request run arbitrary code.
const BLOCKED = /^(eval|Function)$/;

export function createRuntime({ codeFile, dataDir }) {
  const db = openDb(dataDir);

  const sandbox = {
    SpreadsheetApp: createSpreadsheetApp(db),
    DriveApp: createDriveApp(db, dataDir),
    Utilities: createUtilities(),
    PropertiesService: createPropertiesService(db),
    CacheService: createCacheService(),
    LockService: createLockService(),
    HtmlService: createHtmlService(),
    console
  };

  const context = vm.createContext(sandbox, { name: 'apps-script' });
  vm.runInContext(fs.readFileSync(codeFile, 'utf8'), context, { filename: path.basename(codeFile) });

  // Function declarations become own properties of the context's global object.
  const appFunctions = new Set(vm.runInContext(
    'Object.getOwnPropertyNames(this).filter(function (k) { return typeof this[k] === "function"; })',
    context
  ));

  return {
    call(name, args) {
      if (typeof name !== 'string' || !appFunctions.has(name) || BLOCKED.test(name)) {
        return { ok: false, error: 'دالة غير معروفة: ' + name };
      }
      try {
        const result = sandbox[name].apply(null, Array.isArray(args) ? args : []);
        return { ok: true, result: result === undefined ? null : result };
      } catch (e) {
        return { ok: false, error: String((e && e.message) || e) };
      }
    },
    functions: () => Array.from(appFunctions).sort()
  };
}
