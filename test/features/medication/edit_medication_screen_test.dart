import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';
import 'package:fakkarni/features/medication/dose_row.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<int> seedTelfast({bool unknown = true}) => h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Telfast 180 mg',
        timing: const AnchorTiming(DayAnchor.dinner, 0),
        startDate: aug31,
        amountLabel: unknown ? null : 'قرص واحد',
        amountUnknown: unknown,
      );

  Future<void> pumpEdit(WidgetTester tester, int id) =>
      h.pump(tester, EditMedicationScreen(medicationId: id));

  screenTest('الاسم والقاعدة، وتنبيه ذهبي لو الجرعة مش معروفة', (tester) async {
    final id = await seedTelfast();
    await pumpEdit(tester, id);

    expect(find.text('Telfast 180 mg'), findsOneWidget);
    expect(find.textContaining('العشا'), findsOneWidget);
    final gold = tester.widget<Text>(find.textContaining('اسأل الصيدلي واكتبها هنا'));
    // ذهبي على الحافة، والنص غامق يتقري (الذهبي كنص ≈ ١.٩:١)
    expect(gold.style?.color, F.ink);
    expect(find.ancestor(of: find.textContaining('اسأل الصيدلي واكتبها هنا'), matching: find.byType(GoldNote)), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«عدّل» على الجرعة بيفتح محرّر الجرعة بتوقيتها، والحفظ بيغيّر الصف نفسه', (tester) async {
    final id = await seedTelfast(unknown: false);
    await pumpEdit(tester, id);

    expect(find.textContaining('العشا'), findsOneWidget);
    await tester.tap(find.text('عدّل'));
    await settle(tester);
    expect(find.byType(DoseEditor), findsOneWidget);
    // متعبّي بالتوقيت الحالي: العشا، إزاحة ٠
    expect(find.text('٠ دقيقة'), findsOneWidget);

    await tester.tap(find.text('قبل الفطار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    expect(find.byType(EditMedicationScreen), findsOneWidget);
    final loaded = (await h.meds.schedulesFor(id)).single;
    expect(loaded.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    expect(find.textContaining('الفطار − ٣٠ د'), findsOneWidget);
  });

  screenTest('كتابة الجرعة وحفظها بتقفل «مش معروفة» وبتعيد الجدولة', (tester) async {
    final id = await seedTelfast();
    await h.services.scheduler.rescheduleAll();
    expect(h.sink.scheduled.values.first.body, 'Telfast 180 mg');

    await pumpEdit(tester, id);
    await tester.enterText(find.byType(TextField), 'قرص واحد');
    await tester.tap(find.text('احفظ'));
    await settle(tester);

    final row = (await h.db.select(h.db.medications).get()).single;
    expect(row.amountLabel, 'قرص واحد');
    expect(row.amountUnknown, isFalse);
    // نص التذكير اتحدّث بالجرعة
    expect(h.sink.scheduled.values.first.body, 'Telfast 180 mg — قرص واحد');
    expect(find.byType(EditMedicationScreen), findsNothing);
  });

  screenTest('حفظ نص فاضي بيسيبها «مش معروفة» — مفيش قيمة مخترعة', (tester) async {
    final id = await seedTelfast(unknown: false);
    await pumpEdit(tester, id);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('احفظ'));
    await settle(tester);

    final row = (await h.db.select(h.db.medications).get()).single;
    expect(row.amountLabel, isNull);
    expect(row.amountUnknown, isTrue);
  });

  screenTest('«أضف جرعة» لدوا موجود بتكتب صف جديد وبتجدول تذكيره — نفس طريق الروشتة', (tester) async {
    final id = await seedTelfast(unknown: false);
    await pumpEdit(tester, id);
    expect(find.byType(DoseRow), findsOneWidget);

    await tester.tap(find.text('أضف جرعة'));
    await settle(tester);
    expect(find.byType(DoseEditor), findsOneWidget);
    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    final saved = await h.meds.schedulesFor(id);
    expect(saved, hasLength(2), reason: 'الجرعة الجديدة صف جديد، والقديمة زي ما هي');
    expect(find.byType(DoseRow), findsNWidgets(2), reason: 'والقايمة بتتحدّث');

    // التذكير الجديد اتجدول
    final doseTimes = {
      for (final e in h.sink.scheduled.entries)
        if (isDoseId(e.key)) '${e.value.at.hour}:${e.value.at.minute.toString().padLeft(2, '0')}',
    };
    expect(doseTimes, hasLength(2));
  });

  screenTest('الإيقاف بخطوتين: سؤال واضح، «لا، سيبه» بترجّع من غير ما توقف', (tester) async {
    final id = await seedTelfast(unknown: false);
    await pumpEdit(tester, id);

    await tester.tap(find.text('وقّف الدوا ده'));
    await tester.pumpAndSettle();
    expect(find.textContaining('توقّف Telfast 180 mg؟'), findsOneWidget);
    // وزرار الحفظ مقفول وإحنا في السؤال
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احفظ'));
    expect(save.onPressed, isNull);

    await tester.tap(find.text('لا، سيبه'));
    await tester.pumpAndSettle();
    expect(find.textContaining('توقّف'), findsNothing);
    expect((await h.db.select(h.db.medications).get()).single.stoppedAt, isNull);
  });

  screenTest('«أيوه، وقّفه» بتوقفه بإيد إنسان وبتلغي تذكيراته', (tester) async {
    final id = await seedTelfast(unknown: false);
    await h.services.scheduler.rescheduleAll();
    expect(h.sink.scheduled, isNotEmpty);

    await pumpEdit(tester, id);
    await tester.tap(find.text('وقّف الدوا ده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أيوه، وقّفه'));
    await settle(tester);

    expect((await h.db.select(h.db.medications).get()).single.stoppedAt, isNotNull);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
    expect(h.sink.scheduled.values.where((p) => isDoseId(p.id)), isEmpty);
    expect(find.byType(EditMedicationScreen), findsNothing);
  });

  screenTest('الأزرار: احفظ ٦٤، الإيقاف ٥٦، وجوابا التأكيد بنفس الحجم', (tester) async {
    final id = await seedTelfast();
    await pumpEdit(tester, id);

    expect(tester.getSize(find.widgetWithText(FilledButton, 'احفظ')).height, F.primaryButtonHeight);
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'وقّف الدوا ده')).height, F.minTapTarget);

    await tester.tap(find.text('وقّف الدوا ده'));
    await tester.pumpAndSettle();
    final yes = tester.getSize(find.widgetWithText(FilledButton, 'أيوه، وقّفه'));
    final no = tester.getSize(find.widgetWithText(OutlinedButton, 'لا، سيبه'));
    expect(yes, no);
    expectNoRedAndMinSize(tester);
  });

  group('من «يومك»', () {
    Future<void> pumpToday(WidgetTester tester) =>
        h.pump(tester, TodayScreen(routine: normalDay, now: DateTime(2026, 8, 31, 8)));

    screenTest('«اسأل الصيدلي عن جرعة …» بتفتح شاشة التعديل', (tester) async {
      await seedTelfast();
      await pumpToday(tester);

      await tester.tap(find.text('اسأل الصيدلي عن جرعة Telfast 180 mg'));
      await settle(tester);

      expect(find.byType(EditMedicationScreen), findsOneWidget);
    });

  });

  // قايمة «أدويتك» اتنقلت من «جدول النهاردة» لتبويب «الأدوية» (D2.1)
  group('من تبويب «الأدوية»', () {
    Future<void> pumpMeds(WidgetTester tester) => h.pump(tester, MedicationsScreen(today: aug31));

    screenTest('«جدول الأدوية»: مجمّع بالمرساة، الاسم والجرعة — القاعدة، و«عدّل» بيفتح التعديل', (tester) async {
      await seedTelfast(unknown: false);
      await pumpMeds(tester);

      expect(find.text('جدول الأدوية'), findsOneWidget);
      expect(find.text('العشا — ٨:٠٠ م'), findsOneWidget, reason: 'عنوان المجموعة بالمرساة والوقت');
      expect(find.text('قرص واحد — العشا'), findsOneWidget);

      // «خيارات» → شيت التلات أفعال → «عدّل»
      await tester.tap(find.text('خيارات'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'عدّل'));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsOneWidget);
    });

    screenTest('الدوا الموقوف بيفضل باين تحت «موقوفة» — ما يختفيش', (tester) async {
      final id = await seedTelfast(unknown: false);
      await h.meds.stopMedication(id);
      await pumpMeds(tester);

      expect(find.text('موقوفة'), findsOneWidget);
      expect(find.text('Telfast 180 mg'), findsOneWidget);
      expect(find.text('موقوف — التذكيرات واقفة'), findsOneWidget);
      expect(find.textContaining('العشا — '), findsNothing, reason: 'مش في مجموعة مرساة');
    });

    screenTest('«جدول النهاردة» مابقاش فيه قايمة «أدويتك»', (tester) async {
      await seedTelfast(unknown: false);
      await h.pump(tester, TodayScreen(routine: normalDay, now: DateTime(2026, 8, 31, 8)));
      expect(find.text('أدويتك'), findsNothing);
    });
  });

  /// **عدد الجرعات لدوا محفوظ بيتغيّر من هنا** — الحالتين دول كانوا على
  /// قايمة «ضيف دوا» قبل ما تتشال. هنا صح أكتر: الصفوف حقيقية، فالشيل
  /// بيوقف تذكير فعلاً، والأرضية بتتفرض على اللي في القاعدة مش على قايمة
  /// في الذاكرة.
  group('كام جرعة لدوا موجود', () {
    const fourTimes = [
      AnchorTiming(DayAnchor.wake, 0),
      AnchorTiming(DayAnchor.breakfast, 0),
      AnchorTiming(DayAnchor.lunch, 0),
      AnchorTiming(DayAnchor.dinner, 0),
    ];

    Future<int> seedFour() => h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: 'Augmentin',
          timings: fourTimes,
          startDate: aug31,
          amountLabel: 'قرص',
        );

    Future<void> removeRow(WidgetTester tester, int index) async {
      await tester.tap(find.descendant(
        of: find.byKey(ValueKey('dose-row-$index')),
        matching: find.text('شيل'),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('remove-dose-confirm')));
      await settle(tester);
    }

    screenTest('٤ → ٢: «شيل» مرتين، والتذكيرات بتفضل للاتنين الباقيين بس', (tester) async {
      final id = await seedFour();
      await pumpEdit(tester, id);
      expect(find.byType(DoseRow), findsNWidgets(4));

      // شيل الصحيان والغدا — الفاضل الفطار والعشا
      await removeRow(tester, 0);
      await removeRow(tester, 1);

      expect(find.byType(DoseRow), findsNWidgets(2));
      final left = await h.meds.schedulesFor(id);
      expect(left, hasLength(2));
      expect(
        [for (final s in left) if (s.timing case AnchorTiming(:final anchor)) anchor],
        unorderedEquals([DayAnchor.breakfast, DayAnchor.dinner]),
      );

      final doseTimes = {
        for (final e in h.sink.scheduled.entries)
          if (isDoseId(e.key)) '${e.value.at.hour}:${e.value.at.minute.toString().padLeft(2, '0')}',
      };
      expect(doseTimes, {'7:30', '20:00'}, reason: 'ولا تذكير للصحيان ولا الغدا');
    });

    screenTest('١ → ٢: «أضف جرعة» بتكتب صف جديد', (tester) async {
      final id = await seedTelfast(unknown: false);
      await pumpEdit(tester, id);
      expect(find.byType(DoseRow), findsOneWidget);

      await tester.tap(find.text('أضف جرعة'));
      await settle(tester);
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      expect(find.byType(DoseRow), findsNWidgets(2));
      expect(await h.meds.schedulesFor(id), hasLength(2));
    });

    screenTest('الأرضية: آخر جرعة مالهاش «شيل» خالص', (tester) async {
      final id = await seedTelfast(unknown: false);
      await pumpEdit(tester, id);
      expect(find.byType(DoseRow), findsOneWidget);
      expect(find.text('شيل'), findsNothing, reason: 'دوا من غير جرعة مش دوا');

      // اتنين → فيه شيل؛ ونرجع لواحدة → يختفي تاني
      await tester.tap(find.text('أضف جرعة'));
      await settle(tester);
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);
      expect(find.text('شيل'), findsNWidgets(2));

      await removeRow(tester, 1);
      expect(find.byType(DoseRow), findsOneWidget);
      expect(find.text('شيل'), findsNothing, reason: 'رجعنا للأرضية');
      expect(await h.meds.schedulesFor(id), hasLength(1));
    });

    screenTest('الشيل إيقاف ناعم: الصف بيفضل في القاعدة، والأحداث الجاية superseded',
        (tester) async {
      final id = await seedFour();
      await pumpEdit(tester, id);
      await removeRow(tester, 0);

      // مفيش مسح — الصف مكانه بـstopped_at
      final all = await h.db.select(h.db.doseSchedules).get();
      expect(all, hasLength(4), reason: 'مسح حقيقي كان هيخلّي الابن يتصعّد على جرعة مش موجودة');
      expect(all.where((s) => s.stoppedAt != null), hasLength(1));
    });
  });
}
