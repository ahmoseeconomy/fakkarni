// اختبار الترحيل بيتكتب **قبل** الترحيل نفسه، وبيتشاف أحمر الأول —
// الترحيل ده بيمشي على موبايل فيه بيانات حقيقية، ومفيش «نضيفه بعدين».
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';

import '../drift/generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v4 → v5: الصفوف عايشة بقيمها، وكل صف خد uuid فريد، والمفاتيح سليمة',
      () async {
    final schema = await verifier.schemaAt(4);

    // بيانات واقعية بشكل نسخة ٤ بالظبط — مريض وروتين ودواءين وجدول وحدث
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, name, notification_slot) VALUES (1, 'الحاج أحمد', 0)");
    raw.execute(
        'INSERT INTO day_routines (id, patient_id, wake_minutes, breakfast_minutes, '
        'lunch_minutes, dinner_minutes, sleep_minutes) VALUES (1, 1, 420, 450, 870, 1200, 1410)');
    raw.execute(
        "INSERT INTO medications (id, patient_id, name, amount_label, amount_unknown) "
        "VALUES (1, 1, 'Concor 5mg', 'قرص واحد', 0)");
    raw.execute(
        "INSERT INTO medications (id, patient_id, name, amount_label, amount_unknown) "
        "VALUES (2, 1, 'Telfast 180 mg', NULL, 1)");
    raw.execute(
        "INSERT INTO dose_schedules (id, medication_id, timing_kind, anchor, offset_minutes, "
        "repeat, start_date, duration_days) VALUES (10, 1, 'anchor', 'breakfast', -30, 'daily', '2026-08-31', NULL)");
    raw.execute(
        "INSERT INTO dose_events (id, dose_schedule_id, routine_day, scheduled_at, state, acted_at) "
        "VALUES (100, 10, '2026-08-31', 1788235200, 'taken', 1788235500)");

    // الترحيل + تحقق drift إن الناتج مطابق لمخطط نسخة ٥
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);

    // القيم الأصلية زي ما هي
    final patient = await (db.select(db.patients)..where((t) => t.id.equals(1))).getSingle();
    expect(patient.name, 'الحاج أحمد');

    final meds = await (db.select(db.medications)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(meds.length, 2);
    expect(meds[0].name, 'Concor 5mg');
    expect(meds[0].amountLabel, 'قرص واحد');
    expect(meds[1].name, 'Telfast 180 mg');
    expect(meds[1].amountUnknown, isTrue);

    final schedule = (await db.select(db.doseSchedules).get()).single;
    expect(schedule.id, 10);
    expect(schedule.offsetMinutes, -30);

    final event = (await db.select(db.doseEvents).get()).single;
    expect(event.doseScheduleId, 10);

    // كل صف خد uuid مش فاضي، وكلهم مختلفين
    final uuids = <String>[
      patient.uuid,
      (await db.select(db.dayRoutines).get()).single.uuid,
      meds[0].uuid,
      meds[1].uuid,
      schedule.uuid,
      event.uuid,
    ];
    for (final id in uuids) {
      expect(id, isNotEmpty);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(id),
          isTrue, reason: 'uuid v4 شكلها معروف: $id');
    }
    expect(uuids.toSet().length, uuids.length, reason: 'مفيش uuid متكرر');

    // المفاتيح الرقمية لسه هي العلاقات: الدوا لسه لاقي مريضه
    expect(meds[0].patientId, patient.id);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

    await db.close();
  });

  test('كل النسخ المتسجّلة بتترحّل لآخر نسخة وتتطابق', () async {
    for (final version in GeneratedHelper.versions) {
      if (version == 5) continue;
      final schema = await verifier.schemaAt(version);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);
      await db.close();
    }
  });
}
