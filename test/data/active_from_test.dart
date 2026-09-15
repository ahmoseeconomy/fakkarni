// «نسيتها؟» على دوا لسه متضاف: جرعة معادها قبل ما قاعدتها تبقى سارية
// (`dose_schedules.active_from`) ما يتعملّهاش صف ولا سلّم. اتلقت في مشي
// المحاكي: Concor قبل الفطار (٧:٠٠) اتضاف ١١:١٧ وظهر فوراً «نسيتها؟».
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import 'reminder_plan_test.dart' show FakeReminderSink, normalDay;

final aug30 = DateTime(2026, 8, 30);
final aug31 = DateTime(2026, 8, 31);
final sep1 = DateTime(2026, 9, 1);

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late MedicationRepository meds;
  late ReminderScheduler scheduler;
  late FakeReminderSink sink;
  late DateTime clock;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    clock = DateTime(2000);
    meds = MedicationRepository(db, clock: () => clock);
    sink = FakeReminderSink();
    final patientId = await routines.ensurePatient();
    // صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م
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

  Future<DoseEventRow?> eventOf(int scheduleId, DateTime day) =>
      (db.select(db.doseEvents)..where((t) => t.doseScheduleId.equals(scheduleId) & t.routineDay.equalsValue(day)))
          .getSingleOrNull();

  Future<int> scheduleIdOf(int medicationId, DayAnchor anchor) async =>
      (await (db.select(db.doseSchedules)
                ..where((t) => t.medicationId.equals(medicationId) & t.anchor.equalsValue(anchor)))
              .getSingle())
          .id;

  test('دوا جديد ١١:١٧: جرعة ٧:٠٠ النهارده من غير صف، و٢:٠٠ النهارده وبكرة ٧:٠٠ بصفوف', () async {
    final at1117 = DateTime(2026, 8, 31, 11, 17);
    clock = at1117;
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug31,
    );
    await meds.addDoseSchedule(medId, timing: const AnchorTiming(DayAnchor.lunch, -30), startDate: aug31);
    final morning = await scheduleIdOf(medId, DayAnchor.breakfast);
    final afternoon = await scheduleIdOf(medId, DayAnchor.lunch);

    await scheduler.rescheduleAll(now: at1117);

    expect(await eventOf(morning, aug31), isNull, reason: 'الجرعة دي ما كانتش موجودة');
    expect(await eventOf(morning, aug30), isNull);
    expect((await eventOf(afternoon, aug31))!.scheduledAt, DateTime(2026, 8, 31, 14));
    expect((await eventOf(morning, sep1))!.scheduledAt, DateTime(2026, 9, 1, 7));

    // ولا بعد المهلة بتتكتب «اتنست»
    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 13));
    expect(await eventOf(morning, aug31), isNull);
    expect(
      await (db.select(db.doseEvents)..where((t) => t.state.equalsValue(DoseState.missed))).get(),
      isEmpty,
    );
  });

  test('جرعة جديدة على دوا عمره أيام: نفس القاعدة — من لحظة إضافة الجرعة', () async {
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: DateTime(2026, 8, 20),
    );
    final at1117 = DateTime(2026, 8, 31, 11, 17);
    clock = at1117;
    await meds.addDoseSchedule(medId, timing: const AnchorTiming(DayAnchor.breakfast, -30), startDate: aug31);
    final morning = await scheduleIdOf(medId, DayAnchor.breakfast);
    final evening = await scheduleIdOf(medId, DayAnchor.dinner);

    await scheduler.rescheduleAll(now: at1117);

    expect(await eventOf(morning, aug31), isNull);
    expect((await eventOf(morning, sep1))!.scheduledAt, DateTime(2026, 9, 1, 7));
    expect((await eventOf(evening, aug31))!.scheduledAt, DateTime(2026, 8, 31, 20),
        reason: 'الجرعة القديمة ما اتلمستش');
  });

  test('جرعة معادها ١١:٠٠ اتضافت ١١:١٧ → مفيش درجة +٣٠ بترن على حاجة مش موجودة', () async {
    final at1117 = DateTime(2026, 8, 31, 11, 17);
    clock = at1117;
    await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: FixedTiming(MinuteOfDay.hm(11)),
      startDate: aug31,
    );

    await scheduler.rescheduleAll(now: at1117);

    final eleven = DateTime(2026, 8, 31, 11);
    expect(sink.scheduled.containsKey(escalationIdFor(eleven, EscalationRung.second)), isFalse);
    expect(sink.escalations.values.any((n) => n.at.day == 31), isFalse);
  });

  test('عكسي: دوا من امبارح جرعته ٧:٠٠ النهارده بتتسجل وبتبقى «اتنست» عادي', () async {
    clock = DateTime(2026, 8, 30, 20);
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug30,
    );
    final morning = await scheduleIdOf(medId, DayAnchor.breakfast);

    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 11, 17));

    final row = (await eventOf(morning, aug31))!;
    expect(row.scheduledAt, DateTime(2026, 8, 31, 7));
    expect(row.state, DoseState.missed);
  });

  test('الصف القديم (قبل v15) من غير سريان = ساري من الأول', () async {
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug30,
    );
    final morning = await scheduleIdOf(medId, DayAnchor.breakfast);
    await (db.update(db.doseSchedules)..where((t) => t.id.equals(morning)))
        .write(const DoseSchedulesCompanion(activeFrom: Value(null)));

    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 11, 17));

    expect((await eventOf(morning, aug31))!.state, DoseState.missed);
  });

  test('تعديل ٢:٠٠ → ٧:٠٠ الساعة ١١:١٧: صف النهارده «اتغيّرت القاعدة» مش «نسيتها؟»، وبكرة ٧:٠٠', () async {
    clock = DateTime(2026, 8, 30, 9);
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.lunch, -30),
      startDate: aug30,
    );
    final id = await scheduleIdOf(medId, DayAnchor.lunch);
    // امبارح بالليل: صف النهارده اتعمل كـ«بكرة» (وممكن يكون اتبعت للسحابة)
    await scheduler.rescheduleAll(now: DateTime(2026, 8, 30, 21));
    expect((await eventOf(id, aug31))!.state, DoseState.pending);

    final at1117 = DateTime(2026, 8, 31, 11, 17);
    clock = at1117;
    await meds.updateTiming(id, const AnchorTiming(DayAnchor.breakfast, -30));
    await scheduler.rescheduleAll(now: at1117);

    final today = (await eventOf(id, aug31))!;
    expect(today.state, DoseState.superseded,
        reason: 'ما يتمسحش: السحابة مفيهاش مسح، وصف pending هناك كان هينبّه ابنه');
    expect((await eventOf(id, sep1))!.scheduledAt, DateTime(2026, 9, 1, 7));

    // مش بيتقري في «يومك» ولا بيتكتب «اتنست» بعد المهلة
    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 15));
    expect((await eventOf(id, aug31))!.state, DoseState.superseded);
    final visible = await DoseEventRepository(db).watchDay(aug31).first;
    expect(visible, isEmpty);

    // ورجع تاني لميعاد لسه قدام → الصف يرجع «لسه» بميعاده الجديد
    clock = DateTime(2026, 8, 31, 15, 5);
    await meds.updateTiming(id, const AnchorTiming(DayAnchor.dinner, 0));
    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 15, 5));
    final back = (await eventOf(id, aug31))!;
    expect(back.state, DoseState.pending);
    expect(back.scheduledAt, DateTime(2026, 8, 31, 20));
  });

  test('updateTiming بيحدّث لحظة السريان', () async {
    final medId = await meds.addMedication(
      patientId: 1,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.lunch, -30),
      startDate: aug30,
    );
    final id = await scheduleIdOf(medId, DayAnchor.lunch);
    clock = DateTime(2026, 8, 31, 11, 17);
    await meds.updateTiming(id, const AnchorTiming(DayAnchor.breakfast, -30));

    final row = await (db.select(db.doseSchedules)..where((t) => t.id.equals(id))).getSingle();
    expect(row.activeFrom, DateTime(2026, 8, 31, 11, 17));
  });
}
