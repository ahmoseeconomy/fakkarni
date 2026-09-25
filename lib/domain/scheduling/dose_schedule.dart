import 'day_pattern.dart';
import '../escalation/alert_mode.dart';
import '../wording/rule_wording.dart';
import 'day_routine.dart';

/// تكرار الجرعة.
enum DoseRepeat {
  /// كل يوم.
  daily,

  /// مرة واحدة بس — زي «حبتين معاً اليوم فقط».
  /// من غير النوع ده، التطبيق بيفضل يرن كل يوم على جرعة اتاخدت خلاص.
  once,
}

/// إمتى الجرعة بتتاخد.
///
/// نوعين بس، والافتراضي هو [AnchorTiming]: الروشتة بتقول «قبل الفطار»
/// والجرعة بتتحرك مع يوم المريض. [FixedTiming] هو المخرج الثانوي — لدوا
/// الدكتور قال عليه «الساعة ٨ بالظبط» — وبيتعرض دايماً بعد المراسي، مش
/// قبلها، وبيتقال عليه صراحة إنه مش هيتحرك مع الروتين.
sealed class DoseTiming {
  const DoseTiming();

  /// وصف القاعدة بالعربي — «الفطار − ٣٠ د» أو «ساعة ثابتة».
  String get ruleLabel;
}

/// مرساة + إزاحة — الطريقة الأصلية والافتراضية.
///
/// `{anchor: breakfast, offsetMinutes: -30}` مش `{time: "07:00"}`. الساعة
/// بتتحسب وقت العرض من روتين المريض، فتغيير معاد الفطار بيحرّكها لوحدها.
final class AnchorTiming extends DoseTiming {
  const AnchorTiming(this.anchor, [this.offsetMinutes = 0]);

  final DayAnchor anchor;

  /// بالسالب = قبل المرساة، بالموجب = بعدها.
  final int offsetMinutes;

  @override
  String get ruleLabel => anchorRuleWording(anchor.label, offsetMinutes);

  @override
  bool operator ==(Object other) =>
      other is AnchorTiming &&
      other.anchor == anchor &&
      other.offsetMinutes == offsetMinutes;

  @override
  int get hashCode => Object.hash(anchor, offsetMinutes);

  @override
  String toString() => 'AnchorTiming($ruleLabel)';
}

/// ساعة ثابتة — **ما بتتحركش** مع روتين اليوم.
///
/// الاستثناء الموثّق للقاعدة، مش بديل ليها. الجرعة دي بتفضل في نفس الساعة
/// لو المريض غيّر فطاره أو دخل رمضان، وده اللي المستخدم اختاره عن قصد.
final class FixedTiming extends DoseTiming {
  const FixedTiming(this.minuteOfDay);

  final MinuteOfDay minuteOfDay;

  /// الساعة نفسها بتتعرض جنبه من وقت الجرعة — الوصف هنا بيقول النوع بس.
  @override
  String get ruleLabel => fixedRuleWording;

  @override
  bool operator ==(Object other) =>
      other is FixedTiming && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay.hashCode;

  @override
  String toString() => 'FixedTiming($minuteOfDay)';
}

/// جرعة مجدولة.
///
/// مهم: الجرعة متخزّنة كـ[DoseTiming] — مرساة + إزاحة افتراضياً، أو ساعة
/// ثابتة لو المستخدم طلبها صراحة. ولما المستخدم يعدّل معاد فطاره، أو يدخل
/// رمضان، جرعات المراسي بتتحرك لوحدها والساعات الثابتة بتفضل مكانها.
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
  });

  final String id;

  /// أنهي أيام (الجولة ٢) — «كل يوم» افتراضياً. الأيام بس؛ الدقيقة من [timing].
  final DayPattern days;
  final String medicationName;
  final DoseTiming timing;

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
    DoseTiming? timing,
    DoseRepeat? repeat,
    DateTime? startDate,
    int? durationDays,
    bool clearDuration = false,
    String? amountLabel,
    DayPattern? days,
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
      );

  /// وصف القاعدة بالعربي — «الفطار − ٣٠ د».
  /// بنعرضه للمستخدم بدل الساعة، عشان يفهم إن الجرعة مربوطة بيومه.
  String get ruleLabel => timing.ruleLabel;

  @override
  String toString() => 'DoseSchedule($medicationName، $ruleLabel)';
}
