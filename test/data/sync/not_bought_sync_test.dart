import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/care/medication_changes.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart' show medicationFromRow;
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/not_bought_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../features/scan/scan_test_support.dart' show RecordingSink;
import '../../support/seeded_clock.dart';
import 'sync_service_test.dart' show FakeSyncRemote;

/// ٠٠٣١: «لسه ماتشترتش» بتطلع مع الدوا، بترجع للدائرة زي ما هي، و«اشتريته»
/// من الممرض بتشيلها على موبايل المريض من غير ما تلمس المخزون.
void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late MedicationRepository meds;
  late int patientId;
  late int bought;
  late int notBought;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    patientId = await routines.ensurePatient(name: 'أحمد');
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    meds = MedicationRepository(db, clock: seededLongAgo);
    bought = await meds.addMedication(
        patientId: patientId, name: 'Glucophage', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: DateTime(2026, 9, 1));
    notBought = await meds.addMedication(
        patientId: patientId, name: 'Concor', timing: const AnchorTiming(DayAnchor.breakfast, 0), startDate: DateTime(2026, 9, 1));
    await NotBoughtRepository(db, clock: () => DateTime(2026, 9, 25, 10)).markNotBought(notBought);
  });
  tearDown(() => db.close());

  test('بتطلع مع الدوا، وبترجع من الدائرة زي ما هي — والمشتري null', () async {
    final cloud = FakeSyncRemote();
    final sync = SyncService(db: db, remote: cloud, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync.confirmLinked();
    await sync.push();
    final rows = cloud.tables['medications']!.values.toList();
    final concor = rows.firstWhere((r) => r['name'] == 'Concor');
    final gluco = rows.firstWhere((r) => r['name'] == 'Glucophage');
    expect(concor['not_bought_at'], DateTime(2026, 9, 25, 10).toUtc().toIso8601String());
    expect(gluco['not_bought_at'], isNull, reason: 'اللي اتشرى ما بيتغيّرلوش حاجة');

    // الابن/الممرض بيقروا نفس الصف
    expect(medicationFromRow({...concor, 'dose_schedules': const []}).notBoughtAt, DateTime(2026, 9, 25, 10));
    expect(medicationFromRow({...gluco, 'dose_schedules': const []}).notBoughtAt, isNull);
    await sync.dispose();
  });

  test('«اشتريته» من الممرض بتشيل العلامة على موبايل المريض — والمخزون زي ما هو', () async {
    await StockRepository(db).setQuantity(notBought, 4);
    final uuid = (await (db.select(db.medications)..where((t) => t.id.equals(notBought))).getSingle()).uuid;
    final remote = _Changes()
      ..pending.add(MedicationChange(
        uuid: 'c-bought',
        kind: MedicationChangeKind.bought,
        medicationUuid: uuid,
        medicationName: 'Concor',
        payload: const MedicationChangePayload(),
        actorName: 'سارة',
        createdAt: DateTime(2026, 9, 25, 9), // قبل آخر تعديل محلي — ومع ذلك بيتطبّق
      ));
    final applied = await MedicationChangePuller(
      remote: remote,
      db: db,
      routines: routines,
      medications: meds,
      scheduler: ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: RecordingSink(),
      ),
      patientId: patientId,
      clock: () => DateTime(2026, 9, 25, 12),
    ).pull();
    expect(applied, 1);
    expect(remote.marked.single, ('c-bought', ChangeOutcome.applied));
    expect(await NotBoughtRepository(db).all(patientId), isEmpty);
    expect((await StockRepository(db).rowFor(notBought))!.quantity, 4, reason: 'مفيش كمية بتتخمّن');
    expect(MedicationChangePuller.notices.value, ['سارة علّم إنه اشترى Concor']);
    expect(bought, isNot(notBought));
  });
}

class _Changes implements MedicationChangeRemote {
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
