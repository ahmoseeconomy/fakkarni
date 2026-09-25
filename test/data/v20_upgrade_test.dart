// اختبار الترقية قبل تجربة الجهاز: أقدم نسخة ممكن تكون على موبايل حقيقي
// (v20) ببيانات شكلها زي بيانات مريض فعلاً ← تتفتح بالتطبيق الحالي.
//
// الوعد اللي بيتختبر هنا مش «الجداول اتعملت» (ده شغل `migrateAndValidate`)،
// هو إن **ولا حاجة ضاعت** وإن **التذكيرات بعد الترقية هي هي** اللي كانت
// هتطلع لو نفس البيانات اتكتبت على قاعدة جديدة من الأول.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/scheduling/day_pattern.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../drift/generated/schema.dart';
import '../features/scan/scan_test_support.dart' show RecordingSink;
import '../support/seeded_clock.dart';

/// ثواني من عصر يونكس — نفس تخزين drift لأعمدة الوقت.
int _s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// «دلوقتي» في الاختبار: الخميس ٢٥ سبتمبر ٢٠٢٦، ٩ الصبح.
final _now = DateTime(2026, 9, 25, 9);

/// البيانات بأعمدة v20 **وبس** — نفس الجمل بالحرف بتتكتب على الملف القديم
/// وعلى قاعدة جديدة، فأي فرق في الخطة بعد كده سببه الترحيل مش البيانات.
List<String> _seed() => [for (final sql in _statements()) _stamp(sql)];

/// `updated_at_ms` في v20 بيتملى من التطبيق (`clientDefault`) مش من SQLite،
/// فالجملة الخام لازم تحطه — زي ما التطبيق القديم كان بيكتبه.
String _stamp(String sql) {
  if (sql.contains('updated_at_ms') || sql.contains('device_preferences')) return sql;
  return sql
      .replaceFirst('(uuid,', '(updated_at_ms, uuid,')
      .replaceFirst(RegExp(r"VALUES \('"), "VALUES (1788000000000, '");
}

List<String> _statements() {
  final longAgo = _s(DateTime(2026, 8, 1, 10));
  return [
    // المريض مربوط (synced_at_ms مليان) — الابن نفسه في السحابة بس، وأثره
    // المحلي هو إن الصفوف اتدفعت. جهة اتصاله محفوظة في بيانات الطوارئ.
    "INSERT INTO patients (uuid, updated_at_ms, synced_at_ms, id, name, notification_slot, created_at, sex, age) "
        "VALUES ('p-1', 1788000000000, 1788000000000, 1, 'الحاج عاشور', 0, $longAgo, 'm', 72)",
    "INSERT INTO day_routines (uuid, updated_at_ms, synced_at_ms, id, patient_id, wake_minutes, breakfast_minutes, "
        "lunch_minutes, dinner_minutes, sleep_minutes, updated_at) "
        "VALUES ('r-1', 1788000000000, 1788000000000, 1, 1, 390, 450, 870, 1230, 1380, $longAgo)",
    "INSERT INTO device_preferences (id, elder_mode, rung_first_on, rung_second_on) VALUES (1, 0, 1, 0)",
    "INSERT INTO emergency_profile (uuid, id, patient_id, blood_type, allergies, chronic_conditions, contacts_json) "
        "VALUES ('e-1', 1, 1, 'A+', 'بنسلين', 'سكر وضغط', "
        "'[{\"name\":\"محمد\",\"phone\":\"01000000000\",\"relation\":\"ابنه\"}]')",

    // ١ — قبل الفطار بنص ساعة، مفتوح
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, active_ingredient, created_at) "
        "VALUES ('m-1', 1, 1, 'Concor 5mg', 'قرص واحد', 0, 'bisoprolol', $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-1', 1, 1, 'anchor', 'breakfast', -30, 'daily', '2026-08-01', NULL, $longAgo)",
    // ٢ — بعد الفطار وبعد العشا، جرعتين
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, created_at) "
        "VALUES ('m-2', 2, 1, 'Glucophage 1000', 'نص قرص', 0, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-2', 2, 2, 'anchor', 'breakfast', 15, 'daily', '2026-08-01', NULL, NULL)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-3', 3, 2, 'anchor', 'dinner', 15, 'daily', '2026-08-01', NULL, NULL)",
    // ٣ — ساعة ثابتة ٩ بالليل
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, created_at) "
        "VALUES ('m-3', 3, 1, 'Eltroxin 50', NULL, 1, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-4', 4, 3, 'fixed', NULL, NULL, 'daily', '2026-08-01', NULL, $longAgo)",
    "INSERT INTO fixed_timings (uuid, dose_schedule_id, minute_of_day) VALUES ('f-4', 4, 1260)",
    // ٤ — كورس ٧ أيام مع الغدا، ساعة ثابتة تانية الصبح بدري
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, created_at) "
        "VALUES ('m-4', 4, 1, 'Augmentin 1g', 'قرص', 0, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-5', 5, 4, 'anchor', 'lunch', 0, 'daily', '2026-09-22', 7, NULL)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-6', 6, 4, 'fixed', NULL, NULL, 'daily', '2026-09-22', 7, NULL)",
    "INSERT INTO fixed_timings (uuid, dose_schedule_id, minute_of_day) VALUES ('f-6', 6, 367)",
    // ٥ — قبل النوم، ومرة واحدة بكرة الساعة ١١ ونص الصبح
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, created_at) "
        "VALUES ('m-5', 5, 1, 'Stilnox', 'قرص', 0, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-7', 7, 5, 'anchor', 'sleep', -15, 'daily', '2026-08-01', NULL, NULL)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-8', 8, 5, 'fixed', NULL, NULL, 'once', '2026-09-26', NULL, NULL)",
    "INSERT INTO fixed_timings (uuid, dose_schedule_id, minute_of_day) VALUES ('f-8', 8, 690)",
    // ٦ — موقوف، ٧ — متشال، ٨ — جرعة موقوفة على دوا شغّال
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, stopped_at, created_at) "
        "VALUES ('m-6', 6, 1, 'Brufen 400', 'قرص', 0, ${_s(DateTime(2026, 9, 10))}, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-9', 9, 6, 'anchor', 'lunch', 15, 'daily', '2026-08-01', NULL, NULL)",
    "INSERT INTO medications (uuid, id, patient_id, name, amount_label, amount_unknown, removed_at, created_at) "
        "VALUES ('m-7', 7, 1, 'Panadol', 'قرص', 0, ${_s(DateTime(2026, 9, 12))}, $longAgo)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
        "VALUES ('s-10', 10, 7, 'anchor', 'dinner', 0, 'daily', '2026-08-01', NULL, NULL)",
    "INSERT INTO dose_schedules (uuid, id, medication_id, timing_kind, stopped_at, anchor, offset_minutes, repeat, start_date, duration_days, active_from) "
            "VALUES ('s-11', 11, 1, 'anchor', 'lunch', -30, 'daily', '2026-08-01', NULL, NULL)"
        .replaceFirst("'anchor', 'lunch'", "'anchor', ${_s(DateTime(2026, 9, 1))}, 'lunch'"),

    // أحداث: امبارح اتاخد واتنسى، والنهارده الفطار اتاخد بدري
    for (final (id, sched, day, at, state, acted) in [
      (1, 1, '2026-09-24', DateTime(2026, 9, 24, 7), 'taken', DateTime(2026, 9, 24, 7, 4)),
      (2, 2, '2026-09-24', DateTime(2026, 9, 24, 7, 45), 'taken', DateTime(2026, 9, 24, 7, 50)),
      (3, 5, '2026-09-24', DateTime(2026, 9, 24, 14, 30), 'missed', null),
      (4, 3, '2026-09-24', DateTime(2026, 9, 24, 20, 45), 'skipped', DateTime(2026, 9, 24, 21)),
      (5, 4, '2026-09-24', DateTime(2026, 9, 24, 21), 'taken', DateTime(2026, 9, 24, 21, 10)),
      (6, 7, '2026-09-24', DateTime(2026, 9, 24, 22, 45), 'missed', null),
      (7, 6, '2026-09-25', DateTime(2026, 9, 25, 6, 7), 'taken', DateTime(2026, 9, 25, 6, 30)),
      (8, 1, '2026-09-25', DateTime(2026, 9, 25, 7), 'taken', DateTime(2026, 9, 25, 6, 55)),
      (9, 2, '2026-09-25', DateTime(2026, 9, 25, 7, 45), 'pending', null),
      (10, 5, '2026-09-25', DateTime(2026, 9, 25, 14, 30), 'taken', DateTime(2026, 9, 25, 8, 58)),
    ])
      "INSERT INTO dose_events (uuid, id, dose_schedule_id, routine_day, scheduled_at, state, acted_at) "
          "VALUES ('ev-$id', $id, $sched, '$day', ${_s(at)}, '$state', ${acted == null ? 'NULL' : _s(acted)})",

    // الملف الصحي
    "INSERT INTO records (uuid, id, patient_id, kind, title, happened_at, doctor, place) "
        "VALUES ('rec-1', 1, 1, 'lab', 'صورة دم', ${_s(DateTime(2026, 9, 1))}, 'د. هشام', 'معمل البرج')",
    "INSERT INTO lab_results (uuid, id, record_id, test_name, value, unit, ref_low, ref_high) "
        "VALUES ('lab-1', 1, 1, 'Haemoglobin', 11.6, 'g/dL', 13, 17)",
    "INSERT INTO readings (uuid, id, patient_id, value_mg_dl, measured_at, context) "
        "VALUES ('rd-1', 1, 1, 142, ${_s(DateTime(2026, 9, 24, 8))}, 'fasting')",
    "INSERT INTO visit_questions (uuid, id, patient_id, body, created_at, asked) "
        "VALUES ('q-1', 1, 1, 'أوقّف البروفين؟', ${_s(DateTime(2026, 9, 20))}, 0)",
  ];
}

const _tables = [
  'patients',
  'day_routines',
  'device_preferences',
  'emergency_profile',
  'medications',
  'dose_schedules',
  'fixed_timings',
  'dose_events',
  'records',
  'lab_results',
  'readings',
  'visit_questions',
];

/// نفس الأعمدة اللي اتكتبت في v20، بالقيم — عشان «ولا حاجة ضاعت» تبقى
/// مقارنة حرفية مش عيّنات.
const _v20Columns = {
  'patients': 'uuid, id, name, notification_slot, created_at, sex, age, synced_at_ms',
  'day_routines': 'uuid, id, patient_id, wake_minutes, breakfast_minutes, lunch_minutes, dinner_minutes, sleep_minutes',
  'device_preferences': 'id, elder_mode, rung_first_on, rung_second_on',
  'emergency_profile': 'uuid, id, patient_id, blood_type, allergies, chronic_conditions, contacts_json',
  'medications': 'uuid, id, patient_id, name, amount_label, amount_unknown, notes, active_ingredient, stopped_at, removed_at, created_at',
  'dose_schedules': 'uuid, id, medication_id, timing_kind, stopped_at, anchor, offset_minutes, repeat, start_date, duration_days, active_from',
  'fixed_timings': 'uuid, dose_schedule_id, minute_of_day',
  'dose_events': 'uuid, id, dose_schedule_id, routine_day, scheduled_at, state, acted_at',
  'records': 'uuid, id, patient_id, kind, title, happened_at, doctor, place, deleted_at',
  'lab_results': 'uuid, id, record_id, test_name, value, unit, ref_low, ref_high',
  'readings': 'uuid, id, patient_id, value_mg_dl, measured_at, context',
  'visit_questions': 'uuid, id, patient_id, body, created_at, asked',
};

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String table) async {
  final order = table == 'fixed_timings' || table == 'device_preferences' ? '1' : 'uuid';
  final rows = await db.customSelect('SELECT ${_v20Columns[table]} FROM $table ORDER BY $order').get();
  return [for (final r in rows) r.data];
}

/// الخطة: كل إشعار بالرقم والوقت والكلام والحمولة.
Map<int, String> _plan(RecordingSink sink) => {
  for (final n in sink.scheduled.values) n.id: '${n.at.toIso8601String()}|${n.kind}|${n.title}|${n.body}|${n.payload}',
};

Future<(RecordingSink, List<Map<String, Object?>>)> _reschedule(AppDatabase db) async {
  final sink = RecordingSink();
  await ReminderScheduler(
    routines: RoutineRepository(db),
    medications: MedicationRepository(db, clock: seededLongAgo),
    events: DoseEventRepository(db),
    patientId: 1,
    sink: sink,
    preferences: PreferencesRepository(db),
  ).rescheduleAll(now: _now);
  // الأحداث بعد الجدولة (اللي اتعمل لامبارح والنهارده وبكرة، واللي اتنسى)
  // — من غير uuid، لأن الصفوف الجديدة بتاخد uuid عشوائي.
  final events = await db
      .customSelect(
        'SELECT dose_schedule_id, routine_day, scheduled_at, state, acted_at '
        'FROM dose_events ORDER BY dose_schedule_id, routine_day',
      )
      .get();
  return (sink, [for (final r in events) r.data]);
}

void main() {
  late SchemaVerifier verifier;
  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
    // القاعدتين (المترقّية والجديدة) مفتوحين مع بعض عن قصد.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('v20 ← الحالي: ولا صف ضاع، الجداول سليمة، والتذكيرات زي قاعدة جديدة بالظبط', () async {
    // ── القاعدة القديمة
    final schema = await verifier.schemaAt(20);
    final raw = schema.rawDatabase;
    for (final sql in _seed()) {
      raw.execute(sql);
    }
    final before = {
      for (final t in _tables)
        t: raw
            .select(
              'SELECT ${_v20Columns[t]} FROM $t ORDER BY '
              '${t == 'fixed_timings' || t == 'device_preferences' ? '1' : 'uuid'}',
            )
            .map((r) => Map<String, Object?>.of(r))
            .toList(),
    };
    expect(before['dose_events'], hasLength(10));
    expect(before['medications'], hasLength(7));

    final upgraded = AppDatabase(schema.newConnection());
    addTearDown(upgraded.close);
    await verifier.migrateAndValidate(upgraded, upgraded.schemaVersion);

    // ── ١. ولا حاجة ضاعت: كل عمود من v20 بقيمته، في كل جدول
    for (final t in _tables) {
      expect(await _rows(upgraded, t), before[t], reason: 'جدول $t اتغيّر بعد الترقية');
    }

    // الأعمدة الجديدة بافتراضياتها — ولا حاجة اتخترعت
    final routineRow = (await upgraded.customSelect('SELECT unset_anchors FROM day_routines').getSingle()).data;
    expect(routineRow['unset_anchors'], '', reason: 'روتين قديم = كله متحدد');
    final meds = await upgraded
        .customSelect('SELECT alert_mode, purpose, instructions, photo_path FROM medications')
        .get();
    for (final m in meds) {
      expect(m.data.values, everyElement(isNull), reason: 'دوا قديم خد قيمة مخترعة');
    }
    final patterns = await upgraded
        .customSelect('SELECT weekdays_mask, every_days, cycle_on, cycle_off FROM dose_schedules')
        .get();
    for (final p in patterns) {
      expect(p.data.values, everyElement(isNull), reason: 'جدول قديم لازم يفضل «كل يوم»');
    }
    expect(
      await upgraded.customSelect('SELECT * FROM medication_stock').get(),
      isEmpty,
      reason: 'مخزون مالوش رقم من إنسان = مفيش صف',
    );

    // ── ٢. الجداول سليمة كما يقراها التطبيق
    final routine = await RoutineRepository(upgraded).getRoutine(1);
    expect(routine!.wake.minutes, 390);
    expect(routine.dinner.minutes, 1230);
    expect(routine.unset, isEmpty);

    final active = await MedicationRepository(upgraded, clock: seededLongAgo).activeSchedules(1);
    final byId = {for (final s in active) s.id: s};
    // الموقوف والمتشال والجرعة الموقوفة برّه؛ الباقي كله جوّه
    expect(byId.keys.toSet(), {'1', '2', '3', '4', '5', '6', '7', '8'});
    expect(active.every((s) => s.days == const EveryDay()), isTrue);
    expect(byId['1']!.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    expect(byId['3']!.timing, const AnchorTiming(DayAnchor.dinner, 15));
    expect(byId['4']!.timing, const FixedTiming(MinuteOfDay(1260)));
    expect(byId['6']!.timing, const FixedTiming(MinuteOfDay(367)));
    expect(byId['5']!.durationDays, 7);
    expect(byId['5']!.startDate, DateTime(2026, 9, 22));
    expect(byId['8']!.repeat, DoseRepeat.once);
    expect(byId['4']!.amountLabel, isNull);

    // ── ٣. الخطة بعد الترقية = الخطة من نفس البيانات على قاعدة جديدة
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    for (final sql in _seed()) {
      await fresh.customStatement(sql);
    }

    final (upSink, upEvents) = await _reschedule(upgraded);
    final (freshSink, freshEvents) = await _reschedule(fresh);

    final upPlan = _plan(upSink);
    expect(upPlan, isNotEmpty);
    expect(upPlan, _plan(freshSink));
    expect(upEvents, freshEvents);

    // وخطة فيها المعنى، مش خطتين فاضيين متساويين
    final bodies = upPlan.values.join('\n');
    for (final name in ['Concor', 'Glucophage', 'Eltroxin', 'Augmentin', 'Stilnox']) {
      expect(bodies, contains(name));
    }
    for (final gone in ['Brufen', 'Panadol']) {
      expect(bodies, isNot(contains(gone)));
    }
    // الفطار اللي اتاخد بدري النهارده ما رجعش يتجدول
    final doneToday = upEvents.where((e) => e['dose_schedule_id'] == 1 && e['routine_day'] == '2026-09-25');
    expect(doneToday.single['state'], 'taken');
  });
}
