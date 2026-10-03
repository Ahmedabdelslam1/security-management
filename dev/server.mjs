// Local dev entry point: serves the app's own Index.html on port 3000 and
// routes google.script.run calls into Code.gs running under the emulated
// Google services. No npm dependencies — Node standard library only.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './appsscript/runtime.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(here, '..');
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const DATA_DIR = process.env.DATA_DIR || path.join(here, '.data');

const INDEX_FILE = path.join(ROOT, 'Index.html');
const CODE_FILE = path.join(ROOT, 'Code.gs');
const SHIM_FILE = path.join(here, 'client-shim.js');

const runtime = createRuntime({ codeFile: CODE_FILE, dataDir: DATA_DIR });

// Index.html is read per request so UI edits show up on refresh; Code.gs is
// compiled once at boot (the container runs with --watch to restart on edits).
function renderPage() {
  const shim = fs.readFileSync(SHIM_FILE, 'utf8');
  const html = fs.readFileSync(INDEX_FILE, 'utf8');
  const tag = '<script>/* base44: local google.script.run shim */\n' + shim + '\n</script>';
  return /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, (m) => m + '\n' + tag) : tag + html;
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(payload));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
    try {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(renderPage());
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('render error: ' + e.message);
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/exec') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 20e6) req.destroy(); // base64 photos can be a few MB
    });
    req.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body || '{}');
      } catch (e) {
        return sendJson(res, 400, { ok: false, error: 'طلب غير صالح' });
      }
      const out = runtime.call(payload.fn, payload.args);
      sendJson(res, out.ok ? 200 : 400, out);
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not found');
});

server.listen(PORT, HOST, () => {
  console.log(`[base44] Apps Script runtime listening on http://${HOST}:${PORT} (data: ${DATA_DIR})`);
});
