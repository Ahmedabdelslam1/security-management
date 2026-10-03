# AGENTS.md — running this repo locally

## What this is
A **Google Apps Script** web app ("إدارة الأمن" — daily worker management). It has no
conventional server: `Code.gs` is the backend and runs inside Google's servers, using
`SpreadsheetApp` as its database and `DriveApp` for worker photos. Both frontends talk
to it through `google.script.run`, and both **refuse to run outside Apps Script** unless
that global is shimmed.

## How it runs here
`dev/` contains a small local **Apps Script runtime** (Node standard library only, no
npm dependencies) that makes the real project run on port 3000:

- `dev/server.mjs` — serves the app's own `Index.html` and exposes `POST /api/exec`.
- `dev/client-shim.js` — browser-side `google.script.run` that POSTs to `/api/exec`.
- `dev/appsscript/runtime.mjs` — loads **`Code.gs` unmodified** into a Node `vm` with
  emulated Google globals.
- `dev/appsscript/{sheets,drive,services,store}.mjs` — the emulated services.

The emulation is a dev harness, not a product: data lives in `/data/db.json` (a mounted
volume) and Drive bytes in `/data/files/`. `Code.gs` is executed as-is — do not port it.

## Which frontend pairs with the backend
The repo contains two frontends and only one of them matches `Code.gs`:

- **`Index.html` (single file) + `Code.gs` — this is the coherent pair**, and what the
  server renders. It calls the backend's real function names (`login`, `bootstrap`,
  `saveDay`, `settleWorkers`, …), attaching the session token via its own `api()` helper.
- `Index2.html` + `Styles.html` + `AppJs.html` (the three-file variant described in
  `README.txt`) call `api*` wrappers (`apiLogin`, `apiGetWorkers`, `apiReportByWorker`, …)
  that **do not exist in `Code.gs`** — that frontend was uploaded without its matching
  backend. Do not wire the server to it; the UI will break on the first call.

If asked to reconcile them, the missing piece is the `api*` server layer (plus report
functions: period/settlement/worker/location/summary) that `AppJs.html` expects.

## Verify it works
```bash
curl -s http://localhost:3000/ | head -c 200          # serves the UI
curl -s -X POST http://localhost:3000/api/exec \
  -H 'Content-Type: application/json' \
  -d '{"fn":"login","args":["admin","admin123"]}'     # returns {ok:true,result:{token:...}}
```
Default login: **admin / admin123** (the admin account is created on first login).

## Quirks
- Editing **`Code.gs` needs a restart** (`docker compose -f docker-compose.base44.yml
  restart web`) — the runtime compiles it at boot. The container runs with
  `node --watch`, but `fs.watch` may not fire across the bind mount, so restart if a
  backend change doesn't take effect. **`Index.html` edits are picked up on refresh**
  (it is re-read per request).
- Sessions live in the emulated `CacheService` (in-process), so a restart logs everyone out.
- To start from a clean database: delete `/data/db.json` and `/data/files` inside the
  container, then restart. The admin account is recreated automatically.
- `README.txt` mentions run-once `setup()` and a Google Sheet; neither is needed here —
  sheets are created lazily on first use.
