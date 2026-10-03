'use strict';
/**
 * Dev server for the Google Apps Script project in this repo.
 *
 *   GET  /                     -> Index.html, with the google.script.run shim injected
 *   GET  /__gas/client-shim.js -> browser shim
 *   GET  /__gas/live           -> SSE live-reload channel
 *   POST /__gas/api            -> { fn, args } dispatched into Code.gs
 *   GET  /healthz              -> readiness probe
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const { Store } = require('./store');
const { createRuntime, CODE_FILE } = require('./runtime');

const ROOT = path.join(__dirname, '..');
const PAGE_FILE = path.join(ROOT, 'Index.html');
const SHIM_FILE = path.join(__dirname, 'client-shim.js');
const PORT = Number(process.env.PORT || 3000);
const MAX_BODY = 12 * 1024 * 1024; // uploaded images arrive as base64 data URLs

const store = new Store();
const runtime = createRuntime(store);

const WATCHED = [PAGE_FILE, CODE_FILE];
const mtimes = new Map();
const clients = new Set();

function injectShim(html) {
  const tag = '<script src="/__gas/client-shim.js"></script>';
  if (html.indexOf(tag) !== -1) return html;
  // Must load before the app's own inline script, which feature-detects google.script.run.
  if (/<head[^>]*>/i.test(html)) return html.replace(/<head[^>]*>/i, (m) => m + '\n' + tag);
  return tag + '\n' + html;
}

function send(res, status, body, type) {
  res.writeHead(status, {
    'Content-Type': type || 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function broadcastReload() {
  clients.forEach((res) => {
    try {
      res.write('data: reload\n\n');
    } catch (e) {
      /* dropped client */
    }
  });
}

function pollSources() {
  let changed = false;
  WATCHED.forEach((file) => {
    try {
      const mtime = fs.statSync(file).mtimeMs;
      if (mtimes.has(file) && mtimes.get(file) !== mtime) changed = true;
      mtimes.set(file, mtime);
    } catch (e) {
      /* file missing: ignore */
    }
  });
  if (changed) broadcastReload();
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error('حجم الطلب كبير'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch (e) {
        reject(new Error('طلب غير صالح'));
      }
    });
    req.on('error', reject);
  });
}

async function handleApi(req, res) {
  let payload;
  try {
    payload = await readJson(req);
  } catch (e) {
    send(res, 400, JSON.stringify({ ok: false, error: e.message }), 'application/json; charset=utf-8');
    return;
  }
  let out;
  try {
    out = { ok: true, result: runtime.call(payload.fn, payload.args) };
  } catch (e) {
    console.error('[api] ' + payload.fn + ' failed: ' + (e && e.message));
    out = { ok: false, error: (e && e.message) || 'خطأ غير معروف' };
  }
  send(res, 200, JSON.stringify(out === undefined ? { ok: true, result: null } : out), 'application/json; charset=utf-8');
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const route = url.pathname;

  if (req.method === 'GET' && route === '/__gas/live') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-store',
      Connection: 'keep-alive'
    });
    res.write('retry: 1000\n\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }

  if (req.method === 'POST' && route === '/__gas/api') {
    handleApi(req, res);
    return;
  }

  if (req.method === 'GET' && route === '/__gas/client-shim.js') {
    send(res, 200, fs.readFileSync(SHIM_FILE), 'application/javascript; charset=utf-8');
    return;
  }

  if (req.method === 'GET' && route === '/healthz') {
    const ready = runtime.health();
    send(res, ready ? 200 : 503, ready ? 'ok' : 'starting', 'text/plain; charset=utf-8');
    return;
  }

  if (req.method === 'GET' && (route === '/' || route === '/index.html')) {
    try {
      send(res, 200, injectShim(fs.readFileSync(PAGE_FILE, 'utf8')), 'text/html; charset=utf-8');
    } catch (e) {
      send(res, 500, 'Index.html not found', 'text/plain; charset=utf-8');
    }
    return;
  }

  if (req.method === 'GET' && route === '/favicon.ico') {
    res.writeHead(204);
    res.end();
    return;
  }

  send(res, 404, 'Not found');
});

pollSources();
setInterval(pollSources, 1000).unref();

server.listen(PORT, '0.0.0.0', () => {
  console.log('[gas-preview] listening on http://0.0.0.0:' + PORT);
});
