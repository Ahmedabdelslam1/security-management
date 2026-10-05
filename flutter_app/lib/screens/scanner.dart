// سكانر الباركود + مستندات وصور مرفقة لكل البنود
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../attach.dart';
import '../state.dart';
import '../widgets.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<(String, DateTime)> _scans = [];
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    try {
      final p = await SharedPreferences.getInstance();
      final j = jsonDecode(p.getString('scan_history') ?? '[]') as List;
      setState(() {
        _scans.clear();
        for (final e in j) {
          _scans.add((e[0] as String, DateTime.tryParse(e[1] as String) ?? DateTime.now()));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveScans() async {
    try {
      final p = await SharedPreferences.getInstance();
      p.setString('scan_history', jsonEncode(_scans.take(30).map((s) => [s.$1, s.$2.toIso8601String()]).toList()));
    } catch (_) {}
  }

  void _onDetect(BarcodeCapture c) {
    final b = c.barcodes.firstWhere((x) => (x.rawValue ?? '').isNotEmpty, orElse: () => c.barcodes.first);
    final v = b.rawValue ?? '';
    if (v.isEmpty) return;
    final now = DateTime.now();
    if (v == _last && now.difference(_lastAt).inSeconds < 4) return;
    _last = v;
    _lastAt = now;
    setState(() => _scans.insert(0, (v, now)));
    _scans.length > 30 ? _scans.removeLast() : null;
    _saveScans();
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('نتيجة المسح', textAlign: TextAlign.center),
        content: SelectableText(v, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('إغلاق')),
          TextButton(
            onPressed: () { Clipboard.setData(ClipboardData(text: v)); Navigator.pop(_); },
            child: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Share.share(v).then((_) => Navigator.pop(_)),
            child: const Text('مشاركة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('باركود ومستندات'),
          bottom: const TabBar(
            tabs: [Tab(text: 'مسح باركود', icon: Icon(Icons.qr_code_scanner)), Tab(text: 'المستندات والصور', icon: Icon(Icons.photo_library))],
          ),
        ),
        body: TabBarView(
          children: [
            // ===== تبويب الباركود =====
            Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      MobileScanner(onDetect: _onDetect),
                      Center(
                        child: Container(
                          width: 230, height: 230,
                          decoration: BoxDecoration(
                            border: Border.all(color: Color(0xFF7C5CFC), width: 3),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 108,
                  padding: const EdgeInsets.all(8),
                  child: _scans.isEmpty
                      ? const Center(child: Text('وجه الكاميرا نحو الباركود — النتائج تظهر هنا', style: TextStyle(fontSize: 12, color: Colors.black45)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _scans.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, i) => ActionChip(
                            avatar: const Icon(Icons.qr_code, size: 16),
                            label: Text(_scans[i].$1.length > 18 ? '${_scans[i].$1.substring(0, 18)}…' : _scans[i].$1),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(_scans[i].$2.toString().substring(0, 16), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                                content: SelectableText(_scans[i].$1, textAlign: TextAlign.center),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
                                  FilledButton(onPressed: () { Clipboard.setData(ClipboardData(text: _scans[i].$1)); Navigator.pop(context); }, child: const Text('نسخ')),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            // ===== تبويب المستندات والصور =====
            const DocsTab(),
          ],
        ),
      ),
    );
  }
}

// ===== المستندات: ربط الصور بكل البنود + عرض كل الصور المرفقة =====
class DocsTab extends StatefulWidget {
  const DocsTab({super.key});
  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  String _item = '__all__';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AttachStore.I.ensure().then((_) { if (mounted) setState(() => _loading = false); });
  }

  // قائمة البنود المتاحة للربط: عاملين + مستخدمين + عام
  List<(String, String)> get _items {
    final out = <(String, String)>[('__all__', 'كل الصور المرفقة')];
    for (final w in App.I.workers) {
      out.add(('worker_${w.id}', 'عامل: ${w.name}'));
    }
    final us = App.I.data?.users ?? [];
    for (final u in us) {
      out.add(('user_${u.id}', 'مستخدم: ${u.name}'));
    }
    out.add(('general', 'مستندات عامة'));
    return out;
  }

  Future<void> _pickAndSave(String key, String label, {required bool camera}) async {
    final ok = await AttachStore.I.add(
      key: key, label: label,
      source: camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'تم حفظ الصورة مع «$label»' : 'تم الإلغاء'),
      backgroundColor: ok ? const Color(0xFF15803D) : Colors.black54,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final st = AttachStore.I;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final cur = _item == '__all__' ? st.all : st.forItem(_item);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
              child: DropdownButtonFormField<String>(
                value: _items.any((e) => e.$1 == _item) ? _item : '__all__',
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.folder_open, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: [for (final it in _items) DropdownMenuItem(value: it.$1, child: Text(it.$2, style: const TextStyle(fontSize: 13)))],
                onChanged: (v) => setState(() => _item = v ?? '__all__'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('كاميرا'),
                      onPressed: () => _pickAndSave(_item == '__all__' ? 'general' : _item, _labelFor(_item), camera: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('من المعرض'),
                      onPressed: () => _pickAndSave(_item == '__all__' ? 'general' : _item, _labelFor(_item), camera: false),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cur.isEmpty
                  ? const Center(child: Text('لا توجد صور مرفقة بعد', style: TextStyle(color: Colors.black38)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                      itemCount: cur.length,
                      itemBuilder: (_, i) => _imgTile(context, cur[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  String _labelFor(String key) => _items.firstWhere((e) => e.$1 == key, orElse: () => ('general', 'مستندات عامة')).$2;

  Widget _imgTile(BuildContext context, Attach a) {
    return SlideIn(
      index: 0,
      child: GestureDetector(
        onTap: () => _viewer(a),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: const Color(0xFF7C5CFC).withOpacity(.18), blurRadius: 7, offset: const Offset(0, 2))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(a.path), fit: BoxFit.cover),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    color: Colors.black.withOpacity(.55),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '${a.label} • ${a.date.day}/${a.date.month}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _viewer(Attach a) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            InteractiveViewer(maxScale: 4, child: Image.file(File(a.path))),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('مشاركة'),
                    onPressed: () => Share.shareXFiles([XFile(a.path)]),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                    label: const Text('حذف', style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      Navigator.pop(_);
                      await AttachStore.I.delete(a.id);
                    },
                  ),
                  FilledButton(onPressed: () => Navigator.pop(_), child: const Text('إغلاق')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

}
