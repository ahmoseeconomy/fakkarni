import '../domain/escalation/alert_mode.dart';
import '../domain/scheduling/day_routine.dart';
import '../domain/scheduling/day_pattern.dart';
import '../domain/scheduling/dose_schedule.dart';
import 'db/app_database.dart';
import 'db/tables.dart';

/// تحويل صفوف drift لكائنات الدومين.
///
/// الاتجاه ده في اتجاه واحد بس مقصود: `lib/domain/` عمره ما بيعرف إن فيه
/// قاعدة بيانات أصلاً، وده اللي بيخلي المحرك يتختبر في أقل من ثانية.

DayRoutine routineFromRow(DayRoutineRow row) => DayRoutine(
      wake: MinuteOfDay(row.wakeMinutes),
      breakfast: MinuteOfDay(row.breakfastMinutes),
      lunch: MinuteOfDay(row.lunchMinutes),
      dinner: MinuteOfDay(row.dinnerMinutes),
      sleep: MinuteOfDay(row.sleepMinutes),
      unset: unsetAnchorsFromText(row.unsetAnchors),
    );

/// العلم على الصف: أسامي المراسي مفصولة بفاصلة. اسم غريب بيتعدّى — صف
/// من نسخة أحدث ما ينفعش يوقّع القراية.
Set<DayAnchor> unsetAnchorsFromText(String text) => {
      for (final name in text.split(','))
        for (final a in DayAnchor.values)
          if (a.name == name.trim()) a,
    };

String unsetAnchorsToText(Set<DayAnchor> unset) =>
    [for (final a in DayAnchor.values) if (unset.contains(a)) a.name].join(',');

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

/// بيرجّع نوع التوقيت من الصف وصف الساعة الثابتة (لو موجود).
///
/// صف نوعه `fixed` من غير ساعة، أو نوعه `anchor` من غير مرساة، معناه إن
/// حاجة اتكسرت في الكتابة — بنرمي بدل ما نخمّن معاد دوا.
DoseTiming timingFromRow(DoseScheduleRow row, FixedTimingRow? fixed) =>
    switch (row.timingKind) {
      DoseTimingKind.anchor => AnchorTiming(
          row.anchor ??
              (throw StateError('جرعة ${row.id} مرساة من غير مرساة')),
          row.offsetMinutes ?? 0,
        ),
      DoseTimingKind.fixed => FixedTiming(
          MinuteOfDay(
            fixed?.minuteOfDay ??
                (throw StateError('جرعة ${row.id} ساعة ثابتة من غير ساعة')),
          ),
        ),
    };
