import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'home.dart';
import 'login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // أي خطأ في الواجهة يظهر نصه بدل الشاشة الفارغة
  ErrorWidget.builder = (FlutterErrorDetails d) => Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText('خطأ في الواجهة:\n${d.exceptionAsString()}', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ),
        ),
      );
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFC)),
        useMaterial3: true,
        fontFamily: 'TimesNewRoman',
        scaffoldBackgroundColor: const Color(0xFFF6F5FB),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF7C5CFC), foregroundColor: Colors.white, centerTitle: true),
      ),
      home: const Start(),
    );
  }
}

/// البداية: لو توجد جلسة محفوظة → الرئيسية، وإلا → الدخول (بدون أي انتظار للشبكة)
class Start extends StatefulWidget {
  const Start({super.key});
  @override
  State<Start> createState() => _StartState();
}

class _StartState extends State<Start> {
  Widget? _next;

  @override
  void initState() {
    super.initState();
    Api.token().then((t) {
      if (mounted) setState(() => _next = t.isNotEmpty ? const HomeScreen() : const LoginScreen());
    }).catchError((_) {
      if (mounted) setState(() => _next = const LoginScreen());
    });
    // حارس: لو تعذرت قراءة التخزين نعرض الدخول
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _next == null) setState(() => _next = const LoginScreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    return _next ??
        Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('v$appVersion', style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]),
          ),
        );
  }
}
