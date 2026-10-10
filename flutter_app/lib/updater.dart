// التحديث التلقائي: يفحص app-version.json في المستودع، ولو فيه إصدار أحدث
// يحمّل الـ APK ويفتح المثبّت تلقائيًا — بالكامل في الخلفية بدون أي نافذة أو إشعار
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String appVersion = '1.10.22';
const String _versionUrl =
    'https://raw.githubusercontent.com/Ahmedabdelslam1/security-management/main/app-version.json';
const String _apkUrl =
    'https://github.com/Ahmedabdelslam1/security-management/releases/download/v1.0-android/security-management.apk';

const _channel = MethodChannel('app_installer');

int _verNum(String v) {
  final parts = v.split('+').first.split('.');
  int n = 0;
  for (final s in parts) {
    n = n * 100 + (int.tryParse(s.trim()) ?? 0);
  }
  return n;
}

/// يرجع رقم أحدث إصدار متاح أو null لو لا يوجد أو النسخة هي نفسها
Future<String?> fetchNewerVersion() async {
  try {
    final r = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final v = (j['version'] ?? '').toString();
    if (v.isEmpty) return null;
    return _verNum(v) > _verNum(appVersion) ? v : null;
  } catch (_) {
    return null; // صمت: مفيش إنترنت أو المستودع غير متاح — التطبيق يكمل شغله
  }
}

const String _runsUrl =
    'https://api.github.com/repos/Ahmedabdelslam1/security-management/actions/workflows/build-apk.yml/runs?status=success&branch=main&per_page=1';

/// يبحث في GitHub Actions عن آخر بناء ناجح للتطبيق ويقرأ رقم إصداره من pubspec.yaml الخاص بنفس الـ commit.
/// يرجع نص الإصدار (مثل 1.10.16) أو null لو تعذر الاتصال بـ Actions.
Future<String?> latestFromActions() async {
  try {
    final r = await http
        .get(Uri.parse(_runsUrl), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final runs = (j['workflow_runs'] as List?) ?? const [];
    if (runs.isEmpty) return null;
    final sha = (runs.first as Map)['head_sha']?.toString() ?? '';
    if (sha.isEmpty) return null;
    final p = await http
        .get(Uri.parse('https://raw.githubusercontent.com/Ahmedabdelslam1/security-management/$sha/flutter_app/pubspec.yaml'))
        .timeout(const Duration(seconds: 12));
    if (p.statusCode != 200) return null;
    final m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(utf8.decode(p.bodyBytes));
    return m?.group(1);
  } catch (_) {
    return null;
  }
}

/// آخر إصدار متاح: من GitHub Actions أولًا، ثم من app-version.json كاحتياطي. يرجع الإصدار لو كان أحدث من المثبّت.
Future<String?> _findNewer() async {
  final fromRuns = await latestFromActions();
  if (fromRuns != null) {
    return _verNum(fromRuns) > _verNum(appVersion) ? fromRuns : null;
  }
  return fetchNewerVersion();
}

/// تحديث تلقائي كامل وصامت: بدون أي نافذة تأكيد أو شريط تقدم أو إشعار خطأ.
/// يفحص الإصدار، يحمّل الملف في الخلفية، ثم يفتح المثبّت مباشرة.
/// لا يستخدم BuildContext نهائيًا — يعمل حتى لو المستخدم غيّر الشاشة.
bool _updating = false;
Future<void> autoUpdate(BuildContext context) async {
  await _runUpdate();
}

/// تحديث فوري يدوي (زر المستخدمين): يرجع رسالة بالنتيجة
Future<String> forceUpdate() => _runUpdate();

Future<String> _runUpdate() async {
  if (_updating) return 'التحديث قيد التنفيذ';
  _updating = true;
  try {
    final newer = await _findNewer();
    if (newer == null) return 'أنت على آخر إصدار ($appVersion) — تم الفحص في GitHub Actions';

    final client = http.Client();
    final res = await client.send(http.Request('GET', Uri.parse(_apkUrl))).timeout(const Duration(minutes: 5));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/security-management-update.apk');
    final sink = file.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
    }
    await sink.close();
    client.close();

    try {
      await _channel.invokeMethod('install', file.path);
      return 'تم تحميل الإصدار $newer — أكّد التثبيت';
    } catch (_) {
      return 'اسمح بالتثبيت من هذا التطبيق ثم اضغط التحديث مرة أخرى';
      // صمت تام: لو فشل فتح المثبت (مثلاً صلاحية غير ممنوحة)، نحاول مرة واحدة أخرى
      // في المرة القادمة لفتح التطبيق دون إظهار أي رسالة للمستخدم الآن.
    }
  } catch (_) {
    return 'تعذر التحديث — تأكد من الإنترنت';
  } finally {
    _updating = false;
  }
}
