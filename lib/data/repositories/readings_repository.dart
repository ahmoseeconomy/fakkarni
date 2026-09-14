import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

/// قياسات السكر (D3.6) — محلي. SyncService ما بيقراهوش.
class ReadingsRepository {
  ReadingsRepository(this._db);

  final AppDatabase _db;

  /// اللي أجهزة القياس المنزلية بتقراه. برّه كده غلطة كتابة، مش حكم طبي.
  static const minMgDl = 20;
  static const maxMgDl = 600;

  static bool isReadable(int mgDl) => mgDl >= minMgDl && mgDl <= maxMgDl;

  Future<int> add({
    required int patientId,
    required int valueMgDl,
    required GlucoseContext context,
    required DateTime measuredAt,
  }) {
    if (!isReadable(valueMgDl)) {
      throw ArgumentError.value(valueMgDl, 'valueMgDl', 'برّه اللي الأجهزة بتقراه');
    }
    return _db.into(_db.readings).insert(ReadingsCompanion.insert(
          patientId: patientId,
          valueMgDl: valueMgDl,
          measuredAt: measuredAt,
          context: context,
        ));
  }

  /// الأحدث الأول.
  Stream<List<ReadingRow>> watchRecent(int patientId, {int limit = 60}) => (_db.select(_db.readings)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.desc(t.measuredAt), (t) => OrderingTerm.desc(t.id)])
        ..limit(limit))
      .watch();

  /// القياسات اللي **قبل** [reading] في نفس سياقه، الأحدث الأول — منها
  /// بيتحسب المعتاد ليه.
  static List<int> previousInContext(List<ReadingRow> newestFirst, ReadingRow reading) => [
        for (final r in newestFirst)
          if (r.context == reading.context &&
              (r.measuredAt.isBefore(reading.measuredAt) ||
                  (r.measuredAt == reading.measuredAt && r.id < reading.id)))
            r.valueMgDl,
      ];
}
