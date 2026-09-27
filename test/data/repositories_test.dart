import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';
import '../support/seeded_clock.dart';
import '../support/legacy_anchor.dart';

/// نفس روتين اختبارات المحرك: صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م

final aug31 = DateTime(2026, 8, 31);

void main() {
  late AppDatabase db;
  late PatientRepository patients;
  late MedicationRepository meds;
  late DoseEventRepository events;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    patients = PatientRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    events = DoseEventRepository(db);
    patientId = await patients.ensurePatient();
  });

  tearDown(() => db.close());

  group('الساعة في جدولها، ومفيش عمود ساعة على الجرعة', () {
    Future<Set<String>> columnsOf(String table) async {
      final columns =
          await db.customSelect('PRAGMA table_info($table)').get();
      return columns.map((r) => r.read<String>('name')).toSet();
    }

    test('مفيش ولا عمود ساعة في جدول الجرعات', () async {
      final names = await columnsOf('dose_schedules');

      expect(names, {
        'id',
        'uuid',
        'updated_at_ms',
        'synced_at_ms',
        'medication_id',
        // «قبل الأكل» وأخواتها (v30) — كلمة تعليمات، مش ساعة.
        'meal_relation',
        'repeat',
        'start_date',
        'duration_days',
        // لحظة سريان القاعدة (v15) — مش ميعاد جرعة. مسموح بالاسم ده بس.
        'active_from',
        // لحظة إيقاف الجرعة (v16) — مش ميعاد جرعة برضه، وإيقاف ناعم مش مسح.
        'stopped_at',
        // أنماط الأيام (v29) — **أنهي أيام**، مش ساعة: الدقيقة لسه من المرساة
        // أو من fixed_timings.
        'weekdays_mask',
        'every_days',
        'cycle_on',
        'cycle_off',
      });
      // لو حد ضاف عمود وقت هنا، السطر ده بيقع — وده المقصود بالظبط.
      // عمود الساعة بيخص نوع «ثابتة» لوحده، وعايش في جدوله.
      expect(
        names.any((n) => n.contains('time') || n.contains('clock')),
        isFalse,
        reason: 'الساعة في fixed_timings، مش على الجرعة',
      );
    });

    test('عمود الساعة موجود في جدول الساعات الثابتة وبس', () async {
      expect(
        await columnsOf('fixed_timings'),
        {'uuid', 'updated_at_ms', 'synced_at_ms', 'dose_schedule_id', 'minute_of_day'},
      );
    });

    test('صفّين ورا بعض بياخدوا uuid مختلفين من غير ما حد يفتكر', () async {
      // مفيش ولا نقطة إدخال بتمرّر uuid — الـclientDefault هو اللي بيولّد
      await meds.addMedication(
        patientId: patientId,
        name: 'A',
        timing: FixedTiming(MinuteOfDay.hm(8)),
        startDate: aug31,
      );
      await meds.addMedication(
        patientId: patientId,
        name: 'B',
        timing: FixedTiming(MinuteOfDay.hm(9)),
        startDate: aug31,
      );

      final rows = await db.select(db.medications).get();
      expect(rows.length, 2);
      expect(rows[0].uuid, isNotEmpty);
      expect(rows[0].uuid, isNot(rows[1].uuid));
      final schedules = await db.select(db.doseSchedules).get();
      expect(schedules[0].uuid, isNot(schedules[1].uuid));
    });

    test('الساعة الثابتة بترجع زي ما اتحطت ومن غير مرساة', () async {
      await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(8)),
        startDate: aug31,
      );

      final loaded = (await meds.activeSchedules(patientId)).single;
      expect(loaded.timing, FixedTiming(MinuteOfDay.hm(8)));
      expect(loaded.ruleLabel, isNull);

      final row = (await db.select(db.doseSchedules).get()).single;
      expect(row.mealRelation, isNull);
    });

    test('وقف الدوا بيشيل ساعته الثابتة معاه (cascade)', () async {
      final id = await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(8)),
        startDate: aug31,
      );
      await (db.delete(db.medications)..where((t) => t.id.equals(id))).go();

      expect(await db.select(db.fixedTimings).get(), isEmpty);
    });

    test('الساعة وكلمة الأكل بيرجعوا زي ما اتحطوا', () async {
      await meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Antodine',
        timings: [FixedTiming(MinuteOfDay.hm(7))],
        startDate: aug31,
        amountLabel: 'قرص واحد',
        mealRelation: MealRelation.before,
      );

      final loaded = (await meds.activeSchedules(patientId)).single;
      expect(loaded.timing, FixedTiming(MinuteOfDay.hm(7)));
      expect(loaded.medicationName, 'Antodine');
      expect(loaded.amountLabel, 'قرص واحد');
      expect(loaded.ruleLabel, 'قبل الأكل');
      expect((await db.select(db.doseSchedules).get()).single.mealRelation, 'before');
    });

    test('updateTiming: ساعة → ساعة → ساعة، نفس الصف ونفس uuid وصف ساعة واحد', () async {
      final medId = await meds.addMedication(
        patientId: patientId,
        name: 'Antodine',
        timing: FixedTiming(MinuteOfDay.hm(7)),
        startDate: aug31,
      );
      final before = (await db.select(db.doseSchedules).get()).single;

      await meds.updateTiming(before.id, FixedTiming(MinuteOfDay.hm(14)));
      var loaded = (await meds.schedulesFor(medId)).single;
      expect(loaded.timing, FixedTiming(MinuteOfDay.hm(14)));
      var row = (await db.select(db.doseSchedules).get()).single;
      expect(row.id, before.id);
      expect(row.uuid, before.uuid);
      expect((await db.select(db.fixedTimings).get()).single.minuteOfDay, 14 * 60);

      await meds.updateTiming(before.id, FixedTiming(MinuteOfDay.hm(20, 30)));
      loaded = (await meds.schedulesFor(medId)).single;
      expect(loaded.timing, FixedTiming(MinuteOfDay.hm(20, 30)));
      row = (await db.select(db.doseSchedules).get()).single;
      expect(row.uuid, before.uuid);
      expect((await db.select(db.fixedTimings).get()).single.minuteOfDay, 20 * 60 + 30,
          reason: 'صف ساعة واحد للجرعة، مش صفّين');
    });

    test('watchAllSummaries بيرجّع الموقوف كمان — والنشط بس في watchActiveSummaries', () async {
      final a = await meds.addMedication(
        patientId: patientId, name: 'A', timing: FixedTiming(MinuteOfDay.hm(7, 30)), startDate: aug31);
      await meds.addMedication(
        patientId: patientId, name: 'B', timing: FixedTiming(MinuteOfDay.hm(20)), startDate: aug31);
      await meds.stopMedication(a);

      final all = await meds.watchAllSummaries(patientId).first;
      final active = await meds.watchActiveSummaries(patientId).first;
      expect(all.map((m) => m.medication.name).toSet(), {'A', 'B'});
      expect(all.firstWhere((m) => m.medication.name == 'A').medication.stoppedAt, isNotNull);
      expect(active.map((m) => m.medication.name).toList(), ['B']);
    });

    test('تاريخ البداية بيرجع محلّي وبنص الليل بالظبط', () async {
      await meds.addMedication(
        patientId: patientId,
        name: 'Amebazole',
        timing: FixedTiming(MinuteOfDay.hm(14, 30)),
        repeat: DoseRepeat.once,
        startDate: DateTime(2026, 8, 31, 14, 37),
      );

      final loaded = (await meds.activeSchedules(patientId)).single;
      expect(loaded.startDate, aug31);
      expect(loaded.startDate.isUtc, isFalse);
      // «اليوم فقط» بيقارن بمساواة تامة — لو التاريخ رجع UTC ده كان هيقع
      expect(loaded.isActiveOn(aug31), isTrue);
    });
  });

  group('المدة والإيقاف', () {
    test('مدة مفتوحة بتتخزّن null وبتفضل شغالة بعد سنين', () async {
      await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(7, 30)),
        startDate: aug31,
      );

      final loaded = (await meds.activeSchedules(patientId)).single;
      expect(loaded.durationDays, isNull);
      expect(loaded.isActiveOn(aug31.add(const Duration(days: 3650))), isTrue);
    });

    test('الدوا ما بيتوقفش إلا بـstopMedication', () async {
      final id = await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(7, 30)),
        startDate: aug31,
      );

      expect((await meds.activeSchedules(patientId)).length, 1);

      await meds.stopMedication(id);
      expect(await meds.activeSchedules(patientId), isEmpty);

      // الدوا نفسه ما اتمسحش — بس بقى موقوف
      expect((await db.select(db.medications).get()).length, 1);
    });
  });

  group('أحداث الجرعات', () {
    Future<int> addDose(String name, DayAnchor anchor, {int offset = 0}) async {
      await meds.addMedication(
        patientId: patientId,
        name: name,
        timing: AnchorTiming(anchor, offset),
        startDate: aug31,
      );
      final all = await meds.activeSchedules(patientId);
      return int.parse(all.firstWhere((d) => d.medicationName == name).id);
    }

    Future<void> materialize() async {
      final engine = const ScheduleEngine();
      await events.materializeDay(
        aug31,
        engine.remindersForDay(await meds.activeSchedules(patientId), aug31),
      );
    }

    test('اليوم بيتولّد بحالة «لسه»', () async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();

      final day = await events.watchDay(aug31).first;
      expect(day.length, 1);
      expect(day.single.state, DoseState.pending);
      expect(day.single.scheduledAt, DateTime(2026, 8, 31, 7, 0));
    });

    test('التوليد مرتين ما بيعملش أحداث مكررة', () async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();
      await materialize();

      expect((await db.select(db.doseEvents).get()).length, 1);
    });

    test('جرعة اتاخدت بتفضل موجودة، بتهدى بس', () async {
      final id = await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();
      await events.markTaken(id, aug31);

      final day = await events.watchDay(aug31).first;
      expect(day.length, 1, reason: 'الجرعة المتاخدة ما بتتمسحش أبداً');
      expect(day.single.state, DoseState.taken);
      expect(day.single.isDone, isTrue);
      expect(day.single.actedAt, isNotNull);
    });

    test('التوليد بعد «اتاخد» ما بيرجعهاش «لسه»', () async {
      final id = await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();
      await events.markTaken(id, aug31);
      await materialize();

      final day = await events.watchDay(aug31).first;
      expect(day.single.state, DoseState.taken);
    });

    test('ساعة الجرعة اتعدّلت → ساعة الحدث المعلّق بتمشي وراها', () async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();

      final schedule = (await meds.activeSchedules(patientId)).single;
      await meds.updateTiming(int.parse(schedule.id), FixedTiming(MinuteOfDay.hm(8, 30)));
      await events.materializeDay(
        aug31,
        const ScheduleEngine().remindersForDay(
          await meds.activeSchedules(patientId),
          aug31,
        ),
      );

      final day = await events.watchDay(aug31).first;
      expect(day.single.scheduledAt, DateTime(2026, 8, 31, 8, 30));
      expect((await db.select(db.doseEvents).get()).length, 1);
    });

    test('الفهرس بيمنع حدثين لنفس الجرعة في نفس اليوم', () async {
      final id = await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await materialize();

      expect(
        () => db.into(db.doseEvents).insert(
              DoseEventsCompanion.insert(
                doseScheduleId: id,
                routineDay: aug31,
                scheduledAt: DateTime(2026, 8, 31, 7),
                state: DoseState.pending,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('دواءين في نفس الدقيقة = حدثين، تذكير واحد', () async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30);
      await addDose('Vitamin D', DayAnchor.breakfast, offset: -30);
      await materialize();

      final day = await events.watchDay(aug31).first;
      expect(day.length, 2);
      expect(day.map((e) => e.scheduledAt).toSet().length, 1);
    });
  });

  group('البث', () {
    test('watchActiveSchedules بترمي قيمة جديدة بعد الإضافة', () async {
      final emissions = <int>[];
      final sub = meds
          .watchActiveSchedules(patientId)
          .listen((list) => emissions.add(list.length));

      await pumpEventQueue();
      await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(7, 30)),
        startDate: aug31,
      );
      await pumpEventQueue();

      await sub.cancel();
      expect(emissions.first, 0);
      expect(emissions.last, 1);
    });
  });
}
