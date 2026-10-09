// شاشة تسجيل حضور اليوم (أو تاريخ سابق) — نفس منطق نسخة الويب
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _q = '';
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
          wg: _numStr((byWid[w.id]?.wage ?? 0) > 0 ? byWid[w.id]!.wage : w.wage),
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
        if (c.status == '--' && c.loc.trim().isEmpty) return;
        recs.add({
          'wid': wid,
          'status': c.status,
          'loc': c.loc.trim(),
          'xh': kExtraStatuses.contains(c.status) ? (double.tryParse(c.xh) ?? 0) : 0,
          'wage': double.tryParse(c.wg) ?? 0,
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
    final all = app.workers;
    final workers = _q.isEmpty ? all : all.where((w) => txtMatch(_q, [w.name, w.card])).toList();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(
              children: [
                Expanded(child: SearchBox(hint: 'بحث عن عامل بالاسم أو البطاقة...', value: _q, onChanged: (v) => setState(() => _q = v))),
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
                      itemBuilder: (_, i) => SlideIn(index: i, child: _workerCard(context, workers[i], locs)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _numStr(double x) => x == x.truncateToDouble() ? x.truncate().toString() : x.toString();

  // المستحق = عدد الأيام + الإضافي = الإجمالي (نفس منطق الويب)
  List<String> _dueParts(Worker w, _RowCtl c) {
    var days = 0;
    var ot = 0.0;
    var hrsTotal = 0.0;
    var amt = 0.0;
    final hrs = w.hours <= 0 ? 8.0 : w.hours;
    AttRec? saved;
    for (final r in App.I.att) {
      if (r.wid != w.id) continue;
      if (r.date == _dstr) saved = r;
      if (r.date.compareTo(_dstr) >= 0) continue;
      final h = (r.wage > 0 ? r.wage : w.wage) / hrs;
      final val = r.counts ? r.wage + r.xh * h : 0.0;
      final d = r2(val - (r.settleId.isNotEmpty ? r.paidAmt : 0));
      amt += d;
      if (d > 0.005) {
        days++;
        ot += r.settleId.isNotEmpty ? d : r.xh * h;
        hrsTotal += r.settleId.isNotEmpty ? (h > 0 ? d / h : 0.0) : r.xh;
      }
    }
    final wgRaw = double.tryParse(c.wg) ?? 0;
    final wg = wgRaw > 0 ? wgRaw : w.wage;
    final counts = c.loc.trim().isNotEmpty;
    final xh = kExtraStatuses.contains(c.status) ? (double.tryParse(c.xh) ?? 0) : 0.0;
    final liveOt = xh * (wg / hrs);
    final settled = saved != null && saved.settleId.isNotEmpty;
    final d = r2((counts ? wg + liveOt : 0.0) - (settled ? saved!.paidAmt : 0));
    amt += d;
    if (d > 0.005) {
      days++;
      ot += settled ? d : liveOt;
      hrsTotal += settled ? (wg > 0 ? d / (wg / hrs) : 0.0) : xh;
    }
    final hr0 = hrsTotal;
    return ['$days يوم', hr0 > 0 ? '+ إضافي (${_numStr(r2(hr0))}) ساعة' : '', '= ${r2(amt < 0 ? 0 : amt)}'];
  }

  void _pdf() {
    final ws = _q.isEmpty ? App.I.workers : App.I.workers.where((x) => txtMatch(_q, [x.name, x.card])).toList();
    final rows = <List<String>>[];
    var present = 0;
    for (final w in ws) {
      final c = _ctl[w.id];
      if (c == null) continue;
      if (c.status != '--' || c.loc.trim().isNotEmpty) present++;
      final xhN = double.tryParse(c.xh) ?? 0;
      final ex = (kExtraStatuses.contains(c.status) && xhN > 0) ? 'إضافي (${_numStr(xhN)}) ساعة' : '';
      rows.add([w.name, c.status == '--' ? '—' : c.status, c.loc.isEmpty ? '—' : c.loc, [ex, c.notes].where((x) => x.isNotEmpty).join(' — ')]);
    }
    exportTablePdf(
      context: context,
      title: 'كشف الحضور اليومي',
      subtitle: fmtDate(_dstr),
      headers: ['اسم العامل', 'الموقف', 'مكان الحضور', 'ملاحظات'],
      widths: [95, 75, 75, 120],
      rows: rows,
      totalsRow: ['الحضور: $present من ${ws.length}', '', '', ''],
    );
  }

  static const _palette = [Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF7C3AED), Color(0xFF0D9488), Color(0xFFDC2626), Color(0xFF0369A1)];

  InputDecoration _dec(String? label, {String? hint, Widget? suffix}) => InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 11),
        hintStyle: const TextStyle(fontSize: 11.5),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      );

  Widget _workerCard(BuildContext context, Worker w, List<String> locs) {
    final c = _ctl[w.id]!;
    final cs = Theme.of(context).colorScheme;
    final isExtra = kExtraStatuses.contains(c.status);
    final active = c.status != '--';
    final isSettled = App.I.att.any((r) => r.date == _dstr && r.wid == w.id && r.settleId.isNotEmpty);
    final col = _palette[w.id.hashCode.abs() % _palette.length];

    return GlowCard(
      glow: col,
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? col.withOpacity(.45) : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                  child: const Icon(Icons.person, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => _showDays(w),
                    child: Text(w.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: col, decoration: TextDecoration.underline, decorationColor: col.withOpacity(.4))),
                  ),
                ),
                if (isSettled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
                    child: Text('مسوّى', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                  ),
                const SizedBox(width: 6),
                Text('${w.wage}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 11)),
                if (!isSettled)
                  IconButton(
                    tooltip: 'حفظ',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    style: IconButton.styleFrom(backgroundColor: col.withOpacity(.12)),
                    onPressed: () => _saveOne(w),
                    icon: Icon(Icons.save, size: 15, color: col),
                  ),
              ],
            ),
            Builder(builder: (_) {
              final p = _dueParts(w, c);
              return Padding(
                padding: const EdgeInsets.fromLTRB(30, 2, 0, 4),
                child: Text.rich(TextSpan(style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9.5), children: [
                  const TextSpan(text: 'المستحق: ', style: TextStyle(color: Color(0xFF64748B))),
                  TextSpan(text: p[0], style: const TextStyle(color: Color(0xFF1D4ED8))),
                  if (p[1].isNotEmpty) TextSpan(text: ' ${p[1]}', style: const TextStyle(color: Color(0xFFEA580C))),
                  TextSpan(text: ' ${p[2]}', style: const TextStyle(color: Color(0xFF15803D))),
                ])),
              );
            }),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: kStatuses.contains(c.status) ? c.status : '--',
                    decoration: _dec(null),
                    items: kStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s == '--' ? 'بدون تسجيل' : s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() { c.status = v ?? '--'; if (!kExtraStatuses.contains(c.status)) c.xh = ''; }),
                  ),
                ),
                ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: locs.contains(c.loc) ? c.loc : null,
                      decoration: _dec(null, hint: c.loc.isNotEmpty && !locs.contains(c.loc) ? c.loc : 'المكان',
                          suffix: InkWell(onTap: () => _newLoc(c), child: const Icon(Icons.add_location_alt_outlined, size: 15))),
                      items: locs.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => c.loc = v ?? ''),
                    ),
                  ),
                ],
              ],
            ),
            if (active) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  if (isExtra) ...[
                    SizedBox(
                      width: 78,
                      child: TextField(
                        controller: TextEditingController(text: c.xh)..selection = TextSelection.collapsed(offset: c.xh.length),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _dec('إضافي (ساعة)'),
                        style: const TextStyle(fontSize: 12),
                        onChanged: (v) => setState(() => c.xh = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: c.notes)..selection = TextSelection.collapsed(offset: c.notes.length),
                      decoration: _dec('ملاحظات'),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (v) => c.notes = v,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===== تقرير أيام العامل: عرض وتعديل وطباعة/حفظ =====
  String _ds(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<bool> _saveRec(String date, Map<String, dynamic> rec) async {
    try {
      final res = await Api.auth('saveDay', [date, [rec], true]) as Map;
      final fresh = (res['att'] as List).map((r) => AttRec.fromJson(r as Map)).toList();
      final app = App.I;
      final kept = app.att.where((r) => r.date != date).toList()..addAll(fresh);
      final newLocs = (res['locs'] as List).map((l) => l.toString()).where((l) => !app.locs.contains(l)).toList();
      app.att..clear()..addAll(kept);
      app.locs.addAll(newLocs);
      app.notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showDays(Worker w) async {
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, 1);
    var to = now;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final f = _ds(from), t = _ds(to);
        final recs = App.I.att.where((r) => r.wid == w.id && r.date.compareTo(f) >= 0 && r.date.compareTo(t) <= 0 && r.counts).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final hrs = w.hours <= 0 ? 8.0 : w.hours;
        double val(AttRec r) => r.counts ? (r.wage > 0 ? r.wage : w.wage) + r.xh * ((r.wage > 0 ? r.wage : w.wage) / hrs) : 0.0;
        final total = r2(recs.fold<double>(0, (s, r) => s + val(r)));
        final days = recs.where((r) => r.counts).length;
        final xs = recs.fold<double>(0, (s, r) => s + r.xh);
        String exTxt(double x) => x > 0 ? 'إضافي (${x == x.truncateToDouble() ? x.truncate() : x}) ساعة' : '';
        Future<void> pick(bool isFrom) async {
          final d = await showDatePicker(context: ctx, initialDate: isFrom ? from : to, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) setS(() { if (isFrom) { from = d; } else { to = d; } });
        }
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * .82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                    IconButton.filledTonal(
                      tooltip: 'طباعة / حفظ PDF',
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                      onPressed: () {
                        exportTablePdf(
                          context: ctx,
                          title: 'تقرير أيام العامل: ${w.name}',
                          subtitle: 'من ${fmtDate(f)} إلى ${fmtDate(t)}',
                          headers: ['التاريخ', 'الموقف', 'مكان الحضور', 'القيمة', 'ملاحظات'],
                          widths: [70, 80, 80, 55, 110],
                          rows: [for (final r in recs) [fmtDate(r.date), r.status, r.loc.isEmpty ? '—' : r.loc, val(r).toStringAsFixed(2), [exTxt(r.xh), r.notes].where((x) => x.isNotEmpty).join(' — ')]],
                          totalsRow: ['الإجمالي', '$days يوم', '', total.toStringAsFixed(2), exTxt(xs)],
                          total: total.toStringAsFixed(2),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 19, color: Color(0xFF6D28D9)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.date_range, size: 15), label: Text('من ${fmtDate(f)}', style: const TextStyle(fontSize: 11.5)))),
                    const SizedBox(width: 6),
                    Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.date_range, size: 15), label: Text('إلى ${fmtDate(t)}', style: const TextStyle(fontSize: 11.5)))),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('$days يوم${xs > 0 ? ' + ${exTxt(xs)}' : ''} = ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF15803D))),
                ),
                Expanded(
                  child: recs.isEmpty
                      ? const Center(child: Text('لا توجد أيام مسجلة في هذه الفترة'))
                      : ListView.separated(
                          itemCount: recs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = recs[i];
                            final settled = r.settleId.isNotEmpty;
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text('${fmtDate(r.date)} • ${r.status} • ${r.loc.isEmpty ? '—' : r.loc}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              subtitle: Text([exTxt(r.xh), r.notes].where((x) => x.isNotEmpty).join(' — '), style: const TextStyle(fontSize: 11)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(val(r).toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                if (settled) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock, size: 14, color: Colors.green))
                                else IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit, size: 16, color: Color(0xFF1D4ED8)),
                                  onPressed: () async {
                                    if (await _editDay(ctx, w, r)) setS(() {});
                                  },
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _editDay(BuildContext ctx, Worker w, AttRec r) async {
    var status = r.status;
    var loc = r.loc;
    final xh = TextEditingController(text: r.xh > 0 ? _numStr(r.xh) : '');
    final notes = TextEditingController(text: r.notes);
    final locs = App.I.locs.toList();
    if (loc.isNotEmpty && !locs.contains(loc)) locs.add(loc);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
        title: Text('${w.name} — ${fmtDate(r.date)}', style: const TextStyle(fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: kStatuses.contains(status) ? status : '--',
              decoration: _dec('الموقف'),
              items: kStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s == '--' ? 'بدون تسجيل' : s, style: const TextStyle(fontSize: 12.5)))).toList(),
              onChanged: (v) => setD(() => status = v ?? '--'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: locs.contains(loc) ? loc : null,
              decoration: _dec('مكان الحضور'),
              items: locs.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12.5)))).toList(),
              onChanged: (v) => setD(() => loc = v ?? ''),
            ),
            if (kExtraStatuses.contains(status)) ...[
              const SizedBox(height: 8),
              TextField(controller: xh, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('إضافي (ساعة)')),
            ],
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: _dec('ملاحظات')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('حفظ')),
        ],
      )),
    );
    if (ok != true) return false;
    return _saveRec(r.date, {
      'wid': w.id,
      'status': status,
      'loc': loc.trim(),
      'xh': kExtraStatuses.contains(status) ? (double.tryParse(xh.text) ?? 0) : 0,
      'wage': r.wage > 0 ? r.wage : w.wage,
      'notes': notes.text.trim(),
    });
  }

  Future<void> _saveOne(Worker w) async {
    final c = _ctl[w.id]!;
    try {
      final rec = {
        'wid': w.id,
        'status': c.status,
        'loc': c.loc.trim(),
        'xh': kExtraStatuses.contains(c.status) ? (double.tryParse(c.xh) ?? 0) : 0,
        'wage': double.tryParse(c.wg) ?? 0,
        'notes': c.notes.trim(),
      };
      final res = await Api.auth('saveDay', [_dstr, [rec], true]) as Map;
      final fresh = (res['att'] as List).map((r) => AttRec.fromJson(r as Map)).toList();
      final app = App.I;
      final kept = app.att.where((r) => r.date != _dstr).toList()..addAll(fresh);
      final newLocs = (res['locs'] as List).map((l) => l.toString()).where((l) => !app.locs.contains(l)).toList();
      app.att..clear()..addAll(kept);
      app.locs.addAll(newLocs);
      c.wgLocked = true;
      app.notifyListeners();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ ${w.name}'), backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 1)));
      }
    } on SessionExpired {
      await _relogin();
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
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
  String wg;
  bool wgLocked = true; // أجر اليوم تلقائي ومغلق حتى الضغط عليه
  _RowCtl({required this.status, required this.loc, required this.xh, required this.notes, required this.wg});
}
