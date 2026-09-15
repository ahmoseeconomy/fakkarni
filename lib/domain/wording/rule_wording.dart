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
