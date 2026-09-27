// «قبل الأكل» وأخواتها — **كلمة تعليمات، مش توقيت**: بتتعرض في متن الإشعار
// وجنب الجرعة، وعمرها ما تحرّك ساعة.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

import '../support/seeded_clock.dart';

void main() {
  test('الكلمات الأربعة وأسماؤها المخزّنة، ومن الاسم بترجع — واسم غريب null', () {
    expect(MealRelation.values.map((m) => m.label), ['قبل الأكل', 'مع الأكل', 'بعد الأكل', 'على معدة فاضية']);
    for (final m in MealRelation.values) {
      expect(MealRelation.fromStorage(m.storageName), m);
    }
    expect(MealRelation.emptyStomach.storageName, 'empty_stomach');
    expect(MealRelation.fromStorage('breakfast'), isNull);
    expect(MealRelation.labelOf(null), isNull);
  });

  test('متن الإشعار: الاسم — الجرعة — كلمة الأكل؛ ومن غيرها الاسم والجرعة بس', () {
    expect(reminderBodyFor([(name: 'Concor', amount: 'قرص واحد', note: 'بعد الأكل')]), 'Concor — قرص واحد — بعد الأكل');
    expect(reminderBodyFor([(name: 'Concor', amount: null, note: 'على معدة فاضية')]), 'Concor — على معدة فاضية');
    expect(reminderBodyFor([(name: 'Concor', amount: 'قرص', note: null)]), 'Concor — قرص');
    final schedule = DoseSchedule(
      id: '1',
      medicationName: 'Concor',
      timing: FixedTiming(MinuteOfDay.hm(9)),
      startDate: DateTime(2026, 8, 31),
      amountLabel: 'قرص',
      mealRelation: MealRelation.before,
    );
    expect(reminderBody(Reminder(at: DateTime(2026, 8, 31, 9), doses: [schedule])), 'Concor — قرص — قبل الأكل');
    expect(schedule.ruleLabel, 'قبل الأكل');
  });

  test('الكلمة بتتحفظ على كل جرعات الدوا وبتوصل «يومك» — والساعة ما بتتحركش', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final patientId = await PatientRepository(db).ensurePatient();
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final id = await meds.addMedicationWithDoses(
      patientId: patientId,
      name: 'Augmentin',
      timings: [FixedTiming(MinuteOfDay.hm(9)), FixedTiming(MinuteOfDay.hm(21))],
      startDate: DateTime(2026, 8, 31),
      mealRelation: MealRelation.after,
    );
    var schedules = await meds.activeSchedules(patientId);
    expect(schedules.map((s) => s.mealRelation).toSet(), {MealRelation.after});
    final before = schedules.map((s) => s.timing).toList();

    await meds.updateMealRelation(id, MealRelation.emptyStomach);
    schedules = await meds.activeSchedules(patientId);
    expect(schedules.map((s) => s.ruleLabel).toSet(), {'على معدة فاضية'});
    expect(schedules.map((s) => s.timing).toList(), before, reason: 'كلمة، مش توقيت');

    final events = DoseEventRepository(db);
    final day = DateTime(2026, 8, 31);
    await events.materializeDay(day, const ScheduleEngine().remindersForDay(schedules, day));
    final views = await events.watchDay(day).first;
    expect(views.map((v) => v.mealLabel).toSet(), {'على معدة فاضية'});

    await meds.updateMealRelation(id, null);
    expect((await events.watchDay(day).first).map((v) => v.mealLabel).toSet(), {null});
  });
}
