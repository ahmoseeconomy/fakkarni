import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import 'reminder_plan_test.dart' show FakeReminderSink, normalDay;
import '../support/seeded_clock.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('نطاق الصيام', () {
    test('ما بيتقاطعش مع أي نطاق جرعات: الجرعة، التأجيل، درجتين السلّم', () {
      final bands = <String, (int, int)>{
        'dose': (doseIdBase, doseIdLimit),
        'snooze': (snoozeIdBase, snoozeIdLimit),
        'rung1': (escalationFirstIdBase, escalationFirstIdBase + maxPatients * patientIdSpan),
        'rung2': (escalationSecondIdBase, escalationSecondIdBase + maxPatients * patientIdSpan),
      };
      for (final MapEntry(key: name, value: (lo, hi)) in bands.entries) {
        final overlaps = fastingIdBase < hi && lo < fastingIdLimit;
        expect(overlaps, isFalse, reason: 'الصيام متقاطع مع $name');
      }
      expect(fastingIdLimit, lessThan(1 << 31), reason: 'سقف أندرويد');
    });

    test('كل رقم صيام برّه كل الحارسين — والعكس', () {
      for (final recordId in [0, 1, 999, 5898239]) {
        final id = fastingIdFor(recordId);
        expect(isFastingId(id), isTrue);
        expect(isDoseId(id), isFalse);
        expect(isEscalationId(id), isFalse);
        expect(isSnoozeId(id), isFalse);
        expect(isRescheduledId(id), isFalse, reason: 'إعادة الجدولة ما تلغيهوش');
      }
      final at = DateTime(2026, 9, 20, 8);
      for (final id in [
        notificationIdFor(at, patientIndex: 127),
        snoozeIdFor(at),
        escalationIdFor(at, EscalationRung.first),
        escalationIdFor(at, EscalationRung.second, patientIndex: 127),
      ]) {
        expect(isFastingId(id), isFalse);
      }
    });

    test('id برّه النطاق بيرمي — مفيش لفّ', () {
      expect(() => fastingIdFor(maxPatients * patientIdSpan), throwsRangeError);
      expect(() => fastingIdFor(-1), throwsRangeError);
    });

    test('المساحة تحت سقف iOS: ٤٤ + ١٤ + ٢ تأجيل + ٢ صيام + ٢ متابعة = ٦٤', () {
      expect(
        maxPendingReminders +
            maxPendingEscalations +
            snoozePendingSlack +
            fastingPendingSlack +
            checkupPendingSlack,
        iosPendingLimit,
      );
      expect(maxPendingEscalations, 14, reason: 'سلّم التصعيد ما اتقصّش — الجرعات هي اللي دفعت');
      expect(maxPendingReminders, 44);
    });

    test('نطاق المتابعة مستقل عن كل النطاقات التانية', () {
      // تذكير متابعة بيدوس على تذكير دوا = جرعة ما بترنّش، في صمت
      expect(isCheckupId(checkupIdFor(0, 0)), isTrue);
      expect(isDoseId(checkupIdFor(0, 0)), isFalse);
      expect(isFastingId(checkupIdFor(0, 0)), isFalse);
      expect(isRescheduledId(checkupIdFor(5, 1)), isFalse,
          reason: 'إعادة جدولة الجرعات ما بتلمسش مواعيد المتابعة');

      // رقم لكل (صف، مرحلة) — تلاتة متجاورين، وما بيتصادموش بين الصفوف
      final ids = {
        for (var record = 0; record < 40; record++)
          for (var slot = 0; slot < checkupDatedStages; slot++) checkupIdFor(record, slot),
      };
      expect(ids.length, 40 * checkupDatedStages);

      expect(() => checkupIdFor(0, checkupDatedStages), throwsRangeError);
      expect(() => checkupIdFor(-1, 0), throwsRangeError);
      expect(() => checkupIdFor(maxPatients * patientIdSpan, 0), throwsRangeError);
    });
  });

  group('متابعة التحليل وتذكير الصيام', () {
    late AppDatabase db;
    late FakeReminderSink sink;
    late CheckupService checkups;
    late ReminderScheduler scheduler;
    late int patientId;
    final now = DateTime(2026, 9, 15, 10);
    final draw = DateTime(2026, 9, 17, 8);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final routines = RoutineRepository(db);
      final meds = MedicationRepository(db, clock: seededLongAgo);
      patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, normalDay);
      sink = FakeReminderSink();
      checkups = CheckupService(db, sink);
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: sink,
      );
      await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: const AnchorTiming(DayAnchor.breakfast, -30),
        startDate: DateTime(2026, 9, 15),
      );
    });
    tearDown(() => db.close());

    Future<RecordRow> row(int id) => (db.select(db.records)..where((t) => t.id.equals(id))).getSingle();

    /// **مواعيد المراحل**: كل مرحلة بتسأل سؤالها، وما بنفترضش مدة لحاجة.
    ///
    /// كل اختبار هنا بيعدّ الإشعارات في نطاق المتابعة لوحده — تذكير
    /// الصيام له نطاقه، والجرعات ليها نطاقها، والخلط بينهم هو بالظبط
    /// الباج اللي النطاقات موجودة عشانه.
    group('مواعيد المراحل', () {
      Set<int> checkupIds() => sink.scheduled.keys.where(isCheckupId).toSet();

      /// بيوصل المتابعة للمرحلة [stage] بالتقدّم خطوة خطوة.
      Future<int> at(CheckupStage stage) async {
        final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
        while ((await row(id)).checkupStage! < stage.number) {
          await checkups.advance(id, now: now);
        }
        return id;
      }

      test('كل مرحلة بتسأل سؤالها — والتلاتة بس', () {
        expect(
          [for (final s in CheckupStage.dated) s.dateQuestion],
          ['حجزت إمتى؟', 'النتيجة هتجهز إمتى؟', 'معاد الدكتور؟'],
        );
        expect(CheckupStage.dated.length, checkupDatedStages);
      });

      for (final (stage, day) in [
        (CheckupStage.labBooking, DateTime(2026, 9, 18)),
        (CheckupStage.waitingResult, DateTime(2026, 9, 20)),
        (CheckupStage.resultArrived, DateTime(2026, 9, 24)),
      ]) {
        test('«${stage.dateQuestion}» بتجدول تذكير واحد في اليوم اللي اتقال', () async {
          final id = await at(stage);
          expect(checkupIds(), isEmpty, reason: 'مفيش تذكير قبل ما حد يقول ميعاد');

          final result = await checkups.setStageDate(id, stage, day: day, now: now);

          expect(result, StageDateResult.scheduled);
          expect(checkupIds(), {checkupIdFor(id, CheckupStage.dated.indexOf(stage))},
              reason: 'تذكير واحد بالظبط');
          final at_ = sink.scheduled[checkupIdFor(id, CheckupStage.dated.indexOf(stage))]!.at;
          expect(DateTime(at_.year, at_.month, at_.day), day, reason: 'في نفس اليوم');
          // الساعة من صحيان المريض، مش رقم مخترع
          expect(at_.hour * 60 + at_.minute, normalDay.wake.minutes);
          expect(CheckupService.stageDateOf(await row(id), stage), at_);
        });
      }

      test('التخطّي مفيش وراه تذكير — والمرحلة بتعدّي عادي', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.advance(id, now: now);
        expect(checkupIds(), isEmpty);
        expect((await row(id)).labBookingAt, isNull, reason: 'مفيش ميعاد اتخترع');
        expect((await row(id)).checkupStage, CheckupStage.preparation.number);
      });

      test('تغيير الميعاد بيعيد الجدولة على نفس الرقم — مش بيزوّد تذكير', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 22), now: now);

        expect(checkupIds(), hasLength(1), reason: 'الرقم مشتق، فالتاني بيستبدل الأول');
        final at_ = sink.scheduled[checkupIdFor(id, 0)]!.at;
        expect(DateTime(at_.year, at_.month, at_.day), DateTime(2026, 9, 22));
        expect((await row(id)).labBookingAt, at_);
      });

      test('يوم عدّى بيترفض — ومفيش تذكير ولا ميعاد بيتكتب', () async {
        final id = await at(CheckupStage.labBooking);
        final result = await checkups.setStageDate(
            id, CheckupStage.labBooking, day: DateTime(2026, 9, 14), now: now);
        expect(result, StageDateResult.inPast);
        expect(checkupIds(), isEmpty);
        expect((await row(id)).labBookingAt, isNull);
      });

      test('«شيل الميعاد» بيلغي ويصفّر', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now);
        await checkups.clearStageDate(id, CheckupStage.labBooking);

        expect(checkupIds(), isEmpty);
        expect(sink.cancelled, contains(checkupIdFor(id, 0)));
        expect((await row(id)).labBookingAt, isNull);
      });

      test('الرجوع مرحلة بيلغي ميعادها — الخطة اتغيّرت', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now);

        await checkups.back(id, now: now);

        expect(sink.cancelled, contains(checkupIdFor(id, 0)));
        expect(checkupIds(), isEmpty);
        expect((await row(id)).labBookingAt, isNull);
        expect((await row(id)).checkupStage, CheckupStage.doctorOrder.number);
      });

      test('ميعاد المعمل بيعيش لحد ما العينة تتسحب — «التحضير» ما بتلغيهوش', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now);

        // الواحد بيعدّي على «التحضير» **قبل** ما يروح المعمل
        await checkups.advance(id, now: now);
        expect(checkupIds(), hasLength(1), reason: 'الميعاد لسه جاي');

        await checkups.advance(id, now: now); // سحب العينة
        expect(checkupIds(), hasLength(1));

        await checkups.advance(id, now: now); // انتظار النتيجة — خلاص راح
        expect(checkupIds(), isEmpty, reason: 'مش هنزنّ على ميعاد عدّى');
        expect((await row(id)).labBookingAt, isNull);
      });

      test('وقف المتابعة بيلغي كل مواعيدها وتذكير صيامها', () async {
        final id = await at(CheckupStage.labBooking);
        await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now);
        await checkups.setFastingReminder(id, draw: draw, hours: 8, now: now);

        await checkups.delete(id, now: now);

        expect(sink.cancelled, contains(checkupIdFor(id, 0)));
        expect(sink.cancelled, contains(fastingIdFor(id)));
        expect(checkupIds(), isEmpty);
        expect(sink.scheduled.keys.where(isFastingId), isEmpty);
      });

      test('تالت ميعاد في متابعة تالتة بيترفض — سقف iOS', () async {
        final a = await at(CheckupStage.labBooking);
        final b = await at(CheckupStage.labBooking);
        final c = await at(CheckupStage.labBooking);
        for (final id in [a, b]) {
          expect(
            await checkups.setStageDate(id, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now),
            StageDateResult.scheduled,
          );
        }
        expect(
          await checkups.setStageDate(c, CheckupStage.labBooking, day: DateTime(2026, 9, 18), now: now),
          StageDateResult.tooMany,
        );
        expect(checkupIds(), hasLength(checkupPendingSlack));
      });

      test('«واقفة» بتبقى صح في اليوم السابع بالظبط، مش السادس', () async {
        final since = DateTime(2026, 9, 15, 10);
        bool stalledOn(DateTime when, {DateTime? date}) => checkupIsStalled(
              stage: CheckupStage.labBooking,
              stageSince: since,
              stageDate: date,
              now: when,
            );

        expect(stalledOn(DateTime(2026, 9, 21, 10)), isFalse, reason: 'اليوم السادس');
        expect(stalledOn(DateTime(2026, 9, 22, 10)), isTrue, reason: 'اليوم السابع');
        // وميعاد متحطّ = مفيش وقوف، مهما طال الوقت
        expect(stalledOn(DateTime(2026, 10, 30), date: DateTime(2026, 9, 18)), isFalse);
        // ومرحلة ما بتسألش عن تاريخ عمرها ما «تقف»
        expect(
          checkupIsStalled(
            stage: CheckupStage.preparation,
            stageSince: since,
            stageDate: null,
            now: DateTime(2026, 10, 30),
          ),
          isFalse,
        );
      });

      test('التقدّم والرجوع بيحرّكوا ساعة المرحلة — منها بس بنعرف إنها واقفة', () async {
        final id = await checkups.start(patientId: patientId, title: 'صورة دم', today: now);
        expect((await row(id)).checkupStageSince, now);

        final later = DateTime(2026, 9, 25, 9);
        await checkups.advance(id, now: later);
        expect((await row(id)).checkupStageSince, later);

        final evenLater = DateTime(2026, 10, 1, 9);
        await checkups.back(id, now: evenLater);
        expect((await row(id)).checkupStageSince, evenLater);
      });
    });

    test('البداية مرحلة ١، ومفيش أي إشعار قبل الضغطة (القاعدة ٤)', () async {
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      expect((await row(id)).checkupStage, CheckupStage.doctorOrder.number);
      await checkups.advance(id);
      await checkups.advance(id);
      expect(sink.scheduled.keys.where(isFastingId), isEmpty);
    });

    test('الضغطة بتجدول عند ميعاد السحب ناقص الساعات اللي اتكتبت، في نطاق الصيام، ومن غير أزرار جرعة', () async {
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      final result = await checkups.setFastingReminder(id, draw: draw, hours: 8, now: now);
      expect(result, FastingResult.scheduled);
      final n = sink.scheduled[fastingIdFor(id)]!;
      expect(n.at, DateTime(2026, 9, 17, 0));
      expect(n.kind, NotificationKind.fasting);
      expect(decodePayload(n.payload), isNull, reason: 'الدوسة ما بتفتحش شاشة جرعة');
      expect(n.body, contains('٨ ساعة'));
      expect((await row(id)).fastingReminderAt, DateTime(2026, 9, 17, 0));
    });

    test('إعادة جدولة الجرعات وتأكيد جرعة ما بيلمسوش تذكير الصيام — وهو ما بيلمسهمش', () async {
      await scheduler.rescheduleAll(now: now);
      final dosesBefore = sink.doses.keys.toSet();
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      await checkups.setFastingReminder(id, draw: draw, hours: 8, now: now);

      await scheduler.rescheduleAll(now: now);
      await scheduler.cancelReminderAt(DateTime(2026, 9, 16, 7));
      await scheduler.rescheduleAll(now: now);

      expect(sink.scheduled.containsKey(fastingIdFor(id)), isTrue);
      expect(sink.cancelled.where(isFastingId), isEmpty);
      expect(sink.doses.keys.toSet().difference(dosesBefore), isEmpty);

      final dosesBeforeCancel = sink.doses.keys.toSet();
      final escalationsBeforeCancel = sink.escalations.keys.toSet();
      await checkups.cancelFasting(id);
      expect(sink.cancelled.last, fastingIdFor(id));
      expect(sink.doses.keys.toSet(), dosesBeforeCancel, reason: 'إلغاء الصيام ما لغاش جرعة');
      expect(sink.escalations.keys.toSet(), escalationsBeforeCancel);
    });

    test('الرجوع لمرحلة قبلها بيلغي التذكير', () async {
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      await checkups.advance(id);
      await checkups.advance(id);
      await checkups.setFastingReminder(id, draw: draw, hours: 10, now: now);
      await checkups.back(id);
      expect(sink.scheduled.containsKey(fastingIdFor(id)), isFalse);
      expect((await row(id)).fastingReminderAt, isNull);
    });

    test('التقدّم بعد «سحب العينة» بيلغيه، وقبلها لأ', () async {
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      await checkups.setFastingReminder(id, draw: draw, hours: 10, now: now);
      for (var i = 0; i < 3; i++) {
        await checkups.advance(id); // لحد «سحب العينة»
      }
      expect(CheckupStage.fromNumber((await row(id)).checkupStage), CheckupStage.sampleDraw);
      expect(sink.scheduled.containsKey(fastingIdFor(id)), isTrue);
      await checkups.advance(id); // «انتظار النتيجة»
      expect(sink.scheduled.containsKey(fastingIdFor(id)), isFalse);
    });

    test('إلغاء الدورة بيمسحها ويلغي تذكيرها — ومفيش رجوع يرجّعه', () async {
      final id = await checkups.start(patientId: patientId, title: 'صورة دم كاملة', today: now);
      await checkups.setFastingReminder(id, draw: draw, hours: 8, now: now);
      await checkups.delete(id, now: now);
      expect(sink.scheduled.containsKey(fastingIdFor(id)), isFalse);
      expect(sink.scheduled.keys.where(isFastingId), isEmpty);
      expect(await RecordsRepository(db).all(patientId), isEmpty);
    });

    test('وقت فات، ساعات غلط، أو تالت تذكير → مفيش جدولة', () async {
      final a = await checkups.start(patientId: patientId, title: 'أ', today: now);
      final b = await checkups.start(patientId: patientId, title: 'ب', today: now);
      final c = await checkups.start(patientId: patientId, title: 'ج', today: now);
      expect(await checkups.setFastingReminder(a, draw: DateTime(2026, 9, 15, 12), hours: 8, now: now), FastingResult.inPast);
      expect(await checkups.setFastingReminder(a, draw: draw, hours: 0, now: now), FastingResult.badHours);
      expect(await checkups.setFastingReminder(a, draw: draw, hours: 8, now: now), FastingResult.scheduled);
      expect(await checkups.setFastingReminder(b, draw: draw, hours: 8, now: now), FastingResult.scheduled);
      expect(await checkups.setFastingReminder(c, draw: draw, hours: 8, now: now), FastingResult.tooMany);
      expect(sink.scheduled.keys.where(isFastingId).length, fastingPendingSlack);
      // تعديل تذكير نفس الدورة مش «تالت»
      expect(await checkups.setFastingReminder(a, draw: draw, hours: 12, now: now), FastingResult.scheduled);
    });
  });
}
