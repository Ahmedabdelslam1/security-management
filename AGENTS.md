# AGENTS.md

## What this project is

"إدارة الأمن" is a **Google Apps Script** web app (Arabic, RTL, daily-workers
management). Files:

- `Code.gs` — server code: data access (Google Sheets), users/sessions,
  attendance, settlement, locations, reports, activity log. Runs only on
  Google's servers. **Plain ES5-style JavaScript, no modules.**
- `Index.html` — page structure, `Styles.html` — CSS, `AppJs.html` — frontend
  logic.

The frontend has no HTTP calls of its own: every server interaction goes through
`gs(fn, ...args)` in `AppJs.html`, which wraps `google.script.run`.

## Running it locally (Base44 preview)

`docker-compose.base44.yml` starts one `web` service on port 3000 running
`dev-server/server.js`, which:

- executes the real, unmodified `Code.gs` inside a Node `vm` context built by
  `dev-server/appsscript-shim.js`. The shim emulates the Apps Script services
  Code.gs uses (`SpreadsheetApp`, `DriveApp`, `CacheService`,
  `PropertiesService`, `Utilities`, `Session`, `HtmlService`);
- renders `Index.html` with the Apps Script template tag
  `<?!= include('Styles') ?>` / `<?!= include('AppJs') ?>`;
- serves `dev-server/dev-harness.js`, which emulates `google.script.run` in the
  browser over `POST /api/call { fn, args }`.

Non-obvious points:

- **No npm dependencies.** The harness is pure Node stdlib; `node:22` is enough.
- Sheets are stored as JSON (`database.json`) and Drive images as files under the
  `app_data` volume (`APP_DATA_DIR=/data`), never in the repo.
- `dev-server` reloads `Code.gs` automatically when its mtime changes; HTML/CSS
  is re-read on every request, so use `reload_preview` to see markup changes.
- The default admin account is `admin` / `admin123` (created by `Code.gs`).
- `imgThumb()` is overridden by the dev harness to load images from `/img/<id>`,
  since Google Drive is not reachable in the preview.
- Google Cloud / Apps Script credentials are **not** needed for the local
  preview. Real deployment is still "Deploy → Web app" per `README.txt`.
- Reset local data: `docker compose -f docker-compose.base44.yml down -v`.

## Verifying it works

```bash
docker compose -f docker-compose.base44.yml up -d --build
curl -sS -X POST localhost:3000/api/call \
  -H 'Content-Type: application/json' \
  -d '{"fn":"apiLogin","args":["admin","admin123"]}'
```

A JSON response with `"ok": true` and a `token` means the Apps Script runtime
emulation and the data layer are both working.

## Deployment

Real hosting is Google Apps Script (see `README.txt`): paste `Code.gs` into a
script project, add the three HTML files, run `setup()` once, then publish as a
web app (Execute as: Me / Who has access: Anyone). The local stack is for
development and preview only; it is not a production deployment.
