import '../../core/format/arabic_time.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../../domain/wording/rule_wording.dart' show weekdayName;

/// رسالة الحجز للدكتور على واتساب (طلب المالك، ٢٩ سبتمبر ٢٠٢٦) — **المستخدم
/// بيشوفها وبيبعتها بنفسه**، والتطبيق ما بيبعتش حاجة.
///
/// فيها اليوم والساعة اللي **اختارهم** في «ميعاد جديد»، واسم المريض وسنّه من
/// «نتعرّف عليك» — واللي مش متسجّل ما بيتكتبش: مفيش سن مخترع، ولا اسم «أنا».
/// «ممكن أحجز» عن قصد: من غير «عايز / عايزة» — التطبيق ما بيسألش عن الجنس.
String doctorBookingMessage({
  required DateTime day,
  MinuteOfDay? time,
  String? patientName,
  int? age,
}) {
  final name = patientName?.trim();
  final when = 'يوم ${weekdayName(day.weekday)} ${arabicDate(day)}'
      '${time == null ? '' : ' الساعة ${arabicTime(DateTime(day.year, day.month, day.day, 0, time.minutes))}'}';
  return [
    'السلام عليكم،',
    'ممكن أحجز ميعاد كشف $when؟',
    if (name != null && name.isNotEmpty && name != 'أنا') 'الاسم: $name',
    if (age != null && age > 0) 'السن: ${arabicNumber(age)} سنة',
  ].join('\n');
}
