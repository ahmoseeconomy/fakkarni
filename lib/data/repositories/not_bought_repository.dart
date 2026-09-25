import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// **«أدوية لسه ماتشترتش»** — علامة على الدوا وبس.
///
/// **مالهاش أي علاقة بالتذكير**: ولا جدول ولا حدث ولا إشعار بيتلمس هنا.
/// الدوا بيبدأ يرن زي ما «هتبدأ الدوا من إمتى؟» قالت — القايمة دي تذكرة
/// شرا، مش مفتاح للجرعات.
class NotBoughtRepository {
  NotBoughtRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<void> markNotBought(int medicationId) =>
      (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
          .write(MedicationsCompanion(notBoughtAt: Value(_clock())));

  /// «اشتريته».
  Future<void> markBought(int medicationId) =>
      (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
          .write(const MedicationsCompanion(notBoughtAt: Value(null)));

  /// اللي لسه ماتشترتش — الشغّال بس (المتشال والموقوف مالهمش لازمة يتشروا).
  SimpleSelectStatement<$MedicationsTable, MedicationRow> _query(int patientId) =>
      _db.select(_db.medications)
        ..where((t) =>
            t.patientId.equals(patientId) & t.notBoughtAt.isNotNull() & t.removedAt.isNull() & t.stoppedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.notBoughtAt)]);

  Stream<List<MedicationRow>> watch(int patientId) => _query(patientId).watch();
  Future<List<MedicationRow>> all(int patientId) => _query(patientId).get();
}
