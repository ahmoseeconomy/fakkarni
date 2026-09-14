import '../../core/format/arabic_time.dart';
import '../../data/db/tables.dart';
import '../../domain/health/usual_range.dart';

/// الكلام اللي بيتقال عن رقم — **رقم ونطاق وفرق، ويقف.**
///
/// مفيش هنا «مرتفع» ولا «طبيعي» ولا «راجع دكتورك» ولا «ممكن يكون»: احنا مش
/// دكاترة (القاعدة ٦). اختبار بيقرا نصوص الشاشات ويوقع لو ظهرت كلمة نصيحة.

/// لما لسه مفيش قياسات كفاية — الرقم بيتعرض من غير أي تعليم.
const notEnoughForUsual = 'لسه ما عندناش قياسات كفاية نعرف المعتاد ليك';

/// «١٥٢» أو «٧.٦».
String arabicDecimal(num v) {
  if (v == v.roundToDouble()) return arabicNumber(v.round());
  final text = v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return arabicDigits(text);
}

String usualRangeText(UsualRange r) => r.low == r.high
    ? arabicDecimal(r.low)
    : '${arabicDecimal(r.low)}–${arabicDecimal(r.high)}';

/// «جوّه المعتاد ليك (١١٠–١٣١)» / «أعلى من أعلى قياس معتاد ليك (١٣١) بـ ٢١».
String comparisonText(UsualComparison c, UsualRange r) => switch (c) {
      WithinUsual() => 'جوّه المعتاد ليك (${usualRangeText(r)})',
      AboveUsual(:final by) => 'أعلى من أعلى قياس معتاد ليك (${arabicDecimal(r.high)}) بـ ${arabicDecimal(by)}',
      BelowUsual(:final by) => 'أقل من أقل قياس معتاد ليك (${arabicDecimal(r.low)}) بـ ${arabicDecimal(by)}',
    };

extension GlucoseContextWords on GlucoseContext {
  String get label => switch (this) {
        GlucoseContext.fasting => 'صايم',
        GlucoseContext.afterMeal => 'بعد الأكل',
      };
}

/// الكلمات اللي **ممنوع** تظهر في نصوص شاشات السكر والتحاليل — نصيحة أو
/// تشخيص أو حكم. الاختبارات بتقرا الشاشات بيها.
const adviceWords = [
  'يُفضّل', 'يفضّل', 'يفضل', 'الأفضل',
  'راجع دكتور', 'راجع الدكتور', 'راجع طبيب', 'استشر', 'دكتورك', 'فوراً', 'فورا',
  'ممكن يكون', 'قد يكون', 'يدل على', 'تشخيص',
  'مرتفع', 'منخفض', 'طبيعي', 'خطر', 'خطير', 'مقلق',
  'ننصح', 'نصيحة', 'لازم تروح', 'المرجعي',
  'high', 'low', 'normal', 'abnormal',
];
