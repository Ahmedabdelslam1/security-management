// شاشة التسوية: صرف مستحقات العاملين + سجل المرتبات
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});
  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  int _tab = 0; // 0 = تسوية، 1 = سجل المرتبات

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // تبويبات
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('تسوية'), icon: Icon(Icons.payments_outlined, size: 17)),
                ButtonSegment(value: 1, label: Text('سجل المرتبات'), icon: Icon(Icons.receipt_long_outlined, size: 17)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
        ),
        Expanded(child: _tab == 0 ? const _SettlePane() : const _PayrollPane()),
      ],
    );
  }
}

/* ============ لوحة التسوية ============ */
class _SettlePane extends StatefulWidget {
  const _SettlePane();
  @override
  State<_SettlePane> createState() => _SettlePaneState();
}

class _SettlePaneState extends State<_SettlePane> {
  String _q = '';
  DateTime _to = DateTime.now();
  DateTime? _from;
  String? _loc; // null = كل الأماكن
  final Set<String> _sel = {};
  bool _busy = false;
  String? _err;
  final Map<String, List<double>> _adj = {}; // wid -> [مكافآت، خصومات، ضرائب]

  List<double> _a(String id) => _adj[id] ?? [0, 0, 0];
  double _netOf(Worker w, _Due d) => r2(d.amount + _a(w.id)[0] - _a(w.id)[1] - _a(w.id)[2]);

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _hourly(Worker w) => w.hours <= 0 ? w.wage / 8 : w.wage / w.hours;

  // نفس منطق السيرفر تمامًا: معاينة = ما سيُصرف فعلًا
  _Due _dueOf(Worker w) {
    final d = _Due();
    final fromS = _from == null ? '0000-00-00' : _d(_from!);
    final toS = _d(_to);
    for (final r in App.I.att) {
      if (r.wid != w.id) continue;
      if (r.date.compareTo(fromS) < 0 || r.date.compareTo(toS) > 0) continue;
      if (_loc != null && r.loc != _loc) continue;
      final counts = r.loc.trim().isNotEmpty;
      if (r.settleId.isEmpty && !counts) continue;
      final hr = (r.wage > 0 ? r.wage : w.wage) / (w.hours <= 0 ? 8 : w.hours);
      final val = counts ? r.wage + r.xh * hr : 0.0;
      final diff = (val - (r.settleId.isNotEmpty ? r.paidAmt : 0)) * 100;
      final diffR = diff.round() / 100;
      if (diffR.abs() < 0.005) continue;
      d.amount += diffR;
      if (r.settleId.isEmpty) {
        d.days++;
        d.wsum += r.wage;
        if (counts) {
          d.ot += r.xh * hr;
          d.hrs += r.xh;
        }
      } else {
        d.ot += diffR;
        d.hrs += hr > 0 ? diffR / hr : 0.0;
      }
    }
    d.amount = r2(d.amount);
    d.ot = r2(d.ot);
    d.hrs = r2(d.hrs);
    d.wage = d.days > 0 ? r2(d.wsum / d.days) : w.wage;
    return d;
  }

  void _pdf() {
    final ws = _q.isEmpty ? App.I.workers : App.I.workers.where((x) => txtMatch(_q, [x.name, x.card])).toList();
    final rows = <List<String>>[];
    var total = 0.0;
    for (final w in ws) {
      final d = _dueOf(w);
      if (d.amount.abs() < 0.005) continue;
      final a = _a(w.id);
      final net = _netOf(w, d);
      total += net;
      rows.add([w.name, '${d.days}', d.wage.toStringAsFixed(2), d.gross.toStringAsFixed(2), d.ot.toStringAsFixed(2), a[0].toStringAsFixed(2), a[1].toStringAsFixed(2), a[2].toStringAsFixed(2), net.toStringAsFixed(2), '']);
    }
    exportTablePdf(
      context: context,
      title: 'تسوية العاملين',
      subtitle: '${_from == null ? 'الكل' : fmtDate(_d(_from!))} ← ${fmtDate(_d(_to))}',
      headers: ['اسم العامل', 'عدد الأيام', 'أجر اليوم', 'الإجمالي', 'إضافي', 'المكافآت', 'الخصومات', 'الضرائب', 'الصافي', 'التوقيع'],
      widths: [3.2, 1, 1.1, 1.3, 1.1, 1.1, 1.1, 1.1, 1.4, 1.6],
      landscape: true,
      rows: rows,
      total: r2(total).toStringAsFixed(2),
      totalLabel: 'قيمة التسوية (الإجمالي)',
      totalsRow: ['الإجمالي', '${rows.fold<int>(0, (s, r) => s + int.parse(r[1]))}', '', r2(rows.fold<double>(0, (s, r) => s + double.parse(r[3]))).toStringAsFixed(2), r2(rows.fold<double>(0, (s, r) => s + double.parse(r[4]))).toStringAsFixed(2), r2(rows.fold<double>(0, (s, r) => s + double.parse(r[5]))).toStringAsFixed(2), r2(rows.fold<double>(0, (s, r) => s + double.parse(r[6]))).toStringAsFixed(2), r2(rows.fold<double>(0, (s, r) => s + double.parse(r[7]))).toStringAsFixed(2), r2(total).toStringAsFixed(2), ''],
    );
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_from ?? _to.subtract(const Duration(days: 30))) : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d == null) return;
    setState(() { if (isFrom) { _from = d; } else { _to = d; } });
  }

  Future<void> _settle() async {
    if (_sel.isEmpty) {
      setState(() => _err = 'حدد عاملًا واحدًا على الأقل');
      return;
    }
    final selected = App.I.workers.where((w) => _sel.contains(w.id)).toList();
    final withDue = selected.where((w) => _dueOf(w).amount.abs() >= 0.005).toList();
    final total = withDue.fold<double>(0, (s, w) => s + _netOf(w, _dueOf(w)));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد التسوية'),
        content: Text('صرف مستحقات ${withDue.length} عامل بإجمالي ${r2(total)} جنيه حتى ${fmtDate(_d(_to))}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد الصرف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _err = null; });
    try {
      final res = await Api.auth('settleWorkers', [
        _sel.toList(),
        _from == null ? '' : _d(_from!),
        _d(_to),
        {for (final w in withDue) w.id: {'b': _a(w.id)[0], 'd': _a(w.id)[1], 't': _a(w.id)[2]}},
        _loc,
      ]) as Map;
      await App.I.bootstrap(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم صرف ${res['count']} عامل — ${res['amount']} ج'),
        backgroundColor: Colors.green.shade700,
      ));
      setState(() { _sel.clear(); _adj.clear(); });
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locs = App.I.locs;
    final all = App.I.workers;
    final workers = _q.isEmpty ? all : all.where((w) => txtMatch(_q, [w.name, w.card])).toList();
    final dues = {for (final w in all) w.id: _dueOf(w)};

    return Column(
      children: [
        // أدوات التحديد
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(true),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            labelText: _from == null ? 'من تاريخ (الكل)' : fmtDate(_d(_from!)),
                          ),
                          child: _from == null ? const Text('اضغط للاختيار') : const Icon(Icons.event, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(false),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            labelText: 'حتى تاريخ',
                          ),
                          child: Text(fmtDate(_d(_to)), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: SearchBox(hint: 'بحث عن عامل...', value: _q, onChanged: (v) => setState(() => _q = v))),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'PDF للطباعة والإرسال',
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                  onPressed: _pdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _loc,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    labelText: 'المكان (اختياري)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل الأماكن')),
                    ...locs.map((l) => DropdownMenuItem(value: l, child: Text(l))),
                  ],
                  onChanged: (v) => setState(() => _loc = v),
                ),
              ],
            ),
          ),
        ),
        if (_err != null)
          Container(width: double.infinity, color: cs.errorContainer, padding: const EdgeInsets.all(8),
              child: Text(_err!, style: TextStyle(color: cs.onErrorContainer, fontSize: 12.5))),
        // قائمة العمال مع المستحق
        Expanded(
          child: workers.isEmpty
              ? const Center(child: Text('لا يوجد عاملون'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 90),
                  itemCount: workers.length,
                  itemBuilder: (_, i) {
                    final w = workers[i];
                    final d = dues[w.id]!;
                    final sel = _sel.contains(w.id);
                    return SlideIn(
                      index: i,
                      child: GlowCard(
                      glow: workerColor(w.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1.5,
                      color: sel ? cs.primary.withOpacity(.08) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: sel ? cs.primary : Colors.transparent, width: 1.2),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            value: sel,
                            onChanged: (v) => setState(() { v == true ? _sel.add(w.id) : _sel.remove(w.id); }),
                            title: Row(children: [workerAvatar(w.id, size: 24), const SizedBox(width: 8), Expanded(child: Text(w.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: workerColor(w.id))))]),
                            subtitle: Text(
                              d.amount.abs() < 0.005
                                  ? 'لا مستحقات ضمن التحديد'
                                  : 'مستحق: ${d.amount} ج (${d.label})\nأجر اليوم ${d.wage} • الإجمالي ${d.gross}${d.ot > 0 ? ' • إضافي ${d.ot}' : ''}',
                              style: TextStyle(
                                fontSize: 10,
                                color: d.amount.abs() < 0.005 ? const Color(0xFF64748B) : Colors.green.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            secondary: d.amount.abs() < 0.005
                                ? const Icon(Icons.check_circle_outline, color: Color(0xFF94A3B8))
                                : Text('${_netOf(w, d)}\nالصافي', textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                          ),
                          if (d.amount.abs() >= 0.005)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Row(
                                children: [
                                  for (final k in const [0, 1, 2]) ...[
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey('adj$k${w.id}'),
                                        initialValue: _a(w.id)[k] == 0 ? '' : _a(w.id)[k].toString(),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(fontSize: 12.5),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                                          labelText: const ['المكافآت', 'الخصومات', 'الضرائب'][k],
                                          labelStyle: const TextStyle(fontSize: 11.5),
                                        ),
                                        onChanged: (v) {
                                          final cur = List<double>.from(_a(w.id));
                                          cur[k] = double.tryParse(v) ?? 0;
                                          setState(() => _adj[w.id] = cur);
                                        },
                                      ),
                                    ),
                                    if (k < 2) const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ============ سجل المرتبات ============ */
class _PayrollPane extends StatefulWidget {
  const _PayrollPane();
  @override
  State<_PayrollPane> createState() => _PayrollPaneState();
}

class _PayrollPaneState extends State<_PayrollPane> {
  double _n(Map r, String k) => ((r[k] ?? 0) as num).toDouble();
  double _gross(Map r) => r2(_n(r, 'amount') - _n(r, 'ot'));
  double _wageOf(Map r) {
    final days = _n(r, 'days');
    if (days > 0) return r2(_gross(r) / days);
    return App.I.worker('${r['wid'] ?? ''}').wage;
  }

  void _pdf() {
    final all = _rows ?? [];
    final rows = <List<String>>[];
    var total = 0.0;
    for (final r in all) {
      if (!_q.isEmpty && !txtMatch(_q, ['${r['name'] ?? ''}', '${r['user'] ?? ''}'])) continue;
      total += _n(r, 'net');
      rows.add([
        '${r['name'] ?? ''}', '${r['days'] ?? 0}', _wageOf(r).toStringAsFixed(2), _gross(r).toStringAsFixed(2),
        _n(r, 'ot').toStringAsFixed(2), _n(r, 'bonus').toStringAsFixed(2), _n(r, 'ded').toStringAsFixed(2),
        _n(r, 'tax').toStringAsFixed(2), _n(r, 'net').toStringAsFixed(2), '',
      ]);
    }
    double col(int i) => r2(rows.fold<double>(0, (s, r) => s + double.parse(r[i])));
    exportTablePdf(
      context: context,
      title: 'المرتبات',
      subtitle: '${_from == null ? 'الكل' : fmtDate(_d(_from))} ← ${_to == null ? 'اليوم' : fmtDate(_d(_to))}',
      headers: ['اسم العامل', 'عدد الأيام', 'أجر اليوم', 'الإجمالي', 'إضافي', 'المكافآت', 'الخصومات', 'الضرائب', 'الصافي', 'التوقيع'],
      widths: [3.2, 1, 1.1, 1.3, 1.1, 1.1, 1.1, 1.1, 1.4, 1.6],
      landscape: true,
      rows: rows,
      total: r2(total).toStringAsFixed(2),
      totalsRow: ['الإجمالي', '${rows.fold<int>(0, (s, r) => s + int.parse(r[1]))}', '', col(3).toStringAsFixed(2), col(4).toStringAsFixed(2), col(5).toStringAsFixed(2), col(6).toStringAsFixed(2), col(7).toStringAsFixed(2), r2(total).toStringAsFixed(2), ''],
    );
  }
  String _q = '';
  DateTime? _from;
  DateTime? _to;
  List<Map>? _rows;
  bool _busy = false;

  String _d(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d == null) return;
    setState(() { if (isFrom) { _from = d; } else { _to = d; } });
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Api.auth('listPayroll', [_d(_from), _d(_to)]);
      setState(() => _rows = (r as List).map((x) => x as Map).toList());
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) {
    final all = _rows ?? [];
    final rows = _q.isEmpty ? all : all.where((r) => txtMatch(_q, [r['name'], r['user']])).toList();
    final total = rows.fold<double>(0, (s, r) => s + _n(r, 'net'));
    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pick(true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        isDense: true, border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        labelText: 'من',
                      ),
                      child: Text(_from == null ? 'الكل' : fmtDate(_d(_from)), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _pick(false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        isDense: true, border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        labelText: 'إلى',
                      ),
                      child: Text(_to == null ? 'اليوم' : fmtDate(_d(_to)), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : _load, child: const Icon(Icons.refresh)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(child: SearchBox(hint: 'بحث باسم العامل أو من صرف...', value: _q, onChanged: (v) => setState(() => _q = v))),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'PDF للطباعة والإرسال',
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                onPressed: _pdf,
                icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text('الصافي المصروف: ${r2(total)} ج — ${rows.length} سجل',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(child: Text('لا سجلات في هذه الفترة'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          return SlideIn(
                            index: i,
                            child: GlowCard(
                            glow: const Color(0xFF0369A1),
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1.5,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      workerAvatar('${r['wid'] ?? r['name'] ?? ''}', size: 24),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(r['name'] ?? '',
                                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: workerColor('${r['wid'] ?? r['name'] ?? ''}'))),
                                      ),
                                      Text('${_n(r, 'net')} ج',
                                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7C5CFC))),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${r['days'] ?? 0} يوم × ${_wageOf(r)} = ${_gross(r)} • إضافي ${_n(r, 'ot')}\nمكافآت ${_n(r, 'bonus')} • خصومات ${_n(r, 'ded')} • ضرائب ${_n(r, 'tax')}',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'صُرف في ${fmtDate(r['date'] ?? '')} • عن فترة ${r['from'] == null || r['from'] == '' ? 'البداية' : fmtDate(r['from'])} ← ${fmtDate(r['to'] ?? '')} • ${r['days']} يوم • بواسطة ${r['user'] ?? ''}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
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
    );
  }
}

class _Due {
  int days = 0;
  double amount = 0, ot = 0, hrs = 0, wsum = 0, wage = 0;
  double get gross => r2(amount - ot);
  String get label => '$days يوم${hrs > 0 ? ' + إضافي (${hrs == hrs.truncateToDouble() ? hrs.truncate() : r2(hrs)}) ساعة' : ''}';
}
