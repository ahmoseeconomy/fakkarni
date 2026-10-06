import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/domain/health/lab_range.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/export/export_pdf.dart';
import 'package:fakkarni/features/medication/med_groups.dart';
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
    final patients = PatientRepository(db);
    patientId = await patients.ensurePatient();
    await patients.saveProfile(patientId, name: 'أحمد محمود', age: 72);
    await MedicationRepository(db, clock: seededLongAgo).addMedication(
      patientId: patientId,
      name: 'Xatral 10mg',
      amountLabel: 'قرص واحد',
      timing: FixedTiming(MinuteOfDay.hm(20)),
      startDate: DateTime(2026, 9, 1),
    );
    await LabResultsRepository(db).saveReport(
      patientId: patientId,
      happenedAt: DateTime(2026, 9, 12),
      place: 'Al Borg Lab',
      lines: [
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
        // نتيجة نصية (المرحلة ٥) — بالحرف في الملف، ومن غير علامة
        ConfirmedLabLine(testName: 'Pus Cells', valueText: 'Negative'),
      ],
    );
    await LabResultsRepository(db).saveReport(
      patientId: patientId,
      happenedAt: DateTime(2026, 8, 3),
      lines: [
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
      ByteData.sublistView(File('assets/fonts/pdf/CairoPdf-Regular.ttf').readAsBytesSync()),
      ByteData.sublistView(File('assets/fonts/pdf/CairoPdf-Bold.ttf').readAsBytesSync()),
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

  test('الملف نفسه ما بيتغيّرش مع الوضع الليلي — نفس البايتس', () async {
    final day = await build(ExportSection.values.toSet());
    F.setDark(on: true);
    addTearDown(() => F.setDark(on: false));
    final night = await build(ExportSection.values.toSet());
    // مكتبة pdf بتحط /ID عشوائي وتاريخ إنشاء بالثانية في كل ملف — غيرهم
    // لازم يتطابق بايت ببايت (التاريخ كان بيعدّي ثانية بين البناءين أحياناً)
    String stable(Uint8List b) => latin1
        .decode(b)
        .replaceAll(RegExp(r'/ID\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'/(CreationDate|ModDate)\s*\([^)]*\)'), '');
    expect(stable(night), stable(day), reason: 'الليل بيغيّر المعاينة بس، مش الملف اللي بيتطبع ويتشارك');
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
    expect(text.contains(await shaped('من ٤ إلى ١١', fonts)), isTrue);
    // والسطر اللي تحت القسم كله
    expect(text.contains(await shaped(labRangeFooter, fonts)), isTrue);

    // النتيجة النصية (المرحلة ٥): بالحرف في خانة النتيجة — لاتيني فبيتلاقى
    // من غير تشكيل، والسطر واخد اسمه وجنبه الكلمة زي ما الورقة طبعتها.
    expect(text.contains('Pus Cells'), isTrue);
    expect(text.contains('Negative'), isTrue, reason: 'النص بالحرف — مش رقم ولا ترجمة');
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
    expect(wbc, ['WBC', '١٢.٤ 10^3/uL', 'من ٤ إلى ١١', labAboveWord]);

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

  // ---------------- المرحلة ٤ (٥ أكتوبر ٢٠٢٦ مساءً): الشكل الجديد ----------------
  group('المرحلة ٤ — الملخص وسطور الصدق والشرايح', () {
    Future<void> seedDoses() async {
      final meds = MedicationRepository(db, clock: seededLongAgo);
      final sid = int.parse((await meds.activeSchedules(patientId)).single.id);
      // كتابة مباشرة عشان actedAt يتحدد بالدقيقة (confirmDose بيكتبه بساعته)
      Future<void> put(DateTime day, DoseState state, {DateTime? actedAt}) =>
          db.into(db.doseEvents).insert(DoseEventsCompanion.insert(
                doseScheduleId: sid,
                routineDay: day,
                scheduledAt: DateTime(day.year, day.month, day.day, 20),
                state: state,
                actedAt: Value(actedAt),
              ));
      // أغسطس: متاخدة في ميعادها — سبتمبر: في ميعادها، متأخرة ساعة،
      // «اتنست»، و«مش هاخدها»
      await put(DateTime(2026, 8, 20), DoseState.taken, actedAt: DateTime(2026, 8, 20, 20, 10));
      await put(DateTime(2026, 9, 10), DoseState.taken, actedAt: DateTime(2026, 9, 10, 20, 30));
      await put(DateTime(2026, 9, 11), DoseState.taken, actedAt: DateTime(2026, 9, 11, 21, 30));
      await put(DateTime(2026, 9, 12), DoseState.missed);
      await put(DateTime(2026, 9, 13), DoseState.skipped);
    }

    test('البلاطات: ٪ بالأيام المتسجّلة بس (4A)، «N من M في ميعادها»، وسطر «مش هاخده» (5A)', () async {
      await seedDoses();
      final bytes = await build(ExportSection.values.toSet());
      final text = pdfText(bytes);
      // ٣ متاخدة من ٤ تتحسب (المتخطّية برّه) = ٧٥٪ — من ٥ أيام متسجّلة
      expect(text.contains(await shaped('النسبة محسوبة من ٥ أيام متسجّلة', fonts)), isTrue);
      expect(text.contains(await shaped('٢ من ٣ — جرعة اتاخدت في ميعادها', fonts)), isTrue,
          reason: 'المتأخرة ساعة برّه «في ميعادها»');
      expect(text.contains(await shaped('وجرعة واحدة قالها «مش هاخدها» — مش محسوبة في النسبة', fonts)), isTrue);
      expect(text.contains('٪٧٥'), isTrue, reason: 'النسبة نفسها');
      expect(text.contains(await shaped('أدوية بياخدها دلوقتي', fonts)), isTrue);
      // شهر بشهر — بأساميهم
      expect(text.contains(await shaped('الالتزام شهر بشهر', fonts)), isTrue);
      expect(text.contains(await shaped('أغسطس ٢٠٢٦', fonts)), isTrue);
      expect(text.contains(await shaped('سبتمبر ٢٠٢٦', fonts)), isTrue);
      // جدول الأدوية بأعمدته و«من غير تحديد» للدوا اللي من غير غرض
      expect(text.contains(await shaped('المواعيد', fonts)), isTrue);
      expect(text.contains(await shaped('من غير تحديد', fonts)), isTrue);
      // الذيل على كل صفحة: الإنكار + «فكّرني — صفحة ١ من …»
      expect(text.contains(await shaped('الملف ده أرقام ووقايع متسجلة على موبايل المريض، ومش تشخيص.', fonts)), isTrue);
      // الرقم الأخير بيتكتب في TJ لوحده فالجملة الكاملة بتتقطّع في فك
      // الـToUnicode — الجزأين دول بيثبتوا العلامة والترقيم مع بعض
      expect(text.contains(await shaped('فكّرني — صفحة', fonts)), isTrue);
      expect(text.contains(await shaped('صفحة ١ من', fonts)), isTrue);
    });

    test('الأقسام الفاضية سطر شرايح واحد — و«مفيش حاجة متسجّلة» المكرّرة اتشالت', () async {
      await seedDoses();
      final bytes = await build(ExportSection.values.toSet());
      final text = pdfText(bytes);
      expect(text.contains(await shaped('مفيش تسجيلات في الفترة دي:', fonts)), isTrue);
      // الروشتات والقياسات والزيارات فاضيين في اللقطة دي — شرايح بأساميهم
      expect(text.contains(await shaped('الروشتات', fonts)), isTrue);
      expect(text.contains(await shaped('مفيش حاجة متسجّلة في الفترة دي', fonts)), isFalse,
          reason: 'الجملة المكرّرة القديمة راحت');
    });

    test('مريض من غير ولا تسجيل: البلاطات بتقول ليه مفيش رقم — ولا ٪ مخترعة', () async {
      final empty = AppDatabase(NativeDatabase.memory());
      addTearDown(empty.close);
      final pid = await PatientRepository(empty).ensurePatient();
      final doc = await collectExport(empty,
          patientId: pid, options: ExportOptions(period: RecordPeriod.all, visible: ExportSection.values.toSet()), now: now);
      final text = pdfText(await buildExportPdf(doc, fonts, compress: false));
      expect(text.contains(await shaped('مفيش جرعات متسجّلة تتحسب منها نسبة', fonts)), isTrue);
      expect(text.contains('٪'), isFalse, reason: 'مفيش نسبة من غير بيانات — عمرنا ما نقدّر');
      // وصفر الأدوية كلمة مش «٠» — الصفر العربي بيتقري نقطة
      expect(text.contains(await shaped('مفيش أدوية متسجّلة دلوقتي', fonts)), isTrue);
      expect(text.contains(await shaped('مفيش تسجيلات في الفترة دي:', fonts)), isTrue);
    });

    test('الفترة أطول من التسجيل = «البيانات المتسجّلة بتبدأ من …» بالكلمة (4A)', () async {
      await seedDoses();
      final doc = await collectExport(db,
          patientId: patientId,
          options: ExportOptions(period: RecordPeriod.year, visible: {ExportSection.medications}),
          now: now);
      expect(doc.summary!.dataStartLine, 'البيانات المتسجّلة بتبدأ من ٢٠ أغسطس ٢٠٢٦ — قبلها مفيش تسجيل.');
      final text = pdfText(await buildExportPdf(doc, fonts, compress: false));
      // ذيل الجملة بيتقطّع في فك الـToUnicode (النقطة بتلزق في آخر كلمة
      // وسطر طويل بيتكسر runs) — رأس الجملة المميّز كفاية، والنص الكامل
      // متثبت فوق بالحرف من المستند نفسه.
      expect(text.contains(await shaped('البيانات المتسجّلة بتبدأ من', fonts)), isTrue);
    });

    test('لون نقطة المجموعة في الملف = لون المجموعة النهاري بالظبط — مرآة بالرقم', () {
      F.setDark(on: false);
      for (final g in MedGroup.values) {
        expect(g.exportDotArgb, g.ink.toARGB32(), reason: g.name);
      }
    });

    test('لقطات: الملفّين بيتكتبوا لـbuild/capture/phase4 — متعبّي وفاضي', () async {
      await seedDoses();
      Directory('build/capture/phase4').createSync(recursive: true);
      File('build/capture/phase4/health-file-seeded.pdf')
          .writeAsBytesSync(await build(ExportSection.values.toSet()));
      final empty = AppDatabase(NativeDatabase.memory());
      addTearDown(empty.close);
      final pid = await PatientRepository(empty).ensurePatient();
      final doc = await collectExport(empty,
          patientId: pid, options: ExportOptions(period: RecordPeriod.all, visible: ExportSection.values.toSet()), now: now);
      File('build/capture/phase4/health-file-empty.pdf').writeAsBytesSync(await buildExportPdf(doc, fonts));
    });
  });
}
