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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12.5),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12),
          prefixIcon: const Icon(Icons.search, size: 17),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 28),
          suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 28),
          suffixIcon: value.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onChanged(''),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
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
  'home': [0xFFEDE9FE, 0xFF5B21B6], // الرئيسية — بنفسجي غامق
  'attendance': [0xFFDBEAFE, 0xFF1D4ED8], // حضور — أزرق
  'settlement': [0xFFBBF7D0, 0xFF15803D], // تسوية — أخضر
  'workers': [0xFFFDE68A, 0xFFB45309], // عاملين — أصفر
  'reports': [0xFFFBCFE8, 0xFFBE185D], // تقارير — وردي
  'gate': [0xFFDDD6FE, 0xFF6D28D9], // بوابة — بنفسجي
  'procs': [0xFFFED7AA, 0xFFC2410C], // إجراءات يومية — برتقالي
  'users': [0xFF99F6E4, 0xFF0F766E], // مستخدمين — تركواز
  'monitor': [0xFFFECACA, 0xFFB91C1C], // متابعة — أحمر
  'chat': [0xFFBBF7D0, 0xFF16A34A],
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


// ===== لون ثابت لكل عامل + أيقونة دائرية (تُستخدم في كل الشاشات) =====
const List<Color> kWorkerPalette = [Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF7C3AED), Color(0xFF0D9488), Color(0xFFDC2626), Color(0xFF0369A1)];
Color workerColor(String id) => kWorkerPalette[id.hashCode.abs() % kWorkerPalette.length];
Widget workerAvatar(String id, {double size = 26}) => Container(
      width: size, height: size,
      decoration: BoxDecoration(color: workerColor(id), shape: BoxShape.circle),
      child: Icon(Icons.person, size: size * .62, color: Colors.white),
    );


// ===== تطبيع النص العربي للبحث: حذف التشكيل، توحيد الهمزات والياء والتاء المربوطة، الأرقام العربية → لاتينية =====
String normAr(String x) {
  var s = x.toLowerCase();
  s = s.replaceAll(RegExp('[\u064B-\u0652\u0640]'), '');
  s = s.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

// بحث عربي مُطبَّع في عدة حقول
bool txtMatchAr(String query, Iterable<String?> fields) {
  final q = normAr(query.trim());
  if (q.isEmpty) return true;
  for (final f in fields) {
    if (f != null && normAr(f).contains(q)) return true;
  }
  return false;
}

// ===== أزرار صغيرة مشتركة للشرائح العلوية =====
class MiniChipButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;
  const MiniChipButton({super.key, required this.label, this.icon, this.onTap, this.color = const Color(0xFF6D28D9), this.filled = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? color.withOpacity(.14) : Colors.white,
          border: Border.all(color: color.withOpacity(.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

// أيقونة صغيرة ملونة (تعديل / حذف / ...)
Widget miniIconBtn(IconData icon, Color color, VoidCallback? onTap, {String? tip}) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      style: IconButton.styleFrom(backgroundColor: color.withOpacity(.12)),
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: color),
    );

// ===== شريط علوي مصغّر: خط وحقول أصغر لكل أدوات الفلترة (التاريخ/البحث/الأماكن/التبويبات) =====
Widget compactMaterial({Color? color, double elevation = 0, Widget? child}) => Builder(builder: (context) {
      final th = Theme.of(context);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(.82)),
        child: Theme(
          data: th.copyWith(
            visualDensity: VisualDensity.compact,
            inputDecorationTheme: th.inputDecorationTheme.copyWith(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
          ),
          child: Material(color: color, elevation: elevation, child: child),
        ),
      );
    });
