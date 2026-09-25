import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/adherence/adherence.dart';
import 'package:fakkarni/domain/scheduling/day_pattern.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../features/scan/scan_test_support.dart' show RecordingSink, normalDay;
import '../support/seeded_clock.dart';
import 'sync/sync_service_test.dart' show FakeSyncRemote;

/// خطط ذهبية لأنماط الأيام: اليوم المقفول ما بيطلعش منه ولا إشعار ولا
/// درجة ولا إعادة ولا حدث — والأيام الشغّالة زي «كل يوم» بالظبط.
void main() {
  late AppDatabase db;
  late RecordingSink sink;
  late ReminderScheduler scheduler;
  late MedicationRepository meds;
  late int patientId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    sink = RecordingSink();
    final routines = RoutineRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    patientId = await routines.ensurePatient(name: 'أحمد');
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

  Future<int> add(DayPattern days, {DateTime? start}) => meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Concor',
        timings: const [AnchorTiming(DayAnchor.breakfast, -30)], // ٧:٠٠ ص
        startDate: start ?? DateTime(2026, 9, 1),
        days: days,
      );

  Set<DateTime> daysOf(Iterable<PlannedNotification> ns) => {for (final n in ns) DateTime(n.at.year, n.at.month, n.at.day)};
  Iterable<PlannedNotification> byKind(NotificationKind k) => sink.scheduled.values.where((n) => n.kind == k);
  Future<Set<DateTime>> eventDays() async => {for (final e in await db.select(db.doseEvents).get()) e.routineDay};

  test('السبت والتلات والخميس: إشعارات وسلّم وإعادات وأحداث في الأيام دي بس', () async {
    await add(OnWeekdays({DateTime.saturday, DateTime.tuesday, DateTime.thursday}));
    await scheduler.rescheduleAll(now: DateTime(2026, 9, 19, 6)); // سبت
    // النافذة ١٩–٢٥: سبت ١٩، تلات ٢٢، خميس ٢٤
    final expected = {DateTime(2026, 9, 19), DateTime(2026, 9, 22), DateTime(2026, 9, 24)};
    expect(daysOf(byKind(NotificationKind.dose)), expected);
    expect(daysOf(byKind(NotificationKind.escalation)).difference(expected), isEmpty);
    expect(daysOf(byKind(NotificationKind.repeat)).difference(expected), isEmpty);
    expect(byKind(NotificationKind.dose).every((n) => n.at.hour == 7 && n.at.minute == 0), isTrue,
        reason: 'الدقيقة من المرساة زي ما هي');
    // ٦ الصبح قبل الصحيان = يوم روتين ١٨ (جمعة): امبارح ١٧ (خميس) وبكرة ١٩
    // (سبت) شغّالين، والجمعة لأ
    expect(await eventDays(), {DateTime(2026, 9, 17), DateTime(2026, 9, 19)});
  });

  test('يوم ويوم: من يوم البداية', () async {
    await add(EveryNDays(2));
    await scheduler.rescheduleAll(now: DateTime(2026, 9, 19, 6));
    expect(daysOf(byKind(NotificationKind.dose)),
        {DateTime(2026, 9, 19), DateTime(2026, 9, 21), DateTime(2026, 9, 23), DateTime(2026, 9, 25)});
    expect(await eventDays(), {DateTime(2026, 9, 17), DateTime(2026, 9, 19)}, reason: '١٨ مقفول');
  });

  test('٢١/٧: النافذة اللي بتعدّي على أسبوع الراحة، واللي بتخرج منه', () async {
    await add(OnOffCycle(21, 7));
    await scheduler.rescheduleAll(now: DateTime(2026, 9, 19, 6));
    expect(daysOf(byKind(NotificationKind.dose)),
        {DateTime(2026, 9, 19), DateTime(2026, 9, 20), DateTime(2026, 9, 21)}, reason: '٢٢–٢٥ راحة');

    sink.scheduled.clear();
    await scheduler.rescheduleAll(now: DateTime(2026, 9, 26, 6));
    expect(daysOf(byKind(NotificationKind.dose)),
        {DateTime(2026, 9, 29), DateTime(2026, 9, 30), DateTime(2026, 10, 1), DateTime(2026, 10, 2)},
        reason: '٢٦–٢٨ راحة، و٢٩ اللفّة التانية');
    final off = [for (var i = 22; i <= 28; i++) DateTime(2026, 9, i)];
    expect((await eventDays()).intersection(off.toSet()), isEmpty, reason: 'ولا حدث في أيام الراحة');
  });

  test('الالتزام: أيام الراحة محايدة — العدّ بيعدّي عليها', () async {
    await add(OnOffCycle(21, 7));
    // أحداث اللفّة كلها من ١٥ لـ٣٠ سبتمبر، كلها اتاخدت — من نفس الدالة
    final schedule = (await meds.activeSchedules(patientId)).single;
    final doses = [
      for (var i = 15; i <= 30; i++)
        if (schedule.isActiveOn(DateTime(2026, 9, i)))
          AdherenceDose(
            id: '$i',
            medicationName: 'Concor',
            routineDay: DateTime(2026, 9, i),
            scheduledAt: DateTime(2026, 9, i, 7),
            state: AdherenceState.taken,
          ),
    ];
    final a = computeAdherence(doses, today: DateTime(2026, 9, 30), now: DateTime(2026, 9, 30, 20));
    // ١٥–٢١ (٧) + ٢٩–٣٠ (٢) = ٩ أيام كاملة، والراحة ما كسرتش
    expect(a.currentStreak, 9);
    expect(a.week.where((w) => w.day.day >= 22 && w.day.day <= 28 && w.day.month == 9).every((w) => w.mark == DayMark.neutral),
        isTrue);
  });

  test('المخزون: السبت/التلات/الخميس = ٣/٧ جرعة في اليوم', () async {
    final id = await add(OnWeekdays({DateTime.saturday, DateTime.tuesday, DateTime.thursday}));
    await StockRepository(db).setQuantity(id, 9);
    final view = (await StockRepository(db).all(patientId)).single;
    expect(view.dosesPerDay, closeTo(3 / 7, 1e-9));
    expect(view.daysLeft, 21, reason: '٩ ÷ ٣/٧');
  });

  test('السحابة قبل ٠٠٣٢: الجدول بنمط بيفضل على الموبايل، وأولاده مستنيينه، والأدمن بيتبلّغ', () async {
    await meds.addMedication(patientId: patientId, name: 'Daily', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: DateTime(2026, 9, 1));
    await add(EveryNDays(2));
    await scheduler.rescheduleAll(now: DateTime(2026, 9, 19, 6));
    final cloud = _OldCloud();
    final sync = SyncService(db: db, remote: cloud, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync.confirmLinked();
    expect(await sync.push(), PushOutcome.pushed, reason: 'باقي الطابور ماشي');

    final pushed = cloud.tables['dose_schedules']!.values.toList();
    expect(pushed, hasLength(1), reason: 'العادي اترفع');
    expect(pushed.single.keys, isNot(contains('weekdays')), reason: 'حمولة العادي زي ما هي بالحرف');
    final patterned = (await db.select(db.doseSchedules).get()).firstWhere((s) => s.everyDays == 2);
    expect(patterned.syncedAtMs, isNull, reason: 'فاضل متوسّخ ومستني');
    final eventUuids = {for (final e in cloud.tables['dose_events']?.values ?? const <Map<String, dynamic>>[]) e['dose_schedule_uuid']};
    expect(eventUuids, isNot(contains(patterned.uuid)), reason: 'الحدث ما اترفعش قبل أبوه');
    expect(await patternRejectedSince(), isNotNull);

    // بعد ٠٠٣٢: بيطلع لوحده، والبلاغ بيتشال
    final fresh = FakeSyncRemote()..tables.addAll(cloud.tables);
    final sync2 = SyncService(db: db, remote: fresh, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync2.confirmLinked();
    await sync2.push();
    expect(fresh.tables['dose_schedules']!.values.any((r) => r['every_days'] == 2), isTrue);
    expect(await patternRejectedSince(), isNull);
    expect((await db.select(db.doseEvents).get()).where((e) => e.state == DoseState.pending), isNotEmpty);
    await sync.dispose();
    await sync2.dispose();
  });
}

/// سحابة لسه ما شغّلتش ٠٠٣٢.
class _OldCloud extends FakeSyncRemote {
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (table == 'dose_schedules' && rows.any((r) => r.containsKey('every_days'))) {
      throw const SyncRejected('PGRST204', "Could not find the 'cycle_off' column of 'dose_schedules'");
    }
    await super.upsert(table, rows);
  }
}
