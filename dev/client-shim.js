// Browser-side stand-in for google.script.run, injected into the page by
// dev/server.mjs. It mirrors the Apps Script client API:
//   google.script.run.withSuccessHandler(fn).withFailureHandler(fn).someServerFn(a, b)
// Each call is a POST to /api/exec, where the real Code.gs function runs.
(function () {
  if (window.google && window.google.script && window.google.script.run) return;

  function invoke(name, args, onSuccess, onFailure) {
    fetch('/api/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: name, args: args })
    })
      .then(function (res) { return res.json(); })
      .then(function (payload) {
        if (payload && payload.ok) {
          if (onSuccess) onSuccess(payload.result);
          return;
        }
        var err = new Error((payload && payload.error) || 'حدث خطأ غير متوقع');
        if (onFailure) onFailure(err); else console.error(err);
      })
      .catch(function (e) {
        var err = e instanceof Error ? e : new Error(String(e));
        if (onFailure) onFailure(err); else console.error(err);
      });
  }

  function makeRunner(onSuccess, onFailure) {
    var base = {
      withSuccessHandler: function (h) { return makeRunner(h, onFailure); },
      withFailureHandler: function (f) { return makeRunner(onSuccess, f); }
    };
    return new Proxy(base, {
      get: function (target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop !== 'string') return undefined;
        return function () {
          invoke(prop, Array.prototype.slice.call(arguments), onSuccess, onFailure);
        };
      }
    });
  }

  window.google = window.google || {};
  window.google.script = window.google.script || {};
  window.google.script.run = makeRunner(null, null);
})();
