// ملخص الأسبوع في «ملفّي» عند المريض (طلب المدير، ٤ أكتوبر ٢٠٢٦) — من
// القاعدة المحلية، آخر ٧ أيام كاملة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep15 = DateTime(2026, 9, 15, 10);

  screenTest('«ملفّي»: الكارت بالأرقام من القاعدة، وقرب يخلص، تحت العنوان وفوق المواعيد', (tester) async {
    final medId = await h.meds.addMedication(
      patientId: h.services.patientId,
      name: 'Concor 5mg',
      amountLabel: 'قرص واحد',
      timing: const FixedTiming(MinuteOfDay.hm(8)),
      startDate: DateTime(2026, 9, 1),
    );
    final scheduleId = int.parse((await h.meds.activeSchedules(h.services.patientId)).single.id);
    Future<void> day(int d, DoseState state) => h.services.events.confirmDose(
          doseScheduleId: scheduleId,
          routineDay: DateTime(2026, 9, d),
          scheduledAt: DateTime(2026, 9, d, 8),
          state: state,
        );
    await day(14, DoseState.taken);
    await day(13, DoseState.missed);
    await day(12, DoseState.taken);
    await day(15, DoseState.taken); // النهارده — برّه
    await day(7, DoseState.missed); // يوم -٨ — برّه
    await StockRepository(h.db).setQuantity(medId, 3);

    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, HealthFileScreen(today: sep15));
    await settle(tester);

    expect(find.text('ملخص الأسبوع — ٨ سبتمبر لـ١٤ سبتمبر'), findsOneWidget);
    expect(find.text('اتاخد ٢ من ٣ جرعات'), findsOneWidget);
    expect(find.text('ما اتأكدتش: ١ — Concor 5mg (الحد ٨:٠٠ ص)'), findsOneWidget);
    expect(find.text('قرب يخلص: Concor 5mg (فاضله ٣ أيام)'), findsOneWidget);
    final cardY = tester.getTopLeft(find.byKey(const ValueKey('weekly-summary'))).dy;
    expect(cardY, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('health-file-title'))).dy));
    expect(cardY, lessThan(tester.getTopLeft(find.text('مواعيدك الجاية')).dy));
    expectNoRedAndMinSize(tester);
  });
}
