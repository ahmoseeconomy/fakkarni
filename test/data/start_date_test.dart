import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

import '../support/seeded_clock.dart';

/// **«هتبدأ الدوا من إمتى؟» — تاريخ بداية جاي بيجدول ولا حاجة قبله، وبعده
/// بالظبط زي دوا بدأ النهارده.** اختبار ذهبي: خطتين على قاعدتين، والفرق
/// بينهم لازم يكون **الأيام اللي قبل البداية وبس**.
class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};

  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  @override
  Future<void> ensurePermissions() async {}
}

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final _now = DateTime(2026, 9, 15, 10);
final _today = DateTime(2026, 9, 15);
final _later = DateTime(2026, 9, 18);

const _timings = [
  AnchorTiming(DayAnchor.breakfast, -30),
  AnchorTiming(DayAnchor.dinner, 30),
];

Future<(AppDatabase, _Sink, ReminderScheduler, DoseEventRepository, int)> _build(DateTime start) async {
  final db = AppDatabase(NativeDatabase.memory());
  final sink = _Sink();
  final routines = RoutineRepository(db);
  final meds = MedicationRepository(db, clock: seededLongAgo);
  final patientId = await routines.ensurePatient();
  await routines.saveRoutine(patientId, _routine);
  await meds.addMedicationWithDoses(
    patientId: patientId,
    name: 'Concor',
    amountLabel: 'قرص',
    timings: _timings,
    startDate: start,
  );
  final events = DoseEventRepository(db);
  final scheduler = ReminderScheduler(
    routines: routines,
    medications: meds,
    events: events,
    patientId: patientId,
    sink: sink,
  );
  return (db, sink, scheduler, events, patientId);
}

Set<String> _plan(_Sink sink) => {
      for (final n in sink.scheduled.values) '${n.id}|${n.at.toIso8601String()}|${n.kind.name}',
    };

void main() {
  test('بداية بعد ٣ أيام: ولا إشعار قبلها — وبعدها الخطة هي هي بالحرف', () async {
    final (dbA, sinkA, schedA, _, _) = await _build(_today);
    final (dbB, sinkB, schedB, _, _) = await _build(_later);
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    await schedA.rescheduleAll(now: _now);
    await schedB.rescheduleAll(now: _now);

    final today = _plan(sinkA);
    final later = _plan(sinkB);
    expect(today, isNotEmpty, reason: 'الاختبار نفسه لازم يشوف خطة');

    // ولا حاجة قبل البداية — لا جرعة ولا درجة سلّم ولا إعادة
    for (final n in sinkB.scheduled.values) {
      expect(n.at.isBefore(_later), isFalse, reason: 'إشعار قبل البداية: ${n.at} (${n.id})');
    }
    expect(later, isNotEmpty);

    // وبعد البداية: **نفس أرقام الجرعات ونفس لحظاتها** في الأيام اللي
    // النافذتين بيغطّوها مع بعض. (السلّم والإعادات بياخدوا «الأقرب» من
    // كل خطة، فبيتحرّكوا مع البداية — وده الصح، مش فرق.)
    final overlapEnd = _later.add(const Duration(days: 6));
    Set<String> doses(_Sink sink) => {
          for (final n in sink.scheduled.values)
            if (isDoseId(n.id) && !n.at.isBefore(_later) && n.at.isBefore(overlapEnd))
              '${n.id}|${n.at.toIso8601String()}',
        };
    expect(doses(sinkB), isNotEmpty);
    expect(doses(sinkB), doses(sinkA));

    // والسلّم والإعادات بتوع الدوا الجاي بيبدأوا يوم البداية، مش قبله
    final firstLadder = sinkB.scheduled.values.where((n) => isEscalationId(n.id)).map((n) => n.at).reduce((a, b) => a.isBefore(b) ? a : b);
    expect(firstLadder.isBefore(_later), isFalse);
    expect(today.length, greaterThanOrEqualTo(later.length));
  });

  test('«يومك» ما بتشوفش الدوا قبل بدايته: مفيش صف جرعة النهارده، وفيه يوم البداية', () async {
    final (db, _, _, events, patientId) = await _build(_later);
    addTearDown(db.close);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final schedules = await meds.activeSchedules(patientId);
    final engine = ScheduleEngine(_routine);

    expect(engine.remindersForDay(schedules, _today), isEmpty);
    expect(engine.remindersForDay(schedules, _later), hasLength(2));

    await events.materializeDay(_today, engine.remindersForDay(schedules, _today));
    expect(await db.select(db.doseEvents).get(), isEmpty, reason: 'ولا صف قبل البداية');
  });

  test('دوا من الدفعة (الروشتة) بياخد بدايته لوحده لو اتحدّدت', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await routines.ensurePatient();
    await meds.addMedicationsWithDoses(
      patientId: patientId,
      startDate: _today,
      medications: [
        (
          name: 'A',
          timings: _timings,
          amountLabel: null,
          amountUnknown: false,
          durationDays: null,
          alertMode: null,
          purpose: null,
          instructions: null,
          startDate: null,
        ),
        (
          name: 'B',
          timings: _timings,
          amountLabel: null,
          amountUnknown: false,
          durationDays: null,
          alertMode: null,
          purpose: null,
          instructions: null,
          startDate: _later,
        ),
      ],
    );
    final starts = {
      for (final s in await meds.activeSchedules(patientId)) s.medicationName: s.startDate,
    };
    expect(starts['A'], _today);
    expect(starts['B'], _later);
  });
}
