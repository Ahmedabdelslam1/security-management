// الإعدادات: تغيير كلمة المرور
import 'package:flutter/material.dart';
import '../api.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  String _msg = '';
  bool _err = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _changePass() async {
    if (_new.text.length < 6) {
      setState(() { _msg = 'كلمة المرور الجديدة 6 أحرف على الأقل'; _err = true; });
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.auth('changePassword', [_old.text, _new.text]);
      setState(() { _msg = 'تم تغيير كلمة المرور'; _err = false; });
      _old.clear(); _new.clear();
    } on ApiException catch (e) {
      setState(() { _msg = e.message; _err = true; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('تغيير كلمة المرور', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                TextField(controller: _old, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الحالية', isDense: true, border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', isDense: true, border: OutlineInputBorder())),
                const SizedBox(height: 10),
                _busy
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(onPressed: _changePass, icon: const Icon(Icons.key, size: 18), label: const Text('تغيير')),
              ],
            ),
          ),
        ),
        if (_msg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_msg, textAlign: TextAlign.center,
                style: TextStyle(color: _err ? cs.error : Colors.green.shade700, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
