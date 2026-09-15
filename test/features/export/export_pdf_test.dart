import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/export/export_pdf.dart';
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
      lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.6, unit: '%')],
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
