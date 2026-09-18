import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/services/reminder_plan.dart' show isDoseId;
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_row.dart';

import '../scan/scan_test_support.dart';

/// عدد جرعات الدوا بيتظبط **قبل** ما يتحفظ: «شيل» و«أضف جرعة» على قايمة
/// الجرعات، والأرضية جرعة واحدة.
///
/// ده اللي كان ناقص: سطر روشتة بأربع جرعات ما كانش ينفع يتعدّل لاتنين، لأن
/// العدد كان جاي من الورقة وخلاص.
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

  /// بيمشي في محرّر الجرعة [count] مرة ويحفظ.
  Future<void> walk(WidgetTester tester, int count) async {
    await tester.tap(find.text('كمّل — إمتى؟'));
    await settle(tester);
    for (var i = 1; i <= count; i++) {
      await tester.tap(find.text(i == count ? 'احفظ الجرعة' : 'الجرعة اللي بعدها'));
      await settle(tester);
    }
  }

  screenTest('٤ → ٢: «شيل» مرتين بيحفظ جرعتين، والتذكيرات المجدولة للاتنين الباقيين بس',
      (tester) async {
    await pumpAdd(tester, timings: fourTimes);
    expect(find.byType(DoseRow), findsNWidgets(4));

    // «شيل» الصحيان والغدا — الفاضل الفطار والعشا
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dose-row-0')), matching: find.text('شيل')));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dose-row-1')), matching: find.text('شيل')));
    await settle(tester);
    expect(find.byType(DoseRow), findsNWidgets(2));

    await walk(tester, 2);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(2), reason: 'اتنين اتشالوا قبل الحفظ — فمفيش صفوف ليهم');
    expect(
      [for (final s in saved) if (s.timing case AnchorTiming(:final anchor)) anchor],
      unorderedEquals([DayAnchor.breakfast, DayAnchor.dinner]),
    );

    // التذكيرات المجدولة (نطاق الجرعات — من غير درجات التصعيد) على الفطار
    // والعشا بس: ولا تذكير للصحيان ولا الغدا اللي اتشالوا.
    final doseTimes = {
      for (final e in h.sink.scheduled.entries)
        if (isDoseId(e.key)) '${e.value.at.hour}:${e.value.at.minute.toString().padLeft(2, '0')}',
    };
    expect(doseTimes, {'7:30', '20:00'});
  });

  screenTest('١ → ٢: «أضف جرعة» بيحفظ جرعتين', (tester) async {
    await pumpAdd(tester, timings: const [AnchorTiming(DayAnchor.breakfast, 0)]);
    expect(find.byType(DoseRow), findsOneWidget);

    await tester.tap(find.text('أضف جرعة'));
    await settle(tester);
    expect(find.byType(DoseRow), findsNWidgets(2));

    await walk(tester, 2);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved, hasLength(2));
    expect(saved.map((s) => s.medicationName).toSet(), {'Augmentin'});
  });

  screenTest('الأرضية: جرعة واحدة مالهاش «شيل» — لا من الورقة ولا بعد ما تشيل الباقي',
      (tester) async {
    await pumpAdd(tester, timings: const [AnchorTiming(DayAnchor.breakfast, 0)]);
    expect(find.text('شيل'), findsNothing, reason: 'آخر جرعة مالهاش شيل');

    await tester.tap(find.text('أضف جرعة'));
    await settle(tester);
    expect(find.text('شيل'), findsNWidgets(2));

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dose-row-1')), matching: find.text('شيل')));
    await settle(tester);
    expect(find.byType(DoseRow), findsOneWidget);
    expect(find.text('شيل'), findsNothing, reason: 'رجعنا للأرضية');

    await walk(tester, 1);
    expect(await h.meds.activeSchedules(h.services.patientId), hasLength(1));
  });

  screenTest('«كام مرة» لسه بتشتغل في الإدخال اليدوي — وبتعيد بناء القايمة', (tester) async {
    await pumpAdd(tester);
    expect(find.byType(DoseRow), findsOneWidget, reason: 'الافتراضي مرة واحدة');

    await tester.tap(find.text('٣ مرات'));
    await settle(tester);
    expect(find.byType(DoseRow), findsNWidgets(3));

    // وبعد كده «أضف جرعة» بتزوّد على العُرف
    await tester.tap(find.text('أضف جرعة'));
    await settle(tester);
    expect(find.byType(DoseRow), findsNWidgets(4));
  });
}
