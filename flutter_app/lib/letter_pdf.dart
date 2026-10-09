// خطاب الاعتماد PDF — للطباعة والإرسال، بنفس شكل الويب (خط عربي، جدول أزرق، تفقيط)
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'models.dart';

class LetterRow {
  final String name;
  final int days;
  final double wage, gross, ot, b, d, tax, net;
  const LetterRow(this.name, this.days, this.wage, this.gross, this.ot, {this.b = 0, this.d = 0, this.tax = 0, this.net = 0});
  double get total => gross + ot;
}

/// يبني PDF خطاب الاعتماد كاملًا: ترويسة اللوجو + المعنون + التفقيط + جدول التسوية + الإجمالي
Future<Uint8List> buildLetterPdf({
  required List<LetterRow> rows,
  required String addressee,
  required String from,
  required String to,
  required String amountWords,
}) async {
  final fontData = await rootBundle.load('assets/fonts/TimesNewRoman.ttf');
  final boldData = await rootBundle.load('assets/fonts/TimesNewRoman-Bold.ttf');
  final ttf = pw.Font.ttf(fontData);
  final bold = pw.Font.ttf(boldData);

  final doc = pw.Document(theme: pw.ThemeData.withFont(base: ttf, bold: bold));
  final blue = const pw.PdfColor.fromInt(0xFF1D4ED8);
  final light = const pw.PdfColor.fromInt(0xFFEAF1FE);
  final gray = const pw.PdfColor.fromInt(0xFF64748B);

  final tot = _r2(rows.fold<double>(0, (s, r) => s + r.net)); // الصافي = الإجمالي + المكافآت - الخصومات - الضرائب
  final gTot = _r2(rows.fold<double>(0, (s, r) => s + r.gross));
  final days = rows.fold<int>(0, (s, r) => s + r.days);
  final txh = _r2(rows.fold<double>(0, (s, r) => s + r.ot));
  final tb = _r2(rows.fold<double>(0, (s, r) => s + r.b));
  final td = _r2(rows.fold<double>(0, (s, r) => s + r.d));
  final tt = _r2(rows.fold<double>(0, (s, r) => s + r.tax));

  doc.addPage(
    pw.MultiPage(
      pageFormat: pw.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 40),
      maxPages: 30,
      textDirection: pw.TextDirection.rtl,
      build: (c) => [
        pw.SizedBox(height: 6),
        ...[
              pw.Align(
                alignment: pw.Alignment.topRight,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
                  child: pw.Text('السيد / مدير $addressee', style: pw.TextStyle(font: bold, fontSize: 14)),
                ),
              ),
              pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('تحية طيبة وبعد ،،،', style: const pw.TextStyle(fontSize: 12.5))),
              pw.SizedBox(height: 8),
              pw.RichText(
                textAlign: pw.TextAlign.right,
                text: pw.TextSpan(
                  text: 'برجاء من سيادتكم التكرم بالموافقة على اعتماد مبلغ ( ',
                  style: const pw.TextStyle(fontSize: 12.5),
                  children: [
                    pw.TextSpan(text: '$tot', style: pw.TextStyle(font: bold, fontSize: 13, color: blue)),
                    const pw.TextSpan(text: ' ) فقط وقدرة : ( '),
                    pw.TextSpan(text: amountWords, style: pw.TextStyle(font: bold, fontSize: 12.5, color: blue)),
                    const pw.TextSpan(text: ' )'),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.RichText(
                textAlign: pw.TextAlign.right,
                text: pw.TextSpan(
                  text: 'وذلك قيمة أجور أيام حضور العمال اليوميه الاتى أسماؤهم خلال الفترة من ',
                  style: const pw.TextStyle(fontSize: 12.5),
                  children: [
                    pw.TextSpan(text: from, style: pw.TextStyle(font: bold, fontSize: 12.5, color: blue)),
                    const pw.TextSpan(text: ' حتى '),
                    pw.TextSpan(text: to, style: pw.TextStyle(font: bold, fontSize: 12.5, color: blue)),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: blue, width: 1.2), borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text('تسويه', style: pw.TextStyle(font: bold, fontSize: 14, color: blue)),
                ),
              ),
              pw.SizedBox(height: 8),
              _table(rows, blue, light, bold, days, txh, tb, td, tt, gTot, tot),
              pw.SizedBox(height: 18),
              pw.Center(child: pw.Text('ولسيادتكم فائق الاحترام والتقدير', style: pw.TextStyle(font: bold, fontSize: 12.5))),
              pw.SizedBox(height: 26),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تحريرًا في: ${_today()}', style: pw.TextStyle(fontSize: 11.5, color: gray)),
                  pw.Text('يعتمد ،،', style: pw.TextStyle(font: bold, fontSize: 12.5)),
                ],
              ),
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _table(List<LetterRow> rows, pw.PdfColor blue, pw.PdfColor light, pw.Font bold, int days, double txh, double tb, double td, double tt, double gTot, double tot) {
  const headers = ['اسم العامل', 'عدد الأيام', 'أجر اليوم', 'الإجمالي', 'إضافي', 'المكافآت', 'الخصومات', 'الضرائب', 'الصافي', 'ملاحظات'];
  final widths = [3.0, 1.0, 1.0, 1.2, 1.0, 1.0, 1.1, 1.0, 1.3, 1.2];
  pw.Widget cell(String t, {bool head = false, bool isBold = false, pw.PdfColor? bg, pw.PdfColor? fg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        t,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: head || isBold ? bold : null,
          fontSize: head ? 10.5 : 11,
          color: fg ?? (head ? const pw.PdfColor.fromInt(0xFFFFFFFF) : null),
          fontWeight: head ? pw.FontWeight.bold : null,
        ),
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: blue, width: 0.7),
    tableWidth: pw.TableWidth.max,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: pw.PdfColor.fromInt(0xFF1D4ED8)),
        children: [for (var i = 0; i < headers.length; i++) cell(headers[i], head: true)],
      ),
      for (final r in rows)
        pw.TableRow(
          decoration: pw.BoxDecoration(color: rows.indexOf(r).isEven ? light : null),
          children: [
            cell(r.name, isBold: true),
            cell('${r.days}'),
            cell(_trimNum(r.wage)),
            cell(_trimNum(r.gross)),
            cell(r.ot > 0 ? _trimNum(r.ot) : '—'),
            cell(r.b > 0 ? _trimNum(r.b) : '—'),
            cell(r.d > 0 ? _trimNum(r.d) : '—'),
            cell(r.tax > 0 ? _trimNum(r.tax) : '—'),
            cell(_trimNum(r.net), isBold: true, fg: blue),
            cell(''),
          ],
        ),
      pw.TableRow(
        decoration: pw.BoxDecoration(color: light),
        children: [
          cell('الإجمالي', head: true),
          cell('$days', head: true),
          cell('', head: true),
          cell(_trimNum(gTot), head: true),
          cell(txh > 0 ? _trimNum(txh) : '—', head: true),
          cell(tb > 0 ? _trimNum(tb) : '—', head: true),
          cell(td > 0 ? _trimNum(td) : '—', head: true),
          cell(tt > 0 ? _trimNum(tt) : '—', head: true),
          cell(_trimNum(tot), head: true, fg: blue),
          cell('', head: true),
        ],
      ),
    ],
    columnWidths: {
      for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]),
    },
  );
}

String _today() {
  final d = DateTime.now();
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

double _r2(double x) => (x * 100).round() / 100;
String _trimNum(double x) {
  final r = _r2(x);
  return r == r.truncateToDouble() ? r.truncate().toString() : r.toStringAsFixed(2);
}
