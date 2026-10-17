// الاتصال بسيرفر Google Apps Script: POST {action,args} ثم متابعة التحويل يدويًا
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'store.dart';

const String appVersion = '2.0.0';
const String defaultUrl =
    'https://script.google.com/macros/s/AKfycbz5ISJT-vROTmczOi8HdFBvwSXiUZ3mMGzHJBfv732cumsONfMsu-yK_5-NuOzByHQu/exec';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class SessionExpired extends ApiException {
  SessionExpired() : super('انتهت الجلسة، سجّل الدخول من جديد');
}

class Api {
  static final http.Client _c = http.Client();
  static String? _url;
  static String? _token;

  static Future<String> url() async {
    if (_url != null) return _url!;
    final u = (await Store.get('url')) ?? '';
    _url = u.trim().isEmpty ? defaultUrl : u.trim();
    return _url!;
  }

  static Future<void> setUrl(String u) async {
    u = u.trim();
    if (u.isEmpty) u = defaultUrl;
    if (!u.startsWith('http')) throw ApiException('الرابط لازم يبدأ بـ https://');
    _url = u;
    await Store.set('url', u);
  }

  static Future<String> token() async {
    _token ??= (await Store.get('token')) ?? '';
    return _token!;
  }

  static Future<void> setToken(String t) async {
    _token = t;
    await Store.set('token', t);
  }

  static Future<void> clearToken() async {
    _token = '';
    await Store.remove('token');
  }

  /// نداء بدون جلسة (مثل login)
  static Future<dynamic> call(String action, [List args = const []]) async {
    final u = await url();
    final body = jsonEncode({'action': action, 'args': args});
    http.Response res;
    try {
      final req = http.Request('POST', Uri.parse(u))
        ..headers['Content-Type'] = 'text/plain; charset=utf-8'
        ..body = body
        ..followRedirects = false;
      res = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 30)));
      var hops = 0;
      while ([301, 302, 303, 307].contains(res.statusCode) && hops < 5) {
        final loc = res.headers['location'];
        if (loc == null || loc.isEmpty) break;
        res = await _c.get(Uri.parse(loc)).timeout(const Duration(seconds: 30));
        hops++;
      }
    } catch (e) {
      throw ApiException('تعذر الوصول للسيرفر — تأكد من الإنترنت والرابط\n($e)');
    }
    Map out;
    try {
      out = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    } catch (_) {
      throw ApiException('رد غير صالح من السيرفر (${res.statusCode}) — تأكد من رابط النشر (يجب أن ينتهي بـ /exec ويكون الوصول: أي شخص)');
    }
    if (out['ok'] != true) {
      final msg = (out['error'] ?? 'خطأ غير معروف').toString();
      if (msg.contains('SESSION')) throw SessionExpired();
      throw ApiException(msg);
    }
    return out['data'];
  }

  /// نداء بجلسة: الـ token أول وسيطة
  static Future<dynamic> auth(String action, [List args = const []]) async =>
      call(action, [await token(), ...args]);
}
