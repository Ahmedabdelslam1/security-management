/**
 * Browser-side shim for the local Apps Script host (development only).
 *
 * 1. Replaces `google.script.run` with a forwarder to POST /__gas/exec, keeping
 *    the withSuccessHandler / withFailureHandler contract the app expects.
 *    Like Apps Script, each withSuccessHandler/withFailureHandler call returns a
 *    NEW runner, so concurrent calls never share each other's handlers.
 * 2. Reloads the page when Index.html or Code.gs changes on disk.
 */
(function () {
  function post(fn, args, okHandler, failHandler) {
    function deliver(message) {
      if (failHandler) failHandler({ message: message });
      else if (window.console) console.error(message);
    }
    fetch('/__gas/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: fn, args: args || [] })
    }).then(function (r) {
      return r.json();
    }).then(function (data) {
      if (data && data.ok) {
        if (okHandler) okHandler(data.result);
      } else {
        deliver((data && data.error && data.error.message) || 'خطأ في الخادم');
      }
    }).catch(function (e) {
      deliver('تعذر الاتصال بالخادم المحلي');
      if (window.console) console.error(e);
    });
  }

  function makeRunner(okHandler, failHandler) {
    var base = {
      withSuccessHandler: function (f) { return makeRunner(f, failHandler); },
      withFailureHandler: function (f) { return makeRunner(okHandler, f); }
    };
    return new Proxy(base, {
      get: function (target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop !== 'string') return undefined;
        return function () { post(prop, Array.prototype.slice.call(arguments), okHandler, failHandler); };
      }
    });
  }

  window.google = window.google || {};
  window.google.script = window.google.script || {};
  window.google.script.run = makeRunner(null, null);
})();

(function () {
  var stamp = null;
  setInterval(function () {
    fetch('/__gas/stamp').then(function (r) { return r.json(); }).then(function (d) {
      if (stamp === null) stamp = d.stamp;
      else if (d.stamp !== stamp) location.reload();
    }).catch(function () { /* host restarting */ });
  }, 1500);
})();
