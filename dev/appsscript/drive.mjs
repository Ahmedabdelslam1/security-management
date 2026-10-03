// Minimal DriveApp emulation: folders + files (worker photos / ID cards).
// File bytes are written to DATA_DIR/files/<id>.bin; metadata lives in db.json.
import fs from 'node:fs';
import path from 'node:path';
import { newId } from './store.mjs';

export function createDriveApp(db, dataDir) {
  const filesDir = path.join(dataDir, 'files');
  fs.mkdirSync(filesDir, { recursive: true });

  function fileApi(id) {
    const rec = db.data.files[id];
    if (!rec) throw new Error('لم يتم العثور على الملف: ' + id);
    return {
      getId: () => id,
      getName: () => rec.name,
      setTrashed(v) {
        rec.trashed = !!v;
        db.save();
        return true;
      },
      getBlob() {
        let bytes = Buffer.alloc(0);
        const bin = path.join(filesDir, id + '.bin');
        try { bytes = fs.readFileSync(bin); } catch (e) { /* missing file → empty blob */ }
        return {
          getBytes: () => Array.from(bytes),
          getContentType: () => rec.contentType || 'application/octet-stream',
          getName: () => rec.name
        };
      }
    };
  }

  function folderApi(id) {
    const rec = db.data.folders[id];
    if (!rec) throw new Error('لم يتم العثور على المجلد: ' + id);
    return {
      getId: () => id,
      getName: () => rec.name,
      createFile(blob) {
        const fid = newId();
        fs.writeFileSync(path.join(filesDir, fid + '.bin'), Buffer.from(blob.getBytes()));
        db.data.files[fid] = {
          name: blob.getName(),
          contentType: blob.getContentType(),
          folderId: id,
          trashed: false
        };
        db.save();
        return fileApi(fid);
      }
    };
  }

  return {
    getFoldersByName(name) {
      const ids = Object.keys(db.data.folders).filter((id) => db.data.folders[id].name === name);
      let i = 0;
      return {
        hasNext: () => i < ids.length,
        next: () => {
          if (i >= ids.length) throw new Error('لا يوجد مجلد بهذا الاسم');
          return folderApi(ids[i++]);
        }
      };
    },
    createFolder(name) {
      const id = newId();
      db.data.folders[id] = { name: name || 'Untitled folder' };
      db.save();
      return folderApi(id);
    },
    getFileById(id) { return fileApi(String(id)); }
  };
}
