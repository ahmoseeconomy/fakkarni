import 'package:drift/drift.dart' show Value;
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
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import '../support/seeded_clock.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final times = RamadanTimes(
  iftar: MinuteOfDay.hm(18),
  suhoor: MinuteOfDay.hm(3, 30),
);

final aug31 = DateTime(2026, 8, 31);

class RecordingSink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};

  @override
  Future<void> schedule(PlannedNotification notification) async =>
      scheduled[notification.id] = notification;
  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
  @override
  Future<void> ensurePermissions() async {}
}

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
  });

  tearDown(() => db.close());

  Future<DayRoutineRow> row() =>
      (db.select(db.dayRoutines)..where((t) => t.patientId.equals(patientId)))
          .getSingle();

  test('مقفول في الأول — مفيش نسخة احتياطية', () async {
    expect(await routines.ramadanTimes(patientId), isNull);
  });

  test('فتح → الروتين بقى رمضان، والأصل اتحفظ بالحرف قبل الكتابة', () async {
    final before = await row();
    await routines.enterRamadan(patientId, times);

    expect(await routines.getRoutine(patientId), ramadanRoutine(normalDay, times));
    expect(await routines.ramadanTimes(patientId), times);

    final backup = (await db.select(db.routineBackups).get()).single;
    expect(
      [
        backup.wakeMinutes,
        backup.breakfastMinutes,
        backup.lunchMinutes,
        backup.dinnerMinutes,
        backup.sleepMinutes,
      ],
      [
        before.wakeMinutes,
        before.breakfastMinutes,
        before.lunchMinutes,
        before.dinnerMinutes,
        before.sleepMinutes,
      ],
    );
  });

  test('فتح ثم قفل → الصف رجع بالحرف: نفس id وuuid والخمس مواعيد', () async {
    final before = await row();
    await routines.enterRamadan(patientId, times);
    await routines.leaveRamadan(patientId);
    final after = await row();

    expect(after.id, before.id);
    expect(after.uuid, before.uuid, reason: 'تعديل في مكانه — مش delete/insert');
    expect(after.wakeMinutes, before.wakeMinutes);
    expect(after.breakfastMinutes, before.breakfastMinutes);
    expect(after.lunchMinutes, before.lunchMinutes);
    expect(after.dinnerMinutes, before.dinnerMinutes);
    expect(after.sleepMinutes, before.sleepMinutes);
    expect(await routines.ramadanTimes(patientId), isNull);
    expect(await db.select(db.routineBackups).get(), isEmpty);
  });

  test('فتح/قفل مرتين → الروتين هو هو من الأول — ده اللي بيمسك رجوع غلطان',
      () async {
    for (var i = 0; i < 2; i++) {
      await routines.enterRamadan(patientId, times);
      await routines.leaveRamadan(patientId);
    }
    expect(await routines.getRoutine(patientId), normalDay);
  });

  test('فتح وهو مفتوح (تعديل الفطار) → الأصل المحفوظ ما بيتلمسش', () async {
    await routines.enterRamadan(patientId, times);
    final later = times.copyWith(iftar: MinuteOfDay.hm(18, 20));
    await routines.enterRamadan(patientId, later);

    expect((await routines.getRoutine(patientId))!.breakfast, MinuteOfDay.hm(18, 20));
    expect(await routines.ramadanTimes(patientId), later);

    await routines.leaveRamadan(patientId);
    expect(await routines.getRoutine(patientId), normalDay,
        reason: 'لو النسخة الاحتياطية اتكتبت من روتين رمضان، الأصل كان ضاع');
  });

  test('ramadanOriginal: null وهو مقفول، والأصل بالحرف وهو شغّال', () async {
    expect(await routines.ramadanOriginal(patientId), isNull);
    await routines.enterRamadan(patientId, times);
    expect(await routines.ramadanOriginal(patientId), normalDay);
    await routines.leaveRamadan(patientId);
    expect(await routines.ramadanOriginal(patientId), isNull);
  });

  test('قفل وهو مقفول → ولا حاجة بتحصل', () async {
    await routines.leaveRamadan(patientId);
    expect(await routines.getRoutine(patientId), normalDay);
  });

  test('الصف بيتوسّخ للمزامنة في الاتجاهين — الابن بيشوف الروتين الساري',
      () async {
    // نعلّمه «مدفوع» زي ما SyncService بيعمل، ونستنى شوية عشان الملّي تتحرك
    final clean = await row();
    await (db.update(db.dayRoutines)..where((t) => t.patientId.equals(patientId)))
        .write(DayRoutinesCompanion(syncedAtMs: Value(clean.updatedAtMs)));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await routines.enterRamadan(patientId, times);
    final r = await row();
    expect(r.updatedAtMs, greaterThan(r.syncedAtMs!),
        reason: 'التريجر بيرفع updated_at_ms فوق synced_at_ms');
  });

  test('التذكيرات: جرعة المرساة اتحركت والثابتة رجعت بنفس رقمها — وبالعكس',
      () async {
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final sink = RecordingSink();
    final scheduler = ReminderScheduler(
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      patientId: patientId,
      sink: sink,
    );
    await meds.addMedication(
      patientId: patientId,
      name: 'Antodine',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug31,
    );
    await meds.addMedication(
      patientId: patientId,
      name: 'Fixed',
      timing: FixedTiming(MinuteOfDay.hm(14)),
      startDate: aug31,
    );
    final now = DateTime(2026, 8, 31, 6);

    await scheduler.rescheduleAll(now: now);
    final start = Map.of(sink.scheduled);
    int idOf(Map<int, PlannedNotification> m, String name) => m.entries
        .firstWhere((e) => e.value.title.contains(name) || e.value.body.contains(name))
        .key;
    final fixedId = idOf(start, 'Fixed');
    final anchorId = idOf(start, 'Antodine');

    await routines.enterRamadan(patientId, times);
    await scheduler.rescheduleAll(now: now);
    expect(sink.scheduled.containsKey(fixedId), isTrue, reason: 'الثابتة مكانها');
    expect(sink.scheduled.containsKey(anchorId), isFalse, reason: 'المرساة اتحركت');
    expect(sink.scheduled[idOf(sink.scheduled, 'Antodine')]!.at.hour, 17);

    await routines.leaveRamadan(patientId);
    await scheduler.rescheduleAll(now: now);
    expect(sink.scheduled.keys.toSet(), start.keys.toSet(),
        reason: 'نفس الأرقام بالظبط زي قبل رمضان');
  });
}
