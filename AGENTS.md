# AGENTS.md

## What this project is
A **Google Apps Script** web app (Arabic — "إدارة الأمن", a daily worker / attendance
management system). It is *not* a Node/Python web app: `Code.gs` runs on Google's
servers against `SpreadsheetApp` (the database), `DriveApp` (images), `CacheService`
(sessions), `PropertiesService` and `HtmlService`. `Index.html` is the whole frontend
(styles + JS inline) and talks to the backend only through `google.script.run`.

`AppJs.html`, `Styles.html` and `Index2.html` are leftovers from an older split
version. **`Index.html` is the live frontend** (`doGet` serves it), do not edit the
others expecting an effect.

## How it runs in Base44
`docker-compose.base44.yml` runs `dev-server/server.js` on `node:22` with the repo
bind-mounted. That server emulates the Apps Script runtime:

- `dev-server/gas-runtime.js` — `vm` sandbox that injects the Google globals
  (`SpreadsheetApp`, `DriveApp`, `Utilities`, `CacheService`, `LockService`,
  `PropertiesService`, `HtmlService`) and executes `Code.gs`.
- `dev-server/store.js` — JSON persistence, on the `gasdata` volume at `/data`
  (`ss.json` = simulated spreadsheet, `drive.json` + `drive/` = simulated Drive,
  `props.json` = script properties). Never inside the repo.
- `dev-server/client-shim.js` — the browser-side `google.script.run` implementation
  (POSTs to `/api/exec`), plus the live-reload channel.
- `GET /` renders `doGet()`; `POST /api/exec` runs a `Code.gs` function;
  `GET /api/health` is the compose healthcheck.

No npm dependencies — nothing to install, no lockfile to keep in sync.

## Editing loop
- **Frontend** (`Index.html`): refresh the page (or live reload fires).
- **Backend** (`Code.gs`): nothing to restart — each request recompiles the script.
  Live reload also refreshes the page automatically.

## First login / resetting data
- Admin credentials: `admin` / `admin123` (from the README; the seeded row is created
  lazily by `ensureAdmin_()`).
- To wipe the simulated database: `docker compose -f docker-compose.base44.yml down -v`
  (drops the `gasdata` volume) — the app recreates a fresh sheet on next request.

## Verification
```
curl -s -o /dev/null -w '%{http_code}\n' localhost:3000/api/health   # expect 200
curl -s localhost:3000 | grep -c google.script.run                   # shim injected
```
Log in with `admin` / `admin123` to confirm the app itself works end to end.

## Gotchas
- `Code.gs` uses `Africa/Cairo` for all dates; the emulator honours it via `Intl`.
- Sessions live in the in-process script cache: restarting the container logs users
  out (same as Apps Script cache eviction).
- The emulator is a dev harness, not a deployment target. Real deployment stays on
  Apps Script (Extensions → Apps Script → Deploy → Web app), per `README.txt`.
