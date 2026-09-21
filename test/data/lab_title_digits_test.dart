import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/bootstrap.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/health/lab_range.dart';

/// **رقم لاتيني جوّه جملة عربية متخزّنة.**
///
/// عنوان تقرير التحليل كان بيتكتب `'تقرير تحليل — $count نتايج'` برقم
/// لاتيني، فالعنوان **اتخزّن** كده وبيتعرض كده في كل مكان بيقراه —
/// «يومك» والملف الصحي وشاشة الابن. الإصلاح في المصدر، والصفوف القديمة
/// بتتظبط عند الفتح.
void main() {
  late AppDatabase db;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    patientId = await RoutineRepository(db).ensurePatient();
  });
  tearDown(() => db.close());

  Future<String> titleFor(int count) async {
    final id = await LabResultsRepository(db).saveReport(
      patientId: patientId,
      happenedAt: DateTime(2026, 9, 1),
      lines: [
        for (var i = 0; i < count; i++)
          ConfirmedLabLine(testName: 'Test$i', value: 1 + i.toDouble(), unit: 'g', range: const LabRange()),
      ],
    );
    final row = await (db.select(db.records)..where((t) => t.id.equals(id))).getSingle();
    return row.title;
  }

  test('العنوان الجديد برقم عربي', () async {
    expect(await titleFor(6), 'تقرير تحليل — ٦ نتايج');
    expect(await titleFor(12), 'تقرير تحليل — ١٢ نتايج');
  });

  test('والواحد والاتنين بكلامهم زي ما هم', () async {
    expect(await titleFor(1), 'تقرير تحليل — Test0');
    expect(await titleFor(2), 'تقرير تحليل — نتيجتين');
  });

  group('الصفوف اللي اتكتبت قبل الإصلاح', () {
    Future<int> insertTitle(String title) => db.into(db.records).insert(RecordsCompanion.insert(
          patientId: patientId,
          kind: RecordKind.lab,
          title: title,
          happenedAt: DateTime(2026, 9, 1),
        ));

    Future<String> read(int id) async =>
        (await (db.select(db.records)..where((t) => t.id.equals(id))).getSingle()).title;

    test('بتتظبط عند الفتح', () async {
      final id = await insertTitle('تقرير تحليل — 6 نتايج');
      await normaliseLabReportTitles(db);
      expect(await read(id), 'تقرير تحليل — ٦ نتايج');
    });

    test('**واللي كتبه إنسان ما بيتلمسش** — الأرقام اللي جواه بتاعته هو', () async {
      final ids = <int, String>{};
      for (final title in [
        'تحليل HbA1c',
        'أشعة على الركبة 2',
        'تقرير تحليل — نتيجتين',
        'روشتة د. طارق',
      ]) {
        ids[await insertTitle(title)] = title;
      }
      await normaliseLabReportTitles(db);
      for (final MapEntry(key: id, value: title) in ids.entries) {
        expect(await read(id), title, reason: '«$title» اتغيّر');
      }
    });

    test('وبتتعاد من غير أثر', () async {
      final id = await insertTitle('تقرير تحليل — 6 نتايج');
      await normaliseLabReportTitles(db);
      final once = await read(id);
      await normaliseLabReportTitles(db);
      expect(await read(id), once);
    });
  });

  test('المصدر ما بيحقنش رقم خام في جملة عربية', () {
    // الحارس على المصدر نفسه: `$count` جوّه نص عربي هو اللي عمل العطل.
    final source = File('lib/data/repositories/lab_results_repository.dart').readAsStringSync();
    expect(source.contains(r"'تقرير تحليل — $count نتايج'"), isFalse);
    expect(source, contains('arabicNumber(count)'));
  });
}
