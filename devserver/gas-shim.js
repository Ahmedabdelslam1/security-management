/*
 * جسر المتصفح: محاكاة `google.script.run` محليًا.
 *
 * يُضاف تلقائيًا إلى الصفحة التي يقدّمها devserver/server.js، ويرسل كل نداء
 * (fn, args) إلى السيرفر المحلي الذي ينفّذ دوال Code.gs الحقيقية.
 * لا يُعدَّل أي ملف من ملفات التطبيق.
 */
(function () {
  if (window.google && window.google.script && window.google.script.run && window.google.script.run.__local) return;

  var handlers = { success: null, failure: null };

  function run(fn, args, onOk, onFail) {
    fetch('/__gas/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: fn, args: args })
    }).then(function (r) { return r.json(); }).then(function (res) {
      if (res && res.ok) { if (onOk) onOk(res.value); }
      else {
        var err = new Error((res && res.error) || 'حدث خطأ');
        if (onFail) onFail(err); else console.error(err);
      }
    }).catch(function (e) { if (onFail) onFail(e); else console.error(e); });
  }

  var proxy;
  var client = {
    withSuccessHandler: function (h) { handlers.success = h; return proxy; },
    withFailureHandler: function (h) { handlers.failure = h; return proxy; }
  };

  proxy = new Proxy(client, {
    get: function (target, prop) {
      if (prop in target) return target[prop];
      if (prop === '__local') return true;
      return function () {
        var args = Array.prototype.slice.call(arguments);
        run(String(prop), args, handlers.success, handlers.failure);
      };
    }
  });

  window.google = window.google || {};
  window.google.script = window.google.script || {};
  window.google.script.run = proxy;
  window.google.script.host = window.google.script.host || { close: function () { } };

  /* إعادة تحميل المعاينة تلقائيًا عند تغيير أي ملف من ملفات المشروع. */
  var known = null;
  setInterval(function () {
    fetch('/__gas/version', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (known === null) known = d.v;
        else if (d.v !== known) { known = d.v; window.location.reload(); }
      })
      .catch(function () { });
  }, 1200);
})();
