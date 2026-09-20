import '../../core/format/arabic_time.dart';
import '../../data/db/tables.dart';
import '../../domain/health/lab_range.dart';
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

/// ===================================================== نطاق ورقة المعمل
///
/// كلمة مع كل علامة، مش لون بس: الملف بيتطبع وبيتصوّر أبيض وأسود، واللون
/// لوحده بيختفي هناك — وبيختفي كمان عند حد ما بيفرّقش الألوان. الكلمات
/// تلاتة وبس، ومفيش رابعة: مفيش «يعني إيه» ولا «اعمل إيه» ولا «قد إيه ده
/// مستعجل» (القاعدة ٦).

const labAboveWord = 'فوق المعدل';
const labBelowWord = 'تحت المعدل';
const labNearWord = 'قريب من الحد';

/// الكلمة اللي بتتكتب جنب الرقم، أو null لو مفيش علامة.
String? labFlagWord(LabFlag flag) => switch (flag) {
      AboveRange() => labAboveWord,
      BelowRange() => labBelowWord,
      NearBoundary() => labNearWord,
      InsideRange() || NoPrintedRange() || RangeNotNumeric() => null,
    };

/// الورقة ما طبعتش نطاق للسطر ده — بيتقال بصراحة بدل ما الرقم يقعد من غير
/// سياق والواحد يفتكر إحنا اللي سكتنا.
const labNoRangeText = 'الورقة ما فيهاش نطاق للتحليل ده';

/// «نطاق الورقة: من ٤ إلى ١١» / «أقل من ٢٠٠» / «أكتر من ٤٠» / النص المطبوع.
///
/// بنقول «نطاق الورقة» عن قصد: النطاق بتاع المعمل اللي طبع الورقة، مش
/// بتاعنا، والجملة نفسها بتقول كده كل مرة.
///
/// **والنطاق من طرف واحد بيتقال زي ما الورقة بتقوله**: «أقل من ٥»،
/// «أكتر من ٤٠». كان بيتكتب «من ٤٠» لوحدها، ودي بتتقري كجملة مقطوعة —
/// الواحد بيستنى «إلى كام» وما بيلاقيهاش، فيفتكر إن الشاشة بلعت نص
/// النطاق. وساعات يكون ده اللي حصل فعلاً (شوف [LabLine.range])، فالصياغة
/// الواضحة هي اللي بتخلي النقص ده **يبان** بدل ما يعدّي.
String? labRangeText(LabRange? range) {
  if (range == null || range.isEmpty) return null;
  final low = range.low, high = range.high;
  final body = switch ((low, high)) {
    (final l?, final h?) => 'من ${arabicDecimal(l)} إلى ${arabicDecimal(h)}',
    (final l?, null) => 'أكتر من ${arabicDecimal(l)}',
    (null, final h?) => 'أقل من ${arabicDecimal(h)}',
    _ => range.text!.trim(),
  };
  return 'نطاق الورقة: $body';
}

/// سطر واحد تحت قسم التحاليل — في الشاشة وفي الملف.
const labRangeFooter = 'النطاقات دي مكتوبة على ورق المعمل نفسه، والدكتور هو اللي بيقراها.';

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
