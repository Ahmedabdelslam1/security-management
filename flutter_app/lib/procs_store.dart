// الإجراءات اليومية: تعمل دائمًا حتى لو سكربت Google قديم ولا يعرف دوال الإجراءات.
// - لو السيرفر يدعمها: كل شيء يمرّ عليه كالمعتاد، وأي سجلات محفوظة محليًا تُرفع تلقائيًا ثم تُحذف من الهاتف.
// - لو السيرفر قديم: تُحفظ السجلات على الهاتف (بنفس رقم القيد والشكل) وتُرفع وحدها لاحقًا — بدون أي رسالة خطأ.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'state.dart';

class ProcsStore {
  static const _days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  static List<Map> _server = [];

  static bool _unknown(Object e) => e is ApiException && (e.message.contains('غير معروف') || e.message.contains('Unknown'));

  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/procs_local.json');

  static Future<List<Map>> _readLocal() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final j = jsonDecode(await f.readAsString());
      return (j as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeLocal(List<Map> rows) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(rows));
  }

  static String _p2(int n) => n < 10 ? '0$n' : '$n';

  static String _weekday(String date) {
    final d = DateTime.tryParse(date);
    return d == null ? '' : _days[d.weekday % 7];
  }

  static String _entry(String date, int n) {
    final p = date.split('-');
    if (p.length != 3) return '';
    final page = ((n - 1) ~/ 25) + 1, line = ((n - 1) % 25) + 1;
    return '${p[0].substring(p[0].length - 2)}${p[1]}${p[2]}${_p2(page)}${_p2(line)}';
  }

  static int _seqMax(List<Map> a) {
    var m = 0;
    for (final x in a) {
      final s = int.tryParse('${x['seq'] ?? 0}') ?? 0;
      if (s > m) m = s;
    }
    return m;
  }

  static Map _view(Map l) {
    List types(String k) => ((l[k] ?? []) as List).map((f) => (f as Map)['t']).toList();
    return {
      'id': l['id'], 'seq': l['seq'], 'date': l['date'], 'weekday': l['weekday'], 'plate': l['plate'], 'driver': l['driver'], 'rep': l['rep'],
      'statement': l['statement'], 'ptype': l['ptype'], 'signed': l['signed'], 'signDate': l['signDate'], 'signer': l['signer'],
      'bookPage': l['bookPage'], 'supervisor': l['supervisor'], 'notes': l['notes'],
      'docs': types('docs'), 'other': types('other'), 'entryNo': l['entryNo'], 'createdBy': l['createdBy'], 'local': true,
    };
  }

  static Map _toSave(Map l) => {
        'date': l['date'], 'plate': l['plate'], 'driver': l['driver'], 'rep': l['rep'], 'statement': l['statement'], 'ptype': l['ptype'],
        'signed': l['signed'], 'signDate': l['signDate'], 'signer': l['signer'], 'bookPage': l['bookPage'], 'supervisor': l['supervisor'], 'notes': l['notes'],
        'newDocs': ((l['docs'] ?? []) as List).map((f) => (f as Map)['data']).toList(),
        'newOther': ((l['other'] ?? []) as List).map((f) => (f as Map)['data']).toList(),
        'removeDocs': [], 'removeOther': [],
      };

  static Future<List<Map>> _fetchServer() async {
    final r = await Api.auth('listProcs') as List;
    return r.map((x) => x as Map).toList();
  }

  /// قائمة الإجراءات (السيرفر + المحفوظ محليًا)
  static Future<List<Map>> list() async {
    var ok = true;
    var server = <Map>[];
    try {
      server = await _fetchServer();
    } on ApiException catch (e) {
      if (!_unknown(e)) rethrow;
      ok = false;
    }
    var local = await _readLocal();
    if (ok && local.isNotEmpty) {
      final rest = <Map>[];
      for (final l in local) {
        try {
          await Api.auth('saveProc', [_toSave(l)]);
        } on SessionExpired {
          rethrow;
        } catch (_) {
          rest.add(l);
        }
      }
      if (rest.length != local.length) {
        await _writeLocal(rest);
        try {
          server = await _fetchServer();
        } catch (_) {}
      }
      local = rest;
    }
    _server = server;
    return [...local.map(_view), ...server];
  }

  /// حفظ (جديد أو تعديل). يرجع نفس شكل رد السيرفر.
  static Future<Map> save(Map e) async {
    final id = '${e['id'] ?? ''}';
    if (!id.startsWith('L')) {
      try {
        return await Api.auth('saveProc', [e]) as Map;
      } on ApiException catch (x) {
        if (!_unknown(x)) rethrow;
      }
    }
    final local = await _readLocal();
    Map? cur;
    if (id.startsWith('L')) {
      for (final l in local) {
        if (l['id'] == id) cur = l;
      }
    }
    final date = '${e['date']}';
    if (cur == null) {
      final all = [..._server, ...local];
      final sameDay = all.where((x) => '${x['date']}' == date).length;
      cur = {
        'id': 'L${DateTime.now().millisecondsSinceEpoch}',
        'seq': _seqMax(all) + 1,
        'docs': [], 'other': [],
        'entryNo': _entry(date, sameDay + 1),
        'createdBy': App.I.user?.name ?? '',
      };
      local.add(cur);
    }
    for (final k in ['plate', 'driver', 'rep', 'statement', 'ptype', 'signed', 'signDate', 'signer', 'bookPage', 'supervisor', 'notes']) {
      cur[k] = '${e[k] ?? ''}';
    }
    cur['date'] = date;
    cur['weekday'] = _weekday(date);
    void files(String field, String newKey, String rmKey) {
      final old = ((cur![field] ?? []) as List).map((x) => x as Map).toList();
      final rm = ((e[rmKey] ?? []) as List).map((x) => int.tryParse('$x') ?? -1).toSet();
      final keep = <Map>[for (var i = 0; i < old.length; i++) if (!rm.contains(i)) old[i]];
      for (final d in ((e[newKey] ?? []) as List)) {
        final s = '$d';
        keep.add({'t': s.startsWith('data:application/pdf') ? 'pdf' : 'img', 'data': s});
      }
      cur[field] = keep;
    }
    files('docs', 'newDocs', 'removeDocs');
    files('other', 'newOther', 'removeOther');
    await _writeLocal(local);
    return _view(cur);
  }

  static Future<void> delete(String id) async {
    if (id.startsWith('L')) {
      final local = await _readLocal();
      local.removeWhere((l) => l['id'] == id);
      await _writeLocal(local);
      return;
    }
    await Api.auth('deleteProc', [id]);
  }

  static Future<Map> files(String id) async {
    if (id.startsWith('L')) {
      for (final l in await _readLocal()) {
        if (l['id'] == id) return {'docs': l['docs'] ?? [], 'other': l['other'] ?? []};
      }
      return {'docs': [], 'other': []};
    }
    return await Api.auth('getProcFiles', [id]) as Map;
  }
}
