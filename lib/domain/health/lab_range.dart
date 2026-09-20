// نطاق التحليل — **زي ما هو مطبوع على ورقة المعمل، مش من عندنا**.
//
// مفيش هنا — ولا في أي مكان تاني في التطبيق — جدول قيم طبيعية. النطاقات
// بتختلف من معمل لمعمل وبطريقة التحليل وبالسن والنوع، واختراع واحد يبقى
// كلام دكتور (القاعدة ٦). اللي بنعمله حاجة واحدة: بنقارن رقمين **الاتنين
// مطبوعين على نفس الورقة**. سطر الورقة ما فيهوش نطاق = رقم من غير أي علامة.
//
// دارت نقية — من غير Flutter ولا قاعدة بيانات — زي باقي `domain/`.

/// النطاق زي ما هو مكتوب على الورقة.
///
/// [low]/[high] للنطاق الرقمي (واحد منهم ممكن يكون null: «لحد ١١»، «من ٤»)،
/// و[text] للنطاق المطبوع اللي مش رقم أصلاً — «Negative»، «< 5». الاتنين
/// بدايل: لو فيه رقم بنقارن، ولو فيه نص بس بنعرضه زي ما هو **وما بنقارنش**.
class LabRange {
  const LabRange({this.low, this.high, this.text});

  final double? low;
  final double? high;

  /// نطاق مطبوع مش رقمي — بيتعرض بالحرف وعمره ما بيتقارن.
  final String? text;

  bool get isEmpty => low == null && high == null && (text == null || text!.trim().isEmpty);

  /// ينفع نقارن بيه؟ لازم رقم واحد على الأقل، ولو الاتنين موجودين لازم
  /// يكونوا بالترتيب. ورقة مكتوب فيها نطاق مقلوب مش بنصلّحها — بنعرضها
  /// زي ما هي ومش بنحكم بيها.
  bool get comparable {
    final l = low, h = high;
    if (l == null && h == null) return false;
    return l == null || h == null || l <= h;
  }

  /// عرض النطاق — null لو طرف واحد بس مطبوع.
  double? get width => low != null && high != null ? high! - low! : null;
}

/// «قريب من الحد» — **مساعدة عرض من عندنا، مش طب**.
///
/// القاعدة، مكتوبة مرة واحدة هنا: الرقم بيتحسب قريب لو بعده عن أي طرف من
/// أطراف النطاق أقل من أو يساوي **١٠٪ من عرض النطاق نفسه**. النسبة من عرض
/// الورقة، مش رقم مطلق، فهي بتتمدّ وتقصر مع نطاق كل تحليل لوحده.
///
/// محتاجة **الطرفين** عشان يبقى فيه عرض أصلاً: نطاق من طرف واحد («لحد ١١»)
/// بياخد جوّه/برّه وبس. وعمرها ما بتتقال كنتيجة — الكلمة هي «قريب من الحد»
/// ولا حاجة غيرها.
const double nearBoundaryFraction = 0.10;

/// الرقم اللي على حافة الهامش بالظبط — والحافة نفسها مش بتتقاس بالظبط في
/// الـfloat: ٤.٧ − ٤ بتطلع ٠.٧٠٠٠٠٠٠٠٠٠٠٠٠٠٠٢ و٧ × ٠.١ بتطلع
/// ٠.٧٠٠٠٠٠٠٠٠٠٠٠٠٠٠١، فرقم مكتوب على الورقة على الحافة بالظبط كان بيقع
/// برّه الهامش **بخطأ تمثيل، مش بقرار**. الهامش الضئيل ده بيخلي القرار
/// بالقاعدة المكتوبة فوق؛ واتجاهه مقصود — اللي على الحافة يتحسب «قريب».
const double _edgeTolerance = 1e-9;

/// نتيجة المقارنة — خمس حالات، تلاتة منهم بس بيتعلّموا على الشاشة.
sealed class LabFlag {
  const LabFlag();
}

/// الورقة ما طبعتش نطاق للسطر ده — رقم عادي من غير علامة، والشاشة بتقول كده.
final class NoPrintedRange extends LabFlag {
  const NoPrintedRange();
}

/// نطاق مطبوع بس مش رقم — بيتعرض بالحرف وما بيتقارنش.
final class RangeNotNumeric extends LabFlag {
  const RangeNotNumeric();
}

final class InsideRange extends LabFlag {
  const InsideRange();
}

/// جوّه النطاق وقريب من طرف — [nearBoundaryFraction].
final class NearBoundary extends LabFlag {
  const NearBoundary();
}

final class AboveRange extends LabFlag {
  const AboveRange();
}

final class BelowRange extends LabFlag {
  const BelowRange();
}

/// بيقارن رقم مطبوع بنطاق مطبوع. مفيش هنا أي رقم من عندنا غير نسبة العرض.
LabFlag labFlagFor(double value, LabRange? range) {
  if (range == null || range.isEmpty) return const NoPrintedRange();
  if (!range.comparable) return const RangeNotNumeric();

  final low = range.low, high = range.high;
  if (high != null && value > high) return const AboveRange();
  if (low != null && value < low) return const BelowRange();

  final width = range.width;
  if (width != null) {
    final margin = width * nearBoundaryFraction;
    if (value - low! <= margin + margin * _edgeTolerance ||
        high! - value <= margin + margin * _edgeTolerance) {
      return const NearBoundary();
    }
  }
  return const InsideRange();
}

/// بيتعلّم على الشاشة وفي الملف؟ (جوّه النطاق ما بياخدش أي لون ولا كلمة)
bool isFlagged(LabFlag flag) => flag is AboveRange || flag is BelowRange || flag is NearBoundary;
