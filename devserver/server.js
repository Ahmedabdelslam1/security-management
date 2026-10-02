'use strict';
/**
 * سيرفر التطوير المحلي لمشروع Google Apps Script.
 *
 * - يقدّم صفحة التطبيق Index.html وينفّذ ملف Code.gs الحقيقي دون أي تعديل
 *   عبر المحاكاة المحلية (gas-env.js).
 * - يحوّل أي جافاسكربت مضمّن داخل الصفحة إلى ملف خارجي، لأن بعض دوال الطباعة
 *   تحتوي على النص "<script>" داخل سلاسل نصية، وهو ما يفسد تحليل الصفحة عند
 *   تمريرها عبر وسيط المعاينة.
 * - مسارات: /__gas/run (جسر google.script.run)، /__gas/file/<id> (الصور)،
 *   /__gas/version (إعادة التحميل التلقائي للمعاينة).
 *
 * بدون أي مكتبات خارجية: وحدات Node المدمجة فقط.
 * أداة تطوير فقط: لا تؤثر على نشر التطبيق على Apps Script.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const gasEnv = require('./gas-env');

const ROOT = path.resolve(__dirname, '..');
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '.data');
const PORT = Number(process.env.PORT || 3000);
const PAGE_FILE = 'Index.html';
const INCLUDE_RE = /<\?!=\s*include\(\s*['"]([^'"]+)['"]\s*\)\s*;?\s*\?>/g;

const SOURCE_FILES = [PAGE_FILE, 'Code.gs', 'devserver/gas-shim.js', 'devserver/gas-preview-patch.js'];

let inlineScripts = { version: '', files: {} };

/* ---------- Code.gs : سياق يُعاد تحميله عند تغيّر الملف ---------- */
let ctx = null;
let ctxMtime = 0;

function context() {
  const codePath = path.join(ROOT, 'Code.gs');
  const mtime = fs.statSync(codePath).mtimeMs;
  if (!ctx || mtime !== ctxMtime) {
    ctx = gasEnv.createContext(fs.readFileSync(codePath, 'utf8'), DATA_DIR);
    ctxMtime = mtime;
    console.log('[dev] Code.gs محمّل (' + new Date().toISOString() + ')');
  }
  return ctx;
}

/* ---------- ملفات الواجهة ---------- */
function moduleFile(name) {
  const candidates = [name, name.charAt(0).toUpperCase() + name.slice(1)];
  for (const c of candidates) {
    const f = path.join(ROOT, c + '.html');
    if (fs.existsSync(f)) return f;
  }
  return null;
}

function stripScriptTags(source) {
  return String(source).replace(/^\s*<script[^>]*>/i, '').replace(/<\/script>\s*$/i, '');
}

/* يستخرج كل كتل <script> المضمّنة (بلا src) إلى ملفات منفصلة. */
function externalizeScripts(html, versionKey) {
  const files = {};
  let n = 0;
  const out = html.replace(/<script(?![^>]*\bsrc=)([^>]*)>([\s\S]*?)<\/script>/gi, function (m, attrs, body) {
    if (/\btype\s*=/i.test(attrs)) return m;
    n++;
    const name = 'inline-' + n + '.js';
    files[name] = body;
    return '<script' + attrs + ' src="/__gas/inline/' + name + '"></script>';
  });
  inlineScripts = { version: versionKey, files: files };
  return out;
}

function renderPage() {
  let html = fs.readFileSync(path.join(ROOT, PAGE_FILE), 'utf8');

  // حلّ تعليمات include إن وُجدت (صفحات Apps Script ذات القوالب)
  html = html.replace(INCLUDE_RE, function (m, name) {
    const f = moduleFile(name);
    if (!f) return '';
    const content = fs.readFileSync(f, 'utf8');
    if (/^\s*<script[\s>]/i.test(content)) {
      return '<script src="/__gas/module/' + encodeURIComponent(name) + '.js"></script>';
    }
    return content;
  });

  html = externalizeScripts(html, version());

  // الجسر (google.script.run) قبل أي سكربت آخر
  html = html.replace(/<head(\s[^>]*)?>/i, function (m) { return m + '\n<script src="/__gas/shim.js"></script>'; });

  const patchTag = '<script src="/__gas/patch.js"></script>';
  const bodyClose = html.lastIndexOf('</body>');
  if (bodyClose !== -1) html = html.slice(0, bodyClose) + patchTag + '\n' + html.slice(bodyClose);
  else html += patchTag;
  return html;
}

function version() {
  const h = crypto.createHash('md5');
  SOURCE_FILES.forEach(function (rel) {
    try { h.update(rel + ':' + fs.statSync(path.join(ROOT, rel)).mtimeMs); } catch (e) { /* غير موجود */ }
  });
  return h.digest('hex');
}

/* ---------- الردود ---------- */
function send(res, code, type, body) {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

function sendJSON(res, code, obj) { send(res, code, 'application/json; charset=utf-8', JSON.stringify(obj)); }

function sendFile(res, filePath, type) {
  const body = fs.readFileSync(filePath);
  res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store', 'Content-Length': body.length });
  res.end(body);
}

function readBody(req, cb) {
  let size = 0;
  const chunks = [];
  req.on('data', function (c) {
    size += c.length;
    if (size > 30 * 1024 * 1024) { req.destroy(); return; }
    chunks.push(c);
  });
  req.on('end', function () { cb(Buffer.concat(chunks).toString('utf8')); });
  req.on('error', function () { cb(''); });
}

function handleRun(req, res) {
  readBody(req, function (raw) {
    let payload;
    try { payload = JSON.parse(raw || '{}'); } catch (e) { return sendJSON(res, 200, { ok: false, error: 'طلب غير صالح' }); }
    const fn = String(payload.fn || '');
    const args = Array.isArray(payload.args) ? payload.args : [];
    try {
      const value = context().call(fn, args);
      sendJSON(res, 200, { ok: true, value: value === undefined ? null : value });
    } catch (e) {
      const message = (e && e.message) ? e.message : String(e);
      if (message !== 'SESSION') console.error('[dev] ' + fn + ' -> ' + message);
      sendJSON(res, 200, { ok: false, error: message });
    }
  });
}

/* ---------- السيرفر ---------- */
const server = http.createServer(function (req, res) {
  const p = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);

  try {
    if (p === '/' || p === '/index.html' || p === '/' + PAGE_FILE) {
      return send(res, 200, 'text/html; charset=utf-8', renderPage());
    }

    if (p === '/__gas/shim.js') return sendFile(res, path.join(__dirname, 'gas-shim.js'), 'application/javascript; charset=utf-8');
    if (p === '/__gas/patch.js') return sendFile(res, path.join(__dirname, 'gas-preview-patch.js'), 'application/javascript; charset=utf-8');

    if (p.indexOf('/__gas/inline/') === 0) {
      const name = p.slice('/__gas/inline/'.length);
      if (inlineScripts.version !== version()) renderPage();
      if (!inlineScripts.files[name]) { res.writeHead(404); return res.end('not found'); }
      return send(res, 200, 'application/javascript; charset=utf-8', inlineScripts.files[name]);
    }

    if (p.indexOf('/__gas/module/') === 0) {
      const f = moduleFile(p.slice('/__gas/module/'.length).replace(/\.js$/, ''));
      if (!f) { res.writeHead(404); return res.end('not found'); }
      return send(res, 200, 'application/javascript; charset=utf-8', stripScriptTags(fs.readFileSync(f, 'utf8')));
    }

    if (p === '/__gas/version') return sendJSON(res, 200, { v: version() });

    if (p === '/__gas/health') {
      const c = context();
      return sendJSON(res, 200, { ok: true, sheets: c.sheets().length, page: PAGE_FILE });
    }

    if (p === '/__gas/run' && req.method === 'POST') return handleRun(req, res);

    if (p.indexOf('/__gas/file/') === 0) {
      const file = context().file(p.slice('/__gas/file/'.length));
      if (!file) { res.writeHead(404); return res.end('not found'); }
      const buf = Buffer.from(file.base64 || '', 'base64');
      res.writeHead(200, { 'Content-Type': file.type || 'application/octet-stream', 'Content-Length': buf.length, 'Cache-Control': 'no-store' });
      return res.end(buf);
    }

    if (p === '/favicon.ico') { res.writeHead(204); return res.end(); }

    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404');
  } catch (e) {
    console.error('[dev] خطأ في السيرفر:', e);
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('500 ' + ((e && e.message) || ''));
  }
});

fs.mkdirSync(DATA_DIR, { recursive: true });
context();
server.listen(PORT, '0.0.0.0', function () {
  console.log('[dev] إدارة الأمن — http://0.0.0.0:' + PORT + ' (البيانات: ' + DATA_DIR + ')');
});

['SIGTERM', 'SIGINT'].forEach(function (sig) {
  process.on(sig, function () { try { ctx && ctx.store.writeNow(); } catch (e) { } process.exit(0); });
});
