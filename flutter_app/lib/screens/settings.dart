// الإعدادات: تغيير كلمة المرور
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../url_dialog.dart';

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
  bool _diagBusy = false;
  String _diag = '';

  /// فحص الربط مع الويب/شيت جوجل: الرابط، إصدار السكربت، عدد السجلات على السيرفر، واختبار كتابة فعلي
  Future<void> _runDiag() async {
    setState(() { _diagBusy = true; _diag = ''; });
    final b = StringBuffer();
    try {
      b.writeln('رابط السيرفر:\n${await Api.getUrl()}');
      try {
        final v = await Api.auth('srvVer');
        b.writeln('إصدار سكربت Google: $v ${(int.tryParse('$v') ?? 0) >= 4 ? '(محدّث ✓)' : '(قديم — لن يقبل نصف يوم/ساعات؛ حدّث السكربت)'}');
      } catch (e) {
        b.writeln('إصدار سكربت Google: غير معروف ($e)');
      }
      final j = await Api.auth('bootstrap') as Map;
      final att = (j['att'] as List?) ?? [];
      final ws = (j['workers'] as List?) ?? [];
      final dates = att.map((r) => '${(r as Map)['date']}').toList()..sort();
      b.writeln('المستخدم: ${(j['user'] as Map?)?['username']}');
      b.writeln('العمال على السيرفر: ${ws.length}');
      b.writeln('سجلات الحضور على السيرفر: ${att.length}${dates.isEmpty ? '' : ' (آخر تاريخ: ${dates.last})'}');
      if (ws.isNotEmpty) {
        final wid = '${(ws.first as Map)['id']}';
        const d = '2099-12-31';
        try {
          await Api.auth('saveDay', [d, [{'wid': wid, 'status': 'حضور', 'loc': 'اختبار', 'xh': 1, 'wage': 0, 'notes': 'اختبار ربط'}], true]);
          b.writeln('اختبار الكتابة في السيرفر: نجح ✓');
        } catch (e) {
          b.writeln('اختبار الكتابة: فشل ✗ — $e');
        }
        try {
          await Api.auth('saveDay', [d, [{'wid': wid, 'status': '--', 'loc': '', 'xh': 0, 'wage': 0, 'notes': ''}], true]);
        } catch (_) {}
      }
    } catch (e) {
      b.writeln('فشل الاتصال: $e');
    }
    if (mounted) setState(() { _diag = b.toString(); _diagBusy = false; });
  }

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
        Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(top: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('رابط السيرفر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('يجب أن يكون نفس رابط الويب الذي تفتحه في المتصفح. لو تغيّر النشر في Apps Script غيّره هنا.', style: TextStyle(fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ch = await showServerUrlDialog(context);
                    if (ch) {
                      await App.I.logout();
                      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                    }
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('تغيير رابط السيرفر'),
                ),
              ],
            ),
          ),
        ),
        Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(top: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('فحص الربط مع الويب وشيت جوجل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                _diagBusy
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(onPressed: _runDiag, icon: const Icon(Icons.network_check, size: 18), label: const Text('فحص الآن')),
                if (_diag.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: SelectableText(_diag, style: const TextStyle(fontSize: 12.5, height: 1.5))),
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
