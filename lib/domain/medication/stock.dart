// **مخزون الدوا** (٢٥ سبتمبر ٢٠٢٦) — دارت نقية.
//
// درس التطبيق القديم بتاع الشركة، مكتوب عشان ما يتكررش: كان بيحسب المخزون
// من جديد «الجرعات الفاضلة × الجرعة» وبيمسح اللي المستخدم كتبه، وتنبيه
// «قرب يخلص» ما كانش بيرن عند ناس كتير. هنا:
//   * المخزون **اختياري** ورقم الإنسان هو الأصل — بيتغيّر بس بتأكيد جرعة
//     (أو «اشتريت علبة جديدة»)، وعمره ما بيتحسب من الجدول.
//   * بينقص **بس** لما جرعة تتأكّد «اتاخدت»، بمقدار الجرعة (١ لو مش
//     معروفة)، وبيرجع لو التأكيد اتلغى. الفايتة والمتخطّية ما بتنقّصش،
//     وعمره ما ينزل تحت الصفر.
//   * «قرب يخلص» = اللي فاضل يكفّي ≤ N يوم (افتراضي ٥) من **الجدول
//     الحالي**: عدد جرعات اليوم × الجرعة — مش تخمين.

/// افتراضي «قرب يخلص» — بيتغيّر لكل دوا.
const int defaultRefillWarnDays = 5;

/// كل قد إيه التنبيه بيتكرر وهو لسه قرب يخلص.
const Duration refillRepeatEvery = Duration(days: 3);

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

String _westernDigits(String s) {
  final out = StringBuffer();
  for (final ch in s.split('')) {
    final i = _arabicDigits.indexOf(ch);
    out.write(i >= 0 ? '$i' : (ch == '٫' || ch == ',' ? '.' : ch));
  }
  return out.toString();
}

/// **الجرعة بالرقم** من كلام الجرعة: «قرص واحد» ١، «نص قرص» ٠٫٥، «قرصين» ٢،
/// «٢ قرص» ٢، «١٠ نقط» ١٠. مش مفهومة أو فاضية = ١ (القاعدة: الافتراضي ١،
/// مش تخمين أكبر).
double doseAmountOf(String? amountLabel) {
  final raw = amountLabel?.trim() ?? '';
  if (raw.isEmpty) return 1;
  final western = _westernDigits(raw);
  final number = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(western);
  if (number != null) {
    final v = double.parse(number.group(1)!);
    return v > 0 ? v : 1;
  }
  if (raw.contains('ربع')) return 0.25;
  if (raw.contains('نص') || raw.contains('نصف')) return 0.5;
  if (raw.contains('تلاتة') || raw.contains('ثلاثة') || raw.contains('تلات ')) return 3;
  // المثنّى: «قرصين» / «كبسولتين» / «معلقتين» / «اتنين»
  // (مش أي كلمة آخرها «ين» — «فيتامين» مش اتنين)
  if (raw.contains('اتنين') || raw.contains('اثنين') || raw.contains('قرصين') || RegExp(r'\Sتين(\s|$)').hasMatch(raw)) {
    return 2;
  }
  return 1;
}

/// الوحدة من كلام الجرعة — وإلا «وحدة».
String stockUnitOf(String? amountLabel) {
  final raw = amountLabel ?? '';
  if (raw.contains('كبسول')) return 'كبسولة';
  if (raw.contains('قرص') || raw.contains('أقراص') || raw.contains('حباي') || raw.contains('حبة')) return 'قرص';
  if (raw.contains('ملعق') || raw.contains('معلق')) return 'ملعقة';
  if (raw.contains('نقط') || raw.contains('نقطة')) return 'نقط';
  if (raw.contains('حقن')) return 'حقنة';
  return 'وحدة';
}

/// المخزون بعد جرعة اتاخدت — عمره ما ينزل تحت الصفر.
double stockAfterTaken(double stock, double amount) => (stock - amount).clamp(0, double.infinity).toDouble();

/// المخزون لو التأكيد اتلغى.
double stockAfterUndo(double stock, double amount) => stock + amount;

/// **فاضله كام يوم** من الجدول الحالي. null = مفيش جدول يومي يتحسب منه
/// (مفيش جرعات شغّالة) — ساعتها مفيش «قرب يخلص» أصلاً.
int? stockDaysLeft({required double stock, required int dosesPerDay, required double amount}) {
  if (dosesPerDay <= 0 || amount <= 0) return null;
  return (stock / (dosesPerDay * amount)).floor();
}

/// «قرب يخلص»؟
bool stockIsLow({required int? daysLeft, required int warnDays}) => daysLeft != null && daysLeft <= warnDays;

String _arabic(num n) {
  final text = n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);
  return text.split('').map((c) => c == '.' ? '٫' : (int.tryParse(c) == null ? c : _arabicDigits[int.parse(c)])).join();
}

/// «كونكور فاضله ٤ أيام» / «فاضله يوم واحد» / «فاضله أقل من يوم» / «خلص».
String stockLowLine(String name, {required double stock, required int daysLeft}) {
  if (stock <= 0) return '$name خلص';
  return switch (daysLeft) {
    0 => '$name فاضله أقل من يوم',
    1 => '$name فاضله يوم واحد',
    2 => '$name فاضله يومين',
    _ when daysLeft <= 10 => '$name فاضله ${_arabic(daysLeft)} أيام',
    _ => '$name فاضله ${_arabic(daysLeft)} يوم',
  };
}

/// «معاك ٢٠ قرص — تكفّي ١٠ أيام» (من غير «تكفّي» لو مفيش جدول يومي).
String stockSummaryLine({required double stock, required String unit, required int? daysLeft}) {
  final base = 'معاك ${_arabic(stock)} $unit';
  if (daysLeft == null) return base;
  return switch (daysLeft) {
    0 => '$base — مش هتكفّي يوم كامل',
    1 => '$base — تكفّي يوم واحد',
    2 => '$base — تكفّي يومين',
    _ => '$base — تكفّي ${_arabic(daysLeft)} ${daysLeft <= 10 ? 'أيام' : 'يوم'}',
  };
}

/// رسالة الصيدلية — المستخدم بيراجعها ويبعتها بنفسه.
String pharmacyOrderMessage(String medicationName, int boxes) =>
    'محتاج $medicationName — ${switch (boxes) {
      1 => '${_arabic(1)} علبة',
      2 => 'علبتين',
      <= 10 => '${_arabic(boxes)} علب',
      _ => '${_arabic(boxes)} علبة',
    }}';

/// رقم واتساب مصري → صيغة wa.me (من غير + ولا مسافات). null = مش رقم.
String? whatsappNumber(String raw) {
  final digits = _westernDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 8) return null;
  if (digits.startsWith('00')) return digits.substring(2);
  if (digits.startsWith('0')) return '2$digits'; // ٠١٠… → ٢٠١٠…
  return digits;
}
