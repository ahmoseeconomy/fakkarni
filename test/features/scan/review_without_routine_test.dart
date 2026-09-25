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

  screenTest('الفطار مش متحدد → مفيش ساعة، سؤال مكتوب — و«تمام» مفتوحة', (tester) async {
    await RoutineRepository(h.db).saveRoutine(h.services.patientId, DayRoutine.none);
    await pumpReview(tester, DayRoutine.none);

    expect(find.text('ميعاد الفطار مش متحدد'), findsOneWidget);
    expect(find.text('٧:٠٠ ص'), findsNothing, reason: 'ولا رقم من الافتراضي');
    expect(find.byKey(const ValueKey('unset-anchor-note-0')), findsOneWidget);
    expect(find.text('حدّد ميعاد الفطار'), findsOneWidget);
    expect(confirm(tester).onPressed, isNotNull, reason: 'المرساة بتتسأل بعد «تمام»، مش بتقفلها');
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

  group('المرساة اللي ما اتحددتش بتتسأل بعد «تمام» — مرة واحدة، وممكن تتعدّى', () {
    final fixedLine = ReadLine(
      name: ok('Eltroxin 50'),
      amount: ok('قرص'),
      timings: ok([const FixedTiming(MinuteOfDay(1260))]), // ٩ بالليل
      duration: const ReadField(value: null, confidence: 1),
    );

    Future<void> pumpTwo(WidgetTester tester) async {
      await RoutineRepository(h.db).saveRoutine(h.services.patientId, DayRoutine.none);
      await h.pump(
        tester,
        ReviewPrescriptionScreen(
          reading: PrescriptionReading(
            doctor: const ReadField(value: null, confidence: 1),
            clinic: const ReadField(value: null, confidence: 1),
            issuedAt: const ReadField(value: null, confidence: 1),
            lines: [breakfastLine, fixedLine],
          ),
          routine: DayRoutine.none,
          today: aug31,
        ),
      );
      await settle(tester);
    }

    screenTest('«تمام» → السؤال بيظهر مرة → الإجابة بتتحفظ وبتتجدول، والثابتة اتجدولت قبلها', (tester) async {
      await pumpTwo(tester);
      expect(find.text('تمام — دواءين'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)));
      await settle(tester);

      // الاتنين اتحفظوا قبل السؤال — والثابتة ليها إشعار خلاص
      expect(await h.meds.activeSchedules(h.services.patientId), hasLength(2));
      expect(find.text('بتفطر الساعة كام؟'), findsOneWidget, reason: 'سؤال واحد بعد الحفظ');
      final beforeAnswer = h.sink.scheduled.values.where((n) => n.body.contains('Eltroxin'));
      expect(beforeAnswer, isNotEmpty, reason: 'الجرعة الثابتة بتتجدول عادي وإحنا لسه بنسأل');
      expect(h.sink.scheduled.values.where((n) => n.body.contains('Antodine')), isEmpty,
          reason: 'جرعة الفطار ساكتة لحد ما يتحدد');

      await tester.drag(find.byKey(FTimeWheel.minutesKey), const Offset(0, -FTimeWheel.itemExtent));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('anchor-confirm')));
      await settle(tester);

      final routine = (await RoutineRepository(h.db).getRoutine(h.services.patientId))!;
      expect(routine.isSet(DayAnchor.breakfast), isTrue);
      expect(h.sink.scheduled.values.where((n) => n.body.contains('Antodine')), isNotEmpty,
          reason: 'اتحدد → اتجدول');
      expect(find.text('بتفطر الساعة كام؟'), findsNothing, reason: 'ما بيتسألش تاني');
    });

    screenTest('القفل من غير إجابة: الدوا محفوظ على مرساته، ساكت، والمرساة لسه مش متحددة', (tester) async {
      await pumpTwo(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)));
      await settle(tester);
      expect(find.text('بتفطر الساعة كام؟'), findsOneWidget);
      // تخطّي = قفل الورقة
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);

      final routine = (await RoutineRepository(h.db).getRoutine(h.services.patientId))!;
      expect(routine.isSet(DayAnchor.breakfast), isFalse, reason: 'ولا رقم اتكتب');
      final saved = await h.meds.activeSchedules(h.services.patientId);
      expect(saved.map((s) => s.timing), contains(const AnchorTiming(DayAnchor.breakfast, -30)));
      expect(h.sink.scheduled.values.where((n) => n.body.contains('Antodine')), isEmpty);
      expect(h.sink.scheduled.values.where((n) => n.body.contains('Eltroxin')), isNotEmpty);
    });
  });
}
