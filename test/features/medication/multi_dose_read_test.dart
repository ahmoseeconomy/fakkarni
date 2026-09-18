import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/records/record_kinds.dart' show RecordPeriod;
import 'package:fakkarni/features/medication/medications_screen.dart';

import '../scan/scan_test_support.dart';

/// دوا بأربع جرعات لازم يبان بأربعتهم — في القاعدة، وعلى جدول الأدوية،
/// وفي ملف التصدير.
///
/// الاختبار ده على **ناحية القراية**: ضياع جرعة في الكتابة (زي اللي حصل في
/// طريق تعديل الروشتة) بيبان هنا كمان، مش في اختبار الكتابة بس. ورقة
/// بتقول «أربع مرات» وملف بيقول «مرة واحدة» غلط يوصل للدكتور.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  const fourTimes = [
    AnchorTiming(DayAnchor.wake, 0),
    AnchorTiming(DayAnchor.breakfast, 0),
    AnchorTiming(DayAnchor.lunch, 0),
    AnchorTiming(DayAnchor.dinner, 0),
  ];

  Future<void> seed() => h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Augmentin',
        timings: fourTimes,
        startDate: aug31,
        amountLabel: 'قرص',
        durationDays: 7,
      );

  test('القاعدة: أربع جرعات = أربع صفوف، كلها لنفس الدوا', () async {
    await seed();
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(4));
    expect(saved.map((s) => s.timing), containsAll(fourTimes));
    expect(saved.map((s) => s.medicationName).toSet(), {'Augmentin'});
  });

  test('جرعة واحدة مش مسموح بيها تبقى صفر — الكتابة بترفض قايمة فاضية', () async {
    expect(
      () => h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Augmentin',
        timings: const [],
        startDate: aug31,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  screenTest('جدول الأدوية بيعرض الدوا تحت كل مرساة من الأربعة — أربع كروت', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await seed();

    await h.pump(tester, MedicationsScreen(today: aug31));

    expect(find.text('Augmentin'), findsNWidgets(4), reason: 'كارت لكل جرعة — ده جدول');
    expect(find.text('دوا واحد — مرتّبة على مواعيد يومك'), findsOneWidget);
  });

  test('ملف التصدير بيقول «٤× في اليوم» — مش ١×', () async {
    await seed();
    final doc = await collectExport(
      h.db,
      patientId: h.services.patientId,
      options: const ExportOptions(period: RecordPeriod.all, visible: {ExportSection.medications}),
      now: aug31,
    );
    final line = doc.blocks.singleWhere((b) => b.section == ExportSection.medications).lines.single;
    expect(line, contains('Augmentin'));
    expect(line, contains('٤× في اليوم'));
  });
}
