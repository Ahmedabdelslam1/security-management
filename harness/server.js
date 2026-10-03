'use strict';
/*
 * Local development host for this Google Apps Script web app.
 *
 * The project is a Google Apps Script / HtmlService app: its "server" is Code.gs,
 * its database is a Google Sheet and its file store is Google Drive. To make it
 * runnable (and editable) in the sandbox, this harness:
 *   - renders Index.html the way HtmlService templates do (<?!= include('X') ?>)
 *   - injects a google.script.run shim that forwards calls over HTTP
 *   - executes Code.gs verbatim in a vm context with the GAS services emulated
 *
 * Code.gs is re-read on every call, so edits to it apply immediately.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const runtime = require('./gas-runtime');

const ROOT = path.join(__dirname, '..');
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';

const CODE_PATH = path.join(ROOT, 'Code.gs');
const SHIM_PATH = path.join(__dirname, 'client-shim.js');

/* ===================== Code.gs execution ===================== */

let cached = null; // { mtimeMs, app }

function loadApp() {
  const stat = fs.statSync(CODE_PATH);
  if (cached && cached.mtimeMs === stat.mtimeMs) return cached.app;

  const source = fs.readFileSync(CODE_PATH, 'utf8');
  const names = [];
  const re = /^function\s+([A-Za-z0-9_]+)/gm;
  let m;
  while ((m = re.exec(source)) !== null) names.push(m[1]);

  const context = vm.createContext(runtime.createSandbox());
  vm.runInContext(
    source + '\n;globalThis.__app = {' + names.join(', ') + '};',
    context,
    { filename: 'Code.gs' }
  );

  cached = { mtimeMs: stat.mtimeMs, app: context.__app };
  console.log('[harness] compiled Code.gs (' + names.length + ' functions)');
  return cached.app;
}

/* ===================== HtmlService templating ===================== */

function readTemplate(name) {
  return fs.readFileSync(path.join(ROOT, name + '.html'), 'utf8');
}

// AppJs.html is served as an external script rather than inlined: it contains the
// literal string '<script>setTimeout(...)<\/script>' for its print windows, and an
// inline <script> block gets truncated by the HTML parser at that point.
function renderIndex() {
  let html = readTemplate('Index');
  html = html.replace(/<\?!=\s*include\('([\w.-]+)'\)\s*;?\s*\?>/g, function (_, name) {
    if (name === 'AppJs') return '<script src="/__gas/appjs.js"></script>';
    return readTemplate(name);
  });
  // The shim must exist before AppJs.html runs.
  const shimTag = '<script src="/__gas/shim.js"></script>\n';
  return html.replace('<body>', '<body>\n' + shimTag);
}

function clientScript() {
  return readTemplate('AppJs')
    .replace(/^\s*<script[^>]*>\s*/, '')
    .replace(/\s*<\/script>\s*$/, '');
}

/* ===================== HTTP ===================== */

function send(res, status, body, type) {
  res.writeHead(status, {
    'Content-Type': type || 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function readBody(req) {
  return new Promise(function (resolve, reject) {
    let data = '';
    req.on('data', function (chunk) {
      data += chunk;
      if (data.length > 40 * 1024 * 1024) reject(new Error('payload too large'));
    });
    req.on('end', function () { resolve(data); });
    req.on('error', reject);
  });
}

async function rpc(req, res) {
  let payload;
  try {
    payload = JSON.parse(await readBody(req));
  } catch (e) {
    return send(res, 400, JSON.stringify({ ok: false, error: { message: 'طلب غير صالح' } }), 'application/json; charset=utf-8');
  }

  const fn = String(payload.fn || '');
  const args = Array.isArray(payload.args) ? payload.args : [];

  if (!/^api[A-Z]/.test(fn) && fn !== 'setup') {
    return send(res, 400, JSON.stringify({ ok: false, error: { message: 'دالة غير معروفة: ' + fn } }), 'application/json; charset=utf-8');
  }

  try {
    const app = loadApp();
    if (typeof app[fn] !== 'function') throw new Error('دالة غير معروفة: ' + fn);
    const result = app[fn].apply(null, args);
    send(res, 200, JSON.stringify({ ok: true, result: result === undefined ? null : result }), 'application/json; charset=utf-8');
  } catch (e) {
    console.error('[harness] ' + fn + ' failed:', e && e.message);
    send(res, 200, JSON.stringify({ ok: false, error: { message: (e && e.message) || 'حدث خطأ' } }), 'application/json; charset=utf-8');
  }
}

const server = http.createServer(async function (req, res) {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;

  if (p === '/__gas/health') return send(res, 200, 'ok');
  if (p === '/__gas/shim.js') return send(res, 200, fs.readFileSync(SHIM_PATH, 'utf8'), 'application/javascript; charset=utf-8');
  if (p === '/__gas/appjs.js') {
    try {
      return send(res, 200, clientScript(), 'application/javascript; charset=utf-8');
    } catch (e) {
      return send(res, 500, 'console.error(' + JSON.stringify(String(e.message)) + ');', 'application/javascript; charset=utf-8');
    }
  }
  if (p === '/__gas/rpc' && req.method === 'POST') return rpc(req, res);
  if (p === '/favicon.ico') return send(res, 204, '');

  if (p === '/' || p === '/index.html') {
    try {
      return send(res, 200, renderIndex(), 'text/html; charset=utf-8');
    } catch (e) {
      console.error('[harness] render failed:', e);
      return send(res, 500, 'Render error: ' + e.message, 'text/plain; charset=utf-8');
    }
  }

  send(res, 404, 'Not found');
});

server.listen(PORT, HOST, function () {
  console.log('[harness] Google Apps Script dev host on http://' + HOST + ':' + PORT);
  console.log('[harness] data dir: ' + runtime.DATA_DIR);
});
