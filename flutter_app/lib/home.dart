// الخطوة 1: الرئيسية = إثبات أن الاتصال والبيانات تعمل (عدد العمال/السجلات + إصدار السكربت)
import 'package:flutter/material.dart';
import 'api.dart';
import 'login.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = true;
  String _err = '';
  Map? _data;
  String _srv = '';
  String _url = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _err = ''; });
    try {
      _url = await Api.url();
      final j = await Api.auth('bootstrap') as Map;
      String v;
      try { v = '${await Api.auth('srvVer')}'; } catch (_) { v = 'قديم (غير معروف)'; }
      if (!mounted) return;
      setState(() { _data = j; _srv = v; });
    } on SessionExpired {
      await _logout();
      return;
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = 'خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    try { await Api.auth('logout').timeout(const Duration(seconds: 4)); } catch (_) {}
    await Api.clearToken();
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final user = d?['user'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الأمن'),
        actions: [
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _busy
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('v$appVersion', style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]))
          : _err.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 44),
                      const SizedBox(height: 10),
                      SelectableText(_err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      TextButton(onPressed: _logout, child: const Text('تسجيل الخروج / تغيير السيرفر')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        const Text('الاتصال بالسيرفر يعمل ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 17)),
                        const Divider(),
                        _row('المستخدم', '${user?['name'] ?? user?['username'] ?? ''}'),
                        _row('الصلاحية', '${user?['role'] ?? ''}'),
                        _row('عدد العاملين', '${(d?['workers'] as List?)?.length ?? 0}'),
                        _row('سجلات الحضور', '${(d?['att'] as List?)?.length ?? 0}'),
                        _row('إصدار سكربت Google', _srv),
                        _row('إصدار التطبيق', appVersion),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Directionality(textDirection: TextDirection.ltr, child: SelectableText(_url, style: const TextStyle(fontSize: 11, color: Colors.black45))),
                  const SizedBox(height: 16),
                  const Text('الخطوة 1 من إعادة البناء: الدخول والاتصال. الخطوة التالية: شاشة الحضور.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                ]),
    );
  }
}
