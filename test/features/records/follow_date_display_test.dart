// **العطل اللي الجولة دي عن، ممسوك من الناحيتين.**
//
// من جهاز حقيقي: زيارة محجوزة **بكرة** كانت بتتعرض «١٣ سبتمبر ٢٠٢٣» —
// تاريخ الروشتة اللي المتابعة اتبدت منها. الكارت الجديد لوحده كان بيقول
// «بكرة»، لأنه الوحيد اللي بيقرا ميعاد المرحلة؛ كل شاشة تانية كانت
// بتطبع `happenedAt`.
//
// فالاختبار ده بيحط التاريخين بعيد عن بعض عن قصد — الورقة من ٢٠٢٣
// والميعاد بكرة — وبيدوّر على تاريخ الورقة **في كل شاشة**. لو رجع في أي
// واحدة، ده نفس العطل رجع.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/domain/health/follow_display.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/features/records/calendar_screen.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/records_of_kind_screen.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../scan/scan_test_support.dart';

/// تاريخ الورقة — بعيد خالص عن أي ميعاد، عشان ظهوره ما يبقاش صدفة.
const paperYear = 2023;
final paperDate = DateTime(paperYear, 9, 13);
const paperText = '١٣ سبتمبر ٢٠٢٣';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final now = DateTime(2026, 9, 15, 10);
  final tomorrow = DateTime(2026, 9, 16, 9);

  /// متابعة زيارة محجوزة بكرة، واتبدت من ورقة قديمة.
  Future<int> visitBookedTomorrow({DateTime? at}) async {
    final id = await h.services.checkups.start(
      patientId: h.services.patientId,
      kind: FollowKind.visit,
      title: 'د. حسام',
      doctor: 'د. حسام',
      today: now,
    );
    // الصف القديم بيتكتب بتاريخ ورقته — زي الصفوف اللي اتكتبت قبل الإصلاح
    await (h.db.update(h.db.records)..where((t) => t.id.equals(id)))
        .write(RecordsCompanion(happenedAt: Value(paperDate)));
    await h.services.checkups
        .setStageDate(id, VisitStage.booked, day: at ?? tomorrow, now: now);
    return id;
  }

  /// بيطبع كل نص معروض — للأسباب في رسايل الوقوع.
  List<String> shown(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) ?t.data,
      ];

  void expectNoPaperDate(WidgetTester tester, String where) {
    final lines = shown(tester);
    expect(lines.where((l) => l.contains(paperText)), isEmpty,
        reason: '«$where»: تاريخ الورقة رجع يتعرض كأنه ميعاد — $lines');
  }

  group('متابعة مفتوحة — الميعاد ميعاد المرحلة، في كل شاشة', () {
    Future<void> wide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    screenTest('قايمة «زيارات»: «بكرة»، ومفيش تاريخ الورقة', (tester) async {
      await visitBookedTomorrow();
      await wide(tester);
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);

      expect(find.textContaining('بكرة'), findsWidgets);
      expectNoPaperDate(tester, 'قايمة الزيارات');
      expectNoRedAndMinSize(tester);
    });

    screenTest('«الملف الصحي»: نفس القاعدة على الصف نفسه', (tester) async {
      await visitBookedTomorrow();
      await wide(tester);
      await h.pump(tester, HealthFileScreen(today: now));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('records-filter')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('kind-entry-visit')));
      await settle(tester);

      expect(find.textContaining('بكرة'), findsWidgets);
      expectNoPaperDate(tester, 'الملف الطبي');
    });

    screenTest('«يومك»: المتابعة اللي مالهاش ميعاد بتقول كده بالحرف', (tester) async {
      // من غير ميعاد خالص — دي اللي بتنزل في قسم «المتابعات»
      await h.services.checkups.start(
        patientId: h.services.patientId,
        kind: FollowKind.lab,
        title: 'صورة دم كاملة',
        today: now,
      );
      await wide(tester);
      await h.pump(tester, TodayScreen(routine: DayRoutine.fallback, now: now));
      await settle(tester);

      expect(find.textContaining(noFollowDateText), findsWidgets);
      expectNoPaperDate(tester, 'يومك');
    });

    screenTest('«التقويم»: المتابعة بتقع على يوم ميعادها، مش على يوم ورقتها',
        (tester) async {
      await visitBookedTomorrow();
      await wide(tester);
      await h.pump(tester, CalendarScreen(today: now));
      await settle(tester);

      // يوم ١٦ — فيه المتابعة
      await tester.tap(find.text('١٦'));
      await settle(tester);
      expect(find.textContaining(VisitStage.booked.label), findsWidgets,
          reason: 'المتابعة المفروض تقع على ١٦ — يوم الزيارة');
      expectNoPaperDate(tester, 'التقويم');
    });

    test('ومن غير ميعاد مالهاش يوم على التقويم أصلاً — مش يوم الورقة', () async {
      final id = await h.services.checkups.start(
        patientId: h.services.patientId,
        kind: FollowKind.lab,
        title: 'صورة دم كاملة',
        today: now,
      );
      await (h.db.update(h.db.records)..where((t) => t.id.equals(id)))
          .write(RecordsCompanion(happenedAt: Value(paperDate)));
      final rows = await RecordsRepository(h.db).all(h.services.patientId);
      final entries = calendarEntries(
        doses: const [],
        records: rows,
        readings: const [],
        now: now,
      );
      expect(entries.where((e) => e.at.year == paperYear), isEmpty);
    });
  });

  group('«منتظر» فوق و«تمت» تحت', () {
    screenTest('اللي ليه ميعاد فوق بالأقرب، واللي من غير ميعاد آخر «منتظر»',
        (tester) async {
      await h.services.checkups.start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'من غير ميعاد',
        today: now,
      );
      await visitBookedTomorrow(at: DateTime(2026, 9, 25, 9)); // بعيد
      await visitBookedTomorrow(); // بكرة
      // وزيارة عدّت خلاص — سجل عادي
      await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'زيارة قديمة',
        happenedAt: paperDate,
      );

      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);

      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(find.text('منتظر (٣)'), findsOneWidget);
      expect(find.text('تمت (١)'), findsOneWidget);
      expect(y(find.text('منتظر (٣)')), lessThan(y(find.text('تمت (١)'))));
      // الأقرب فوق البعيد، واللي من غير ميعاد تحتهم
      expect(y(find.textContaining('بكرة')), lessThan(y(find.textContaining('بعد ١٠ أيام'))));
      expect(y(find.textContaining('بعد ١٠ أيام')),
          lessThan(y(find.textContaining(noFollowDateText))));
      // و«تمت» تحت الكل
      expect(y(find.textContaining(noFollowDateText)), lessThan(y(find.text('زيارة قديمة'))));
    });

    screenTest('قسم فاضي ما بيظهرش — غيابه هو «مفيش حاجة هنا»', (tester) async {
      await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'زيارة قديمة',
        happenedAt: paperDate,
      );
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);
      expect(find.textContaining('منتظر'), findsNothing);
      expect(find.textContaining('تمت ('), findsNothing,
          reason: 'قسم واحد بس معروض — عنوان فوق كل الشاشة بيقول حاجة مش موجودة');
      expect(find.text('زيارة قديمة'), findsOneWidget);
    });
  });

  group('الاسم والدكتور بيتعدّلوا من «خيارات»', () {
    screenTest('اسم المتابعة بيتغيّر، والمراحل والمواعيد بتفضل مكانها', (tester) async {
      final id = await visitBookedTomorrow();
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);

      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-rename')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('rename-title')), 'متابعة الضغط');
      await tester.enterText(find.byKey(const ValueKey('rename-doctor')), 'د. سامي');
      await tester.tap(find.byKey(const ValueKey('rename-save')));
      await settle(tester);

      final row = (await RecordsRepository(h.db).all(h.services.patientId))
          .firstWhere((r) => r.id == id);
      expect(row.title, 'متابعة الضغط');
      expect(row.doctor, 'د. سامي');
      // **المسح مش البديل**: المرحلة والميعاد زي ما هما
      expect(row.checkupStage, VisitStage.booked.number);
      // الساعة بتيجي من صحيان المريض، فالمقارنة على اليوم
      expect(row.doctorVisitAt?.day, tomorrow.day);
      expect(row.doctorVisitAt?.month, tomorrow.month);
    });

    screenTest('اسم فاضي مش بيتحفظ', (tester) async {
      final id = await visitBookedTomorrow();
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-rename')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('rename-title')), '   ');
      await tester.tap(find.byKey(const ValueKey('rename-save')));
      await settle(tester);

      final row = (await RecordsRepository(h.db).all(h.services.patientId))
          .firstWhere((r) => r.id == id);
      expect(row.title, 'د. حسام', reason: 'الاسم القديم فضل');
    });

    screenTest('و«عدّل الاسم» مش معروض على سجل عادي — مفيش متابعة تتسمّى',
        (tester) async {
      final id = await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'زيارة قديمة',
        happenedAt: paperDate,
      );
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.visit, today: now));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      expect(find.byKey(const ValueKey('record-rename')), findsNothing);
      expect(find.byKey(const ValueKey('record-delete')), findsOneWidget);
    });
  });

  group('أرقام عربية في كل عنوان سجل', () {
    // توليد العنوان نفسه متختبر في `lab_title_digits_test` — هنا اللي
    // بيتعرض فعلاً على الشاشة، وده اللي الواحد بيقراه.
    screenTest('ولا رقم لاتيني في أي سطر معروض على قايمة السجلات',
        (tester) async {
      await visitBookedTomorrow();
      await h.services.checkups.start(
        patientId: h.services.patientId,
        kind: FollowKind.lab,
        title: 'تقرير تحليل — ٦ نتايج',
        today: now,
      );
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(tester, RecordsOfKindScreen(kind: RecordKind.lab, today: now));
      await settle(tester);
      for (final line in shown(tester)) {
        expect(RegExp(r'[0-9]').hasMatch(line), isFalse, reason: 'رقم لاتيني في «$line»');
      }
    });
  });
}
