// مكونات مشتركة: بحث، أنيميشن دخول، بلاط أيقونات ملونة — بنفس هوية نسخة الويب
import 'package:flutter/material.dart';

// ===== صندوق البحث (يظهر في كل الشاشات) =====
class SearchBox extends StatelessWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  const SearchBox({super.key, required this.hint, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: value.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(''),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

// فلترة نصية موحدة: تطابق جزئي غير حساس لحالة الأحرف
bool txtMatch(String query, Iterable<String?> fields) {
  final q = query.trim();
  if (q.isEmpty) return true;
  for (final f in fields) {
    if (f != null && f.toLowerCase().contains(q.toLowerCase())) return true;
  }
  return false;
}

// ===== أنيميشن دخول العناصر (ظهور تدريجي + انزلاق خفيف) =====
class SlideIn extends StatelessWidget {
  final Widget child;
  final int index; // للتتابع
  final Duration duration;
  const SlideIn({super.key, required this.child, this.index = 0, this.duration = const Duration(milliseconds: 350)});

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: (index < 8 ? index * 40 : 320));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + delay,
      curve: Curves.easeOutCubic,
      builder: (c, t, ch) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: ch),
      ),
      child: child,
    );
  }
}

// ===== بلاط أيقونة ملون زي شريط التنقل في الويب =====
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;
  const IconTile({super.key, required this.icon, required this.bg, required this.fg, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, Colors.white, 0.35)!],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: Color.lerp(bg, Colors.white, 0.0)!.withOpacity(0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: fg, size: size * 0.55),
    );
  }
}

// ألوان تبويبات الصفحات — مطابقة لنسخة الويب
const tabColors = <String, List<int>>{
  'attendance': [0xFFDBEAFE, 0xFF1D4ED8], // حضور — أزرق
  'settlement': [0xFFBBF7D0, 0xFF15803D], // تسوية — أخضر
  'workers': [0xFFFDE68A, 0xFFB45309], // عاملين — أصفر
  'reports': [0xFFFBCFE8, 0xFFBE185D], // تقارير — وردي
  'gate': [0xFFDDD6FE, 0xFF6D28D9], // بوابة — بنفسجي
  'users': [0xFF99F6E4, 0xFF0F766E], // مستخدمين — تركواز
  'monitor': [0xFFFECACA, 0xFFB91C1C], // متابعة — أحمر
  'settings': [0xFFBAE6FD, 0xFF0369A1], // إعدادات — سماوي
};

// ===== كارت متوهج بألوان مميزة لكل شاشة + نبض أنيميشن مستمر =====
class GlowCard extends StatefulWidget {
  final Widget child;
  final Color glow;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final double elevation;
  final ShapeBorder? shape;
  const GlowCard({
    super.key,
    required this.child,
    required this.glow,
    this.color,
    this.margin,
    this.elevation = 2,
    this.shape,
  });

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(13));
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        final opacity = 0.22 + t * 0.33;
        final blur = 9.0 + t * 11.0;
        return Container(
          margin: widget.margin,
          decoration: ShapeDecoration(
            shape: shape,
            shadows: [
              BoxShadow(
                color: widget.glow.withOpacity(opacity),
                blurRadius: blur,
                spreadRadius: 0.5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: widget.color ?? Colors.white,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        );
      },
    );
  }
}
