import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../support/seeded_clock.dart';
import 'sync_service_test.dart' show FakeSyncRemote;

/// المخزون بيترفع (٠٠٢٨) عشان العيلة والممرض يشوفوه — ومن غير الهجرة
/// الصف بيفضل مستني، وباقي الرفعة ما بتقعش.
class _NoStockTable extends FakeSyncRemote {
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (table == 'medication_stock') {
      throw const SyncRejected('PGRST205', "Could not find the table 'public.medication_stock'");
    }
    await super.upsert(table, rows);
  }
}

void main() {
  test('صف المخزون بيترفع بالكمية وحد التنبيه — ومن غير الجدول بيفضل مستني', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final routines = RoutineRepository(db);
    final patientId = await routines.ensurePatient(name: 'أحمد');
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    final medId = await MedicationRepository(db, clock: seededLongAgo).addMedication(
      patientId: patientId,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: DateTime(2026, 9, 1),
    );
    await StockRepository(db).setQuantity(medId, 12, warnDays: 7);

    final missing = _NoStockTable();
    final sync = SyncService(db: db, remote: missing, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync.confirmLinked();
    await sync.push();
    expect(missing.rowCount('medications'), 1, reason: 'باقي الرفعة ما وقعتش');
    expect((await db.select(db.medicationStock).getSingle()).syncedAtMs, isNull, reason: 'مستني ٠٠٢٨');
    await sync.dispose();

    final cloud = FakeSyncRemote();
    final sync2 = SyncService(db: db, remote: cloud, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync2.confirmLinked();
    await sync2.push();
    final row = cloud.tables['medication_stock']!.values.single;
    final med = (await db.select(db.medications).getSingle());
    expect((row['medication_uuid'], row['quantity'], row['warn_days']), (med.uuid, 12.0, 7));
    expect(row.containsKey('notified_at'), isFalse, reason: 'ميعاد التنبيه محلي');
    await sync2.dispose();
  });
}
