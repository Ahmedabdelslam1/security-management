// الهيكل الرئيسي: تنقل بأيقونات ملونة (هوية الويب) + ساعة حية + مزامنة تلقائية + تحديث تلقائي
import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../updater.dart';
import '../widgets.dart';
import 'attendance.dart';
import 'workers.dart';
import 'settlement.dart';
import 'reports.dart';
import 'gate.dart';
import 'procs.dart';
import 'home.dart';
import 'users.dart';
import 'monitor.dart';
import 'settings.dart';

const _arDays = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  String _tab = 'home';
  Timer? _clock;
  Timer? _sync;
  Timer? _updateCheck;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    App.I.bootstrap(silent: true).catchError((_) {});
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // مزامنة فورية مع الويب: سحب أي إضافة/تعديل كل 15 ثانية
    _sync = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!App.I.loading) App.I.syncIfChanged().catchError((_) {});
    });
    // فحص التحديث عند البدء ثم كل 6 ساعات
    Future.delayed(const Duration(seconds: 4), () { if (mounted) autoUpdate(context); });
    _updateCheck = Timer.periodic(const Duration(hours: 6), (_) {
      if (mounted) autoUpdate(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      App.I.bootstrap(silent: true).catchError((_) {});
      autoUpdate(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _sync?.cancel();
    _updateCheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = App.I;
    final u = app.user;
    if (u == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final tabs = <_Tab>[
      const _Tab('home', 'الرئيسية', Icons.home),
      if (u.can('attendance')) const _Tab('attendance', 'الحضور', Icons.checklist),
      if (u.can('attendance')) const _Tab('settlement', 'التسوية', Icons.payments_outlined),
      if (u.can('workers')) const _Tab('workers', 'العاملين', Icons.groups_outlined),
      if (u.can('reports')) const _Tab('reports', 'التقارير', Icons.bar_chart),
      if (u.can('gate')) const _Tab('gate', 'دفتر البوابة', Icons.door_front_door),
      if (u.can('gate')) const _Tab('procs', 'الإجراءات اليومية', Icons.assignment_outlined),
      if (u.isAdmin) const _Tab('users', 'المستخدمين', Icons.manage_accounts_outlined),
      if (u.isAdmin) const _Tab('monitor', 'المتابعة', Icons.monitor_heart_outlined),
    ];
    if (!tabs.any((t) => t.id == _tab) && tabs.isNotEmpty) _tab = tabs.first.id;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 'home') setState(() => _tab = 'home');
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(appTitle(_tab)),
        centerTitle: true,
        actions: [
          // زر الرجوع للصفحة الرئيسية — ظاهر في كل الشاشات ما عدا الرئيسية نفسها
          if (_tab != 'home')
            IconButton(
              tooltip: 'الصفحة الرئيسية',
              onPressed: () => setState(() => _tab = 'home'),
              icon: const Icon(Icons.home_outlined, size: 21),
            ),
          // الساعة الحية: اليوم + التاريخ + الوقت — في كل الشاشات
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_arDays[_now.weekday % 7]} ${_now.day} ${_arMonths[_now.month - 1]}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(_now.second % 2),
                    tween: Tween(begin: 0.6, end: 1),
                    duration: const Duration(milliseconds: 500),
                    builder: (c, t, ch) => Opacity(opacity: .6 + t * .4, child: ch),
                    child: Text(
                      clockText(_now),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // زر تحديث يدوي (مزامنة فورية)
          IconButton(
            tooltip: 'مزامنة الآن',
            onPressed: () {
              App.I.bootstrap().catchError((_) {});
            },
            icon: const Icon(Icons.sync, size: 20),
          ),
        ],
      ),
      drawer: _drawer(context, u, tabs),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        // الاستماع لـ App يجعل كل شاشة تُعاد رسمها فور وصول بيانات جديدة من الويب
        child: ListenableBuilder(
          listenable: App.I,
          key: ValueKey(_tab),
          builder: (c, _) => _body(_tab),
        ),
      ),
    ));
  }

  Widget _drawer(BuildContext context, AppUser u, List<_Tab> tabs) {
    final items = <(String, String, IconData)>[
      ...tabs.map((t) => (t.id, t.label, t.icon)),
      ('settings', 'الإعدادات', Icons.settings_outlined),
    ];
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7C5CFC), Color(0xFFA78BFA)])),
            accountName: Text(u.name),
            accountEmail: Text(u.isAdmin ? 'مدير النظام' : 'مستخدم'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Image.asset('assets/icon_tile.png', fit: BoxFit.cover),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (var i = 0; i < items.length; i++)
                  SlideIn(
                    index: i,
                    child: _drawerTile(items[i].$1, items[i].$2, items[i].$3),
                  ),
                const Divider(height: 20),
                SlideIn(
                  index: items.length,
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('خروج', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
                    onTap: () async {
                      Navigator.pop(context);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('تأكيد'),
                          content: const Text('هل تريد تسجيل الخروج؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('خروج')),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(String id, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final sel = _tab == id;
    final colors = tabColors[id] ?? const [0xFFBAE6FD, 0xFF0369A1];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: sel
              ? const LinearGradient(colors: [Color(0xFF7C5CFC), Color(0xFFA78BFA)])
              : null,
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          selected: sel,
          selectedColor: Colors.white,
          leading: IconTile(
            icon: icon,
            bg: Color(colors[0]),
            fg: Color(colors[1]),
            size: sel ? 36 : 32,
          ),
          title: Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: sel ? Colors.white : Colors.black87,
              )),
          onTap: () {
            Navigator.pop(context);
            if (_tab != id) setState(() => _tab = id);
          },
        ),
      ),
    );
  }

  Widget _body(String tab) {
    switch (tab) {
      case 'home':
        return HomeScreen(onOpen: (id) => setState(() => _tab = id));
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
      case 'procs':
        return const ProcsScreen();
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
      'home': 'إدارة الأمن',
      'attendance': 'الحضور',
      'settlement': 'التسوية',
      'workers': 'العاملين',
      'reports': 'التقارير',
      'gate': 'دفتر البوابة',
      'procs': 'الإجراءات اليومية',
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
    return '${two(h)}:${two(d.minute)}:${two(d.second)} $ap';
  }
}

class _Tab {
  final String id;
  final String label;
  final IconData icon;
  const _Tab(this.id, this.label, this.icon);
}
