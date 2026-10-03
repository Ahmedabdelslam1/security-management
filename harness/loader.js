/**
 * Loads Code.gs into a fresh Apps Script-like sandbox and calls its functions.
 * The file is re-read whenever its mtime changes, so editing server code shows
 * up on the next request without restarting the container.
 */
const fs = require('fs');
const vm = require('vm');
const { buildServices } = require('./apps-script');

function createHost({ serverFile, store }) {
  let cached = null;
  let cachedMtime = -1;

  function load() {
    const mtime = fs.statSync(serverFile).mtimeMs;
    if (cached && mtime === cachedMtime) return cached;
    const code = fs.readFileSync(serverFile, 'utf8');
    const sandbox = Object.assign({ console }, buildServices(store));
    const context = vm.createContext(sandbox);
    vm.runInContext(code, context, { filename: serverFile });
    cached = context;
    cachedMtime = mtime;
    return cached;
  }

  return {
    call(fn, args) {
      if (!fn || typeof fn !== 'string') throw new Error('اسم الدالة مطلوب');
      const context = load();
      if (typeof context[fn] !== 'function') throw new Error('دالة غير معروفة: ' + fn);
      return context[fn].apply(null, args || []);
    },
    stamp() {
      try { return fs.statSync(serverFile).mtimeMs; } catch (e) { return 0; }
    }
  };
}

module.exports = { createHost };
