// الصفحة الرئيسية: كروت متوهجة نابضة بالأنيميشن — الضغط يفتح الشاشة أو الأداة
import 'package:flutter/material.dart';
import '../state.dart';
import '../widgets.dart';
import 'calculator.dart';
import 'scanner.dart';

class HomeScreen extends StatelessWidget {
  final void Function(String tab) onOpen;
  const HomeScreen({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final u = App.I.user;
    final pages = <(String, String, IconData)>[
      if (u?.can('attendance') ?? false) ('attendance', 'الحضور', Icons.checklist),
      if (u?.can('workers') ?? false) ('workers', 'العاملين', Icons.groups_outlined),
      if (u?.can('attendance') ?? false) ('settlement', 'التسوية', Icons.payments_outlined),
      if (u?.can('gate') ?? false) ('gate', 'دفتر البوابة', Icons.door_front_door),
      if (u?.can('procs') ?? false) ('procs', 'الإجراءات اليومية', Icons.assignment_outlined),
      if (u?.can('reports') ?? false) ('reports', 'التقارير', Icons.bar_chart),
      if (u?.isAdmin ?? false) ('users', 'المستخدمين', Icons.manage_accounts_outlined),
      if (u?.isAdmin ?? false) ('monitor', 'المتابعة', Icons.monitor_heart_outlined),
      ('settings', 'الإعدادات', Icons.settings_outlined),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlideIn(
            child: Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('أهلاً بك 👋',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF5B21B6))),
                  const SizedBox(height: 2),
                  Text('اختر الشاشة أو الأداة اللي محتاجها',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black54)),
                ],
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.06,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < pages.length; i++)
                SlideIn(
                  index: i,
                  child: _HomeCard(
                    icon: pages[i].$3,
                    label: pages[i].$2,
                    colors: tabColors[pages[i].$1] ?? const [0xFFDDD6FE, 0xFF6D28D9],
                    onTap: () => onOpen(pages[i].$1),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SlideIn(
            index: 9,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 10),
              child: Text('الأدوات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF5B21B6))),
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.06,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              SlideIn(
                index: 10,
                child: _HomeCard(
                  icon: Icons.calculate,
                  label: 'آلة حاسبة متقدمة',
                  colors: const [0xFFDDD6FE, 0xFF6D28D9],
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const CalculatorScreen())),
                ),
              ),
              SlideIn(
                index: 11,
                child: _HomeCard(
                  icon: Icons.qr_code_scanner,
                  label: 'باركود ومستندات',
                  colors: const [0xFFBAE6FD, 0xFF0369A1],
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ScannerScreen())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<int> colors;
  final VoidCallback onTap;
  const _HomeCard({required this.icon, required this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = Color(colors[0]);
    final fg = Color(colors[1]);
    return GlowCard(
      glow: fg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTile(icon: icon, bg: bg, fg: fg, size: 46),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
