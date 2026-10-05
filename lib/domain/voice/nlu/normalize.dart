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

/// إجابة حقل واحدة زي ما **المتعرّف الحقيقي** بيرجّعها (المرحلة ٢، المالك
/// 1A): فوق [normalizeUtterance] بيشيل علامات الوقف اللي [normalizeArabic]
/// بيسيبها — **النقطة** بالذات: آيفون بيختم كل جملة بيها، فكانت «للضغط.»
/// بتقع في التوكنة الصارمة والبكرة ما بتتحركش — وبيشيل كلمات الحشو من
/// الطرفين («آه للضغط.» = «للضغط»، «شراب يعني.» = «شراب»). للمطابقة
/// المتسامحة على قايمة مقفولة — مش للفهم الحر؛ النقطتين «:» بتفضل عشان
/// «9:30».
String spokenAnswer(String text) {
  final s = normalizeUtterance(text)
      .replaceAll(RegExp(r'[.…]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final words = s.split(' ');
  var start = 0;
  var end = words.length;
  while (start < end && _answerFillers.contains(words[start])) {
    start++;
  }
  while (end > start && _answerFillers.contains(words[end - 1])) {
    end--;
  }
  return words.sublist(start, end).join(' ');
}

/// حشو الكلام — بالصيغة **المطبّعة** (آه → اه، أيوه → ايوه). من الطرفين
/// بس: كلمة منهم في النص هي النص نفسه («تمام» لوحدها) ما بتتشالش لو هي
/// كل الإجابة... بتتشال برضه — القوايم المقفولة مفيهاش ولا واحدة منهم.
const _answerFillers = {
  'اه', 'ايوه', 'ايوا', 'اها', 'ها', 'يعني', 'هو', 'هي', 'طبعا', 'خلاص',
  'تمام', 'ماشي', 'اوك', 'امم', 'اممم', 'بقي', 'كده',
};

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
