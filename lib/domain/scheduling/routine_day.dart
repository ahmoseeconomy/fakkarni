// يوم الروتين — دارت نقية.
//
// **اليوم بيبدأ الساعة ٤ الفجر، ثابتة** (قرار المالك، ٢٧ سبتمبر ٢٠٢٦ — كان
// بيبدأ من ساعة الصحيان اللي المستخدم بيقولها، والروتين اتشال). جرعة الساعة
// ١ بالليل تبع قايمة امبارح وسلسلته و«اتنست» بتاعته؛ الساعة ٥ الفجر تبع
// النهارده.

import 'minute_of_day.dart';

/// الحد بين يومين — ٤:٠٠ الفجر. المكان الوحيد للرقم ده.
const MinuteOfDay dayStart = MinuteOfDay(4 * 60);

/// يوم الروتين اللي [now] واقع فيه: قبل ٤ الفجر = امبارح بالتقويم.
DateTime routineDayOf(DateTime now) {
  final startToday = DateTime(now.year, now.month, now.day, 0, dayStart.minutes);
  return now.isBefore(startToday)
      ? DateTime(now.year, now.month, now.day - 1)
      : DateTime(now.year, now.month, now.day);
}

/// **الدوا اللي بيبدأ «النهارده» بيشمل كل جرعة لسه جاية بالساعة الحقيقية —
/// وجرعة بعد نص الليل تبع يوم امبارح** (٢٦ سبتمبر ٢٠٢٦، من الجهاز: دوا اتضاف
/// ١٢:٥٠ بالليل بساعة ثابتة ١٢:٥٢ اتعرض «بكرة» وما رنّش).
///
/// `start_date` بيتقارن بيوم **الروتين** في `DoseSchedule.isActiveOn`، و«النهارده»
/// في الفورم هي تاريخ **التقويم**. بعد نص الليل وقبل ٤ الفجر الاتنين مختلفين:
/// يوم الروتين لسه امبارح، فجرعة الليلة دي كانت بتتشال. فلو المختار هو تاريخ
/// النهارده بالتقويم ويوم الروتين لسه قبله، البداية بتبقى يوم الروتين —
/// والماضي مقفول من ناحيتين تانيتين: `active_from` (لحظة الحفظ) و«الأقرب من
/// دلوقتي» في الخطة. أي تاريخ تاني بيتساب زي ما هو: «بكرة» تاريخ تقويم،
/// وبعد نص الليل يعني الليلة اللي بعد الجاية بالساعة — الفورم بيقول التاريخ.
DateTime startDayFor(DateTime chosen, DateTime now) {
  final chosenDay = DateTime(chosen.year, chosen.month, chosen.day);
  final today = DateTime(now.year, now.month, now.day);
  if (chosenDay != today) return chosenDay;
  final routineDay = routineDayOf(now);
  return routineDay.isBefore(today) ? routineDay : chosenDay;
}
