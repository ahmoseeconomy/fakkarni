import 'package:drift/drift.dart';

/// بيخزّن تاريخ من غير ساعة كنص `YYYY-MM-DD`.
///
/// مقصود إننا مش بنستخدم تخزين drift الافتراضي (ملي ثانية UTC) للأعمدة دي.
/// [DoseSchedule.isActiveOn] بيقارن `DateTime` مقارنة تامة — بتشمل `isUtc` —
/// فلو التاريخ راح UTC ورجع، جرعة «اليوم فقط» بتبوظ بالسكوت، والتوقيت الصيفي
/// ممكن يزحلق اليوم كله. النص بيرجّع دايماً `DateTime(y, m, d)` محلّي
/// وبنص الليل بالظبط — نفس اللي المحرك بيعمله.
class DateOnlyConverter extends TypeConverter<DateTime, String> {
  const DateOnlyConverter();

  @override
  DateTime fromSql(String fromDb) {
    final parts = fromDb.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  @override
  String toSql(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
