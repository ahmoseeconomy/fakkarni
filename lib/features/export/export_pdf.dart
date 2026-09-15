import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_document.dart';

/// الخطوط المضمّنة — نفس خط التطبيق. من غيرها الحروف العربي مش هتطلع.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static PdfFonts fromBytes(ByteData regular, ByteData bold) =>
      PdfFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));

  static Future<PdfFonts> fromAssets() async => fromBytes(
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
      );
}

final _latin = RegExp(r'[A-Za-z]');
final _tashkeel = RegExp('[ً-ْٰ]');

/// سطر عربي في الـPDF — **اتأكد منه بالعين على ملف متولّد**، مش من الكود.
///
/// حزمة `pdf` بتوصل الحروف صح، لكن فيها مشكلتين اتشافوا في الصورة:
/// ١) عرض الكلمة بيتحسب من الحبر مش من الـadvance، فكلمة آخرها حرف ديله
///    طويل (ر، ا…) بتلزق في اللي بعدها («سكرصايم»)؛
/// ٢) السطر المخلوط (عربي + Concor 5mg) بيتقلب ترتيبه.
/// الحل: كل كلمة عربي Text لوحدها محاطة بمسافة مش بتتكسر (مالهاش حبر،
/// فالصندوق بيمشي على الـadvance)، والتسلسل اللاتيني متجمّع في Text واحد
/// LTR، والكل في Wrap بيبدأ من اليمين. التشكيل بيتشال في الملف بس (الشدّة
/// كانت بتقع في مكان غلط).
pw.Widget arabicLine(String text, pw.TextStyle style) {
  final words = text.replaceAll(_tashkeel, '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final runs = <pw.Widget>[];
  final latin = <String>[];
  void flush() {
    if (latin.isEmpty) return;
    runs.add(pw.Text('\u00A0${latin.join(' ')}\u00A0', style: style, textDirection: pw.TextDirection.ltr));
    latin.clear();
  }

  for (final w in words) {
    if (_latin.hasMatch(w)) {
      latin.add(w);
    } else {
      flush();
      runs.add(pw.Text('\u00A0$w\u00A0', style: style));
    }
  }
  flush();
  return pw.Wrap(children: runs);
}

/// بيولّد الملف من [doc] — اللي فيه أقسامه الظاهرة بس.
Future<Uint8List> buildExportPdf(ExportDocument doc, PdfFonts fonts, {bool compress = true}) {
  final pdf = pw.Document(compress: compress, title: 'ملف صحي', creator: 'فكرني');
  const ink = PdfColor.fromInt(0xFF122E28);
  const green = PdfColor.fromInt(0xFF0A4638);
  const muted = PdfColor.fromInt(0xFF43544C);
  const line = PdfColor.fromInt(0xFFDFDACB);

  pdf.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    ),
    build: (context) => [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: const pw.BoxDecoration(color: green, borderRadius: pw.BorderRadius.all(pw.Radius.circular(10))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            arabicLine(doc.patientLine, pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            arabicLine(doc.rangeLine, const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
            arabicLine(doc.generatedLine, const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
      for (final block in doc.blocks) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: arabicLine(block.section.label, pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: green)),
        ),
        pw.Container(height: 1, color: line),
        pw.SizedBox(height: 4),
        for (final l in block.lines)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: arabicLine(l, const pw.TextStyle(fontSize: 12, color: ink)),
          ),
      ],
      pw.SizedBox(height: 16),
      arabicLine('الملف ده أرقام ووقائع متسجّلة على موبايل المريض.', const pw.TextStyle(fontSize: 10, color: muted)),
    ],
  ));
  return pdf.save();
}
