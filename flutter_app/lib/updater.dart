// التحديث التلقائي: يفحص app-version.json في المستودع، ولو فيه إصدار أحدث
// يحمّل الـ APK تلقائيًا ثم يفتح مثبّت أندرويد
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String appVersion = '1.1.0';
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

/// فحص وتحديث تلقائي: إشعار ثم تحميل بشريط تقدم ثم فتح المثبّت
Future<void> autoUpdate(BuildContext context) async {
  final newer = await fetchNewerVersion();
  if (newer == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('تحديث جديد متاح', textAlign: TextAlign.center),
      content: Text('إصدار $newer متاح. سيتم تحميل ملفات التحديث الآن.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('لاحقًا')),
        FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('تحديث الآن')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0.0);
  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (c, v, _) => AlertDialog(
          title: const Text('جاري التحميل...', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v <= 0 ? 0.02 : v),
              const SizedBox(height: 10),
              const Text('يتم سحب ملفات التحديث — لا تغلق التطبيق',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final client = http.Client();
    final res = await client.send(http.Request('GET', Uri.parse(_apkUrl))).timeout(const Duration(minutes: 5));
    final total = res.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/security-management-update.apk');
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress.value = got / total;
    }
    await sink.close();
    client.close();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // إغلاق شريط التقدم
    try {
      await _channel.invokeMethod('install', file.path);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم التحميل — اسمح بالتثبيت من المصادر غير المعروفة من الإعدادات'),
            backgroundColor: Color(0xFFB91C1C)));
      }
    }
  } catch (_) {
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر التحميل — جرّب لاحقًا'), backgroundColor: Color(0xFFB91C1C)));
    }
  }
}
