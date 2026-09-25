import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/care/medication_changes.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../features/scan/scan_test_support.dart' show RecordingSink;
import '../../support/seeded_clock.dart';

/// تغييرات الممرض بتتطبّق بسكّة الأب نفسها وبتعيد الجدولة — وتعديل الأب
/// المحلي بيكسب.
class _FakeChanges implements MedicationChangeRemote {
  final pending = <MedicationChange>[];
  final marked = <(String, ChangeOutcome)>[];

  @override
  Future<void> submit({required String patientUuid, required MedicationChangeKind kind, required MedicationChangePayload payload, String? medicationUuid, String? medicationName, String? actorName}) async {}

  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) async => List.of(pending);

  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) async => List.of(pending);

  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) async {
    marked.add((changeUuid, outcome));
    pending.removeWhere((c) => c.uuid == changeUuid);
  }
}

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(8, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);
final _now = DateTime(2026, 9, 15, 6);

void main() {
  late AppDatabase db;
  late RecordingSink sink;
  late RoutineRepository routines;
  late MedicationRepository meds;
  late ReminderScheduler scheduler;
  late _FakeChanges remote;
  late int patientId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MedicationChangePuller.notices.value = const [];
    db = AppDatabase(NativeDatabase.memory());
    sink = RecordingSink();
    routines = RoutineRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, _routine);
    scheduler = ReminderScheduler(routines: routines, medications: meds, events: DoseEventRepository(db), patientId: patientId, sink: sink);
    remote = _FakeChanges();
  });

  tearDown(() => db.close());

  MedicationChangePuller puller() => MedicationChangePuller(
        remote: remote,
        db: db,
        routines: routines,
        medications: meds,
        scheduler: scheduler,
        patientId: patientId,
        clock: () => _now,
      );

  MedicationChange change(String uuid, MedicationChangeKind kind, {String? medUuid, MedicationChangePayload payload = const MedicationChangePayload(), DateTime? at}) =>
      MedicationChange(uuid: uuid, kind: kind, medicationUuid: medUuid, medicationName: 'Concor', payload: payload, actorName: 'سارة', createdAt: at ?? _now);

  test('إضافة من الممرض → دوا بجدوله محلول بروتين الأب، وإشعار متجدول، والصف اتعلّم applied، والجملة اتحفظت', () async {
    remote.pending.add(change('c1', MedicationChangeKind.add, payload: const MedicationChangePayload(
      name: 'Concor 5mg',
      timings: [AnchorTiming(DayAnchor.breakfast, -30)],
      amountLabel: 'قرص',
    )));
    expect(await puller().pull(), 1);

    final saved = (await meds.activeSchedules(patientId)).single;
    expect(saved.medicationName, 'Concor 5mg');
    expect(saved.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    // ٨:٣٠ − ٣٠ = ٨:٠٠ بروتين **الأب**، مش الافتراضي بتاع الممرض (٧:٠٠)
    expect(sink.scheduled.keys, contains(notificationIdFor(DateTime(2026, 9, 15, 8))));
    expect(remote.marked, [('c1', ChangeOutcome.applied)]);
    expect(MedicationChangePuller.notices.value, ['سارة ضاف دوا Concor 5mg']);
    expect((await SharedPreferences.getInstance()).getStringList(MedicationChangePuller.noticesKey), ['سارة ضاف دوا Concor 5mg']);
  });

  test('إيقاف: بيتطبّق لو الأب ما لمسش الدوا بعد الاقتراح — وتعديل الأب المحلي بيكسب', () async {
    final id = await meds.addMedication(patientId: patientId, name: 'Concor', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: DateTime(2026, 9, 1));
    final row = (await db.select(db.medications).get()).single;
    // الاقتراح اتبعت **بعد** آخر تعديل محلي → بيتطبّق
    remote.pending.add(change('c-stop', MedicationChangeKind.stop, medUuid: row.uuid, at: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs).add(const Duration(minutes: 1))));
    expect(await puller().pull(), 1);
    expect((await db.select(db.medications).get()).single.stoppedAt, isNotNull);
    expect(remote.marked.last, ('c-stop', ChangeOutcome.applied));

    // دوا تاني: الأب عدّله بعد ما الممرض بعت → التعديل المحلي بيكسب
    final id2 = await meds.addMedication(patientId: patientId, name: 'Glucophage', timing: const AnchorTiming(DayAnchor.lunch, 0), startDate: DateTime(2026, 9, 1));
    final row2 = (await db.select(db.medications).get()).firstWhere((m) => m.id == id2);
    remote.pending.add(change('c-conflict', MedicationChangeKind.stop, medUuid: row2.uuid, at: DateTime.fromMillisecondsSinceEpoch(row2.updatedAtMs).subtract(const Duration(hours: 1))));
    expect(await puller().pull(), 0);
    expect((await db.select(db.medications).get()).firstWhere((m) => m.id == id2).stoppedAt, isNull, reason: 'تعديل الأب كسب');
    expect(remote.marked.last, ('c-conflict', ChangeOutcome.conflict));
    expect(id, isNot(id2));
  });

  test('تعديل الجرعة بيتكتب، ودوا مش موجود missing، والصف مش بيتسحب تاني', () async {
    await meds.addMedication(patientId: patientId, name: 'Concor', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: DateTime(2026, 9, 1));
    final row = (await db.select(db.medications).get()).single;
    remote.pending.add(change('c-amount', MedicationChangeKind.amount, medUuid: row.uuid,
        payload: const MedicationChangePayload(amountLabel: 'قرصين'),
        at: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs).add(const Duration(minutes: 1))));
    remote.pending.add(change('c-missing', MedicationChangeKind.stop, medUuid: 'nope'));
    expect(await puller().pull(), 1);
    expect((await db.select(db.medications).get()).single.amountLabel, 'قرصين');
    expect(remote.marked, containsAll([('c-amount', ChangeOutcome.applied), ('c-missing', ChangeOutcome.missing)]));
    expect(await puller().pull(), 0);
  });

  test('٠٠٢٨: «اشتريت علبة جديدة» من الممرض بتزوّد المخزون — ومن غير فحص تعارض (إضافة مش كتابة فوق)', () async {
    final id = await meds.addMedication(patientId: patientId, name: 'Concor', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: DateTime(2026, 9, 1));
    final row = (await db.select(db.medications).get()).single;
    await StockRepository(db).setQuantity(id, 4);
    // اتبعت **قبل** آخر تعديل محلي — ومع ذلك بيتطبّق: علبة اتشرت فعلاً
    remote.pending.add(change('c-restock', MedicationChangeKind.restock, medUuid: row.uuid,
        payload: const MedicationChangePayload(quantity: 30),
        at: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs).subtract(const Duration(hours: 1))));
    expect(await puller().pull(), 1);
    expect((await StockRepository(db).rowFor(id))!.quantity, 34);
    expect(remote.marked.last, ('c-restock', ChangeOutcome.applied));
    expect(sink.scheduled.keys.where(isRefillId), isEmpty, reason: 'المخزون ما بيلمسش التذكيرات');
  });

  test('٠٠٢٦: ميعاد من الممرض → متابعة زيارة بميعادها وإشعاراتها على موبايل الأب، والجملة بتسمّيه', () async {
    remote.pending.add(change('c-appt', MedicationChangeKind.appointment,
        payload: MedicationChangePayload(name: 'د. حسام', followKind: 'visit', day: DateTime(2026, 9, 18))));
    expect(await puller().pull(), 1);
    final row = (await db.select(db.records).get()).single;
    expect(row.followKind, 'visit');
    expect(row.checkupStage, isNotNull);
    expect(row.doctorVisitAt, isNotNull, reason: 'الميعاد اتحط على المرحلة');
    expect(row.doctorVisitAt!.day, 18);
    expect(sink.scheduled.keys.where(isAppointmentId), isNotEmpty, reason: 'إشعارات الميعاد اتجدولت على موبايله');
    expect(MedicationChangePuller.notices.value.single, 'سارة حط ميعاد زيارة د. حسام');
    expect(remote.marked, [('c-appt', ChangeOutcome.applied)]);
  });

  test('٠٠٢٦: ورقة من الممرض → سجل من غير صورة بنوعه وتاريخه', () async {
    remote.pending.add(change('c-rec', MedicationChangeKind.record,
        payload: MedicationChangePayload(
          name: 'كشف القلب',
          recordKind: 'visit',
          happenedAt: DateTime(2026, 9, 14),
          doctor: 'د. سامي',
          notes: '',
        )));
    expect(await puller().pull(), 1);
    final row = (await db.select(db.records).get()).single;
    expect(row.title, 'كشف القلب');
    expect(row.kind.name, 'visit');
    expect(row.happenedAt, DateTime(2026, 9, 14));
    expect(row.doctor, 'د. سامي');
    expect(row.notes, isNull, reason: 'فاضي = مش مكتوب');
    expect(row.attachmentPath, isNull);
    expect(MedicationChangePuller.notices.value.single, 'سارة ضاف ورقة كشف القلب');
  });

  test('٠٠٢٦: ورقة من غير عنوان أو نوع مش معروف → missing، ومفيش سجل', () async {
    remote.pending.add(change('c-bad', MedicationChangeKind.record,
        payload: const MedicationChangePayload(name: 'x', recordKind: 'weird')));
    expect(await puller().pull(), 0);
    expect(await db.select(db.records).get(), isEmpty);
    expect(remote.marked, [('c-bad', ChangeOutcome.missing)]);
  });
}
