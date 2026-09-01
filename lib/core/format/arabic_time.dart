/// أرقام وأوقات بالعربي.
///
/// دارت نقية — من غير Flutter — عشان تتختبر من غير ما تشغّل واجهة.
/// المستخدم الأساسي عنده ٧٢ سنة وبيقرا ٧:٣٠ أسرع بكتير من 7:30.
const List<String> _arabicDigits = [
  '٠',
  '١',
  '٢',
  '٣',
  '٤',
  '٥',
  '٦',
  '٧',
  '٨',
  '٩',
];

/// بيحوّل أي أرقام إنجليزي في نص لأرقام عربي، وبيسيب باقي الحروف زي ما هي.
String arabicDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final digit = rune - 0x30;
    buffer.write(digit >= 0 && digit <= 9 ? _arabicDigits[digit] : String.fromCharCode(rune));
  }
  return buffer.toString();
}

String arabicNumber(int value) => arabicDigits(value.toString());

/// «٧:٣٠ ص» — نظام ١٢ ساعة، وده اللي الناس بتقوله.
String arabicTime(DateTime time) {
  final isMorning = time.hour < 12;
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minutes = time.minute.toString().padLeft(2, '0');
  return '${arabicNumber(hour12)}:${arabicDigits(minutes)} '
      '${isMorning ? 'ص' : 'م'}';
}

/// «كمان ٢٥ دقيقة» / «كمان ساعتين» / «فات معاده بنص ساعة».
///
/// مفيش لوم في أي صيغة هنا: هو نسي، مش غلط.
String arabicCountdown(Duration remaining) {
  final late = remaining.isNegative;
  final minutes = remaining.abs().inMinutes;

  if (minutes < 1) return late ? 'دلوقتي' : 'دلوقتي';

  final String amount;
  if (minutes < 60) {
    amount = '${arabicNumber(minutes)} دقيقة';
  } else {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final hourText = switch (hours) {
      1 => 'ساعة',
      2 => 'ساعتين',
      _ when hours <= 10 => '${arabicNumber(hours)} ساعات',
      _ => '${arabicNumber(hours)} ساعة',
    };
    amount = rest == 0 ? hourText : '$hourText و${arabicNumber(rest)} دقيقة';
  }

  return late ? 'فات معاده بـ$amount' : 'كمان $amount';
}
