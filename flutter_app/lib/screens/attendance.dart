// شاشة تسجيل حضور اليوم (أو تاريخ سابق) — نفس منطق نسخة الويب
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

class AttendanceScreen extends StatefulWidget {
  final String? openWorkerId; // فتح موقف عامل مباشرة (من التسوية)
  final VoidCallback? onHome;
  const AttendanceScreen({super.key, this.openWorkerId, this.onHome});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _q = '';
  String _locF = ''; // فلتر مكان الحضور
  String _wkF = ''; // عامل محدد
  DateTime _date = DateTime.now();
  late Map<String, _RowCtl> _ctl; // wid -> عناصر التحكم
  bool _saving = false;
  String? _err;

  /// المواقف المتاحة: الموقفان الجديدان يُخفيان مع سكربت Google القديم
  List<String> get _sts => (App.I.srvVer > 0 && App.I.srvVer < 4) ? kStatuses.where((s) => s != kHalfStatus && s != kHoursStatus).toList() : kStatuses;

  String get _dstr =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _ctl = {};
    _locF = App.I.attLoc;
    App.I.attLoc = '';
    App.I.addListener(_onApp);
    _build();
    if (widget.openWorkerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final w = App.I.workers.where((x) => x.id == widget.openWorkerId).toList();
        if (w.isNotEmpty && mounted) _showDays(w.first);
      });
    }
  }

  @override
  void dispose() {
    App.I.removeListener(_onApp);
    super.dispose();
  }

  _RowCtl _mk(Worker w, AttRec? r) {
    final c = _RowCtl(
      status: r?.status ?? '--',
      loc: r?.loc ?? '',
      xh: r?.xh.toString() ?? '',
      notes: r?.notes ?? '',
      wg: _numStr((r?.wage ?? 0) > 0 ? r!.wage : w.wage),
    );
    c.base = c.sig();
    return c;
  }

  void _build() {
    final app = App.I;
    final byWid = <String, AttRec>{};
    for (final r in app.att.where((r) => r.date == _dstr)) {
      byWid[r.wid] = r;
    }
    _ctl = {for (final w in app.workers) w.id: _mk(w, byWid[w.id])};
    setState(() {});
  }

  /// عند وصول بيانات جديدة (من الويب أو جهاز آخر): تُحدَّث الصفوف التي لم يعدّلها المستخدم فقط
  void _onApp() {
    if (!mounted || _saving) return;
    final byWid = <String, AttRec>{};
    for (final r in App.I.att.where((r) => r.date == _dstr)) {
      byWid[r.wid] = r;
    }
    var changed = false;
    for (final w in App.I.workers) {
      final c = _ctl[w.id];
      if (c != null && c.sig() != c.base) continue; // المستخدم يعدّل هذا الصف الآن
      final n = _mk(w, byWid[w.id]);
      if (c == null || n.base != c.base) {
        _ctl[w.id] = n;
        changed = true;
      }
    }
    if (changed) setState(() {});
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
    // الحفظ الجزئي: يُرسل فقط العمال الذين تغيّر موقفهم هنا، فلا تُمحى تسجيلات الويب أو الأجهزة الأخرى
    final php = await Api.isPhp();
    final recs = <Map<String, dynamic>>[];
    _ctl.forEach((wid, c) {
      final empty = c.status == '--' && c.loc.trim().isEmpty;
      if (!php && c.sig() == c.base) return;
      if (empty) {
        if (!php) recs.add({'wid': wid, 'status': '--', 'loc': '', 'xh': 0, 'wage': 0, 'notes': ''});
        return;
      }
      recs.add({
          'wid': wid,
          'status': c.status,
          'loc': c.loc.trim(),
          'xh': usesXh(c.status) ? (double.tryParse(c.xh) ?? 0) : 0,
          'wage': double.tryParse(c.wg) ?? 0,
          'notes': c.notes.trim(),
        });
    });
    if (recs.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد تغييرات للحفظ')));
      return;
    }
    setState(() { _saving = true; _err = null; });
    try {
      final res = await Api.auth('saveDay', php ? [_dstr, recs] : [_dstr, recs, true]) as Map;
      final fresh = (res['att'] as List).map((r) => AttRec.fromJson(r as Map)).toList();
      // حدّث الحالة محليًا
      final app = App.I;
      final kept = app.att.where((r) => r.date != _dstr).toList()..addAll(fresh);
      final newLocs = (res['locs'] as List).map((l) => l.toString()).where((l) => !app.locs.contains(l)).toList();
      app.att..clear()..addAll(kept);
      app.locs.addAll(newLocs);
      _saving = false;
      if (mounted) _build();
      app.notifyListeners();
      final noLoc = recs.where((r) => r['status'] != '--' && '${r['loc']}'.trim().isEmpty).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ يوم ${fmtDate(_dstr)} (${recs.length} عامل) — المسجل في السيرفر: ${fresh.length}${noLoc > 0 ? '\nتنبيه: $noLoc عامل بدون مكان حضور — لن يُحتسب يومهم ولن يظهروا في الويب كحضور' : ''}'), backgroundColor: Colors.green.shade700),
        );
      }
    } on SessionExpired {
      await _relogin();
    } on ApiException catch (e) {
      setState(() => _err = e.message);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لم يتم الحفظ: ${e.message}'), backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 8)));
    } catch (e) {
      setState(() => _err = 'تعذر الحفظ: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لم يتم الحفظ: $e'), backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 8)));
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
    final locIds = _locF.isEmpty
        ? <String>{}
        : <String>{
            for (final w in all) if (w.loc == _locF) w.id,
            for (final r in app.att) if (r.loc == _locF) r.wid,
          };
    final workers = all
        .where((w) => (_locF.isEmpty || locIds.contains(w.id)) && (_wkF.isEmpty || w.id == _wkF) && (_q.isEmpty || txtMatch(_q, [w.name, w.card])))
        .toList();
    final nPresent = workers.where((w) => (_ctl[w.id]?.status ?? '--') != '--').length;
    final locs = <String>{...app.locs, ...app.workers.map((w) => w.loc).where((l) => l.isNotEmpty)}.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      body: Column(
        children: [
          // شريط التاريخ + الحفظ
          compactMaterial(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(fmtDate(_dstr), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 30),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 15),
                    label: const Text('حفظ اليوم'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(
              children: [
                if (widget.onHome != null)
                  IconButton(
                    tooltip: 'رجوع للرئيسية',
                    visualDensity: VisualDensity.compact,
                    onPressed: () { App.I.attLoc = ''; widget.onHome!(); },
                    icon: const Icon(Icons.home_outlined, size: 20, color: Color(0xFF6D28D9)),
                  ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: (_locF.isEmpty || locs.contains(_locF)) ? (_locF.isEmpty ? '' : _locF) : '',
                    decoration: _dec('فرز بمكان الحضور'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كل الأماكن', style: TextStyle(fontSize: 12))),
                      ...locs.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _locF = v ?? ''),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: all.any((w) => w.id == _wkF) ? _wkF : '',
                    decoration: _dec('عامل محدد'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كل العاملين', style: TextStyle(fontSize: 12))),
                      ...all.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _wkF = v ?? ''),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text.rich(TextSpan(style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), children: [
                TextSpan(text: 'عدد الكل = ${workers.length}', style: const TextStyle(color: Color(0xFF1D4ED8))),
                const TextSpan(text: '  /  '),
                TextSpan(text: 'عدد الحضور = $nPresent', style: const TextStyle(color: Color(0xFF15803D))),
                const TextSpan(text: '  /  '),
                TextSpan(text: 'بدون موقف = ${workers.length - nPresent}', style: const TextStyle(color: Color(0xFFDC2626))),
              ])),
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
            padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
            child: Row(
              children: [
                Expanded(child: SearchBox(hint: 'بحث عن عامل بالاسم أو البطاقة...', value: _q, onChanged: (v) => setState(() => _q = v))),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: miniIconBtn(Icons.picture_as_pdf, const Color(0xFF6D28D9), _pdf, tip: 'PDF للطباعة والإرسال'),
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
    var days = 0.0;
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
      final val = r.counts ? r.valueOf(w) : 0.0;
      final d = r2(val - (r.settleId.isNotEmpty ? r.paidAmt : 0));
      amt += d;
      if (d > 0.005) {
        days += r.daysOf(w);
        ot += r.settleId.isNotEmpty ? d : r.otOf(w);
        hrsTotal += r.settleId.isNotEmpty ? (h > 0 ? d / h : 0.0) : r.otHours;
      }
    }
    final wgRaw = double.tryParse(c.wg) ?? 0;
    final wg = wgRaw > 0 ? wgRaw : w.wage;
    final counts = c.loc.trim().isNotEmpty;
    final xRaw = double.tryParse(c.xh) ?? 0;
    final xh = kExtraStatuses.contains(c.status) ? xRaw : 0.0;
    final liveOt = xh * (wg / hrs);
    final liveBase = c.status == kHalfStatus ? r2(wg / 2) : (c.status == kHoursStatus ? r2(xRaw * (wg / hrs)) : wg);
    final liveDays = c.status == kHalfStatus ? 0.5 : (c.status == kHoursStatus ? r2(xRaw / hrs) : 1.0);
    final settled = saved != null && saved.settleId.isNotEmpty;
    final d = r2((counts ? liveBase + liveOt : 0.0) - (settled ? saved!.paidAmt : 0));
    amt += d;
    if (d > 0.005) {
      days += liveDays;
      ot += settled ? d : liveOt;
      hrsTotal += settled ? (wg > 0 ? d / (wg / hrs) : 0.0) : xh;
    }
    final hr0 = hrsTotal;
    return ['${dn(r2(days))} يوم', hr0 > 0 ? '+ إضافي (${_numStr(r2(hr0))}) ساعة' : '', '= ${r2(amt < 0 ? 0 : amt)}'];
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
      final ex = (usesXh(c.status) && xhN > 0) ? '${c.status == kHoursStatus ? 'حضور' : 'إضافي'} (${_numStr(xhN)}) ساعة' : '';
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
    final isExtra = usesXh(c.status);
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
                c.wgLocked
                    ? InkWell(
                        onTap: isSettled ? null : () => setState(() => c.wgLocked = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                          child: Text(c.wg, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF92400E), fontSize: 11.5)),
                        ),
                      )
                    : SizedBox(
                        width: 62,
                        child: TextField(
                          autofocus: true,
                          controller: TextEditingController(text: c.wg)..selection = TextSelection(baseOffset: 0, extentOffset: c.wg.length),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _dec(null),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => setState(() => c.wg = v),
                          onSubmitted: (_) => setState(() { if ((double.tryParse(c.wg) ?? 0) <= 0) c.wg = _numStr(w.wage); c.wgLocked = true; }),
                          onTapOutside: (_) => setState(() { if ((double.tryParse(c.wg) ?? 0) <= 0) c.wg = _numStr(w.wage); c.wgLocked = true; }),
                        ),
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
                    value: _sts.contains(c.status) ? c.status : '--',
                    decoration: _dec(null),
                    items: _sts.map((s) => DropdownMenuItem(value: s, child: Text(s == '--' ? 'بدون تسجيل' : s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) {
                      setState(() { final prev = c.status; c.status = v ?? '--'; if (!usesXh(c.status) || (prev == kHoursStatus) != (c.status == kHoursStatus)) c.xh = ''; if (c.status == '--') c.loc = ''; });
                      if (c.status != '--' && c.loc.trim().isEmpty) {
                        // مكان تلقائي: المكان الثابت للعامل، وإلا المكان المحدد في الفلتر، وإلا المكان الوحيد المسجل
                        final auto = w.loc.isNotEmpty ? w.loc : (_locF.isNotEmpty ? _locF : (locs.length == 1 ? locs.first : ''));
                        if (auto.isNotEmpty) setState(() => c.loc = auto);
                      }
                    },
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
                      onChanged: (v) {
                        setState(() => c.loc = v ?? '');
                      },
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
                        decoration: _dec(c.status == kHoursStatus ? 'عدد الساعات' : 'إضافي (ساعة)'),
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

  Future<void> _showDays(Worker w) async {
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, 1);
    var to = now;
    final pending = <String, Map<String, dynamic>>{};
    var savingPosition = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final f = _ds(from), t = _ds(to);
        final recs = App.I.att.where((r) => r.wid == w.id && r.date.compareTo(f) >= 0 && r.date.compareTo(t) <= 0 && r.counts).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final hrs = w.hours <= 0 ? 8.0 : w.hours;
        double val(AttRec r) => r.counts ? r.valueOf(w) : 0.0;
        final total = r2(recs.fold<double>(0, (s, r) => s + val(r)));
        final days = r2(recs.where((r) => r.counts).fold<double>(0, (s, r) => s + r.daysOf(w)));
        final xs = recs.fold<double>(0, (s, r) => s + r.otHours);
        String xTxt(String st, double x) => x > 0 ? '${st == kHoursStatus ? 'حضور' : 'إضافي'} (${x == x.truncateToDouble() ? x.truncate() : x}) ساعة' : '';
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
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                      onPressed: () {
                        exportTablePdf(
                          context: ctx,
                          title: 'تقرير أيام العامل: ${w.name}',
                          subtitle: 'من ${fmtDate(f)} إلى ${fmtDate(t)}',
                          headers: ['التاريخ', 'الموقف', 'مكان الحضور', 'القيمة', 'ملاحظات'],
                          widths: [70, 80, 80, 55, 110],
                          rows: [for (final r in recs) [fmtDate(r.date), r.status, r.loc.isEmpty ? '—' : r.loc, val(r).toStringAsFixed(2), [xTxt(r.status, r.xh), r.notes].where((x) => x.isNotEmpty).join(' — ')]],
                          totalsRow: ['الإجمالي', '${dn(days)} يوم', '', total.toStringAsFixed(2), exTxt(xs)],
                          total: total.toStringAsFixed(2),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFF6D28D9)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.date_range, size: 14), label: Text('من ${fmtDate(f)}', style: const TextStyle(fontSize: 11)))),
                    const SizedBox(width: 6),
                    Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.date_range, size: 15), label: Text('إلى ${fmtDate(t)}', style: const TextStyle(fontSize: 11.5)))),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('${dn(days)} يوم${xs > 0 ? ' + ${exTxt(xs)}' : ''} = ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF15803D))),
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
                            final edit = pending[r.date];
                            final shownStatus = edit?['status'] as String? ?? r.status;
                            final shownLoc = edit?['loc'] as String? ?? r.loc;
                            final shownXh = (edit?['xh'] as num?)?.toDouble() ?? r.xh;
                            final shownNotes = edit?['notes'] as String? ?? r.notes;
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text('${fmtDate(r.date)} • $shownStatus • ${shownLoc.isEmpty ? '—' : shownLoc}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              subtitle: Text([xTxt(shownStatus, shownXh), shownNotes, if (edit != null) 'تعديل غير محفوظ'].where((x) => x.isNotEmpty).join(' — '), style: const TextStyle(fontSize: 11)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(val(r).toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                if (settled) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock, size: 14, color: Colors.green))
                                else IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit, size: 16, color: Color(0xFF1D4ED8)),
                                  onPressed: () async {
                                    final change = await _editDay(ctx, w, r, edit);
                                    if (change != null) setS(() => pending[r.date] = change);
                                  },
                                ),
                              ]),
                            );
                          },
                        ),
                ),
                if (pending.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: savingPosition ? null : () async {
                        final changeCount = pending.length;
                        setS(() => savingPosition = true);
                        try {
                          await _saveSituation(pending);
                          pending.clear();
                          setS(() {});
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم حفظ الموقف ($changeCount تعديل)'), backgroundColor: Colors.green.shade700),
                            );
                          }
                        } on SessionExpired {
                          await _relogin();
                        } on ApiException catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
                        } finally {
                          if (mounted) setS(() => savingPosition = false);
                        }
                      },
                      icon: savingPosition
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 16),
                      label: Text(savingPosition ? 'جاري حفظ الموقف...' : 'حفظ الموقف (${pending.length})'),
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

  Future<Map<String, dynamic>?> _editDay(BuildContext ctx, Worker w, AttRec r, Map<String, dynamic>? previous) async {
    var status = previous?['status'] as String? ?? r.status;
    var loc = previous?['loc'] as String? ?? r.loc;
    final savedXh = (previous?['xh'] as num?)?.toDouble() ?? r.xh;
    final xh = TextEditingController(text: savedXh > 0 ? _numStr(savedXh) : '');
    final notes = TextEditingController(text: previous?['notes'] as String? ?? r.notes);
    final locs = App.I.locs.toList();
    if (loc.isNotEmpty && !locs.contains(loc)) locs.add(loc);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
        title: Text('${w.name} — ${fmtDate(r.date)}', style: const TextStyle(fontSize: 14)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: _sts.contains(status) ? status : '--',
              decoration: _dec('الموقف'),
              items: _sts.map((s) => DropdownMenuItem(value: s, child: Text(s == '--' ? 'بدون تسجيل' : s, style: const TextStyle(fontSize: 12.5)))).toList(),
              onChanged: (v) => setD(() { final prev = status; status = v ?? '--'; if (status == '--') loc = ''; if (!usesXh(status) || (prev == kHoursStatus) != (status == kHoursStatus)) xh.text = ''; }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: locs.contains(loc) ? loc : null,
              decoration: _dec('مكان الحضور'),
              items: locs.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12.5)))).toList(),
              onChanged: (v) => setD(() => loc = v ?? ''),
            ),
            if (usesXh(status)) ...[
              const SizedBox(height: 8),
              TextField(controller: xh, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec(status == kHoursStatus ? 'عدد الساعات' : 'إضافي (ساعة)')),
            ],
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: _dec('ملاحظات')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('إضافة للموقف')),
        ],
      )),
    );
    if (ok != true) return null;
    return {
      'wid': w.id,
      'status': status,
      'loc': loc.trim(),
      'xh': usesXh(status) ? (double.tryParse(xh.text) ?? 0) : 0,
      'wage': r.wage > 0 ? r.wage : w.wage,
      'notes': notes.text.trim(),
    };
  }

  Future<void> _saveSituation(Map<String, Map<String, dynamic>> changes) async {
    final app = App.I;
    final php = await Api.isPhp();
    for (final entry in changes.entries) {
      final date = entry.key;
      final records = app.att.where((r) => r.date == date).map((r) => <String, dynamic>{
        'wid': r.wid,
        'status': r.status,
        'loc': r.loc,
        'wage': r.wage,
        'xh': r.xh,
        'notes': r.notes,
      }).toList();
      final index = records.indexWhere((r) => r['wid'] == entry.value['wid']);
      if (index == -1) {
        records.add(entry.value);
      } else {
        records[index] = entry.value;
      }
      final res = await Api.auth('saveDay', php ? [date, records] : [date, [entry.value], true]) as Map;
      final fresh = (res['att'] as List).map((r) => AttRec.fromJson(r as Map)).toList();
      final kept = app.att.where((r) => r.date != date).toList()..addAll(fresh);
      final newLocs = (res['locs'] as List).map((l) => l.toString()).where((l) => !app.locs.contains(l)).toList();
      app.att..clear()..addAll(kept);
      app.locs.addAll(newLocs);
    }
    app.notifyListeners();
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
  String base = ''; // بصمة الصف عند التحميل/آخر حفظ (لمعرفة ما تغيّر)
  String sig() => '$status|${loc.trim()}|$xh|$wg|${notes.trim()}';
  _RowCtl({required this.status, required this.loc, required this.xh, required this.notes, required this.wg});
}
