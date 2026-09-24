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
