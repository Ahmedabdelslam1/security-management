// شاشة الدخول + رابط السيرفر + تسجيل مستخدم جديد
import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _url = TextEditingController();
  final _rgName = TextEditingController();
  final _rgUser = TextEditingController();
  final _rgPass = TextEditingController();
  String _msg = '';
  bool _err = false;
  bool _busy = false;
  bool _reg = false;

  @override
  void initState() {
    super.initState();
    Api.getUrl().then((u) {
      if (u != null && u.isNotEmpty && mounted) setState(() => _url.text = u);
    });
  }

  void _say(String m, [bool e = false]) => setState(() { _msg = m; _err = e; });

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await Api.saveUrl(_url.text);
      final r = await Api.call('login', [_u.text.trim().toLowerCase(), _p.text]);
      await Api.saveToken((r as Map)['token'] as String);
      await App.I.bootstrap();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    } on SessionExpired {
      _say('انتهت الجلسة، حاول مرة أخرى', true);
    } on ApiException catch (e) {
      _say(e.message, true);
    } catch (e) {
      _say('خطأ غير متوقع: $e', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await Api.saveUrl(_url.text);
      await Api.call('register', [_rgName.text.trim(), _rgUser.text.trim().toLowerCase(), _rgPass.text]);
      _say('تم إرسال الطلب — بانتظار موافقة الإدارة');
      setState(() => _reg = false);
    } on ApiException catch (e) {
      _say(e.message, true);
    } catch (e) {
      _say('خطأ غير متوقع: $e', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Icon(Icons.shield_outlined, size: 64, color: cs.primary),
                const SizedBox(height: 6),
                Text('إدارة الأمن', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 18),
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'رابط التطبيق (ينتهي بـ /exec)',
                            hintText: 'https://script.google.com/macros/s/.../exec',
                            prefixIcon: Icon(Icons.link),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (!_reg) ...[
                          TextField(
                            controller: _u,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline), isDense: true),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _p,
                            obscureText: true,
                            onSubmitted: (_) => _login(),
                            decoration: const InputDecoration(labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline), isDense: true),
                          ),
                        ] else ...[
                          TextField(controller: _rgName, decoration: const InputDecoration(labelText: 'الاسم بالكامل', isDense: true)),
                          const SizedBox(height: 10),
                          TextField(controller: _rgUser, decoration: const InputDecoration(labelText: 'اسم المستخدم', isDense: true)),
                          const SizedBox(height: 10),
                          TextField(controller: _rgPass, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', isDense: true)),
                        ],
                        const SizedBox(height: 14),
                        if (_busy) const Center(child: CircularProgressIndicator())
                        else ...[
                          FilledButton(
                            onPressed: _reg ? _register : _login,
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                            child: Text(_reg ? 'إرسال طلب التسجيل' : 'دخول'),
                          ),
                          TextButton(
                            onPressed: () => setState(() { _reg = !_reg; _msg = ''; }),
                            child: Text(_reg ? 'لديك حساب؟ سجّل الدخول' : 'مستخدم جديد'),
                          ),
                        ],
                        if (_msg.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_msg, textAlign: TextAlign.center, style: TextStyle(color: _err ? cs.error : Colors.green.shade700, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
