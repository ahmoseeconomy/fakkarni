import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../support/seeded_clock.dart';
import 'sync_service_test.dart' show FakeSyncRemote, normalDay, aug31;

/// سحابة لسه ما شغّلتش ٠٠٢٦: أي صف فيه عمود جديد بيترفض بـPGRST204 زي
/// PostgREST بالظبط.
class _OldCloud extends FakeSyncRemote {
  final rejected = <String>[];

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (table == 'medications' && rows.any((r) => r.containsKey('purpose'))) {
      rejected.add(table);
      throw const SyncRejected('PGRST204', "Could not find the 'purpose' column of 'medications'");
    }
    await super.upsert(table, rows);
  }
}

/// ٠٠٢٦ بتزوّد الغرض والتعليمات ونوع التنبيه على medications. **لو النسخة
/// وصلت قبل الهجرة، الجرعات لازم تفضل توصل** — وإلا الابن يتنبّه عن جرعات
/// اتاخدت.
void main() {
  late AppDatabase db;
  late SyncService sync;
  late _OldCloud remote;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    remote = _OldCloud();
    sync = SyncService(
      db: db,
      remote: remote,
      hasSession: () => true,
      localWrites: const Stream.empty(),
      blockStore: MemorySyncBlockStore(),
    );
    final routines = RoutineRepository(db);
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
    await MedicationRepository(db, clock: seededLongAgo).addMedicationWithDoses(
      patientId: patientId,
      name: 'Concor 5mg',
      timings: const [AnchorTiming(DayAnchor.breakfast, -30)],
      startDate: aug31,
      purpose: MedicationPurpose.pressure,
      instructions: 'بعد الأكل',
    );
    await sync.confirmLinked();
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  test('السحابة القديمة بترفض العمود — الأدوية بتوصل من غيره، وباقي الجداول بتكمّل', () async {
    await sync.push();
    expect(remote.rejected, ['medications'], reason: 'اتجرّب بالأعمدة الأول');
    final row = remote.tables['medications']!.values.single;
    expect(row.containsKey('purpose'), isFalse);
    expect(row['name'], 'Concor 5mg');
    expect(remote.rowCount('dose_schedules'), 1, reason: 'اللي بعد الأدوية ما وقفش');
    expect(await sync.stats().then((s) => s.dirtyCount), 0);
  });

  test('السحابة الجديدة بتاخد التفاصيل كاملة', () async {
    final fresh = FakeSyncRemote();
    final s2 = SyncService(
      db: db,
      remote: fresh,
      hasSession: () => true,
      localWrites: const Stream.empty(),
      blockStore: MemorySyncBlockStore(),
    );
    await s2.confirmLinked();
    await s2.push();
    final row = fresh.tables['medications']!.values.single;
    expect(row['purpose'], 'pressure');
    expect(row['instructions'], 'بعد الأكل');
    expect(row['alert_mode'], isNull);
    await s2.dispose();
  });

  test('رفض تاني (مش عمود ناقص) لسه بيوقّف الدفعة زي ما كان', () async {
    remote.failOnTable = 'medications';
    remote.rejectCode = '42501';
    await sync.push();
    expect(remote.rowCount('dose_schedules'), 0);
  });
}
