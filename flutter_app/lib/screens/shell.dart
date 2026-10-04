// الهيكل الرئيسي: قائمة جانبية + شريط ساعة + تنقل بين الشاشات
import 'dart:async';
import 'package:flutter/material.dart';
import '../state.dart';
import 'attendance.dart';
import 'workers.dart';
import 'settlement.dart';
import 'reports.dart';
import 'gate.dart';
import 'users.dart';
import 'monitor.dart';
import 'settings.dart';

const _arDays = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  String _tab = 'attendance';
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    App.I.bootstrap(silent: true).catchError((_) {});
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = App.I;
    final u = app.user;
    if (u == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;

    final tabs = <_Tab>[
      if (u.can('attendance')) const _Tab('attendance', 'الحضور', Icons.checklist),
      if (u.can('attendance')) const _Tab('settlement', 'التسوية', Icons.payments_outlined),
      if (u.can('workers')) const _Tab('workers', 'العاملين', Icons.groups_outlined),
      if (u.can('reports')) const _Tab('reports', 'التقارير', Icons.bar_chart),
      if (u.can('gate')) const _Tab('gate', 'دفتر البوابة', Icons.door_front_door),
      if (u.isAdmin) const _Tab('users', 'المستخدمين', Icons.manage_accounts_outlined),
      if (u.isAdmin) const _Tab('monitor', 'المتابعة', Icons.monitor_heart_outlined),
    ];
    if (!tabs.any((t) => t.id == _tab) && tabs.isNotEmpty) _tab = tabs.first.id;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: Text(appTitle(_tab)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: Text(
                clockText(_now),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: cs.primary),
              accountName: Text(u.name),
              accountEmail: Text(u.isAdmin ? 'مدير النظام' : 'مستخدم'),
              currentAccountPicture: CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: cs.primary)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ...tabs.map((t) => ListTile(
                        selected: _tab == t.id,
                        selectedColor: cs.primary,
                        leading: Icon(t.icon),
                        title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () { Navigator.pop(context); setState(() => _tab = t.id); },
                      )),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () { Navigator.pop(context); setState(() => _tab = 'settings'); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('خروج', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('تأكيد'),
                          content: const Text('هل تريد تسجيل الخروج؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await App.I.logout();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _body(_tab),
    );
  }

  Widget _body(String tab) {
    switch (tab) {
      case 'attendance':
        return const AttendanceScreen();
      case 'workers':
        return const WorkersScreen();
      case 'settlement':
        return const SettlementScreen();
      case 'reports':
        return const ReportsScreen();
      case 'gate':
        return const GateScreen();
      case 'users':
        return const UsersScreen();
      case 'monitor':
        return const MonitorScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return Center(child: Text(appTitle(tab)));
    }
  }

  static String appTitle(String tab) {
    const m = {
      'attendance': 'الحضور',
      'settlement': 'التسوية',
      'workers': 'العاملين',
      'reports': 'التقارير',
      'gate': 'دفتر البوابة',
      'users': 'المستخدمين',
      'monitor': 'المتابعة',
      'settings': 'الإعدادات',
    };
    return m[tab] ?? 'إدارة الأمن';
  }

  static String clockText(DateTime d) {
    int h = d.hour % 12; if (h == 0) h = 12;
    final ap = d.hour < 12 ? 'ص' : 'م';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_arDays[d.weekday % 7]} ${two(d.day)}/${two(d.month)} — ${two(h)}:${two(d.minute)}:${two(d.second)} $ap';
  }
}

class _Tab {
  final String id;
  final String label;
  final IconData icon;
  const _Tab(this.id, this.label, this.icon);
}
