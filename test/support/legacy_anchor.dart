// **للاختبارات بس** — مراسي الروتين القديم كأداة تثبيت.
//
// الروتين والمراسي اتشالوا من التطبيق (٢٧ سبتمبر ٢٠٢٦)؛ الاختبارات القديمة
// كانت بتكتب جرعاتها «قبل الفطار بنص ساعة» على روتين ثابت واحد (الصحيان ٧،
// الفطار ٧:٣٠، الغدا ٢:٣٠، العشا ٨، النوم ١١:٣٠) وبتتوقّع الساعات الناتجة.
// الدالة دي بتحسب نفس الساعة بالحرف، فالتوقّعات القديمة بتفضل صح — وأي
// اختبار جديد يكتب `FixedTiming(MinuteOfDay.hm(…))` على طول.
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

enum DayAnchor { wake, breakfast, lunch, dinner, sleep }

const Map<DayAnchor, int> testRoutineMinutes = {
  DayAnchor.wake: 7 * 60,
  DayAnchor.breakfast: 7 * 60 + 30,
  DayAnchor.lunch: 14 * 60 + 30,
  DayAnchor.dinner: 20 * 60,
  DayAnchor.sleep: 23 * 60 + 30,
};

/// «المرساة + الإزاحة» على روتين الاختبارات → ساعة ثابتة.
// ignore: non_constant_identifier_names
FixedTiming AnchorTiming(DayAnchor anchor, [int offsetMinutes = 0]) =>
    FixedTiming(MinuteOfDay((testRoutineMinutes[anchor]! + offsetMinutes + 1440) % 1440));

/// الإزاحة الافتراضية «قبل» اللي كانت في التطبيق: ٣٠ قبل الأكل، ١٥ قبل النوم.
int defaultOffsetBefore(DayAnchor anchor) => anchor == DayAnchor.sleep ? 15 : 30;
