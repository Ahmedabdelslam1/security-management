/*
 * Browser-side stand-in for `google.script.run`.
 * Forwards every server call to the local runtime over HTTP, using the same
 * success/failure handler contract as Apps Script. Also wires up live reload.
 */
(function () {
  'use strict';

  function invoke(fnName, args, onSuccess, onFailure) {
    fetch('/__gas/api', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: fnName, args: args })
    })
      .then(function (res) { return res.json(); })
      .then(function (payload) {
        if (payload && payload.ok) {
          if (onSuccess) onSuccess(payload.result);
          return;
        }
        var err = new Error((payload && payload.error) || 'حدث خطأ في الخادم');
        if (onFailure) onFailure(err);
        else console.error(err);
      })
      .catch(function (err) {
        var e = err instanceof Error ? err : new Error(String(err));
        if (onFailure) onFailure(e);
        else console.error(e);
      });
  }

  function makeRunner(onSuccess, onFailure) {
    return new Proxy({}, {
      get: function (target, prop) {
        if (prop === 'withSuccessHandler') return function (fn) { return makeRunner(fn, onFailure); };
        if (prop === 'withFailureHandler') return function (fn) { return makeRunner(onSuccess, fn); };
        if (prop === 'withUserObject') return function () { return makeRunner(onSuccess, onFailure); };
        if (typeof prop !== 'string') return undefined;
        return function () {
          return invoke(prop, Array.prototype.slice.call(arguments), onSuccess, onFailure);
        };
      }
    });
  }

  window.google = window.google || {};
  google.script = google.script || {};
  google.script.run = makeRunner(null, null);
  google.script.host = { close: function () {}, setHeight: function () {}, editor: {} };
  google.script.url = { getLocation: function (cb) { if (cb) cb({ parameter: {}, hash: '' }); } };

  /* Live reload: the server watches Code.gs / Index.html and pings us on change. */
  try {
    var source = new EventSource('/__gas/live');
    source.onmessage = function (event) {
      if (event.data === 'reload') window.location.reload();
    };
  } catch (e) {
    /* live reload is best-effort */
  }
})();
