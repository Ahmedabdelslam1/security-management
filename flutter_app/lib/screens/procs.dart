// الإجراءات اليومية: سيارة / سائق / مندوب + مستندات (صور وPDF) + ختم وتوقيع
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

const List<String> kProcTypes = ['--', 'دخول', 'خروج'];
const List<String> kProcSign = ['--', 'تم الختم والتوقيع'];
const List<String> _wd = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

String _ds(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _s(Map r, String k) => '${r[k] ?? ''}';
String _norm(String x) => x.trim().toLowerCase();

class ProcsScreen extends StatefulWidget {
  const ProcsScreen({super.key});
  @override
  State<ProcsScreen> createState() => _ProcsScreenState();
}

class _ProcsScreenState extends State<ProcsScreen> {
  List<Map> _rows = [];
  bool _busy = false;
  String _q = '';
  String _type = ''; // '' = الكل
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Api.auth('listProcs');
      if (mounted) setState(() => _rows = (r as List).map((x) => x as Map).toList());
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on ApiException catch (e) {
      _msg(e.message, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String m, [bool err = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: err ? Colors.red.shade700 : Colors.green.shade700));
  }

  List<Map> get _filtered {
    final f = _from == null ? '' : _ds(_from!);
    final t = _to == null ? '' : _ds(_to!);
    return _rows.where((p) {
      final d = _s(p, 'date');
      if (f.isNotEmpty && d.compareTo(f) < 0) return false;
      if (t.isNotEmpty && d.compareTo(t) > 0) return false;
      if (_type.isNotEmpty && _s(p, 'ptype') != _type) return false;
      if (_q.isEmpty) return true;
      return txtMatch(_q, [
        _s(p, 'seq'), fmtDate(d), d, _s(p, 'weekday'), _s(p, 'plate'), _s(p, 'driver'), _s(p, 'rep'), _s(p, 'statement'),
        _s(p, 'ptype'), _s(p, 'signed'), _s(p, 'signDate'), _s(p, 'signer'), _s(p, 'bookPage'), _s(p, 'supervisor'), _s(p, 'notes'),
      ]);
    }).toList();
  }

  static String _signText(Map p) {
    if (_s(p, 'signed') != 'تم الختم والتوقيع') return '—';
    final bp = _s(p, 'bookPage');
    return 'تم الختم والتوقيع ${fmtDate(_s(p, 'signDate'))} — ${_s(p, 'signer')}${bp.isEmpty ? '' : ' — ص/ع $bp'}';
  }

  List<List<String>> _pdfRows(List<Map> rs) => [
        for (final p in rs)
          [
            _s(p, 'seq'), fmtDate(_s(p, 'date')), _s(p, 'weekday'), _s(p, 'plate'), _s(p, 'driver'), _s(p, 'rep'),
            _s(p, 'statement'), _s(p, 'ptype'), _signText(p), _s(p, 'supervisor'), _s(p, 'notes'),
          ]
      ];

  static const _pdfHeaders = ['م', 'التاريخ', 'اليوم', 'رقم السيارة', 'اسم السائق', 'المندوب / الموظف', 'البيان', 'نوع الإجراء', 'توقيع المستند', 'مشرف الوردية', 'ملاحظات'];
  static const _pdfWidths = <double>[0.6, 1.3, 1.1, 1.4, 1.8, 1.8, 2, 1, 2.6, 1.4, 1.6];

  void _pdf() {
    final rs = _filtered.toList()..sort((a, b) => _s(a, 'date') == _s(b, 'date') ? _s(a, 'seq').compareTo(_s(b, 'seq')) : _s(a, 'date').compareTo(_s(b, 'date')));
    exportTablePdf(
      context: context,
      title: 'الإجراءات اليومية',
      subtitle: '${_from == null ? '' : 'من ${fmtDate(_ds(_from!))} '}${_to == null ? '' : 'إلى ${fmtDate(_ds(_to!))}'}${_type.isEmpty ? '' : ' — $_type'}',
      headers: _pdfHeaders,
      widths: _pdfWidths,
      landscape: true,
      rows: _pdfRows(rs),
      total: '${rs.length}',
      totalLabel: 'عدد الإجراءات',
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

  Future<void> _edit([Map? p]) async {
    final saved = await Navigator.of(context).push<Map>(MaterialPageRoute(builder: (_) => _ProcForm(rec: p, all: _rows)));
    if (saved == null) return;
    setState(() {
      final i = _rows.indexWhere((x) => x['id'] == saved['id']);
      if (i == -1) { _rows.insert(0, saved); } else { _rows[i] = saved; }
      _rows.sort((a, b) => _s(a, 'date') == _s(b, 'date') ? ((b['seq'] ?? 0) as num).compareTo((a['seq'] ?? 0) as num) : _s(b, 'date').compareTo(_s(a, 'date')));
    });
    _msg('تم الحفظ');
  }

  Future<void> _delete(Map p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف هذا الإجراء (${_s(p, 'plate').isNotEmpty ? _s(p, 'plate') : _s(p, 'rep')}) نهائيًا؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.auth('deleteProc', [p['id']]);
      setState(() => _rows.removeWhere((x) => x['id'] == p['id']));
      _msg('تم الحذف');
    } on ApiException catch (e) {
      _msg(e.message, true);
    }
  }

  void _files(Map p, String field) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FilesPage(id: '${p['id']}', field: field, title: '${field == 'docs' ? 'صور المستندات' : 'مستندات أخرى'} — ${_s(p, 'plate').isNotEmpty ? _s(p, 'plate') : _s(p, 'rep')}')));
  }

  // تقرير يومي لسيارة / سائق / مندوب
  void _report(String kind, Map p) {
    final val = _s(p, kind);
    if (val.trim().isEmpty) return;
    DateTime from = DateTime.tryParse(_s(p, 'date')) ?? DateTime.now();
    DateTime? to = from;
    DateTime? fromN = from;
    final title = '${kind == 'plate' ? 'تقرير يومي للسيارة' : kind == 'driver' ? 'تقرير يومي للسائق' : 'تقرير يومي للمندوب / الموظف'} $val';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final f = fromN == null ? '' : _ds(fromN!);
        final t = to == null ? '' : _ds(to!);
        final rs = _rows.where((x) => _norm(_s(x, kind)) == _norm(val) && (f.isEmpty || _s(x, 'date').compareTo(f) >= 0) && (t.isEmpty || _s(x, 'date').compareTo(t) <= 0)).toList()
          ..sort((a, b) => _s(a, 'date').compareTo(_s(b, 'date')));
        Future<void> pickD(bool isFrom) async {
          final d = await showDatePicker(context: ctx, initialDate: (isFrom ? fromN : to) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)), locale: const Locale('ar'));
          if (d != null) setS(() { if (isFrom) { fromN = d; } else { to = d; } });
        }
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * .8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => pickD(true), child: Text(fromN == null ? 'من: الكل' : 'من ${fmtDate(f)}', style: const TextStyle(fontSize: 12.5)))),
                    const SizedBox(width: 6),
                    Expanded(child: OutlinedButton(onPressed: () => pickD(false), child: Text(to == null ? 'إلى: الكل' : 'إلى ${fmtDate(t)}', style: const TextStyle(fontSize: 12.5)))),
                    IconButton(tooltip: 'كل الأيام', onPressed: () => setS(() { fromN = null; to = null; }), icon: const Icon(Icons.all_inclusive)),
                    IconButton(
                      tooltip: 'طباعة',
                      onPressed: rs.isEmpty
                          ? null
                          : () => exportTablePdf(
                                context: context,
                                title: title,
                                subtitle: '${fromN == null ? '' : 'من ${fmtDate(f)} '}${to == null ? '' : 'إلى ${fmtDate(t)}'}',
                                headers: _pdfHeaders,
                                widths: _pdfWidths,
                                landscape: true,
                                rows: _pdfRows(rs),
                                total: '${rs.length}',
                                totalLabel: 'عدد الإجراءات',
                              ),
                      icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF6D28D9)),
                    ),
                  ],
                ),
                Text('عدد الإجراءات: ${rs.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(height: 4),
                Expanded(
                  child: rs.isEmpty
                      ? const Center(child: Text('لا توجد إجراءات في الفترة'))
                      : ListView(children: [for (final p in rs) _card(p, compact: true)]),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _link(String kind, Map p, {TextStyle? style}) {
    final v = _s(p, kind);
    if (v.isEmpty) return const Text('—');
    return InkWell(
      onTap: () => _report(kind, p),
      child: Text(v, style: (style ?? const TextStyle(fontSize: 12.5)).copyWith(color: const Color(0xFF1D4ED8), decoration: TextDecoration.underline)),
    );
  }

  Widget _card(Map p, {bool compact = false}) {
    final docs = (p['docs'] as List? ?? []).length;
    final other = (p['other'] as List? ?? []).length;
    final tp = _s(p, 'ptype');
    return GlowCard(
      glow: const Color(0xFFEA580C),
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _link('plate', p, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tp == 'دخول' ? Colors.green.shade100 : tp == 'خروج' ? Colors.orange.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tp, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Text('م ${_s(p, 'seq')}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
              ],
            ),
            const SizedBox(height: 4),
            Text('${_s(p, 'weekday')} ${fmtDate(_s(p, 'date'))}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Wrap(spacing: 14, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [const Text('السائق: ', style: TextStyle(fontSize: 12)), _link('driver', p)]),
              Row(mainAxisSize: MainAxisSize.min, children: [const Text('المندوب: ', style: TextStyle(fontSize: 12)), _link('rep', p)]),
            ]),
            if (_s(p, 'statement').isNotEmpty) Text('البيان: ${_s(p, 'statement')}', style: const TextStyle(fontSize: 12.5)),
            Text('التوقيع: ${_signText(p)}', style: TextStyle(fontSize: 12, color: _s(p, 'signed') == 'تم الختم والتوقيع' ? Colors.green.shade800 : const Color(0xFF64748B))),
            if (_s(p, 'supervisor').isNotEmpty) Text('مشرف الوردية: ${_s(p, 'supervisor')}', style: const TextStyle(fontSize: 12)),
            if (_s(p, 'notes').isNotEmpty) Text('ملاحظات: ${_s(p, 'notes')}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Row(
              children: [
                if (docs > 0) TextButton.icon(onPressed: () => _files(p, 'docs'), icon: const Icon(Icons.attach_file, size: 16), label: Text('المستندات ($docs)', style: const TextStyle(fontSize: 12))),
                if (other > 0) TextButton.icon(onPressed: () => _files(p, 'other'), icon: const Icon(Icons.folder_open, size: 16), label: Text('أخرى ($other)', style: const TextStyle(fontSize: 12))),
                const Spacer(),
                if (!compact) ...[
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => _edit(p), icon: const Icon(Icons.edit, size: 19)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => _delete(p), icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade700)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('إجراء جديد')),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SearchBox(hint: 'بحث في كل البنود...', value: _q, onChanged: (v) => setState(() => _q = v))),
                    IconButton.filledTonal(
                      tooltip: 'طباعة / PDF',
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                      onPressed: _pdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
                    ),
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Row(
                    children: [
                      for (final t in const ['', 'دخول', 'خروج', '--'])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(label: Text(t.isEmpty ? 'الكل' : t, style: const TextStyle(fontSize: 12)), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
                        ),
                      const Spacer(),
                      TextButton(onPressed: () => _pick(true), child: Text(_from == null ? 'من' : fmtDate(_ds(_from!)), style: const TextStyle(fontSize: 12))),
                      TextButton(onPressed: () => _pick(false), child: Text(_to == null ? 'إلى' : fmtDate(_ds(_to!)), style: const TextStyle(fontSize: 12))),
                      if (_from != null || _to != null) IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() { _from = null; _to = null; }), icon: const Icon(Icons.close, size: 18)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text('عدد الإجراءات: ${rs.length} • دخول ${rs.where((p) => _s(p, 'ptype') == 'دخول').length} • خروج ${rs.where((p) => _s(p, 'ptype') == 'خروج').length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          Expanded(
            child: _busy && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : rs.isEmpty
                    ? const Center(child: Text('لا توجد إجراءات'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
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

/* ===================== عرض الملفات (صور بحجم واضح + PDF + طباعة) ===================== */
class _FilesPage extends StatefulWidget {
  final String id, field, title;
  const _FilesPage({required this.id, required this.field, required this.title});
  @override
  State<_FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<_FilesPage> {
  List<Map>? _files;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.auth('getProcFiles', [widget.id]) as Map;
      if (mounted) setState(() => _files = ((r[widget.field] ?? []) as List).map((x) => x as Map).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  Uint8List _bytes(Map f) => base64Decode('${f['data']}'.split(',').last);

  Future<void> _printImages() async {
    final doc = pw.Document();
    for (final f in _files ?? <Map>[]) {
      if (f['t'] == 'pdf' || '${f['data']}'.isEmpty) continue;
      doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(_bytes(f)), fit: pw.BoxFit.contain))));
    }
    final bytes = await doc.save();
    await Printing.layoutPdf(name: 'مستندات', onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final fs = _files;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        actions: [
          if (fs != null && fs.any((f) => f['t'] != 'pdf'))
            IconButton(tooltip: 'طباعة الصور', onPressed: _printImages, icon: const Icon(Icons.print)),
        ],
      ),
      body: _err != null
          ? Center(child: Text(_err!))
          : fs == null
              ? const Center(child: CircularProgressIndicator())
              : fs.isEmpty
                  ? const Center(child: Text('لا توجد ملفات'))
                  : ListView(
                      padding: const EdgeInsets.all(10),
                      children: [
                        for (final f in fs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: '${f['data']}'.isEmpty
                                ? const Text('ملف غير متاح')
                                : f['t'] == 'pdf'
                                    ? FilledButton.icon(
                                        onPressed: () => Printing.layoutPdf(name: 'مستند', onLayout: (_) async => _bytes(f)),
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: const Text('عرض / طباعة ملف PDF'),
                                      )
                                    : InteractiveViewer(minScale: 1, maxScale: 5, child: Image.memory(_bytes(f), width: double.infinity, fit: BoxFit.fitWidth)),
                          ),
                      ],
                    ),
    );
  }
}

/* ===================== نموذج الإضافة / التعديل ===================== */
class _NewFile {
  final String data;
  final String name;
  final bool pdf;
  _NewFile(this.data, this.name, this.pdf);
}

class _ProcForm extends StatefulWidget {
  final Map? rec;
  final List<Map> all;
  const _ProcForm({this.rec, required this.all});
  @override
  State<_ProcForm> createState() => _ProcFormState();
}

class _ProcFormState extends State<_ProcForm> {
  late String _date;
  late String _ptype;
  late String _signed;
  late String _signDate;
  final _plate = TextEditingController();
  final _driver = TextEditingController();
  final _rep = TextEditingController();
  final _statement = TextEditingController();
  final _signer = TextEditingController();
  final _bookPage = TextEditingController();
  final _supervisor = TextEditingController();
  final _notes = TextEditingController();
  final List<_NewFile> _newDocs = [];
  final List<_NewFile> _newOther = [];
  List<Map> _oldDocs = [];
  List<Map> _oldOther = [];
  final Set<int> _rmDocs = {};
  final Set<int> _rmOther = {};
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final r = widget.rec;
    _date = r == null ? _ds(DateTime.now()) : _s(r, 'date');
    _ptype = r == null || !kProcTypes.contains(_s(r, 'ptype')) ? '--' : _s(r, 'ptype');
    _signed = r == null || !kProcSign.contains(_s(r, 'signed')) ? '--' : _s(r, 'signed');
    _signDate = r != null && _s(r, 'signDate').isNotEmpty ? _s(r, 'signDate') : _ds(DateTime.now());
    if (r != null) {
      _plate.text = _s(r, 'plate');
      _driver.text = _s(r, 'driver');
      _rep.text = _s(r, 'rep');
      _statement.text = _s(r, 'statement');
      _signer.text = _s(r, 'signer');
      _bookPage.text = _s(r, 'bookPage');
      _supervisor.text = _s(r, 'supervisor');
      _notes.text = _s(r, 'notes');
      if (((r['docs'] as List?) ?? []).isNotEmpty || ((r['other'] as List?) ?? []).isNotEmpty) _loadOld('${r['id']}');
    }
  }

  Future<void> _loadOld(String id) async {
    try {
      final r = await Api.auth('getProcFiles', [id]) as Map;
      if (mounted) {
        setState(() {
          _oldDocs = ((r['docs'] ?? []) as List).map((x) => x as Map).toList();
          _oldOther = ((r['other'] ?? []) as List).map((x) => x as Map).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDate(bool sign) async {
    final cur = DateTime.tryParse(sign ? _signDate : _date) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)), locale: const Locale('ar'));
    if (d != null) setState(() { if (sign) { _signDate = _ds(d); } else { _date = _ds(d); } });
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addFiles(List<_NewFile> target, {required bool camera}) async {
    try {
      if (camera) {
        final p = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
        if (p == null) return;
        final b = await p.readAsBytes();
        setState(() => target.add(_NewFile('data:image/jpeg;base64,${base64Encode(b)}', p.name, false)));
      } else {
        final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'], withData: true);
        if (r == null) return;
        for (final f in r.files) {
          final b = f.bytes;
          if (b == null) continue;
          if (b.length > 5000000) {
            setState(() => _err = 'الملف ${f.name} أكبر من 5 ميجا');
            continue;
          }
          final m = _mime(f.name);
          setState(() => target.add(_NewFile('data:$m;base64,${base64Encode(b)}', f.name, m == 'application/pdf')));
        }
      }
    } catch (e) {
      setState(() => _err = 'تعذر إضافة الملف');
    }
  }

  Future<void> _save() async {
    if (_plate.text.trim().isEmpty && _driver.text.trim().isEmpty && _rep.text.trim().isEmpty) {
      setState(() => _err = 'اكتب رقم السيارة أو السائق أو المندوب');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      final res = await Api.auth('saveProc', [
        {
          'id': widget.rec?['id'],
          'date': _date,
          'plate': _plate.text.trim(),
          'driver': _driver.text.trim(),
          'rep': _rep.text.trim(),
          'statement': _statement.text.trim(),
          'ptype': _ptype,
          'signed': _signed,
          'signDate': _signDate,
          'signer': _signer.text.trim(),
          'bookPage': _bookPage.text.trim(),
          'supervisor': _supervisor.text.trim(),
          'notes': _notes.text.trim(),
          'newDocs': _newDocs.map((f) => f.data).toList(),
          'newOther': _newOther.map((f) => f.data).toList(),
          'removeDocs': _rmDocs.toList(),
          'removeOther': _rmOther.toList(),
        }
      ]) as Map;
      if (mounted) Navigator.of(context).pop(res);
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tf(TextEditingController c, String label, {List<String> hints = const []}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: label),
        onChanged: (_) {
          // تعبئة تلقائية: رقم السيارة يملأ السائق من آخر سجل مطابق
          if (identical(c, _plate) && _driver.text.isEmpty) {
            for (final g in widget.all) {
              if (_norm(_s(g, 'plate')) == _norm(c.text) && _s(g, 'driver').isNotEmpty) {
                _driver.text = _s(g, 'driver');
                break;
              }
            }
          }
        },
      ),
    );
  }

  Widget _filesSection(String title, List<_NewFile> news, List<Map> olds, Set<int> rm, bool isDocs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        Row(
          children: [
            TextButton.icon(onPressed: () => _addFiles(news, camera: true), icon: const Icon(Icons.photo_camera, size: 18), label: const Text('تصوير')),
            TextButton.icon(onPressed: () => _addFiles(news, camera: false), icon: const Icon(Icons.attach_file, size: 18), label: const Text('صور / PDF')),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < olds.length; i++)
              InputChip(
                label: Text(olds[i]['t'] == 'pdf' ? 'PDF ${i + 1}' : 'صورة ${i + 1}', style: TextStyle(decoration: rm.contains(i) ? TextDecoration.lineThrough : null)),
                avatar: Icon(rm.contains(i) ? Icons.undo : Icons.delete_outline, size: 16),
                onPressed: () => setState(() { if (rm.contains(i)) { rm.remove(i); } else { rm.add(i); } }),
              ),
            for (var i = 0; i < news.length; i++)
              InputChip(
                label: Text(news[i].pdf ? 'PDF جديد' : 'صورة جديدة', style: const TextStyle(fontSize: 12)),
                onDeleted: () => setState(() => news.removeAt(i)),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wd = DateTime.tryParse(_date);
    return Scaffold(
      appBar: AppBar(title: Text(widget.rec == null ? 'إجراء يومي جديد' : 'تعديل إجراء', style: const TextStyle(fontSize: 15))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_err != null)
            Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8), color: Theme.of(context).colorScheme.errorContainer, child: Text(_err!)),
          InkWell(
            onTap: () => _pickDate(false),
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'التاريخ'),
              child: Text('${fmtDate(_date)}${wd == null ? '' : ' — ${_wd[wd.weekday % 7]}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          _tf(_plate, 'رقم السيارة'),
          _tf(_driver, 'اسم السائق'),
          _tf(_rep, 'المندوب / الموظف'),
          _tf(_statement, 'البيان'),
          DropdownButtonFormField<String>(
            value: _ptype,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'نوع الإجراء'),
            items: kProcTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _ptype = v ?? '--'),
          ),
          const SizedBox(height: 8),
          _filesSection('صورة المستندات (صورة أو أكثر أو PDF)', _newDocs, _oldDocs, _rmDocs, true),
          DropdownButtonFormField<String>(
            value: _signed,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'توقيع المستند'),
            items: kProcSign.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _signed = v ?? '--'),
          ),
          const SizedBox(height: 8),
          if (_signed == 'تم الختم والتوقيع') ...[
            InkWell(
              onTap: () => _pickDate(true),
              child: InputDecorator(
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'تاريخ الختم والتوقيع'),
                child: Text(fmtDate(_signDate), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            _tf(_signer, 'اسم القائم بالعمل'),
            _tf(_bookPage, 'رقم الصفحة والعمود في الدفتر'),
          ],
          _tf(_supervisor, 'مشرف الوردية'),
          _tf(_notes, 'ملاحظات'),
          _filesSection('مستندات أخرى (صورة أو أكثر أو PDF)', _newOther, _oldOther, _rmOther, false),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('حفظ'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
