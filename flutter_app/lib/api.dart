// بوابة الاتصال بالسيرفر — متوافقة مع Google Apps Script (doPost) و PHP (api.php)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class SessionExpired implements Exception {
  @override
  String toString() => 'انتهت الجلسة، سجّل الدخول من جديد';
}

class Api {
  static final http.Client _shared = http.Client(); // اتصال دائم لتسريع كل الطلبات
  static String? _url;
  static String myIp = ''; // IP الجهاز العام (يظهر للمدير في شاشة المتابعة)
  static Future<void> fetchIp() async {
    if (myIp.isNotEmpty) return;
    try {
      final r = await _shared.get(Uri.parse('https://api.ipify.org')).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) myIp = r.body.trim();
    } catch (_) {}
  }
  static String? _token;
  static const _kUrl = 'gas_url_v2';
  static const _kTok = 'gas_token';

  // رابط السيرفر الافتراضي (Google Apps Script)
  static const String defaultUrl =
      'https://script.google.com/macros/s/AKfycbyuuuvOsx9ttlnAzPSUCeAksqDmRl4qkHn32Cnpoe33YhLG4x3A7KCk0er9DjGW5OqW/exec';

  static Future<String?> getUrl() async {
    if (_url != null) return _url;
    _url = await Store.getString(_kUrl);
    if (_url == null || _url!.trim().isEmpty) {
      _url = defaultUrl;
      await Store.setString(_kUrl, defaultUrl);
    }
    return _url;
  }

  /// ينظّف الرابط الملصوق من المتصفح: يقطع أي معاملات بعد /exec أو /dev
  static String normalizeUrl(String u) {
    u = u.trim();
    final m = RegExp(r'^(https?://[^\s?#]*?/(?:exec|dev))(?:[/?#].*)?$').firstMatch(u);
    return m != null ? m.group(1)! : u.split(RegExp(r'[?#]')).first;
  }

  static Future<void> saveUrl(String u) async {
    u = normalizeUrl(u);
    if (u.isEmpty) {
      _url = defaultUrl;
      await Store.setString(_kUrl, defaultUrl);
      return;
    }
    if (!u.startsWith('http')) throw ApiException('الرابط لازم يبدأ بـ https://');
    _url = u;
    await Store.setString(_kUrl, u);
  }

  static Future<String?> getToken() async {
    if (_token != null) return _token;
    _token = await Store.getString(_kTok);
    return _token;
  }

  static Future<void> saveToken(String t) async {
    _token = t;
    await Store.setString(_kTok, t);
  }

  static Future<void> clear() async {
    _token = null;
    await Store.remove(_kTok);
  }

  /// هل الرابط يشير لسيرفر PHP؟
  static bool _isPhpBackend(String u) {
    final lower = u.toLowerCase();
    return lower.contains('api.php') ||
        lower.endsWith('/php') ||
        lower.contains('/php/') ||
        (!lower.contains('script.google.com') && !lower.contains('googleusercontent.com'));
  }

  /// هل السيرفر الحالي PHP؟ (لا يدعم الحفظ الجزئي لليوم)
  static Future<bool> isPhp() async {
    final u = (await getUrl()) ?? defaultUrl;
    return _isPhpBackend(u);
  }

  // نداء عام: action = اسم الدالة، args = وسائطها (token أولًا حيث يلزم)
  static Future<dynamic> call(String action, [List args = const []]) async {
    var u = _url ?? await getUrl();
    if (u == null || u.trim().isEmpty) u = defaultUrl;
    u = u.trim();

    // لو كان رابط مجلد PHP بدون api.php أضفه تلقائيًا
    if (!u.contains('script.google.com') &&
        !u.endsWith('/exec') &&
        !u.endsWith('api.php') &&
        !u.contains('api.php?')) {
      if (u.endsWith('/')) {
        u = '${u}api.php';
      } else if (!u.contains('.php')) {
        u = '$u/api.php';
      }
    }

    final body = jsonEncode({'action': action, 'args': args});
    http.Response res;
    final client = _shared;
    try {
      if (_isPhpBackend(u) || !u.contains('script.google.com')) {
        // سيرفر PHP أو أي API مباشر — POST JSON عادي
        res = await client
            .post(
              Uri.parse(u),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: body,
            )
            .timeout(const Duration(seconds: 30));
      } else {
        // Google Apps Script: POST ثم اتبع تحويل 302 يدويًا
        final req = http.Request('POST', Uri.parse(u))
          ..headers['Content-Type'] = 'text/plain; charset=utf-8'
          ..body = body
          ..followRedirects = false;
        res = await http.Response.fromStream(
            await client.send(req).timeout(const Duration(seconds: 30)));
        var hops = 0;
        while ((res.statusCode == 301 ||
                res.statusCode == 302 ||
                res.statusCode == 303) &&
            hops < 5) {
          final loc = res.headers['location'];
          if (loc == null || loc.isEmpty) break;
          res = await client.get(Uri.parse(loc)).timeout(const Duration(seconds: 30));
          hops++;
        }
      }
    } catch (e) {
      throw ApiException('تعذر الوصول للسيرفر — تأكد من الرابط والإنترنت');
    }

    Map out;
    try {
      out = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    } catch (_) {
      throw ApiException(
          'رد غير صالح من السيرفر (${res.statusCode}) — تأكد من الرابط والنشر');
    }
    if (out['ok'] != true) {
      final msg = (out['error'] ?? 'خطأ غير معروف').toString();
      if (msg.contains('SESSION')) throw SessionExpired();
      throw ApiException(msg);
    }
    return out['data'];
  }


  // ===== اختيار السيرفر تلقائيًا =====
  static const String registryUrl =
      'https://raw.githubusercontent.com/Ahmedabdelslam1/security-management/main/server-url.json';
  static Future<bool>? _selFut;

  /// يفحص رابطًا: 4 = سكربت محدّث، 1 = قديم، 0 = لا يرد
  static Future<int> probe(String u) async {
    try {
      final req = http.Request('POST', Uri.parse(u))
        ..headers['Content-Type'] = 'text/plain; charset=utf-8'
        ..body = jsonEncode({'action': 'srvVer', 'args': [_token ?? '']})
        ..followRedirects = false;
      var res = await http.Response.fromStream(await _shared.send(req).timeout(const Duration(seconds: 9)));
      var hops = 0;
      while ([301, 302, 303, 307].contains(res.statusCode) && hops < 5) {
        final loc = res.headers['location'];
        if (loc == null || loc.isEmpty) break;
        res = await _shared.get(Uri.parse(loc)).timeout(const Duration(seconds: 9));
        hops++;
      }
      final out = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (out['ok'] == true) return (int.tryParse('${out['data']}') ?? 1) >= 4 ? 4 : 1;
      final msg = '${out['error']}';
      if (msg.contains('SESSION')) return 4; // الدالة موجودة (فشل التوثيق فقط)
      return 1; // إجراء غير معروف = سكربت قديم
    } catch (_) {
      return 0;
    }
  }

  /// يختار تلقائيًا أحدث سيرفر منشور: المحفوظ ثم المسجّل في GitHub (server-url.json) ثم الافتراضي،
  /// ويعتمد أول رابط يرد بسكربت محدّث. يرجع true إذا تغيّر الرابط.
  static Future<bool> autoSelect({bool force = false}) {
    if (force || _selFut == null) _selFut = _autoSelect();
    return _selFut!;
  }

  static Future<bool> _autoSelect() async {
    final stored = (await getUrl()) ?? defaultUrl;
    // الأولوية: أحدث رابط منشور (السجل على GitHub) ← الافتراضي ← المحفوظ؛ أول رابط يردّ بسكربت محدّث يُعتمد
    final cands = <String>[];
    try {
      final r = await _shared
          .get(Uri.parse('$registryUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final u = normalizeUrl('${(jsonDecode(utf8.decode(r.bodyBytes)) as Map)['url'] ?? ''}');
        if (u.startsWith('http')) cands.add(u);
      }
    } catch (_) {}
    for (final u in [defaultUrl, stored]) {
      if (!cands.contains(u)) cands.add(u);
    }
    final res = await Future.wait(cands.map(probe));
    for (var i = 0; i < cands.length; i++) {
      if (res[i] == 4) {
        if (cands[i] == stored) return false;
        await saveUrl(cands[i]);
        return true;
      }
    }
    return false; // لا أحد محدّث: نبقى على المحفوظ
  }

  // نداء موثّق: يضيف token تلقائيًا كأول وسيطة
  static Future<dynamic> auth(String action, [List args = const []]) async {
    final t = await getToken();
    return call(action, [if (t != null) t else '', ...args]);
  }
}
