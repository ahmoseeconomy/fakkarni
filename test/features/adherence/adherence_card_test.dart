import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/adherence/patient_adherence_card.dart';

import '../scan/scan_test_support.dart';

/// كارت «إنت ماشي إزاي»: العدّ، الصفر، الإخفاء أول يومين، ونمط كبار السن.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  // الخميس ٢٤ سبتمبر ٢٠٢٦، ٦ المسا
  final today = DateTime(2026, 9, 24);
  final now = DateTime(2026, 9, 24, 18);

  Future<int> seedMed() async {
    await h.meds.addMedication(
      patientId: h.services.patientId,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: DateTime(2026, 9, 1),
    );
    return (await h.db.select(h.db.doseSchedules).get()).single.id;
  }

  Future<void> seedDay(int scheduleId, DateTime day, DoseState state) => h.db.into(h.db.doseEvents).insert(
        DoseEventsCompanion.insert(
          doseScheduleId: scheduleId,
          routineDay: day,
          scheduledAt: DateTime(day.year, day.month, day.day, 8),
          state: state,
        ),
      );

  Future<void> pumpCard(WidgetTester tester, {bool elder = false}) =>
      h.pump(tester, Scaffold(body: ListView(children: [PatientAdherenceCard(routineDay: today, now: now, elder: elder)])));

  screenTest('خمس أيام كاملة ورا بعض → «٥ أيام ورا بعض» والنقط', (tester) async {
    final id = await seedMed();
    for (var i = 5; i >= 1; i--) {
      await seedDay(id, DateTime(2026, 9, 24 - i), DoseState.taken);
    }
    await pumpCard(tester);

    expect(find.text('إنت ماشي إزاي'), findsOneWidget);
    expect(find.text('٥ أيام ورا بعض'), findsOneWidget);
    expect(find.byKey(const ValueKey('adherence-dots')), findsOneWidget);
    // سبت ← الأربع كاملين (١٩–٢٣)، الخميس محايد (مفيش صف)، الجمعة لسه
    expect(find.byKey(const ValueKey('adherence-dot-4-complete')), findsOneWidget);
    expect(find.byKey(const ValueKey('adherence-dot-6-upcoming')), findsOneWidget);
    expect(find.text('شوف التفاصيل'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('العدّ صفر → «النهارده بداية جديدة» ونقطة رمادي مش حمرا', (tester) async {
    final id = await seedMed();
    await seedDay(id, DateTime(2026, 9, 20), DoseState.taken);
    await seedDay(id, DateTime(2026, 9, 23), DoseState.missed);
    await pumpCard(tester);

    expect(find.text('النهارده بداية جديدة'), findsOneWidget);
    final dot = tester.widget<Container>(find.descendant(
        of: find.byKey(const ValueKey('adherence-dot-4-missed')), matching: find.byType(Container)).first);
    expect((dot.decoration as BoxDecoration).color, F.line, reason: 'الفايت رمادي هادي');
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.data ?? '', isNot(contains('فشل')));
    }
    expectNoRedAndMinSize(tester);
  });

  screenTest('أول يومين بعد أول دوا: الكارت مش موجود، والتالت بيظهر', (tester) async {
    final id = await seedMed();
    await seedDay(id, DateTime(2026, 9, 23), DoseState.taken);
    await seedDay(id, today, DoseState.taken);
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('adherence-card')), findsNothing);

    await seedDay(id, DateTime(2026, 9, 22), DoseState.taken);
    await settle(tester);
    expect(find.byKey(const ValueKey('adherence-card')), findsOneWidget);
  });

  screenTest('مفيش أدوية خالص: مفيش كارت', (tester) async {
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('adherence-card')), findsNothing);
  });

  screenTest('نمط كبار السن: الرقم أكبر، والنقط ≥ ٢٨، ومن غير «أخدتها متأخر»', (tester) async {
    final id = await seedMed();
    await seedDay(id, DateTime(2026, 9, 21), DoseState.taken);
    await seedDay(id, DateTime(2026, 9, 22), DoseState.taken);
    await seedDay(id, today, DoseState.missed);
    await pumpCard(tester, elder: true);

    final big = tester.widget<Text>(find.byKey(const ValueKey('adherence-streak')));
    expect(big.style!.fontSize, greaterThanOrEqualTo(F.elderTitleSize));
    for (final e in tester.elementList(find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('adherence-dot-')))) {
      expect(e.size!.width, greaterThanOrEqualTo(28));
    }

    await tester.tap(find.byKey(const ValueKey('adherence-card')));
    await settle(tester);
    expect(find.text('فاتك كام جرعة الأسبوع ده'), findsOneWidget);
    expect(find.text('أخدتها متأخر'), findsNothing, reason: 'نمط كبار السن: مكان واحد للتأكيد');
  });

  screenTest('التفاصيل: «أخدتها متأخر» على فايت النهارده بس — ونفس سكّة التأكيد بتكتبه', (tester) async {
    final id = await seedMed();
    await seedDay(id, DateTime(2026, 9, 20), DoseState.taken);
    await seedDay(id, DateTime(2026, 9, 21), DoseState.missed);
    await seedDay(id, DateTime(2026, 9, 22), DoseState.taken);
    await seedDay(id, today, DoseState.missed);
    await pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('adherence-card')));
    await settle(tester);
    expect(find.byKey(const ValueKey('adherence-percent')), findsOneWidget);
    expect(find.byKey(const ValueKey('adherence-best')), findsOneWidget);
    expect(find.text('أخدتها متأخر'), findsOneWidget, reason: 'فايت يوم ٢١ مالوش زرار — بس النهارده');

    await tester.tap(find.text('أخدتها متأخر'));
    await settle(tester);
    final row = (await h.db.select(h.db.doseEvents).get()).firstWhere((e) => e.routineDay == today);
    expect(row.state, DoseState.taken);
    expect(find.text('أخدتها متأخر'), findsNothing, reason: 'الشاشة اتحدّثت من نفس الصفوف');
  });
}
