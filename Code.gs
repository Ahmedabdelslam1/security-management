/**
 * إدارة الأمن — الخلفية (Google Apps Script)
 * ------------------------------------------------------------
 * الإعداد:
 *  1) أنشئ Google Sheet جديدًا ثم: الإضافات/الامتدادات > Apps Script.
 *  2) الصق هذا الملف في Code.gs، وأنشئ ملف HTML باسم index والصق فيه ملف index.html.
 *  3) (اختياري) شغّل الدالة setup() مرة واحدة لمنح الصلاحيات وإنشاء الجداول.
 *  4) نشر > نشر كتطبيق ويب: التنفيذ بصفتي، الوصول: أي شخص. افتح الرابط.
 *  الدخول الأول:  admin / admin123  (غيّر كلمة المرور فورًا من زر 🔑)
 *  لو نسيت كلمة مرور المدير: شغّل resetAdminPassword() من المحرر.
 */

var TZ = 'Africa/Cairo';
var STATUSES = ['حضور', 'حضور + وقت اضافى', 'حضور + مبيت'];
var EXTRA_STATUSES = ['حضور + وقت اضافى', 'حضور + مبيت'];
var PERMS = ['workers', 'attendance', 'reports', 'gate'];
var SESSION_TTL = 21600;            // كاش الجلسة (أقصى مدة يسمح بها الكاش = 6 ساعات)
var SESSION_MAX_IDLE = 180 * 24 * 3600 * 1000;  // الجلسة تبقى محفوظة حتى تسجيل الخروج (تنتهي فقط بعد 180 يومًا بلا استخدام)
var ONLINE_MS = 5 * 60 * 1000;      // متصل = نشاط خلال 5 دقائق
var MAX_LOG_ROWS = 5000;

var SHEETS = {
  Workers:    ['id', 'name', 'card', 'phone', 'wage', 'hours', 'lastSet', 'cardImg', 'photo'],
  Attendance: ['date', 'wid', 'name', 'status', 'loc', 'wage', 'xh', 'notes', 'settleId', 'paidAmt'],
  Locations:  ['name'],
  Users:      ['username', 'name', 'salt', 'hash', 'status', 'role', 'perms', 'lastLogin', 'lastActive'],
  Settlements:['id', 'date', 'from', 'to', 'wid', 'name', 'days', 'amount', 'user', 'createdAt', 'bonus', 'ded', 'tax', 'net', 'ot'],
  Gate:       ['id', 'seq', 'weekday', 'date', 'plate', 'time', 'driver', 'statement', 'notes', 'managers', 'host', 'images', 'createdBy', 'createdAt'],
  Log:        ['time', 'user', 'action', 'page', 'details']
};
var SCHEMA_CHECKED_ = {};

/* ===================== الصفحة ===================== */
function doGet() {
  return HtmlService.createHtmlOutputFromFile('index')
    .setTitle('إدارة الأمن')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function setup() {
  Object.keys(SHEETS).forEach(function (n) { sh_(n); });
  ensureAdmin_();
  return 'تم الإعداد: ' + ss_().getUrl();
}

function resetAdminPassword() {
  var salt = Utilities.getUuid();
  var users = readAll_('Users');
  var found = false;
  users.forEach(function (u) {
    if (u.username === 'admin') { u.salt = salt; u.hash = hash_(salt, 'admin123'); u.status = 'approved'; u.role = 'admin'; found = true; }
  });
  if (!found) { ensureAdmin_(); return; }
  writeAll_('Users', users);
}

/* ===================== أدوات الشيت ===================== */
function ss_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('SS_ID');
  if (id) return SpreadsheetApp.openById(id);
  var a = SpreadsheetApp.getActiveSpreadsheet();
  if (a) return a;
  var n = SpreadsheetApp.create('إدارة الأمن - البيانات');
  props.setProperty('SS_ID', n.getId());
  return n;
}

function sh_(name) {
  var s = ss_();
  var h = SHEETS[name];
  var sheet = s.getSheetByName(name);
  if (!sheet) {
    sheet = s.insertSheet(name);
    sheet.getRange(1, 1, sheet.getMaxRows(), h.length).setNumberFormat('@');
    sheet.getRange(1, 1, 1, h.length).setValues([h]).setFontWeight('bold');
    sheet.setFrozenRows(1);
    sheet.setRightToLeft(true);
    SCHEMA_CHECKED_[name] = 1;
  } else if (!SCHEMA_CHECKED_[name]) {
    SCHEMA_CHECKED_[name] = 1;
    if (sheet.getMaxColumns() < h.length) sheet.insertColumnsAfter(sheet.getMaxColumns(), h.length - sheet.getMaxColumns());
    var cur = sheet.getRange(1, 1, 1, h.length).getValues()[0];
    var same = h.every(function (k, i) { return String(cur[i]) === k; });
    if (!same) {
      sheet.getRange(1, 1, sheet.getMaxRows(), h.length).setNumberFormat('@');
      sheet.getRange(1, 1, 1, h.length).setValues([h]).setFontWeight('bold');
    }
  }
  return sheet;
}

function str_(v) {
  if (v instanceof Date) return Utilities.formatDate(v, TZ, 'yyyy-MM-dd');
  return v == null ? '' : String(v);
}

function readAll_(name) {
  var sheet = sh_(name), h = SHEETS[name], n = sheet.getLastRow();
  if (n < 2) return [];
  var vals = sheet.getRange(2, 1, n - 1, h.length).getValues();
  return vals.filter(function (r) { return String(r[0]) !== ''; }).map(function (r) {
    var o = {};
    h.forEach(function (k, i) { o[k] = str_(r[i]); });
    return o;
  });
}

function writeAll_(name, objs) {
  var sheet = sh_(name), h = SHEETS[name], last = sheet.getLastRow();
  if (last > 1) sheet.getRange(2, 1, last - 1, h.length).clearContent();
  if (!objs.length) return;
  var rows = objs.map(function (o) { return h.map(function (k) { return o[k] == null ? '' : String(o[k]); }); });
  var need = rows.length + 1 - sheet.getMaxRows();
  if (need > 0) sheet.insertRowsAfter(sheet.getMaxRows(), need);
  sheet.getRange(2, 1, rows.length, h.length).setNumberFormat('@').setValues(rows);
}

function locked_(fn) {
  var lock = LockService.getScriptLock();
  lock.waitLock(25000);
  try { return fn(); } finally { lock.releaseLock(); }
}

function now_() { return Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd HH:mm:ss'); }
function today_() { return Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd'); }
function clip_(v, n) { return String(v == null ? '' : v).trim().slice(0, n); }
function num_(v, d) { var x = Number(v); return isFinite(x) ? x : (d || 0); }
function validDate_(d) { return /^\d{4}-\d{2}-\d{2}$/.test(String(d)); }

/* ===================== المستخدمون والجلسات ===================== */
function hash_(salt, pass) {
  var d = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, salt + ':' + pass, Utilities.Charset.UTF_8);
  return d.map(function (b) { return ('0' + (b & 255).toString(16)).slice(-2); }).join('');
}

function ensureAdmin_() {
  if (readAll_('Users').length) return;
  var salt = Utilities.getUuid();
  writeAll_('Users', [{
    username: 'admin', name: 'مدير النظام', salt: salt, hash: hash_(salt, 'admin123'),
    status: 'approved', role: 'admin', perms: '{}', lastLogin: '', lastActive: ''
  }]);
}

function parsePerms_(p) {
  if (p && typeof p === 'object') return p;   // كانت تُفرَّغ الصلاحيات عند تحليلها مرتين
  try { var o = JSON.parse(p || '{}'); return o && typeof o === 'object' ? o : {}; } catch (e) { return {}; }
}

function can_(u, perm) {
  if (u.role === 'admin') return true;
  if (perm === 'admin') return false;
  var list = Array.isArray(perm) ? perm : [perm];
  return list.some(function (p) { return u.perms && u.perms[p]; });
}

function auth_(token, perm) {
  if (!token) throw new Error('SESSION');
  var cache = CacheService.getScriptCache();
  var un = cache.get('S_' + token);
  if (!un) un = sessionRestore_(token);
  if (!un) throw new Error('SESSION');
  var u = readAll_('Users').filter(function (x) { return x.username === un; })[0];
  if (!u || u.status !== 'approved') throw new Error('SESSION');
  u.perms = parsePerms_(u.perms);
  cache.put('S_' + token, un, SESSION_TTL);
  if (perm && !can_(u, perm)) throw new Error('غير مصرح لك بهذا الإجراء');
  return u;
}

/* الجلسات تُحفظ في خصائص السكريبت (دائمة) بجانب الكاش، فلا تنتهي بانتهاء الكاش ولا بإغلاق المتصفح */
function sessionSave_(token, username) {
  CacheService.getScriptCache().put('S_' + token, username, SESSION_TTL);
  PropertiesService.getScriptProperties().setProperty('SS_' + token, username + '|' + Date.now());
}
function sessionRestore_(token) {
  var props = PropertiesService.getScriptProperties();
  var v = props.getProperty('SS_' + token);
  if (!v) return '';
  var p = String(v).split('|'), un = p[0], seen = Number(p[1]) || 0;
  if (Date.now() - seen > SESSION_MAX_IDLE) { props.deleteProperty('SS_' + token); return ''; }
  if (Date.now() - seen > 24 * 3600 * 1000) props.setProperty('SS_' + token, un + '|' + Date.now());
  return un;
}
function sessionPrune_() {
  var props = PropertiesService.getScriptProperties(), all = props.getProperties();
  Object.keys(all).forEach(function (k) {
    if (k.indexOf('SS_') !== 0) return;
    var seen = Number(String(all[k]).split('|')[1]) || 0;
    if (Date.now() - seen > SESSION_MAX_IDLE) props.deleteProperty(k);
  });
}

function updateUser_(username, fields) {
  var sheet = sh_('Users'), h = SHEETS.Users, n = sheet.getLastRow();
  if (n < 2) return;
  var names = sheet.getRange(2, 1, n - 1, 1).getValues();
  for (var i = 0; i < names.length; i++) {
    if (String(names[i][0]) === username) {
      Object.keys(fields).forEach(function (k) {
        sheet.getRange(i + 2, h.indexOf(k) + 1).setValue(String(fields[k]));
      });
      return;
    }
  }
}

function publicUser_(u) {
  return { name: u.name, username: u.username, role: u.role, status: u.status, perms: parsePerms_(u.perms) };
}

function login(username, password) {
  ensureAdmin_();
  username = clip_(username, 40).toLowerCase();
  var cache = CacheService.getScriptCache();
  var fkey = 'F_' + username;
  if (Number(cache.get(fkey) || 0) >= 5) throw new Error('تم تجاوز عدد المحاولات، حاول بعد 10 دقائق');
  var u = readAll_('Users').filter(function (x) { return x.username === username; })[0];
  if (!u || hash_(u.salt, String(password || '')) !== u.hash) {
    cache.put(fkey, String(Number(cache.get(fkey) || 0) + 1), 600);
    throw new Error('بيانات الدخول غير صحيحة');
  }
  if (u.status === 'pending') throw new Error('حسابك بانتظار موافقة الإدارة');
  if (u.status !== 'approved') throw new Error('تم إيقاف هذا الحساب');
  cache.remove(fkey);
  var token = Utilities.getUuid() + Utilities.getUuid();
  sessionSave_(token, username);
  sessionPrune_();
  updateUser_(username, { lastLogin: now_(), lastActive: String(Date.now()) });
  log_(u.name, 'دخول', 'النظام', username);
  return { token: token };
}

function logout(token) {
  try {
    var u = auth_(token);
    log_(u.name, 'خروج', 'النظام', u.username);
  } catch (e) { /* تجاهل */ }
  if (token) {
    CacheService.getScriptCache().remove('S_' + token);
    PropertiesService.getScriptProperties().deleteProperty('SS_' + token);
  }
  return true;
}

function register(name, username, password) {
  name = clip_(name, 60);
  username = clip_(username, 30).toLowerCase();
  password = String(password || '');
  if (name.length < 2) throw new Error('اكتب الاسم بالكامل');
  if (!/^[a-z0-9_.]{3,30}$/.test(username)) throw new Error('اسم المستخدم: حروف إنجليزية صغيرة وأرقام فقط (3 أحرف على الأقل)');
  if (password.length < 6) throw new Error('كلمة المرور 6 أحرف على الأقل');
  return locked_(function () {
    ensureAdmin_();
    var users = readAll_('Users');
    if (users.some(function (u) { return u.username === username; })) throw new Error('اسم المستخدم مستخدم من قبل');
    if (users.filter(function (u) { return u.status === 'pending'; }).length >= 50) throw new Error('عدد الطلبات المعلقة كبير، تواصل مع الإدارة');
    var salt = Utilities.getUuid();
    users.push({ username: username, name: name, salt: salt, hash: hash_(salt, password), status: 'pending', role: 'user', perms: '{}', lastLogin: '', lastActive: '' });
    writeAll_('Users', users);
    log_(name, 'طلب تسجيل', 'النظام', username);
    return true;
  });
}

function changePassword(token, oldPass, newPass) {
  var u = auth_(token);
  newPass = String(newPass || '');
  if (newPass.length < 6) throw new Error('كلمة المرور الجديدة 6 أحرف على الأقل');
  if (hash_(u.salt, String(oldPass || '')) !== u.hash) throw new Error('كلمة المرور الحالية غير صحيحة');
  var salt = Utilities.getUuid();
  updateUser_(u.username, { salt: salt, hash: hash_(salt, newPass) });
  log_(u.name, 'تغيير كلمة المرور', 'النظام', u.username);
  return true;
}

function ping(token) {
  var u = auth_(token);
  updateUser_(u.username, { lastActive: String(Date.now()) });
  return true;
}

/* ===================== السجل ===================== */
function log_(user, action, page, details) {
  var sheet = sh_('Log');
  sheet.appendRow([now_(), clip_(user, 60), clip_(action, 60), clip_(page, 60), clip_(details, 200)]);
  if (sheet.getLastRow() > MAX_LOG_ROWS + 1) sheet.deleteRows(2, 1000);
}

function addLog(token, action, page, details) {
  var u = auth_(token);
  log_(u.name, action, page, details);
  return true;
}

/* ===================== تحميل البيانات ===================== */
function lastSetMap_() {
  var m = {};
  readAll_('Settlements').forEach(function (r) { if (r.to && (!m[r.wid] || r.to > m[r.wid])) m[r.wid] = r.to; });
  return m;
}

function workerOut_(w, full, ls) {
  var legacy = String(w.lastSet || ''), led = (ls && ls[w.id]) || '';
  return {
    id: w.id, name: w.name,
    card: full ? w.card : '', phone: full ? w.phone : '',
    wage: num_(w.wage), hours: num_(w.hours, 8) || 8, lastSet: legacy > led ? legacy : led,
    hasCard: !!w.cardImg, hasPhoto: !!w.photo
  };
}

/* قيمة اليوم = الأجر + الساعات الإضافية × أجر الساعة */
function recValue_(r, w) {
  var h = w ? (num_(w.wage) / (num_(w.hours, 8) || 8)) : 0;
  return Math.round((num_(r.wage) + num_(r.xh) * h) * 100) / 100;
}

/* ترحيل لمرة واحدة: (1) الأيام المسوّاة حسب "آخر تسوية" القديم تُعلَّم مصروفة، (2) يُسجَّل المبلغ المصروف فعليًا لكل يوم مصروف */
function migrate_() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('MIG_PAIDAMT')) return;
  var workers = {}, ls = {};
  readAll_('Workers').forEach(function (w) { workers[w.id] = w; if (w.lastSet) ls[w.id] = w.lastSet; });
  var legacyDone = props.getProperty('MIG_SETTLE_ID');
  var att = readAll_('Attendance'), changed = false;
  att.forEach(function (r) {
    if (!legacyDone && !r.settleId && ls[r.wid] && r.date <= ls[r.wid] && r.status && r.status !== '--') { r.settleId = 'legacy'; changed = true; }
    if (r.settleId && r.paidAmt === '') { r.paidAmt = String(recValue_(r, workers[r.wid])); changed = true; }
  });
  if (changed) writeAll_('Attendance', att);
  props.setProperty('MIG_SETTLE_ID', '1');
  props.setProperty('MIG_PAIDAMT', '1');
}

function bootstrap(token) {
  var u = auth_(token);
  if (!PropertiesService.getScriptProperties().getProperty('MIG_PAIDAMT')) locked_(migrate_);
  updateUser_(u.username, { lastActive: String(Date.now()) });
  var full = can_(u, 'workers');
  var ls = lastSetMap_();
  var workers = readAll_('Workers').map(function (w) { return workerOut_(w, full, ls); });
  var att = readAll_('Attendance').map(function (r) {
    return { date: r.date, wid: r.wid, name: r.name, status: r.status, loc: r.loc, wage: num_(r.wage), xh: num_(r.xh), notes: r.notes, settleId: r.settleId, paidAmt: num_(r.paidAmt) };
  });
  var out = { user: publicUser_(u), workers: workers, att: att, locs: allLocs_(att) };
  if (u.role === 'admin') out.users = readAll_('Users').map(publicUser_);
  return out;
}

function allLocs_(att) {
  var seen = {}, list = [];
  readAll_('Locations').map(function (x) { return x.name; })
    .concat((att || []).map(function (r) { return r.loc; }))
    .forEach(function (l) { l = String(l || '').trim(); if (l && !seen[l]) { seen[l] = 1; list.push(l); } });
  return list;
}

/* ===================== الحضور والتسوية ===================== */
function saveDay(token, date, recs) {
  var u = auth_(token, 'attendance');
  if (!validDate_(date)) throw new Error('تاريخ غير صحيح');
  if (!Array.isArray(recs)) throw new Error('بيانات غير صحيحة');
  return locked_(function () {
    var workers = {};
    readAll_('Workers').forEach(function (w) { workers[w.id] = w; });
    /* الأيام المسوّاة مغلقة: لا تُعدَّل ولا تُحذف، وتبقى كما سُجّلت وقت التسوية */
    var existing = readAll_('Attendance'), closed = {};
    existing.forEach(function (r) { if (r.date === date && r.settleId) closed[r.wid] = r; });
    var fresh = [], seen = {}, blocked = [];
    recs.forEach(function (r) {
      var w = workers[String(r.wid)];
      if (!w || seen[w.id]) return;
      if (STATUSES.indexOf(r.status) === -1) return;
      seen[w.id] = 1;
      var extra = EXTRA_STATUSES.indexOf(r.status) !== -1;
      var c = closed[w.id];
      if (c) {
        var same = c.status === r.status && String(c.loc) === clip_(r.loc, 80) &&
          num_(c.xh) === (extra ? Math.max(0, num_(r.xh)) : 0) && String(c.notes) === clip_(r.notes, 300);
        if (!same) blocked.push(w.name);
        return;
      }
      fresh.push({
        date: date, wid: w.id, name: w.name, status: r.status, loc: clip_(r.loc, 80),
        wage: num_(w.wage), xh: extra ? Math.max(0, num_(r.xh)) : 0, notes: clip_(r.notes, 300),
        settleId: '', paidAmt: ''
      });
    });
    var all = existing.filter(function (r) { return r.date !== date || r.settleId; }).concat(fresh);
    writeAll_('Attendance', all);
    var known = readAll_('Locations').map(function (x) { return x.name; });
    var add = [];
    fresh.forEach(function (r) { if (r.loc && known.indexOf(r.loc) === -1 && add.indexOf(r.loc) === -1) add.push(r.loc); });
    if (add.length) writeAll_('Locations', known.concat(add).map(function (n) { return { name: n }; }));
    log_(u.name, 'حفظ يوم حضور', 'الحضور', date + ' (' + fresh.length + ')' + (blocked.length ? ' — محاولة تعديل أيام مغلقة: ' + blocked.join('، ') : ''));
    var att = all.filter(function (r) { return r.date === date; }).map(function (r) { return { date: r.date, wid: r.wid, name: r.name, status: r.status, loc: r.loc, wage: num_(r.wage), xh: num_(r.xh), notes: r.notes, settleId: r.settleId, paidAmt: num_(r.paidAmt) }; });
    return { att: att, locs: allLocs_(readAll_('Attendance')), locked: blocked };
  });
}

/* التسوية = صرف فعلي: لكل يوم يُسجَّل المبلغ المصروف (paidAmt).
 * - يوم جديد (له مكان حضور) ⇒ يُصرف كامل قيمته.
 * - يوم سبق صرفه ثم عُدِّل (ساعات إضافية، موقف، مكان...) ⇒ يُصرف الفرق فقط (قد يكون سالبًا = استرداد).
 * - يوم يُسجَّل لاحقًا داخل فترة سبقت تسويتها يبقى مستحقًا لأنه لم يُصرف فعلًا. */
function settleWorkers(token, ids, from, to, adj, loc, setDate) {
  var u = auth_(token, ['workers', 'attendance']);
  if (!validDate_(to)) throw new Error('تاريخ غير صحيح');
  if (from && !validDate_(from)) throw new Error('تاريخ غير صحيح');
  if (setDate && !validDate_(setDate)) throw new Error('يوم التسوية غير صحيح');
  if (setDate && String(setDate) > today_()) throw new Error('يوم التسوية لا يمكن أن يكون في المستقبل');
  from = from || '0000-00-00';
  adj = (adj && typeof adj === 'object') ? adj : {};
  if (!Array.isArray(ids) || !ids.length) throw new Error('حدد عاملًا واحدًا على الأقل');
  return locked_(function () {
    var workers = {};
    readAll_('Workers').forEach(function (w) { workers[w.id] = w; });
    var sid = 's' + Date.now() + Math.floor(Math.random() * 1000);
    var att = readAll_('Attendance'), per = {}, keys = [];
    att.forEach(function (r) {
      var w = workers[r.wid];
      if (!w || ids.indexOf(r.wid) === -1) return;
      if (!r.status || r.status === '--') return;
      if (r.date < from || r.date > to) return;
      if (loc && String(r.loc) !== String(loc)) return;
      var counts = String(r.loc).trim() !== '';
      if (!r.settleId && !counts) return;
      var val = counts ? recValue_(r, w) : 0;
      var diff = Math.round((val - (r.settleId ? num_(r.paidAmt) : 0)) * 100) / 100;
      if (Math.abs(diff) < 0.005) return;
      var wasPaid = !!r.settleId;
      var otPart = wasPaid ? diff : (counts ? num_(r.xh) * (num_(w.wage) / (num_(w.hours, 8) || 8)) : 0);
      r.settleId = sid;
      r.paidAmt = String(val);
      var p = per[r.wid] || (per[r.wid] = { days: 0, amt: 0, ot: 0, name: w.name });
      if (!wasPaid) p.days++;
      p.amt += diff;
      p.ot += otPart;
      keys.push(r.date + '|' + r.wid);
    });
    var wids = Object.keys(per);
    if (!wids.length) throw new Error('لا توجد مبالغ مستحقة للصرف ضمن التحديد');
    writeAll_('Attendance', att);
    var sheet = sh_('Settlements'), total = 0, bTot = 0, dTot = 0, tTot = 0, t = now_(), d = setDate || today_();
    wids.forEach(function (id) {
      var p = per[id], a = Math.round(p.amt * 100) / 100, x = adj[id] || {};
      var b = Math.max(0, num_(x.b)), ded = Math.max(0, num_(x.d)), tx = Math.max(0, num_(x.t));
      var net = Math.round((a + b - ded - tx) * 100) / 100, ot = Math.round(p.ot * 100) / 100;
      total += a; bTot += b; dTot += ded; tTot += tx;
      sheet.appendRow([sid, d, from === '0000-00-00' ? '' : from, to, id, p.name, p.days, a, u.name, t, b, ded, tx, net, ot]);
    });
    total = Math.round(total * 100) / 100;
    log_(u.name, 'تسوية', 'التسوية', wids.length + ' عامل — ' + total + ' ج' + (bTot || dTot || tTot ? ' (مكافآت ' + bTot + ' / خصومات ' + dTot + ' / ضرائب ' + tTot + ')' : '') + ' حتى ' + to);
    return { sid: sid, count: wids.length, amount: total, to: to, date: d, wids: wids, keys: keys };
  });
}

/* ===================== المرتبات ===================== */
function listPayroll(token, from, to) {
  auth_(token, ['workers', 'attendance']);
  if (from && !validDate_(from)) throw new Error('تاريخ غير صحيح');
  if (to && !validDate_(to)) throw new Error('تاريخ غير صحيح');
  return readAll_('Settlements').filter(function (r) {
    return (!from || r.date >= from) && (!to || r.date <= to);
  }).map(function (r) {
    var a = num_(r.amount), b = num_(r.bonus), d = num_(r.ded), t = num_(r.tax);
    return {
      id: r.id, date: r.date, weekday: validDate_(r.date) ? weekday_(r.date) : '', from: r.from, to: r.to, wid: r.wid, name: r.name,
      days: num_(r.days), amount: a, ot: num_(r.ot), bonus: b, ded: d, tax: t,
      net: String(r.net) === '' ? Math.round((a + b - d - t) * 100) / 100 : num_(r.net), user: r.user
    };
  }).sort(function (x, y) { return x.date === y.date ? (x.id < y.id ? 1 : -1) : (x.date < y.date ? 1 : -1); });
}

/* تعديل المكافآت والخصومات والضرائب لسطر مرتب (تسوية + عامل) */
function updatePayrollAdj(token, id, wid, b, d, t) {
  var u = auth_(token, ['workers', 'attendance']);
  b = Math.max(0, num_(b)); d = Math.max(0, num_(d)); t = Math.max(0, num_(t));
  return locked_(function () {
    var sheet = sh_('Settlements'), h = SHEETS.Settlements, n = sheet.getLastRow();
    if (n < 2) throw new Error('السطر غير موجود');
    var vals = sheet.getRange(2, 1, n - 1, h.length).getValues();
    for (var i = 0; i < vals.length; i++) {
      if (String(vals[i][0]) === String(id) && String(vals[i][h.indexOf('wid')]) === String(wid)) {
        var a = num_(vals[i][h.indexOf('amount')]), net = Math.round((a + b - d - t) * 100) / 100;
        sheet.getRange(i + 2, h.indexOf('bonus') + 1, 1, 4).setValues([[String(b), String(d), String(t), String(net)]]);
        log_(u.name, 'تعديل مرتب', 'المرتبات', String(vals[i][h.indexOf('name')]) + ' — مكافآت ' + b + ' / خصومات ' + d + ' / ضرائب ' + t);
        return { id: id, wid: wid, bonus: b, ded: d, tax: t, net: net };
      }
    }
    throw new Error('السطر غير موجود');
  });
}

/* ===================== العاملون والصور ===================== */
function imgFolder_() {
  var it = DriveApp.getFoldersByName('إدارة الأمن - صور العاملين');
  return it.hasNext() ? it.next() : DriveApp.createFolder('إدارة الأمن - صور العاملين');
}

function saveImg_(dataUrl, label) {
  var m = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+\/=]+)$/.exec(String(dataUrl || ''));
  if (!m) throw new Error('صيغة الصورة غير مدعومة');
  if (m[2].length > 3000000) throw new Error('حجم الصورة كبير');
  var blob = Utilities.newBlob(Utilities.base64Decode(m[2]), m[1], label + '-' + Date.now());
  return imgFolder_().createFile(blob).getId();
}

function trashImg_(id) {
  if (!id) return;
  try { DriveApp.getFileById(id).setTrashed(true); } catch (e) { /* ملف محذوف */ }
}

function saveWorker(token, w) {
  var u = auth_(token, 'workers');
  var name = clip_(w && w.name, 80);
  if (!name) throw new Error('اكتب اسم العامل');
  return locked_(function () {
    var workers = readAll_('Workers');
    var cur = null;
    if (w.id) {
      cur = workers.filter(function (x) { return x.id === String(w.id); })[0];
      if (!cur) throw new Error('العامل غير موجود');
    } else {
      cur = { id: 'w' + Date.now() + Math.floor(Math.random() * 1000), lastSet: '', cardImg: '', photo: '' };
      workers.push(cur);
    }
    cur.name = name;
    cur.card = clip_(w.card, 30);
    cur.phone = clip_(w.phone, 20);
    cur.wage = Math.max(0, num_(w.wage));
    cur.hours = Math.max(1, num_(w.hours, 8)) || 8;
    if (w.cardImgData) { trashImg_(cur.cardImg); cur.cardImg = saveImg_(w.cardImgData, 'card'); }
    if (w.photoData) { trashImg_(cur.photo); cur.photo = saveImg_(w.photoData, 'photo'); }
    writeAll_('Workers', workers);
    log_(u.name, w.id ? 'تعديل عامل' : 'إضافة عامل', 'العاملين', name);
    return workerOut_(cur, true, lastSetMap_());
  });
}

function deleteWorkers(token, ids) {
  var u = auth_(token, 'workers');
  if (!Array.isArray(ids) || !ids.length) throw new Error('حدد عاملًا واحدًا على الأقل');
  return locked_(function () {
    var keep = [], n = 0;
    readAll_('Workers').forEach(function (w) {
      if (ids.indexOf(w.id) !== -1) { trashImg_(w.cardImg); trashImg_(w.photo); n++; } else keep.push(w);
    });
    writeAll_('Workers', keep);
    log_(u.name, 'حذف عاملين', 'العاملين', n + ' عامل');
    return { count: n };
  });
}

function getImage(token, id, kind) {
  auth_(token, ['workers', 'attendance']);
  var w = readAll_('Workers').filter(function (x) { return x.id === String(id); })[0];
  if (!w) return null;
  var fid = kind === 'card' ? w.cardImg : w.photo;
  if (!fid) return null;
  try {
    var blob = DriveApp.getFileById(fid).getBlob();
    return 'data:' + blob.getContentType() + ';base64,' + Utilities.base64Encode(blob.getBytes());
  } catch (e) { return null; }
}

/* ===================== إدارة المستخدمين والمتابعة ===================== */
function setUser(token, username, patch) {
  var me = auth_(token, 'admin');
  username = clip_(username, 40).toLowerCase();
  return locked_(function () {
    var users = readAll_('Users');
    var u = users.filter(function (x) { return x.username === username; })[0];
    if (!u) throw new Error('المستخدم غير موجود');
    if (u.role === 'admin') throw new Error('لا يمكن تعديل حساب المدير');
    if (patch && patch.status) {
      if (['approved', 'pending', 'suspended'].indexOf(patch.status) === -1) throw new Error('حالة غير صحيحة');
      u.status = patch.status;
      log_(me.name, 'تغيير حالة مستخدم', 'المستخدمين', u.name + ' → ' + patch.status);
    }
    if (patch && patch.perms) {
      var p = {};
      PERMS.forEach(function (k) { if (patch.perms[k]) p[k] = 1; });
      u.perms = JSON.stringify(p);
      log_(me.name, 'تعديل صلاحيات', 'المستخدمين', u.name);
    }
    writeAll_('Users', users);
    return users.map(publicUser_);
  });
}

function cleanPerms_(perms) {
  var p = {};
  PERMS.forEach(function (k) { if (perms && perms[k]) p[k] = 1; });
  return p;
}

function addUser(token, name, username, password, perms, isAdmin) {
  var me = auth_(token, 'admin');
  name = clip_(name, 60);
  username = clip_(username, 30).toLowerCase();
  password = String(password || '');
  if (name.length < 2) throw new Error('اكتب الاسم بالكامل');
  if (!/^[a-z0-9_.]{3,30}$/.test(username)) throw new Error('اسم المستخدم: حروف إنجليزية صغيرة وأرقام فقط (3 أحرف على الأقل)');
  if (password.length < 6) throw new Error('كلمة المرور 6 أحرف على الأقل');
  return locked_(function () {
    var users = readAll_('Users');
    if (users.some(function (u) { return u.username === username; })) throw new Error('اسم المستخدم مستخدم من قبل');
    var salt = Utilities.getUuid();
    users.push({
      username: username, name: name, salt: salt, hash: hash_(salt, password), status: 'approved',
      role: isAdmin ? 'admin' : 'user', perms: JSON.stringify(cleanPerms_(perms)), lastLogin: '', lastActive: ''
    });
    writeAll_('Users', users);
    log_(me.name, 'إضافة مستخدم', 'المستخدمين', name + ' (' + username + ')');
    return users.map(publicUser_);
  });
}

function resetUserPassword(token, username, newPass) {
  var me = auth_(token, 'admin');
  username = clip_(username, 40).toLowerCase();
  newPass = String(newPass || '');
  if (newPass.length < 6) throw new Error('كلمة المرور 6 أحرف على الأقل');
  var u = readAll_('Users').filter(function (x) { return x.username === username; })[0];
  if (!u) throw new Error('المستخدم غير موجود');
  if (u.role === 'admin') throw new Error('غيّر كلمة مرور المدير من زر 🔑 داخل حسابه');
  var salt = Utilities.getUuid();
  updateUser_(username, { salt: salt, hash: hash_(salt, newPass) });
  log_(me.name, 'إعادة تعيين كلمة مرور', 'المستخدمين', u.name);
  return true;
}

function deleteUser(token, username) {
  var me = auth_(token, 'admin');
  username = clip_(username, 40).toLowerCase();
  return locked_(function () {
    var users = readAll_('Users');
    var u = users.filter(function (x) { return x.username === username; })[0];
    if (!u) throw new Error('المستخدم غير موجود');
    if (u.role === 'admin') throw new Error('لا يمكن حذف حساب المدير');
    writeAll_('Users', users.filter(function (x) { return x.username !== username; }));
    log_(me.name, 'حذف مستخدم', 'المستخدمين', u.name);
    return readAll_('Users').map(publicUser_);
  });
}

function getMonitor(token) {
  auth_(token, 'admin');
  var log = readAll_('Log');
  var nowMs = Date.now();
  var users = readAll_('Users').map(function (u) {
    var mine = log.filter(function (l) { return l.user === u.name; });
    var last = mine.length ? mine[mine.length - 1].action : '';
    var act = Number(u.lastActive) || 0;
    return { name: u.name, username: u.username, lastLogin: u.lastLogin, online: act && (nowMs - act) < ONLINE_MS, count: mine.length, lastAction: last };
  });
  return { users: users, log: log.slice(-300).reverse() };
}

/* ===================== دفتر دخول البوابة ===================== */
var AR_DAYS_ = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

function weekday_(d) {
  var p = d.split('-');
  return AR_DAYS_[new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), 12).getDay()];
}

function gateImgs_(g) {
  try { var a = JSON.parse(g.images || '[]'); return Array.isArray(a) ? a : []; } catch (e) { return []; }
}

function gateOut_(g) {
  return {
    id: g.id, seq: num_(g.seq), weekday: g.weekday, date: g.date, plate: g.plate, time: g.time,
    driver: g.driver, statement: g.statement, notes: g.notes, managers: g.managers, host: g.host,
    imgCount: gateImgs_(g).length, createdBy: g.createdBy
  };
}

function listGate(token) {
  auth_(token, 'gate');
  var rows = readAll_('Gate').map(gateOut_);
  rows.sort(function (a, b) { return a.date === b.date ? b.seq - a.seq : (a.date < b.date ? 1 : -1); });
  return rows.slice(0, 3000);
}

function saveGate(token, e) {
  var u = auth_(token, 'gate');
  e = e || {};
  var date = String(e.date || '');
  if (!validDate_(date)) throw new Error('حدد التاريخ');
  var time = clip_(e.time, 5);
  if (time && !/^\d{2}:\d{2}$/.test(time)) throw new Error('الوقت غير صحيح');
  var plate = clip_(e.plate, 40);
  if (!plate) throw new Error('اكتب رقم السيارة');
  var fresh = Array.isArray(e.newImages) ? e.newImages : [];
  if (fresh.length > 10) throw new Error('الحد الأقصى 10 صور في المرة الواحدة');
  return locked_(function () {
    var rows = readAll_('Gate'), cur = null;
    if (e.id) {
      cur = rows.filter(function (x) { return x.id === String(e.id); })[0];
      if (!cur) throw new Error('السجل غير موجود');
    } else {
      var mx = 0;
      rows.forEach(function (x) { mx = Math.max(mx, num_(x.seq)); });
      cur = { id: 'g' + Date.now() + Math.floor(Math.random() * 1000), seq: mx + 1, images: '[]', createdBy: u.name, createdAt: now_() };
      rows.push(cur);
    }
    var imgs = gateImgs_(cur);
    var rm = (Array.isArray(e.removeIdx) ? e.removeIdx : []).map(Number);
    var keep = imgs.filter(function (id, i) { return rm.indexOf(i) === -1; });
    if (keep.length + fresh.length > 20) throw new Error('الحد الأقصى 20 صورة للتسجيل الواحد');
    imgs.forEach(function (id, i) { if (rm.indexOf(i) !== -1) trashImg_(id); });
    fresh.forEach(function (d) { keep.push(saveImg_(d, 'gate')); });
    cur.date = date; cur.weekday = weekday_(date); cur.time = time; cur.plate = plate;
    cur.driver = clip_(e.driver, 80); cur.statement = clip_(e.statement, 200); cur.notes = clip_(e.notes, 300);
    cur.managers = clip_(e.managers, 200); cur.host = clip_(e.host, 80);
    cur.images = JSON.stringify(keep);
    writeAll_('Gate', rows);
    log_(u.name, e.id ? 'تعديل دخول بوابة' : 'تسجيل دخول بوابة', 'دفتر البوابة', plate + ' — ' + date);
    return gateOut_(cur);
  });
}

function deleteGate(token, id) {
  var u = auth_(token, 'gate');
  return locked_(function () {
    var keep = [], hit = null;
    readAll_('Gate').forEach(function (g) { if (g.id === String(id)) hit = g; else keep.push(g); });
    if (!hit) throw new Error('السجل غير موجود');
    gateImgs_(hit).forEach(trashImg_);
    writeAll_('Gate', keep);
    log_(u.name, 'حذف دخول بوابة', 'دفتر البوابة', hit.plate + ' — ' + hit.date);
    return true;
  });
}

function getGateImage(token, id, idx) {
  auth_(token, 'gate');
  var g = readAll_('Gate').filter(function (x) { return x.id === String(id); })[0];
  if (!g) return null;
  var fid = gateImgs_(g)[Number(idx)];
  if (!fid) return null;
  try {
    var blob = DriveApp.getFileById(fid).getBlob();
    return 'data:' + blob.getContentType() + ';base64,' + Utilities.base64Encode(blob.getBytes());
  } catch (err) { return null; }
}

function resetAll(token) {
  var u = auth_(token, 'admin');
  return locked_(function () {
    readAll_('Workers').forEach(function (w) { trashImg_(w.cardImg); trashImg_(w.photo); });
    writeAll_('Workers', []);
    writeAll_('Attendance', []);
    writeAll_('Locations', []);
    writeAll_('Settlements', []);
    log_(u.name, 'تصفير البرنامج', 'النظام', '');
    return true;
  });
}
