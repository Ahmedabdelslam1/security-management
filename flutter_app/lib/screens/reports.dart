// شاشة التقارير — كل البنود مثل الويب: حسب العامل / حسب مكان الحضور / تقرير مجمع / خطاب الاعتماد
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../letter_pdf.dart';
import '../pdf_export.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';

// ===== التفقيط: تحويل المبلغ لكلمات بالجنيه والقروش (مثل الويب) =====
String _three(int x) {
  const ones = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
  const tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
  const hunds = ['', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];
  final p = <String>[];
  final h = x ~/ 100, r = x % 100;
  if (h > 0) p.add(hunds[h]);
  if (r > 0) {
    if (r < 20) {
      p.add(ones[r]);
    } else {
      final t = r ~/ 10, o = r % 10;
      p.add(o > 0 ? '${ones[o]} و${tens[t]}' : tens[t]);
    }
  }
  return p.join(' و');
}

String numWords(int n) {
  n = n.round();
  if (n == 0) return 'صفر';
  final mil = n ~/ 1000000, th = (n ~/ 1000) % 1000, rest = n % 1000;
  final p = <String>[];
  if (mil > 0) p.add(mil == 1 ? 'مليون' : (mil == 2 ? 'مليونان' : '${_three(mil)} ملايين'));
  if (th > 0) p.add(th == 1 ? 'ألف' : (th == 2 ? 'ألفان' : (th <= 10 ? '${_three(th)} آلاف' : '${_three(th)} ألفاً')));
  if (rest > 0) p.add(_three(rest));
  return p.join(' و');
}

String amtWords(double a) {
  a = (a * 100).round() / 100;
  final w = a.truncate();
  final f = ((a - w) * 100).round();
  var t = (w > 0 || f == 0) ? '${w == 0 ? 'صفر' : numWords(w)} جنيها' : '';
  if (f > 0) t += '${t.isNotEmpty ? ' و' : ''}${numWords(f)} قرشا';
  if (t.isEmpty) t = 'صفر جنيها';
  return '$t لا غير';
}

class _Rec { // سطر تقرير لكل عامل (مكان/مجمع/خطاب)
  final Worker w;
  int days;
  double xh, total;
  double gross = 0, ot = 0; // الإجمالي (أيام × أجر) والإضافي بالمبلغ
  _Rec(this.w, {this.days = 0, this.xh = 0, this.total = 0});
  double get wageAvg => days > 0 ? r2(gross / days) : w.wage;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _sub = 1;
  String _q = '';
  String? _wid;
  String? _loc;
  String _locFilter = ''; // '' = كل الأماكن
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  // مكافآت وخصومات وضرائب كل عامل من التسويات المتداخلة مع فترة التقرير
  Map<String, List<double>> _adj = {};
  List<double> _adjOf(String wid) => _adj[wid] ?? const [0, 0, 0];
  double _bOf(String wid) => _adjOf(wid)[0];
  double _dOf(String wid) => _adjOf(wid)[1];
  double _tOf(String wid) => _adjOf(wid)[2];

  Future<void> _loadAdj() async {
    try {
      final list = await Api.auth('listPayroll', ['', '']) as List;
      final f = _d(_from), to = _d(_to);
      final m = <String, List<double>>{};
      for (final x in list) {
        final r = x as Map;
        var rf = '${r['from'] ?? ''}';
        if (rf.isEmpty) rf = '0000-00-00';
        var rt = '${r['to'] ?? ''}';
        if (rt.isEmpty) rt = '9999-99-99';
        if (rf.compareTo(to) > 0 || rt.compareTo(f) < 0) continue;
        final o = m.putIfAbsent('${r['wid'] ?? ''}', () => [0, 0, 0]);
        o[0] += ((r['bonus'] ?? 0) as num).toDouble();
        o[1] += ((r['ded'] ?? 0) as num).toDouble();
        o[2] += ((r['tax'] ?? 0) as num).toDouble();
      }
      _adj = {for (final e in m.entries) e.key: [r2(e.value[0]), r2(e.value[1]), r2(e.value[2])]};
    } catch (_) {
      _adj = {};
    }
    if (mounted) setState(() {});
  }

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  double _hourly(Worker w) => w.hours <= 0 ? w.wage / 8 : w.wage / w.hours;
  double _hourlyR(AttRec r, Worker w) => (r.wage > 0 ? r.wage : w.wage) / (w.hours <= 0 ? 8 : w.hours);
  bool _inPeriod(AttRec r) => r.date.compareTo(_d(_from)) >= 0 && r.date.compareTo(_d(_to)) <= 0;

  List<AttRec> get _workerRecs {
    return App.I.att.where((r) => r.wid == (_wid ?? '') && _inPeriod(r)).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  // سطور تقرير المكان: كل العمال اللي حضروا المكان المحدد خلال الفترة
  List<_Rec> get _locRows {
    final map = <String, _Rec>{};
    for (final w in App.I.workers) {
      map[w.id] = _Rec(w);
    }
    for (final r in App.I.att) {
      if (r.counts && _inPeriod(r) && r.loc == (_loc ?? '')) {
        final m = map[r.wid];
        if (m == null) continue;
        m.days++;
        m.xh += r.xh;
        m.gross += r.wage;
        m.ot += r.xh * _hourlyR(r, m.w);
        m.total += r.wage + r.xh * _hourlyR(r, m.w);
      }
    }
    final rows = map.values.where((m) => m.days > 0).toList()..sort((a, b) => b.days.compareTo(a.days));
    for (final m in rows) {
      m.total = r2(m.total);
      m.gross = r2(m.gross);
      m.ot = r2(m.ot);
    }
    return rows;
  }

  // سطور التقرير المجمع: كل العمال خلال الفترة (زي الويب — حتى اللي مالهمش حضور)
  List<_Rec> get _sumRows {
    final map = <String, _Rec>{};
    for (final w in App.I.workers) {
      map[w.id] = _Rec(w);
    }
    for (final r in App.I.att) {
      if (r.counts && _inPeriod(r)) {
        final m = map[r.wid];
        if (m == null) continue;
        m.days++;
        m.xh += r.xh;
        m.gross += r.wage;
        m.ot += r.xh * _hourlyR(r, m.w);
        m.total += r.wage + r.xh * _hourlyR(r, m.w);
      }
    }
    final rows = App.I.workers.map((w) => map[w.id]!).where((m) => m.days > 0).toList();
    for (final m in rows) {
      m.total = r2(m.total);
      m.gross = r2(m.gross);
      m.ot = r2(m.ot);
    }
    return rows;
  }

  // سطور خطاب الاعتماد: العمال اللي ليهم حضور خلال الفترة (مع فلتر مكان اختياري)
  List<_Rec> get _letterRows {
    final out = <_Rec>[];
    for (final w in App.I.workers) {
      var xh = 0.0, tot = 0.0, gr = 0.0, otA = 0.0;
      var days = 0;
      for (final r in App.I.att) {
        if (r.wid == w.id && _inPeriod(r) && r.counts && (_locFilter.isEmpty || r.loc == _locFilter)) {
          days++;
          xh += r.xh;
          gr += r.wage;
          otA += r.xh * _hourlyR(r, w);
          tot += r.wage + r.xh * _hourlyR(r, w);
        }
      }
      if (days == 0) continue;
      out.add(_Rec(w, days: days, xh: xh, total: r2(tot))..gross = r2(gr)..ot = r2(otA));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _loadAdj();
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() { if (isFrom) { _from = d; } else { _to = d; } });
      _loadAdj();
    }
  }

  // ===== مشاركات نصية =====
  void _shareWorker() {
    final w = App.I.worker(_wid ?? '');
    final recs = _workerRecs;
    final buf = StringBuffer();
    buf.writeln('تقرير حضور: ${w.name}');
    buf.writeln('الفترة: ${fmtDate(_d(_from))} ← ${fmtDate(_d(_to))}');
    buf.writeln('------------------');
    int days = 0;
    double total = 0;
    for (final r in recs) {
      final val = r.counts ? r2(r.wage + r.xh * _hourlyR(r, w)) : 0.0;
      if (r.counts) { days++; total += val; }
      buf.writeln('${fmtDate(r.date)} | ${r.status} | ${r.loc} | $val ج${r.notes.isEmpty ? '' : ' | ${r.notes}'}');
    }
    buf.writeln('------------------');
    buf.writeln('أيام الحضور: $days — الإجمالي: ${r2(total)} ج');
    Share.share(buf.toString(), subject: 'تقرير ${w.name}');
  }

  void _shareRows(String title, List<_Rec> rows) {
    final buf = StringBuffer();
    buf.writeln(title);
    buf.writeln('الفترة: ${fmtDate(_d(_from))} ← ${fmtDate(_d(_to))}');
    buf.writeln('------------------');
    for (final m in rows) {
      buf.writeln('${m.w.name} | ${m.days} يوم × ${m.wageAvg} = ${m.gross} | إضافي ${m.ot} | ${m.total} ج');
    }
    final days = rows.fold<int>(0, (s, m) => s + m.days);
    final total = r2(rows.fold<double>(0, (s, m) => s + m.total));
    final otT = r2(rows.fold<double>(0, (s, m) => s + m.ot));
    buf.writeln('------------------');
    buf.writeln('إجمالي الأيام: $days — إضافي: $otT — الإجمالي: $total ج');
    Share.share(buf.toString(), subject: title);
  }

  void _shareLetter() {
    final rows = _letterRows;
    final addressee = _locFilter.isNotEmpty ? _locFilter : (_loc ?? 'الموقع');
    final tot = r2(rows.fold<double>(0, (s, m) => s + m.total));
    final buf = StringBuffer();
    buf.writeln('خطاب اعتماد');
    buf.writeln('السيد / مدير $addressee');
    buf.writeln('تحية طيبة وبعد ،،،');
    buf.writeln('برجاء من سيادتكم التكرم بالموافقة على اعتماد مبلغ ( $tot ) فقط وقدرة : ( ${amtWords(tot)} )');
    buf.writeln('وذلك قيمة أجور أيام حضور العمال اليوميه الاتى أسماؤهم خلال الفترة من ${fmtDate(_d(_from))} حتى ${fmtDate(_d(_to))}');
    buf.writeln('------------------');
    for (final m in rows) {
      buf.writeln('${m.w.name} | أيام: ${m.days} | ${m.wageAvg} ج/يوم | إضافي: ${m.ot} | ${m.total} ج');
    }
    final days = rows.fold<int>(0, (s, m) => s + m.days);
    buf.writeln('------------------');
    buf.writeln('إجمالي الأيام: $days — الإجمالي: $tot ج');
    buf.writeln('ولسيادتكم فائق الاحترام والتقدير');
    Share.share(buf.toString(), subject: 'خطاب اعتماد');
  }

  Future<void> _letterPdf() async {
    final rows = _letterRows;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا عمال لهم حضور في هذه الفترة'), backgroundColor: Colors.black54));
      return;
    }
    await _loadAdj();
    final addressee = _locFilter.isNotEmpty ? _locFilter : (_loc ?? 'الموقع');
    var tot = 0.0;
    final lrows = [for (final m in rows) LetterRow(m.w.name, m.days, m.wageAvg, m.gross, m.ot, b: _bOf(m.w.id), d: _dOf(m.w.id), tax: _tOf(m.w.id), net: r2(m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id)))];
    for (final m in lrows) {
      tot += m.net;
    }
    tot = r2(tot);
    final bytes = await buildLetterPdf(
      rows: lrows,
      addressee: addressee,
      from: fmtDate(_d(_from)),
      to: fmtDate(_d(_to)),
      amountWords: amtWords(tot),
    );
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('خطاب الاعتماد — PDF جاهز', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('اختر الطباعة أو الإرسال عبر واتساب أو البريد', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.print, size: 19),
                  label: const Text('معاينة وطباعة'),
                  onPressed: () { Navigator.pop(context); Printing.layoutPdf(name: 'خطاب اعتماد', onLayout: (_) async => bytes); },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                  icon: const Icon(Icons.send, size: 19),
                  label: const Text('إرسال PDF (واتساب / بريد / إلخ)'),
                  onPressed: () { Navigator.pop(context); Printing.sharePdf(bytes: bytes, filename: 'خطاب-اعتماد.pdf'); },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.text_snippet, size: 19),
                  label: const Text('مشاركة كنص'),
                  onPressed: () { Navigator.pop(context); _shareLetter(); },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = App.I.workers;
    if (_wid == null && all.isNotEmpty) _wid = all.first.id;
    if (_loc == null && App.I.locs.isNotEmpty) _loc = App.I.locs.first;

    return Column(
      children: [
        // بنود التقارير — مثل الويب
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('حسب العامل', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
                ButtonSegment(value: 2, label: Text('حسب المكان', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
                ButtonSegment(value: 3, label: Text('مجمع', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
                ButtonSegment(value: 4, label: Text('خطاب اعتماد', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
              ],
              selected: {_sub},
              onSelectionChanged: (s) => setState(() => _sub = s.first),
            ),
          ),
        ),
        Expanded(child: _sub == 1 ? _workerTab(all) : _sub == 2 ? _locTab() : _sub == 3 ? _summaryTab() : _letterTab()),
      ],
    );
  }

  // ================= (1) حسب العامل =================
  Widget _workerTab(List<Worker> all) {
    final w = App.I.worker(_wid ?? '');
    final workers = _q.isEmpty ? all : all.where((x) => txtMatch(_q, [x.name, x.card])).toList();
    final recs = _workerRecs;
    int days = 0;
    double total = 0;
    for (final r in recs) {
      if (r.counts) {
        days++;
        total += r.wage + r.xh * _hourlyR(r, w);
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
                SearchBox(hint: 'بحث عن عامل للعرض...', value: _q, onChanged: (v) => setState(() { _q = v; if (_wid != null && !workers.any((x) => x.id == _wid)) _wid = workers.isNotEmpty ? workers.first.id : null; })),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _wid,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), labelText: 'العامل'),
                  items: workers.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(),
                  onChanged: (v) => setState(() => _wid = v),
                ),
                const SizedBox(height: 8),
                _dateRow(),
              ],
            ),
          ),
        ),
        Builder(builder: (_) {
          final b = _bOf(_wid ?? ''), dd = _dOf(_wid ?? ''), tx = _tOf(_wid ?? '');
          final net = r2(total + b - dd - tx);
          return _totalsBar('$days يوم حضور • مكافآت $b / خصومات $dd / ضرائب $tx', net, _shareWorker, onPdf: () async {
            await _loadAdj();
            final ww = App.I.worker(_wid ?? '');
            final b2 = _bOf(_wid ?? ''), d2 = _dOf(_wid ?? ''), t2 = _tOf(_wid ?? '');
            final net2 = r2(total + b2 - d2 - t2);
            exportTablePdf(
              context: context,
              title: 'تقرير عامل: ${ww.name}',
              subtitle: 'من ${fmtDate(_d(_from))} إلى ${fmtDate(_d(_to))}\nمكافآت: $b2 ج | خصومات: $d2 ج | ضرائب: $t2 ج — الصافي المستحق: $net2 ج',
              headers: ['التاريخ', 'الموقف', 'مكان الحضور', 'إضافي', 'القيمة', 'ملاحظات'],
              widths: [55, 55, 60, 40, 45, 70],
              rows: [for (final r in recs) [fmtDate(r.date), r.status, r.loc.isEmpty ? '—' : r.loc, r.xh > 0 ? otText(r.xh) : '—', r.counts ? r2(r.wage + r.xh * _hourlyR(r, ww)).toStringAsFixed(2) : '—', r.notes]],
              total: net2.toStringAsFixed(2),
              totalsRow: ['الإجمالي', '$days يوم', '', '', total.toStringAsFixed(2), ''],
            );
          });
        }),
        Expanded(
          child: recs.isEmpty
              ? const Center(child: Text('لا سجلات حضور في هذه الفترة', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  itemCount: recs.length,
                  itemBuilder: (_, i) {
                    final r = recs[i];
                    final val = r.counts ? r2(r.wage + r.xh * _hourlyR(r, w)) : 0.0;
                    return SlideIn(
                      index: i,
                      child: GlowCard(
                        glow: const Color(0xFFBE185D),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(radius: 9, backgroundColor: r.counts ? Colors.green.shade400 : const Color(0xFFCBD5E1)),
                          title: Text('${fmtDate(r.date)} — ${r.status}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
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
                          trailing: Text(r.counts ? '$val ج' : '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ================= (2) حسب مكان الحضور =================
  Widget _locTab() {
    final rows = _locRows;
    final days = rows.fold<int>(0, (s, m) => s + m.days);
    final total = r2(rows.fold<double>(0, (s, m) => s + m.total));
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
                  value: _loc,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), labelText: 'مكان الحضور'),
                  items: App.I.locs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setState(() => _loc = v),
                ),
                const SizedBox(height: 8),
                _dateRow(),
              ],
            ),
          ),
        ),
        Builder(builder: (_) {
          var tb = 0.0, td = 0.0, tt = 0.0, tnet = 0.0;
          for (final m in rows) {
            final b = _bOf(m.w.id), d = _dOf(m.w.id), x = _tOf(m.w.id);
            tb += b; td += d; tt += x; tnet += m.total + b - d - x;
          }
          tnet = r2(tnet);
          return _totalsBar('$days يوم حضور • الصافي ${tnet.toStringAsFixed(2)} ج', total, () => _shareRows('تقرير مكان: ${_loc ?? ''}', rows), onPdf: () async {
            await _loadAdj();
            var b2 = 0.0, d2 = 0.0, x2 = 0.0, n2 = 0.0;
            final rws = [for (final m in rows) [m.w.name, '${m.days}', m.wageAvg.toStringAsFixed(m.wageAvg == m.wageAvg.truncateToDouble() ? 0 : 2), m.gross.toStringAsFixed(2), m.ot.toStringAsFixed(2), _bOf(m.w.id).toStringAsFixed(2), _dOf(m.w.id).toStringAsFixed(2), _tOf(m.w.id).toStringAsFixed(2), r2(m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id)).toStringAsFixed(2)]];
            for (final m in rows) { b2 += _bOf(m.w.id); d2 += _dOf(m.w.id); x2 += _tOf(m.w.id); n2 += m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id); }
            exportTablePdf(
              context: context,
              title: 'تقرير مكان الحضور: ${_loc ?? ''}',
              subtitle: 'من ${fmtDate(_d(_from))} إلى ${fmtDate(_d(_to))}',
              headers: ['اسم العامل', 'عدد الأيام', 'أجر اليوم', 'الإجمالي', 'إضافي', 'المكافآت', 'الخصومات', 'الضرائب', 'الصافي'],
              widths: [3.2, 1, 1.1, 1.3, 1.1, 1.2, 1.2, 1.1, 1.4],
              landscape: true,
              rows: rws,
              total: r2(n2).toStringAsFixed(2),
              totalsRow: ['الإجمالي', '$days يوم', '', r2(rows.fold<double>(0, (s, m) => s + m.gross)).toStringAsFixed(2), r2(rows.fold<double>(0, (s, m) => s + m.ot)).toStringAsFixed(2), r2(b2).toStringAsFixed(2), r2(d2).toStringAsFixed(2), r2(x2).toStringAsFixed(2), r2(n2).toStringAsFixed(2)],
            );
          });
        }),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا سجلات في هذا المكان خلال الفترة', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => SlideIn(
                    index: i,
                    child: GlowCard(
                      glow: const Color(0xFFBE185D),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.person, size: 19, color: Color(0xFF1D4ED8)),
                        title: Text(rows[i].w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        subtitle: Text('${rows[i].days} يوم × ${rows[i].wageAvg} = ${rows[i].gross} • إضافي ${rows[i].ot}${_bOf(rows[i].w.id) + _dOf(rows[i].w.id) + _tOf(rows[i].w.id) > 0 ? ' • صافي ${r2(rows[i].total + _bOf(rows[i].w.id) - _dOf(rows[i].w.id) - _tOf(rows[i].w.id))} ج' : ''}', style: const TextStyle(fontSize: 12)),
                        trailing: Text('${rows[i].total} ج', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFBE185D))),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ================= (3) تقرير مجمع =================
  Widget _summaryTab() {
    final rows = _sumRows;
    final days = rows.fold<int>(0, (s, m) => s + m.days);
    final total = r2(rows.fold<double>(0, (s, m) => s + m.total));
    return Column(
      children: [
        Material(color: Colors.white, elevation: 1, child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: _dateRow())),
        Builder(builder: (_) {
          var tb = 0.0, td = 0.0, tt = 0.0, tnet = 0.0;
          for (final m in rows) {
            final b = _bOf(m.w.id), d = _dOf(m.w.id), x = _tOf(m.w.id);
            tb += b; td += d; tt += x; tnet += m.total + b - d - x;
          }
          tnet = r2(tnet);
          return _totalsBar('$days يوم — إضافي ${r2(rows.fold<double>(0, (s, m) => s + m.ot))} • الصافي ${tnet.toStringAsFixed(2)} ج', total, null, onPdf: () async {
            await _loadAdj();
            var b2 = 0.0, d2 = 0.0, x2 = 0.0, n2 = 0.0;
            final rws = [for (final m in rows) [m.w.name, '${m.days}', m.wageAvg.toStringAsFixed(m.wageAvg == m.wageAvg.truncateToDouble() ? 0 : 2), m.gross > 0 ? m.gross.toStringAsFixed(2) : '—', m.ot.toStringAsFixed(2), _bOf(m.w.id).toStringAsFixed(2), _dOf(m.w.id).toStringAsFixed(2), _tOf(m.w.id).toStringAsFixed(2), r2(m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id)).toStringAsFixed(2)]];
            for (final m in rows) { b2 += _bOf(m.w.id); d2 += _dOf(m.w.id); x2 += _tOf(m.w.id); n2 += m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id); }
            exportTablePdf(
              context: context,
              title: 'تقرير مجمع للعاملين',
              subtitle: 'من ${fmtDate(_d(_from))} إلى ${fmtDate(_d(_to))}',
              headers: ['اسم العامل', 'عدد الأيام', 'أجر اليوم', 'الإجمالي', 'إضافي', 'المكافآت', 'الخصومات', 'الضرائب', 'الصافي'],
              widths: [3.2, 1, 1.1, 1.3, 1.1, 1.2, 1.2, 1.1, 1.4],
              landscape: true,
              rows: rws,
              total: r2(n2).toStringAsFixed(2),
              totalsRow: ['الإجمالي', '$days يوم', '', r2(rows.fold<double>(0, (s, m) => s + m.gross)).toStringAsFixed(2), r2(rows.fold<double>(0, (s, m) => s + m.ot)).toStringAsFixed(2), r2(b2).toStringAsFixed(2), r2(d2).toStringAsFixed(2), r2(x2).toStringAsFixed(2), r2(n2).toStringAsFixed(2)],
            );
          });
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final m = rows[i];
              return SlideIn(
                index: i,
                child: GlowCard(
                  glow: const Color(0xFFBE185D),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 10, backgroundColor: m.days > 0 ? Colors.green.shade400 : const Color(0xFFCBD5E1), child: Text('${m.days}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white))),
                    title: Text(m.w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    subtitle: Text('${m.days} يوم × ${m.wageAvg} = ${m.gross} • إضافي ${m.ot}${_bOf(m.w.id) + _dOf(m.w.id) + _tOf(m.w.id) > 0 ? ' • صافي ${r2(m.total + _bOf(m.w.id) - _dOf(m.w.id) - _tOf(m.w.id))} ج' : ''}', style: const TextStyle(fontSize: 12)),
                    trailing: Text(m.total > 0 ? '${m.total} ج' : '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFBE185D))),
                    onTap: () => _detail(m.w),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _detail(Worker w) {
    final recs = App.I.att.where((r) => r.wid == w.id && r.counts && _inPeriod(r)).toList()..sort((a, b) => a.date.compareTo(b.date));
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text('تفاصيل: ${w.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Text('من ${fmtDate(_d(_from))} إلى ${fmtDate(_d(_to))} — ${recs.length} سجل', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final r in recs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${fmtDate(r.date)} — ${r.status} — ${r.loc}${r.xh > 0 ? ' — إضافي ${otText(r.xh)}' : ''}', style: const TextStyle(fontSize: 12.5)),
            ),
          if (recs.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('لا سجلات حضور', textAlign: TextAlign.center, style: TextStyle(color: Colors.black38))),
        ],
      ),
    );
  }

  // ================= (4) خطاب الاعتماد =================
  Widget _letterTab() {
    final rows = _letterRows;
    final days = rows.fold<int>(0, (s, m) => s + m.days);
    final total = r2(rows.fold<double>(0, (s, m) => s + m.total));
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
                  value: _locFilter,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), labelText: 'المكان (اختياري)'),
                  items: [const DropdownMenuItem(value: '', child: Text('كل الأماكن'))]..addAll(App.I.locs.map((l) => DropdownMenuItem(value: l, child: Text(l)))),
                  onChanged: (v) => setState(() => _locFilter = v ?? ''),
                ),
                const SizedBox(height: 8),
                _dateRow(),
              ],
            ),
          ),
        ),
        _totalsBar('$days يوم — ${rows.length} عامل', total, _letterPdf),
        // زر PDF للطباعة والإرسال
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
              icon: const Icon(Icons.picture_as_pdf, size: 19),
              label: const Text('PDF — للطباعة والإرسال'),
              onPressed: _letterPdf,
            ),
          ),
        ),
        // صندوق التفقيط مثل الويب
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDD6FE)),
            boxShadow: [BoxShadow(color: const Color(0xFF7C5CFC).withOpacity(.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: [
              Text('المبلغ كتابةً:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black45)),
              const SizedBox(height: 3),
              Text(amtWords(total), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF6D28D9))),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا عمال لهم حضور في هذه الفترة', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final m = rows[i];
                    return SlideIn(
                      index: i,
                      child: GlowCard(
                        glow: const Color(0xFFBE185D),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.badge_outlined, size: 19, color: Color(0xFF6D28D9)),
                          title: Text(m.w.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                          subtitle: Text('أيام: ${m.days} • ${m.wageAvg} ج/يوم • الإجمالي ${m.gross} • إضافي ${m.ot}', style: const TextStyle(fontSize: 12)),
                          trailing: Text('${m.total} ج', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFBE185D))),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ================= مكونات مشتركة =================
  Widget _dateRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pick(true),
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), labelText: 'من'),
              child: Text(fmtDate(_d(_from)), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_left)),
        Expanded(
          child: InkWell(
            onTap: () => _pick(false),
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), labelText: 'إلى'),
              child: Text(fmtDate(_d(_to)), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalsBar(String mid, double total, VoidCallback? onShare, {VoidCallback? onPdf}) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.summarize_outlined, size: 17, color: Color(0xFF7C5CFC)),
          const SizedBox(width: 6),
          Flexible(child: Text(mid, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
          const Spacer(),
          Text('$total ج', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF7C5CFC))),
          const SizedBox(width: 4),
          if (onShare != null) IconButton(onPressed: onShare, icon: const Icon(Icons.share), tooltip: 'مشاركة كنص'),
          if (onPdf != null) IconButton(onPressed: onPdf, icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF6D28D9)), tooltip: 'PDF للطباعة والإرسال'),
        ],
      ),
    );
  }
}
