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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFC),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F5FB),
        useMaterial3: true,
        fontFamily: 'Cairo',
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
