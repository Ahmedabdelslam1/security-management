// مخزن الصور المرفقة: حفظ صور البنود (عاملين/مستخدمين/عام) على الجهاز + ميتاداتا
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class Attach {
  final String id, key, label, path;
  final DateTime date;
  const Attach({required this.id, required this.key, required this.label, required this.path, required this.date});
  Map<String, dynamic> toJson() => {'id': id, 'key': key, 'label': label, 'path': path, 'date': date.toIso8601String()};
  static Attach fromJson(Map j) => Attach(
        id: j['id'], key: j['key'], label: j['label'], path: j['path'],
        date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
      );
}

class AttachStore extends ChangeNotifier {
  static final AttachStore I = AttachStore._();
  AttachStore._();

  List<Attach> items = [];
  Directory? _dir;
  bool _loaded = false;

  Future<Directory> _docs() async {
    if (_dir == null) _dir = Directory('${(await getApplicationDocumentsDirectory()).path}/attachments');
    if (!(_dir!.existsSync())) _dir!.createSync(recursive: true);
    return _dir!;
  }

  Future<void> ensure() async {
    if (_loaded) return;
    try {
      final d = await _docs();
      final f = File('${d.path}/meta.json');
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as List;
        items = j.map((e) => Attach.fromJson(e as Map)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final d = await _docs();
      File('${d.path}/meta.json').writeAsStringSync(jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// يضيف صورة من الكاميرا أو المعرض ويربطها ببند
  Future<bool> add({required String key, required String label, required ImageSource source}) async {
    try {
      final p = await ImagePicker().pickImage(source: source, imageQuality: 72, maxWidth: 1600);
      if (p == null) return false;
      final d = await _docs();
      final id = '${DateTime.now().millisecondsSinceEpoch}_${key.hashCode.abs()}';
      final f = File('${d.path}/$id.jpg');
      await f.writeAsBytes(await p.readAsBytes());
      items.insert(0, Attach(id: id, key: key, label: label, path: f.path, date: DateTime.now()));
      await _save();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String id) async {
    final i = items.indexWhere((a) => a.id == id);
    if (i == -1) return;
    try { File(items[i].path).deleteSync(); } catch (_) {}
    items.removeAt(i);
    await _save();
    notifyListeners();
  }

  List<Attach> forItem(String key) => items.where((a) => a.key == key).toList();
  List<Attach> get all => items;
}
