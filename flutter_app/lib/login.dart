import 'package:flutter/material.dart';
import 'api.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  bool _showUrl = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    Api.url().then((u) { if (mounted) _url.text = u; });
  }

  Future<void> _login() async {
    setState(() { _busy = true; _msg = ''; });
    try {
      await Api.setUrl(_url.text);
      final r = await Api.call('login', [_u.text.trim().toLowerCase(), _p.text, 'android']);
      await Api.setToken('${(r as Map)['token']}');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiException catch (e) {
      setState(() => _msg = e.message);
    } catch (e) {
      setState(() => _msg = 'خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.shield_outlined, size: 56, color: Color(0xFF7C5CFC)),
                const SizedBox(height: 8),
                const Text('إدارة الأمن', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                TextField(
                  controller: _u,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _p,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('دخول', style: TextStyle(fontSize: 16)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _showUrl = !_showUrl),
                  child: const Text('رابط السيرفر'),
                ),
                if (_showUrl)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _url,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                if (_msg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(_msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 16),
                Text('v$appVersion', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
