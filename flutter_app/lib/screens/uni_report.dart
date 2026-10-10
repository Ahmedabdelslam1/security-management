// تقرير شامل: يجمع دفتر البوابة والإجراءات اليومية في قائمة واحدة (بحث بالسائق / المندوب / السيارة / التاريخ)
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

const Color _kGate = Color(0xFF6D28D9);
const Color _kProc = Color(0xFFC2410C);

String _ds(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _s(Map r, String k) => '${r[k] ?? ''}';

class _Item {
  final bool gate;
  final Map r;
  _Item(this.gate, this.r);
  String get screen => gate ? 'دفتر البوابة' : 'الإجراءات اليومية';
  String get act => gate ? _s(r, 'action') : _s(r, 'ptype');
  String get date => _s(r, 'date');
  int get seq => int.tryParse(_s(r, 'seq')) ?? 0;
}

class UniReportScreen extends StatefulWidget {
  final String initialQuery;
  final String kind; // plate | driver | rep | ''  (مطابقة تامة عند الفتح من رابط)
  const UniReportScreen({super.key, this.initialQuery = '', this.kind = ''});
  @override
  State<UniReportScreen> createState() => _UniReportScreenState();
}

class _UniReportScreenState extends State<UniReportScreen> {
  List<_Item> _all = [];
  bool _busy = true;
  String? _err;
  late String _q = widget.initialQuery;
  late String _kind = widget.kind;
  DateTime? _from, _to;
  final _qc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _qc.text = _q;
    _load();
  }

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _busy = true; _err = null; });
    final out = <_Item>[];
    try {
      if (App.I.user?.can('gate') ?? false) {
        try {
          final r = await Api.auth('listGate') as List;
          out.addAll(r.map((x) => _Item(true, x as Map)));
        } on SessionExpired {
          rethrow;
        } catch (_) {}
      }
      if (App.I.user?.can('procs') ?? false) {
        try {
          final r = await Api.auth('listProcs') as List;
          out.addAll(r.map((x) => _Item(false, x as Map)));
        } on SessionExpired {
          rethrow;
        } catch (_) {}
      }
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }
    if (mounted) setState(() { _all = out; _busy = false; if (out.isEmpty) _err = 'لا توجد بيانات أو لا تملك صلاحية الشاشتين'; });
  }

  List<_Item> get _rows {
    final f = _from == null ? '' : _ds(_from!);
    final t = _to == null ? '' : _ds(_to!);
    final q = _q.trim();
    final rs = _all.where((i) {
      if (f.isNotEmpty && i.date.compareTo(f) < 0) return false;
      if (t.isNotEmpty && i.date.compareTo(t) > 0) return false;
      if (q.isEmpty) return true;
      if (_kind.isNotEmpty) return normAr(_s(i.r, _kind).trim()) == normAr(q);
      return txtMatchAr(q, [
        _s(i.r, 'entryNo'), '${i.seq}', _s(i.r, 'weekday'), fmtDate(i.date), i.date, i.act,
        _s(i.r, 'plate'), _s(i.r, 'driver'), _s(i.r, 'rep'), _s(i.r, 'statement'), _s(i.r, 'notes'), i.screen,
      ]);
    }).toList();
    rs.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      if (a.gate != b.gate) return a.gate ? -1 : 1;
      return a.seq.compareTo(b.seq);
    });
    return rs;
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => isFrom ? _from = d : _to = d);
  }

  void _pdf(List<_Item> rs) {
    exportTablePdf(
      context: context,
      title: 'تقرير شامل — دفتر البوابة والإجراءات اليومية',
      subtitle: [
        if (_q.trim().isNotEmpty) 'بحث: ${_q.trim()}',
        if (_from != null) 'من ${fmtDate(_ds(_from!))}',
        if (_to != null) 'إلى ${fmtDate(_ds(_to!))}',
      ].join('  '),
      headers: const ['الشاشة', 'رقم القيد', 'م', 'التاريخ', 'اليوم', 'الوقت', 'الإجراء', 'رقم السيارة', 'السائق', 'المندوب / الموظف', 'البيان', 'ملاحظات'],
      widths: const [1.5, 1.6, 0.6, 1.3, 1.1, 0.9, 0.9, 1.2, 1.6, 1.6, 3, 1.6],
      landscape: true,
      rows: [
        for (final i in rs)
          [i.screen, _s(i.r, 'entryNo'), '${i.seq}', fmtDate(i.date), _s(i.r, 'weekday'), i.gate ? _s(i.r, 'time') : '', i.act, _s(i.r, 'plate'), _s(i.r, 'driver'), _s(i.r, 'rep'), _s(i.r, 'statement'), _s(i.r, 'notes')]
      ],
      total: '${rs.length}',
      totalLabel: 'عدد البنود',
    );
  }

  Widget _card(_Item i) {
    final col = i.gate ? _kGate : _kProc;
    final plate = _s(i.r, 'plate'), driver = _s(i.r, 'driver'), rep = _s(i.r, 'rep'), st = _s(i.r, 'statement'), notes = _s(i.r, 'notes');
    final time = i.gate ? _s(i.r, 'time') : '';
    return GlowCard(
      glow: col,
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: col.withOpacity(.3))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(20)),
                  child: Text(i.screen, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('قيد ${_s(i.r, 'entryNo')}  •  م ${i.seq}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: col))),
                if (i.act.isNotEmpty && i.act != '--')
                  Text(i.act, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: i.act == 'دخول' ? const Color(0xFF15803D) : const Color(0xFFEA580C))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('${_s(i.r, 'weekday')}  ${fmtDate(i.date)}${time.isEmpty ? '' : '  •  $time'}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (plate.isNotEmpty) Text('سيارة $plate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: col)),
                if (driver.isNotEmpty) Text('السائق $driver', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8))),
                if (rep.isNotEmpty) Text('المندوب $rep', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F766E))),
              ],
            ),
            if (st.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: col.withOpacity(.07), borderRadius: BorderRadius.circular(8)),
                child: Text(st, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.35, color: Color(0xFF1E293B))),
              ),
            if (notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('ملاحظات: $notes', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = _rows;
    final g = rs.where((x) => x.gate).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      appBar: AppBar(
        title: const Text('تقرير شامل', style: TextStyle(fontSize: 15)),
        actions: [
          IconButton(tooltip: 'طباعة / PDF', onPressed: rs.isEmpty ? null : () => _pdf(rs), icon: const Icon(Icons.picture_as_pdf)),
          IconButton(tooltip: 'تحديث', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          compactMaterial(
            color: Colors.white,
            elevation: 1,
            child: Column(
              children: [
                SearchBox(
                  hint: 'سائق / مندوب / رقم سيارة / تاريخ / أي كلمة...',
                  value: _q,
                  onChanged: (v) => setState(() { _q = v; _kind = ''; }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        MiniChipButton(icon: Icons.date_range, label: _from == null ? 'من' : fmtDate(_ds(_from!)), onTap: () => _pick(true), filled: _from != null),
                        const SizedBox(width: 5),
                        MiniChipButton(icon: Icons.date_range, label: _to == null ? 'إلى' : fmtDate(_ds(_to!)), onTap: () => _pick(false), filled: _to != null),
                        if (_from != null || _to != null) ...[
                          const SizedBox(width: 5),
                          MiniChipButton(icon: Icons.close, label: 'مسح', color: Colors.red.shade700, onTap: () => setState(() { _from = null; _to = null; })),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Text('عدد البنود: ${rs.length} • دفتر البوابة $g • الإجراءات اليومية ${rs.length - g}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF475569))),
          ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : rs.isEmpty
                    ? Center(child: Text(_err ?? 'لا توجد بنود مطابقة'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
                        itemCount: rs.length,
                        itemBuilder: (_, i) => _card(rs[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
