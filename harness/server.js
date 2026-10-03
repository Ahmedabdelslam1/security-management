/**
 * Local host for the "إدارة الأمن" Google Apps Script web app.
 *
 * Google Apps Script cannot run outside Google's servers, so this host serves
 * the app's Index.html with a small `google.script.run` shim that forwards
 * calls to Code.gs, executed in a sandbox with the service stand-ins from
 * harness/apps-script.js. Data lives in DATA_DIR (outside the repository).
 *
 * Routes:
 *   GET  /                the app UI
 *   GET  /__gas/shim.js   browser shim (google.script.run + auto refresh)
 *   GET  /__gas/stamp     source mtime, used by the shim to reload on edit
 *   POST /__gas/exec      {"fn": "...", "args": [...]} -> Code.gs function
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { Store } = require('./store');
const { createHost } = require('./loader');

const PORT = Number(process.env.PORT || 3000);
const APP_DIR = process.env.APP_DIR || path.resolve(__dirname, '..');
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '.data');
const INDEX_FILE = path.join(APP_DIR, process.env.INDEX_FILE || 'Index.html');
const SERVER_FILE = path.join(APP_DIR, process.env.SERVER_FILE || 'Code.gs');
const SHIM_FILE = path.join(__dirname, 'client-shim.js');

const SHIM_TAG = '<script src="/__gas/shim.js"></script>';
const MAX_BODY = 80 * 1024 * 1024; // attendance/gate payloads carry base64 images

const store = new Store(DATA_DIR);
const host = createHost({ serverFile: SERVER_FILE, store });

function renderPage() {
  const html = fs.readFileSync(INDEX_FILE, 'utf8');
  if (html.indexOf(SHIM_TAG) !== -1) return html;
  const at = html.indexOf('<script>');
  if (at === -1) return html.replace('<head>', '<head>' + SHIM_TAG);
  return html.slice(0, at) + SHIM_TAG + '\n' + html.slice(at);
}

function stamp() {
  let newest = 0;
  [INDEX_FILE, SERVER_FILE].forEach(function (f) {
    try { newest = Math.max(newest, fs.statSync(f).mtimeMs); } catch (e) { /* missing file */ }
  });
  return String(Math.round(newest));
}

function sendJson(res, status, body) {
  const buf = Buffer.from(JSON.stringify(body));
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': buf.length });
  res.end(buf);
}

function sendText(res, status, text, type) {
  res.writeHead(status, { 'Content-Type': (type || 'text/plain') + '; charset=utf-8' });
  res.end(text);
}

const server = http.createServer(function (req, res) {
  const url = (req.url || '/').split('?')[0];

  if (req.method === 'GET' && url === '/') {
    try {
      sendText(res, 200, renderPage(), 'text/html');
    } catch (e) {
      sendText(res, 500, 'تعذر قراءة ' + path.basename(INDEX_FILE) + ': ' + e.message);
    }
    return;
  }

  if (req.method === 'GET' && url === '/__gas/shim.js') {
    res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(fs.readFileSync(SHIM_FILE));
    return;
  }

  if (req.method === 'GET' && url === '/__gas/stamp') {
    sendJson(res, 200, { stamp: stamp() });
    return;
  }

  if (req.method === 'POST' && url === '/__gas/exec') {
    let raw = '';
    req.on('data', function (chunk) {
      raw += chunk;
      if (raw.length > MAX_BODY) req.destroy();
    });
    req.on('end', function () {
      let body;
      try {
        body = JSON.parse(raw || '{}');
      } catch (e) {
        sendJson(res, 400, { ok: false, error: { message: 'طلب غير صالح' } });
        return;
      }
      try {
        const result = host.call(body.fn, body.args);
        sendJson(res, 200, { ok: true, result: result === undefined ? null : result });
      } catch (err) {
        sendJson(res, 200, { ok: false, error: { message: (err && err.message) || String(err) } });
      }
    });
    return;
  }

  sendText(res, 404, 'not found');
});

server.listen(PORT, '0.0.0.0', function () {
  console.log('Apps Script host on http://0.0.0.0:' + PORT);
  console.log('  ui:  ' + INDEX_FILE);
  console.log('  api: ' + SERVER_FILE);
  console.log('  data: ' + DATA_DIR);
});
