/// **«لا» مش اسم دوا.**
///
/// على الموبايل ظهر دوا اسمه «لا» على «يومك»: «كلّمني» سمعت «ضيف دوا … لا»
/// في جملة واحدة، والقارئ خد اللي بعد «دوا» اسم، والفورم اتفتح متعبّي بيه
/// و«احفظ» شغّال. كلمة إجابة (أيوه / لأ / آه / مش عارف / بعدين …) لوحدها
/// عمرها ما تبقى اسم دوا — مش في القارئ، ولا في الفورم، ولا في القاعدة.
///
/// دارت نقية — بتستعمل قوايم كلمات القبول والرفض من قارئ الإجابات نفسه،
/// فكلمة جديدة هناك بتتحجب هنا من غير ما حد يفتكر.
library;

import '../voice/answer_parser.dart' show affirmWords, denyWords, normalizeArabic;

/// كلمات بتتقال كإجابة أو تردّد، مش كاسم — فوق قوايم القبول والرفض.
const _fillerWords = {
  'مش', 'عارف', 'عارفه', 'عايز', 'عايزه', 'دلوقتي', 'كده', 'عدي', 'عدّي',
  'اقول', 'مفيش', 'ولا', 'حاجه', 'فاكر', 'فاكره', 'يعني', 'اممم', 'امم', 'ااه',
};

/// true لو [text] مالوش غير كلمات إجابة/تردّد — «لا»، «أيوه»، «آه»،
/// «مش عارف»، «لا مش عايز» — أو فاضي. ساعتها مش اسم دوا.
bool isNotAMedicineName(String? text) {
  if (text == null) return true;
  final norm = normalizeArabic(text);
  if (norm.isEmpty) return true;
  final words = norm.split(' ');
  return words.every((w) => affirmWords.contains(w) || denyWords.contains(w) || _fillerWords.contains(w));
}

/// الاسم زي ما هو، أو null لو مش اسم دوا — للي بيتعبّى من كلام أو قراية.
String? medicineNameOrNull(String? text) => isNotAMedicineName(text) ? null : text!.trim();
