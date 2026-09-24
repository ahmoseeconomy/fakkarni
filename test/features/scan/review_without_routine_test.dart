import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import 'scan_test_support.dart';

/// **اقتراح الذكاء على مرساة ما اتحددتش ما بيتملاش لوحده.** الورقة قالت
/// «قبل الفطار» والفطار مش متحدد: السطر بيسأل، و«تمام» مقفولة لحد ما
/// الإنسان يجاوب — والإجابة بتتحفظ في روتينه متحددة، مرة واحدة.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  ReadField<T> ok<T>(T v) => ReadField(value: v, confidence: 0.99);

  final breakfastLine = ReadLine(
    name: ok('Antodine 40 mg'),
    amount: ok('قرص واحد'),
    timings: ok([const AnchorTiming(DayAnchor.breakfast, -30)]),
    duration: const ReadField(value: null, confidence: 1),
  );

  Future<void> pumpReview(WidgetTester tester, DayRoutine routine) async {
    await h.pump(
      tester,
      ReviewPrescriptionScreen(
        reading: PrescriptionReading(
          doctor: const ReadField(value: null, confidence: 1),
          clinic: const ReadField(value: null, confidence: 1),
          issuedAt: const ReadField(value: null, confidence: 1),
          lines: [breakfastLine],
        ),
        routine: routine,
        today: aug31,
      ),
    );
    await settle(tester);
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)),
      );

  screenTest('الفطار مش متحدد → مفيش ساعة، سؤال مكتوب، و«تمام» مقفولة', (tester) async {
    await RoutineRepository(h.db).saveRoutine(h.services.patientId, DayRoutine.none);
    await pumpReview(tester, DayRoutine.none);

    expect(find.text('ميعاد الفطار مش متحدد'), findsOneWidget);
    expect(find.text('٧:٠٠ ص'), findsNothing, reason: 'ولا رقم من الافتراضي');
    expect(find.byKey(const ValueKey('unset-anchor-note-0')), findsOneWidget);
    expect(find.text('حدّد ميعاد الفطار'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«حدّد ميعاد الفطار» → السؤال → الإجابة بتتحفظ متحددة، والساعة بتظهر و«تمام» بتتفتح', (tester) async {
    final routines = RoutineRepository(h.db);
    await routines.saveRoutine(h.services.patientId, DayRoutine.none);
    await pumpReview(tester, DayRoutine.none);

    await tester.tap(find.text('حدّد ميعاد الفطار'));
    await settle(tester);
    expect(find.text('بتفطر الساعة كام؟'), findsOneWidget);
    // البكرة واقفة على ٧:٣٠ — دقيقة واحدة لفوق = ٧:٣١ (وبعدها «تمام» بتتفتح)
    await tester.drag(find.byKey(FTimeWheel.minutesKey), const Offset(0, -FTimeWheel.itemExtent));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('anchor-confirm')));
    await settle(tester);

    final routine = (await routines.getRoutine(h.services.patientId))!;
    expect(routine.isSet(DayAnchor.breakfast), isTrue);
    expect(routine.breakfast, MinuteOfDay.hm(7, 31), reason: 'بالدقيقة الواحدة');
    expect(routine.isSet(DayAnchor.dinner), isFalse, reason: 'سؤال واحد بس');

    expect(find.text('ميعاد الفطار مش متحدد'), findsNothing);
    expect(find.text('٧:٠١ ص'), findsOneWidget, reason: '٧:٣١ − ٣٠');
    expect(find.text('حدّد ميعاد الفطار'), findsNothing);
    expect(confirm(tester).onPressed, isNotNull);

    // ولسه مفيش دوا اتكتب — القاعدة الرابعة زي ما هي
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)));
    await settle(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.single.timing, const AnchorTiming(DayAnchor.breakfast, -30));
  });

  screenTest('روتين كامل: نفس الشاشة زي قبل — الساعة معروضة و«تمام» مفتوحة', (tester) async {
    await RoutineRepository(h.db).saveRoutine(h.services.patientId, normalDay);
    await pumpReview(tester, normalDay);
    expect(find.text('٧:٠٠ ص'), findsOneWidget);
    expect(find.text('حدّد ميعاد الفطار'), findsNothing);
    expect(confirm(tester).onPressed, isNotNull);
  });
}
