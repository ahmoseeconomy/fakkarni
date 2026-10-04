// **نسخة ٣٠ — الروتين اتشال وكل جرعة بقت ساعة ثابتة. الوعد: ولا تذكير
// بيتحرك دقيقة.**
//
// قاعدة v29 بروتين المريض بتاعه (مش الافتراضي) وأدوية على مراسي بإزاحات،
// وواحدة على مرساة ما اتحددتش، وساعة ثابتة، وأحداث اليوم. بعد الترحيل:
// خطة السبع أيام (بالرقم واللحظة) هي **نفس** اللي المحرّك القديم كان
// هيطلّعها — المحرّك القديم متعاد هنا بالحرف عشان يبقى فيه «قبل» نقارن بيه.
import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

import '../drift/generated/schema.dart';

/// روتين المريض في القاعدة القديمة — **مش الافتراضي** عن قصد: الصحيان ٥:٤٥،
/// الفطار ٨:١٠، الغدا ٣:٢٠، العشا ٩:٠٥، النوم ١٢:٤٠ بعد نص الليل.
const _wake = 5 * 60 + 45, _breakfast = 8 * 60 + 10, _lunch = 15 * 60 + 20, _dinner = 21 * 60 + 5, _sleep = 40;

/// المحرّك القديم بالحرف: `الصحيان + ((المرساة − الصحيان + ١٤٤٠) % ١٤٤٠) + الإزاحة`
/// على تاريخ يوم الروتين، واليوم بيبدأ من الصحيان.
DateTime _oldResolve(int anchorMinutes, int offset, DateTime day) =>
    DateTime(day.year, day.month, day.day, 0, _wake + ((anchorMinutes - _wake + 1440) % 1440) + offset);

/// الأدوية القديمة: (id، المرساة، دقايقها، الإزاحة)
const _anchored = [
  (10, 'breakfast', _breakfast, -30), // Concor قبل الفطار
  (11, 'dinner', _dinner, 30), // LINEX بعد العشا
  (12, 'sleep', _sleep, -15), // Telfast قبل النوم — بعد نص الليل
  (13, 'wake', _wake, 0), // Eltroxin أول ما يصحى
];

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  Future<AppDatabase> migrated() async {
    final schema = await verifier.schemaAt(29);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO patients (id, uuid, name, notification_slot, sex, updated_at_ms) VALUES (1, 'p-1', 'الحاج أحمد', 0, 'm', 1000)");
    raw.execute(
        "INSERT INTO day_routines (id, uuid, patient_id, wake_minutes, breakfast_minutes, lunch_minutes, dinner_minutes, sleep_minutes, unset_anchors, updated_at_ms) "
        "VALUES (1, 'r-1', 1, $_wake, $_breakfast, $_lunch, $_dinner, $_sleep, 'lunch', 2000)");
    for (final (i, name) in ['Concor', 'LINEX', 'Telfast', 'Eltroxin', 'Amaryl', 'Glucophage'].indexed) {
      raw.execute("INSERT INTO medications (id, uuid, patient_id, name, amount_unknown, updated_at_ms) VALUES (${i + 1}, 'm-${i + 1}', 1, '$name', 0, 3000)");
    }
    for (final (i, (id, anchor, _, offset)) in _anchored.indexed) {
      raw.execute(
          "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, updated_at_ms, synced_at_ms) "
          "VALUES ($id, 's-$id', ${i + 1}, 'anchor', '$anchor', $offset, 'daily', '2026-08-01', 4000, 4000)");
    }
    // Amaryl قبل الغدا — والغدا **ما اتحددش**: ما كانش بيرن
    raw.execute(
        "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, updated_at_ms) "
        "VALUES (14, 's-14', 5, 'anchor', 'lunch', -30, 'daily', '2026-08-01', 4000)");
    // Glucophage ساعة ثابتة ٦:٠٠ الصبح — قبل الصحيان القديم؟ لأ، بعده: زي ما هي
    raw.execute(
        "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, repeat, start_date, updated_at_ms) "
        "VALUES (15, 's-15', 6, 'fixed', 'daily', '2026-08-01', 4000)");
    raw.execute("INSERT INTO fixed_timings (uuid, dose_schedule_id, minute_of_day, updated_at_ms) VALUES ('f-15', 15, ${6 * 60}, 4000)");
    // أحداث النهارده (يوم روتين ٣٠ أغسطس): Telfast بتاعته بعد نص الليل — ٣١ أغسطس ٠:٢٥
    final telfastAt = _oldResolve(_sleep, -15, DateTime(2026, 8, 30)).millisecondsSinceEpoch ~/ 1000;
    final concorAt = _oldResolve(_breakfast, -30, DateTime(2026, 8, 30)).millisecondsSinceEpoch ~/ 1000;
    raw.execute("INSERT INTO dose_events (id, uuid, dose_schedule_id, routine_day, scheduled_at, state, updated_at_ms) VALUES (1, 'e-1', 12, '2026-08-30', $telfastAt, 'pending', 5000)");
    raw.execute("INSERT INTO dose_events (id, uuid, dose_schedule_id, routine_day, scheduled_at, state, acted_at, updated_at_ms) VALUES (2, 'e-2', 10, '2026-08-30', $concorAt, 'taken', $concorAt, 5000)");

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 32);
    return db;
  }

  test('كل مرساة اتحوّلت للساعة اللي كانت بترن فيها بالحرف — بروتين المريض، مش الافتراضي', () async {
    final db = await migrated();
    addTearDown(db.close);
    final fixed = {for (final f in await db.select(db.fixedTimings).get()) f.doseScheduleId: f.minuteOfDay};
    expect(fixed[10], _breakfast - 30, reason: 'Concor ٧:٤٠');
    expect(fixed[11], _dinner + 30, reason: 'LINEX ٩:٣٥ م');
    expect(fixed[12], _sleep - 15, reason: 'Telfast ١٢:٢٥ بعد نص الليل — الرقم بيلف');
    expect(fixed[13], _wake, reason: 'Eltroxin أول ما يصحى');
    expect(fixed[15], 6 * 60, reason: 'الثابتة زي ما هي');
    // كلمة الأكل اتحفظت — والصحيان والنوم مش أكل
    final rel = {for (final s in await db.select(db.doseSchedules).get()) s.id: s.mealRelation};
    expect(rel[10], 'before');
    expect(rel[11], 'after');
    expect(rel[12], isNull);
    expect(rel[13], isNull);
    expect(rel[15], isNull);
    // الأعمدة القديمة راحت
    final cols = (await db.customSelect("SELECT name FROM pragma_table_info('dose_schedules')").get()).map((r) => r.read<String>('name')).toSet();
    expect(cols, isNot(contains('anchor')));
    expect(cols, isNot(contains('offset_minutes')));
    expect(cols, isNot(contains('timing_kind')));
    expect(cols, contains('meal_relation'));
    expect(await db.customSelect("SELECT 1 FROM sqlite_master WHERE name IN ('day_routines', 'routine_backups')").get(), isEmpty);
    // والمريض اتعلّم إنه مريض
    expect((await db.select(db.patients).get()).single.profileDoneAt, isNotNull);
  });

  test('مرساة ما اتحددتش ما كانتش بترن — بتتوقف بدل ما ترن على رقم ما قالهوش', () async {
    final db = await migrated();
    addTearDown(db.close);
    final amaryl = (await (db.select(db.doseSchedules)..where((t) => t.id.equals(14))).getSingle());
    expect(amaryl.stoppedAt, isNotNull, reason: 'موقوفة — بيرجّعها بإيده بعد ما يظبط ساعتها');
    expect((await (db.select(db.fixedTimings)..where((t) => t.doseScheduleId.equals(14))).getSingle()).minuteOfDay, _lunch - 30,
        reason: 'وساعتها محفوظة على مكان الراحة عشان الرجوع يبقى بإيده');
    final active = await MedicationRepository(db).activeSchedules(1);
    expect(active.map((s) => s.medicationName), isNot(contains('Amaryl')));
  });

  test('**خطة السبع أيام قبل وبعد متطابقة** — الرقم واللحظة لكل تذكير', () async {
    final db = await migrated();
    addTearDown(db.close);
    final from = DateTime(2026, 8, 31, 6);
    final after = planWindow(schedules: await MedicationRepository(db).activeSchedules(1), from: from, maxPending: 1 << 20);

    // «قبل»: المحرّك القديم بالحرف على نفس النافذة (امبارح + ٧ أيام)
    final before = <int, DateTime>{};
    for (var offset = -1; offset < reminderWindowDays; offset++) {
      final day = DateTime(from.year, from.month, from.day + offset);
      for (final (_, _, minutes, off) in _anchored) {
        final at = _oldResolve(minutes, off, day);
        if (at.isAfter(from)) before[notificationIdFor(at)] = at;
      }
      // الثابتة ٦:٠٠ — بعد الصحيان القديم (٥:٤٥) فنفس التاريخ
      final six = DateTime(day.year, day.month, day.day, 6);
      if (six.isAfter(from)) before[notificationIdFor(six)] = six;
    }
    expect({for (final n in after) n.id: n.at}, before, reason: 'ولا تذكير اتحرك دقيقة');
    expect(after.length, before.length);
  });

  test('أحداث الجرعات اتعاد مفتاحها على قاعدة ٤ الفجر من ساعتها الحقيقية — من غير ما تتكرر', () async {
    final db = await migrated();
    addTearDown(db.close);
    final events = await db.select(db.doseEvents).get();
    final telfast = events.singleWhere((e) => e.doseScheduleId == 12);
    // ٣١ أغسطس ٠:٢٥ < ٤ الفجر → لسه تبع ٣٠ أغسطس، زي ما كانت
    expect(telfast.routineDay, DateTime(2026, 8, 30));
    expect(telfast.state, DoseState.pending);
    final concor = events.singleWhere((e) => e.doseScheduleId == 10);
    expect(concor.routineDay, DateTime(2026, 8, 30));
    expect(concor.state, DoseState.taken, reason: 'اللي اتاخد ما اتلمسش');

    // ولما «يومك» تنزّل نفس اليوم بالمحرّك الجديد، مفيش صف تاني
    final meds = MedicationRepository(db);
    final repo = DoseEventRepository(db);
    await repo.materializeDay(DateTime(2026, 8, 30), const ScheduleEngineProbe().remindersFor(await meds.activeSchedules(1), DateTime(2026, 8, 30)));
    expect((await db.select(db.doseEvents).get()).where((e) => e.doseScheduleId == 12).length, 1);
  });

  test('من غير صف روتين: الافتراضي القديم (٦:٣٠ / ٧:٣٠ / ٢ / ٨ / ١١:٣٠) هو اللي بيتحسب بيه', () async {
    final schema = await verifier.schemaAt(29);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO patients (id, uuid, name, notification_slot, updated_at_ms) VALUES (1, 'p-1', 'أنا', 0, 1000)");
    raw.execute("INSERT INTO medications (id, uuid, patient_id, name, amount_unknown, updated_at_ms) VALUES (1, 'm-1', 1, 'Concor', 0, 3000)");
    raw.execute(
        "INSERT INTO dose_schedules (id, uuid, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, updated_at_ms) "
        "VALUES (1, 's-1', 1, 'anchor', 'dinner', 30, 'daily', '2026-08-01', 4000)");
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 32);
    expect((await db.select(db.fixedTimings).get()).single.minuteOfDay, 20 * 60 + 30);
    expect((await db.select(db.patients).get()).single.profileDoneAt, isNull, reason: 'صف «أنا» مش مريض');
    final s = (await MedicationRepository(db).activeSchedules(1)).single;
    expect(s.timing, FixedTiming(MinuteOfDay.hm(20, 30)));
    expect(s.mealRelation, MealRelation.after);
    // والكتابة بعد الترحيل شغّالة بالشكل الجديد
    await MedicationRepository(db).updateMealRelation(1, MealRelation.emptyStomach);
    expect((await MedicationRepository(db).activeSchedules(1)).single.ruleLabel, 'على معدة فاضية');
    await (db.update(db.doseSchedules)..where((t) => t.id.equals(1))).write(const DoseSchedulesCompanion(mealRelation: Value(null)));
  });
}

/// المحرّك الجديد — عشان الاختبار ما يستوردش الجدولة على طول في اسم مضلّل.
class ScheduleEngineProbe {
  const ScheduleEngineProbe();
  List<Reminder> remindersFor(List<DoseSchedule> schedules, DateTime day) => const ScheduleEngine().remindersForDay(schedules, day);
}
