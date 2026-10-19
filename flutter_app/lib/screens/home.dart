// الصفحة الرئيسية: كروت متوهجة نابضة بالأنيميشن — الضغط يفتح الشاشة أو الأداة
import 'package:flutter/material.dart';
import '../state.dart';
import '../widgets.dart';
import 'calculator.dart';
import 'scanner.dart';

class HomeScreen extends StatelessWidget {
  final void Function(String tab) onOpen;
  const HomeScreen({super.key, required this.onOpen});

  static const _lc = [0xFF2563EB, 0xFF16A34A, 0xFFEA580C, 0xFF9333EA, 0xFFDB2777, 0xFF0891B2, 0xFFCA8A04, 0xFFDC2626, 0xFF4F46E5, 0xFF0D9488];
  static const _li = [Icons.factory, Icons.apartment, Icons.store, Icons.local_shipping, Icons.construction, Icons.local_hospital, Icons.school, Icons.shield, Icons.home_work, Icons.holiday_village];

  @override
  Widget build(BuildContext context) {
    final u = App.I.user;
    final pages = <(String, String, IconData)>[
      if (u?.can('attendance') ?? false) ('attendance', 'الحضور', Icons.checklist),
      if (u?.can('workers') ?? false) ('workers', 'العاملين', Icons.groups_outlined),
      if (u?.can('settlement') ?? false) ('settlement', 'التسوية', Icons.payments_outlined),
      if (u?.can('gate') ?? false) ('gate', 'دفتر البوابة', Icons.door_front_door),
      if (u?.can('reports') ?? false) ('reports', 'التقارير', Icons.bar_chart),
      if (u?.isAdmin ?? false) ('users', 'المستخدمين', Icons.manage_accounts_outlined),
      if (u?.isAdmin ?? false) ('monitor', 'المتابعة', Icons.monitor_heart_outlined),
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
          if ((u?.can('attendance') ?? false) && App.I.allLocs.isNotEmpty) ...[
            const SizedBox(height: 16),
            SlideIn(
              index: 8,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 10),
                child: Text('أماكن الحضور', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF5B21B6))),
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
                for (var i = 0; i < App.I.allLocs.length; i++)
                  SlideIn(
                    index: i,
                    child: Builder(builder: (_) {
                      final l = App.I.allLocs[i];
                      final ids = <String>{
                        for (final w in App.I.workers) if (w.loc == l) w.id,
                        for (final r in App.I.att) if (r.loc == l) r.wid,
                      };
                      final c = _lc[i % _lc.length];
                      return _HomeCard(
                        icon: _li[i % _li.length],
                        label: '$l\n${ids.length} عامل',
                        colors: [Color(c).withOpacity(.15).value, c],
                        onTap: () {
                          App.I.attLoc = l;
                          onOpen('attendance');
                        },
                      );
                    }),
                  ),
              ],
            ),
          ],
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
