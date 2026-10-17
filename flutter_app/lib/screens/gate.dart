// دفتر البوابة: سجلات دخول/خروج السيارات + مرفقات (صور وPDF) + تقارير بالسيارة/السائق/المندوب
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';
import 'uni_report.dart';

const List<String> kGateActions = ['--', 'دخول', 'خروج'];
const Color _kGatePurple = Color(0xFF6D28D9);

String _ds(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _s(Map r, String k) => '${r[k] ?? ''}';
int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

Color _actionColor(String a) {
  if (a == 'دخول') return const Color(0xFF15803D);
  if (a == 'خروج') return const Color(0xFFEA580C);
  return const Color(0xFF64748B);
}

String _mimeOf(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  List<Map> _rows = [];
  bool _loaded = false;
  bool _busy = false;
  String _q = '';
  String _action = ''; // '' = الكل
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String m, [bool err = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: err ? Colors.red.shade700 : Colors.green.shade700));
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      final r = await Api.auth('listGate');
      final list = (r as List).map((x) => x as Map).toList();
      if (mounted) setState(() { _rows = list; _loaded = true; });
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on ApiException catch (e) {
      _msg(e.message, true);
    } catch (_) {
      _msg('تعذر تحميل السجلات', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map> get _filtered {
    final f = _from == null ? '' : _ds(_from!);
    final t = _to == null ? '' : _ds(_to!);
    return _rows.where((g) {
      final d = _s(g, 'date');
      if (f.isNotEmpty && d.compareTo(f) < 0) return false;
      if (t.isNotEmpty && d.compareTo(t) > 0) return false;
      if (_action.isNotEmpty && _s(g, 'action') != _action) return false;
      if (_q.trim().isEmpty) return true;
      return txtMatchAr(_q, [
        _s(g, 'seq'), _s(g, 'entryNo'), _s(g, 'weekday'), d, fmtDate(d), _s(g, 'time'), _s(g, 'action'), _s(g, 'plate'),
        _s(g, 'driver'), _s(g, 'rep'), _s(g, 'statement'), _s(g, 'notes'), _s(g, 'managers'), _s(g, 'host'),
      ]);
    }).toList();
  }

  static const _pdfHeaders = ['م', 'اليوم', 'التاريخ', 'الوقت', 'الإجراء', 'رقم السيارة', 'السائق', 'المندوب / الموظف', 'البيان', 'حضور مديرين', 'المضيف', 'ملاحظات', 'رقم القيد'];
  static const _pdfWidths = <double>[0.5, 1, 1.2, 0.8, 0.8, 1.3, 1.4, 1.4, 2.4, 1.2, 1.2, 1.4, 1.4];

  List<List<String>> _pdfRows(List<Map> rs) => [
        for (final g in rs)
          [
            _s(g, 'seq'), _s(g, 'weekday'), fmtDate(_s(g, 'date')), _s(g, 'time'), _s(g, 'action'), _s(g, 'plate'),
            _s(g, 'driver'), _s(g, 'rep'), _s(g, 'statement'), _s(g, 'managers'), _s(g, 'host'), _s(g, 'notes'), _s(g, 'entryNo'),
          ]
      ];

  List<Map> _sorted(List<Map> rs) {
    final out = rs.toList();
    out.sort((a, b) {
      final c = _s(a, 'date').compareTo(_s(b, 'date'));
      if (c != 0) return c;
      return _int(a['seq']).compareTo(_int(b['seq']));
    });
    return out;
  }

  void _pdf() {
    final rs = _sorted(_filtered);
    exportTablePdf(
      context: context,
      title: 'دفتر البوابة',
      subtitle: '${_from == null ? '' : 'من ${fmtDate(_ds(_from!))} '}${_to == null ? '' : 'إلى ${fmtDate(_ds(_to!))}'}${_action.isEmpty ? '' : ' — $_action'}',
      headers: _pdfHeaders,
      widths: _pdfWidths,
      rows: _pdfRows(rs),
      landscape: true,
      total: '${rs.length}',
      totalLabel: 'عدد السجلات',
    );
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() { if (isFrom) { _from = d; } else { _to = d; } });
  }

  // ===== المرفقات =====
  void _viewFiles(Map g) {
    final count = _int(g['imgCount']);
    if (count == 0) {
      _msg('لا مرفقات لهذا السجل');
      return;
    }
    final types = (g['imgTypes'] is List) ? (g['imgTypes'] as List).map((x) => '$x').toList() : <String>[];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GateFilesPage(id: g['id'], count: count, types: types, title: 'مرفقات ${_s(g, 'plate')}'),
    ));
  }

  // ===== حذف / تعديل =====
  Future<bool> _delete(Map g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف سجل ${_s(g, 'plate')} بتاريخ ${fmtDate(_s(g, 'date'))}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(dctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await Api.auth('deleteGate', [g['id']]);
      await _load();
      _msg('تم الحذف');
      return true;
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on ApiException catch (e) {
      _msg(e.message, true);
    } catch (_) {
      _msg('تعذر الحذف', true);
    }
    return false;
  }

  Future<bool> _edit(Map? g) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _GateForm(existing: g, all: _rows),
    );
    if (saved == true) {
      await _load();
      return true;
    }
    return false;
  }

  // ===== تقرير لسيارة / سائق / مندوب =====
  void _report(String kind, Map g) {
    final val = _s(g, kind);
    if (val.trim().isEmpty) return;
    DateTime? from;
    DateTime? to;
    final title = '${kind == 'plate' ? 'تقرير السيارة' : kind == 'driver' ? 'تقرير السائق' : 'تقرير المندوب / الموظف'} $val';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final f = from == null ? '' : _ds(from!);
        final t = to == null ? '' : _ds(to!);
        final rs = _sorted(_rows.where((x) {
          if (normAr(_s(x, kind).trim()) != normAr(val.trim())) return false;
          final d = _s(x, 'date');
          if (f.isNotEmpty && d.compareTo(f) < 0) return false;
          if (t.isNotEmpty && d.compareTo(t) > 0) return false;
          return true;
        }).toList());
        Future<void> pickD(bool isFrom) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: (isFrom ? from : to) ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            locale: const Locale('ar'),
          );
          if (d != null) setS(() { if (isFrom) { from = d; } else { to = d; } });
        }

        return SizedBox(
          height: MediaQuery.of(ctx).size.height * .85,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: _kGatePurple))),
                    miniIconBtn(Icons.picture_as_pdf, _kGatePurple, rs.isEmpty
                        ? null
                        : () => exportTablePdf(
                              context: ctx,
                              title: title,
                              subtitle: '${from == null ? '' : 'من ${fmtDate(f)} '}${to == null ? '' : 'إلى ${fmtDate(t)}'}',
                              headers: _pdfHeaders,
                              widths: _pdfWidths,
                              rows: _pdfRows(rs),
                              landscape: true,
                              total: '${rs.length}',
                              totalLabel: 'عدد السجلات',
                            ), tip: 'طباعة / PDF'),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      MiniChipButton(icon: Icons.date_range, label: from == null ? 'من: الكل' : 'من ${fmtDate(f)}', onTap: () => pickD(true), filled: from != null),
                      const SizedBox(width: 6),
                      MiniChipButton(icon: Icons.date_range, label: to == null ? 'إلى: الكل' : 'إلى ${fmtDate(t)}', onTap: () => pickD(false), filled: to != null),
                      const SizedBox(width: 6),
                      MiniChipButton(icon: Icons.all_inclusive, label: 'كل الأيام', color: const Color(0xFF64748B), onTap: () => setS(() { from = null; to = null; })),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('عدد السجلات: ${rs.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Expanded(
                  child: rs.isEmpty
                      ? const Center(child: Text('لا توجد سجلات في الفترة'))
                      : ListView(
                          children: [
                            for (final g in rs)
                              _card(g, links: false, onChanged: () => setS(() {})),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _link(String kind, Map g, Color col, {required bool links, double size = 12.5}) {
    final v = _s(g, kind).trim();
    if (v.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: col);
    if (!links) return Text(v, style: style);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UniReportScreen(initialQuery: v, kind: kind))),
      child: Text(v, style: style.copyWith(decoration: TextDecoration.underline, decorationColor: col.withOpacity(.4))),
    );
  }

  Widget _labeled(String label, Widget w) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
          w,
        ],
      );

  Widget _card(Map g, {bool links = true, VoidCallback? onChanged}) {
    final plate = _s(g, 'plate');
    final col = workerColor(plate.isEmpty ? _s(g, 'driver') + _s(g, 'rep') : plate);
    final action = _s(g, 'action');
    final ac = _actionColor(action);
    final entry = _s(g, 'entryNo').isNotEmpty ? _s(g, 'entryNo') : _s(g, 'seq');
    final imgs = _int(g['imgCount']);
    final statement = _s(g, 'statement');
    final notes = _s(g, 'notes');
    final managers = _s(g, 'managers');
    final host = _s(g, 'host');
    final time = _s(g, 'time');
    final wd = _s(g, 'weekday');
    return SlideIn(
      child: GlowCard(
        glow: col,
        margin: const EdgeInsets.only(bottom: 4),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: col.withOpacity(.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                    child: const Icon(Icons.directions_car, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('م ${_s(g, 'seq')}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: col)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(color: ac.withOpacity(.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: ac.withOpacity(.5))),
                    child: Text(action.isEmpty ? '--' : action, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ac)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '${wd.isEmpty ? '' : '$wd  '}${fmtDate(_s(g, 'date'))}${time.isEmpty ? '' : '  •  $time'}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (plate.isNotEmpty) _labeled('سيارة', _link('plate', g, col, links: links, size: 14)),
                  if (_s(g, 'driver').isNotEmpty) _labeled('السائق', _link('driver', g, const Color(0xFF1D4ED8), links: links)),
                  if (_s(g, 'rep').isNotEmpty) _labeled('المندوب', _link('rep', g, const Color(0xFF0F766E), links: links)),
                ],
              ),
              if (statement.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: col.withOpacity(.07), borderRadius: BorderRadius.circular(8)),
                  child: Text(statement, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3, color: Color(0xFF1E293B))),
                ),
              if (managers.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 3), child: Text('حضور مديرين: $managers', style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C3AED), fontWeight: FontWeight.w700))),
              if (host.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text('المضيف: $host', style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700))),
              if (notes.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text('ملاحظات: $notes', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))),
              const SizedBox(height: 1),
              Row(
                children: [
                  if (imgs > 0)
                    InkWell(
                      onTap: () => _viewFiles(g),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attach_file, size: 13, color: _kGatePurple),
                            Text('$imgs', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kGatePurple)),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text('قيد $entry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: col)),
                  const SizedBox(width: 8),
                  miniIconBtn(Icons.edit, const Color(0xFF1D4ED8), () async {
                    final ok = await _edit(g);
                    if (ok && onChanged != null) onChanged();
                  }, tip: 'تعديل'),
                  const SizedBox(width: 6),
                  miniIconBtn(Icons.delete_outline, Colors.red.shade700, () async {
                    final ok = await _delete(g);
                    if (ok && onChanged != null) onChanged();
                  }, tip: 'حذف'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = _filtered;
    final inN = rs.where((g) => _s(g, 'action') == 'دخول').length;
    final outN = rs.where((g) => _s(g, 'action') == 'خروج').length;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('سجل جديد', style: TextStyle(fontSize: 13)),
      ),
      body: Column(
        children: [
          compactMaterial(
            color: Colors.white,
            elevation: 1,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SearchBox(hint: 'بحث في كل الحقول...', value: _q, onChanged: (v) => setState(() => _q = v))),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: miniIconBtn(Icons.manage_search, const Color(0xFF0F766E), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UniReportScreen())), tip: 'تقرير شامل (البوابة + الإجراءات)'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      child: miniIconBtn(Icons.picture_as_pdf, _kGatePurple, _loaded ? _pdf : null, tip: 'طباعة / PDF'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                      child: miniIconBtn(Icons.refresh, const Color(0xFF0369A1), _busy ? null : _load, tip: 'تحديث'),
                    ),
                  ],
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
                        const SizedBox(width: 10),
                        for (final a in const ['', 'دخول', 'خروج'])
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 5),
                            child: MiniChipButton(
                              label: a.isEmpty ? 'الكل' : a,
                              color: a.isEmpty ? _kGatePurple : _actionColor(a),
                              filled: _action == a,
                              onTap: () => setState(() => _action = a),
                            ),
                          ),
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
            child: Text('عدد السجلات: ${rs.length} • دخول $inN • خروج $outN', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF475569))),
          ),
          Expanded(
            child: _busy && !_loaded
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: rs.isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.all(30),
                              child: Center(child: Text(_rows.isEmpty ? 'لا سجلات بعد — اضغط "سجل جديد"' : 'لا نتائج مطابقة')),
                            ),
                          ])
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
                            itemCount: rs.length,
                            itemBuilder: (_, i) => _card(rs[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/* ===================== عارض المرفقات ===================== */
class _GateFilesPage extends StatefulWidget {
  final dynamic id;
  final int count;
  final List<String> types;
  final String title;
  const _GateFilesPage({required this.id, required this.count, required this.types, required this.title});
  @override
  State<_GateFilesPage> createState() => _GateFilesPageState();
}

class _GateFile {
  Uint8List? bytes;
  bool pdf = false;
  bool failed = false;
  bool loaded = false;
}

class _GateFilesPageState extends State<_GateFilesPage> {
  late final List<_GateFile> _files;

  @override
  void initState() {
    super.initState();
    _files = List.generate(widget.count, (_) => _GateFile());
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (var i = 0; i < widget.count; i++) {
      final f = _files[i];
      try {
        final d = await Api.auth('getGateImage', [widget.id, i]);
        if (d is String && d.isNotEmpty) {
          f.pdf = d.startsWith('data:application/pdf') || (i < widget.types.length && widget.types[i] == 'pdf');
          f.bytes = base64Decode(d.split(',').last);
        } else {
          f.failed = true;
        }
      } catch (_) {
        f.failed = true;
      }
      f.loaded = true;
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _sharePdf(_GateFile f, int i) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gate-${DateTime.now().millisecondsSinceEpoch}-${i + 1}.pdf');
      await file.writeAsBytes(f.bytes!);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الملف')));
    }
  }

  Widget _item(_GateFile f, int i) {
    if (!f.loaded) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (f.failed || f.bytes == null) {
      return const SizedBox(height: 60, child: Center(child: Text('تعذر تحميل المرفق')));
    }
    if (f.pdf) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: Color(0xFFB91C1C), size: 30),
            const SizedBox(width: 10),
            Expanded(child: Text('ملف PDF ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
            FilledButton.icon(
              onPressed: () => _sharePdf(f, i),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('فتح / مشاركة', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Image.memory(
        f.bytes!,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Text('تعذر عرض الصورة'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 14))),
      body: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _files.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _item(_files[i], i),
        ),
      ),
    );
  }
}

/* ===================== نموذج الإضافة / التعديل ===================== */
class _NewAtt {
  final String data;
  final bool pdf;
  final Uint8List bytes;
  _NewAtt(this.data, this.pdf, this.bytes);
}

class _GateForm extends StatefulWidget {
  final Map? existing;
  final List<Map> all;
  const _GateForm({this.existing, required this.all});
  @override
  State<_GateForm> createState() => _GateFormState();
}

class _GateFormState extends State<_GateForm> {
  late DateTime _date;
  late String _action;
  final _time = TextEditingController();
  final _plate = TextEditingController();
  final _plateFocus = FocusNode();
  final _driver = TextEditingController();
  final _rep = TextEditingController();
  final _statement = TextEditingController();
  final _notes = TextEditingController();
  final _managers = TextEditingController();
  final _host = TextEditingController();
  final _page = TextEditingController();
  final _line = TextEditingController();
  final List<_NewAtt> _newAtts = [];
  final Set<int> _remove = {};
  final Map<int, Uint8List> _oldThumbs = {};
  List<String> _oldTypes = [];
  int _keepCount = 0;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g != null) {
      _date = DateTime.tryParse(_s(g, 'date')) ?? DateTime.now();
      _time.text = _s(g, 'time');
      _action = kGateActions.contains(_s(g, 'action')) ? _s(g, 'action') : '--';
      _plate.text = _s(g, 'plate');
      _driver.text = _s(g, 'driver');
      _rep.text = _s(g, 'rep');
      _statement.text = _s(g, 'statement');
      _notes.text = _s(g, 'notes');
      _managers.text = _s(g, 'managers');
      _host.text = _s(g, 'host');
      final pg = _int(g['page']);
      final ln = _int(g['line']);
      _page.text = pg > 0 ? '$pg' : '';
      _line.text = ln > 0 ? '$ln' : '';
      _keepCount = _int(g['imgCount']);
      _oldTypes = (g['imgTypes'] is List) ? (g['imgTypes'] as List).map((x) => '$x').toList() : <String>[];
      _loadOldThumbs(g['id']);
    } else {
      _date = DateTime.now();
      _action = '--';
      final n = TimeOfDay.now();
      _time.text = _fmtTime(n);
    }
  }

  @override
  void dispose() {
    _time.dispose();
    _plate.dispose();
    _plateFocus.dispose();
    _driver.dispose();
    _rep.dispose();
    _statement.dispose();
    _notes.dispose();
    _managers.dispose();
    _host.dispose();
    _page.dispose();
    _line.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool _isOldPdf(int i) => i < _oldTypes.length && _oldTypes[i] == 'pdf';

  Future<void> _loadOldThumbs(dynamic id) async {
    for (var i = 0; i < _keepCount; i++) {
      if (_isOldPdf(i)) continue;
      try {
        final d = await Api.auth('getGateImage', [id, i]);
        if (!mounted) return;
        if (d is String && d.isNotEmpty && !d.startsWith('data:application/pdf')) {
          final b = base64Decode(d.split(',').last);
          setState(() => _oldThumbs[i] = b);
        }
      } catch (_) {
        // تجاهل: تبقى أيقونة بدل المصغّرة
      }
    }
  }

  List<String> get _plates {
    final seen = <String>{};
    final out = <String>[];
    for (final g in widget.all) {
      final p = _s(g, 'plate').trim();
      if (p.isEmpty || seen.contains(p)) continue;
      seen.add(p);
      out.add(p);
    }
    return out;
  }

  void _autofillDriver(String plate) {
    if (_driver.text.trim().isNotEmpty) return;
    final n = normAr(plate.trim());
    if (n.isEmpty) return;
    for (final g in widget.all) {
      if (normAr(_s(g, 'plate').trim()) == n && _s(g, 'driver').trim().isNotEmpty) {
        _driver.text = _s(g, 'driver');
        break;
      }
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final parts = _time.text.split(':');
    var h = TimeOfDay.now().hour;
    var m = TimeOfDay.now().minute;
    if (parts.length == 2) {
      h = int.tryParse(parts[0].trim()) ?? h;
      m = int.tryParse(parts[1].trim()) ?? m;
    }
    if (h < 0 || h > 23) h = 0;
    if (m < 0 || m > 59) m = 0;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (t != null) setState(() => _time.text = _fmtTime(t));
  }

  int get _total => _newAtts.length + _keepCount - _remove.length;

  bool _checkLimit() {
    if (_total >= 20) {
      setState(() => _err = 'الحد الأقصى 20 مرفقًا للتسجيل الواحد');
      return false;
    }
    return true;
  }

  Future<void> _shoot() async {
    if (!_checkLimit()) return;
    try {
      final p = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1400, imageQuality: 72);
      if (p == null) return;
      final bytes = await p.readAsBytes();
      if (!mounted) return;
      setState(() => _newAtts.add(_NewAtt('data:image/jpeg;base64,${base64Encode(bytes)}', false, bytes)));
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذر التقاط الصورة');
    }
  }

  Future<void> _gallery() async {
    if (!_checkLimit()) return;
    try {
      final ps = await ImagePicker().pickMultiImage(maxWidth: 1400, imageQuality: 72);
      for (final p in ps) {
        if (_total >= 20) {
          if (mounted) setState(() => _err = 'الحد الأقصى 20 مرفقًا للتسجيل الواحد');
          break;
        }
        final bytes = await p.readAsBytes();
        if (!mounted) return;
        final m = _mimeOf(p.name);
        setState(() => _newAtts.add(_NewAtt('data:${m == 'application/pdf' ? 'image/jpeg' : m};base64,${base64Encode(bytes)}', false, bytes)));
      }
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذر اختيار الصور');
    }
  }

  Future<void> _files() async {
    if (!_checkLimit()) return;
    try {
      final r = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (r == null) return;
      for (final f in r.files) {
        final b = f.bytes;
        if (b == null) continue;
        if (_total >= 20) {
          if (mounted) setState(() => _err = 'الحد الأقصى 20 مرفقًا للتسجيل الواحد');
          break;
        }
        if (b.length > 5000000) {
          if (mounted) setState(() => _err = 'الملف ${f.name} أكبر من 5 ميجا');
          continue;
        }
        final m = _mimeOf(f.name);
        if (!mounted) return;
        setState(() => _newAtts.add(_NewAtt('data:$m;base64,${base64Encode(b)}', m == 'application/pdf', b)));
      }
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذر إضافة الملف');
    }
  }

  // رقم القيد = yymmdd + الصفحة (خانتان) + السطر
  String get _entryPreview {
    final pg = int.tryParse(_page.text.trim());
    final ln = int.tryParse(_line.text.trim());
    if (pg == null && ln == null) return 'يُحدَّد تلقائيًا عند الحفظ';
    final yy = (_date.year % 100).toString().padLeft(2, '0');
    final mm = _date.month.toString().padLeft(2, '0');
    final dd = _date.day.toString().padLeft(2, '0');
    final p = pg == null ? '..' : pg.toString().padLeft(2, '0');
    final l = ln == null ? '.' : ln.toString();
    return '$yy$mm$dd$p$l';
  }

  Future<void> _save() async {
    if (_plate.text.trim().isEmpty && _driver.text.trim().isEmpty && _rep.text.trim().isEmpty) {
      setState(() => _err = 'اكتب رقم السيارة أو السائق أو المندوب');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      await Api.auth('saveGate', [
        {
          'id': widget.existing?['id'],
          'date': _ds(_date),
          'time': _time.text.trim(),
          'action': _action,
          'plate': _plate.text.trim(),
          'driver': _driver.text.trim(),
          'rep': _rep.text.trim(),
          'statement': _statement.text.trim(),
          'notes': _notes.text.trim(),
          'managers': _managers.text.trim(),
          'host': _host.text.trim(),
          'newImages': _newAtts.map((a) => a.data).toList(),
          'removeIdx': _remove.toList(),
        }
      ]);
      if (mounted) Navigator.pop(context, true);
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on ApiException catch (e) {
      if (mounted) setState(() { _err = e.message; _busy = false; });
    } catch (_) {
      if (mounted) setState(() { _err = 'تعذر الحفظ'; _busy = false; });
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) => InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: mq.viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'سجل بوابة جديد' : 'تعديل سجل البوابة',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kGatePurple)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: _dec('التاريخ'),
                      child: Text(fmtDate(_ds(_date)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _time,
                    keyboardType: TextInputType.datetime,
                    decoration: _dec('الوقت', hint: '09:30', suffix: InkWell(onTap: _pickTime, child: const Icon(Icons.access_time, size: 18))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _action,
              decoration: _dec('إجراء'),
              items: kGateActions.map((a) => DropdownMenuItem(value: a, child: Text(a, style: TextStyle(color: _actionColor(a), fontWeight: FontWeight.w700)))).toList(),
              onChanged: (v) => setState(() => _action = v ?? '--'),
            ),
            const SizedBox(height: 8),
            RawAutocomplete<String>(
              textEditingController: _plate,
              focusNode: _plateFocus,
              optionsBuilder: (TextEditingValue v) {
                final q = normAr(v.text.trim());
                if (q.isEmpty) return const Iterable<String>.empty();
                return _plates.where((p) => normAr(p).contains(q) && normAr(p) != q).take(6);
              },
              onSelected: (String s) => setState(() => _autofillDriver(s)),
              fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) => TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: _dec('رقم السيارة *'),
                onChanged: (v) {
                  final n = normAr(v.trim());
                  if (n.isNotEmpty && _driver.text.trim().isEmpty) {
                    final hit = _plates.any((p) => normAr(p) == n);
                    if (hit) setState(() => _autofillDriver(v));
                  }
                },
              ),
              optionsViewBuilder: (ctx, onSel, options) => Align(
                alignment: AlignmentDirectional.topStart,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 200, maxWidth: mq.size.width - 32),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(o, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            onTap: () => onSel(o),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: _driver, decoration: _dec('اسم السائق')),
            const SizedBox(height: 8),
            TextField(controller: _rep, decoration: _dec('المندوب / الموظف')),
            const SizedBox(height: 8),
            TextField(
              controller: _statement,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: _dec('البيان'),
            ),
            const SizedBox(height: 8),
            TextField(controller: _managers, decoration: _dec('حضور مديرين')),
            const SizedBox(height: 8),
            TextField(controller: _host, decoration: _dec('اسم المضيف')),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            TextField(controller: _notes, maxLines: 2, decoration: _dec('ملاحظات إضافية')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(onPressed: _shoot, icon: const Icon(Icons.photo_camera_outlined, size: 17), label: const Text('تصوير', style: TextStyle(fontSize: 12))),
                OutlinedButton.icon(onPressed: _gallery, icon: const Icon(Icons.photo_library_outlined, size: 17), label: const Text('من المعرض', style: TextStyle(fontSize: 12))),
                OutlinedButton.icon(onPressed: _files, icon: const Icon(Icons.attach_file, size: 17), label: const Text('ملف / PDF', style: TextStyle(fontSize: 12))),
                Text('$_total مرفق', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
            if (_newAtts.isNotEmpty || _keepCount > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _keepCount; i++)
                    _thumb(
                      marked: _remove.contains(i),
                      onTap: () => setState(() { if (_remove.contains(i)) { _remove.remove(i); } else { _remove.add(i); } }),
                      child: _oldThumbs[i] != null
                          ? Image.memory(_oldThumbs[i]!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.photo_outlined))
                          : Icon(_isOldPdf(i) ? Icons.picture_as_pdf : Icons.photo_outlined, color: _isOldPdf(i) ? const Color(0xFFB91C1C) : null),
                    ),
                  for (var i = 0; i < _newAtts.length; i++)
                    _thumb(
                      marked: false,
                      onTap: () => setState(() => _newAtts.removeAt(i)),
                      child: _newAtts[i].pdf
                          ? const Icon(Icons.picture_as_pdf, color: Color(0xFFB91C1C))
                          : Image.memory(_newAtts[i].bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('المرفقات القديمة: اضغط للحذف / التراجع — الجديدة: اضغط لإزالتها', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
              ),
            ],
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: TextStyle(color: cs.error, fontSize: 12.5), textAlign: TextAlign.center),
              ),
            const SizedBox(height: 12),
            _busy
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(onPressed: _save, child: const Text('حفظ السجل')),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ],
        ),
      ),
    );
  }

  Widget _thumb({required bool marked, required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: marked ? Colors.red : const Color(0xFFCBD5E1), width: marked ? 2 : 1),
          color: const Color(0xFFF1F5F9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (marked) const Center(child: Icon(Icons.delete, color: Colors.red, shadows: [Shadow(blurRadius: 6, color: Colors.white)])),
          ],
        ),
      ),
    );
  }
}
