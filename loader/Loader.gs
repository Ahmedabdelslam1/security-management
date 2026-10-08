// ===== محمّل تلقائي: يسحب Code.gs من GitHub ويشغّله (يلصق مرة واحدة فقط) =====
// أي تعديل على Code.gs في GitHub يصل للسكريبت تلقائياً خلال ~5 دقائق بدون نشر جديد.
var SRC_URL_ = 'https://raw.githubusercontent.com/Ahmedabdelslam1/security-management/main/Code.gs';
var FN_ = ['doGet','doPost','setup','resetAdminPassword','resetAll','rev','login','logout','register','changePassword','ping','addLog',
  'bootstrap','saveDay','settleWorkers','listPayroll','updatePayrollAdj','saveWorker','deleteWorkers','getImage','setUser','addUser',
  'resetUserPassword','deleteUser','getMonitor','listGate','saveGate','deleteGate','getGateImage','listProcs','saveProc','deleteProc','getProcFiles','refreshLive','srvVer'];
var LIB_ = null;

function src_() {
  var c = CacheService.getScriptCache(), CH = 30000;
  function put(key, txt, ttl) {
    var n = Math.ceil(txt.length / CH), o = {};
    for (var i = 0; i < n; i++) o[key + i] = txt.substr(i * CH, CH);
    o[key + 'N'] = String(n);
    c.putAll(o, ttl);
  }
  function get(key) {
    var n = Number(c.get(key + 'N') || 0); if (!n) return null;
    var ks = []; for (var i = 0; i < n; i++) ks.push(key + i);
    var m = c.getAll(ks), s = '';
    for (var j = 0; j < n; j++) { if (m[key + j] == null) return null; s += m[key + j]; }
    return s;
  }
  var fresh = get('GS_F'); if (fresh) return fresh;
  var errs = [], urls = [SRC_URL_ + '?t=' + Date.now(), 'https://cdn.jsdelivr.net/gh/Ahmedabdelslam1/security-management@main/Code.gs'];
  for (var i = 0; i < urls.length; i++) {
    try {
      var r = UrlFetchApp.fetch(urls[i], { muteHttpExceptions: true, followRedirects: true });
      var code = r.getResponseCode(), t = r.getContentText();
      if (code === 200 && t.indexOf('function apiMap_') > -1) { put('GS_F', t, 300); put('GS_S', t, 21600); return t; }
      errs.push(code + ' ' + t.slice(0, 60));
    } catch (e) { errs.push(String(e && e.message || e)); }
  }
  var stale = get('GS_S'); if (stale) return stale;
  throw new Error('تعذر تحميل الكود من GitHub: ' + errs.join(' | '));
}

// شغّل هذه الدالة مرة واحدة من المحرر (زر ▶ ثم "مراجعة الأذونات" ← السماح) لمنح صلاحية الاتصال بـ GitHub
function authorize() { var n = src_().length; return 'تم: ' + n; }

function lib_() {
  if (LIB_) return LIB_;
  var s = src_();
  LIB_ = (new Function(s + '\nreturn {' + FN_.map(function (n) { return n + ':typeof ' + n + "==='function'?" + n + ':null'; }).join(',') + '};'))();
  return LIB_;
}

function call_(n, a) { var f = lib_()[n]; if (!f) throw new Error('إجراء غير متاح: ' + n); return f.apply(null, a); }

function doGet(e) { return call_('doGet', [e]); }
function doPost(e) { return call_('doPost', [e]); }
function setup() { return call_('setup', []); }
function resetAdminPassword() { return call_('resetAdminPassword', []); }
function resetAll() { return call_('resetAll', []); }
function rev() { return call_('rev', [].slice.call(arguments)); }
function login() { return call_('login', [].slice.call(arguments)); }
function logout() { return call_('logout', [].slice.call(arguments)); }
function register() { return call_('register', [].slice.call(arguments)); }
function changePassword() { return call_('changePassword', [].slice.call(arguments)); }
function ping() { return call_('ping', [].slice.call(arguments)); }
function addLog() { return call_('addLog', [].slice.call(arguments)); }
function bootstrap() { return call_('bootstrap', [].slice.call(arguments)); }
function saveDay() { return call_('saveDay', [].slice.call(arguments)); }
function settleWorkers() { return call_('settleWorkers', [].slice.call(arguments)); }
function listPayroll() { return call_('listPayroll', [].slice.call(arguments)); }
function updatePayrollAdj() { return call_('updatePayrollAdj', [].slice.call(arguments)); }
function saveWorker() { return call_('saveWorker', [].slice.call(arguments)); }
function deleteWorkers() { return call_('deleteWorkers', [].slice.call(arguments)); }
function getImage() { return call_('getImage', [].slice.call(arguments)); }
function setUser() { return call_('setUser', [].slice.call(arguments)); }
function addUser() { return call_('addUser', [].slice.call(arguments)); }
function resetUserPassword() { return call_('resetUserPassword', [].slice.call(arguments)); }
function deleteUser() { return call_('deleteUser', [].slice.call(arguments)); }
function getMonitor() { return call_('getMonitor', [].slice.call(arguments)); }
function listGate() { return call_('listGate', [].slice.call(arguments)); }
function saveGate() { return call_('saveGate', [].slice.call(arguments)); }
function deleteGate() { return call_('deleteGate', [].slice.call(arguments)); }
function getGateImage() { return call_('getGateImage', [].slice.call(arguments)); }
function listProcs() { return call_('listProcs', [].slice.call(arguments)); }
function saveProc() { return call_('saveProc', [].slice.call(arguments)); }
function deleteProc() { return call_('deleteProc', [].slice.call(arguments)); }
function getProcFiles() { return call_('getProcFiles', [].slice.call(arguments)); }
function refreshLive() { return call_('refreshLive', [].slice.call(arguments)); }
function srvVer() { return call_('srvVer', [].slice.call(arguments)); }
