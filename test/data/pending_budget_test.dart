import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/health/health_check.dart' show lowCoverageLimit;
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/every_hours.dart';

import '../features/scan/scan_test_support.dart' show RecordingSink, normalDay;
import '../support/seeded_clock.dart';

/// **ميزانية الـ٦٤ على iOS لما المواعيد تكتر** — التذكير الأساسي لكل جرعة
/// (الأقرب الأول) قبل أي إعادة، والسلّم محجوز زي ما هو. ولحد ٢٤ تذكير
/// الخطة هي هي بالحرف.
void main() {
  final from = DateTime(2026, 9, 1, 6);

  group('القسمة', () {
    test('٤٤ = ٢٤ + ٢٠ بالظبط — السلّم والاحتياطي ما اتلمسوش', () {
      expect(mainAndRepeatBudget, maxPendingReminders + maxPendingRepeats);
      expect(mainAndRepeatBudget + maxPendingEscalations + snoozePendingSlack + fastingPendingSlack + checkupPendingSlack,
          iosPendingLimit);
      expect(maxPendingEscalations, 14);
    });

    test('لحد ٢٤: زي الأول؛ فوقه إعادات أقرب ميعادين محفوظة والأساسي بياخد الباقي من ٤٤', () {
      expect(splitPendingBudget(0), (mains: 0, repeats: 20));
      expect(splitPendingBudget(24, reservedRepeats: 4), (mains: 24, repeats: 20), reason: 'مش قاصرة = زي الأول');
      expect(splitPendingBudget(30), (mains: 30, repeats: 14));
      expect(splitPendingBudget(126, reservedRepeats: 4), (mains: 40, repeats: 4));
      expect(splitPendingBudget(126, reservedRepeats: 20), (mains: 24, repeats: 20), reason: '«مستمر» لميعادين = ٢٠');
      expect(splitPendingBudget(42, reservedRepeats: 4), (mains: 40, repeats: 4));
    });

    test('التغطية بتتحسب بس لو الخطة اتقصّت', () {
      final p = [PlannedNotification(id: 1, at: from.add(const Duration(hours: 30)), title: '', body: '', payload: '', doses: const [])];
      expect(coverageOf(p, from: from, truncated: false), isNull);
      expect(coverageOf(p, from: from, truncated: true), const Duration(hours: 30));
    });
  });

  group('خطط ذهبية جديدة', () {
    late AppDatabase db;
    late RecordingSink sink;
    late ReminderScheduler scheduler;
    late MedicationRepository meds;
    late int patientId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      sink = RecordingSink();
      final routines = RoutineRepository(db);
      meds = MedicationRepository(db, clock: seededLongAgo);
      patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, normalDay);
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: sink,
      );
    });
    tearDown(() => db.close());

    Future<void> everyHours(String name, int hours, MinuteOfDay first) => meds.addMedicationWithDoses(
          patientId: patientId,
          name: name,
          timings: [for (final t in everyHoursTimes(first, hours)) FixedTiming(t)],
          startDate: DateTime(2026, 8, 31),
        );

    List<PlannedNotification> kind(NotificationKind k) =>
        [for (final n in sink.scheduled.values) if (n.kind == k) n]..sort((a, b) => a.at.compareTo(b.at));

    Future<List<PlannedNotification>> allMains() async => planWindow(
          routine: normalDay,
          schedules: await meds.activeSchedules(patientId),
          from: from,
          maxPending: 1 << 20,
        );

    /// اللي كان هيتجدول قبل الجولة دي: أقرب ٢٤ وبس.
    Future<Duration> coverageBefore() async {
      final all = await allMains();
      return all.take(maxPendingReminders).last.at.difference(from);
    }

    /// أقرب ميعادين لسه ليهم إعادات جاية (التذكير المجمّع = ميعاد واحد،
    /// والجرعة اللي رنّت من شوية جوّه مهلتها بتتحسب) — ليهم إعاداتهم، والباقي لأ.
    Future<void> expectNearestTwoKeepRepeats() async {
      final recent = planWindow(
        routine: normalDay,
        schedules: await meds.activeSchedules(patientId),
        from: from.subtract(graceWindow),
        maxPending: 1 << 20,
      );
      final nearest = [
        for (final r in recent)
          if (repeatsFor(r.at).any((st) => st.at.isAfter(from) && st.delay != EscalationRung.first.delay)) r.payload,
      ].take(protectedDoseTimes).toSet();
      final withRepeats = {for (final r in kind(NotificationKind.repeat)) r.payload};
      expect(withRepeats, nearest);
      expect(nearest, hasLength(2));
    }

    Future<void> expectMainsMaximised() async {
      final mains = kind(NotificationKind.dose);
      final all = await allMains();
      final repeats = kind(NotificationKind.repeat).length;
      expect(mains.length, mainAndRepeatBudget - repeats);
      // الأقرب الأول: كل اللي اتساب بعد آخر واحد اتجدول
      expect([for (final m in mains) m.id], [for (final m in all.take(mains.length)) m.id]);
      expect(sink.scheduled.length + snoozePendingSlack + fastingPendingSlack + checkupPendingSlack,
          lessThanOrEqualTo(iosPendingLimit));
      expect(kind(NotificationKind.escalation).length, lessThanOrEqualTo(maxPendingEscalations));
    }

    test('٣ أدوية كل ٤ ساعات (مش متوازية) — إعادات أقرب ميعادين محفوظة، والأساسي بالباقي، والسلّم محجوز', () async {
      await everyHours('A', 4, MinuteOfDay.hm(8, 0));
      await everyHours('B', 4, MinuteOfDay.hm(9, 0));
      await everyHours('C', 4, MinuteOfDay.hm(10, 0));
      await scheduler.rescheduleAll(now: from);

      await expectMainsMaximised();
      await expectNearestTwoKeepRepeats();
      expect(kind(NotificationKind.dose).length + kind(NotificationKind.repeat).length, mainAndRepeatBudget);
      expect(kind(NotificationKind.escalation), hasLength(14));
      expect(scheduler.lastPlanTruncated, isTrue);

      final before = await coverageBefore();
      final after = scheduler.lastCoverage!;
      // ١٨ ميعاد في اليوم: ٢٤ كانت بتغطّي ٣٢ ساعة؛ دلوقتي ٥٤ (من ٦ الصبح)،
      // وإعادات أقرب ميعادين محفوظة
      expect(before.inHours, 32);
      expect(after.inHours, 54);
      expect(after, greaterThan(before));
    });

    test('دوايين كل ساعتين + ٣ أدوية يومي — الحد بالظبط ولا واحد فوقه', () async {
      await everyHours('P', 2, MinuteOfDay.hm(8, 0));
      await everyHours('Q', 2, MinuteOfDay.hm(9, 0));
      for (final (i, a) in [DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner].indexed) {
        await meds.addMedication(
          patientId: patientId,
          name: 'D$i',
          timing: AnchorTiming(a, -30),
          startDate: DateTime(2026, 8, 31),
        );
      }
      await scheduler.rescheduleAll(now: from);

      await expectMainsMaximised();
      await expectNearestTwoKeepRepeats();
      expect(kind(NotificationKind.dose).length + kind(NotificationKind.repeat).length, mainAndRepeatBudget);
      final before = await coverageBefore();
      final after = scheduler.lastCoverage!;
      // ميعاد كل ساعة + ٣ يومي: ٢٣ ساعة → ٣٨ — لسه أقل من ٤٨، فـ«lowCoverage» للأدمن
      expect(before.inHours, 23);
      expect(after.inHours, 38);
      expect(after < lowCoverageLimit, isTrue);
    });
  });

  group('الخطط اللي ما قصرتش: هي هي بالحرف', () {
    late AppDatabase db;
    late RecordingSink sink;
    late ReminderScheduler scheduler;
    late MedicationRepository meds;
    late RoutineRepository routines;
    late int patientId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      sink = RecordingSink();
      routines = RoutineRepository(db);
      meds = MedicationRepository(db, clock: seededLongAgo);
      patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, normalDay);
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: sink,
      );
    });
    tearDown(() => db.close());

    /// الخوارزمية القديمة بالحرف: أقرب ٢٤، والإعادات من ٢٠.
    Future<Map<int, String>> oldPlan() async {
      final schedules = await meds.activeSchedules(patientId);
      final planned = planWindow(routine: normalDay, schedules: schedules, from: from);
      final recent = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: from.subtract(graceWindow),
        maxPending: maxPendingEscalations ~/ EscalationRung.values.length,
      );
      final ladder = planEscalations(recent, from: from);
      final repeats = planRepeats(recent, from: from);
      return {for (final n in [...planned, ...ladder, ...repeats]) n.id: '${n.at}|${n.title}|${n.body}|${n.payload}'};
    }

    Map<int, String> newPlan() =>
        {for (final n in sink.scheduled.values) n.id: '${n.at}|${n.title}|${n.body}|${n.payload}'};

    test('٨ أدوية × ٣ على المراسي (٢١ تذكير) — نفس الأرقام والأوقات والكلام', () async {
      for (var i = 0; i < 8; i++) {
        await meds.addMedicationWithDoses(
          patientId: patientId,
          name: 'M$i',
          timings: const [
            AnchorTiming(DayAnchor.breakfast, -30),
            AnchorTiming(DayAnchor.lunch, -30),
            AnchorTiming(DayAnchor.dinner, -30),
          ],
          startDate: DateTime(2026, 8, 31),
        );
      }
      await scheduler.rescheduleAll(now: from);
      expect(newPlan(), await oldPlan());
      expect(scheduler.lastPlanTruncated, isFalse);
      expect(scheduler.lastCoverage, isNull);
    });

    test('دوا واحد كل ٨ ساعات (٢١ تذكير) — نفس الخطة، ومش «قليلة»', () async {
      await meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Augmentin',
        timings: [for (final t in everyHoursTimes(MinuteOfDay.hm(8, 0), 8)) FixedTiming(t)],
        startDate: DateTime(2026, 8, 31),
      );
      await scheduler.rescheduleAll(now: from);
      expect(newPlan(), await oldPlan());
      expect(scheduler.lastPlanTruncated, isFalse);
    });
  });
}
