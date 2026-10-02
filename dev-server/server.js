'use strict';
/**
 * Local preview server for the Apps Script web app.
 *
 *   GET  /                 Index.html rendered with the Apps Script include
 *                          template (Styles + AppJs) and the dev bridge
 *   GET  /dev-harness.js   google.script.run emulation for the browser
 *   GET  /img/<fileId>     images stored by the DriveApp shim
 *   POST /api/call         { fn, args } -> runs a function from Code.gs
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const shim = require('./appsscript-shim');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.PORT || 3000);
const HOST = '0.0.0.0';
const BRIDGE_TAG = '<script src="/dev-harness.js"></script>';

function escapeHtml(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

/** Evaluates the single template expression this project uses: include('Name'). */
function evalTemplate(expression) {
  const match = /include\(\s*['"]([\w.-]+)['"]\s*\)/.exec(expression);
  if (!match) return '';
  return fs.readFileSync(path.join(ROOT, match[1] + '.html'), 'utf8');
}

function renderIndex() {
  let html = fs.readFileSync(path.join(ROOT, 'Index.html'), 'utf8');
  html = html.replace(/<\?!=([\s\S]*?)\?>/g, (m, expr) => evalTemplate(expr));
  html = html.replace(/<\?=([\s\S]*?)\?>/g, (m, expr) => escapeHtml(evalTemplate(expr)));
  // Inject before the document's own closing body tag: AppJs.html contains the
  // text "</body>" inside a JS string, so a plain replace() would break it.
  const closing = html.lastIndexOf('</body>');
  if (closing === -1) return html + BRIDGE_TAG;
  return html.slice(0, closing) + BRIDGE_TAG + '\n' + html.slice(closing);
}

function send(res, status, body, contentType) {
  res.writeHead(status, {
    'Content-Type': contentType || 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 20 * 1024 * 1024) reject(new Error('الطلب كبير جدًا'));
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

async function handleCall(req, res) {
  let payload;
  try {
    payload = JSON.parse(await readBody(req) || '{}');
  } catch (e) {
    return send(res, 400, JSON.stringify({ ok: false, message: 'طلب غير صالح' }), 'application/json; charset=utf-8');
  }
  try {
    const result = shim.callFunction(payload.fn, payload.args);
    send(res, 200, JSON.stringify({ ok: true, result: result === undefined ? null : result }),
      'application/json; charset=utf-8');
  } catch (error) {
    const message = (error && error.message) || String(error);
    console.log('[dev-server] ' + payload.fn + ' -> ' + message);
    send(res, 200, JSON.stringify({ ok: false, message: message }), 'application/json; charset=utf-8');
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const route = url.pathname;

  if (req.method === 'POST' && route === '/api/call') return handleCall(req, res);

  if (req.method === 'GET' && route === '/dev-harness.js') {
    return send(res, 200, fs.readFileSync(path.join(__dirname, 'dev-harness.js'), 'utf8'),
      'text/javascript; charset=utf-8');
  }

  if (req.method === 'GET' && route.startsWith('/img/')) {
    const file = shim.getStoredFile(decodeURIComponent(route.slice('/img/'.length)));
    if (!file) return send(res, 404, 'not found');
    res.writeHead(200, { 'Content-Type': file.contentType, 'Cache-Control': 'no-store' });
    return res.end(file.bytes);
  }

  if (req.method === 'GET' && (route === '/' || route === '/index.html')) {
    try {
      return send(res, 200, renderIndex(), 'text/html; charset=utf-8');
    } catch (error) {
      console.error('[dev-server] failed to render Index.html:', error);
      return send(res, 500, 'تعذر تحميل الواجهة: ' + error.message);
    }
  }

  send(res, 404, 'not found');
});

server.listen(PORT, HOST, () => {
  console.log('[dev-server] listening on http://' + HOST + ':' + PORT +
    ' (data: ' + shim.DATA_DIR + ')');
});
