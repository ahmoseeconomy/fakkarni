import 'arabic_time.dart';

/// «٢٬٣٤٧» — أرقام عربية بفاصل الآلاف العربي (U+066C). للعدّادات الكبيرة
/// بس؛ رقم من تلات خانات بيتقري من غير فاصل.
String arabicGrouped(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write('٬');
  }
  final grouped = arabicDigits(buffer.toString());
  return value < 0 ? '−$grouped' : grouped;
}

/// «٨٤٫٧٪» — نسبة بعلامة عشرية عربية (U+066B) ومنزلة واحدة.
String arabicPercent(double fraction) {
  final tenths = (fraction * 1000).round();
  final whole = tenths ~/ 10;
  final frac = tenths % 10;
  return '${arabicDigits('$whole')}٫${arabicDigits('$frac')}٪';
}
