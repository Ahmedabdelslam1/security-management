// تصدير أي شاشة كـ PDF — للطباعة والإرسال (نفس هوية الويب: جدول أزرق + خط Cairo + اللوجو)
import 'package:flutter/material.dart';
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
}) async {
  if (rows.isEmpty && totalsRow == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد بيانات للطباعة'), backgroundColor: Colors.black54));
    return;
  }
  final base = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
  Uint8List? logo;
  try {
    logo = (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
  } catch (_) {}
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold));
  final blue = const pw.PdfColor.fromInt(0xFF1D4ED8);
  final light = const pw.PdfColor.fromInt(0xFFEAF1FE);

  pw.Widget cell(String t, {bool head = false, pw.PdfColor? bg, pw.PdfColor? fg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(vertical: 4.5, horizontal: 4),
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
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
      maxPages: 30,
      textDirection: pw.TextDirection.rtl,
      build: (c) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) pw.Image(pw.MemoryImage(logo), width: 64, height: 40) else pw.Text(''),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 15, color: blue)),
                        if (subtitle != null) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10.5, color: pw.PdfColor.fromInt(0xFF64748B))),
                      ],
                    ),
                  ),
                  pw.Text('إدارة الأمن', style: pw.TextStyle(font: bold, fontSize: 10, color: blue)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: blue, width: 0.7),
                tableWidth: pw.TableWidth.max,
                children: tableRows,
                columnWidths: {for (var i = 0; i < widths.length; i++) i: pw.FixedColumnWidth(widths[i])},
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('عدد السجلات: ${rows.length}', style: const pw.TextStyle(fontSize: 9.5, color: pw.PdfColor.fromInt(0xFF94A3B8))),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  final bytes = await doc.save();
  if (!context.mounted) return;
  await _pdfActionsSheet(context, bytes);
}

Future<void> _pdfActionsSheet(BuildContext context, Uint8List bytes) {
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
          ],
        ),
      ),
    ),
  );
}
