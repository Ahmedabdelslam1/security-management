// شاشة تسجيل حضور اليوم (أو تاريخ سابق) — نفس منطق نسخة الويب
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../state.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _date = DateTime.now();
  late Map<String, _RowCtl> _ctl; // wid -> عناصر التحكم
  bool _saving = false;
  String? _err;

  String get _dstr =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _ctl = {};
    _build();
  }

  void _build() {
    final app = App.I;
    final byWid = <String, AttRec>{};
    for (final r in app.att.where((r) => r.date == _dstr)) {
      byWid[r.wid] = r;
    }
    _ctl = {
      for (final w in app.workers)
        w.id: _RowCtl(
          status: byWid[w.id]?.status ?? '--',
          loc: byWid[w.id]?.loc ?? '',
          xh: byWid[w.id]?.xh.toString() ?? '',
          notes: byWid[w.id]?.notes ?? '',
        ),
    };
    setState(() {});
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d != null) {
      _date = d;
      _build();
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _err = null; });
    try {
      final recs = <Map<String, dynamic>>[];
      _ctl.forEach((wid, c) {
        if (c.status == '--') return;
        recs.add({
          'wid': wid,
          'status': c.status,
          'loc': c.loc.trim(),
          'xh': kExtraStatuses.contains(c.status) ? (double.tryParse(c.xh) ?? 0) : 0,
          'notes': c.notes.trim(),
        });
      });
      final res = await Api.auth('saveDay', [_dstr, recs]) as Map;
      final fresh = (res['att'] as List).map((r) => AttRec.fromJson(r as Map)).toList();
      // حدّث الحالة محليًا
      final app = App.I;
      final kept = app.att.where((r) => r.date != _dstr).toList()..addAll(fresh);
      final newLocs = (res['locs'] as List).map((l) => l.toString()).where((l) => !app.locs.contains(l)).toList();
      app.att..clear()..addAll(kept);
      app.locs.addAll(newLocs);
      app.notifyListeners();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ يوم ${fmtDate(_dstr)} (${"${recs.length} عامل"})'), backgroundColor: Colors.green.shade700),
        );
      }
    } on SessionExpired {
      await _relogin();
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _relogin() async {
    await App.I.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = App.I;
    final cs = Theme.of(context).colorScheme;
    final workers = app.workers;
    final locs = app.locs;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      body: Column(
        children: [
          // شريط التاريخ + الحفظ
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(fmtDate(_dstr), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 18),
                    label: const Text('حفظ اليوم'),
                  ),
                ],
              ),
            ),
          ),
          if (_err != null)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_err!, style: TextStyle(color: cs.onErrorContainer, fontSize: 12.5)),
            ),
          // قائمة العمال
          Expanded(
            child: workers.isEmpty
                ? const Center(child: Text('لا يوجد عاملون — أضف عاملًا من شاشة العاملين', style: TextStyle(color: Color(0xFF64748B))))
                : RefreshIndicator(
                    onRefresh: () async { await app.bootstrap(silent: true); _build(); },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                      itemCount: workers.length,
                      itemBuilder: (_, i) => _workerCard(context, workers[i], locs),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _workerCard(BuildContext context, Worker w, List<String> locs) {
    final c = _ctl[w.id]!;
    final cs = Theme.of(context).colorScheme;
    final isExtra = kExtraStatuses.contains(c.status);
    final active = c.status != '--';
    final isSettled = App.I.att.any((r) => r.date == _dstr && r.wid == w.id && r.settleId.isNotEmpty);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? cs.primary.withOpacity(.35) : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
                if (isSettled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
                    child: Text('مسوّى', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                  ),
                Text('${w.wage} ج', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            // الموقف
            DropdownButtonFormField<String>(
              value: kStatuses.contains(c.status) ? c.status : '--',
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              items: kStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s == '--' ? 'بدون تسجيل' : s, style: const TextStyle(fontSize: 13.5)))).toList(),
              onChanged: (v) => setState(() { c.status = v ?? '--'; if (!kExtraStatuses.contains(c.status)) c.xh = ''; }),
            ),
            if (active) ...[
              const SizedBox(height: 8),
              // مكان الحضور: اختيار من الأماكن أو إضافة جديد
              DropdownButtonFormField<String>(
                value: locs.contains(c.loc) ? c.loc : null,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: 'مكان الحضور',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    onPressed: () => _newLoc(c),
                    tooltip: 'مكان جديد',
                  ),
                ),
                items: locs.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 13.5)))).toList(),
                onChanged: (v) => setState(() => c.loc = v ?? ''),
              ),
              if (c.loc.isNotEmpty && !locs.contains(c.loc))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('مكان جديد: ${c.loc}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                  ),
                ),
              if (isExtra) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: c.xh)..selection = TextSelection.collapsed(offset: c.xh.length),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    labelText: 'ساعات إضافية',
                  ),
                  style: const TextStyle(fontSize: 13.5),
                  onChanged: (v) => c.xh = v,
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: c.notes)..selection = TextSelection.collapsed(offset: c.notes.length),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  labelText: 'ملاحظات',
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => c.notes = v,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _newLoc(_RowCtl c) async {
    final t = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مكان حضور جديد', style: TextStyle(fontSize: 16)),
        content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(hintText: 'اسم المكان')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, t.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() => c.loc = v);
      if (!App.I.locs.contains(v)) App.I.locs.add(v);
    }
  }
}

class _RowCtl {
  String status;
  String loc;
  String xh;
  String notes;
  _RowCtl({required this.status, required this.loc, required this.xh, required this.notes});
}
