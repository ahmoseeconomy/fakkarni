import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/every_hours.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import '../scan/scan_test_support.dart';

/// الجولة الأولى من أنماط الجدولة: «كل كام ساعة» بيتفرد لساعات ثابتة،
/// و«مرة واحدة» بتتحفظ `once`، و«اليوم فقط» من الورقة بتبقى «مرة واحدة».
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> pumpAdd(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, AddMedicationScreen(routine: normalDay, today: aug31, initialName: 'Augmentin'));
  }

  List<int> fixedMinutes(List<DoseSchedule> s) => [
        for (final x in s)
          if (x.timing case FixedTiming(:final minuteOfDay)) minuteOfDay.minutes,
      ]..sort();

  test('الفرد: قواسم ٢٤ بس، ومن أول جرعة، واليوم بيلف', () {
    expect([for (final t in everyHoursTimes(MinuteOfDay.hm(8, 0), 4)) t.minutes],
        [8 * 60, 12 * 60, 16 * 60, 20 * 60, 0, 4 * 60]);
    expect(everyHoursTimes(MinuteOfDay.hm(21, 30), 12).map((t) => t.minutes), [21 * 60 + 30, 9 * 60 + 30]);
    expect(() => everyHoursTimes(MinuteOfDay.hm(8, 0), 5), throwsArgumentError);
    expect(everyHoursOf([MinuteOfDay.hm(8, 0), MinuteOfDay.hm(16, 0), MinuteOfDay.hm(0, 0)]), 8);
    expect(everyHoursOf([MinuteOfDay.hm(8, 0), MinuteOfDay.hm(15, 0)]), isNull);
  });

  screenTest('«كل كام ساعة»: المعاينة قبل الحفظ، و«كل ٤» بيتحفظ ٦ ساعات ثابتة', (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.byKey(const ValueKey('pattern-everyHours')));
    await settle(tester);
    // الافتراضي كل ٨ من ٨ الصبح
    expect(find.text('هتاخده الساعة: ٨:٠٠ ص، ٤:٠٠ م، ١٢:٠٠ ص'), findsOneWidget);
    expect(find.text('كام مرة في اليوم؟'), findsNothing, reason: 'العدد بقى من الفاصل');
    await tester.tap(find.byKey(const ValueKey('every-4')));
    await settle(tester);
    expect(find.text('هتاخده الساعة: ٨:٠٠ ص، ١٢:٠٠ م، ٤:٠٠ م، ٨:٠٠ م، ١٢:٠٠ ص، ٤:٠٠ ص'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey('dose-row-$i')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(6));
    expect(fixedMinutes(saved), [0, 4 * 60, 8 * 60, 12 * 60, 16 * 60, 20 * 60]);
    expect(saved.every((s) => s.repeat == DoseRepeat.daily), isTrue, reason: 'مش نوع جديد — ساعات ثابتة يومية');
    expectNoRedAndMinSize(tester);
  });

  screenTest('«مرة واحدة» بتتحفظ once من غير مدة', (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.byKey(const ValueKey('pattern-once')));
    await settle(tester);
    expect(find.text('هتاخده يوم إيه؟'), findsOneWidget);
    expect(find.text('كام مرة في اليوم؟'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.single.repeat, DoseRepeat.once);
    expect(saved.single.durationDays, isNull);
    expect(saved.single.startDate, aug31);
  });

  screenTest('«اليوم فقط» من الورقة (مدة ١) → «مرة واحدة» على المراجعة، وبتتحفظ once', (tester) async {
    final todayOnly = ReadLine(
      name: ok('Zithromax 500'),
      amount: ok('قرص'),
      timings: ok([const AnchorTiming(DayAnchor.breakfast, 0)]),
      duration: ok(1),
    );
    await h.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ReviewPrescriptionScreen(
                reading: PrescriptionReading(doctor: const ReadField(value: null, confidence: 1), lines: [todayOnly]),
                routine: normalDay,
                today: aug31,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.textContaining('مرة واحدة بس'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('confirm-review'));
    await tester.ensureVisible(confirm);
    await tester.tap(find.descendant(of: confirm, matching: find.byType(FilledButton)));
    await settle(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.single.repeat, DoseRepeat.once);
    expect(saved.single.durationDays, isNull);
  });

  screenTest('تعديل دوا موجود: «خليه كل كام ساعة» بيكتب الساعات الجديدة ويوقف القديمة (إيقاف ناعم)', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = await h.meds.addMedication(
        patientId: h.services.patientId, name: 'Augmentin', timing: const AnchorTiming(DayAnchor.breakfast, 0), startDate: aug31);
    await h.pump(tester, EditMedicationScreen(medicationId: id));
    await tester.tap(find.byKey(const ValueKey('make-every-hours')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('every-12')));
    await settle(tester);
    expect(find.text('هتاخده الساعة: ٨:٠٠ ص، ٨:٠٠ م'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('every-hours-save')));
    await settle(tester);

    final active = await h.meds.activeSchedules(h.services.patientId);
    expect(fixedMinutes(active), [8 * 60, 20 * 60]);
    expect(active.every((s) => s.timing is FixedTiming), isTrue);
    final all = await h.db.select(h.db.doseSchedules).get();
    expect(all.where((s) => s.stoppedAt != null), hasLength(1), reason: 'القديمة اتوقفت، ما اتمسحتش');
  });
}
