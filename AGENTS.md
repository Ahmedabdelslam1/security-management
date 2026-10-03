# AGENTS.md — إدارة الأمن (Google Apps Script project)

## What this repository is
A Google Apps Script web app (Arabic, RTL) for daily staff management: the UI is
`Index.html`, the backend is `Code.gs` (functions called through
`google.script.run`). In the real deployment the data lives in a Google Sheet
and images in Google Drive.

## Which files are current
- `Index.html` — **the app UI actually served.** Self-contained (styles + script
  inline) and the newest: it includes the gate log (دفتر البوابة), which the older
  split files do not.
- `Code.gs` — the server (includes the gate-log functions). Client/server
  contract verified: every `api('...')` call in `Index.html` exists in `Code.gs`.
- `Index2.html` + `Styles.html` + `AppJs.html` — older Apps Script split version
  (`Index2.html` is what `doGet()` refers to as `index`). It lags behind
  `Index.html` (no gate log). Kept for reference only.
- `....٪.html` — an older standalone preview copy of `Index.html` (no gate log).
- `README.txt` — install steps for the real Apps Script deployment.

## Running it here (development)
Apps Script cannot run outside Google's servers, so `harness/` is a local host
with the same UI and the same `Code.gs`:

```
docker compose -f docker-compose.base44.yml up -d
```

- Serves `Index.html` on port 3000, injecting `<script src="/__gas/shim.js">`
  in front of the app script (the repository file itself is untouched).
- `harness/client-shim.js` implements `google.script.run` by POSTing to
  `/__gas/exec`; it also reloads the page when `Index.html`/`Code.gs` change.
- `harness/loader.js` executes `Code.gs` in a `vm` context with the stand-ins
  from `harness/apps-script.js` (SpreadsheetApp, DriveApp, PropertiesService,
  CacheService, LockService, Utilities, HtmlService).
- State (emulated spreadsheet, script properties, session cache, images) is
  written to the `gas-data` docker volume mounted at `/data`. Delete the volume
  to start from a clean install (`docker compose -f docker-compose.base44.yml
  down -v`).
- No credentials are needed and no npm dependencies are installed — the harness
  is plain Node.

## Default credentials
`admin` / `admin123` (created on first `login` by `ensureAdmin_()`).
Change it in the app via the 🔑 button.

## Notes / gotchas
- All timestamps use `TZ=Africa/Cairo` (set in compose); `Utilities.formatDate`
  is emulated with `Intl` and supports only the `yyyy-MM-dd[ HH:mm:ss]` patterns
  the code uses.
- Login sessions are kept in the emulated script cache (persisted), so they
  survive container restarts until `SESSION_TTL` (6h) expires.
- Verification: `curl -s localhost:3000 | head`, then sign in. Logs:
  `docker compose -f docker-compose.base44.yml logs -f app`.
- Never edit `harness/` for app behaviour; it only emulates Google's services.
