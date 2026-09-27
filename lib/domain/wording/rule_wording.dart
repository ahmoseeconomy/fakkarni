// arabic_time دارت نقية (من غير Flutter) — القاعدة ٢ سليمة.
import '../../core/format/arabic_time.dart';
import '../medication/meal_relation.dart';

/// صياغة قاعدة الجرعة — **نص، مش حساب ساعة**.
///
/// عايشة لوحدها برّه `domain/scheduling` عشان جانب الابن (اللي ممنوع
/// يستورد الجدولة — `no_scheduling_imports_test`) يعرض نفس الكلام اللي
/// المريض بيشوفه، من غير نسخة تانية ممكن تختلف.

/// كلمة الأكل جنب الجرعة من اسمها المخزّن (`meal_relation` في drift
/// والسحابة) — «قبل الأكل» / «مع الأكل» / «بعد الأكل» / «على معدة فاضية».
/// تعليمات تتقال، **مش توقيت**. null = مفيش. جانب الابن بيقراها من هنا.
String? mealRelationLabel(String? storageName) => MealRelation.labelOf(storageName);

/// «الساعة ٩:٠٠ م» — الثابتة بساعتها.
String spokenFixedWording(String time) => 'الساعة $time';

/// «كل ساعتين» / «كل ٣ ساعات» / «كل ١٢ ساعة».
String everyHoursLabel(int hours) => switch (hours) {
      2 => 'كل ساعتين',
      <= 10 => 'كل ${arabicNumber(hours)} ساعات',
      _ => 'كل ${arabicNumber(hours)} ساعة',
    };

/// «هتاخده الساعة: ٨:٠٠ ص، ١٢:٠٠ م، ٤:٠٠ م…» — المعاينة قبل الحفظ.
String everyHoursPreview(List<DateTime> times) =>
    'هتاخده الساعة: ${times.map(arabicTime).join('، ')}';

// ---------------------------------------------------------------- أنماط الأيام

/// أسامي الأيام بالترتيب المصري — السبت الأول.
const List<(int, String)> weekdayNamesSatFirst = [
  (DateTime.saturday, 'السبت'),
  (DateTime.sunday, 'الحد'),
  (DateTime.monday, 'الاتنين'),
  (DateTime.tuesday, 'التلات'),
  (DateTime.wednesday, 'الأربع'),
  (DateTime.thursday, 'الخميس'),
  (DateTime.friday, 'الجمعة'),
];

String weekdayName(int weekday) => weekdayNamesSatFirst.firstWhere((e) => e.$1 == weekday).$2;

/// «السبت والتلات والخميس» / «يوم ويوم» / «كل ٣ أيام» / «٢١ يوم وراحة ٧».
/// من الأعمدة نفسها — عشان جانب الابن يقراها من غير ما يستورد الجدولة.
/// null = «كل يوم» (مفيش حاجة تتقال).
String? dayPatternWording({int? weekdaysMask, int? everyDays, int? cycleOn, int? cycleOff}) {
  if (weekdaysMask case final m? when m > 0) {
    final days = [for (final (d, name) in weekdayNamesSatFirst) if (m & (1 << (d - 1)) != 0) name];
    if (days.length == 7) return null;
    return days.join(' و');
  }
  if (everyDays case final n?) {
    return switch (n) {
      2 => 'يوم ويوم',
      <= 10 => 'كل ${arabicNumber(n)} أيام',
      _ => 'كل ${arabicNumber(n)} يوم',
    };
  }
  if ((cycleOn, cycleOff) case (final on?, final off?)) {
    return '${arabicNumber(on)} يوم وراحة ${arabicNumber(off)}';
  }
  return null;
}

/// «الأيام الجاية: السبت ٢٧، التلات ٣٠، …» — المعاينة قبل الحفظ.
String nextDaysPreview(List<DateTime> days) =>
    'الأيام الجاية: ${days.map((d) => '${weekdayName(d.weekday)} ${arabicNumber(d.day)}').join('، ')}';
