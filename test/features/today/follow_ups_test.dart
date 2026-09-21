// متابعة محدش شايفها متابعة محدش بيعملها.
//
// المتابعات كانت عايشة في «الملف الصحي» بس: الراجل بيبدأ متابعة تحليل
// وبيقفل التطبيق، ومفيش حاجة على «يومك» بتفكّره بيها. الجولة دي بتحطّها
// على الشاشة اللي بيفتحها كل يوم.
//
// وحاجتين لازم يفضلوا صح:
//   * مفيش متابعات مفتوحة = **مفيش قسم خالص**، مش قسم فاضي بيقول «مفيش».
//   * المتابعة الواقفة بتتقال بالسطر الهادي الموجود (`_FollowUpPanel`) —
//     مش كارت ولا أحمر. دي حاجة بتتعمل على مهل، مش جرعة فاتت.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_display.dart';
import 'package:fakkarni/features/records/checkup_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep15 = DateTime(2026, 9, 15, 10);

  CheckupService checkups() => h.services.checkups;

  Future<int> startFollowUp(String title, {DateTime? today}) =>
      checkups().start(patientId: h.services.patientId, title: title, today: today ?? sep15);

  Future<void> pumpToday(WidgetTester tester, {DateTime? now}) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, TodayScreen(routine: normalDay, now: now ?? sep15));
    await settle(tester);
  }

  screenTest('مفيش متابعات → مفيش قسم خالص', (tester) async {
    await pumpToday(tester);
    expect(find.byKey(const ValueKey('open-follow-ups')), findsNothing);
    expect(find.text('المتابعات'), findsNothing);
  });

  screenTest('متابعتين مفتوحين → الاتنين على «يومك» باسمهم ومرحلتهم', (tester) async {
    final blood = await startFollowUp('صورة دم كاملة');
    final sugar = await startFollowUp('تحليل سكر تراكمي');
    await checkups().advance(blood, now: sep15); // حجز المعمل

    await pumpToday(tester);

    expect(find.byKey(const ValueKey('open-follow-ups')), findsOneWidget);
    expect(find.text('المتابعات'), findsOneWidget);
    expect(find.text('صورة دم كاملة'), findsOneWidget);
    expect(find.text('تحليل سكر تراكمي'), findsOneWidget);
    // النوع جنب المرحلة — القايمة فيها تحاليل وزيارات — **والميعاد**.
    // الصفوف دي كلها مالهاش ميعاد جاي (اللي ليها بتطلع في «مواعيدك
    // الجاية»)، فالسطر بيقول كده بالحرف بدل ما يعرض تاريخ الورقة.
    expect(find.text('تحليل — ${CheckupStage.labBooking.label} — $noFollowDateText'),
        findsOneWidget);
    expect(find.text('تحليل — ${CheckupStage.doctorOrder.label} — $noFollowDateText'),
        findsOneWidget);
    expect(find.byKey(ValueKey('follow-up-$blood')), findsOneWidget);
    expect(find.byKey(ValueKey('follow-up-$sugar')), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('الدوسة بتفتح شاشة المتابعة', (tester) async {
    final id = await startFollowUp('صورة دم كاملة');
    await pumpToday(tester);

    await tester.tap(find.byKey(ValueKey('follow-up-$id')));
    await settle(tester);

    expect(find.byType(CheckupScreen), findsOneWidget);
  });

  screenTest('متابعة اتوقفت بتختفي من «يومك»', (tester) async {
    final id = await startFollowUp('صورة دم كاملة');
    await checkups().delete(id, now: sep15);
    await pumpToday(tester);
    expect(find.byKey(const ValueKey('open-follow-ups')), findsNothing);
  });

  screenTest('سجل عادي مش متابعة — ما بيظهرش هنا', (tester) async {
    await RecordsRepository(h.db).add(
      patientId: h.services.patientId,
      kind: RecordKind.lab,
      title: 'HbA1c',
      happenedAt: sep15,
    );
    await pumpToday(tester);
    expect(find.byKey(const ValueKey('open-follow-ups')), findsNothing);
  });

  group('المتابعة الواقفة', () {
    /// بيوصل المتابعة لـ«حجز المعمل» ويخلّي ساعة المرحلة [since].
    Future<int> stuckSince(DateTime since) async {
      final id = await startFollowUp('صورة دم كاملة');
      await checkups().advance(id, now: since);
      return id;
    }

    screenTest('اليوم السادس: مفيش سطر', (tester) async {
      await stuckSince(sep15);
      await pumpToday(tester, now: DateTime(2026, 9, 21, 10));
      expect(find.textContaining('واقفة عند'), findsNothing);
    });

    screenTest('اليوم السابع: سطر هادي واحد، وبيفتح المتابعة', (tester) async {
      final id = await stuckSince(sep15);
      await pumpToday(tester, now: DateTime(2026, 9, 22, 10));

      final line = find.text('متابعة تحليل صورة دم كاملة واقفة عند ${CheckupStage.labBooking.label}');
      expect(line, findsOneWidget);
      // هادي: نص باهت في اللوحة الموجودة، مش كارت ولا أحمر
      expect(tester.widget<Text>(line).style?.color, isNot(F.ink));
      expectNoRedAndMinSize(tester);

      await tester.tap(line);
      await settle(tester);
      expect(find.byType(CheckupScreen), findsOneWidget);
      expect(find.byKey(ValueKey('stage-date-set-${CheckupStage.labBooking.number}')), findsOneWidget,
          reason: 'السطر بيوصّل للمكان اللي بيتحلّ فيه');
      expect(id, greaterThan(0));
    });

    screenTest('ميعاد متحطّ → مفيش سطر، مهما طال الوقت', (tester) async {
      final id = await stuckSince(sep15);
      await checkups().setStageDate(
        id,
        CheckupStage.labBooking,
        day: DateTime(2026, 9, 18),
        now: sep15,
      );

      await pumpToday(tester, now: DateTime(2026, 10, 30, 10));
      expect(find.textContaining('واقفة عند'), findsNothing);
    });

    screenTest('مرحلة ما بتسألش عن ميعاد عمرها ما تقف', (tester) async {
      final id = await startFollowUp('صورة دم كاملة');
      await checkups().advance(id, now: sep15); // حجز المعمل
      await checkups().advance(id, now: sep15); // التحضير — مالهاش سؤال

      await pumpToday(tester, now: DateTime(2026, 10, 30, 10));
      expect(find.textContaining('واقفة عند'), findsNothing);
    });
  });
}
