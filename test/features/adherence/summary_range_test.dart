// «غيّر المدة» على ملخص الأسبوع (المالك، ٥ أكتوبر ٢٠٢٦ مساءً): «من/إلى»
// ببكرتين، الافتراضي آخر ٧ أيام كاملة زي ما كان، والمدة المختارة بتعيد
// القراية والحساب — عند المريض من القاعدة، وعند الابن/الممرض من الصورة
// (محدودة بأيامها).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/features/adherence/summary_range.dart';
import 'package:fakkarni/features/adherence/weekly_summary_card.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final now = DateTime(2026, 8, 31, 10);

  Future<void> seed() async {
    final med = await h.meds.addMedicationWithDoses(
      patientId: h.services.patientId,
      name: 'Concor',
      timings: [FixedTiming(MinuteOfDay.hm(9))],
      startDate: DateTime(2026, 8, 1),
    );
    final sid = int.parse((await h.meds.activeSchedules(h.services.patientId)).single.id);
    expect(med, isPositive);
    // أسبوعين ورا: ١٩–٢١ أغسطس (المدة القديمة) و٢٦–٢٨ (جوّه الافتراضي)
    for (final day in [19, 20, 21, 26, 27, 28]) {
      // confirmDose بيزرع الصف لو مش موجود — markTaken بيعدّل الموجود بس
      await h.services.events.confirmDose(
        doseScheduleId: sid,
        routineDay: DateTime(2026, 8, day),
        scheduledAt: DateTime(2026, 8, day, 9),
        state: DoseState.taken,
      );
    }
  }

  screenTest('الافتراضي آخر ٧ كاملة — و«غيّر المدة» بالبكرتين بيعيد القراية والعنوان بيقول «الملخص»', (tester) async {
    await seed();
    await h.pump(tester, Scaffold(body: ListView(children: [PatientWeeklySummary(now: now)])));

    // الافتراضي (٢٤–٣٠ أغسطس): التلات أيام اللي جوّاه بس
    expect(find.textContaining('ملخص الأسبوع'), findsOneWidget);
    expect(find.textContaining('اتاخد ٣ من ٣'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('summary-range')));
    await settle(tester);
    expect(find.text('الملخص من إمتى لإمتى؟'), findsOneWidget);

    // «من» = ١٩ أغسطس (قبل الافتراضي بـ٥ أيام)، «إلى» = ٢١ أغسطس
    await pickWheel(tester, const ValueKey('range-from-wheel'), 30 - 12);
    await pickWheel(tester, const ValueKey('range-to-wheel'), 30 - 10);
    await tester.tap(find.byKey(const ValueKey('range-save')));
    await settle(tester);

    expect(find.textContaining('الملخص — ١٩ أغسطس'), findsOneWidget, reason: 'مدة مش أسبوع = «الملخص»');
    expect(find.textContaining('اتاخد ٣ من ٣'), findsOneWidget, reason: 'تلات أيام المدة القديمة');
  });

  screenTest('«من» بعد «إلى» = جملة و«تمام» مقفول — مفيش مدة مقلوبة بتتحسب في صمت', (tester) async {
    await seed();
    await h.pump(tester, Scaffold(body: ListView(children: [PatientWeeklySummary(now: now)])));
    await tester.tap(find.byKey(const ValueKey('summary-range')));
    await settle(tester);

    await pickWheel(tester, const ValueKey('range-to-wheel'), 0); // «إلى» أقدم يوم
    expect(find.byKey(const ValueKey('range-invalid')), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.descendant(of: find.byKey(const ValueKey('range-save')), matching: find.byType(FilledButton)),
    );
    expect(save.onPressed, isNull);
  });

  test('SummaryRange.lastWeek = آخر ٧ أيام كاملة — النهارده برّه', () {
    final r = SummaryRange.lastWeek(DateTime(2026, 8, 31, 23));
    expect(r.from, DateTime(2026, 8, 24));
    expect(r.to, DateTime(2026, 8, 30));
  });
}
