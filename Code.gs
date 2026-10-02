/**********************************************************************
 * إدارة الأمن – نظام إدارة العاملين اليومية (Google Apps Script)
 * ------------------------------------------------------------------
 * طريقة النشر:
 *   1) أنشئ مشروعًا جديدًا على https://script.google.com
 *   2) انسخ هذا الملف في Code.gs وأنشئ ملفات HTML الثلاثة
 *   3) نشر ← نشر جديد ← تطبيق ويب (Web App)
 *      - Execute as: Me     -  Who has access: Anyone
 *   4) افتح الرابط في المتصفح أو على أندرويد
 *
 * حساب المدير الافتراضي:  admin / admin123   (غيّر كلمة المرور فور الدخول)
 **********************************************************************/

const SESSION_HOURS = 12;

/* ===================== Web App Entry ===================== */

function doGet() {
  return HtmlService.createTemplateFromFile('Index')
    .setTitle('إدارة الأمن')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1, maximum-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function include(name) {
  return HtmlService.createHtmlOutputFromFile(name).getContent();
}

/* ===================== Helpers ===================== */

function hash_(s) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, String(s))
    .map(function (b) { return ('0' + (b & 0xFF).toString(16)).slice(-2); }).join('');
}

function todayStr_() {
  return Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd');
}

function getDB_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('DB_ID');
  if (id) {
    try {
      var ss = SpreadsheetApp.openById(id);
      migrateCols_(ss);
      return ss;
    } catch (e) {}
  }
  var ss = SpreadsheetApp.create('إدارة الأمن - قاعدة البيانات');
  props.setProperty('DB_ID', ss.getId());
  initSheets_(ss);
  return ss;
}


function sheet_(name) {
  var ss = getDB_();
  return ss.getSheetByName(name) || ss.insertSheet(name);
}

// ترقية قواعد البيانات القديمة: إضافة الأعمدة الجديدة
function migrateCols_(ss) {
  var need = { Workers: ['workHours'], Attendance: ['extraHours'] };
  Object.keys(need).forEach(function (name) {
    var sh = ss.getSheetByName(name);
    if (!sh) return;
    var head = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
    need[name].forEach(function (col) {
      if (head.indexOf(col) === -1) {
        var colIdx = head.length + 1;
        sh.getRange(1, colIdx).setValue(col);
        if (col === 'workHours') {
          var rows = sh.getLastRow() - 1;
          if (rows > 0) sh.getRange(2, colIdx, rows, 1).setValue(8);
        }
      }
    });
  });
}

function getAll_(name) {
  var sh = sheet_(name);
  var vals = sh.getDataRange().getValues();
  if (vals.length < 2) return [];
  var head = vals[0];
  var out = [];
  for (var i = 1; i < vals.length; i++) {
    if (vals[i].join('') === '') continue;
    var o = { _row: i + 1 };
    for (var j = 0; j < head.length; j++) o[head[j]] = vals[i][j];
    out.push(o);
  }
  return out;
}

function initSheets_(ss) {
  var defs = {
    Users:      ['id', 'username', 'passHash', 'name', 'phone', 'role', 'status', 'permissions', 'created'],
    Workers:    ['id', 'name', 'cardNumber', 'phone', 'dailyWage', 'cardImg', 'photo', 'lastSettlement', 'active', 'created', 'workHours'],
    Attendance: ['id', 'date', 'workerId', 'workerName', 'status', 'location', 'wage', 'notes', 'created', 'extraHours'],
    Locations:  ['name', 'count'],
    ActivityLog: ['id', 'username', 'name', 'action', 'page', 'details', 'created']
  };
  Object.keys(defs).forEach(function (name) {
    var sh = ss.getSheetByName(name) || ss.insertSheet(name);
    if (sh.getLastRow() === 0) sh.appendRow(defs[name]);
  });
  // حساب المدير الافتراضي
  var u = ss.getSheetByName('Users');
  u.appendRow([Utilities.getUuid(), 'admin', hash_('admin123'), 'مدير النظام', '', 'admin', 'approved',
    JSON.stringify({ workers: true, attendance: true, reports: true, users: true }), new Date()]);
}

function adminOnly_(user) {
  if (user.role !== 'admin') throw new Error('هذه الشاشة متاحة للمدير فقط');
}

/* ===================== الصور (Google Drive) ===================== */

function getFolder_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('IMG_FOLDER');
  if (id) {
    try { return DriveApp.getFolderById(id); } catch (e) {}
  }
  var it = DriveApp.getFoldersByName('إدارة الأمن - الصور');
  var folder = it.hasNext() ? it.next() : DriveApp.createFolder('إدارة الأمن - الصور');
  props.setProperty('IMG_FOLDER', folder.getId());
  return folder;
}

function uploadImage_(b64, filename) {
  var blob = Utilities.newBlob(Utilities.base64Decode(b64), 'image/jpeg', filename);
  var file = getFolder_().createFile(blob);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return file.getId();
}

/* ===================== الجلسات والدخول ===================== */

function makeSession_(u) {
  var token = Utilities.getUuid();
  var data = {
    id: u.id, username: u.username, name: u.name, role: u.role,
    permissions: (function () { try { return JSON.parse(u.permissions || '{}'); } catch (e) { return {}; } })()
  };
  CacheService.getScriptCache().put('sess_' + token, JSON.stringify(data), SESSION_HOURS * 3600);
  return { token: token, user: data };
}

function auth_(token) {
  if (!token) throw new Error('انتهت الجلسة، برجاء تسجيل الدخول من جديد');
  var raw = CacheService.getScriptCache().get('sess_' + token);
  if (!raw) throw new Error('انتهت الجلسة، برجاء تسجيل الدخول من جديد');
  return JSON.parse(raw);
}

function needPerm_(user, perm) {
  if (user.role !== 'admin' && !user.permissions[perm])
    throw new Error('لا تمتلك صلاحية لهذه الشاشة');
}

function apiLogin(username, password) {
  username = String(username || '').trim().toLowerCase();
  var users = getAll_('Users');
  var u = null;
  for (var i = 0; i < users.length; i++) {
    if (String(users[i].username).toLowerCase() === username) { u = users[i]; break; }
  }
  if (!u || u.passHash !== hash_(password)) throw new Error('بيانات الدخول غير صحيحة');
  if (u.status !== 'approved') {
    if (u.status === 'pending') throw new Error('حسابك بانتظار موافقة الإدارة');
    throw new Error('تم إيقاف هذا الحساب، راجع الإدارة');
  }
  logActivity_(u, 'دخول', 'تسجيل الدخول', 'دخول ناجح');
  return makeSession_(u);
}

function apiRegister(name, username, password, phone) {
  username = String(username || '').trim().toLowerCase();
  if (!name || !username || !password) throw new Error('برجاء إكمال جميع البيانات');
  if (String(password).length < 4) throw new Error('كلمة المرور يجب ألا تقل عن 4 أحرف');
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (String(users[i].username).toLowerCase() === username)
      throw new Error('اسم المستخدم موجود بالفعل');
  }
  sheet_('Users').appendRow([Utilities.getUuid(), username, hash_(password), String(name).trim(),
    String(phone || '').trim(), 'user', 'pending', '{}', new Date()]);
  return 'تم إرسال طلب التسجيل بنجاح. سيتم تنشيط الحساب بعد موافقة الإدارة.';
}

function apiSession(token) {
  var user = auth_(token);
  return { token: token, user: user };
}

function apiLogout(token) {
  try { logActivity_(auth_(token), 'خروج', 'تسجيل الدخول', 'تسجيل خروج'); } catch (e) {}
  if (token) CacheService.getScriptCache().remove('sess_' + token);
  return true;
}

function apiChangePassword(token, oldPass, newPass) {
  var user = auth_(token);
  if (String(newPass).length < 4) throw new Error('كلمة المرور يجب ألا تقل عن 4 أحرف');
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (users[i].id === user.id) {
      if (users[i].passHash !== hash_(oldPass)) throw new Error('كلمة المرور الحالية غير صحيحة');
      sheet_('Users').getRange(users[i]._row, 3).setValue(hash_(newPass));
      return 'تم تغيير كلمة المرور بنجاح';
    }
  }
  throw new Error('تعذر العثور على الحساب');
}

/* ===================== إدارة المستخدمين (للمدير) ===================== */

function apiGetUsers(token) {
  var user = auth_(token);
  adminOnly_(user);
  return getAll_('Users').map(function (u) {
    return {
      id: u.id, username: u.username, name: u.name, phone: String(u.phone || ''),
      role: u.role, status: u.status,
      permissions: (function () { try { return JSON.parse(u.permissions || '{}'); } catch (e) { return {}; } })()
    };
  });
}

function apiSetUserStatus(token, userId, status) {
  var user = auth_(token);
  adminOnly_(user);
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (users[i].id === userId) {
      sheet_('Users').getRange(users[i]._row, 7).setValue(status);
      logActivity_(user, 'تعديل حالة مستخدم', 'المستخدمين', 'مستخدم: ' + users[i].username + ' → ' + status);
      return 'تم التحديث';
    }
  }
  throw new Error('المستخدم غير موجود');
}

function apiSetPermissions(token, userId, perms, role) {
  var user = auth_(token);
  adminOnly_(user);
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (users[i].id === userId) {
      sheet_('Users').getRange(users[i]._row, 8).setValue(JSON.stringify(perms || {}));
      if (role) sheet_('Users').getRange(users[i]._row, 6).setValue(role);
      logActivity_(user, 'تعديل صلاحيات', 'المستخدمين', 'مستخدم: ' + users[i].username);
      return 'تم حفظ الصلاحيات';
    }
  }
  throw new Error('المستخدم غير موجود');
}

function apiCreateUser(token, name, username, password, phone, perms, role) {
  var user = auth_(token);
  adminOnly_(user);
  username = String(username || '').trim().toLowerCase();
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (String(users[i].username).toLowerCase() === username)
      throw new Error('اسم المستخدم موجود بالفعل');
  }
  sheet_('Users').appendRow([Utilities.getUuid(), username, hash_(password), String(name).trim(),
    String(phone || '').trim(), role === 'admin' ? 'admin' : 'user', 'approved',
    JSON.stringify(perms || {}), new Date()]);
  logActivity_(user, 'إضافة مستخدم', 'المستخدمين', 'مستخدم: ' + username);
  return 'تم إنشاء الحساب';
}

function apiResetUserPassword(token, userId, newPass) {
  var user = auth_(token);
  adminOnly_(user);
  if (String(newPass).length < 4) throw new Error('كلمة المرور يجب ألا تقل عن 4 أحرف');
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (users[i].id === userId) {
      sheet_('Users').getRange(users[i]._row, 3).setValue(hash_(newPass));
      logActivity_(user, 'تعيين كلمة مرور', 'المستخدمين', 'مستخدم: ' + users[i].username);
      return 'تم تعيين كلمة المرور الجديدة';
    }
  }
  throw new Error('المستخدم غير موجود');
}

function apiDeleteUser(token, userId) {
  var user = auth_(token);
  adminOnly_(user);
  if (userId === user.id) throw new Error('لا يمكن حذف حسابك الحالي');
  var users = getAll_('Users');
  for (var i = 0; i < users.length; i++) {
    if (users[i].id === userId) {
      logActivity_(user, 'حذف مستخدم', 'المستخدمين', 'مستخدم: ' + users[i].username);
      sheet_('Users').deleteRow(users[i]._row);
      return 'تم حذف الحساب';
    }
  }
  throw new Error('المستخدم غير موجود');
}

/* ===================== متابعة المستخدمين (سجل النشاط) ===================== */

function logActivity_(user, action, page, details) {
  try {
    sheet_('ActivityLog').appendRow([Utilities.getUuid(),
      String((user && user.username) || ''), String((user && user.name) || ''),
      String(action || ''), String(page || ''), String(details || ''), new Date()]);
  } catch (e) {}
}

function apiLogPage(token, page) {
  var user = auth_(token);
  logActivity_(user, 'فتح صفحة', page, '');
  return true;
}

function apiGetActivity(token) {
  var user = auth_(token);
  adminOnly_(user);
  var tz = Session.getScriptTimeZone();
  var now = new Date();
  var all = getAll_('ActivityLog');
  var users = {}, log = [];
  for (var i = all.length - 1; i >= 0 && log.length < 300; i--) {
    var r = all[i];
    var dt = r.created ? new Date(r.created) : null;
    var timeStr = dt ? Utilities.formatDate(dt, tz, 'yyyy-MM-dd HH:mm') : '';
    var ts = dt ? dt.getTime() : 0;
    log.push({ time: timeStr, username: String(r.username), name: String(r.name),
      action: String(r.action), page: String(r.page), details: String(r.details) });
    var key = String(r.username);
    if (!users[key]) users[key] = { username: key, name: String(r.name),
      lastLogin: '', lastSeen: '', online: false, actions: 0, _login: 0, _seen: 0 };
    var uu = users[key];
    uu.actions++;
    if (String(r.action) === 'دخول' && ts > uu._login) { uu._login = ts; uu.lastLogin = timeStr; }
    if (ts > uu._seen) { uu._seen = ts; uu.lastSeen = timeStr; uu.online = (now.getTime() - ts) < 5 * 60 * 1000; }
  }
  var list = Object.keys(users).map(function (k) {
    return { username: users[k].username, name: users[k].name, lastLogin: users[k].lastLogin,
      lastSeen: users[k].lastSeen, online: users[k].online, actions: users[k].actions };
  });
  list.sort(function (a, b) { return a.name.localeCompare(b.name, 'ar'); });
  return { log: log, users: list };
}

/* ===================== العاملين ===================== */

function isActive_(w) {
  return w.active === true || w.active === 'TRUE' || String(w.active) === 'true';
}

// عدد أيام الحضور المستحقة (لم تُسوَّ بعد)، محسوبة حتى تاريخ محدد فقط (افتراضيًا تاريخ اليوم)
// وليس بعدد كل أيام الحضور المسجلة بغض النظر عن تاريخها
function unsettledCount_(worker, att, uptoDate) {
  var ls = worker.lastSettlement ? String(worker.lastSettlement).slice(0, 10) : '';
  var upto = String(uptoDate || todayStr_());
  var c = 0;
  for (var i = 0; i < att.length; i++) {
    var r = att[i];
    if (r.workerId === worker.id && r.status && r.status !== '--' &&
        (!ls || String(r.date) > ls) && String(r.date) <= upto) c++;
  }
  return c;
}

function workerOut_(w, att, uptoDate) {
  var ls = w.lastSettlement ? String(w.lastSettlement).slice(0, 10) : '';
  return {
    id: w.id, name: w.name, cardNumber: String(w.cardNumber || ''), phone: String(w.phone || ''),
    dailyWage: Number(w.dailyWage) || 0,
    cardImg: String(w.cardImg || ''), photo: String(w.photo || ''),
    lastSettlement: ls, active: isActive_(w),
    workHours: Number(w.workHours) || 8,
    unsettled: att ? unsettledCount_(w, att, uptoDate) : 0
  };
}

function apiGetWorkers(token) {
  auth_(token);
  var att = getAll_('Attendance');
  return getAll_('Workers').map(function (w) { return workerOut_(w, att); });
}

function apiSaveWorker(token, w) {
  var user = auth_(token);
  needPerm_(user, 'workers');
  if (!w || !w.name) throw new Error('اسم العامل مطلوب');
  var sh = sheet_('Workers');

  if (w.id) {
    var rows = getAll_('Workers');
    var ex = null;
    for (var i = 0; i < rows.length; i++) if (rows[i].id === w.id) { ex = rows[i]; break; }
    if (!ex) throw new Error('العامل غير موجود');
    var cardImg = ex.cardImg, photo = ex.photo;
    if (w.cardImgB64) cardImg = uploadImage_(w.cardImgB64, 'card_' + Date.now() + '.jpg');
    if (w.photoB64) photo = uploadImage_(w.photoB64, 'photo_' + Date.now() + '.jpg');
    sh.getRange(ex._row, 1, 1, 11).setValues([[
      ex.id, String(w.name).trim(), String(w.cardNumber || '').trim(), String(w.phone || '').trim(),
      Number(w.dailyWage) || 0, cardImg, photo,
      w.lastSettlement || ex.lastSettlement || todayStr_(),
      (w.active === false) ? false : true, ex.created,
      Number(w.workHours) || Number(ex.workHours) || 8
    ]]);
    logActivity_(user, 'تعديل عامل', 'العاملين', 'عامل: ' + String(w.name).trim());
    return 'تم حفظ بيانات العامل';
  }

  var cardImg = w.cardImgB64 ? uploadImage_(w.cardImgB64, 'card_' + Date.now() + '.jpg') : '';
  var photo = w.photoB64 ? uploadImage_(w.photoB64, 'photo_' + Date.now() + '.jpg') : '';
  // آخر تاريخ تسوية تلقائي = تاريخ الإضافة
  sh.appendRow([Utilities.getUuid(), String(w.name).trim(), String(w.cardNumber || '').trim(),
    String(w.phone || '').trim(), Number(w.dailyWage) || 0, cardImg, photo,
    todayStr_(), true, new Date(), Number(w.workHours) || 8]);
  logActivity_(user, 'إضافة عامل', 'العاملين', 'عامل: ' + String(w.name).trim());
  return 'تمت إضافة العامل';
}

function apiSettle(token, workerId, date) {
  var user = auth_(token);
  needPerm_(user, 'workers');
  var rows = getAll_('Workers');
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].id === workerId) {
      sheet_('Workers').getRange(rows[i]._row, 8).setValue(date || todayStr_());
      logActivity_(user, 'تسوية عامل', 'التسوية', 'عامل: ' + rows[i].name + ' حتى ' + (date || todayStr_()));
      return 'تمت التسوية بنجاح حتى ' + (date || todayStr_());
    }
  }
  throw new Error('العامل غير موجود');
}

function apiDeleteWorker(token, workerId) {
  var user = auth_(token);
  needPerm_(user, 'workers');
  var rows = getAll_('Workers');
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].id === workerId) {
      logActivity_(user, 'حذف عامل', 'العاملين', 'عامل: ' + rows[i].name);
      sheet_('Workers').deleteRow(rows[i]._row);
      return 'تم حذف العامل';
    }
  }
  throw new Error('العامل غير موجود');
}

function apiDeleteWorkers(token, workerIds) {
  var user = auth_(token);
  needPerm_(user, 'workers');
  if (!workerIds || !workerIds.length) throw new Error('برجاء تحديد عامل واحد على الأقل');
  var set = {};
  workerIds.forEach(function (id) { set[id] = true; });
  var sh = sheet_('Workers');
  var rows = getAll_('Workers');
  var del = [], names = [];
  rows.forEach(function (w) {
    if (set[w.id]) { del.push(w._row); names.push(w.name); }
  });
  del.sort(function (a, b) { return b - a; }).forEach(function (row) { sh.deleteRow(row); });
  logActivity_(user, 'حذف عاملين', 'العاملين', 'تم حذف ' + del.length + ' عامل: ' + names.join('، '));
  return 'تم حذف ' + del.length + ' عامل';
}

/* ===================== أماكن الحضور ===================== */

function apiResetAllData(token) {
  var user = auth_(token);
  if (user.role !== 'admin') throw new Error('هذا الإجراء للمدير فقط');
  ['Workers', 'Attendance', 'Locations'].forEach(function (name) {
    var sh = sheet_(name);
    var last = sh.getLastRow();
    if (last > 1) sh.getRange(2, 1, last - 1, sh.getLastColumn()).clearContent();
  });
  logActivity_(user, 'تصفير البرنامج', 'النظام', 'تم حذف كل بيانات العاملين والحضور والأماكن نهائيًا');
  return 'تم تصفير البرنامج وحذف كل البيانات بنجاح';
}

function touchLocation_(loc) {
  if (!loc) return;
  loc = String(loc).trim();
  if (!loc) return;
  var sh = sheet_('Locations');
  var rows = getAll_('Locations');
  for (var i = 0; i < rows.length; i++) {
    if (String(rows[i].name).trim() === loc) {
      sh.getRange(rows[i]._row, 2).setValue(Number(rows[i].count) + 1);
      return;
    }
  }
  sh.appendRow([loc, 1]);
}

function apiGetLocations(token) {
  auth_(token);
  return getAll_('Locations')
    .sort(function (a, b) { return Number(b.count) - Number(a.count); })
    .map(function (r) { return String(r.name); });
}


/* ===================== الحضور ===================== */

function attRow_(r) {
  return {
    id: r.id, date: String(r.date), workerId: r.workerId, workerName: r.workerName,
    status: r.status, location: String(r.location || ''), wage: Number(r.wage) || 0,
    notes: String(r.notes || ''), extraHours: Number(r.extraHours) || 0
  };
}

function apiGetDay(token, date) {
  var user = auth_(token);
  needPerm_(user, 'attendance');
  var att = getAll_('Attendance');
  // المستحق هنا يُحسب حتى تاريخ هذا اليوم المحدد، وليس بعدد كل الأيام المسجلة
  var workers = getAll_('Workers').filter(isActive_).map(function (w) { return workerOut_(w, att, date); });
  var records = att.filter(function (r) { return String(r.date) === String(date); }).map(attRow_);
  return { date: String(date), workers: workers, records: records };
}

// حفظ تسجيل اليوم بالكامل (يستبدل أي تسجيل سابق لنفس التاريخ)
function apiSaveDay(token, date, records) {
  var user = auth_(token);
  needPerm_(user, 'attendance');
  if (!date) throw new Error('برجاء تحديد التاريخ');
  var sh = sheet_('Attendance');
  var all = getAll_('Attendance');
  var del = [];
  all.forEach(function (r) { if (String(r.date) === String(date)) del.push(r._row); });
  del.sort(function (a, b) { return b - a; }).forEach(function (row) { sh.deleteRow(row); });
  var now = new Date();
  (records || []).forEach(function (r) {
    if (!r || !r.status || r.status === '--') return;
    sh.appendRow([Utilities.getUuid(), String(date), r.workerId, r.workerName || '',
      r.status, String(r.location || '').trim(), Number(r.wage) || 0, String(r.notes || ''), now,
      Number(r.extraHours) || 0]);
    touchLocation_(r.location);
  });
  logActivity_(user, 'حفظ حضور', 'الحضور', 'تاريخ ' + date + ' (' + (records || []).length + ' سجل)');
  return 'تم حفظ تسجيل اليوم بالكامل';
}

// عرض فترة سابقة (من - إلى)
function apiGetPeriod(token, from, to) {
  var user = auth_(token);
  needPerm_(user, 'attendance');
  var att = getAll_('Attendance');
  var workers = getAll_('Workers').filter(isActive_).map(function (w) { return workerOut_(w, att); });
  var rows = att.filter(function (r) {
    var d = String(r.date);
    return d >= String(from) && d <= String(to);
  }).map(attRow_);
  rows.sort(function (a, b) { return a.date < b.date ? 1 : a.date > b.date ? -1 : 0; });
  return { workers: workers, rows: rows, from: from, to: to };
}

/* ===================== التسوية ===================== */

function apiGetSettlement(token, from, to, location) {
  var user = auth_(token);
  needPerm_(user, 'attendance');
  if (!from || !to) throw new Error('برجاء تحديد الفترة من - إلى');
  location = String(location || '').trim();

  var wmap = workerMap_();
  var att = getAll_('Attendance').filter(function (r) {
    if (!r.status || r.status === '--') return false;
    var d = String(r.date);
    if (d < String(from) || d > String(to)) return false;
    if (location && String(r.location || '').trim() !== location) return false;
    return true;
  });

  var map = {};
  att.forEach(function (r) {
    if (!map[r.workerId]) map[r.workerId] = {
      workerId: r.workerId, workerName: r.workerName, days: 0, wage: 0, extraHours: 0, total: 0, notes: []
    };
    var m = map[r.workerId];
    m.days++;
    m.wage = Number(r.wage) || m.wage;
    m.extraHours += Number(r.extraHours) || 0;
    m.total += recValue_(r, wmap);
    if (r.notes && m.notes.indexOf(r.notes) === -1) m.notes.push(r.notes);
  });

  var wmap = {};
  getAll_('Workers').forEach(function (w) { wmap[w.id] = w; });

  var rows = Object.keys(map).map(function (k) {
    var m = map[k];
    var w = wmap[k];
    var ls = w && w.lastSettlement ? String(w.lastSettlement).slice(0, 10) : '';
    m.settled = !!(ls && ls >= String(to));
    m.notes = m.notes.join(' | ');
    return m;
  });
  rows.sort(function (a, b) { return a.workerName.localeCompare(b.workerName, 'ar'); });

  var totalDays = 0, totalAmount = 0;
  rows.forEach(function (r) { totalDays += r.days; totalAmount += r.total; });
  totalAmount = Math.round(totalAmount * 100) / 100;

  return {
    rows: rows, from: String(from), to: String(to), location: location,
    totalDays: totalDays, totalAmount: totalAmount,
    amountWords: amountToArabic_(totalAmount)
  };
}

function apiSettleBulk(token, workerIds, to) {
  var user = auth_(token);
  needPerm_(user, 'attendance');
  if (!to) throw new Error('برجاء تحديد تاريخ التسوية');
  if (!workerIds || !workerIds.length) throw new Error('برجاء تحديد عامل واحد على الأقل');
  var sh = sheet_('Workers');
  var rows = getAll_('Workers');
  var set = {};
  workerIds.forEach(function (id) { set[id] = true; });
  var count = 0;
  rows.forEach(function (w) {
    if (set[w.id]) { sh.getRange(w._row, 8).setValue(String(to)); count++; }
  });
  logActivity_(user, 'تسوية عاملين', 'التسوية', 'تمت تسوية ' + count + ' عامل حتى ' + to);
  return 'تمت تسوية ' + count + ' عامل حتى تاريخ ' + to;
}

/* ===================== لوحة التحكم ===================== */


/* ===================== تحويل الأرقام إلى كلمات عربية (للخطاب) ===================== */

function numberToWords_(n) {
  n = Math.round(Number(n) || 0);
  if (n === 0) return 'صفر';
  var onesM = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة'];
  var onesF = ['', 'واحدة', 'اثنتان', 'ثلاث', 'أربع', 'خمس', 'ست', 'سبع', 'ثماني', 'تسع'];
  var teens = ['عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
  var tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
  var hundreds = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];

  function threeDigits(num, fem) {
    var oarr = fem ? onesF : onesM;
    var h = Math.floor(num / 100), t = Math.floor((num % 100) / 10), o = num % 10;
    var parts = [];
    if (h) parts.push(hundreds[h]);
    if (t === 1) {
      parts.push(teens[o]);
    } else {
      var sub = [];
      if (o) sub.push(oarr[o]);
      if (t) sub.push(tens[t]);
      if (sub.length) parts.push(sub.join(' و'));
    }
    return parts.join(' و');
  }

  var scales = [
    { val: 1000000000, s: 'مليار', d: 'ملياران', p: 'مليارات' },
    { val: 1000000, s: 'مليون', d: 'مليونان', p: 'ملايين' },
    { val: 1000, s: 'ألف', d: 'ألفان', p: 'آلاف' }
  ];

  var parts = [], rem = n;
  scales.forEach(function (sc) {
    var count = Math.floor(rem / sc.val);
    rem = rem % sc.val;
    if (count === 0) return;
    if (count === 1) parts.push(sc.s);
    else if (count === 2) parts.push(sc.d);
    else if (count >= 3 && count <= 10) parts.push(threeDigits(count, true) + ' ' + sc.p);
    else parts.push(threeDigits(count, false) + ' ' + sc.s);
  });
  if (rem > 0) parts.push(threeDigits(rem, false));
  return parts.join(' و');
}

function amountToArabic_(amount) {
  amount = Number(amount) || 0;
  var whole = Math.floor(amount);
  var frac = Math.round((amount - whole) * 100);
  var txt = (whole === 0 ? 'صفر' : numberToWords_(whole)) + ' جنيه مصري';
  if (frac > 0) txt += ' و' + numberToWords_(frac) + ' قرش';
  txt += ' لا غير';
  return txt;
}

/* ===================== التقارير ===================== */

function inRange_(r, from, to) {
  var d = String(r.date);
  return r.status && r.status !== '--' && d >= String(from) && d <= String(to);
}

function workerMap_() {
  var m = {};
  getAll_('Workers').forEach(function (w) { m[w.id] = w; });
  return m;
}

// قيمة اليوم = أجر اليوم + (ساعات إضافية × أجر الساعة)
function recValue_(r, wmap) {
  var w = wmap[r.workerId];
  var hours = (w && Number(w.workHours)) || 8;
  var dailyWage = (w && Number(w.dailyWage)) || Number(r.wage) || 0;
  var hourly = hours ? dailyWage / hours : 0;
  return (Number(r.wage) || 0) + (Number(r.extraHours) || 0) * hourly;
}

// تقرير حسب اسم العامل
function apiReportByWorker(token, workerId, from, to) {
  var user = auth_(token);
  needPerm_(user, 'reports');
  var wmap = workerMap_();
  var rows = getAll_('Attendance').filter(function (r) {
    return r.workerId === workerId && inRange_(r, from, to);
  }).map(attRow_);
  rows.sort(function (a, b) { return a.date < b.date ? -1 : 1; });
  var days = rows.length, total = 0, wage = 0, extraHours = 0;
  rows.forEach(function (r) { total += recValue_(r, wmap); wage = r.wage; extraHours += r.extraHours; });
  return { rows: rows, days: days, total: Math.round(total * 100) / 100, wage: wage, extraHours: extraHours };
}

// تقرير حسب مكان الحضور
function apiReportByLocation(token, location, from, to) {
  var user = auth_(token);
  needPerm_(user, 'reports');
  var wmap = workerMap_();
  var map = {};
  getAll_('Attendance').filter(function (r) {
    return inRange_(r, from, to) && String(r.location || '').trim() === String(location || '').trim();
  }).forEach(function (r) {
    if (!map[r.workerId]) map[r.workerId] = {
      workerId: r.workerId, workerName: r.workerName, days: 0, wage: Number(r.wage) || 0,
      extraHours: 0, total: 0, notes: []
    };
    var m = map[r.workerId];
    m.days++;
    m.extraHours += Number(r.extraHours) || 0;
    m.total += recValue_(r, wmap);
    if (r.notes && m.notes.indexOf(r.notes) === -1) m.notes.push(r.notes);
  });
  var list = Object.keys(map).map(function (k) { return map[k]; });
  list.sort(function (a, b) { return b.days - a.days; });
  return { workers: list, location: location, from: from, to: to };
}

// تقرير مجمع لجميع العاملين خلال الفترة
function apiReportSummary(token, from, to) {
  var user = auth_(token);
  needPerm_(user, 'reports');
  var wmap = workerMap_();
  var map = {};
  getAll_('Attendance').filter(function (r) { return inRange_(r, from, to); }).forEach(function (r) {
    if (!map[r.workerId]) map[r.workerId] = {
      workerId: r.workerId, workerName: r.workerName, days: 0, wage: Number(r.wage) || 0,
      extraHours: 0, total: 0
    };
    var m = map[r.workerId];
    m.days++;
    m.extraHours += Number(r.extraHours) || 0;
    m.total += recValue_(r, wmap);
    m.wage = Number(r.wage) || 0;
  });
  var list = Object.keys(map).map(function (k) { return map[k]; });
  // إضافة العاملين بدون أيام حضور خلال الفترة
  getAll_('Workers').forEach(function (w) {
    if (!map[w.id] && isActive_(w)) list.push({
      workerId: w.id, workerName: w.name, days: 0, wage: Number(w.dailyWage) || 0, total: 0
    });
  });
  list.sort(function (a, b) { return a.workerName.localeCompare(b.workerName, 'ar'); });
  return { workers: list, from: from, to: to };
}

/* ===================== أوامر مساعدة (اختياري) ===================== */

// شغّل هذه الدالة مرة واحدة من المحرر لإنشاء قاعدة البيانات مسبقًا
function setup() {
  getDB_();
  return 'تم إنشاء قاعدة البيانات';
}
