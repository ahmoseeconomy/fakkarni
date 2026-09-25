import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/mappers.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import '../support/seeded_clock.dart';

/// قاعدة بيانات نسخة ٢ زي ما drift كان بيعملها بالظبط — من `sqlite_master`
/// قبل ما نوع التوقيت يتضاف. لو حد عدّل الجداول القديمة هنا الاختبار بيبقى
/// بيختبر حاجة تانية، فسيبها زي ما هي.
const _v2Schema = [
  'CREATE TABLE "patients" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"name" TEXT NOT NULL, "notification_slot" INTEGER NOT NULL DEFAULT 0, '
      '"created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), '
      'UNIQUE ("notification_slot"))',
  'CREATE TABLE "day_routines" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"patient_id" INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE, '
      '"wake_minutes" INTEGER NOT NULL, "breakfast_minutes" INTEGER NOT NULL, '
      '"lunch_minutes" INTEGER NOT NULL, "dinner_minutes" INTEGER NOT NULL, '
      '"sleep_minutes" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)), '
      'UNIQUE ("patient_id"))',
  'CREATE TABLE "medications" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"patient_id" INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE, '
      '"name" TEXT NOT NULL, "amount_label" TEXT NULL, "notes" TEXT NULL, '
      '"stopped_at" INTEGER NULL, '
      '"created_at" INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)))',
  'CREATE TABLE "dose_schedules" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"medication_id" INTEGER NOT NULL REFERENCES medications (id) ON DELETE CASCADE, '
      '"anchor" TEXT NOT NULL, "offset_minutes" INTEGER NOT NULL DEFAULT 0, '
      '"repeat" TEXT NOT NULL, "start_date" TEXT NOT NULL, "duration_days" INTEGER NULL)',
  'CREATE TABLE "dose_events" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"dose_schedule_id" INTEGER NOT NULL REFERENCES dose_schedules (id) ON DELETE CASCADE, '
      '"routine_day" TEXT NOT NULL, "scheduled_at" INTEGER NOT NULL, '
      '"state" TEXT NOT NULL, "acted_at" INTEGER NULL, '
      'UNIQUE ("dose_schedule_id", "routine_day"))',
];

/// بيانات مريض حقيقي على نسخة ٢: دواءين بمرساتين مختلفتين، وجرعة اتاخدت.
const _v2Rows = [
  "INSERT INTO patients (id, name, notification_slot) VALUES (1, 'الحاج أحمد', 0)",
  'INSERT INTO day_routines (patient_id, wake_minutes, breakfast_minutes, '
      'lunch_minutes, dinner_minutes, sleep_minutes) VALUES (1, 420, 450, 870, 1200, 1410)',
  "INSERT INTO medications (id, patient_id, name, amount_label) VALUES (1, 1, 'Concor 5mg', 'قرص واحد')",
  "INSERT INTO medications (id, patient_id, name, amount_label) VALUES (2, 1, 'LINEX', NULL)",
  "INSERT INTO dose_schedules (id, medication_id, anchor, offset_minutes, repeat, start_date, duration_days) "
      "VALUES (10, 1, 'breakfast', -30, 'daily', '2026-08-31', NULL)",
  "INSERT INTO dose_schedules (id, medication_id, anchor, offset_minutes, repeat, start_date, duration_days) "
      "VALUES (11, 2, 'dinner', 30, 'daily', '2026-08-31', 7)",
  "INSERT INTO dose_events (dose_schedule_id, routine_day, scheduled_at, state, acted_at) "
      "VALUES (10, '2026-08-31', 1788235200, 'taken', 1788235500)",
];

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fakkarni_migration');
    file = File(p.join(dir.path, 'v2.db'));
  });

  tearDown(() => dir.delete(recursive: true));

  /// بيفتح الملف كنسخة ٢ مليانة بيانات — والترحيل لـ٣ بيحصل وdrift بيفتحها.
  AppDatabase openLegacy() => AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            if (raw.userVersion != 0) return; // اتعمل خلاص
            for (final statement in [..._v2Schema, ..._v2Rows]) {
              raw.execute(statement);
            }
            raw.userVersion = 2;
          },
        ),
      );

  test('نسخة ٢ بجرعات مراسي → كل جرعة عاشت بمرساتها وإزاحتها', () async {
    final db = openLegacy();
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 28);

    final loaded = await MedicationRepository(db, clock: seededLongAgo).activeSchedules(1);
    expect(loaded.length, 2);

    final concor = loaded.singleWhere((s) => s.medicationName == 'Concor 5mg');
    expect(concor.id, '10');
    expect(concor.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    expect(concor.amountLabel, 'قرص واحد');
    expect(concor.durationDays, isNull, reason: 'المدة المفتوحة فضلت مفتوحة');

    final linex = loaded.singleWhere((s) => s.medicationName == 'LINEX');
    expect(linex.id, '11');
    expect(linex.timing, const AnchorTiming(DayAnchor.dinner, 30));
    expect(linex.durationDays, 7);
    expect(linex.startDate, DateTime(2026, 8, 31));

    // v4: «الجرعة مش معروفة» — الصفوف القديمة false، مش null ومش true
    final rows = await db.select(db.medications).get();
    expect(rows.every((m) => m.amountUnknown == false), isTrue);

    // v5: كل صف قديم خد uuid — حتى من قاعدة عمرها من نسخة ٢
    final uuids = {for (final m in rows) m.uuid};
    expect(uuids.length, rows.length);
    expect(uuids.every((u) => u.isNotEmpty), isTrue);

    // v8: الجنس والسن موجودين وفاضيين — قاعدة من نسخة ٢ عمرها ما اتسألت
    final patientRow = (await db.select(db.patients).get()).single;
    expect(patientRow.sex, isNull);
    expect(patientRow.age, isNull);

    // v7: جدول رمضان موجود وفاضي — رمضان مقفول لكل قاعدة قديمة
    expect(await db.select(db.routineBackups).get(), isEmpty);
    expect(await RoutineRepository(db).ramadanTimes(1), isNull);

    // v9: التفضيلات موجودة وفاضية — النمط العادي والسلّم كامل
    expect(await db.select(db.devicePreferences).get(), isEmpty);

    // v10: جدول الطوارئ موجود وفاضي — ولا فصيلة دم ولا حساسية اتخمّنت
    expect(await db.select(db.emergencyProfile).get(), isEmpty);

    // v11: الملف الصحي موجود وفاضي
    expect(await db.select(db.records).get(), isEmpty);

    // v12: السكر ونتايج التحاليل موجودين وفاضيين
    expect(await db.select(db.readings).get(), isEmpty);
    expect(await db.select(db.labResults).get(), isEmpty);

    // v14: أسئلة الزيارة موجودة وفاضية
    expect(await db.select(db.visitQuestions).get(), isEmpty);

    // v15: الجرعات القديمة سارية من الأول — ما اتخترعلهاش وقت سريان
    final scheduleRows = await db.select(db.doseSchedules).get();
    expect(scheduleRows.length, 2);
    expect(scheduleRows.every((s) => s.activeFrom == null), isTrue);

    // v16: مفيش حاجة اتشالت ولا اتوقفت لوحدها في الترحيل
    expect(scheduleRows.every((s) => s.stoppedAt == null), isTrue);
    expect(
      (await db.select(db.medications).get()).every((m) => m.removedAt == null),
      isTrue,
      reason: 'الترحيل ما بيشيلش دوا',
    );

    // v17: الأعمدة الجديدة موجودة وفاضية — ولا ميعاد اتخترع لصف قديم
    final columns = await db
        .customSelect("SELECT name FROM pragma_table_info('records')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(
      columns,
      containsAll(['checkup_stage_since', 'lab_booking_at', 'result_ready_at', 'doctor_visit_at']),
    );

    // v18: أعمدة نطاق الورقة موجودة على `lab_results` — والجدول نفسه فاضي،
    // فمفيش سطر قديم اتحطّ له نطاق من عندنا.
    final columnsOf = columns;
    final labColumns = await db
        .customSelect("SELECT name FROM pragma_table_info('lab_results')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(labColumns, containsAll(['ref_low', 'ref_high', 'ref_text']));
    expect(await db.select(db.labResults).get(), isEmpty);

    // v19: نوع المتابعة ومصدرها — موجودين وفاضيين. مفيش سجل قديم اتقال
    // عليه إنه متابعة، ومفيش متابعة اتقال عليها إنها جت من ورقة.
    expect(columnsOf, containsAll(['follow_kind', 'follow_source_id']));

    // v20: المادة الفعّالة موجودة كعمود وفاضية في كل دوا قديم — الأدوية
    // دي اتكتبت بالإيد أو من روشتة، وولا واحدة فيهم حد قال مادتها.
    final medColumns = await db
        .customSelect("SELECT name FROM pragma_table_info('medications')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(medColumns, contains('active_ingredient'));
    for (final m in await db.select(db.medications).get()) {
      expect(m.activeIngredient, isNull, reason: 'مادة مخترعة لدوا قديم');
    }

    // v21: الروتين بقى اختياري — والروتين القديم **كله متحدد**: اللي
    // وصل هنا جاوب على الخمس أسئلة، فولا مرساة بتتعلّم إنها مش بتاعته.
    final routineColumns = await db
        .customSelect("SELECT name FROM pragma_table_info('day_routines')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(routineColumns, contains('unset_anchors'));
    final backupColumns = await db
        .customSelect("SELECT name FROM pragma_table_info('routine_backups')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(backupColumns, contains('unset_anchors'));
    for (final r in await db.select(db.dayRoutines).get()) {
      expect(r.unsetAnchors, '', reason: 'روتين قديم اتعلّم إنه ناقص');
      expect(routineFromRow(r).isComplete, isTrue);
    }

    // v22: نوع التنبيه — الدوا القديم null (زي الجهاز)، والجهاز على «يتكرر»
    // اللي كان السلوك الوحيد: مفيش دوا اتغيّر تنبيهه من غير ما حد يختار.
    final medColumns22 = await db
        .customSelect("SELECT name FROM pragma_table_info('medications')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(medColumns22, contains('alert_mode'));
    for (final m in await db.select(db.medications).get()) {
      expect(m.alertMode, isNull, reason: 'نوع مخترع لدوا قديم');
    }
    final prefColumns = await db
        .customSelect("SELECT name FROM pragma_table_info('device_preferences')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(prefColumns, contains('alert_mode'));

    // v23: «لإيه؟» و«تعليمات» — موجودين وفاضيين لكل دوا قديم.
    expect(medColumns22, containsAll(['purpose', 'instructions']));
    for (final m in await db.select(db.medications).get()) {
      expect(m.purpose, isNull);
      expect(m.instructions, isNull);
    }
  });

  test('التاريخ عاش: حدث «اتاخد» لسه مربوط بجرعته ويومه', () async {
    final db = openLegacy();
    addTearDown(db.close);

    final event = (await db.select(db.doseEvents).get()).single;
    expect(event.doseScheduleId, 10);
    expect(event.routineDay, DateTime(2026, 8, 31));
    expect(event.state, DoseState.taken);
    expect(event.actedAt, isNotNull);
    // v24: مين أكّدها — null لكل صف قديم (المريض بنفسه)
    expect(event.actedBy, isNull);
  });

  test('المفاتيح الأجنبية سليمة بعد إعادة بناء الجدول', () async {
    final db = openLegacy();
    addTearDown(db.close);

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.read<int>('foreign_keys'), 1, reason: 'رجعت شغّالة بعد الترحيل');

    // والـcascade شغال على الجدول الجديد: مسح الدوا بيمسح جرعته وأحداثها
    await (db.delete(db.medications)..where((t) => t.id.equals(1))).go();
    expect(
      await (db.select(db.doseSchedules)..where((t) => t.id.equals(10))).get(),
      isEmpty,
    );
    expect(await db.select(db.doseEvents).get(), isEmpty);
  });

  test('بعد الترحيل، ساعة ثابتة جديدة بتتكتب وبتتقرا جنب القديم', () async {
    final db = openLegacy();
    addTearDown(db.close);
    final meds = MedicationRepository(db, clock: seededLongAgo);

    await meds.addMedication(
      patientId: 1,
      name: 'Eltroxin',
      timing: FixedTiming(MinuteOfDay.hm(6, 30)),
      startDate: DateTime(2026, 9, 1),
    );

    final loaded = await meds.activeSchedules(1);
    expect(loaded.length, 3);
    expect(
      loaded.singleWhere((s) => s.medicationName == 'Eltroxin').timing,
      FixedTiming(MinuteOfDay.hm(6, 30)),
    );
    expect(
      loaded.where((s) => s.timing is AnchorTiming).length,
      2,
      reason: 'القديم لسه مراسي',
    );
  });
}
