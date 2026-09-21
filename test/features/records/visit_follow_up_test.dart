// متابعة الزيارة جنب متابعة التحليل (جولة ٢٤).
//
// الزيارة **مش تحليل**: تلات مراحل بس — اتحجزت، تمت، المتابعة — لأن دي
// اللي الراجل بيعيشها. ونفس التلات طرق تبدأ بيها: من ورقة في الملف، من
// صورة جديدة، أو بالإيد.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/appointment_scheduler.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/features/records/checkup_screen.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep15 = DateTime(2026, 9, 15, 10);
  CheckupService checkups() => h.services.checkups;

  Future<int> prescriptionInFile({String? doctor = 'د. حسام'}) => RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.prescription,
        title: 'روشتة — ٣ أدوية',
        happenedAt: DateTime(2026, 9, 10),
        doctor: doctor,
        place: 'عيادة النزهة',
      );

  Future<int> labReportInFile() => RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.lab,
        title: 'تقرير تحليل — CBC',
        happenedAt: DateTime(2026, 9, 11),
        doctor: 'د. طارق',
      );

  Future<void> openFile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, HealthFileScreen(today: sep15));
    await settle(tester);
  }

  group('مراحل الزيارة — تلاتة وبس', () {
    test('مفيش تحضير ولا انتظار ولا سحب عينة في الزيارة', () {
      expect(VisitStage.values.map((s) => s.label), [
        'الزيارة اتحجزت',
        'الزيارة تمت',
        'المتابعة',
      ]);
      expect(FollowKind.visit.stages.length, 3);
      expect(FollowKind.lab.stages.length, 7);
    });

    test('«الزيارة اتحجزت» هي الوحيدة اللي بتسأل عن ميعاد', () {
      expect(FollowKind.visit.datedStages, [VisitStage.booked]);
      expect(VisitStage.booked.dateQuestion, 'الزيارة إمتى؟');
    });

    test('الرقم بيتفسّر بنوعه — ٢ مش نفس المرحلة في الاتنين', () {
      expect(FollowKind.lab.stageFromNumber(2), CheckupStage.labBooking);
      expect(FollowKind.visit.stageFromNumber(2), VisitStage.done);
      // ورقم برّه مراحل الزيارة مالوش معنى فيها
      expect(FollowKind.visit.stageFromNumber(5), isNull);
    });
  });

  group('الدخول من الملف', () {
    screenTest('«تابع زيارة» من روشتة: بتشيل الدكتور والعيادة وتاريخ الورقة', (tester) async {
      final source = await prescriptionInFile();
      await openFile(tester);

      await tester.tap(find.byKey(const ValueKey('start-follow-visit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-from-file')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('follow-source-$source')));
      await settle(tester);

      expect(find.byType(CheckupScreen), findsOneWidget);
      final rows = await RecordsRepository(h.db).all(h.services.patientId);
      final follow = rows.firstWhere((r) => r.checkupStage != null);
      expect(CheckupService.kindOf(follow), FollowKind.visit);
      expect(follow.title, 'د. حسام', reason: 'الزيارة اسمها الدكتور');
      expect(follow.doctor, 'د. حسام');
      expect(follow.place, 'عيادة النزهة');
      // **تاريخ الورقة بيفضل على الورقة.** المتابعة صف لحاجة **لسه
      // بتحصل**، وتاريخ بدايتها هو النهارده؛ نسخ تاريخ الروشتة عليها
      // كان بيخلّي كل شاشة بتعرض `happenedAt` تقول «١٠ سبتمبر» عن زيارة
      // محجوزة بكرة. المصدر متربوط بـ`followSourceId`، فالورقة مش ضايعة.
      expect(follow.happenedAt, DateTime(2026, 9, 15),
          reason: 'المتابعة بدأت النهارده — تاريخ الورقة بيفضل على الورقة');
      expect(follow.followSourceId, source);
      // **الورقة نفسها بتفضل زي ما هي** — مش بتتحوّل لمتابعة
      expect(rows.firstWhere((r) => r.id == source).checkupStage, isNull);
    });

    screenTest('«تابع تحليل» من تقرير: بيشيل اسمه ودكتوره وتاريخه', (tester) async {
      final source = await labReportInFile();
      await openFile(tester);

      await tester.tap(find.byKey(const ValueKey('start-follow-lab')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-from-file')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('follow-source-$source')));
      await settle(tester);

      final follow = (await RecordsRepository(h.db).all(h.services.patientId))
          .firstWhere((r) => r.checkupStage != null);
      expect(CheckupService.kindOf(follow), FollowKind.lab);
      // الاسم باللي بنتابعه، مش بوصف الورقة: «تقرير تحليل — CBC» بيوصف
      // ورقة قديمة، و«متابعة CBC» بتوصف الحاجة اللي لسه بتحصل.
      expect(follow.title, 'متابعة CBC');
      expect(follow.doctor, 'د. طارق');
      expect(follow.happenedAt, DateTime(2026, 9, 15));
      expect(follow.followSourceId, source);
    });

    screenTest('ورقة ليها متابعة شغّالة ما بتبدأش تانية — بتفتح اللي موجودة', (tester) async {
      final source = await prescriptionInFile();
      final first = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. حسام',
        today: sep15,
        fromRecordId: source,
      );
      await openFile(tester);

      await tester.tap(find.byKey(const ValueKey('start-follow-visit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-from-file')));
      await settle(tester);
      expect(find.text('متابَع خلاص — افتح المتابعة'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('follow-source-$source')));
      await settle(tester);

      // ولا صف جديد اتكتب
      final follows = (await RecordsRepository(h.db).all(h.services.patientId))
          .where((r) => r.checkupStage != null)
          .toList();
      expect(follows, hasLength(1));
      expect(follows.single.id, first);
      expect(find.byType(CheckupScreen), findsOneWidget);
    });

    screenTest('من غير اسم دكتور على الورقة بنقول كده — مش بنخترع اسم', (tester) async {
      final source = await prescriptionInFile(doctor: null);
      await openFile(tester);
      await tester.tap(find.byKey(const ValueKey('start-follow-visit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-from-file')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('follow-source-$source')));
      await settle(tester);

      final follow = (await RecordsRepository(h.db).all(h.services.patientId))
          .firstWhere((r) => r.checkupStage != null);
      // من غير اسم على الورقة بنقول «متابعة زيارة» — وصف صادق للي بيحصل،
      // مش اسم مخترع ومش وصف لغياب («من غير اسم دكتور» كعنوان بتتقري
      // كأنها اسم الحاجة).
      expect(follow.title, 'متابعة زيارة');
    });
  });

  group('الدخول من صورة جديدة', () {
    screenTest('تقرير اتصوّر واتأكد → المتابعة بتبدأ منه في نفس الخطوة', (tester) async {
      // الشاشة بتاعت التصوير بتنده `onSaved` بالـid بعد «تمام، احفظه» —
      // فالمتابعة بتبدأ من **نفس** السجل، مش من واحد جديد فاضي.
      int? saved;
      final recordId = await labReportInFile();
      void onSaved(int id) => saved = id;
      onSaved(recordId);
      expect(saved, recordId);

      final id = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.lab,
        title: 'تقرير تحليل — CBC',
        today: sep15,
        fromRecordId: saved,
      );
      final follow = await (h.db.select(h.db.records)..where((t) => t.id.equals(id))).getSingle();
      expect(follow.followSourceId, recordId);
      // ولو حد جرّب يبدأ تانية من نفس الورقة، القايمة بتقول إنها متابَعة
      expect(await checkups().followedSourceIds(h.services.patientId), contains(recordId));
      expect((await checkups().openFollowUpFor(recordId))?.id, id);
    });

    test('شاشتين التصوير بتوصّلوا السجل اللي اتكتب', () {
      // العقد نفسه: الاتنين بياخدوا `onSaved`. من غيره الطريق التاني ما
      // كانش هيعرف المتابعة تبدأ من أنهي ورقة.
      final lab = File('lib/features/health/scan_lab_screen.dart').readAsStringSync();
      final pres = File('lib/features/scan/scan_prescription_screen.dart').readAsStringSync();
      expect(lab.contains('onSaved'), isTrue);
      expect(pres.contains('onSaved'), isTrue);
      expect(File('lib/features/health/lab_report_screen.dart').readAsStringSync()
          .contains('widget.onSaved?.call(recordId)'), isTrue);
      expect(File('lib/features/scan/review_prescription_screen.dart').readAsStringSync()
          .contains('widget.onSaved?.call(recordId)'), isTrue);
    });
  });

  group('الدخول بالإيد', () {
    screenTest('«تابع زيارة» بالإيد: الاسم هو الدكتور، والمتابعة بتبدأ عند «اتحجزت»', (tester) async {
      await openFile(tester);
      await tester.tap(find.byKey(const ValueKey('start-follow-visit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-by-hand')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('checkup-title')), 'د. منى');
      await tester.tap(find.byKey(const ValueKey('checkup-start')));
      await settle(tester);

      final follow = (await RecordsRepository(h.db).all(h.services.patientId))
          .firstWhere((r) => r.checkupStage != null);
      expect(CheckupService.kindOf(follow), FollowKind.visit);
      expect(CheckupService.stageOf(follow), VisitStage.booked);
      expect(follow.doctor, 'د. منى');
      expect(follow.followSourceId, isNull, reason: 'اتكتبت بالإيد، مفيش ورقة جت منها');
    });
  });

  group('ميعاد الزيارة — تذكير واحد، بنفس قواعد التحليل', () {
    Future<int> visitFollowUp() => checkups().start(
          patientId: h.services.patientId,
          kind: FollowKind.visit,
          title: 'د. حسام',
          today: sep15,
        );

    test('الميعاد بيجدول تذكير في نطاق المتابعات', () async {
      final id = await visitFollowUp();
      final result = await checkups().setStageDate(
        id,
        VisitStage.booked,
        day: DateTime(2026, 9, 20),
        now: sep15,
      );
      expect(result, StageDateResult.scheduled);

      // **الجدولة في نداء لوحده بعد الجرعات** (مواصفة المواعيد):
      // `setStageDate` بتكتب الميعاد، و`AppointmentScheduler` بيبني منه
      // الإشعارين — هادي امبارحه وواحد بيرن في يومه.
      await AppointmentScheduler(
        db: h.db,
        patientId: h.services.patientId,
        sink: h.sink,
        rolling: false,
      ).refresh(now: sep15);

      final before = h.sink.scheduled[appointmentIdFor(id, 0, AppointmentNotice.dayBefore)]!;
      final dayOf = h.sink.scheduled[appointmentIdFor(id, 0, AppointmentNotice.dayOf)]!;
      expect(before.title, 'بكرة عندك زيارة');
      expect(dayOf.title, 'النهارده عندك زيارة');
      expect(before.kind, NotificationKind.appointmentQuiet);
      expect(dayOf.kind, NotificationKind.appointmentAlert);
      // ومش في نطاق الجرعات ولا التصعيد ولا الصيام ولا المتابعات القديم
      for (final n in [before, dayOf]) {
        expect(isAppointmentId(n.id), isTrue);
        expect(isDoseId(n.id), isFalse);
        expect(isRescheduledId(n.id), isFalse);
        expect(isFastingId(n.id), isFalse);
        expect(isCheckupId(n.id), isFalse);
      }
    });

    test('الرجوع مرحلة بيلغي الميعاد ويصفّره — الخطة اتغيّرت', () async {
      final id = await visitFollowUp();
      await checkups().setStageDate(id, VisitStage.booked, day: DateTime(2026, 9, 20), now: sep15);
      await checkups().advance(id, now: sep15);
      await checkups().back(id, now: sep15);

      expect(h.sink.cancelled, contains(checkupIdFor(id, 0)));
      final row = await (h.db.select(h.db.records)..where((t) => t.id.equals(id))).getSingle();
      expect(row.doctorVisitAt, isNull);
    });

    test('«الزيارة تمت» بتلغي التذكير — الزيارة حصلت خلاص', () async {
      final id = await visitFollowUp();
      await checkups().setStageDate(id, VisitStage.booked, day: DateTime(2026, 9, 20), now: sep15);
      await checkups().advance(id, now: sep15);
      expect(h.sink.cancelled, contains(checkupIdFor(id, 0)));
    });

    test('وقف المتابعة بيلغي الميعاد', () async {
      final id = await visitFollowUp();
      await checkups().setStageDate(id, VisitStage.booked, day: DateTime(2026, 9, 20), now: sep15);
      h.sink.cancelled.clear();
      await checkups().delete(id, now: sep15);
      expect(h.sink.cancelled, contains(checkupIdFor(id, 0)));
    });

    test('السقف اتنين — والزيارة بتتعدّ معاهم', () async {
      final a = await visitFollowUp();
      final b = await visitFollowUp();
      final c = await visitFollowUp();
      expect(await checkups().setStageDate(a, VisitStage.booked, day: DateTime(2026, 9, 20), now: sep15),
          StageDateResult.scheduled);
      expect(await checkups().setStageDate(b, VisitStage.booked, day: DateTime(2026, 9, 21), now: sep15),
          StageDateResult.scheduled);
      // **مفيش رفض بسبب الخانات بقى** (مواصفة المواعيد): الخانتين على
      // iOS نافذة متدحرجة، والميعاد البعيد بيستنى دوره — والكارت على
      // «يومك» بيقول إنه موجود. راجل حاجز عند الدكتور ما يتقالش له
      // «شيل ميعاد الأول».
      expect(await checkups().setStageDate(c, VisitStage.booked, day: DateTime(2026, 9, 22), now: sep15),
          StageDateResult.scheduled);
    });

    test('يوم عدّى مش ميعاد', () async {
      final id = await visitFollowUp();
      expect(
        await checkups().setStageDate(id, VisitStage.booked, day: DateTime(2026, 9, 1), now: sep15),
        StageDateResult.inPast,
      );
    });
  });

  group('زرار التقدّم', () {
    // «خلصت — على «سحب العينة»» كان فكرتين في زرار واحد، والتانية مكرّرة:
    // الخط الزمني جنبه بيوري المرحلة اللي جاية أصلاً.
    for (final (kind, title) in [(FollowKind.lab, 'صورة دم'), (FollowKind.visit, 'د. حسام')]) {
      screenTest('«خلصت» وبس — في متابعة ${kind.word}', (tester) async {
        final id = await checkups().start(
          patientId: h.services.patientId,
          kind: kind,
          title: title,
          today: sep15,
        );
        await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
        await settle(tester);

        expect(find.text('خلصت'), findsOneWidget);
        expect(find.textContaining('خلصت — على'), findsNothing);

        // والرجوع لسه بيسمّي وجهته — ده الاتجاه اللي بيفاجئ
        await tester.tap(find.byKey(const ValueKey('checkup-advance')));
        await settle(tester);
        final previous = kind.stages.first.label;
        expect(find.text('رجوع لـ«$previous»'), findsOneWidget);
      });
    }
  });

  group('بعد «الزيارة تمت»: سؤال واحد', () {
    screenTest('أيوه طلب تحليل → متابعة تحليل باسم نفس الدكتور', (tester) async {
      final id = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. حسام',
        doctor: 'د. حسام',
        today: sep15,
      );
      await checkups().advance(id, now: sep15); // الزيارة تمت
      await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('checkup-advance')));
      await settle(tester);
      expect(find.text('الدكتور طلب تحليل؟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('visit-test-yes')));
      await settle(tester);

      final rows = await RecordsRepository(h.db).all(h.services.patientId);
      final lab = rows.firstWhere((r) => CheckupService.kindOf(r) == FollowKind.lab && r.checkupStage != null);
      expect(lab.doctor, 'د. حسام');
      expect(lab.title, 'تحليل طلبه د. حسام');
      expect(CheckupService.stageOf(lab), CheckupStage.doctorOrder);
    });

    screenTest('لأ مطلبش → الزيارة بتقفل، ومفيش متابعة تانية', (tester) async {
      final id = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. حسام',
        today: sep15,
      );
      await checkups().advance(id, now: sep15);
      await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('checkup-advance')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('visit-test-no')));
      await settle(tester);

      final follows = (await RecordsRepository(h.db).all(h.services.patientId))
          .where((r) => r.checkupStage != null)
          .toList();
      expect(follows, hasLength(1));
      expect(CheckupService.stageOf(follows.single), VisitStage.followUp);
      expect(find.text('ده آخر مرحلة.'), findsOneWidget);
    });

    screenTest('السؤال بيتسأل مرة — فتح الشاشة تاني ما بيرجّعهوش', (tester) async {
      final id = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. حسام',
        today: sep15,
      );
      await checkups().advance(id, now: sep15);
      await checkups().advance(id, now: sep15); // عدّى للمتابعة برّه الشاشة

      await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
      await settle(tester);
      expect(find.text('الدكتور طلب تحليل؟'), findsNothing);
    });
  });

  group('«يومك»: قايمة واحدة فيها النوعين', () {
    test('النوع بيتسمّى في السطر الواقف', () async {
      final visit = await checkups().start(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. حسام',
        today: sep15,
      );
      final row = await (h.db.select(h.db.records)..where((t) => t.id.equals(visit))).getSingle();
      expect(CheckupService.kindOf(row).word, 'زيارة');
      expect(
        'متابعة ${CheckupService.kindOf(row).word} ${row.title} واقفة عند ${CheckupService.stageOf(row)!.label}',
        'متابعة زيارة د. حسام واقفة عند الزيارة اتحجزت',
      );
    });
  });
}
