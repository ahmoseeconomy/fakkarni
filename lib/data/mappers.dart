import '../domain/escalation/alert_mode.dart';
import '../domain/medication/meal_relation.dart';
import '../domain/scheduling/minute_of_day.dart';
import '../domain/scheduling/day_pattern.dart';
import '../domain/scheduling/dose_schedule.dart';
import 'db/app_database.dart';

/// تحويل صفوف drift لكائنات الدومين.
///
/// الاتجاه ده في اتجاه واحد بس مقصود: `lib/domain/` عمره ما بيعرف إن فيه
/// قاعدة بيانات أصلاً، وده اللي بيخلي المحرك يتختبر في أقل من ثانية.

DoseSchedule doseScheduleFromRow(
  DoseScheduleRow row,
  MedicationRow med, {
  FixedTimingRow? fixed,
}) =>
    DoseSchedule(
      id: row.id.toString(),
      medicationName: med.name,
      timing: timingFromRow(row, fixed),
      repeat: row.repeat,
      startDate: row.startDate,
      durationDays: row.durationDays,
      amountLabel: med.amountLabel,
      alertMode: AlertMode.fromStorage(med.alertMode),
      days: dayPatternFromRow(row),
      mealRelation: MealRelation.fromStorage(row.mealRelation),
    );

/// النمط من أعمدة v29 — كلهم null = «كل يوم». قيمة برّه الحدود (صف اتكتب
/// غلط) بترجع «كل يوم» بدل ما توقّع الجدولة: الجرعة ترن أكتر أحسن من ما ترنش.
DayPattern dayPatternFromRow(DoseScheduleRow row) {
  try {
    if (row.weekdaysMask case final m? when m > 0) return OnWeekdays.fromMask(m);
    if (row.everyDays case final n?) return EveryNDays(n);
    if ((row.cycleOn, row.cycleOff) case (final on?, final off?)) return OnOffCycle(on, off);
  } catch (_) {}
  return DayPattern.everyDay;
}

/// أعمدة v29 من النمط — للكتابة.
({int? weekdaysMask, int? everyDays, int? cycleOn, int? cycleOff}) dayPatternColumns(DayPattern p) => switch (p) {
      EveryDay() => (weekdaysMask: null, everyDays: null, cycleOn: null, cycleOff: null),
      OnWeekdays() => (weekdaysMask: p.mask, everyDays: null, cycleOn: null, cycleOff: null),
      EveryNDays(:final days) => (weekdaysMask: null, everyDays: days, cycleOn: null, cycleOff: null),
      OnOffCycle(:final on, :final off) => (weekdaysMask: null, everyDays: null, cycleOn: on, cycleOff: off),
    };

/// ساعة الجرعة من صف `fixed_timings` بتاعها.
///
/// صف جرعة من غير ساعة معناه إن حاجة اتكسرت في الكتابة (أو ترحيل ما
/// كملش) — بنرمي بدل ما نخمّن معاد دوا.
FixedTiming timingFromRow(DoseScheduleRow row, FixedTimingRow? fixed) => FixedTiming(
      MinuteOfDay(
        fixed?.minuteOfDay ?? (throw StateError('جرعة ${row.id} من غير ساعة')),
      ),
    );
