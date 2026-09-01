import 'package:drift/drift.dart' show Value;

import '../../domain/scheduling/day_routine.dart';
import '../services/reminder_plan.dart' show maxPatients;
import '../db/app_database.dart';
import '../mappers.dart';

/// روتين يوم المريض — بيتسأل مرة واحدة، وكل الجرعات بتترتّب عليه.
class RoutineRepository {
  RoutineRepository(this._db);

  final AppDatabase _db;

  Stream<DayRoutine?> watchRoutine(int patientId) =>
      (_db.select(_db.dayRoutines)
            ..where((t) => t.patientId.equals(patientId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : routineFromRow(row));

  Future<DayRoutine?> getRoutine(int patientId) async {
    final row = await (_db.select(_db.dayRoutines)
          ..where((t) => t.patientId.equals(patientId)))
        .getSingleOrNull();
    return row == null ? null : routineFromRow(row);
  }

  /// بيستبدل الروتين بالكامل.
  ///
  /// ملاحظة مهمة: مفيش أي جرعة بتتلمس هنا. تحريك الفطار بيحرّك كل الجرعات
  /// المربوطة بيه لوحدها لأنها متخزّنة كمرساة، مش كساعة.
  Future<void> saveRoutine(int patientId, DayRoutine routine) =>
      _db.transaction(() async {
        await (_db.delete(_db.dayRoutines)
              ..where((t) => t.patientId.equals(patientId)))
            .go();
        await _db.into(_db.dayRoutines).insert(
              DayRoutinesCompanion.insert(
                patientId: patientId,
                wakeMinutes: routine.wake.minutes,
                breakfastMinutes: routine.breakfast.minutes,
                lunchMinutes: routine.lunch.minutes,
                dinnerMinutes: routine.dinner.minutes,
                sleepMinutes: routine.sleep.minutes,
              ),
            );
      });

  /// بيرجّع المريض الوحيد، وبينشئه لو التطبيق لسه جديد.
  Future<int> ensurePatient({String name = 'أنا'}) async {
    final existing =
        await (_db.select(_db.patients)..limit(1)).getSingleOrNull();
    if (existing != null) return existing.id;

    return _db.into(_db.patients).insert(
          PatientsCompanion.insert(
            name: name,
            notificationSlot: Value(await _lowestFreeSlot()),
          ),
        );
  }

  /// خانة المريض في نطاق أرقام الإشعارات.
  Future<int> patientIndex(int patientId) async {
    final row = await (_db.select(_db.patients)
          ..where((t) => t.id.equals(patientId)))
        .getSingleOrNull();
    return row?.notificationSlot ?? 0;
  }

  /// أصغر خانة فاضية.
  ///
  /// بنعيد استخدام خانات المرضى المتشالين بدل ما نعدّ لفوق على طول، عشان
  /// النطاق ما يفضاش من غير ما يكون فيه ١٢٨ مريض فعلاً.
  Future<int> _lowestFreeSlot() async {
    final taken = (await _db.select(_db.patients).get())
        .map((p) => p.notificationSlot)
        .toSet();

    for (var slot = 0; slot < maxPatients; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    throw StateError('مفيش خانة إشعارات فاضية — الحد الأقصى $maxPatients مريض');
  }
}
