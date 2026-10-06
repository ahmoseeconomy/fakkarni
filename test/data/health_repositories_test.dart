import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';

void main() {
  late AppDatabase db;
  late int patientId;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    patientId = await PatientRepository(db).ensurePatient();
    tmp = await Directory.systemTemp.createTemp('fakkarni_attach');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  group('قياسات السكر', () {
    test('برّه ٢٠–٦٠٠ بيترفض (غلطة كتابة)، وجوّه بيتحفظ', () async {
      final repo = ReadingsRepository(db);
      expect(
        () => repo.add(patientId: patientId, valueMgDl: 1520, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 9, 1)),
        throwsArgumentError,
      );
      await repo.add(patientId: patientId, valueMgDl: 152, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 9, 1));
      final rows = await repo.watchRecent(patientId).first;
      expect(rows.single.valueMgDl, 152);
    });

    test('«اللي قبله في نفس السياق» بس — بعد الأكل ما بيدخلش في المعتاد بتاع الصايم', () async {
      final repo = ReadingsRepository(db);
      for (final (v, c, d) in [
        (110, GlucoseContext.fasting, 1),
        (180, GlucoseContext.afterMeal, 2),
        (120, GlucoseContext.fasting, 3),
        (150, GlucoseContext.fasting, 4),
      ]) {
        await repo.add(patientId: patientId, valueMgDl: v, context: c, measuredAt: DateTime(2026, 9, d));
      }
      final rows = await repo.watchRecent(patientId).first;
      expect(ReadingsRepository.previousInContext(rows, rows.first), [120, 110]);
    });
  });

  group('نتايج التحاليل', () {
    test('التقرير بيتحفظ صف lab + سطر لكل نتيجة، والتاريخ بيرجع بنفس الاسم بعد تنضيف', () async {
      final repo = LabResultsRepository(db);
      await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 3, 1),
        lines: [ConfirmedLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
      );
      await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 6, 1),
        place: 'معمل البرج',
        lines: [
          ConfirmedLabLine(testName: 'hba1c ', value: 7.4, unit: '%'),
          ConfirmedLabLine(testName: 'Creatinine', value: 1.2, unit: 'mg/dL'),
        ],
      );
      final history = await repo.historyFor(patientId, 'HbA1c');
      expect([for (final h in history) h.value], [7.4, 7.1]);
      final records = await RecordsRepository(db).all(patientId);
      expect(records.first.kind, RecordKind.lab);
      expect(records.first.title, 'تقرير تحليل — نتيجتين');
      expect(records.first.notes, 'hba1c 7.4 % — Creatinine 1.2 mg/dL');
    });

    test('نتيجة نصية (المرحلة ٥): بتتحفظ بالحرف برقم فاضي، وبتتعرض في notes زي ما هي', () async {
      final repo = LabResultsRepository(db);
      await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 9, 12),
        lines: [
          ConfirmedLabLine(testName: 'Pus Cells', valueText: 'Negative'),
          ConfirmedLabLine(testName: 'HbA1c', value: 7.6, unit: '%'),
        ],
      );
      final rows = await db.select(db.labResults).get();
      final text = rows.firstWhere((r) => r.testName == 'Pus Cells');
      expect((text.value, text.valueText), (null, 'Negative'));
      final records = await RecordsRepository(db).all(patientId);
      expect(records.first.notes, 'Pus Cells Negative — HbA1c 7.6 %');
    });

    test('نتيجة واحدة بالظبط: رقم ونص مع بعض — أو ولا واحد — ArgumentError', () {
      expect(
        () => ConfirmedLabLine(testName: 'X', value: 1, valueText: 'Negative'),
        throwsArgumentError,
      );
      expect(() => ConfirmedLabLine(testName: 'X'), throwsArgumentError);
    });

    test('السطر النصي برّه «المعتاد» وبرّه قايمة «كلّمني» — زي refText: بيتعرض وعمره ما بيتقارن', () async {
      final repo = LabResultsRepository(db);
      await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 3, 1),
        lines: [ConfirmedLabLine(testName: 'Pus Cells', valueText: 'Negative')],
      );
      await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 6, 1),
        lines: [ConfirmedLabLine(testName: 'Pus Cells', value: 3, unit: '/HPF')],
      );
      // المعتاد بيشوف الرقم وبس — «Negative» مش رقم يتحسب منه معتاد
      final history = await repo.historyFor(patientId, 'Pus Cells');
      expect([for (final h in history) h.value], [3.0]);
      // و«كلّمني» بيرد برقم وتاريخ — السطر النصي مش في قايمته
      final all = await repo.allNewestFirst(patientId);
      expect([for (final v in all) v.value], [3.0]);
    });

    test('تقرير ممسوح (ناعم) ما بيدخلش في المعتاد', () async {
      final repo = LabResultsRepository(db);
      final id = await repo.saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 3, 1),
        lines: [ConfirmedLabLine(testName: 'HbA1c', value: 9.9)],
      );
      await RecordsRepository(db).delete(id);
      expect(await repo.historyFor(patientId, 'HbA1c'), isEmpty);
    });
  });

  group('المرفقات', () {
    test('الصورة بتتمسح مع السجل في لحظته — مش بعد ٣٠ يوم', () async {
      final store = DirectoryAttachmentStore(root: tmp);
      final path = await store.save(Uint8List.fromList([1, 2, 3]));
      expect(path, startsWith('attachments/'));
      expect(await store.fileFor(path), isNotNull);

      final id = await LabResultsRepository(db).saveReport(
        patientId: patientId,
        happenedAt: DateTime(2026, 6, 1),
        attachmentPath: path,
        lines: [ConfirmedLabLine(testName: 'HbA1c', value: 7.4)],
      );
      final records = RecordsRepository(db);
      await records.delete(id, now: DateTime(2026, 8, 1), attachments: store);

      // تقرير معمل ممكن تكون دي النسخة الوحيدة منه — فالتأكيد بيقول كده
      // بالاسم قبل الدوسة، واللي بيحصل بعدها إنها تروح فعلاً.
      expect(await store.fileFor(path), isNull);
      expect(await db.select(db.labResults).get(), isEmpty, reason: 'النتايج راحت مع السجل');
    });
  });
}
