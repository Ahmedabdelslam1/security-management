/*
 * Browser-side google.script.run shim.
 * The application code (AppJs.html) calls google.script.run.withSuccessHandler(..)
 * .withFailureHandler(..).apiXxx(args). This forwards each call to the harness
 * server, which executes the matching function in Code.gs.
 */
(function () {
  function makeChain() {
    var success = null;
    var failure = null;

    function invoke(fn, args) {
      fetch('/__gas/rpc', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fn: fn, args: args })
      }).then(function (r) {
        return r.json();
      }).then(function (res) {
        if (res && res.ok) {
          if (success) success(res.result);
        } else if (failure) {
          failure({ message: (res && res.error && res.error.message) || 'حدث خطأ' });
        }
      }).catch(function () {
        if (failure) failure({ message: 'تعذر الاتصال بالخادم' });
      });
    }

    var proxy = new Proxy({}, {
      get: function (target, prop) {
        if (prop === 'withSuccessHandler') {
          return function (fn) { success = fn; return proxy; };
        }
        if (prop === 'withFailureHandler') {
          return function (fn) { failure = fn; return proxy; };
        }
        if (prop === 'withUserObject') {
          return function () { return proxy; };
        }
        if (typeof prop !== 'string') return undefined;
        return function () {
          invoke(prop, Array.prototype.slice.call(arguments));
        };
      }
    });
    return proxy;
  }

  var script = {};
  Object.defineProperty(script, 'run', { get: function () { return makeChain(); } });
  script.host = { setHeight: function () {}, close: function () {} };

  window.google = window.google || {};
  window.google.script = script;
})();
