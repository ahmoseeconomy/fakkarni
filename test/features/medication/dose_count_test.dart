import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_row.dart';

import '../scan/scan_test_support.dart';

/// **«كام مرة في اليوم؟» هي المكان الوحيد اللي بيقرر العدد في «ضيف دوا».**
///
/// كانت تحتها قايمة جرعات بـ«شيل» و«أضف جرعة»، فبقى تلات أماكن بتقرر نفس
/// الرقم: الشرايح، والقايمة، والمشي اللي بعد «كمّل». القايمة اتشالت من
/// هنا، وإضافة وشيل لدوا **محفوظ** مكانهم شاشة التعديل.
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

  Future<void> pumpAdd(WidgetTester tester, {List<DoseTiming> timings = const []}) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(
      tester,
      AddMedicationScreen(
        routine: normalDay,
        today: aug31,
        initialName: 'Augmentin',
        initialTimings: timings,
      ),
    );
  }

  /// [count] صف جرعة ظاهرين في الفورم — مفيش مشي — وبعدها «احفظ».
  Future<void> walk(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      expect(find.byKey(ValueKey('dose-row-$i')), findsOneWidget, reason: 'صف $i من $count');
    }
    expect(find.byKey(ValueKey('dose-row-$count')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
  }

  screenTest('مفيش زرار يضيف ولا يشيل جرعة في «ضيف دوا» — ولا قايمة أصلاً', (tester) async {
    await pumpAdd(tester);

    expect(find.byType(DoseRow), findsNothing);
    expect(find.text('أضف جرعة'), findsNothing);
    expect(find.text('شيل'), findsNothing);
    expect(find.text('جرعات اليوم'), findsNothing);
    // اللي فاضل: الشرايح
    expect(find.byKey(const ValueKey('count-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-more')), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«٤ مرات» → أربع محرّرات وأربع جرعات متحفوظة', (tester) async {
    await pumpAdd(tester);

    await tester.tap(find.byKey(const ValueKey('count-4')));
    await settle(tester);

    await walk(tester, 4);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(4), reason: 'روشتة أربع مرات لازم تعدّي');
    expect(
      [for (final s in saved) if (s.timing case AnchorTiming(:final anchor)) anchor],
      unorderedEquals([DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner, DayAnchor.sleep]),
    );
  });

  screenTest('«أكتر» بتفتح بكرة — خانة لفوق = ٦ مرات، وبتمشي ٦ محرّرات', (tester) async {
    await pumpAdd(tester);
    expect(find.byKey(const ValueKey('count-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('count-more')));
    await settle(tester);
    expect(find.byKey(const ValueKey('count-field')), findsOneWidget);
    expect(find.text('٥ مرات'), findsOneWidget, reason: 'البكرة بتبدأ من بعد آخر شريحة');

    await tester.drag(find.byKey(const ValueKey('count-field')), const Offset(0, -FNumberWheel.itemExtent));
    await settle(tester);

    await walk(tester, 6);
    expect(await h.meds.activeSchedules(h.services.patientId), hasLength(6));
  });

  screenTest('الأرضية والسقف من البكرة نفسها: مفيش أقل من ٥ ولا أكتر من ١٢', (tester) async {
    await pumpAdd(tester);
    await tester.tap(find.byKey(const ValueKey('count-more')));
    await settle(tester);
    // لتحت بكتير → واقفة عند ٥
    await tester.drag(find.byKey(const ValueKey('count-field')), const Offset(0, FNumberWheel.itemExtent * 20));
    await settle(tester);
    expect(find.text('٥ مرات'), findsOneWidget);
    // لفوق بكتير → واقفة عند ١٢، وبكلمتها الصح
    await tester.drag(find.byKey(const ValueKey('count-field')), const Offset(0, -FNumberWheel.itemExtent * 40));
    await settle(tester);
    expect(find.text('١٢ مرة'), findsOneWidget);
    expect(find.text('١٣ مرة'), findsNothing);
  });

  screenTest('سطر روشتة بأربع جرعات بيوصل بأربعتهم، والعدّاد واقف على ٤', (tester) async {
    await pumpAdd(tester, timings: fourTimes);

    // الشريحة بتقول الحقيقة — قبل كده العدّاد كان مخبّي خالص في طريق الورقة
    final chip = tester.widget<InkWell>(
      find.descendant(of: find.byKey(const ValueKey('count-4')), matching: find.byType(InkWell)),
    );
    expect(chip.onTap, isNotNull);
    expect(find.textContaining('دي اللي الورقة قالتها'), findsOneWidget);

    await walk(tester, 4);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(4));
    expect(saved.map((s) => s.timing), containsAll(fourTimes),
        reason: 'مراسي الورقة زي ما هي — مش عُرفنا');
  });

  screenTest('دوسة تانية على الشريحة المختارة ما بترميش مراسي الورقة', (tester) async {
    await pumpAdd(tester, timings: fourTimes);

    await tester.tap(find.byKey(const ValueKey('count-4')));
    await settle(tester);

    await walk(tester, 4);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.map((s) => s.timing), containsAll(fourTimes));
  });

  screenTest('تغيير العدد بإيد بيعيد البناء من العُرف — ٤ → ٢', (tester) async {
    await pumpAdd(tester, timings: fourTimes);

    await tester.tap(find.byKey(const ValueKey('count-2')));
    await settle(tester);

    await walk(tester, 2);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(2));
    expect(
      [for (final s in saved) if (s.timing case AnchorTiming(:final anchor)) anchor],
      unorderedEquals([DayAnchor.breakfast, DayAnchor.dinner]),
    );
  });
}
