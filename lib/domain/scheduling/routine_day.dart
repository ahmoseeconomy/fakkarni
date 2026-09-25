// يوم الروتين — دارت نقية.
//
// اليوم بيبدأ من الصحيان مش من نص الليل (شوف `schedule_engine.dart`):
// واحد بيصحى ٧:٣٠ ولسه صاحي الساعة ١٢:٥٠ بالليل لسه في يوم امبارح.

import 'day_routine.dart';

/// يوم الروتين اللي [now] واقع فيه: قبل الصحيان = امبارح بالتقويم.
DateTime routineDayOf(DayRoutine routine, DateTime now) {
  final wakeToday = DateTime(now.year, now.month, now.day, 0, routine.wake.minutes);
  return now.isBefore(wakeToday)
      ? DateTime(now.year, now.month, now.day - 1)
      : DateTime(now.year, now.month, now.day);
}

/// **الدوا اللي بيبدأ «النهارده» بيشمل كل جرعة لسه جاية بالساعة الحقيقية —
/// وجرعة بعد نص الليل تبع يوم امبارح** (٢٦ سبتمبر ٢٠٢٦، من الجهاز: دوا اتضاف
/// ١٢:٥٠ بالليل بساعة ثابتة ١٢:٥٢ اتعرض «بكرة» وما رنّش).
///
/// `start_date` بيتقارن بيوم **الروتين** في `DoseSchedule.isActiveOn`، و«النهارده»
/// في الفورم هي تاريخ **التقويم**. بعد نص الليل وقبل الصحيان الاتنين مختلفين:
/// يوم الروتين لسه امبارح، فجرعة الليلة دي كانت بتتشال. فلو المختار هو تاريخ
/// النهارده بالتقويم ويوم الروتين لسه قبله، البداية بتبقى يوم الروتين —
/// والماضي مقفول من ناحيتين تانيتين: `active_from` (لحظة الحفظ) و«الأقرب من
/// دلوقتي» في الخطة. أي تاريخ تاني بيتساب زي ما هو: «بكرة» تاريخ تقويم،
/// وبعد نص الليل يعني الليلة اللي بعد الجاية بالساعة — الفورم بيقول التاريخ.
DateTime startDayFor(DayRoutine routine, DateTime chosen, DateTime now) {
  final chosenDay = DateTime(chosen.year, chosen.month, chosen.day);
  final today = DateTime(now.year, now.month, now.day);
  if (chosenDay != today) return chosenDay;
  final routineDay = routineDayOf(routine, now);
  return routineDay.isBefore(today) ? routineDay : chosenDay;
}
