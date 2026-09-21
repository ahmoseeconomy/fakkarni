import 'package:drift/drift.dart';

import '../../domain/health/lab_range.dart';
import '../../core/format/arabic_time.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

/// سطر نتيجة زي ما إنسان أكّده.
class ConfirmedLabLine {
  const ConfirmedLabLine({required this.testName, required this.value, this.unit, this.range});

  final String testName;
  final double value;
  final String? unit;

  /// نطاق الورقة زي ما اتقرا منها — null لو الورقة ما طبعتش نطاق للسطر ده.
  final LabRange? range;
}

/// قيمة قديمة لنفس التحليل — للمقارنة بتاريخه هو.
class PastLabValue {
  const PastLabValue({required this.value, required this.unit, required this.at});

  final double value;
  final String? unit;
  final DateTime at;
}

/// نطاق الورقة من صف متخزّن، أو null لو التلاتة فاضيين.
LabRange? rangeOfRow(LabResultRow row) {
  final r = LabRange(low: row.refLow, high: row.refHigh, text: row.refText);
  return r.isEmpty ? null : r;
}

/// تقارير التحاليل (D3.6) — بتتكتب بعد «تمام» بس.
class LabResultsRepository {
  LabResultsRepository(this._db);

  final AppDatabase _db;

  /// «HbA1c» و«hba1c » نفس التحليل. المقارنة بالاسم المطبوع بعد تنضيف بسيط
  /// — مش بنخمّن إن «Glucose» هو «سكر صايم».
  static String normalize(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// صف سجل + سطر لكل نتيجة، في معاملة واحدة.
  ///
  /// [attachmentPath] صورة التقرير — مسار **نسبي** جوّه فولدر التطبيق.
  /// **بتفضل على الموبايل ده**: مفيش عمود ليها في السحابة (0012)، والمزامنة
  /// ما بتلمسش الاسم ده (`health_file_sync_guard_test`)، فالوعد اللي في
  /// «دائرة الرعاية» («مش هيشوفوا الصور») بيفضل صح.
  Future<int> saveReport({
    required int patientId,
    required DateTime happenedAt,
    required List<ConfirmedLabLine> lines,
    String? place,
    String? attachmentPath,
  }) =>
      _db.transaction(() async {
        // **الرقم عربي.** `$count` بيحقن رقم لاتيني جوّه جملة عربية،
        // والعنوان ده بيتخزّن ويتعرض على «يومك» وفي الملف الصحي وعلى
        // شاشة الابن — يعني «٦» بتبقى «6» في كل مكان. الإصلاح في
        // المصدر، والصفوف اللي اتكتبت قبل كده بتتظبط في
        // [launchHousekeeping].
        final title = labReportTitle([for (final l in lines) l.testName]);
        final recordId = await _db.into(_db.records).insert(RecordsCompanion.insert(
              patientId: patientId,
              kind: RecordKind.lab,
              title: title,
              happenedAt: happenedAt,
              place: Value(place),
              notes: Value([
                for (final l in lines) '${l.testName.trim()} ${_number(l.value)}${l.unit == null ? '' : ' ${l.unit}'}',
              ].join(' — ')),
              attachmentPath: Value(attachmentPath),
            ));
        for (final l in lines) {
          await _db.into(_db.labResults).insert(LabResultsCompanion.insert(
                recordId: recordId,
                testName: l.testName.trim(),
                value: l.value,
                unit: Value(l.unit),
                refLow: Value(l.range?.low),
                refHigh: Value(l.range?.high),
                refText: Value(l.range?.text),
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

/// عنوان تقرير التحاليل — **بأرقام عربية، دايماً**.
///
/// مستخرجة عشان تتختبر لوحدها: ده نص بيتخزّن في القاعدة وبيتعرض على
/// «يومك» وفي الملف الصحي وعلى شاشة الابن، ورقم لاتيني واحد جوّه بيفضل
/// في كل مكان فيهم. `${count}` كان بيعمل بالظبط كده.
String labReportTitle(List<String> testNames) => switch (testNames.length) {
      1 => 'تقرير تحليل — ${testNames.single}',
      2 => 'تقرير تحليل — نتيجتين',
      final n => 'تقرير تحليل — ${arabicNumber(n)} نتايج',
    };
