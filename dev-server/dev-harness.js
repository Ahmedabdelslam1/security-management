/* Local preview bridge: emulates google.script.run on top of HTTP. */
(function () {
  function call(fn, args, onSuccess, onFailure) {
    fetch('/api/call', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fn: fn, args: args })
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data && data.ok) {
          if (onSuccess) onSuccess(data.result);
        } else if (onFailure) {
          onFailure({ message: (data && data.message) || 'حدث خطأ' });
        }
      })
      .catch(function () {
        if (onFailure) onFailure({ message: 'تعذر الاتصال بالخادم' });
      });
  }

  function runner(onSuccess, onFailure) {
    var handlers = {
      withSuccessHandler: function (f) { return runner(f, onFailure); },
      withFailureHandler: function (f) { return runner(onSuccess, f); }
    };
    return new Proxy(handlers, {
      get: function (target, prop) {
        if (prop in target) return target[prop];
        return function () {
          call(prop, Array.prototype.slice.call(arguments), onSuccess, onFailure);
        };
      }
    });
  }

  window.google = window.google || {};
  window.google.script = { run: runner(null, null) };

  /* Images live on the local dev server instead of Google Drive. */
  window.imgThumb = function (id) { return '/img/' + encodeURIComponent(id); };
})();
