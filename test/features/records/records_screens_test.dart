import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/history_screen.dart';
import 'package:fakkarni/features/records/manual_entry_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep14 = DateTime(2026, 9, 14);
  RecordsRepository repo() => RecordsRepository(h.db);

  Future<int> add(RecordKind kind, String title, DateTime at, {String? doctor, String? notes}) => repo().add(
        patientId: h.services.patientId,
        kind: kind,
        title: title,
        happenedAt: at,
        doctor: doctor,
        notes: notes,
      );

  Future<void> seed() async {
    await add(RecordKind.imaging, 'أشعة صدر', DateTime(2026, 9, 10), doctor: 'د. هشام مام', notes: 'طبيعية');
    await add(RecordKind.lab, 'HbA1c', DateTime(2026, 8, 28), doctor: 'د. طارق سعيد');
    await add(RecordKind.visit, 'باطنة', DateTime(2026, 3, 2), doctor: 'د. هشام مام');
  }

  group('الإدخال اليدوي (المخطط ٢٨)', () {
    screenTest('أربع استمارات، كل واحدة بحقولها — والتحليل بيتحفظ بالحرف', (tester) async {
      await h.pump(tester, ManualEntryScreen(today: sep14));
      await settle(tester);

      // الأشعة: نوع + مركز + دكتور + نتيجة
      expect(find.text('نوع الأشعة'), findsOneWidget);
      expect(find.text('المركز'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-visit')));
      await settle(tester);
      expect(find.text('التخصص أو سبب الزيارة'), findsOneWidget);
      expect(find.text('العيادة أو المستشفى'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-prescription')));
      await settle(tester);
      expect(find.textContaining('ده للتسجيل بس'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-place')), findsNothing, reason: 'الروشتة مالهاش مكان');

      // «حجز» مش ورقة تتكتب — بقى «ميعاد جديد» في «السجل» وبيعمل تذكيره
      expect(find.byKey(const ValueKey('kind-booking')), findsNothing);
      expect(find.text('اكتب ورقة بإيدك'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-lab')));
      await settle(tester);
      final save = find.widgetWithText(FilledButton, 'احفظ في الملف');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'من غير اسم');

      await tester.enterText(find.byKey(const ValueKey('record-title')), 'HbA1c');
      await tester.enterText(find.byKey(const ValueKey('record-place')), 'معمل البرج');
      await tester.enterText(find.byKey(const ValueKey('record-notes')), '٧.٦٪');
      await tester.tap(find.text('امبارح'));
      await settle(tester);
      await tester.tap(save);
      await settle(tester);

      final r = (await repo().all(h.services.patientId)).single;
      expect(r.kind, RecordKind.lab);
      expect(r.title, 'HbA1c');
      expect(r.place, 'معمل البرج');
      expect(r.doctor, isNull, reason: 'ما اتكتبش');
      expect(r.notes, '٧.٦٪');
      expect(r.happenedAt, DateTime(2026, 9, 13));
      expectNoRedAndMinSize(tester);
    });
  });

  group('«السجل» — تلات أقسام', () {
    screenTest('فاضي → كل قسم بيقول تعمل إيه، ومفيش سبع زرارات', (tester) async {
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      expect(find.text('السجل'), findsOneWidget);
      for (final head in ['مواعيدك الجاية', 'أوراقك', 'للدكتور']) {
        expect(find.text(head), findsOneWidget, reason: head);
      }
      expect(find.byKey(const ValueKey('appointments-empty')), findsOneWidget);
      expect(find.textContaining('دوس «ميعاد جديد» ونفكّرك'), findsOneWidget);
      expect(find.byKey(const ValueKey('papers-empty')), findsOneWidget);
      expect(find.textContaining('صوّر روشتة أو تحليل من «ضيف»'), findsOneWidget);
      expect(find.text('ميعاد جديد'), findsOneWidget, reason: 'زرار أساسي واحد');
      for (final old in ['الحالات السابقة', 'صفحة الطبيب', 'استخراج الملف', 'تابع تحليل', 'تابع زيارة', '+ ضيف']) {
        expect(find.text(old), findsNothing, reason: old);
      }
      expectNoRedAndMinSize(tester);
    });

    screenTest('«ميعاد جديد» → «دكتور» → يوم → «احفظ الميعاد»: متابعة زيارة بتذكيرها، والصف في «مواعيدك الجاية»', (tester) async {
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('new-appointment')));
      await settle(tester);
      expect(find.text('دكتور ولا معمل؟'), findsOneWidget);
      // «دكتور» مختار من الأول، و«بكرة» هي اليوم الافتراضي
      await tester.enterText(find.byKey(const ValueKey('new-appt-name')), 'د. منى');
      await tester.tap(find.byKey(const ValueKey('new-appt-save')));
      await settle(tester);

      final follow = (await repo().all(h.services.patientId)).single;
      expect(CheckupService.kindOf(follow), FollowKind.visit);
      expect(CheckupService.stageOf(follow), VisitStage.booked);
      expect(follow.doctorVisitAt, isNotNull, reason: 'الميعاد اتكتب — فالتذكير موجود');
      expect(DateTime(follow.doctorVisitAt!.year, follow.doctorVisitAt!.month, follow.doctorVisitAt!.day), DateTime(2026, 9, 15));
      expect(find.byKey(ValueKey('upcoming-${follow.id}-1')), findsOneWidget);
      expect(find.textContaining('زيارة الدكتور — بكرة'), findsOneWidget);
      expect(find.byKey(const ValueKey('appointments-empty')), findsNothing);
      expect(h.sink.scheduled.keys.any(isAppointmentId), isTrue, reason: 'إشعار الميعاد اتجدول');
    });

    screenTest('«ميعاد جديد» → «معمل»: متابعة تحليل واقفة عند «حجز المعمل» بميعادها', (tester) async {
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('new-appointment')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('new-appt-lab')));
      await settle(tester);
      await tester.tap(find.text('بعد بكرة'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('new-appt-save')));
      await settle(tester);

      final follow = (await repo().all(h.services.patientId)).single;
      expect(CheckupService.kindOf(follow), FollowKind.lab);
      expect(CheckupService.stageOf(follow), CheckupStage.labBooking);
      expect(follow.title, 'تحليل', reason: 'من غير اسم = «تحليل»، مش اسم مخترع');
      expect(follow.labBookingAt, isNotNull);
      expect(find.textContaining('ميعاد المعمل — بعد بكرة'), findsOneWidget);
    });

    screenTest('حجز قديم بميعاد جاي بيظهر في «مواعيدك الجاية» مع «فكّرني بيه» — والقديم اللي فات ورقة عادية', (tester) async {
      final future = await add(RecordKind.booking, 'كشف عيون', DateTime(2026, 9, 20), doctor: 'د. سامي');
      final past = await add(RecordKind.booking, 'كشف قديم', DateTime(2026, 9, 1));
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);

      expect(find.byKey(ValueKey('legacy-booking-$future')), findsOneWidget);
      expect(find.byKey(ValueKey('legacy-booking-$past')), findsNothing);
      expect(find.byKey(ValueKey('record-$past')), findsOneWidget, reason: 'اللي فات ورقة في «أوراقك»');
      expect(find.text('فكّرني بيه'), findsOneWidget);

      await tester.tap(find.text('فكّرني بيه'));
      await settle(tester);
      final follow = (await repo().all(h.services.patientId)).firstWhere((r) => r.checkupStage != null);
      expect(CheckupService.kindOf(follow), FollowKind.visit);
      expect(follow.followSourceId, future);
      expect(follow.doctor, 'د. سامي');
      expect(DateTime(follow.doctorVisitAt!.year, follow.doctorVisitAt!.month, follow.doctorVisitAt!.day), DateTime(2026, 9, 20));
      // الحجز القديم اتغطّى بالمتابعة — مش بيتعرض مرتين
      expect(find.byKey(ValueKey('legacy-booking-$future')), findsNothing);
      expect(find.byKey(ValueKey('upcoming-${follow.id}-1')), findsOneWidget);
    });

    screenTest('«أوراقك»: كل الأنواع مع بعض، الأحدث فوق، وعنوان لكل يوم — والزيارة وروشتتها جنب بعض', (tester) async {
      await seed();
      await add(RecordKind.prescription, 'روشتة الباطنة', DateTime(2026, 3, 2), doctor: 'د. هشام مام');
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);

      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('أشعة صدر'), lessThan(y('HbA1c')));
      expect(y('HbA1c'), lessThan(y('باطنة')));
      // عنوان اليوم مرة واحدة للزيارة وروشتتها
      expect(find.byKey(const ValueKey('day-head-2026-3-2')), findsOneWidget);
      expect(find.text('٢ مارس ٢٠٢٦'), findsOneWidget);
      expect(find.text('روشتة الباطنة'), findsOneWidget);
    });

    screenTest('البحث بالاسم والدكتور والتاريخ (عربي أو إنجليزي)', (tester) async {
      await seed();
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      final search = find.byKey(const ValueKey('records-search'));

      Future<void> expectShown(String q, List<String> titles) async {
        await tester.enterText(search, q);
        await settle(tester);
        for (final t in ['أشعة صدر', 'HbA1c', 'باطنة']) {
          expect(find.text(t), titles.contains(t) ? findsOneWidget : findsNothing, reason: '$q → $t');
        }
      }

      await expectShown('هشام', ['أشعة صدر', 'باطنة']);
      await expectShown('hba1c', ['HbA1c']);
      await expectShown('أغسطس', ['HbA1c']);
      await expectShown('٢٨', ['HbA1c']);
      await expectShown('3/2026', ['باطنة']);
      await tester.enterText(search, 'مفيش حاجة كده');
      await settle(tester);
      expect(find.text('مفيش حاجة بالكلام ده'), findsOneWidget);
    });

    screenTest('الملف بيفرّج وبيتابع — مفيش زرار إضافة عليه، والأنواع ورا «فلتر»', (tester) async {
      await seed();
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);

      // «صوّر تقرير تحليل» كانت هنا وهي أصلاً في شيت «ضيف»
      expect(find.text('صوّر تقرير تحليل'), findsNothing);
      expect(find.text('قيس السكر'), findsNothing);
      expect(find.text('اكتب ورقة بإيدك'), findsNothing);
      // «فلتر»: مدخل لكل نوع بعدده
      await tester.tap(find.byKey(const ValueKey('records-filter')));
      await settle(tester);
      expect(find.byKey(const ValueKey('kind-entry-imaging')), findsOneWidget);
      expect(find.byKey(const ValueKey('kind-entry-lab')), findsOneWidget);
      expect(find.byKey(const ValueKey('kind-entry-visit')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-history')), findsOneWidget);
      // والمدخل بيفتح قايمته
      await tester.tap(find.byKey(const ValueKey('kind-entry-imaging')));
      await settle(tester);
      expect(find.text('أشعة صدر'), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('«⋯ خيارات» → «امسحه» بتأكيد → الصف بيختفي، مش بيفضل شهر', (tester) async {
      final id = await add(RecordKind.lab, 'HbA1c', DateTime(2026, 8, 28));
      await add(RecordKind.visit, 'باطنة', DateTime(2026, 8, 20));
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      // الصفوف على سكة «أوراقك» نفسها — نفس الكارت بكل اللي بيعمله
      expect(find.text('⋯ خيارات'), findsNWidgets(2), reason: 'مش أيقونة لوحدها — صف لكل ورقة');

      // «لأ، سيبه» ما بيمسحش
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);
      expect(find.text('تمسح «HbA1c»؟'), findsOneWidget);
      expect(find.text('هيتشال من الملف خالص، ومفيش رجوع.'), findsOneWidget);
      // الجملة القديمة كانت بتوعد بشهر رجوع — ومحدش كان بيقدر يرجّع بيها حاجة
      expect(find.textContaining('٣٠ يوم'), findsNothing);
      await tester.tap(find.text('لأ، سيبه'));
      await settle(tester);
      expect((await repo().all(h.services.patientId)), hasLength(2));

      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete-confirm')));
      await settle(tester);

      expect(find.text('HbA1c'), findsNothing, reason: 'اتمسح يعني راح');
      expect(find.text('رجّعه'), findsNothing);
      expect(find.byType(Opacity), findsNothing, reason: 'مفيش صف باهت مشطوب');
      for (final msa in ['حُذف', 'يُنقل', 'المحذوفات']) {
        expect(find.textContaining(msa), findsNothing, reason: msa);
      }

      expectNoRedAndMinSize(tester);
    });
  });

  group('الحالات السابقة (المخطط ٢٩)', () {
    screenTest('بالترتيب، الأحدث فوق، والفلتر بالنوع وبالفترة', (tester) async {
      await seed();
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);

      final y1 = tester.getTopLeft(find.text('أشعة صدر')).dy;
      final y2 = tester.getTopLeft(find.text('HbA1c')).dy;
      final y3 = tester.getTopLeft(find.text('باطنة')).dy;
      expect(y1 < y2 && y2 < y3, isTrue);
      expect(find.text('١٠ سبتمبر ٢٠٢٦'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-lab')));
      await settle(tester);
      expect(find.text('HbA1c'), findsOneWidget);
      expect(find.text('أشعة صدر'), findsNothing);

      await tester.tap(find.text('الكل').first);
      await tester.tap(find.byKey(const ValueKey('period-threeMonths')));
      await settle(tester);
      expect(find.text('أشعة صدر'), findsOneWidget);
      expect(find.text('باطنة'), findsNothing, reason: 'مارس برّه آخر ٣ شهور');

      await tester.tap(find.byKey(const ValueKey('filter-visit')));
      await settle(tester);
      expect(find.text('مفيش حاجة في الفلتر ده'), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('الممسوح مش على الخط خالص — ولا مشطوب ولا «رجّعه»', (tester) async {
      final id = await add(RecordKind.imaging, 'أشعة صدر', DateTime(2026, 9, 10));
      await add(RecordKind.lab, 'صورة دم', DateTime(2026, 9, 11));
      await repo().delete(id, now: sep14);
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);
      expect(find.text('صورة دم'), findsOneWidget, reason: 'الباقي مكانه');
      expect(find.text('أشعة صدر'), findsNothing);
      expect(find.text('رجّعه'), findsNothing);
      expect(find.textContaining('٣٠ يوم'), findsNothing);
    });

    screenTest('فاضي → بيقول إزاي تضيف', (tester) async {
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);
      expect(find.text('لسه مفيش حاجة هنا'), findsOneWidget);
      expect(find.text('+ ضيف'), findsOneWidget);
    });
  });

  group('الوصول', () {
    screenTest('تبويب «الملف» في الدوك، و«ضيف» → «سجّل زيارة أو تحليل أو أشعة»', (tester) async {
      await h.pump(tester, AppShell(routine: normalDay, now: DateTime(2026, 8, 31, 8)));
      await settle(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.tap(find.text('سجّل زيارة أو تحليل أو أشعة'));
      await settle(tester);
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      // الباب الوحيد للملف الصحي: تبويب الدوك. صف الإعدادات اتشال —
      // بابين لأوضة واحدة بيخلّي المستخدم يشك إنهم حاجتين.
      await tester.tap(find.text('السجل').last);
      await settle(tester);
      expect(find.byType(HealthFileScreen), findsOneWidget);
    });
  });
}
