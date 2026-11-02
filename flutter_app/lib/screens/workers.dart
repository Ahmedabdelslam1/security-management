// شاشة العاملين: عرض / إضافة / تعديل / حذف
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});
  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  void _pdf() {
    final ws = _q.isEmpty ? App.I.workers : App.I.workers.where((x) => txtMatch(_q, [x.name, x.card, x.phone])).toList();
    final rows = [for (final w in ws) [w.name, w.card.isEmpty ? '—' : w.card, w.phone.isEmpty ? '—' : w.phone, w.wage.toStringAsFixed(w.wage == w.wage.truncateToDouble() ? 0 : 2), w.hours.toStringAsFixed(w.hours == w.hours.truncateToDouble() ? 0 : 1), w.lastSet.isEmpty ? '—' : fmtDate(w.lastSet)]];
    exportTablePdf(
      context: context,
      title: 'قائمة العاملين',
      subtitle: 'عدد العاملين: ${ws.length}',
      headers: ['الاسم', 'رقم البطاقة', 'التليفون', 'أجر اليوم', 'ساعات العمل', 'آخر تسوية'],
      widths: [95, 70, 65, 50, 45, 60],
      rows: rows,
    );
  }

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
    final wloc = TextEditingController(text: w?.loc ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
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
              Builder(builder: (_) {
                String nk(String x) => x.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
                final q = nk(name.text);
                if (q.isEmpty) return const SizedBox.shrink();
                final ms = App.I.workers.where((o) => o.id != w?.id && nk(o.name).contains(q)).toList();
                final ex = ms.any((o) => nk(o.name) == q);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (ex)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), border: Border.all(color: const Color(0xFFDC2626), width: 2), borderRadius: BorderRadius.circular(8)),
                      child: const Text('⛔ هذا الاسم موجود مسبقًا', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  if (ms.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 110, maxWidth: 240),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                        child: SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            const Text('أسماء مضافة مسبقًا', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                            for (final o in ms.take(30)) Text(o.name, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                ]);
              }),
              TextField(controller: name, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'اسم العامل', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: card, decoration: const InputDecoration(labelText: 'رقم البطاقة', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: wage, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'أجر اليوم (جنيه)', isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: wloc, decoration: const InputDecoration(labelText: 'مكان الحضور الثابت (اختياري)', isDense: true)),
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
      )),
    );
    if (saved != true) return;
    String nk(String x) => x.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final cv = card.text.replaceAll(RegExp(r'\s+'), '');
    for (final o in App.I.workers) {
      if (o.id == w?.id) continue;
      String? msg;
      if (nk(o.name) == nk(name.text)) {
        msg = 'تم إضافة الاسم من قبل';
      } else if (cv.isNotEmpty && o.card.replaceAll(RegExp(r'\s+'), '') == cv) {
        msg = 'تم إضافة رقم البطاقة من قبل';
      }
      if (msg != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
        return;
      }
    }
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
          'loc': wloc.text.trim(),
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
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'PDF للطباعة والإرسال',
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                  onPressed: _pdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
                ),
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
                          glow: workerColor(w.id),
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 1.5,
                          child: ListTile(
                            dense: true,
                            leading: workerAvatar(w.id, size: 30),
                            title: Text(w.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: workerColor(w.id))),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${w.wage} ج/يوم • ${w.hours} ساعات'
                                '${w.card.isEmpty ? '' : ' • بطاقة ${w.card}'}'
                                '${w.phone.isEmpty ? '' : ' • ${w.phone}'}'
                                '${w.lastSet.isEmpty ? '' : ' • آخر تسوية ${fmtDate(w.lastSet)}'}\nالمستحق: ${workerDueText(w, App.I.att)}',
                                style: const TextStyle(fontSize: 11),
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
