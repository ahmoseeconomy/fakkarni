// اختبار الترحيل بيتكتب **قبل** الترحيل نفسه، وبيتشاف أحمر الأول —
// الترحيل ده بيمشي على موبايل فيه بيانات حقيقية، ومفيش «نضيفه بعدين».
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';

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

    // الترحيل + تحقق drift إن الناتج مطابق لآخر نسخة
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

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

  test('v5 → v6: الصفوف عايشة، وكلها متوسّخة (synced_at_ms فاضية) عشان أول '
      'دفعة ترفع التاريخ كله', () async {
    final schema = await verifier.schemaAt(5);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot) VALUES (1, 'p-1', 'الحاج أحمد', 0)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_unknown) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 0)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final patient = (await db.select(db.patients).get()).single;
    final med = (await db.select(db.medications).get()).single;
    expect(patient.name, 'الحاج أحمد');
    expect(med.name, 'Concor 5mg');
    for (final (updated, synced) in [
      (patient.updatedAtMs, patient.syncedAtMs),
      (med.updatedAtMs, med.syncedAtMs),
    ]) {
      expect(updated, greaterThan(0));
      expect(synced, isNull, reason: 'أول دفعة لازم ترفع التاريخ كله');
    }
    await db.close();
  });

  test('v6 → v7: الروتين عايش بنفس uuid وupdated_at_ms، وجدول رمضان فاضي',
      () async {
    final schema = await verifier.schemaAt(6);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) "
        "VALUES (1, 'p-1', 'الحاج أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO day_routines (id, uuid, patient_id, wake_minutes, breakfast_minutes, "
        "lunch_minutes, dinner_minutes, sleep_minutes, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'r-1', 1, 420, 450, 870, 1200, 1410, 2000, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final routine = (await db.select(db.dayRoutines).get()).single;
    expect(routine.uuid, 'r-1');
    expect(routine.breakfastMinutes, 450);
    expect(routine.updatedAtMs, 2000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(await db.select(db.routineBackups).get(), isEmpty,
        reason: 'رمضان مقفول لكل مريض قديم');
    await db.close();
  });

  test('v7 → v8: المريض عايش باسمه وuuid بتاعه، والجنس والسن فاضيين (ما اتسألوش)', () async {
    final schema = await verifier.schemaAt(7);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'p-1', 'الحاج أحمد', 0, 1000, 1000)");
    raw.execute(
        "INSERT INTO day_routines (id, uuid, patient_id, wake_minutes, breakfast_minutes, "
        "lunch_minutes, dinner_minutes, sleep_minutes, updated_at_ms) "
        "VALUES (1, 'r-1', 1, 420, 450, 870, 1200, 1410, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final patient = (await db.select(db.patients).get()).single;
    expect(patient.uuid, 'p-1');
    expect(patient.name, 'الحاج أحمد');
    expect(patient.sex, isNull, reason: 'ما اتسألش — مش بنخمّن');
    expect(patient.age, isNull);
    expect(patient.updatedAtMs, 1000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(patient.syncedAtMs, 1000);
    expect((await db.select(db.dayRoutines).get()).single.breakfastMinutes, 450);
    await db.close();
  });

  test('v8 → v9: المريض والروتين عايشين، وجدول التفضيلات فاضي (يعني الافتراضي: النمط العادي والسلّم كامل)', () async {
    final schema = await verifier.schemaAt(8);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, sex, age, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'p-1', 'فاطمة', 0, 'f', 68, 1000, 1000)");
    raw.execute(
        "INSERT INTO day_routines (id, uuid, patient_id, wake_minutes, breakfast_minutes, "
        "lunch_minutes, dinner_minutes, sleep_minutes, updated_at_ms) "
        "VALUES (1, 'r-1', 1, 420, 450, 870, 1200, 1410, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final patient = (await db.select(db.patients).get()).single;
    expect(patient.uuid, 'p-1');
    expect(patient.age, 68);
    expect(patient.updatedAtMs, 1000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect((await db.select(db.dayRoutines).get()).single.breakfastMinutes, 450);
    expect(await db.select(db.devicePreferences).get(), isEmpty,
        reason: 'مفيش صف = الافتراضي — مش بنكتب اختيار ما حدش اختاره');
    await db.close();
  });

  test('v9 → v10: المريض والتفضيلات عايشين، وجدول الطوارئ فاضي — مفيش حقل اتملا لوحده', () async {
    final schema = await verifier.schemaAt(9);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, sex, age, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'p-1', 'أحمد', 0, 'm', 72, 1000, 1000)");
    raw.execute("INSERT INTO device_preferences (id, elder_mode, rung_first_on, rung_second_on) VALUES (1, 1, 0, 1)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final patient = (await db.select(db.patients).get()).single;
    expect(patient.uuid, 'p-1');
    expect(patient.updatedAtMs, 1000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    final prefs = (await db.select(db.devicePreferences).get()).single;
    expect(prefs.elderMode, isTrue);
    expect(prefs.rungFirstOn, isFalse);
    expect(await db.select(db.emergencyProfile).get(), isEmpty,
        reason: 'فصيلة دم ما حدش كتبها عمرها ما تتحط');
    await db.close();
  });

  test('v10 → v11: المريض وبيانات الطوارئ عايشين، والملف الصحي فاضي', () async {
    final schema = await verifier.schemaAt(10);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'p-1', 'أحمد', 0, 1000, 1000)");
    raw.execute(
        "INSERT INTO emergency_profile (uuid, updated_at_ms, patient_id, blood_type, contacts_json) "
        "VALUES ('e-1', 2000, 1, 'O+', '[]')");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    expect((await db.select(db.patients).get()).single.updatedAtMs, 1000);
    final emergency = (await db.select(db.emergencyProfile).get()).single;
    expect(emergency.bloodType, 'O+');
    expect(emergency.updatedAtMs, 2000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(await db.select(db.records).get(), isEmpty);
    await db.close();
  });

  test('v11 → v12: السجلات عايشة، وجدولين السكر ونتايج التحاليل فاضيين', () async {
    final schema = await verifier.schemaAt(11);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (uuid, updated_at_ms, id, patient_id, kind, title, happened_at) "
        "VALUES ('r-1', 3000, 7, 1, 'lab', 'HbA1c', 1788235200)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final record = (await db.select(db.records).get()).single;
    expect(record.title, 'HbA1c');
    expect(record.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(await db.select(db.readings).get(), isEmpty);
    expect(await db.select(db.labResults).get(), isEmpty, reason: 'مفيش نتيجة اتخمّنت من سجل قديم');
    await db.close();
  });

  test('v12 → v13: السجلات عايشة بقيمها، والمرحلة وتذكير الصيام فاضيين (مش دورات)', () async {
    final schema = await verifier.schemaAt(12);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (uuid, updated_at_ms, id, patient_id, kind, title, happened_at, attachment_path) "
        "VALUES ('r-1', 3000, 7, 1, 'lab', 'HbA1c', 1788235200, 'attachments/x.jpg')");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final record = (await db.select(db.records).get()).single;
    expect(record.title, 'HbA1c');
    expect(record.attachmentPath, 'attachments/x.jpg');
    expect(record.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(record.checkupStage, isNull, reason: 'تحليل قديم مش متابعة');
    expect(record.fastingReminderAt, isNull);
    await db.close();
  });

  test('v13 → v14: المتابعة عايشة بمرحلتها، وأسئلة الزيارة فاضية', () async {
    final schema = await verifier.schemaAt(13);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (uuid, updated_at_ms, id, patient_id, kind, title, happened_at, checkup_stage, fasting_reminder_at) "
        "VALUES ('r-1', 3000, 7, 1, 'lab', 'CBC', 1788235200, 3, 1788300000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final record = (await db.select(db.records).get()).single;
    expect(record.checkupStage, 3);
    expect(record.fastingReminderAt, isNotNull, reason: 'التذكير المتجدول ما يضيعش أثره');
    expect(record.updatedAtMs, 3000);
    expect(await db.select(db.visitQuestions).get(), isEmpty);
    await db.close();
  });

  test('v14 → v15: الجرعات عايشة بتوقيتها، وسريانها null (سارية من الأول)', () async {
    final schema = await verifier.schemaAt(14);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_unknown, updated_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 0, 1000)");
    raw.execute(
        "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, anchor, offset_minutes, "
        "repeat, start_date, duration_days, updated_at_ms, synced_at_ms) "
        "VALUES (10, 's-10', 1, 'anchor', 'breakfast', -30, 'daily', '2026-08-31', NULL, 2000, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final row = (await db.select(db.doseSchedules).get()).single;
    expect(row.anchor, DayAnchor.breakfast);
    expect(row.offsetMinutes, -30);
    expect(row.activeFrom, isNull, reason: 'صف قديم ما بنخترعش له وقت سريان');
    expect(row.updatedAtMs, 2000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(row.syncedAtMs, 2000);
    await db.close();
  });

  test('كل النسخ المتسجّلة بتترحّل لآخر نسخة وتتطابق', () async {
    for (final version in GeneratedHelper.versions) {
      if (version == 15) continue;
      final schema = await verifier.schemaAt(version);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 28);
      await db.close();
    }
  });

  test('v15 → v16: الدوا وجرعاته عايشين، والإيقاف الناعم فاضي (مفيش حاجة موقوفة ولا متشالة)',
      () async {
    final schema = await verifier.schemaAt(15);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_unknown, updated_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 0, 1000)");
    raw.execute(
        "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, anchor, offset_minutes, "
        "repeat, start_date, duration_days, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'ds-1', 1, 'anchor', 'breakfast', -30, 'daily', '2026-08-31', NULL, 2000, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final med = (await db.select(db.medications).get()).single;
    expect(med.name, 'Concor 5mg');
    expect(med.removedAt, isNull, reason: 'دوا قديم مش متشال — وما بنخترعش له وقت');
    expect(med.stoppedAt, isNull);
    expect(med.updatedAtMs, 1000, reason: 'الترحيل ما بيوسّخش صف نضيف');

    final schedule = (await db.select(db.doseSchedules).get()).single;
    expect(schedule.anchor, DayAnchor.breakfast);
    expect(schedule.stoppedAt, isNull, reason: 'جرعة قديمة شغّالة');
    expect(schedule.syncedAtMs, 2000);
    await db.close();
  });

  test('v16 → v17: المتابعة عايشة بمرحلتها، والمواعيد الأربعة فاضية — مفيش ميعاد مخترع',
      () async {
    final schema = await verifier.schemaAt(16);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (id, uuid, patient_id, kind, title, happened_at, checkup_stage, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'r-1', 1, 'lab', 'صورة دم كاملة', 1789000000, 2, 3000, 3000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final record = (await db.select(db.records).get()).single;
    expect(record.title, 'صورة دم كاملة');
    expect(record.checkupStage, 2, reason: 'المرحلة زي ما هي');
    // **مفيش تخمين**: متابعة قديمة ما قالتش مواعيدها، فبتفضل بتسأل
    expect(record.checkupStageSince, isNull);
    expect(record.labBookingAt, isNull);
    expect(record.resultReadyAt, isNull);
    expect(record.doctorVisitAt, isNull);
    expect(record.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(record.syncedAtMs, 3000);
    await db.close();
  });

  test('v17 → v18: نتايج التحاليل عايشة بأرقامها، ونطاق الورقة فاضي — مفيش نطاق مخترع',
      () async {
    final schema = await verifier.schemaAt(17);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (id, uuid, patient_id, kind, title, happened_at, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'r-1', 1, 'lab', 'تقرير تحليل — نتيجتين', 1789000000, 3000, 3000)");
    raw.execute(
        "INSERT INTO lab_results (id, uuid, record_id, test_name, value, unit, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'l-1', 1, 'HbA1c', 7.6, '%', 4000, 4000)");
    raw.execute(
        "INSERT INTO lab_results (id, uuid, record_id, test_name, value, unit, updated_at_ms, synced_at_ms) "
        "VALUES (2, 'l-2', 1, 'WBC', 12.4, '10^3/uL', 4000, NULL)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final rows = await (db.select(db.labResults)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(rows.length, 2);
    expect((rows[0].testName, rows[0].value, rows[0].unit), ('HbA1c', 7.6, '%'));
    expect((rows[1].testName, rows[1].value, rows[1].unit), ('WBC', 12.4, '10^3/uL'));

    // **دي الحتة المهمة**: سطر اتقرا قبل ما يبقى فيه نطاق أصلاً ما بياخدش
    // نطاق دلوقتي. null معناه «الورقة ما طبعتش»، ولو ملّيناه من أي جدول
    // عندنا يبقى إحنا اللي بنحكم على رقمه.
    for (final r in rows) {
      expect(r.refLow, isNull);
      expect(r.refHigh, isNull);
      expect(r.refText, isNull);
    }
    expect(rows[0].updatedAtMs, 4000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    expect(rows[0].syncedAtMs, 4000);
    expect(rows[1].syncedAtMs, isNull, reason: 'اللي كان متوسّخ يفضل متوسّخ');
    await db.close();
  });

  test('v18 → v19: المتابعة القديمة عايشة، ونوعها تحليل — ومالهاش مصدر مخترع', () async {
    final schema = await verifier.schemaAt(18);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO records (id, uuid, patient_id, kind, title, happened_at, checkup_stage, "
        "checkup_stage_since, lab_booking_at, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'r-1', 1, 'lab', 'صورة دم كاملة', 1789000000, 2, 1789000000, 1789500000, 3000, 3000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final record = (await db.select(db.records).get()).single;
    expect(record.title, 'صورة دم كاملة');
    expect(record.checkupStage, 2);
    expect(record.labBookingAt, isNotNull, reason: 'ميعادها زي ما هو');

    // **الحتة المهمة**: متابعة اتبدت قبل ما يبقى فيه نوع تاني أصلاً هي
    // متابعة تحليل — والعمود بيفضل null، والقراية هي اللي بتقول كده.
    expect(record.followKind, isNull);
    expect(CheckupService.kindOf(record), FollowKind.lab);
    expect(CheckupService.stageOf(record), CheckupStage.labBooking);
    // ومالهاش مصدر: اتكتبت بالإيد، وما بنخترعلهاش ورقة جت منها.
    expect(record.followSourceId, isNull);
    expect(record.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    await db.close();
  });
  test('v19 → v20: الأدوية عايشة، والمادة الفعّالة فاضية — مش مخترعة', () async {
    final schema = await verifier.schemaAt(19);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_label, created_at, "
        "updated_at_ms, synced_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 'قرص واحد', 1789000000, 3000, 3000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final med = (await db.select(db.medications).get()).single;
    expect(med.name, 'Concor 5mg');
    expect(med.amountLabel, 'قرص واحد');
    // **دوا اتضاف قبل ما نقرا علب مالوش مادة فعّالة متسجّلة** — وما
    // بنخترعلهوش واحدة من الاسم. null هنا معناه «ماحدش قالنا»، وفحص
    // التكرار بيعدّي عليه بدل ما يدّعي معرفة.
    expect(med.activeIngredient, isNull);
    expect(med.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    await db.close();
  });

  test('v24 → v25: جدول القياسات موجود وفاضي، والسكر زي ما هو', () async {
    final schema = await verifier.schemaAt(24);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO readings (id, uuid, patient_id, value_mg_dl, measured_at, context, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'r-1', 1, 118, 1789000000, 'fasting', 2000, 2000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    expect(await db.select(db.vitals).get(), isEmpty, reason: 'مفيش قياس اتخترع');
    final reading = (await db.select(db.readings).get()).single;
    expect(reading.valueMgDl, 118);
    expect(reading.updatedAtMs, 2000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    await db.close();
  });

  test('v25 → v26: جدول المخزون فاضي — مفيش رقم اتخترع لدوا قديم — والصيدلية فاضية', () async {
    final schema = await verifier.schemaAt(25);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_label, amount_unknown, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 'قرص واحد', 0, 3000, 3000)");
    raw.execute("INSERT INTO device_preferences (id, elder_mode) VALUES (1, 1)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    expect(await db.select(db.medicationStock).get(), isEmpty,
        reason: 'المخزون اختياري — عمره ما بيتحسب من الجرعات الفاضلة');
    final prefs = (await db.select(db.devicePreferences).get()).single;
    expect((prefs.elderMode, prefs.pharmacyName, prefs.pharmacyWhatsapp), (true, null, null));
    expect((await db.select(db.medications).get()).single.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    await db.close();
  });

  test('v26 → v27: صورة الدوا عمود فاضي — ولا صورة اتخترعت لدوا قديم', () async {
    final schema = await verifier.schemaAt(26);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_label, amount_unknown, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 'قرص واحد', 0, 3000, 3000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final med = (await db.select(db.medications).get()).single;
    expect(med.photoPath, isNull);
    expect(med.name, 'Concor 5mg');
    expect(med.updatedAtMs, 3000, reason: 'الترحيل ما بيوسّخش صف نضيف');
    await db.close();
  });

  test('v27 → v28: «لسه ماتشترتش» فاضي لكل دوا قديم — يعني اتشرى، وما بيغيّرش حاجة', () async {
    final schema = await verifier.schemaAt(27);
    final raw = schema.rawDatabase;
    raw.execute(
        "INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أحمد', 0, 1000)");
    raw.execute(
        "INSERT INTO medications (id, uuid, patient_id, name, amount_label, amount_unknown, photo_path, updated_at_ms, synced_at_ms) "
        "VALUES (1, 'm-1', 1, 'Concor 5mg', 'قرص واحد', 0, 'med-photos/x.jpg', 3000, 3000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 28);

    final med = (await db.select(db.medications).get()).single;
    expect(med.notBoughtAt, isNull);
    expect(med.photoPath, 'med-photos/x.jpg', reason: 'عمود v27 فضل زي ما هو');
    expect(med.updatedAtMs, 3000);
    await db.close();
  });
}
