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

    test('المساحة تحت سقف iOS: ٤٦ + ١٤ + ٢ تأجيل + ٢ صيام = ٦٤', () {
      expect(maxPendingReminders + maxPendingEscalations + snoozePendingSlack + fastingPendingSlack, iosPendingLimit);
      expect(maxPendingEscalations, 14);
    });
  });

  group('دورة الفحص وتذكير الصيام', () {
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
