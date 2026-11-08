// أسلوب بصري: كروت زرقاء داكنة بحد سفلي ذهبي + أيقونات ذهبية + شريط تنقل عائم (مستوحى من تطبيقات الخدمات المالية)
import 'dart:math' as math;
import 'package:flutter/material.dart';

const cpNavy1 = Color(0xFF0E2766);
const cpNavy2 = Color(0xFF1B4DA8);
const cpGold = Color(0xFFF5B82E);
const cpBg = Color(0xFFEEF1F6);

const cpHeaderGradient = LinearGradient(
  begin: Alignment.centerRight,
  end: Alignment.centerLeft,
  colors: [Color(0xFF0B1F57), Color(0xFF1B4DA8)],
);

/// كارت خدمة: تدرج أزرق + حد ذهبي سفلي + أيقونة ذهبية. عند الضغط: انضغاط ثم ارتداد للأيقونة وموجة ذهبية.
class CpCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  const CpCard({super.key, required this.icon, required this.label, required this.onTap, this.sub});

  @override
  State<CpCard> createState() => _CpCardState();
}

class _CpCardState extends State<CpCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    _c.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 230));
    if (mounted) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: _tap,
      child: AnimatedScale(
        scale: _down ? .95 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cpNavy1, cpNavy2]),
            boxShadow: const [BoxShadow(color: cpGold, offset: Offset(0, 4), blurRadius: 0)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(alignment: Alignment.center, children: [
              // موجة ذهبية عند الضغط
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) => Opacity(
                  opacity: _c.value == 0 ? 0.0 : (1 - _c.value).clamp(0.0, 1.0) * .35,
                  child: Container(
                    width: 30 + _c.value * 220,
                    height: 30 + _c.value * 220,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: cpGold),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, ch) {
                      final v = _c.value;
                      return Transform.rotate(
                        angle: math.sin(v * math.pi * 4) * (1 - v) * .35,
                        child: Transform.scale(scale: 1 + math.sin(v * math.pi) * .3, child: ch),
                      );
                    },
                    child: Icon(widget.icon, size: 40, color: cpGold),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
                  if (widget.sub != null) ...[
                    const SizedBox(height: 3),
                    Text(widget.sub!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cpGold)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class CpNavItem {
  final String id;
  final String label;
  final IconData icon;
  const CpNavItem(this.id, this.label, this.icon);
}

/// شريط تنقل سفلي عائم: العنصر المحدد داخل كبسولة أفتح وأيقونته ذهبية وتقفز عند الاختيار.
class CpNavBar extends StatelessWidget {
  final List<CpNavItem> items;
  final String current;
  final ValueChanged<String> onSelect;
  const CpNavBar({super.key, required this.items, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0B1F57), Color(0xFF16398C)]),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            for (final it in items)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(it.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: it.id == current ? Colors.white.withOpacity(.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TweenAnimationBuilder<double>(
                        key: ValueKey('${it.id}-${it.id == current}'),
                        tween: Tween(begin: it.id == current ? .5 : 1, end: 1),
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.elasticOut,
                        builder: (_, s, ch) => Transform.scale(scale: s, child: ch),
                        child: Icon(it.icon, size: 24, color: it.id == current ? cpGold : const Color(0xFF8FA6D6)),
                      ),
                      const SizedBox(height: 2),
                      Text(it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: it.id == current ? FontWeight.w900 : FontWeight.w600,
                              color: it.id == current ? Colors.white : const Color(0xFF8FA6D6))),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
