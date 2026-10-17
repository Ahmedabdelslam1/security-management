// آلة حاسبة متقدمة: علمية + ذاكرة + تاريخ — بدون مكتبات خارجية
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ===== محلل التعبيرات (recursive descent) =====
class _Parser {
  final String s;
  int i = 0;
  final bool deg;
  _Parser(this.s, this.deg);

  void _ws() { while (i < s.length && s[i] == ' ') i++; }
  bool _eat(String t) {
    _ws();
    if (s.startsWith(t, i)) { i += t.length; return true; }
    return false;
  }

  double parse() { final v = _expr(); _ws(); if (i < s.length) throw 'خطأ'; return v; }

  double _expr() {
    var v = _term();
    while (true) {
      if (_eat('+')) v += _term();
      else if (_eat('−') || _eat('-')) v -= _term();
      else return v;
    }
  }

  double _term() {
    var v = _unary();
    while (true) {
      if (_eat('×') || _eat('*')) v *= _unary();
      else if (_eat('÷') || _eat('/')) { final d = _unary(); v = d == 0 ? throw 'قسمة على صفر' : v / d; }
      else return v;
    }
  }

  double _unary() {
    _ws();
    if (_eat('−') || _eat('-')) return -_unary();
    if (_eat('+')) return _unary();
    return _power();
  }

  double _power() {
    final base = _postfix();
    if (_eat('^')) {
      final exp = _unary(); // ربط يمين
      var r = m.pow(base, exp).toDouble();
      if (r.isNaN) throw 'خطأ';
      return r;
    }
    return base;
  }

  double _postfix() {
    var v = _atom();
    while (true) {
      if (_eat('!')) {
        if (v < 0 || v != v.truncateToDouble() || v > 170) throw 'خطأ';
        var f = 1.0;
        for (var k = 2; k <= v; k++) f *= k;
        v = f;
      } else if (_eat('%')) {
        v = v / 100;
      } else return v;
    }
  }

  double _atom() {
    _ws();
    // دوال
    for (final fn in ['sin', 'cos', 'tan', 'log', 'ln']) {
      if (s.startsWith(fn, i)) {
        i += fn.length;
        final arg = _atom();
        final rad = deg ? arg * m.pi / 180 : arg;
        switch (fn) {
          case 'sin': return m.sin(rad);
          case 'cos': return m.cos(rad);
          case 'tan':
            if (deg && (arg % 180 == 90)) throw 'خطأ';
            return m.tan(rad);
          case 'log': return arg <= 0 ? throw 'خطأ' : m.log(arg) / m.ln10;
          case 'ln': return arg <= 0 ? throw 'خطأ' : m.log(arg);
        }
      }
    }
    if (_eat('√')) {
      final v = _atom();
      return v < 0 ? throw 'خطأ' : m.sqrt(v);
    }
    if (_eat('π')) return m.pi;
    if (_eat('e')) return m.e;
    if (_eat('(')) {
      final v = _expr();
      if (!_eat(')')) throw 'خطأ';
      return v;
    }
    _ws();
    final st = i;
    while (i < s.length && (s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57 || s[i] == '.')) i++;
    if (st == i) throw 'خطأ';
    final num = double.tryParse(s.substring(st, i));
    if (num == null) throw 'خطأ';
    return num;
  }
}

String _fmt(double v) {
  if (v.isNaN || v.isInfinite) return 'خطأ';
  var r = v.toStringAsFixed(10);
  r = r.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return r;
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String expr = '';
  double mem = 0, ans = 0;
  bool deg = true;
  final List<String> history = [];

  String get _liveResult {
    if (expr.isEmpty) return '';
    try {
      return _fmt(_Parser(expr, deg).parse());
    } catch (_) {
      return '';
    }
  }

  void _append(String t) => setState(() => expr += t);
  void _back() => setState(() { if (expr.isNotEmpty) expr = expr.substring(0, expr.length - 1); });

  void _equals() {
    if (expr.isEmpty) return;
    try {
      final v = _Parser(expr, deg).parse();
      ans = v;
      final line = '$expr = ${_fmt(v)}';
      setState(() {
        history.insert(0, line);
        if (history.length > 12) history.removeLast();
        expr = _fmt(v);
      });
    } catch (e) {
      setState(() => expr = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveResult;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('آلة حاسبة متقدمة'), actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withOpacity(.18)),
              onPressed: () => setState(() => deg = !deg),
              child: Text(deg ? 'DEG' : 'RAD', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
        body: Column(
          children: [
            // شاشة العرض
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              color: const Color(0xFFF6F5FB),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      expr.isEmpty ? '0' : expr,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: expr.contains('خطأ') ? Colors.red : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    live.isEmpty ? ' ' : '= $live',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF7C5CFC)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (mem != 0) const Text('M ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
                      Text('ANS ${_fmt(ans)}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                ],
              ),
            ),
            // الأزرار
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _row(['sin(', 'cos(', 'tan(', 'ln(', 'log('], List.generate(5, (k) => () => _append(['sin(', 'cos(', 'tan(', 'ln(', 'log('][k])), fg: const Color(0xFF6D28D9)),
                    _row(['(', ')', '√(', '^2', '!'], List.generate(5, (k) => () => _append(['(', ')', '√(', '^2', '!'][k])), fg: const Color(0xFF6D28D9)),
                    _row(['7', '8', '9', '÷', 'C'], List.generate(4, (k) => () => _append(['7', '8', '9', '÷'][k]))..add(() => setState(() => expr = '')), fg: const Color(0xFF6D28D9)),
                    _row(['4', '5', '6', '×', '⌫'], List.generate(4, (k) => () => _append(['4', '5', '6', '×'][k]))..add(_back), fg: const Color(0xFF6D28D9)),
                    _row(['1', '2', '3', '−', '%'], List.generate(5, (k) => () => _append(['1', '2', '3', '−', '%'][k])), fg: const Color(0xFF6D28D9)),
                    _row(['π', 'e', '0', '.', '+'], List.generate(5, (k) => () => _append(['π', 'e', '0', '.', '+'][k])), fg: const Color(0xFF6D28D9)),
                    _row(['MC', 'MR', 'M+', 'ANS', '='], [
                      () => setState(() => mem = 0),
                      () => _append(_fmt(mem)),
                      () => setState(() => mem += (_tryEval() ?? 0)),
                      () => _append(_fmt(ans)),
                      _equals,
                    ], fg: const Color(0xFF15803D)),
                  ],
                ),
              ),
            ),
            // التاريخ
            if (history.isNotEmpty)
              SizedBox(
                height: 74,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: history.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ActionChip(
                      label: Text(history[i], style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => setState(() => expr = history[i].split(' = ').first),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double? _tryEval() {
    try {
      return _Parser(expr, deg).parse();
    } catch (_) {
      return null;
    }
  }

  Widget _row(List<String> labels, List<VoidCallback> fns, {Color fg = const Color(0xFF6D28D9)}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var k = 0; k < labels.length; k++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF6F5FB),
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: fns[k],
                child: Text(labels[k], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ],
    );
  }
}
