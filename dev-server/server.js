'use strict';
/**
 * Local dev server for the Apps Script web app.
 *
 *   GET  /                 -> the web app (Code.gs doGet output + google.script.run shim)
 *   POST /api/exec         -> { fn, args } dispatched to Code.gs
 *   GET  /api/health       -> liveness probe used by the compose healthcheck
 *   GET  /__livereload     -> SSE; reloads the page when the app source changes
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const runtime = require('./gas-runtime');

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';

/* ---------- live reload ---------- */
const WATCH = ['Index.html', 'Code.gs', 'AppJs.html', 'Styles.html', 'Index2.html']
  .map((f) => path.join(runtime.REPO, f))
  .concat(fs.readdirSync(__dirname).map((f) => path.join(__dirname, f)));

const clients = new Set();
function broadcast() {
  clients.forEach((res) => {
    try { res.write('data: reload\n\n'); } catch (e) { clients.delete(res); }
  });
}

let stamps = {};
function snapshot() {
  const out = {};
  WATCH.forEach((f) => {
    try { out[f] = fs.statSync(f).mtimeMs; } catch (e) { out[f] = 0; }
  });
  return out;
}
stamps = snapshot();
setInterval(() => {
  const next = snapshot();
  const changed = Object.keys(next).some((f) => next[f] !== stamps[f]);
  stamps = next;
  if (changed) broadcast();
}, 900);

/* ---------- helpers ---------- */
function sendJson(res, code, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (c) => {
      raw += c;
      if (raw.length > 40 * 1024 * 1024) { reject(new Error('payload too large')); req.destroy(); }
    });
    req.on('end', () => resolve(raw));
    req.on('error', reject);
  });
}

/* ---------- server ---------- */
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;

  if (p === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('ok');
  }

  if (p === '/__livereload') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no'
    });
    res.write(': connected\n\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }

  if (p === '/api/exec' && req.method === 'POST') {
    let payload;
    try {
      payload = JSON.parse(await readBody(req) || '{}');
    } catch (e) {
      return sendJson(res, 400, { ok: false, error: 'طلب غير صالح' });
    }
    try {
      const result = runtime.callFunction(payload.fn, payload.args);
      const body = JSON.stringify({ ok: true, result: result === undefined ? null : result });
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(body);
    } catch (e) {
      return sendJson(res, 200, { ok: false, error: runtime.errorMessage(e) });
    }
  }

  if (p === '/' || p === '/index.html' || p === '/exec') {
    try {
      const html = runtime.renderPage();
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(html);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Failed to render app: ' + runtime.errorMessage(e));
    }
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not found');
});

server.listen(PORT, HOST, () => {
  console.log('[base44] Apps Script dev server listening on http://' + HOST + ':' + PORT);
  console.log('[base44] data dir: ' + require('./store').DIR);
});
