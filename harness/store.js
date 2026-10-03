/**
 * Persistence for the local Apps Script host.
 *
 * The real app keeps its data in a Google Sheet and images in Drive. Locally
 * we keep the equivalent state in a directory that is mounted outside the
 * repository (DATA_DIR), so it survives container restarts and never gets
 * committed.
 */
const fs = require('fs');
const path = require('path');

function empty() {
  return { ss: null, props: {}, cache: {}, folders: [], files: {} };
}

class Store {
  constructor(dir) {
    this.dir = dir;
    this.file = path.join(dir, 'store.json');
    this.filesDir = path.join(dir, 'files');
    fs.mkdirSync(this.filesDir, { recursive: true });
    this.data = this.read();
  }

  read() {
    try {
      return Object.assign(empty(), JSON.parse(fs.readFileSync(this.file, 'utf8')));
    } catch (e) {
      return empty();
    }
  }

  save() {
    const tmp = this.file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.data));
    fs.renameSync(tmp, this.file);
  }

  putFile(id, bytes, meta) {
    fs.writeFileSync(path.join(this.filesDir, id), bytes);
    this.data.files[id] = meta;
    this.save();
  }

  getFileMeta(id) {
    return this.data.files[id] || null;
  }

  readFileBytes(id) {
    return fs.readFileSync(path.join(this.filesDir, id));
  }

  trashFile(id) {
    if (!this.data.files[id]) return;
    delete this.data.files[id];
    try { fs.unlinkSync(path.join(this.filesDir, id)); } catch (e) { /* already gone */ }
    this.save();
  }
}

module.exports = { Store };
