import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

/// سطر نتيجة زي ما إنسان أكّده.
class ConfirmedLabLine {
  const ConfirmedLabLine({required this.testName, required this.value, this.unit});

  final String testName;
  final double value;
  final String? unit;
}

/// قيمة قديمة لنفس التحليل — للمقارنة بتاريخه هو.
class PastLabValue {
  const PastLabValue({required this.value, required this.unit, required this.at});

  final double value;
  final String? unit;
  final DateTime at;
}

/// تقارير التحاليل (D3.6) — بتتكتب بعد «تمام» بس.
class LabResultsRepository {
  LabResultsRepository(this._db);

  final AppDatabase _db;

  /// «HbA1c» و«hba1c » نفس التحليل. المقارنة بالاسم المطبوع بعد تنضيف بسيط
  /// — مش بنخمّن إن «Glucose» هو «سكر صايم».
  static String normalize(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// صف سجل + سطر لكل نتيجة، في معاملة واحدة.
  Future<int> saveReport({
    required int patientId,
    required DateTime happenedAt,
    required List<ConfirmedLabLine> lines,
    String? place,
    String? attachmentPath,
  }) =>
      _db.transaction(() async {
        final count = lines.length;
        final title = switch (count) {
          1 => 'تقرير تحليل — ${lines.single.testName}',
          2 => 'تقرير تحليل — نتيجتين',
          _ => 'تقرير تحليل — $count نتايج',
        };
        final recordId = await _db.into(_db.records).insert(RecordsCompanion.insert(
              patientId: patientId,
              kind: RecordKind.lab,
              title: title,
              happenedAt: happenedAt,
              place: Value(place),
              notes: Value([
                for (final l in lines) '${l.testName.trim()} ${_number(l.value)}${l.unit == null ? '' : ' ${l.unit}'}',
              ].join(' · ')),
              attachmentPath: Value(attachmentPath),
            ));
        for (final l in lines) {
          await _db.into(_db.labResults).insert(LabResultsCompanion.insert(
                recordId: recordId,
                testName: l.testName.trim(),
                value: l.value,
                unit: Value(l.unit),
              ));
        }
        return recordId;
      });

  /// قيم نفس التحليل في تقاريره اللي فاتت، الأحدث الأول. التقارير الممسوحة
  /// (مسح ناعم) ما بتدخلش في «المعتاد».
  Future<List<PastLabValue>> historyFor(int patientId, String testName) async {
    final key = normalize(testName);
    final query = _db.select(_db.labResults).join([
      innerJoin(_db.records, _db.records.id.equalsExp(_db.labResults.recordId)),
    ])
      ..where(_db.records.patientId.equals(patientId) & _db.records.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(_db.records.happenedAt), OrderingTerm.desc(_db.labResults.id)]);
    return [
      for (final row in await query.get())
        if (normalize(row.readTable(_db.labResults).testName) == key)
          PastLabValue(
            value: row.readTable(_db.labResults).value,
            unit: row.readTable(_db.labResults).unit,
            at: row.readTable(_db.records).happenedAt,
          ),
    ];
  }

  static String _number(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
