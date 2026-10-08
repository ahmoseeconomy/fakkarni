import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';

import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
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
    FixedTiming(MinuteOfDay.hm(7)),
    FixedTiming(MinuteOfDay.hm(7, 30)),
    FixedTiming(MinuteOfDay.hm(14, 30)),
    FixedTiming(MinuteOfDay.hm(20)),
  ];

  Future<void> pumpAdd(WidgetTester tester, {List<FixedTiming> timings = const []}) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(
      tester,
      AddMedicationScreen(
        
        today: aug31,
        initialName: 'Augmentin',
        initialTimings: timings,
      ),
    );
  }

  /// [count] صف جرعة ظاهرين في الفورم — مفيش مشي — وبعدها «احفظ».
  ///
  /// جرعة واحدة = **مفيش كارت صفوف أصلاً** (المالك، ٥ أكتوبر ٢٠٢٦ مساءً):
  /// ساعتها من «الساعة كام؟» فوق، وصف واحد كان بيكرّر نفس الرقم.
  Future<void> walk(WidgetTester tester, int count) async {
    if (count < 2) {
      expect(find.byKey(const ValueKey('dose-row-0')), findsNothing,
          reason: 'جرعة واحدة = الكارت مستخبي');
    } else {
      for (var i = 0; i < count; i++) {
        expect(find.byKey(ValueKey('dose-row-$i')), findsOneWidget, reason: 'صف $i من $count');
      }
      expect(find.byKey(ValueKey('dose-row-$count')), findsNothing);
    }
    // الصفوف فاضية من غير ساعات مننا — أول ساعة بيختارها هو (البكرة؛
    // الشرايح السريعة اتشالت) وبتوزّع الباقي
    if (find.text('اختار الساعة').evaluate().isNotEmpty) {
      await pickTime(tester, const MinuteOfDay(9 * 60));
    }
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
  }

  screenTest('مفيش زرار يضيف ولا يشيل جرعة في «ضيف دوا» — ولا قايمة أصلاً', (tester) async {
    await pumpAdd(tester);

    expect(find.byType(DoseRow), findsNothing);
    expect(find.text('أضف جرعة'), findsNothing);
    expect(find.text('شيل'), findsNothing);
    expect(find.text('جرعات اليوم'), findsNothing);
    // اللي فاضل: بكرة العدد (الشرايح بقت بكرة — ٥ أكتوبر ٢٠٢٦)
    expect(find.byKey(const ValueKey('count-wheel')), findsOneWidget);
    expect(find.text('مرتين'), findsOneWidget, reason: 'صفوف البكرة — «أكتر» آخرها (بعيد عن نافذة الرسم هنا، واختباره تحت)');
    expectNoRedAndMinSize(tester);
  });

  screenTest('«٤ مرات» → أربع محرّرات وأربع جرعات متحفوظة', (tester) async {
    await pumpAdd(tester);

    await pickWheel(tester, const ValueKey('count-wheel'), 3); // «٤ مرات»

    await walk(tester, 4);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(4), reason: 'روشتة أربع مرات لازم تعدّي');
    expect(
      [for (final s in saved) s.timing.minuteOfDay],
      unorderedEquals([MinuteOfDay.hm(9), MinuteOfDay.hm(13), MinuteOfDay.hm(17), MinuteOfDay.hm(21)]),
      reason: 'أول ساعة اختارها (٩) والباقي اتوزّع قدّامه',
    );
  });

  screenTest('«أكتر» بتفتح بكرة — خانة لفوق = ٦ مرات، وبتمشي ٦ محرّرات', (tester) async {
    await pumpAdd(tester);
    expect(find.byKey(const ValueKey('count-field')), findsNothing);

    await pickWheel(tester, const ValueKey('count-wheel'), 4); // «أكتر»
    expect(find.byKey(const ValueKey('count-field')), findsOneWidget);
    expect(find.text('٥ مرات'), findsOneWidget, reason: 'البكرة بتبدأ من بعد آخر صف رقمي');

    await tester.drag(find.byKey(const ValueKey('count-field')), const Offset(0, -FNumberWheel.itemExtent));
    await settle(tester);

    await walk(tester, 6);
    expect(await h.meds.activeSchedules(h.services.patientId), hasLength(6));
  });

  screenTest('الأرضية والسقف من البكرة نفسها: مفيش أقل من ٥ ولا أكتر من ١٢', (tester) async {
    await pumpAdd(tester);
    await pickWheel(tester, const ValueKey('count-wheel'), 4); // «أكتر»
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

    // البكرة بتقول الحقيقة — واقفة على «٤ مرات» (قبل كده العدّاد كان
    // مخبّي خالص في طريق الورقة)
    final picker = tester.widget<CupertinoPicker>(find.byKey(const ValueKey('count-wheel')));
    expect(picker.scrollController!.selectedItem, 3, reason: 'صف «٤ مرات»');
    expect(find.textContaining('دي اللي فهمناها من الورقة'), findsOneWidget);

    await walk(tester, 4);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(4));
    expect(saved.map((s) => s.timing), containsAll(fourTimes),
        reason: 'ساعات الورقة زي ما هي — مش عُرفنا');
  });

  screenTest('اختيار نفس العدد تاني ما بيرميش مراسي الورقة', (tester) async {
    await pumpAdd(tester, timings: fourTimes);

    // البكرة واقفة على ٤ خلاص — «اختياره تاني» لازم يبقى بلا أثر
    await pickWheel(tester, const ValueKey('count-wheel'), 3);

    await walk(tester, 4);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.map((s) => s.timing), containsAll(fourTimes));
  });

  // كان «بيعيد البناء — صفوف فاضية»؛ قرار المالك (٦ أكتوبر ٢٠٢٦) بدّله:
  // التقليل بيشيل من الآخر والباقي بساعاته.
  screenTest('تقليل العدد بإيد بيشيل من الآخر — ٤ → ٢ والصفّين الأولانيين بساعاتهم', (tester) async {
    await pumpAdd(tester, timings: fourTimes);

    await pickWheel(tester, const ValueKey('count-wheel'), 1); // «مرتين»

    await walk(tester, 2);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(2));
    expect(
      [for (final s in saved) s.timing.minuteOfDay],
      unorderedEquals([MinuteOfDay.hm(7), MinuteOfDay.hm(7, 30)]),
      reason: 'الجرعتين اللي فضلوا هما أول اتنين بساعاتهم — مفيش مسح',
    );
  });
}
