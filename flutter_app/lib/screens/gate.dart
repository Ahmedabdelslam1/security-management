// دفتر البوابة: سجلات دخول السيارات + صور من الكاميرا
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  List<Map>? _rows;
  bool _busy = false;
  String _q = '';

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Api.auth('listGate');
      setState(() => _rows = (r as List).map((x) => x as Map).toList());
    } on SessionExpired {
      await App.I.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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

  Future<void> _viewImages(Map g) async {
    final count = (g['imgCount'] ?? 0) as int;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا صور لهذا السجل')));
      return;
    }
    final imgs = <String?>[];
    for (int i = 0; i < count; i++) {
      try {
        imgs.add(await Api.auth('getGateImage', [g['id'], i]) as String?);
      } catch (_) {
        imgs.add(null);
      }
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: PageView.builder(
          itemCount: imgs.length,
          itemBuilder: (c, i) {
            final d = imgs[i];
            return InteractiveViewer(
              child: d == null
                  ? const Center(child: Text('تعذر تحميل الصورة'))
                  : Image.memory(base64Decode(d.split(',').last), fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _rows;
    final rows = all == null
        ? null
        : _q.isEmpty
            ? all
            : all.where((g) => txtMatch(_q, [
                  '${g['plate']}', '${g['driver']}', '${g['statement']}',
                  '${g['notes']}', '${g['host']}', '${g['seq']}'
                ])).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('سجل جديد'),
      ),
      body: _busy && all == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SearchBox(hint: 'بحث برقم السيارة أو السائق أو البيان...', value: _q, onChanged: (v) => setState(() => _q = v)),
                Expanded(
                child: RefreshIndicator(
              onRefresh: _load,
              child: (rows == null || rows.isEmpty)
                  ? ListView(children: [
                      Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(_q.isEmpty ? 'لا سجلات بعد — اضغط "سجل جديد"' : 'لا نتائج للبحث'))),
                    ])
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final g = rows[i];
                        return SlideIn(
                          index: i,
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 1.5,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFF7C5CFC).withOpacity(.12), borderRadius: BorderRadius.circular(6)),
                                      child: Text('#${g['seq']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${g['plate'] ?? ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                    ),
                                    Text(
                                      '${fmtDate(g['date'] ?? '')}${(g['time'] ?? '') == '' ? '' : ' ${g['time']}'}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if ((g['driver'] ?? '') != '')
                                  Text('السائق: ${g['driver']}', style: const TextStyle(fontSize: 13)),
                                if ((g['statement'] ?? '') != '')
                                  Text('البيان: ${g['statement']}', style: const TextStyle(fontSize: 13)),
                                if ((g['notes'] ?? '') != '')
                                  Text('ملاحظات: ${g['notes']}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                                if ((g['managers'] ?? '') != '')
                                  Text('حضور مديرين: ${g['managers']}', style: const TextStyle(fontSize: 12.5)),
                                if ((g['host'] ?? '') != '')
                                  Text('المضيف: ${g['host']}', style: const TextStyle(fontSize: 12.5)),
                                const Divider(height: 14),
                                Row(
                                  children: [
                                    if ((g['imgCount'] ?? 0) > 0)
                                      OutlinedButton.icon(
                                        onPressed: () => _viewImages(g),
                                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                                        label: Text('${g['imgCount']} صورة'),
                                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: const TextStyle(fontSize: 12)),
                                      ),
                                    const Spacer(),
                                    PopupMenuButton<String>(
                                      onSelected: (v) => v == 'edit' ? _edit(g) : _delete(g),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                        PopupMenuItem(value: 'del', child: Text('حذف', style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  ],
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
    ),
    );
  }

  Future<void> _delete(Map g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف سجل سيارة ${g['plate']} بتاريخ ${fmtDate(g['date'] ?? '')}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.auth('deleteGate', [g['id']]);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
    }
  }

  Future<void> _edit(Map? g) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _GateForm(existing: g),
    );
    if (saved == true) _load();
  }
}

class _GateForm extends StatefulWidget {
  final Map? existing;
  const _GateForm({this.existing});
  @override
  State<_GateForm> createState() => _GateFormState();
}

class _GateFormState extends State<_GateForm> {
  late DateTime _date;
  final _time = TextEditingController();
  final _plate = TextEditingController();
  final _driver = TextEditingController();
  final _statement = TextEditingController();
  final _notes = TextEditingController();
  final _managers = TextEditingController();
  final _host = TextEditingController();
  final List<String> _newImgs = []; // dataURL
  final Set<int> _remove = {};
  int _keepCount = 0;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g != null) {
      final p = (g['date'] ?? '').toString().split('-');
      _date = p.length == 3 ? DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])) : DateTime.now();
      _time.text = g['time'] ?? '';
      _plate.text = g['plate'] ?? '';
      _driver.text = g['driver'] ?? '';
      _statement.text = g['statement'] ?? '';
      _notes.text = g['notes'] ?? '';
      _managers.text = g['managers'] ?? '';
      _host.text = g['host'] ?? '';
      _keepCount = (g['imgCount'] ?? 0) as int;
    } else {
      _date = DateTime.now();
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

  Future<void> _shoot() async {
    if (_newImgs.length + _keepCount >= 20) {
      setState(() => _err = 'الحد الأقصى 20 صورة للتسجيل الواحد');
      return;
    }
    try {
      final p = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1400, imageQuality: 72);
      if (p == null) return;
      final bytes = await p.readAsBytes();
      setState(() => _newImgs.add('data:image/jpeg;base64,${base64Encode(bytes)}'));
    } catch (_) {
      setState(() => _err = 'تعذر التقاط الصورة');
    }
  }

  Future<void> _save() async {
    setState(() { _busy = true; _err = null; });
    try {
      await Api.auth('saveGate', [
        {
          'id': widget.existing?['id'],
          'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
          'time': _time.text.trim(),
          'plate': _plate.text.trim(),
          'driver': _driver.text.trim(),
          'statement': _statement.text.trim(),
          'notes': _notes.text.trim(),
          'managers': _managers.text.trim(),
          'host': _host.text.trim(),
          'newImages': _newImgs,
          'removeIdx': _remove.toList(),
        }
      ]);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _err = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'سجل بوابة جديد' : 'تعديل سجل البوابة',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'التاريخ'),
                      child: Text(fmtDate('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _time,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'الوقت (سس:دد)', hintText: 'مثال 09:30'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(controller: _plate, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'رقم السيارة *')),
            const SizedBox(height: 8),
            TextField(controller: _driver, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'اسم السائق')),
            const SizedBox(height: 8),
            TextField(controller: _statement, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'البيان')),
            const SizedBox(height: 8),
            TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'ملاحظات إضافية')),
            const SizedBox(height: 8),
            TextField(controller: _managers, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'حضور مديرين')),
            const SizedBox(height: 8),
            TextField(controller: _host, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'اسم المضيف')),
            const SizedBox(height: 10),
            // الصور
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _shoot,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('إضافة صورة'),
                ),
                const SizedBox(width: 8),
                Text('${_newImgs.length + _keepCount - _remove.length} صورة', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            if (_newImgs.isNotEmpty || _remove.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _keepCount; i++)
                    _thumb(
                      marked: _remove.contains(i),
                      onTap: () => setState(() { _remove.contains(i) ? _remove.remove(i) : _remove.add(i); }),
                      child: _remove.contains(i)
                          ? const Icon(Icons.delete_outline, color: Colors.red)
                          : const Icon(Icons.photo_outlined),
                    ),
                  for (var i = 0; i < _newImgs.length; i++)
                    _thumb(
                      marked: false,
                      onTap: () => setState(() => _newImgs.removeAt(i)),
                      child: Image.memory(base64Decode(_newImgs[i].split(',').last), fit: BoxFit.cover),
                    ),
                ],
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
            if (marked) const Center(child: Icon(Icons.delete, color: Colors.white, shadows: [Shadow(blurRadius: 6)])),
          ],
        ),
      ),
    );
  }
}
