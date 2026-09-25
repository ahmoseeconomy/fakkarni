import 'package:drift/drift.dart';

import '../../domain/health/vitals.dart';
import '../db/app_database.dart';

/// القياسات الحيوية على الموبايل (v25). مفيش مسح هنا — القياس اللي اتسجّل
/// حصل، وده سجل؛ لو اتكتب غلط بيتسجّل الصح بعده.
class VitalsRepository {
  VitalsRepository(this._db);

  final AppDatabase _db;

  Future<int> add(int patientId, VitalEntry entry, {required DateTime measuredAt}) =>
      _db.into(_db.vitals).insert(VitalsCompanion.insert(
            patientId: patientId,
            kind: entry.kind.name,
            value: entry.value,
            value2: Value(entry.value2),
            pulse: Value(entry.pulse),
            measuredAt: measuredAt,
          ));

  static Vital? toVital(VitalRow r) {
    final kind = VitalKind.fromStored(r.kind);
    if (kind == null) return null;
    return Vital(kind: kind, value: r.value, value2: r.value2, pulse: r.pulse, measuredAt: r.measuredAt);
  }

  /// الأحدث الأول.
  Stream<List<Vital>> watch(int patientId) => (_db.select(_db.vitals)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.desc(t.measuredAt)]))
      .watch()
      .map((rows) => [for (final r in rows) ?toVital(r)]);

  Future<List<Vital>> all(int patientId) => watch(patientId).first;
}
