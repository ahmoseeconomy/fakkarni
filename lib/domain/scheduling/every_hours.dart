import 'day_routine.dart';

/// **«كل كام ساعة» — مش نوع جدولة جديد.** بيتفرد لـ٢٤÷ن جرعة بساعة ثابتة
/// في اليوم، بالظبط زي «ساعة محددة» النهارده: كل جرعة جدول لوحده، صف واحد
/// في يوم الروتين، ونفس المحرّك والسلّم والأرقام.
///
/// **قواسم ٢٤ بس** (٢/٣/٤/٦/٨/١٢): «كل ٥ ساعات» بتلف على اليوم وبتغيّر
/// ساعاتها كل يوم، ودي محتاجة مفتاح أحداث تاني — برّه الجولة دي
/// (`docs/schedule_patterns_audit.md` §٤ب).
const List<int> everyHoursChoices = [2, 3, 4, 6, 8, 12];

/// الساعات من أول جرعة، كل [hours] ساعة، لحد ما اليوم يلف.
List<MinuteOfDay> everyHoursTimes(MinuteOfDay first, int hours) {
  if (!everyHoursChoices.contains(hours)) {
    throw ArgumentError.value(hours, 'hours', 'لازم يقسم ٢٤');
  }
  return [
    for (var k = 0; k < 24 ~/ hours; k++) MinuteOfDay((first.minutes + k * hours * 60) % 1440),
  ];
}

/// الساعات دي «كل كام ساعة»؟ بيرجّع ن لو المسافات كلها متساوية وبتقسم ٢٤.
/// المحرّر بيستعملها عشان يفتح على نفس الإعداد.
int? everyHoursOf(List<MinuteOfDay> times) {
  if (times.length < 2 || 24 % times.length != 0) return null;
  final hours = 24 ~/ times.length;
  if (!everyHoursChoices.contains(hours)) return null;
  final sorted = [for (final t in times) t.minutes]..sort();
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] - sorted[i - 1] != hours * 60) return null;
  }
  return hours;
}
