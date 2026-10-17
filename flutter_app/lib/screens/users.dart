// شاشة المستخدمين (للمدير): موافقة، صلاحيات، كلمة مرور، حذف، إضافة
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../updater.dart';
import '../widgets.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  void _pdf() {
    final all = App.I.data?.users ?? [];
    final us = _q.isEmpty ? all : all.where((u) => txtMatch(_q, [u.name, u.username])).toList();
    final rows = [for (final u in us) [u.name, u.username, u.isAdmin ? 'مدير' : 'مستخدم', u.status == 'approved' ? 'معتمد' : (u.status == 'pending' ? 'بانتظار الموافقة' : 'موقوف')]];
    exportTablePdf(
      context: context,
      title: 'قائمة المستخدمين',
      subtitle: 'عدد المستخدمين: ${us.length}',
      headers: ['الاسم', 'اسم المستخدم', 'الدور', 'الحالة'],
      widths: [110, 85, 60, 75],
      rows: rows,
    );
  }
  bool _busy = false;
  String _q = '';

  Future<void> _refreshAll() async {
    setState(() => _busy = true);
    try {
      try { await Api.auth('refreshLive', []); } catch (_) {}
      await App.I.bootstrap(silent: true);
      final msg = await forceUpdate();
      if (mounted) _done(msg);
    } catch (e) {
      if (mounted) _fail('تعذر التحديث');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700));
  }

  void _fail(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
  }

  Future<void> _run(Future<Object?> Function() fn, String okMsg) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (r is List) {
        App.I.updateUsers((r).map((u) => AppUser.fromJson(u as Map)).toList());
      } else {
        await App.I.bootstrap(silent: true);
      }
      _done(okMsg);
    } on ApiException catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    final Map<String, bool> perms = {};
    bool isAdmin = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(c).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('إضافة مستخدم', textAlign: TextAlign.center, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'الاسم بالكامل')),
                const SizedBox(height: 8),
                TextField(controller: user, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'اسم المستخدم (إنجليزي)')),
                const SizedBox(height: 8),
                TextField(controller: pass, obscureText: true, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'كلمة المرور (6 أحرف+)')),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: isAdmin,
                  onChanged: (v) => setS(() => isAdmin = v),
                  title: const Text('مدير (كل الصلاحيات)', style: TextStyle(fontSize: 14)),
                ),
                if (!isAdmin)
                  Column(
                    children: [
                      ..._permDefs.map((p) => CheckboxListTile(
                            dense: true,
                            value: perms[p.$1] == true,
                            onChanged: (v) => setS(() => perms[p.$1] = v ?? false),
                            title: Text(p.$2, style: const TextStyle(fontSize: 13.5)),
                          )),
                    ],
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('إضافة'),
                ),
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => Api.auth('addUser', [
        name.text.trim(), user.text.trim().toLowerCase(), pass.text, perms, isAdmin
      ]),
      'تمت الإضافة',
    );
  }

  static const _permDefs = [('workers', 'العاملين'), ('attendance', 'الحضور'), ('reports', 'التقارير'), ('gate', 'دفتر البوابة')];

  Future<void> _perms(AppUser u) async {
    final Map<String, bool> perms = {
      'workers': u.perms['workers'] == 1 || u.perms['workers'] == true,
      'attendance': u.perms['attendance'] == 1 || u.perms['attendance'] == true,
      'reports': u.perms['reports'] == 1 || u.perms['reports'] == true,
      'gate': u.perms['gate'] == 1 || u.perms['gate'] == true,
      'procs': u.perms['procs'] == 1 || u.perms['procs'] == true,
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('صلاحيات: ${u.name}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ..._permDefs.map((p) => CheckboxListTile(
                    dense: true,
                    value: perms[p.$1],
                    onChanged: (v) => setS(() => perms[p.$1] = v ?? false),
                    title: Text(p.$2, style: const TextStyle(fontSize: 14)),
                  )),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => Api.auth('setUser', [u.username, {'perms': perms}]), 'تم حفظ الصلاحيات');
  }

  Future<void> _resetPass(AppUser u) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('كلمة مرور جديدة لـ ${u.name}'),
        content: TextField(controller: t, obscureText: true, autofocus: true, decoration: const InputDecoration(hintText: '6 أحرف على الأقل')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || t.text.trim().length < 6) {
      if (ok == true) _fail('كلمة المرور 6 أحرف على الأقل');
      return;
    }
    await _run(() => Api.auth('resetUserPassword', [u.username, t.text.trim()]), 'تم تغيير كلمة المرور');
  }

  Future<void> _delete(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف مستخدم "${u.name}" نهائيًا؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => Api.auth('deleteUser', [u.username]), 'تم الحذف');
  }

  Future<void> _status(AppUser u, String st) =>
      _run(() => Api.auth('setUser', [u.username, {'status': st}]), st == 'approved' ? 'تمت الموافقة' : st == 'suspended' ? 'تم الإيقاف' : 'تم التحديث');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = App.I.data?.users ?? [];
    final users = _q.isEmpty ? all : all.where((u) => txtMatch(_q, [u.name, u.username])).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('إضافة مستخدم'),
      ),
      body: Column(
        children: [
          SearchBox(hint: 'بحث بالمستخدم أو الاسم...', value: _q, onChanged: (v) => setState(() => _q = v)),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'سحب وتحديث الملفات والإصدار',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFDBEAFE)),
            onPressed: _busy ? null : _refreshAll,
            icon: const Icon(Icons.system_update_alt, size: 20, color: Color(0xFF1D4ED8)),
          ),
          IconButton.filledTonal(
            tooltip: 'PDF للطباعة والإرسال',
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
            onPressed: _pdf,
            icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
          ),
          Expanded(
          child: RefreshIndicator(
        onRefresh: () => App.I.bootstrap(silent: true),
        child: users.isEmpty
            ? ListView(children: [Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(_q.isEmpty ? 'لا مستخدمين' : 'لا نتائج للبحث')))])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final u = users[i];
                  final statusColor = u.status == 'approved'
                      ? Colors.green
                      : u.status == 'pending' ? Colors.orange : Colors.red;
                  final statusLabel = u.status == 'approved'
                      ? 'نشط'
                      : u.status == 'pending' ? 'بانتظار الموافقة' : 'موقوف';
                  final permLabels = _permDefs.where((p) => u.can(p.$1)).map((p) => p.$2).join(' • ');
                  return SlideIn(
                    index: i,
                    child: GlowCard(
                    glow: const Color(0xFF0F766E),
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                    Text('@${u.username}${u.isAdmin ? ' — مدير' : ''}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(20)),
                                child: Text(statusLabel, style: TextStyle(color: statusColor.shade800, fontSize: 11.5, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          if (!u.isAdmin && permLabels.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(permLabels, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ),
                          if (!u.isAdmin) ...[
                            const Divider(height: 14),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (u.status != 'approved')
                                  ActionChip(
                                    avatar: const Icon(Icons.check, size: 16, color: Colors.green),
                                    label: const Text('موافقة'),
                                    onPressed: () => _status(u, 'approved'),
                                  ),
                                if (u.status == 'approved')
                                  ActionChip(
                                    avatar: const Icon(Icons.block, size: 16, color: Colors.red),
                                    label: const Text('إيقاف'),
                                    onPressed: () => _status(u, 'suspended'),
                                  ),
                                ActionChip(
                                  avatar: const Icon(Icons.key, size: 16),
                                  label: const Text('كلمة المرور'),
                                  onPressed: () => _resetPass(u),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.tune, size: 16),
                                  label: const Text('الصلاحيات'),
                                  onPressed: () => _perms(u),
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                  label: Text('حذف', style: TextStyle(color: Colors.red.shade700)),
                                  onPressed: () => _delete(u),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  );
                },
              ),
          ),
        ),
      ],
    ),
    );
  }
}
