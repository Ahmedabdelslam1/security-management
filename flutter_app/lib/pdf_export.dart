// تصدير أي شاشة كـ PDF — للطباعة والإرسال (نفس هوية الويب: جدول أزرق + خط Times New Roman + اللوجو)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart' show rootBundle, Uint8List;
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// يبني جدول PDF من أي شاشة ويفتح خيارات الطباعة والإرسال
Future<void> exportTablePdf({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<String> headers,
  required List<double> widths,
  required List<List<String>> rows,
  List<String>? totalsRow,
  bool landscape = false,
  String? total,
  String totalLabel = 'الإجمالي',
}) async {
  if (rows.isEmpty && totalsRow == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد بيانات للطباعة'), backgroundColor: Colors.black54));
    return;
  }
  final base = pw.Font.ttf(await rootBundle.load('assets/fonts/TimesNewRoman.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/TimesNewRoman-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold));
  final blue = const pw.PdfColor.fromInt(0xFF1D4ED8);
  final light = const pw.PdfColor.fromInt(0xFFEAF1FE);

  pw.Widget cell(String t, {bool head = false, pw.PdfColor? bg, pw.PdfColor? fg}) {
    return pw.Container(
      color: bg,
      padding: pw.EdgeInsets.symmetric(vertical: landscape ? 3.5 : 5.3, horizontal: 3), // ≈ 32 سطر في الصفحة الطولية
      alignment: pw.Alignment.center,
      child: pw.Text(
        t,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: head ? bold : base,
          fontSize: head ? 10 : 10.5,
          color: fg ?? (head ? const pw.PdfColor.fromInt(0xFFFFFFFF) : const pw.PdfColor.fromInt(0xFF1E293B)),
        ),
      ),
    );
  }

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: pw.PdfColor.fromInt(0xFF1D4ED8)),
      children: [for (final h in headers) cell(h, head: true)],
    ),
    for (var i = 0; i < rows.length; i++)
      pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? light : null),
        children: [for (final v in rows[i]) cell(v)],
      ),
    if (totalsRow != null)
      pw.TableRow(
        decoration: pw.BoxDecoration(color: light),
        children: [for (var i = 0; i < totalsRow.length; i++) cell(totalsRow[i], head: true, fg: i == 0 ? null : blue)],
      ),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: landscape ? pw.PdfPageFormat.a4.landscape : pw.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
      maxPages: 100,
      textDirection: pw.TextDirection.rtl,
      build: (c) => [
        ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 15, color: blue)),
                        if (subtitle != null) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10.5, color: pw.PdfColor.fromInt(0xFF64748B))),
                      ],
                    ),
                  ),
                  if (total != null)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: blue, width: 1)),
                      child: pw.Column(children: [
                        pw.Text(totalLabel, style: pw.TextStyle(font: bold, fontSize: 9, color: blue)),
                        pw.Text(total!, style: pw.TextStyle(font: bold, fontSize: 14, color: blue)),
                      ]),
                    )
                  else
                    pw.SizedBox(width: 1),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: blue, width: 0.7),
                tableWidth: pw.TableWidth.max,
                children: tableRows,
                columnWidths: {for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i])},
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('عدد السجلات: ${rows.length}', style: const pw.TextStyle(fontSize: 9.5, color: pw.PdfColor.fromInt(0xFF94A3B8))),
              ),
        ],
      ],
    ),
  );
  final bytes = await doc.save();
  if (!context.mounted) return;
  await _pdfActionsSheet(context, bytes, title, headers, [...rows, if (totalsRow != null) totalsRow]);
}

String _csvCell(String v) => '"${v.replaceAll('"', '""')}"';

Future<void> _shareExcel(String title, List<String> headers, List<List<String>> rows) async {
  final b = StringBuffer('\uFEFF');
  b.writeln(headers.map(_csvCell).join(','));
  for (final r in rows) { b.writeln(r.map(_csvCell).join(',')); }
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${title.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '-')}.csv');
  await f.writeAsBytes(utf8.encode(b.toString()));
  await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: title);
}

Future<void> _pdfActionsSheet(BuildContext context, Uint8List bytes, String title, List<String> headers, List<List<String>> rows) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PDF جاهز', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('اختر الطباعة أو الإرسال', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.print, size: 19),
                label: const Text('معاينة وطباعة'),
                onPressed: () { Navigator.pop(context); Printing.layoutPdf(name: 'تقرير', onLayout: (_) async => bytes); },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                icon: const Icon(Icons.send, size: 19),
                label: const Text('إرسال PDF (واتساب / بريد / إلخ)'),
                onPressed: () { Navigator.pop(context); Printing.sharePdf(bytes: bytes, filename: 'تقرير-إدارة-الأمن.pdf'); },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                icon: const Icon(Icons.table_chart, size: 19),
                label: const Text('تصدير Excel'),
                onPressed: () { Navigator.pop(context); _shareExcel(title, headers, rows); },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
