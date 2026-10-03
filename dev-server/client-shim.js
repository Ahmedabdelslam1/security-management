'use strict';
/**
 * Browser-side bridge injected into the served HTML.
 *
 * Implements the `google.script.run` contract the app expects
 * (withSuccessHandler / withFailureHandler / dynamic method call) on top of
 * a plain HTTP POST to /api/exec, plus a live-reload channel so edits to
 * Index.html or Code.gs show up in the preview.
 */
const SHIM_SRC = `
(function () {
  var SUCC = null, FAIL = null;

  function invoke(fn, args) {
    var ok = SUCC, bad = FAIL;
    SUCC = null; FAIL = null;
    fetch('/api/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: fn, args: args })
    }).then(function (r) {
      return r.json();
    }).then(function (res) {
      if (res && res.ok) { if (ok) ok(res.result); }
      else { if (bad) bad(new Error((res && res.error) || 'خطأ غير معروف')); }
    }).catch(function () {
      if (bad) bad(new Error('تعذر الاتصال بالخادم'));
    });
  }

  var RUN, base = {};
  base.withSuccessHandler = function (f) { SUCC = f; return RUN; };
  base.withFailureHandler = function (f) { FAIL = f; return RUN; };

  RUN = new Proxy(base, {
    get: function (t, k) {
      if (k in t) return t[k];
      if (typeof k !== 'string') return undefined;
      return function () { invoke(k, Array.prototype.slice.call(arguments)); };
    }
  });

  window.google = window.google || {};
  window.google.script = window.google.script || {};
  window.google.script.run = RUN;

  try {
    var es = new EventSource('/__livereload');
    es.onmessage = function (ev) { if (ev.data === 'reload') location.reload(); };
  } catch (e) { /* no live reload */ }
})();
`;

module.exports = { SHIM_SRC };
