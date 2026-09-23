// **مستخرَج من `lib/features/care/caregiver_words.dart` في حزمة التطبيق.**
//
// الملف الأصلي بيستورد طبقة البيانات، فمينفعش يتنسخ كامل — الدوال دي
// بتعتمد على `arabicNumber` وبس. تعديل هناك بيتنقل هنا بالإيد.

import 'arabic_time.dart';

// العربي بيعدّ تلات صيغ (واحد، اتنين، جمع)، والكسر بينهم بيخلّي الجملة
// تقرا غلط. الصيغ هنا مكتوبة بالإيد لكل وحدة بدل قاعدة عامة بتغلط.
String _count(int n, String one, String two, String few, String many) => switch (n) {
      1 => one,
      2 => two,
      >= 3 && <= 10 => '${arabicNumber(n)} $few',
      _ => '${arabicNumber(n)} $many',
    };

/// «من ٣ ساعات» — للي عدّى.
///
/// بتتحسب بالأيام التقويمية مش بالضرب في ٢٤ ساعة: مصر بتغيّر الساعة،
/// و«من يومين» المفروض تعدّ أيام مش ساعات.
String timeSince(DateTime from, DateTime at) {
  final minutes = from.difference(at).inMinutes;
  if (minutes < 1) return 'دلوقتي';
  if (minutes < 60) {
    return 'من ${_count(minutes, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة')}';
  }
  final days = DateTime(from.year, from.month, from.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days == 0) {
    final hours = minutes ~/ 60;
    return 'من ${_count(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
  }
  if (days == 1) return 'من امبارح';
  return 'من ${_count(days, 'يوم', 'يومين', 'أيام', 'يوم')}';
}
