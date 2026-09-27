// التطبيع قبل الفهم — بورت `normalize.js` من jarvis، فوق [normalizeForNumbers].
//
// أ/إ/آ → ا، ة → ه، ى → ي، من غير تشكيل ولا تطويل، والأرقام العربية لاتيني
// (ده كله في [normalizeArabic]). وفوقه **غلطات المتعرّف** اللي اتشافت على
// الجهاز: «كله ١٢ ساعة» / «كلها ٨ ساعات» = «كل ١٢ ساعة».
library;

import '../arabic_numbers.dart' show isNumberWord, normalizeForNumbers;

/// الجملة زي ما هتتفهم — نص مطبّع بمسافات واحدة.
String normalizeUtterance(String text) {
  var s = normalizeForNumbers(text);
  // «كله/كلها/كلو N ساعه» → «كل N ساعه» — المتعرّف بيسمع «كل» ملزوقة
  final words = s.split(' ');
  for (var i = 0; i + 1 < words.length; i++) {
    final w = words[i];
    if (w != 'كله' && w != 'كلها' && w != 'كلو' && w != 'كلوا') continue;
    final next = words[i + 1];
    final isNum = RegExp(r'^\d+$').hasMatch(next) || isNumberWord(next) || next == 'ساعتين' || next.startsWith('ساع');
    if (isNum) words[i] = 'كل';
  }
  s = words.join(' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// كلمات الجملة بعد التطبيع — والواو الملزوقة بتتفصل قدّام فعل الأخذ
/// («وآخده» → «و» + «اخده») عشان تبقى حد لاسم الدوا.
List<String> utteranceTokens(String normalized) {
  final out = <String>[];
  for (final t in normalized.split(' ')) {
    if (t.isEmpty) continue;
    if (t.length > 2 && t.startsWith('و') && _splitAfterWaw.contains(t.substring(1))) {
      out
        ..add('و')
        ..add(t.substring(1));
      continue;
    }
    out.add(t);
  }
  return out;
}

const _splitAfterWaw = {
  'اخده', 'اخدها', 'باخده', 'باخدها', 'هاخده', 'هاخدها', 'اخد', 'اخذ', 'اخذه', 'اخذها', 'ناخده', 'تاخده', 'ياخده',
  'كل', 'الساعه', 'قبل', 'بعد', 'مع', 'يوم', 'بكره', 'مرتين', 'مره',
  'احجز', 'احجزلي', 'ضيف', 'ضيفلي',
};
