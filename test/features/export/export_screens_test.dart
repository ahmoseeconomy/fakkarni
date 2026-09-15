import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/doctor/doctor_page_screen.dart';
import 'package:fakkarni/features/export/export_actions.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/export/export_pdf.dart';
import 'package:fakkarni/features/export/export_preview_screen.dart';
import 'package:fakkarni/features/export/export_screen.dart';
import 'package:fakkarni/features/health/usual_words.dart';

import '../scan/scan_test_support.dart';

class FakeActions implements ExportActions {
  Uint8List? rasterized, saved, shared;
  bool shareOpens = true;

  @override
  Stream<Uint8List> rasterize(Uint8List pdf) {
    rasterized = pdf;
    return Stream.value(Uint8List.fromList(_png));
  }

  @override
  Future<String> save(Uint8List pdf, String filename) async {
    saved = pdf;
    return '/docs/exports/$filename';
  }

  @override
  Future<bool> share(Uint8List pdf, String filename) async {
    shared = pdf;
    return shareOpens;
  }

  @override
  Future<bool> print(Uint8List pdf, String name) async => true;
}

/// PNG ١×١ شفاف.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);
  final sep15 = DateTime(2026, 9, 15, 10);

  PdfFonts fonts() => PdfFonts.fromBytes(
        ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Regular.ttf').readAsBytesSync()),
        ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Bold.ttf').readAsBytesSync()),
      );

  Future<void> seed() async {
    await h.meds.addMedication(
      patientId: h.services.patientId,
      name: 'Concor 5mg',
      amountLabel: 'قرص واحد',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: DateTime(2026, 9, 1),
    );
    final readings = ReadingsRepository(h.db);
    for (final (v, d) in [(118, 1), (152, 10), (131, 14)]) {
      await readings.add(patientId: h.services.patientId, valueMgDl: v, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 9, d, 7));
    }
    await readings.add(patientId: h.services.patientId, valueMgDl: 200, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 7, 1, 7));
    final labs = LabResultsRepository(h.db);
    await labs.saveReport(patientId: h.services.patientId, happenedAt: DateTime(2026, 6, 1), lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.4, unit: '%')]);
    await labs.saveReport(patientId: h.services.patientId, happenedAt: DateTime(2026, 9, 12), lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.6, unit: '%')]);
    await RecordsRepository(h.db).add(patientId: h.services.patientId, kind: RecordKind.booking, title: 'باطنة', happenedAt: DateTime(2026, 9, 17), doctor: 'د. هشام مام');
    await EmergencyRepository(h.db).save(h.services.patientId, const EmergencyInfo(bloodType: 'O+'));
  }

  void expectNoAdvice(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final text = t.data ?? '';
      for (final word in adviceWords) {
        final hit = RegExp(r'^[a-z]+$').hasMatch(word)
            ? RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text)
            : text.contains(word);
        expect(hit, isFalse, reason: '«$word» في: $text');
      }
      for (final word in ['يبدو', 'نستنتج', 'ملخص ذكي', 'غالباً', 'غالبا']) {
        expect(text.contains(word), isFalse, reason: '«$word» في: $text');
      }
    }
  }

  group('صفحة الطبيب (المخطط ١٦)', () {
    screenTest('أرقام ووقائع: الأدوية، سكر آخر ٣٠ يوم، آخر التحاليل، والميعاد الجاي — من غير أي استنتاج', (tester) async {
      await seed();
      await h.pump(tester, DoctorPageScreen(now: () => sep15));
      await settle(tester);

      expect(find.text('Concor 5mg'), findsOneWidget);
      expect(find.text('سكر صايم · ٣ قياس'), findsOneWidget, reason: 'قياس يوليو برّه آخر ٣٠ يوم');
      expect(find.text('متوسط ١٣٤ · أقل ١١٨ · أعلى ١٥٢ ملّيجرام/ديسيلتر'), findsOneWidget);
      expect(find.text('HbA1c ٧.٦ %'), findsOneWidget);
      expect(find.text('١٢ سبتمبر ٢٠٢٦ · كان ٧.٤ في ١ يونيو ٢٠٢٦'), findsOneWidget);
      expect(find.byKey(const ValueKey('next-booking')), findsOneWidget);
      expect(find.textContaining('↑'), findsNothing);
      expect(find.textContaining('↓'), findsNothing);
      expectNoAdvice(tester);
      expectNoRedAndMinSize(tester);
    });

    screenTest('أسئلة العيلة: بتتضاف، وبتتعلّم «اتسأل ✓»', (tester) async {
      await h.pump(tester, DoctorPageScreen(now: () => sep15));
      await settle(tester);
      expect(find.textContaining('لسه مفيش أسئلة'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('question-field')), 'نقدر نوقف Amaryl؟');
      await settle(tester);
      await tester.tap(find.text('ضيف السؤال'));
      await settle(tester);
      expect(find.text('نقدر نوقف Amaryl؟'), findsOneWidget);

      final q = (await h.db.select(h.db.visitQuestions).get()).single;
      expect(q.asked, isFalse);
      await tester.tap(find.byKey(ValueKey('question-asked-${q.id}')));
      await settle(tester);
      expect(find.text('اتسأل ✓'), findsOneWidget);
    });
  });

  group('استخراج الملف (٣٠) ومعاينته (٣١)', () {
    screenTest('الافتراضي: الطوارئ 🙈 مخفي والباقي 👁 هيظهر، وتحكّم واحد لكل قسم', (tester) async {
      await h.pump(tester, ExportScreen(actions: FakeActions(), fonts: fonts(), now: () => sep15));
      await settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('export-emergency')), matching: find.text('🙈 مخفي')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('export-labs')), matching: find.text('👁 هيظهر')), findsOneWidget);
      expect(find.byType(Switch), findsNothing, reason: 'مفيش مفتاح تاني بنفس المعنى');
      expectNoRedAndMinSize(tester);
    });

    screenTest('المعاينة بتعرض صفحات **نفس الملف** اللي بيتحفظ ويتشارك، والقسم المخفي مش في المستند', (tester) async {
      await seed();
      final actions = FakeActions();
      await h.pump(tester, ExportScreen(actions: actions, fonts: fonts(), now: () => sep15));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('export-medications')));
      await settle(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('export-preview')));
        for (var i = 0; i < 40 && find.byType(ExportPreviewScreen).evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await settle(tester);

      expect(find.byType(ExportPreviewScreen), findsOneWidget);
      final sections = tester.widget<Text>(find.byKey(const ValueKey('preview-sections'))).data!;
      expect(sections, isNot(contains('الأدوية')), reason: 'اتخبّت');
      expect(sections, isNot(contains('الطوارئ')), reason: 'مخفية من الأول');
      expect(sections, contains('نتايج التحاليل'));
      expect(find.byKey(const ValueKey('preview-page-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('export-share')));
      await settle(tester);
      expect(actions.saved, same(actions.rasterized), reason: 'اللي اتعاين هو اللي اتحفظ');
      expect(actions.shared, same(actions.rasterized), reason: 'واللي اتشارك');
      expect(find.byKey(const ValueKey('saved-path')), findsOneWidget);
    });

    screenTest('لو قايمة المشاركة ما اتفتحتش → المكان مكتوب بوضوح — مش زرار ما بيعملش حاجة', (tester) async {
      final actions = FakeActions()..shareOpens = false;
      await h.pump(
        tester,
        ExportPreviewScreen(pdf: Uint8List.fromList([1, 2, 3]), document: const ExportDocument(patientLine: 'أحمد', rangeLine: '', generatedLine: '', blocks: []), filename: 'f.pdf', actions: actions),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('export-share')));
      await settle(tester);
      expect(find.textContaining('ما اتفتحتش'), findsOneWidget);
      expect(find.textContaining('الملفات'), findsOneWidget);
    });
  });

  test('كود صفحة الطبيب والاستخراج: ولا كلمة نصيحة أو استنتاج في نص للمستخدم', () {
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final offenders = <String>[];
    for (final dir in ['lib/features/doctor', 'lib/features/export']) {
      for (final entity in Directory(dir).listSync()) {
        if (entity is! File) continue;
        for (final raw in entity.readAsLinesSync()) {
          final line = raw.trimLeft();
          if (line.startsWith('//')) continue;
          for (final m in literal.allMatches(line)) {
            final text = m.group(1)!;
            for (final word in [...adviceWords, 'يبدو', 'نستنتج', 'غالباً']) {
              final hit = RegExp(r'^[a-z]+$').hasMatch(word)
                  ? RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text)
                  : text.contains(word);
              if (hit) offenders.add('${entity.path}: «$word» في «$text»');
            }
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
