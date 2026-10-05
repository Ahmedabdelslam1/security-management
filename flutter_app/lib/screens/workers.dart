// شاشة العاملين: عرض / إضافة / تعديل / حذف
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  bool _busy = false;
  String _q = '';

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await App.I.bootstrap(silent: true);
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Worker? w]) async {
    final name = TextEditingController(text: w?.name ?? '');
    final card = TextEditingController(text: w?.card ?? '');
    final phone = TextEditingController(text: w?.phone ?? '');
    final wage = TextEditingController(text: w == null ? '' : w.wage.toString());
    final hours = TextEditingController(text: w == null ? '8' : w.hours.toString());
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(w == null ? 'إضافة عامل' : 'تعديل عامل', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العامل', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: card, decoration: const InputDecoration(labelText: 'رقم البطاقة', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: wage, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'أجر اليوم (جنيه)', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'ساعات اليوم الافتراضية', isDense: true)),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    setState(() => _busy = true);
    try {
      await Api.auth('saveWorker', [
        {
          'id': w?.id,
          'name': name.text.trim(),
          'card': card.text.trim(),
          'phone': phone.text.trim(),
          'wage': double.tryParse(wage.text) ?? 0,
          'hours': double.tryParse(hours.text) ?? 8,
        }
      ]);
      await App.I.bootstrap(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(w == null ? 'تمت الإضافة' : 'تم التعديل'), backgroundColor: Colors.green.shade700));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Worker w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف العامل "${w.name}"؟ سيتم حذف سجلات حضوره وصوره أيضًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await Api.auth('deleteWorkers', [
        [w.id]
      ]);
      await App.I.bootstrap(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = App.I.user?.can('workers') ?? false;
    final all = App.I.workers;
    final ws = _q.isEmpty
        ? all
        : all.where((w) => txtMatch(_q, [w.name, w.card, w.phone])).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('إضافة عامل'),
            )
          : null,
      body: _busy && all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SearchBox(hint: 'بحث بالاسم أو رقم البطاقة أو الهاتف...', value: _q, onChanged: (v) => setState(() => _q = v)),
                Expanded(
                child: RefreshIndicator(
              onRefresh: _refresh,
              child: ws.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Center(child: Text(_q.isEmpty ? 'لا يوجد عاملون بعد — اضغط "إضافة عامل"' : 'لا نتائج للبحث')),
                      )
                    ])
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 80),
                      itemCount: ws.length,
                      itemBuilder: (_, i) {
                        final w = ws[i];
                        return SlideIn(
                          index: i,
                        child: GlowCard(
                          glow: const Color(0xFFB45309),
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 1.5,
                          child: ListTile(
                            title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${w.wage} ج/يوم • ${w.hours} ساعات'
                                '${w.card.isEmpty ? '' : ' • بطاقة ${w.card}'}'
                                '${w.phone.isEmpty ? '' : ' • ${w.phone}'}'
                                '${w.lastSet.isEmpty ? '' : ' • آخر تسوية ${fmtDate(w.lastSet)}'}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            trailing: isAdmin
                                ? PopupMenuButton<String>(
                                    onSelected: (v) => v == 'edit' ? _edit(w) : _delete(w),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                      PopupMenuItem(value: 'del', child: Text('حذف', style: TextStyle(color: Colors.red))),
                                    ],
                                  )
                                : null,
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
