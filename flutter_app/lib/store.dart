// تخزين محلي بسيط: shared_preferences وإن تعطّل يرجع لملف محلي/الذاكرة (حتى لا يتعطل التطبيق)
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class Store {
  static final Map<String, String> _mem = {};
  static bool _loaded = false;

  static File get _file => File('${Directory.systemTemp.path}/sm_store.json');

  static Future<void> _loadFile() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final m = jsonDecode(await _file.readAsString()) as Map;
        m.forEach((k, v) => _mem.putIfAbsent('$k', () => '$v'));
      }
    } catch (_) {}
  }

  static Future<void> _flush() async {
    try { await _file.writeAsString(jsonEncode(_mem)); } catch (_) {}
  }

  static Future<String?> get(String k) async {
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 4));
      final v = p.getString(k);
      if (v != null) return v;
    } catch (_) {}
    await _loadFile();
    return _mem[k];
  }

  static Future<void> set(String k, String v) async {
    _mem[k] = v;
    var ok = false;
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 4));
      ok = await p.setString(k, v);
    } catch (_) {}
    if (!ok) await _flush();
  }

  static Future<void> remove(String k) async {
    _mem.remove(k);
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 4));
      await p.remove(k);
    } catch (_) {}
    await _flush();
  }
}
