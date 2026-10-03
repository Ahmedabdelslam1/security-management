# AGENTS.md

## What this project is

A **Google Apps Script** web app (Arabic UI, "إدارة الأمن") — an attendance/workers
system for security staff. There is no package.json, build step, or test suite.
The deployment target is script.google.com (`appsscript.json` + `README.txt` hold the
publish steps). Google Sheets is the database and Google Drive stores images.

**No external credentials are needed to run it locally** — the data layer is emulated
(see below). Real publishing happens in the user's own Google account and cannot be
done from this sandbox.

## Which files are the working app

* `Code.gs` — the entire backend (auth, workers, attendance, settlements, reports, logs).
* `Index.html` — the standalone page (inline CSS **and** inline JS). It corresponds
  exactly to the server functions in `Code.gs`; this is the file the preview serves.
* `Styles.html` — the modular copy of the styles that are inlined in `Index.html`.
* `Index2.html` + `AppJs.html` — a newer modular client that calls an `api*` server
  layer (`apiLogin`, `apiSaveDay`, …) that **does not exist in `Code.gs`**. That pair is
  inconsistent with the backend and must not be served until someone adds those
  functions. `Index.html` + `Code.gs` is the pair that works.

## Local preview harness (`server/`, `docker-compose.base44.yml`)

`docker compose -f docker-compose.base44.yml up -d --build` runs `node server/index.js`
(node:22, repo bind-mounted at `/app`, no dependencies to install) and:

* serves `Index.html` on port 3000 with `server/client-shim.js` injected into `<head>`
  (it must come before the inline app script, which feature-detects `google.script.run`);
* executes the real, unmodified `Code.gs` inside a `vm` context (`server/runtime.js`);
* emulates the Apps Script server globals Code.gs uses (`server/gas.js`):
  `SpreadsheetApp` (Sheets → JSON), `DriveApp` (blobs → files on disk), `Utilities`,
  `CacheService`, `PropertiesService`, `LockService`, `HtmlService`;
* routes `google.script.run.fn(...)` calls over `POST /__gas/api`.

### Things worth knowing

* **Data lives in the `preview-data` Docker volume** (`DATA_DIR=/data`), never in the
  repo. `docker compose -f docker-compose.base44.yml down -v` resets the app to an
  empty database; the admin user is recreated on the next boot.
* First boot runs `setup()` automatically (README step 4) to create the sheets + admin.
* Default login: **admin / admin123**.
* `Index.html` and `Code.gs` are re-read from disk on every request, and an SSE channel
  live-reloads the page when either changes — no restart needed for app edits.
  Edits under `server/` restart the node process (`node --watch`).
* Sessions live in the emulated `CacheService` (in-process), so restarting the
  container invalidates tokens; the browser just re-logs in.

### How to verify it works

```bash
curl -s localhost:3000/healthz                    # -> ok
curl -s -X POST localhost:3000/__gas/api \
  -H 'Content-Type: application/json' \
  -d '{"fn":"login","args":["admin","admin123"]}'  # -> {"ok":true,"result":{"token":"..."}}
```
Then `bootstrap` with that token should return the user, workers, attendance and locations.

## Deploying for real

Keep editing the Apps Script files; after changes, re-publish in the Apps Script editor
(Deploy → Manage deployments → Edit → New version), as `README.txt` describes.
