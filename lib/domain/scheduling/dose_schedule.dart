import '../escalation/alert_mode.dart';
import '../medication/meal_relation.dart';
import 'day_pattern.dart';
import 'minute_of_day.dart';

/// تكرار الجرعة.
enum DoseRepeat {
  /// كل يوم.
  daily,

  /// مرة واحدة بس — زي «حبتين معاً اليوم فقط».
  /// من غير النوع ده، التطبيق بيفضل يرن كل يوم على جرعة اتاخدت خلاص.
  once,
}

/// ساعة الجرعة — **ثابتة بالساعة**، ودي الطريقة الوحيدة.
///
/// كان فيه نوع تاني (مرساة + إزاحة على روتين اليوم) واتشال بقرار المالك في
/// ٢٧ سبتمبر ٢٠٢٦: الناس في مصر ما عندهاش مواعيد أكل ونوم ثابتة. علاقة
/// الجرعة بالأكل فضلت **كلمة تعليمات** ([MealRelation]) ما بتحرّكش الساعة.
final class FixedTiming {
  const FixedTiming(this.minuteOfDay);

  final MinuteOfDay minuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is FixedTiming && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay.hashCode;

  @override
  String toString() => 'FixedTiming($minuteOfDay)';
}

/// جرعة مجدولة.
class DoseSchedule {
  const DoseSchedule({
    required this.id,
    required this.medicationName,
    required this.timing,
    required this.startDate,
    this.repeat = DoseRepeat.daily,
    this.durationDays,
    this.amountLabel,
    this.alertMode,
    this.days = DayPattern.everyDay,
    this.mealRelation,
  });

  final String id;

  /// أنهي أيام (الجولة ٢) — «كل يوم» افتراضياً. الأيام بس؛ الدقيقة من [timing].
  final DayPattern days;
  final String medicationName;
  final FixedTiming timing;

  /// «قبل الأكل» وأخواتها — تعليمات تتعرض، مش توقيت. null = مفيش.
  final MealRelation? mealRelation;

  /// نوع التنبيه بتاع الدوا — null = زي إعداد الجهاز.
  final AlertMode? alertMode;

  final DoseRepeat repeat;

  /// أول يوم فعّال (بيتقارن باليوم بس، الساعة بتتجاهل).
  final DateTime startDate;

  /// عدد أيام العلاج. **null معناها مدة مفتوحة.**
  ///
  /// قاعدة ثابتة: ما نوقفش دوا من نفسنا. لو المدة مش معروفة، التذكير
  /// يفضل شغال لحد ما المستخدم يوقفه بإيده.
  final int? durationDays;

  /// نص الجرعة زي ما الطبيب كتبها — «قرص واحد»، «حبتين معاً».
  final String? amountLabel;

  DateTime get _startDay =>
      DateTime(startDate.year, startDate.month, startDate.day);

  /// آخر يوم فعّال، أو null لو المدة مفتوحة.
  DateTime? get lastActiveDay {
    if (repeat == DoseRepeat.once) return _startDay;
    final d = durationDays;
    if (d == null) return null;
    return _startDay.add(Duration(days: d - 1));
  }

  /// هل الجرعة دي شغّالة في اليوم ده؟ (`day` هو يوم الروتين، مش التقويم)
  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(_startDay)) return false;
    if (repeat == DoseRepeat.once) return d == _startDay;
    final last = lastActiveDay;
    if (last != null && d.isAfter(last)) return false;
    return dayPatternActive(days, start: _startDay, day: d);
  }

  DoseSchedule copyWith({
    String? id,
    String? medicationName,
    FixedTiming? timing,
    DoseRepeat? repeat,
    DateTime? startDate,
    int? durationDays,
    bool clearDuration = false,
    String? amountLabel,
    DayPattern? days,
    MealRelation? mealRelation,
  }) =>
      DoseSchedule(
        id: id ?? this.id,
        medicationName: medicationName ?? this.medicationName,
        timing: timing ?? this.timing,
        repeat: repeat ?? this.repeat,
        startDate: startDate ?? this.startDate,
        durationDays: clearDuration ? null : (durationDays ?? this.durationDays),
        amountLabel: amountLabel ?? this.amountLabel,
        days: days ?? this.days,
        mealRelation: mealRelation ?? this.mealRelation,
        alertMode: alertMode,
      );

  /// كلمة التعليمات جنب الجرعة — «بعد الأكل». null = مفيش حاجة تتقال.
  /// (الساعة نفسها بتتعرض من وقت الجرعة، مش من هنا.)
  String? get ruleLabel => mealRelation?.label;

  @override
  String toString() => 'DoseSchedule($medicationName، ${timing.minuteOfDay}${ruleLabel == null ? '' : '، $ruleLabel'})';
}
