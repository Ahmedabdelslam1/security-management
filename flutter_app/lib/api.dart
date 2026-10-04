// بوابة الاتصال بسيرفر Apps Script — نفس دوال النسخة الويب بالضبط
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static String? _url;
  static String? _token;
  static const _kUrl = 'gas_url';
  static const _kTok = 'gas_token';

  static Future<String?> getUrl() async {
    if (_url != null) return _url;
    final p = await SharedPreferences.getInstance();
    _url = p.getString(_kUrl);
    return _url;
  }

  static Future<void> saveUrl(String u) async {
    u = u.trim();
    if (u.isEmpty) throw ApiException('اكتب رابط التطبيق');
    if (!u.startsWith('http')) throw ApiException('الرابط لازم يبدأ بـ https://');
    _url = u;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, u);
  }

  static Future<String?> getToken() async {
    if (_token != null) return _token;
    final p = await SharedPreferences.getInstance();
    _token = p.getString(_kTok);
    return _token;
  }

  static Future<void> saveToken(String t) async {
    _token = t;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTok, t);
  }

  static Future<void> clear() async {
    _token = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTok);
  }

  // نداء عام: action = اسم الدالة في Code.gs، args = وسائطها بالترتيب (token أولًا حيث يلزم)
  static Future<dynamic> call(String action, [List args = const []]) async {
    final u = _url ?? await getUrl();
    if (u == null || u.trim().isEmpty) throw ApiException('اضبط رابط السيرفر من شاشة الدخول أولًا');
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(u!),
            headers: {'Content-Type': 'text/plain; charset=utf-8'},
            body: jsonEncode({'action': action, 'args': args}),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ApiException('تعذر الوصول للسيرفر — تأكد من الرابط والإنترنت');
    }
    Map out;
    try {
      out = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    } catch (_) {
      throw ApiException('رد غير صالح من السيرفر — تأكد أن الرابط ينتهي بـ /exec');
    }
    if (out['ok'] != true) {
      final msg = (out['error'] ?? 'خطأ غير معروف').toString();
      if (msg.contains('SESSION')) throw SessionExpired();
      throw ApiException(msg);
    }
    return out['data'];
  }

  // نداء موثّق: يضيف token تلقائيًا كأول وسيطة
  static Future<dynamic> auth(String action, [List args = const []]) async {
    final t = await getToken();
    return call(action, [if (t != null) t else '', ...args]);
  }
}
