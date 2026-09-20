import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/health/lab_range.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/export/export_pdf.dart';
import 'package:fakkarni/features/health/usual_words.dart'
    show labAboveWord, labBelowWord, labNearWord, labRangeFooter;
import 'package:fakkarni/features/records/record_kinds.dart';
import '../../support/seeded_clock.dart';

/// النص اللي في الملف فعلاً: بيفك كل سلاسل `<hex>` بكل خريطة ToUnicode
/// موجودة في الملف (كل خط ليه خريطة). محتاج ملف مش مضغوط.
String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final maps = <Map<int, int>>[];
  for (final block in RegExp(r'beginbfchar\n([\s\S]*?)endbfchar').allMatches(raw)) {
    final map = <int, int>{};
    for (final pair in RegExp(r'<([0-9A-F]{4})> <([0-9A-F]{4})>').allMatches(block.group(1)!)) {
      map[int.parse(pair.group(1)!, radix: 16)] = int.parse(pair.group(2)!, radix: 16);
    }
    maps.add(map);
  }
  // `[<hex>]TJ` — كلمة لكل أمر. بنفك كل الأوامر بكل خريطة ونلزقهم بمسافة،
  // عشان «Chest CT» (كلمتين) يتلاقي.
  final strings = [for (final s in RegExp(r'\[<([0-9a-f]+)>\]TJ').allMatches(raw)) s.group(1)!];
  final out = StringBuffer();
  for (final map in maps) {
    for (final hex in strings) {
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final code = map[int.parse(hex.substring(i, i + 4), radix: 16)];
        if (code != null && code != 0xA0) out.writeCharCode(code);
      }
      out.write(' ');
    }
    out.write('\n');
  }
  return out.toString();
}

/// الكلمة العربي زي ما `pdf` بتكتبها فعلاً.
///
/// الحزمة بتكتب العربي **بأشكال العرض** (U+FExx) ومقلوبة، فالبحث عن
/// «فوق المعدل» بالحرف في الملف بيرجع فاضي حتى وهي مكتوبة فيه. بدل ما
/// نكتب الجليفات بإيدينا (وتبقى مربوطة بنسخة الحزمة)، بنمرّر الكلمة على
/// **نفس** الكاتب ونقارن الناتج بالناتج.
Future<String> shaped(String phrase, PdfFonts fonts) async {
  final doc = pw.Document(compress: false);
  doc.addPage(pw.Page(
    pageTheme: pw.PageTheme(
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.regular),
    ),
    build: (_) => arabicLine(phrase, const pw.TextStyle(fontSize: 12)),
  ));
  return pdfText(await doc.save()).trim();
}

void main() {
  late AppDatabase db;
  late int patientId;
  late PdfFonts fonts;
  final now = DateTime(2026, 9, 15, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    await routines.saveProfile(patientId, name: 'أحمد محمود', sex: Sex.m, age: 72);
    await MedicationRepository(db, clock: seededLongAgo).addMedication(
      patientId: patientId,
      name: 'Xatral 10mg',
      amountLabel: 'قرص واحد',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: DateTime(2026, 9, 1),
    );
    await LabResultsRepository(db).saveReport(
      patientId: patientId,
      happenedAt: DateTime(2026, 9, 12),
      place: 'Al Borg Lab',
      lines: const [
        ConfirmedLabLine(testName: 'HbA1c', value: 7.6, unit: '%'),
        // نطاق الورقة ٤–١١: ١٢.٤ فوقه، و١٠.٥ جوّه بس قريب من الحد
        ConfirmedLabLine(
          testName: 'WBC',
          value: 12.4,
          unit: '10^3/uL',
          range: LabRange(low: 4, high: 11),
        ),
        ConfirmedLabLine(
          testName: 'Platelets',
          value: 10.5,
          unit: '10^3/uL',
          range: LabRange(low: 4, high: 11),
        ),
      ],
    );
    await LabResultsRepository(db).saveReport(
      patientId: patientId,
      happenedAt: DateTime(2026, 8, 3),
      lines: const [
        ConfirmedLabLine(testName: 'Ferritin', value: 8, unit: 'ng/mL', range: LabRange(low: 30, high: 400)),
      ],
    );
    await RecordsRepository(db).add(
      patientId: patientId,
      kind: RecordKind.imaging,
      title: 'Chest CT',
      happenedAt: DateTime(2026, 9, 5),
    );
    await ReadingsRepository(db).add(patientId: patientId, valueMgDl: 152, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 9, 14, 7));
    await EmergencyRepository(db).save(
      patientId,
      const EmergencyInfo(
        bloodType: 'O+',
        allergies: 'Penicillin',
        contacts: [EmergencyContact(name: 'Mohamed', phone: '01001234567', relation: 'son')],
      ),
    );
    fonts = PdfFonts.fromBytes(
      ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Regular.ttf').readAsBytesSync()),
      ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Bold.ttf').readAsBytesSync()),
    );
  });
  tearDown(() => db.close());

  Future<Uint8List> build(Set<ExportSection> visible) async {
    final doc = await collectExport(
      db,
      patientId: patientId,
      options: ExportOptions(period: RecordPeriod.all, visible: visible),
      now: now,
    );
    return buildExportPdf(doc, fonts, compress: false);
  }

  test('الضابط الإيجابي: كل الأقسام ظاهرة → البحث بيلاقي نص كل قسم في الملف', () async {
    final bytes = await build(ExportSection.values.toSet());
    final out = Platform.environment['FAKKARNI_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
    final text = pdfText(bytes);
    for (final token in ['Xatral', 'HbA1c', 'Chest CT', 'Penicillin', 'O+', '١٥٢']) {
      expect(text.contains(token), isTrue, reason: 'لو البحث ما لقاش «$token» وهو ظاهر، الاختبار اللي بعده مالوش معنى');
    }
  });

  test('القسم المخفي مش موجود في ملف الـPDF أصلاً — مش مستخبي', () async {
    final text = pdfText(await build(ExportSection.values.toSet()..removeAll({ExportSection.medications, ExportSection.emergency})));
    expect(text.contains('Xatral'), isFalse, reason: 'الأدوية مخفية');
    expect(text.contains('Penicillin'), isFalse, reason: 'الطوارئ مخفية');
    expect(text.contains('O+'), isFalse);
    expect(text.contains('HbA1c'), isTrue, reason: 'الظاهر فضل ظاهر');
    expect(text.contains('Chest CT'), isTrue);
  });

  test('الإخفاء وقت التوليد: المستند نفسه ما فيهوش القسم المخفي', () async {
    final doc = await collectExport(
      db,
      patientId: patientId,
      options: ExportOptions(period: RecordPeriod.all, visible: {ExportSection.labs}),
      now: now,
    );
    expect([for (final b in doc.blocks) b.section], [ExportSection.labs]);
    expect(doc.blocks.expand((b) => b.lines).join('\n'), isNot(contains('Xatral')));
  });

  test('أرقام جهات الاتصال عمرها ما بتدخل الملف — حتى والطوارئ ظاهرة', () async {
    final text = pdfText(await build(ExportSection.values.toSet()));
    expect(text.contains('01001234567'), isFalse);
    expect(text.contains('Mohamed'), isFalse);
  });

  test('كل سطر متعلّم في الملف بياخد كلمته — الملف بيتطبع أبيض وأسود', () async {
    final text = pdfText(await build(ExportSection.values.toSet()));

    // ضابط إيجابي: الطريقة نفسها بتلاقي كلمة إحنا متأكدين إنها هناك.
    expect(text.contains(await shaped('نتايج التحاليل', fonts)), isTrue,
        reason: 'لو عنوان القسم مش بيتلاقى، باقي الاختبار مالوش معنى');

    // فوق، تحت، وقريب — التلاتة بالكلمة، مش باللون
    expect(text.contains(await shaped(labAboveWord, fonts)), isTrue, reason: 'WBC ١٢.٤ فوق ٤–١١');
    expect(text.contains(await shaped(labBelowWord, fonts)), isTrue, reason: 'Ferritin ٨ تحت ٣٠–٤٠٠');
    expect(text.contains(await shaped(labNearWord, fonts)), isTrue,
        reason: 'Platelets ١٠.٥ على بعد أقل من ١٠٪ من الحد');

    // ونطاق الورقة نفسه — بنفس الطريقة: الترتيب في الملف بيتقلب (١١–٤)
    expect(text.contains(await shaped('٤–١١', fonts)), isTrue);
    // والسطر اللي تحت القسم كله
    expect(text.contains(await shaped(labRangeFooter, fonts)), isTrue);
  });

  test('السطر اللي الورقة مفيهاش نطاق ليه بيوصل الملف من غير ولا كلمة علامة', () async {
    final doc = await collectExport(
      db,
      patientId: patientId,
      options: ExportOptions(period: RecordPeriod.all, visible: {ExportSection.labs}),
      now: now,
    );
    final hba1c = doc.blocks.single.tables
        .expand((t) => t.rows)
        .firstWhere((r) => r.first == 'HbA1c');
    expect(hba1c.last, isEmpty);
    expect([labAboveWord, labBelowWord, labNearWord].any(hba1c.contains), isFalse);
  });

  test('جدول التحاليل: أعمدة، ومجمّع بتاريخ التقرير', () async {
    final doc = await collectExport(
      db,
      patientId: patientId,
      options: ExportOptions(period: RecordPeriod.all, visible: {ExportSection.labs}),
      now: now,
    );
    final block = doc.blocks.single;
    expect(block.tables.length, 2, reason: 'تقريرين بتاريخين = جدولين');
    expect(block.tables.first.caption, '١٢ سبتمبر ٢٠٢٦');
    expect(block.tables.last.caption, '٣ أغسطس ٢٠٢٦');
    expect(block.tables.first.headers, labExportHeaders);
    expect(block.footnote, labRangeFooter);

    final wbc = block.tables.first.rows.firstWhere((r) => r.first == 'WBC');
    expect(wbc, ['WBC', '١٢.٤ 10^3/uL', '٤–١١', labAboveWord]);

    // السطر اللي الورقة مفيهاش نطاق ليه: شرطة، وعمود الكلمة فاضي
    final hba1c = block.tables.first.rows.firstWhere((r) => r.first == 'HbA1c');
    expect(hba1c, ['HbA1c', '٧.٦ %', '—', '']);
  });

  test('الافتراضي: الطوارئ مخفية', () {
    expect(ExportOptions.defaults().visible.contains(ExportSection.emergency), isFalse);
    expect(ExportOptions.defaults().visible.contains(ExportSection.labs), isTrue);
  });

  test('الفترة بتشيل اللي برّاها من الأقسام المؤرخة', () async {
    await RecordsRepository(db).add(patientId: patientId, kind: RecordKind.imaging, title: 'Old MRI', happenedAt: DateTime(2025, 1, 1));
    final doc = await collectExport(
      db,
      patientId: patientId,
      options: ExportOptions(period: RecordPeriod.month, visible: {ExportSection.imaging}),
      now: now,
    );
    final lines = doc.blocks.single.lines.join('\n');
    expect(lines, contains('Chest CT'));
    expect(lines, isNot(contains('Old MRI')));
  });
}
