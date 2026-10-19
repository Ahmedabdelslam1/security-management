// تقريرا الحضور والحسابات (مثل الويب)
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

String _nl(String s) => s.replaceAll(RegExp(r'[\u200b-\u200f\u202a-\u202e\ufeff]'), '').replaceAll(RegExp(r'\s+'), ' ').trim(); // إلغاء المسافات الزائدة في اسم المكان
String _ds(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _locOptions() {
  final s = <String>{};
  for (final l in App.I.allLocs) {
    final n = _nl(l);
    if (n.isNotEmpty) s.add(n);
  }
  return s.toList()..sort();
}

Widget _dateBox(String label, DateTime d, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), labelStyle: const TextStyle(fontSize: 11), labelText: label),
        child: Text(fmtDate(_ds(d)), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );

Widget _locDrop(String value, ValueChanged<String> onChanged) {
  final opts = _locOptions();
  return DropdownButtonFormField<String>(
    value: opts.contains(value) ? value : '',
    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 3), labelStyle: TextStyle(fontSize: 11), labelText: 'مكان الحضور'),
    items: [const DropdownMenuItem(value: '', child: Text('كل الأماكن')), ...opts.map((l) => DropdownMenuItem(value: l, child: Text(l)))],
    onChanged: (v) => onChanged(v ?? ''),
  );
}

Widget _bar(String mid, VoidCallback? onPdf) => Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(children: [
        const Icon(Icons.summarize_outlined, size: 17, color: Color(0xFF7C5CFC)),
        const SizedBox(width: 6),
        Flexible(child: Text(mid, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
        const Spacer(),
        if (onPdf != null) IconButton(visualDensity: VisualDensity.compact, onPressed: onPdf, icon: const Icon(Icons.picture_as_pdf, size: 18, color: Color(0xFF6D28D9)), tooltip: 'PDF للطباعة والإرسال'),
      ]),
    );

// ===================== تقرير الحضور: يوم محدد (مع السابق/التالي) أو فترة =====================
class AttendanceReportTab extends StatefulWidget {
  const AttendanceReportTab({super.key});
  @override
  State<AttendanceReportTab> createState() => _AttState();
}

class _Row {
  final String date, loc;
  int n = 0;
  double days = 0;
  _Row(this.date, this.loc);
}

class _AttState extends State<AttendanceReportTab> {
  bool _day = true;
  DateTime _d = DateTime.now();
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _loc = '';

  Future<DateTime?> _pick(DateTime init) => showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100), locale: const Locale('ar'));

  List<_Row> _rows() {
    final f = _day ? _ds(_d) : _ds(_from), t = _day ? _ds(_d) : _ds(_to);
    final m = <String, _Row>{};
    for (final r in App.I.att) {
      if (!r.counts || r.date.compareTo(f) < 0 || r.date.compareTo(t) > 0) continue;
      final l = _nl(r.loc);
      if (_loc.isNotEmpty && l != _loc) continue;
      final x = m.putIfAbsent('${r.date}|$l', () => _Row(r.date, l));
      x.n++;
      x.days = r2(x.days + r.daysOf(App.I.worker(r.wid)));
    }
    return m.values.toList()..sort((a, b) => a.date == b.date ? a.loc.compareTo(b.loc) : a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.I,
      builder: (_, __) {
        final rows = _rows();
        final n = rows.fold<int>(0, (s, x) => s + x.n);
        final d = r2(rows.fold<double>(0, (s, x) => s + x.days));
        return Column(children: [
          compactMaterial(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Column(children: [
                SegmentedButton<bool>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [ButtonSegment(value: true, label: Text('يوم محدد')), ButtonSegment(value: false, label: Text('فترة من – إلى'))],
                  selected: {_day},
                  onSelectionChanged: (s) => setState(() => _day = s.first),
                ),
                const SizedBox(height: 6),
                if (_day)
                  Row(children: [
                    IconButton(onPressed: () => setState(() => _d = _d.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_right), tooltip: 'اليوم السابق'),
                    Expanded(child: _dateBox('اليوم', _d, () async { final p = await _pick(_d); if (p != null) setState(() => _d = p); })),
                    IconButton(onPressed: () => setState(() => _d = _d.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_left), tooltip: 'اليوم التالي'),
                    TextButton(onPressed: () => setState(() => _d = DateTime.now()), child: const Text('اليوم')),
                  ])
                else
                  Row(children: [
                    Expanded(child: _dateBox('من', _from, () async { final p = await _pick(_from); if (p != null) setState(() => _from = p); })),
                    const SizedBox(width: 6),
                    Expanded(child: _dateBox('إلى', _to, () async { final p = await _pick(_to); if (p != null) setState(() => _to = p); })),
                  ]),
                const SizedBox(height: 6),
                _locDrop(_loc, (v) => setState(() => _loc = v)),
              ]),
            ),
          ),
          _bar('إجمالي العدد $n • إجمالي الحضور ${dn(d)}', rows.isEmpty ? null : () => exportTablePdf(
                context: context,
                title: 'تقرير الحضور',
                subtitle: _day ? 'يوم ${fmtDate(_ds(_d))}' : 'من ${fmtDate(_ds(_from))} إلى ${fmtDate(_ds(_to))}${_loc.isEmpty ? '' : ' — $_loc'}',
                headers: ['التاريخ', 'مكان الحضور', 'إجمالي العدد', 'إجمالي الحضور'],
                widths: [1.6, 3, 1.3, 1.4],
                rows: [for (final x in rows) [fmtDate(x.date), x.loc, '${x.n}', dn(x.days)]],
                totalsRow: ['الإجمالي', '', '$n', dn(d)],
              )),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('لا توجد سجلات حضور', style: TextStyle(color: Color(0xFF64748B))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => GlowCard(
                      glow: const Color(0xFF0E7490),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        title: Text(rows[i].loc, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        subtitle: Text(fmtDate(rows[i].date), style: const TextStyle(fontSize: 12)),
                        trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('العدد ${rows[i].n}', style: const TextStyle(fontSize: 12)),
                          Text('الحضور ${dn(rows[i].days)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

// ===================== تقرير الحسابات: لكل تسوية ومكان حضور =====================
class AccountsReportTab extends StatefulWidget {
  const AccountsReportTab({super.key});
  @override
  State<AccountsReportTab> createState() => _AccState();
}

class _Acc {
  final String date, period, loc;
  final double base, ot, bonus, total;
  _Acc(this.date, this.period, this.loc, this.base, this.ot, this.bonus, this.total);
}

class _AccState extends State<AccountsReportTab> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _loc = '';
  List _pay = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      _pay = await Api.auth('listPayroll', ['', '']) as List;
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<DateTime?> _pick(DateTime init) => showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100), locale: const Locale('ar'));

  double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? 0}') ?? 0);

  List<_Acc> _rows() {
    final f = _ds(_from), t = _ds(_to);
    final S = <String, Map<String, dynamic>>{};
    for (final x in _pay) {
      final r = x as Map;
      final date = '${r['date'] ?? ''}';
      if (date.compareTo(f) < 0 || date.compareTo(t) > 0) continue;
      final s = S.putIfAbsent('${r['id']}', () => {'date': date, 'from': '${r['from'] ?? ''}', 'to': '${r['to'] ?? ''}', 'amt': 0.0, 'ot': 0.0, 'b': 0.0, 'locs': <String, double>{}});
      s['amt'] = (s['amt'] as double) + _n(r['amount']);
      s['ot'] = (s['ot'] as double) + _n(r['ot']);
      s['b'] = (s['b'] as double) + _n(r['bonus']);
    }
    for (final r in App.I.att) {
      final s = S[r.settleId];
      if (s == null || !r.counts) continue;
      final m = s['locs'] as Map<String, double>;
      final l = _nl(r.loc);
      m[l] = r2((m[l] ?? 0) + r.paidAmt);
    }
    final out = <_Acc>[];
    for (final s in S.values) {
      final m = s['locs'] as Map<String, double>;
      final per = '${(s['from'] as String).isEmpty ? '--' : fmtDate(s['from'])} ← ${fmtDate(s['to'])}';
      if (m.isEmpty) {
        if (_loc.isEmpty) out.add(_Acc(s['date'], per, '—', r2(s['amt'] - s['ot']), r2(s['ot']), r2(s['b']), r2(s['amt'] + s['b'])));
        continue;
      }
      final sum = m.values.fold<double>(0, (a, b) => a + b);
      for (final e in m.entries) {
        if (_loc.isNotEmpty && e.key != _loc) continue;
        final sh = m.length == 1 ? 1.0 : (sum == 0 ? 0.0 : e.value / sum);
        out.add(_Acc(s['date'], per, e.key, r2(((s['amt'] as double) - (s['ot'] as double)) * sh), r2((s['ot'] as double) * sh), r2((s['b'] as double) * sh), r2(((s['amt'] as double) + (s['b'] as double)) * sh)));
      }
    }
    // دمج السطور المتطابقة (نفس التاريخ والفترة والمكان) فلا يتكرر المكان
    final mg = <String, _Acc>{};
    for (final x in out) {
      final k = '${x.date}|${x.period}|${x.loc}';
      final o = mg[k];
      mg[k] = o == null ? x : _Acc(x.date, x.period, x.loc, r2(o.base + x.base), r2(o.ot + x.ot), r2(o.bonus + x.bonus), r2(o.total + x.total));
    }
    final res = mg.values.toList();
    res.sort((a, b) => a.date == b.date ? a.loc.compareTo(b.loc) : b.date.compareTo(a.date));
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.I,
      builder: (_, __) {
        final rows = _rows();
        final bs = r2(rows.fold<double>(0, (s, x) => s + x.base));
        final ot = r2(rows.fold<double>(0, (s, x) => s + x.ot));
        final bn = r2(rows.fold<double>(0, (s, x) => s + x.bonus));
        final tot = r2(rows.fold<double>(0, (s, x) => s + x.total));
        return Column(children: [
          compactMaterial(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _dateBox('من', _from, () async { final p = await _pick(_from); if (p != null) setState(() => _from = p); })),
                  const SizedBox(width: 6),
                  Expanded(child: _dateBox('إلى', _to, () async { final p = await _pick(_to); if (p != null) setState(() => _to = p); })),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
                ]),
                const SizedBox(height: 6),
                _locDrop(_loc, (v) => setState(() => _loc = v)),
              ]),
            ),
          ),
          _bar('إجمالي $bs • إضافي $ot • مكافآت $bn • الإجمالي $tot ج', rows.isEmpty ? null : () => exportTablePdf(
                context: context,
                title: 'تقرير الحسابات',
                subtitle: 'من ${fmtDate(_ds(_from))} إلى ${fmtDate(_ds(_to))}${_loc.isEmpty ? '' : ' — $_loc'}',
                headers: ['تاريخ التسوية', 'الفترة', 'مكان الحضور', 'إجمالي', 'إضافي', 'مكافآت', 'الإجمالي'],
                widths: [1.5, 2.5, 2.2, 1.2, 1.1, 1.1, 1.3],
                landscape: true,
                rows: [for (final x in rows) [fmtDate(x.date), x.period, x.loc, x.base.toStringAsFixed(2), x.ot.toStringAsFixed(2), x.bonus.toStringAsFixed(2), x.total.toStringAsFixed(2)]],
                totalsRow: ['الإجمالي', '', '', bs.toStringAsFixed(2), ot.toStringAsFixed(2), bn.toStringAsFixed(2), tot.toStringAsFixed(2)],
                total: tot.toStringAsFixed(2),
              )),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _err != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))))
                    : rows.isEmpty
                        ? const Center(child: Text('لا توجد تسويات في الفترة', style: TextStyle(color: Color(0xFF64748B))))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                            itemCount: rows.length,
                            itemBuilder: (_, i) => GlowCard(
                              glow: const Color(0xFF15803D),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                title: Text(rows[i].loc, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                subtitle: Text('تسوية ${fmtDate(rows[i].date)}\nالفترة: ${rows[i].period}\nإجمالي ${rows[i].base} • إضافي ${rows[i].ot} • مكافآت ${rows[i].bonus}', style: const TextStyle(fontSize: 12)),
                                isThreeLine: true,
                                trailing: Text('${rows[i].total} ج', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF15803D))),
                              ),
                            ),
                          ),
          ),
        ]);
      },
    );
  }
}
