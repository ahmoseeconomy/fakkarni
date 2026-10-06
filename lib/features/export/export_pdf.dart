import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format/arabic_time.dart' show arabicMonths, arabicNumber;
import '../../domain/adherence/export_adherence.dart' show MonthAdherence;
import '../medication/med_groups.dart' show MedGroup;
import 'export_document.dart';

/// الخطوط المضمّنة — نفس خط التطبيق. من غيرها الحروف العربي مش هتطلع.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static PdfFonts fromBytes(ByteData regular, ByteData bold) =>
      PdfFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));

  static Future<PdfFonts> fromAssets() async => fromBytes(
        await rootBundle.load('assets/fonts/pdf/CairoPdf-Regular.ttf'),
        await rootBundle.load('assets/fonts/pdf/CairoPdf-Bold.ttf'),
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
    runs.add(pw.Text(' ${latin.join(' ')} ', style: style, textDirection: pw.TextDirection.ltr));
    latin.clear();
  }

  for (final w in words) {
    if (_latin.hasMatch(w)) {
      latin.add(w);
    } else {
      flush();
      runs.add(pw.Text(' $w ', style: style));
    }
  }
  flush();
  return pw.Wrap(children: runs);
}

// لوحة الملف — قيم النهار الثابتة (الورق مالوش وضع ليلي).
const _ink = PdfColor.fromInt(0xFF122E28);
const _green = PdfColor.fromInt(0xFF0A4638);
const _muted = PdfColor.fromInt(0xFF43544C);
const _line = PdfColor.fromInt(0xFFDFDACB);
const _gold = PdfColor.fromInt(0xFFC9A227);
const _tile = PdfColor.fromInt(0xFFF1EFE6);

/// عتبة «أخضر» لشريط الالتزام (المواصفة): ≥٩٠٪ أخضر، أقل دهبي.
const int adherenceGreenAt = 90;

PdfColor _pctColor(int pct) => pct >= adherenceGreenAt ? _green : _gold;

/// نص المحتوى كله ≥ ١٢ (مواصفة المرحلة ٤ — الورق بيتقري من على مكتب).
const _body = pw.TextStyle(fontSize: 12, color: _ink);
const _small = pw.TextStyle(fontSize: 12, color: _muted);

/// بيولّد الملف من [doc] — اللي فيه أقسامه الظاهرة بس.
Future<Uint8List> buildExportPdf(ExportDocument doc, PdfFonts fonts, {bool compress = true}) {
  final pdf = pw.Document(compress: compress, title: 'ملف صحي', creator: 'فكرني');

  pdf.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    ),
    // «صفحة X من Y» + جملة الذيل على كل صفحة. «ومش تشخيص» بقرار المالك
    // (المرحلة ٤) — إنكار، مش نصيحة؛ مستثناة بالاسم في حارس كلمات النصايح.
    footer: (context) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5))),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: arabicLine('الملف ده أرقام ووقايع متسجلة على موبايل المريض، ومش تشخيص.', _small),
          ),
          arabicLine(
            'فكّرني — صفحة ${arabicNumber(context.pageNumber)} من ${arabicNumber(context.pagesCount)}',
            const pw.TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    ),
    build: (context) => [
      _header(doc),
      // الخيط الدهبي الرفيع تحت الترويسة
      pw.Container(height: 2, color: _gold),
      pw.SizedBox(height: 12),
      if (doc.summary case final s?) ...[
        _tiles(s),
        pw.SizedBox(height: 6),
        _honestyLines(s),
        if (s.medRows.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _sectionHead('الأدوية والجرعات'),
          _medsTable(s),
        ],
        if (s.adherence.perMonth.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _sectionHead('الالتزام شهر بشهر'),
          pw.SizedBox(height: 4),
          _monthBars(s.adherence.perMonth),
        ],
      ],
      for (final block in doc.blocks) ...[
        pw.SizedBox(height: 10),
        _sectionHead(block.section.label),
        for (final l in block.lines)
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: arabicLine(l, _body)),
        for (final table in block.tables) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
            child: arabicLine(table.caption, pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _tile),
                children: [
                  for (final h in table.headers)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: arabicLine(h, pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _muted)),
                    ),
                ],
              ),
              for (final row in table.rows)
                pw.TableRow(
                  children: [
                    for (final cell in row)
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: arabicLine(cell, _body)),
                  ],
                ),
            ],
          ),
        ],
        if (block.footnote case final note?)
          pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: arabicLine(note, _small)),
      ],
      // الأقسام الفاضية كلها سطر شرايح واحد — مش «مفيش» مكرّرة تحت كل عنوان
      if (doc.emptySections.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        arabicLine('مفيش تسجيلات في الفترة دي:', pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final label in doc.emptySections)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: _tile,
                  borderRadius: pw.BorderRadius.circular(9),
                  border: pw.Border.all(color: _line, width: 0.5),
                ),
                child: arabicLine(label, _small),
              ),
          ],
        ),
      ],
    ],
  ));
  return pdf.save();
}

/// الترويسة: شريط أخضر غامق — «فكّرني — الملف الصحي» صغيرة، الاسم كبير،
/// الفترة و«اتعمل في». («·» ممنوعة في نصوص المستخدم — القاعدة بتكسب
/// والفاصل « — »، زي كل التطبيق.)
pw.Widget _header(ExportDocument doc) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: const pw.BoxDecoration(
        color: _green,
        borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(10), topRight: pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          arabicLine('فكّرني — الملف الصحي', const pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFFBFD6CE))),
          pw.SizedBox(height: 2),
          arabicLine(doc.patientLine, pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 2),
          arabicLine(doc.rangeLine, const pw.TextStyle(fontSize: 12, color: PdfColors.white)),
          arabicLine(doc.generatedLine, const pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFFBFD6CE))),
        ],
      ),
    );

pw.Widget _sectionHead(String label) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, bottom: 3),
          child: arabicLine(label, pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _green)),
        ),
        pw.Container(height: 1, color: _line),
        pw.SizedBox(height: 4),
      ],
    );

/// البلاطات التلاتة: النسبة بحلقة، «N من M في ميعادها»، وعدد الأدوية.
/// اللي مش محسوب بصدق بيتكتب مكانه ليه («مفيش جرعات متسجّلة») — مفيش تقدير.
pw.Widget _tiles(ExportSummary s) {
  pw.Widget tile(pw.Widget child) => pw.Expanded(
        child: pw.Container(
          height: 86,
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: _tile, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Center(child: child),
        ),
      );

  final pct = s.adherence.pct;
  final onTime = s.adherence.onTimeLine;
  return pw.Row(children: [
    tile(pct == null
        ? arabicLine('مفيش جرعات متسجّلة تتحسب منها نسبة', _small)
        : pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            pw.Container(
              width: 46,
              height: 46,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: _pctColor(pct), width: 5),
              ),
              child: pw.Text('٪${arabicNumber(pct)}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
            ),
            pw.SizedBox(height: 3),
            arabicLine('الالتزام', _small),
          ])),
    tile(onTime == null
        ? arabicLine('مفيش جرعات متاخدة نحكم على ميعادها', _small)
        : arabicLine(onTime, _body)),
    // صفر مش رقم يتعرض: «٠» العربي بيتقري نقطة (قاعدة «·» نفسها) —
    // والجملة أوضح من دايرة فاضية
    tile(s.currentMedsCount == 0
        ? arabicLine('مفيش أدوية متسجّلة دلوقتي', _small)
        : pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            pw.Text(arabicNumber(s.currentMedsCount),
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _green)),
            arabicLine('أدوية بياخدها دلوقتي', _small),
          ])),
  ]);
}

/// سطور الصدق تحت البلاطات: «من N يوم متسجّل» (4A)، سطر «مش هاخده» (5A)،
/// و«البيانات بتبدأ من …» لما الفترة أطول من التسجيل.
pw.Widget _honestyLines(ExportSummary s) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        arabicLine('النسبة محسوبة ${s.adherence.recordedDaysLine}', _small),
        if (s.adherence.skippedLine case final l?) arabicLine(l, _small),
        if (s.dataStartLine case final l?) arabicLine(l, _small),
      ],
    );

const medsTableHeaders = ['الدوا', 'لإيه', 'الجرعة', 'المواعيد', 'الالتزام'];

pw.Widget _medsTable(ExportSummary s) => pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2.2),
        4: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _tile),
          children: [
            for (final h in medsTableHeaders)
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: arabicLine(h, pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _muted)),
              ),
          ],
        ),
        for (final m in s.medRows)
          pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: arabicLine(m.name, _body)),
            // نقطة المجموعة بلونها (القلب أحمر — قرار المالك، واللون معرّف
            // في med_groups وبس) وكلمتها — «من غير تحديد» لما مفيش غرض
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Row(children: [
                pw.Container(
                  width: 7,
                  height: 7,
                  margin: const pw.EdgeInsets.only(left: 3, top: 5),
                  decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColor.fromInt(m.group.exportDotArgb)),
                ),
                pw.Expanded(child: arabicLine(_groupWord(m.group), _body)),
              ]),
            ),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: arabicLine(m.doseLabel, _body)),
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: arabicLine(m.timesLabel, _body)),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: m.pct == null
                  ? arabicLine('مفيش جرعات متسجّلة', _small)
                  : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('٪${arabicNumber(m.pct!)}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _pctColor(m.pct!))),
                      pw.SizedBox(height: 2),
                      _bar(m.pct!),
                    ]),
            ),
          ]),
      ],
    );

/// نقطة «لإيه» بتتكتب «من غير تحديد» لما مفيش غرض (مواصفة المرحلة ٤).
String _groupWord(MedGroup g) => g == MedGroup.unclassified ? 'من غير تحديد' : g.label;

pw.Widget _bar(int pct) {
  final share = pct.clamp(0, 100);
  return pw.Container(
    height: 5,
    decoration: pw.BoxDecoration(color: _line, borderRadius: pw.BorderRadius.circular(2.5)),
    // حزمة pdf مافيهاش FractionallySizedBox — صفّ بجزئين flex بنفس المعنى
    child: pw.Row(children: [
      pw.Expanded(
        flex: share == 0 ? 1 : share,
        child: share == 0
            ? pw.SizedBox()
            : pw.Container(
                decoration: pw.BoxDecoration(color: _pctColor(pct), borderRadius: pw.BorderRadius.circular(2.5)),
              ),
      ),
      if (share < 100) pw.Expanded(flex: share == 0 ? 99 : 100 - share, child: pw.SizedBox()),
    ]),
  );
}

/// «الالتزام شهر بشهر» — عمود لكل شهر في الفترة، بكلمته ورقمه.
pw.Widget _monthBars(List<MonthAdherence> months) {
  const maxH = 54.0;
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(color: _tile, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        for (final m in months)
          pw.Expanded(
            child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
              if (m.pct case final pct?) ...[
                pw.Text('٪${arabicNumber(pct)}', style: const pw.TextStyle(fontSize: 12, color: _muted)),
                pw.Container(
                  height: maxH * pct.clamp(0, 100) / 100 + 2,
                  width: 16,
                  decoration: pw.BoxDecoration(
                    color: _pctColor(pct),
                    borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                  ),
                ),
              ] else
                arabicLine('مفيش', _small),
              pw.SizedBox(height: 2),
              arabicLine('${arabicMonths[m.month - 1]} ${arabicNumber(m.year)}', _small),
            ]),
          ),
      ],
    ),
  );
}
