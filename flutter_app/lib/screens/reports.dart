// شاشة التقارير: تقرير عامل عن فترة + مشاركة كنص
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../state.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? _wid;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _hourly(Worker w) => w.hours <= 0 ? w.wage / 8 : w.wage / w.hours;

  List<AttRec> get _recs {
    final w = App.I.worker(_wid ?? '');
    return App.I.att
        .where((r) => r.wid == (_wid ?? '') && r.date.compareTo(_d(_from)) >= 0 && r.date.compareTo(_d(_to)) <= 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() { if (isFrom) { _from = d; } else { _to = d; } });
  }

  void _share() {
    final w = App.I.worker(_wid ?? '');
    final recs = _recs;
    final buf = StringBuffer();
    buf.writeln('تقرير حضور: ${w.name}');
    buf.writeln('الفترة: ${fmtDate(_d(_from))} ← ${fmtDate(_d(_to))}');
    buf.writeln('------------------');
    int days = 0;
    double total = 0;
    for (final r in recs) {
      final val = r.counts ? r2(r.wage + r.xh * _hourly(w)) : 0.0;
      if (r.counts) { days++; total += val; }
      buf.writeln('${fmtDate(r.date)} | ${r.status} | ${r.loc} | $val ج${r.notes.isEmpty ? '' : ' | ${r.notes}'}');
    }
    buf.writeln('------------------');
    buf.writeln('أيام الحضور: $days — الإجمالي: ${r2(total)} ج');
    Share.share(buf.toString(), subject: 'تقرير ${w.name}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workers = App.I.workers;
    if (_wid == null && workers.isNotEmpty) _wid = workers.first.id;
    final w = App.I.worker(_wid ?? '');
    final recs = _recs;
    int days = 0;
    double total = 0;
    for (final r in recs) {
      if (r.counts) {
        days++;
        total += r.wage + r.xh * _hourly(w);
      }
    }
    total = r2(total);

    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _wid,
                  decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    labelText: 'العامل',
                  ),
                  items: workers.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(),
                  onChanged: (v) => setState(() => _wid = v),
                ),
                const SizedBox(height: 8),
                Row(
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
                          child: Text(fmtDate(_d(_from)), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_left)),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pick(false),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true, border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            labelText: 'إلى',
                          ),
                          child: Text(fmtDate(_d(_to)), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // الإجمالي
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const Icon(Icons.summarize_outlined, size: 17, color: Color(0xFF7C5CFC)),
              const SizedBox(width: 6),
              Text('$days يوم حضور', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              Text('$total ج', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF7C5CFC))),
              const SizedBox(width: 8),
              IconButton(onPressed: _share, icon: const Icon(Icons.share), tooltip: 'مشاركة التقرير'),
            ],
          ),
        ),
        Expanded(
          child: recs.isEmpty
              ? const Center(child: Text('لا سجلات حضور في هذه الفترة', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  itemCount: recs.length,
                  itemBuilder: (_, i) {
                    final r = recs[i];
                    final val = r.counts ? r2(r.wage + r.xh * _hourly(w)) : 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1.5,
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 9,
                          backgroundColor: r.counts ? Colors.green.shade400 : const Color(0xFFCBD5E1),
                        ),
                        title: Text(
                          '${fmtDate(r.date)} — ${r.status}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${r.loc.isEmpty ? 'بدون مكان' : r.loc}'
                            '${r.xh > 0 ? ' • إضافي ${otText(r.xh)}' : ''}'
                            '${r.notes.isEmpty ? '' : ' • ${r.notes}'}'
                            '${r.settleId.isNotEmpty ? ' • مسوّى' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        trailing: Text(
                          r.counts ? '$val ج' : '—',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
