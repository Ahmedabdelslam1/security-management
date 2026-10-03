// JSON-backed persistence for the local Apps Script runtime.
// Everything the emulated Google services keep (sheets, script properties,
// Drive files) lives inside a single JSON file under DATA_DIR.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const newId = () => crypto.randomBytes(12).toString('hex');

export function openDb(rootDir) {
  fs.mkdirSync(rootDir, { recursive: true });
  const file = path.join(rootDir, 'db.json');
  let data = { props: {}, spreadsheets: {}, folders: {}, files: {} };
  if (fs.existsSync(file)) {
    try {
      data = Object.assign(data, JSON.parse(fs.readFileSync(file, 'utf8')));
    } catch (e) {
      console.warn('[store] ignoring unreadable db.json:', e.message);
    }
  }
  function save() {
    try {
      fs.writeFileSync(file, JSON.stringify(data));
    } catch (e) {
      console.error('[store] save failed:', e.message);
    }
  }
  return { data, save, file };
}
