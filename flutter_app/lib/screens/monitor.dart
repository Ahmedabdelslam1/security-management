// المتابعة (للمدير): حالة المستخدمين + سجل النشاط
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../pdf_export.dart';
import '../state.dart';
import '../widgets.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  Map? _data;

  void _pdf() {
    if (_data == null) return;
    if (_tab == 0) {
      final log = (_data!['log'] as List? ?? []).map((x) => x as Map).toList();
      final rows = <List<String>>[];
      for (final l in log) {
        if (!_filter.isEmpty && !'${l['user'] ?? ''} ${l['action'] ?? ''} ${l['details'] ?? ''}'.contains(_filter)) continue;
        rows.add(['${l['time'] ?? ''}', '${l['user'] ?? ''}', '${l['action'] ?? ''}', '${l['page'] ?? ''}', '${l['details'] ?? ''}']);
      }
      exportTablePdf(
        context: context,
        title: 'سجل نشاط المستخدمين',
        headers: ['الوقت', 'المستخدم', 'الإجراء', 'الشاشة', 'التفاصيل'],
        widths: [70, 65, 65, 55, 95],
        rows: rows,
        landscape: true,
      );
    } else {
      final us = (_data!['users'] as List? ?? []).map((x) => x as Map).toList();
      final rows = [for (final u in us) ['${u['name'] ?? ''}', '${u['username'] ?? ''}', u['online'] == true ? 'متصل الآن' : 'غير متصل', '${u['lastSeen'] ?? ''}']];
      exportTablePdf(
        context: context,
        title: 'حالة المستخدمين',
        headers: ['الاسم', 'المستخدم', 'الحالة', 'آخر ظهور'],
        widths: [100, 80, 60, 75],
        rows: rows,
      );
    }
  }

  bool _busy = false;
  String _filter = '';
  int _tab = 0; // 0 = نشاط، 1 = حالة المستخدمين

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Api.auth('getMonitor') as Map;
      setState(() => _data = r);
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
    final log = (_data?['log'] as List? ?? []).map((x) => x as Map).toList();
    final users = (_data?['users'] as List? ?? []).map((x) => x as Map).toList();
    final filtered = _filter.isEmpty
        ? log
        : log.where((l) =>
            (l['user'] ?? '').toString().contains(_filter) ||
            (l['action'] ?? '').toString().contains(_filter) ||
            (l['details'] ?? '').toString().contains(_filter)).toList();

    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('سجل النشاط')),
                      ButtonSegment(value: 1, label: Text('المستخدمون')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'PDF للطباعة والإرسال',
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFEDE9FE)),
                  onPressed: _data == null ? null : _pdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF6D28D9)),
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
        ),
        if (_tab == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: TextField(
              decoration: InputDecoration(
                isDense: true, border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                labelText: 'بحث في السجل',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
          ),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _tab == 0
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: filtered.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا سجلات')))])
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final l = filtered[i];
                                return GlowCard(
                                  glow: const Color(0xFFB91C1C),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  elevation: 1,
                                  child: ListTile(
                                    dense: true,
                                    title: Text('${l['action'] ?? ''} — ${l['user'] ?? ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        '${l['page'] ?? ''}${(l['details'] ?? '') == '' ? '' : ' • ${l['details']}'}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    trailing: Text(
                                      (l['time'] ?? '').toString().substring(5),
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                                    ),
                                  ),
                                );
                              },
                            ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: users.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا بيانات')))])
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                              itemCount: users.length,
                              itemBuilder: (_, i) {
                                final u = users[i];
                                final online = u['online'] == true;
                                return GlowCard(
                                  glow: const Color(0xFFB91C1C),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  elevation: 1,
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 8,
                                      backgroundColor: online ? Colors.green : const Color(0xFFCBD5E1),
                                    ),
                                    title: Text('${u['name'] ?? ''} @${u['username'] ?? ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        'آخر دخول: ${u['lastLogin'] ?? '--'} • آخر إجراء: ${u['lastAction'] ?? '--'}',
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    trailing: online
                                        ? const Text('متصل', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 12))
                                        : const Text('', style: TextStyle(fontSize: 12)),
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
