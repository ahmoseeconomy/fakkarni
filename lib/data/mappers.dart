import '../domain/scheduling/day_routine.dart';
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
    );

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
    );

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
