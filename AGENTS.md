> **Note:** This is a **Google Apps Script** project (see `README.txt`). It is not a
> conventional web app: `Code.gs` runs on Google's Apps Script runtime, the database
> is a Google Sheet, sessions live in `CacheService`, and images are stored in Google
> Drive. `Index.html` / `Styles.html` / `AppJs.html` are `HtmlService` templates.

# Running it locally (sandbox / preview)

`harness/` is a **local development host** that runs the app unchanged:

- `harness/gas-runtime.js` — emulates `SpreadsheetApp`, `PropertiesService`, `DriveApp`,
  `Utilities`, `Session`, `CacheService`. State is persisted to the `gas_data` volume
  at `/data/gas-db.json`, so the "spreadsheet" survives restarts.
- `harness/server.js` — serves `Index.html` with the `<?!= include('X') ?>` templates
  resolved, injects the `google.script.run` shim, and executes `Code.gs` in a `vm`
  context. **`Code.gs` is re-read on every request**, so edits apply with no restart.
- `harness/client-shim.js` — browser side of `google.script.run`; forwards every
  `apiXxx(...)` call to `POST /__gas/rpc`.

```bash
docker compose -f docker-compose.base44.yml up -d     # http://localhost:3000
docker compose -f docker-compose.base44.yml logs -f web
```

No dependencies and no build step: the harness uses only the Node standard library.
There are **no external credentials** to configure — Sheets, Drive and Cache are all
emulated locally.

Default admin login: `admin` / `admin123`.

## Verifying it works

```bash
curl -s localhost:3000/__gas/health          # -> ok
curl -s localhost:3000 | head -20            # rendered page, no <?!= ... ?> left
curl -s -X POST localhost:3000/__gas/rpc \
  -H 'Content-Type: application/json' \
  -d '{"fn":"apiLogin","args":["admin","admin123"]}'
```

The login call must return `{"ok":true,"result":{"token":"...","user":{...}}}`.

## Known limitations of the local harness

- **Uploaded worker photos/cards will not display.** `AppJs.html` builds image URLs
  as `https://drive.google.com/thumbnail?id=<id>`, and the harness has no real Drive.
  Uploads still save (bytes land in `/data/images/`); only the thumbnails are missing.
- Emulated `Utilities.formatDate` supports the `yyyy-MM-dd` and `yyyy-MM-dd HH:mm`
  patterns the app uses. Anything else needs extending in `harness/gas-runtime.js`.
- Sheet row/column semantics follow what `Code.gs` actually uses (`getDataRange`,
  `getRange`, `setValue`, `setValues`, `appendRow`, `deleteRow`, `clearContent`).

## Deploying for real

Deployment remains Google Apps Script, as described in `README.txt`: create a project
at <https://script.google.com>, paste `Code.gs` plus the three HTML files, run `setup()`
once, then Deploy → New deployment → Web app (Execute as: Me, Access: Anyone).
Re-deploy a new version after code changes. The harness is development-only.

## Repo layout

| File | Role |
| --- | --- |
| `Code.gs` | Server logic (auth, workers, attendance, settlement, reports, activity log) |
| `Index.html` | UI structure |
| `Styles.html` | Styling |
| `AppJs.html` | Client logic |
| `harness/` | Local Apps Script runtime (development only) |
| `docker-compose.base44.yml` | Local dev stack (web on port 3000) |
