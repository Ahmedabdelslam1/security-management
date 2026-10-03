// Minimal SpreadsheetApp emulation: just the surface Code.gs actually uses.
// Sheets are stored as dense row arrays (row 1 = index 0) with string cells,
// so readAll_/writeAll_ round-trip exactly like the real thing.
import { newId } from './store.mjs';

const DEFAULT_ROWS = 1000;
const DEFAULT_COLS = 26;

const cell = (sh, r, c) => {
  const row = sh.rows[r - 1];
  const v = row ? row[c - 1] : undefined;
  return v == null ? '' : v;
};

function setCell(sh, r, c, v) {
  if (r > sh.maxRows) sh.maxRows = r;
  if (c > sh.maxCols) sh.maxCols = c;
  while (sh.rows.length < r) sh.rows.push([]);
  const row = sh.rows[r - 1];
  while (row.length < c) row.push('');
  row[c - 1] = v == null ? '' : String(v);
}

function lastRow(sh) {
  for (let r = sh.rows.length; r >= 1; r--) {
    const row = sh.rows[r - 1] || [];
    for (let c = 0; c < row.length; c++) {
      if (row[c] !== '' && row[c] != null) return r;
    }
  }
  return 0;
}

export function createSpreadsheetApp(db) {
  const ss = (id) => {
    const s = db.data.spreadsheets[id];
    if (!s) throw new Error('لم يتم العثور على الجدول: ' + id);
    return s;
  };
  const sheet = (id, name) => {
    const s = ss(id).sheets[name];
    if (!s) throw new Error('لا يوجد شيت بالاسم: ' + name);
    return s;
  };

  function rangeApi(id, name, row, col, numRows, numCols) {
    const api = {
      getValues() {
        const s = sheet(id, name);
        const out = [];
        for (let r = 0; r < numRows; r++) {
          const line = [];
          for (let c = 0; c < numCols; c++) line.push(cell(s, row + r, col + c));
          out.push(line);
        }
        return out;
      },
      setValues(values) {
        const s = sheet(id, name);
        for (let r = 0; r < values.length; r++) {
          for (let c = 0; c < values[r].length; c++) setCell(s, row + r, col + c, values[r][c]);
        }
        db.save();
        return api;
      },
      setValue(v) {
        setCell(sheet(id, name), row, col, v);
        db.save();
        return api;
      },
      getValue() {
        return cell(sheet(id, name), row, col);
      },
      clearContent() {
        const s = sheet(id, name);
        for (let r = 0; r < numRows; r++) {
          for (let c = 0; c < numCols; c++) setCell(s, row + r, col + c, '');
        }
        db.save();
        return api;
      },
      setNumberFormat() { return api; },
      setFontWeight() { return api; },
      getNumRows: () => numRows,
      getNumColumns: () => numCols
    };
    return api;
  }

  function sheetApi(id, name) {
    const data = () => sheet(id, name);
    const api = {
      getName: () => name,
      getMaxRows: () => data().maxRows,
      getMaxColumns: () => data().maxCols,
      getLastRow: () => lastRow(data()),
      getRange(row, col, numRows, numCols) {
        return rangeApi(id, name, row, col, numRows == null ? 1 : numRows, numCols == null ? 1 : numCols);
      },
      appendRow(values) {
        const s = data();
        const r = lastRow(s) + 1;
        values.forEach((v, i) => setCell(s, r, i + 1, v));
        db.save();
        return api;
      },
      deleteRows(startRow, howMany) {
        data().rows.splice(startRow - 1, howMany);
        db.save();
        return api;
      },
      insertRowsAfter(afterRow, howMany) {
        const s = data();
        s.maxRows = Math.max(s.maxRows, afterRow + howMany);
        db.save();
        return api;
      },
      insertColumnsAfter(afterCol, howMany) {
        const s = data();
        s.maxCols = Math.max(s.maxCols, afterCol + howMany);
        db.save();
        return api;
      },
      setFrozenRows() { return api; },
      setRightToLeft() { return api; },
      setColumnWidth() { return api; }
    };
    return api;
  }

  function spreadsheetApi(id) {
    const s = ss(id);
    return {
      getId: () => id,
      getUrl: () => s.url,
      getName: () => s.name,
      getSheetByName: (name) => (s.sheets[name] ? sheetApi(id, name) : null),
      insertSheet: (name) => {
        s.sheets[name] = { maxRows: DEFAULT_ROWS, maxCols: DEFAULT_COLS, rows: [] };
        db.save();
        return sheetApi(id, name);
      },
      getSheets: () => Object.keys(s.sheets).map((n) => sheetApi(id, n))
    };
  }

  return {
    create(name) {
      const id = newId();
      db.data.spreadsheets[id] = {
        name: name || 'Untitled',
        url: 'https://docs.google.com/spreadsheets/d/' + id + '/edit',
        sheets: {}
      };
      db.save();
      return spreadsheetApi(id);
    },
    openById(id) { return spreadsheetApi(String(id)); },
    getActiveSpreadsheet() {
      const id = Object.keys(db.data.spreadsheets)[0];
      return id ? spreadsheetApi(id) : null;
    }
  };
}
