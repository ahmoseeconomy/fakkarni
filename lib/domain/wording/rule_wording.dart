// arabic_time دارت نقية (من غير Flutter) — القاعدة ٢ سليمة.
import '../../core/format/arabic_time.dart';

/// صياغة قاعدة الجرعة — **نص، مش حساب ساعة**.
///
/// عايشة لوحدها برّه `domain/scheduling` عشان جانب الابن (اللي ممنوع
/// يستورد الجدولة — `no_scheduling_imports_test`) يعرض نفس الكلام اللي
/// المريض بيشوفه، من غير نسخة تانية ممكن تختلف. الجدولة نفسها بتستعمل
/// الملف ده (`DayAnchor.label` و`ruleLabel`).

/// أسماء المراسي بالعربي، بمفتاح اسمها المخزّن (`anchor` في drift والسحابة).
const anchorWords = <String, String>{
  'wake': 'الصحيان',
  'breakfast': 'الفطار',
  'lunch': 'الغدا',
  'dinner': 'العشا',
  'sleep': 'النوم',
};

/// «الفطار − ٣٠ د» — المرساة والإزاحة بالظبط زي ما اتسجلوا.
String anchorRuleWording(String anchorWord, int offsetMinutes) {
  if (offsetMinutes == 0) return anchorWord;
  final sign = offsetMinutes < 0 ? '−' : '+';
  return '$anchorWord $sign ${arabicNumber(offsetMinutes.abs())} د';
}

/// الساعة الثابتة — الوصف بيقول النوع بس، والساعة بتتعرض جنبه.
const fixedRuleWording = 'ساعة ثابتة';

/// المدة بالكلام — «ربع ساعة» / «نص ساعة» / «تلات أرباع ساعة» / «ساعة»
/// / «ساعتين»، وغير كده «N دقيقة» بأرقام عربية.
String spokenOffset(int minutes) => switch (minutes.abs()) {
      15 => 'ربع ساعة',
      30 => 'نص ساعة',
      45 => 'تلات أرباع ساعة',
      60 => 'ساعة',
      120 => 'ساعتين',
      final m => '${arabicNumber(m)} دقيقة',
    };

/// الجرعة بكلام طبيعي — «قبل الفطار بنص ساعة» / «بعد العشا بربع ساعة» /
/// «مع الغدا». مش «الفطار − ٣٠ د»: ده كلام الجدول، مش كلام البيت.
String spokenTimingWording(String anchorWord, int offsetMinutes) {
  if (offsetMinutes == 0) return 'مع $anchorWord';
  final side = offsetMinutes < 0 ? 'قبل' : 'بعد';
  return '$side $anchorWord ب${spokenOffset(offsetMinutes)}';
}

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
