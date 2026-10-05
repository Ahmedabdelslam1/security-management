import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

void main() {
  runApp(const SecurityApp());
}

class SecurityApp extends StatelessWidget {
  const SecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C5CFC),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'إدارة الأمن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: cs,
        useMaterial3: true,
        fontFamily: 'TimesNewRoman',
        scaffoldBackgroundColor: const Color(0xFFF6F5FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF7C5CFC),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shadowColor: const Color(0x667C5CFC), // توهج بنفسجي حول كل الكروت
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C5CFC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'TimesNewRoman'),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'TimesNewRoman'),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF7C5CFC), width: 1.6),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
                const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'TimesNewRoman')),
          ),
        ),
      ),
      home: const Gate(),
    );
  }
}

// يقرر: شاشة الدخول أو التطبيق حسب الجلسة المحفوظة
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool _busy = true;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final t = await Api.getToken();
    if (t == null || t.isEmpty) {
      setState(() { _busy = false; });
      return;
    }
    try {
      await Api.auth('ping');
      setState(() { _valid = true; _busy = false; });
    } catch (_) {
      await Api.clear();
      setState(() { _valid = false; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _valid ? const Shell() : const LoginScreen();
  }
}
