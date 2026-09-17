/// جنس المريض — عشان الكلام اللي بيخاطبه يطلع صح: «بتفطر» ولا «بتفطري».
///
/// `m` = راجل، `f` = ست. متخزّن بالحرف ده في `patients.sex`. null = لسه ما
/// اتسألش (أجهزة قبل نسخة ٨) — والنص بيرجع للمذكّر اللي كان عليه قبل كده.
enum Sex { m, f }

/// اختيار الكلمة حسب الجنس. [female] بيتاخد لما الجنس `f` بس.
///
/// كله بالمخاطب: التطبيق بيكلّم اللي هيمسك التليفون، وهو المريض. كان فيه
/// صيغة غايب لمسار «بظبّط لحد تاني» في شاشة البداية — الكارت ده اتشال،
/// والصيغة معاه (في git لو رجعت).
///
/// دارت نقية — مفيش Flutter. الطبقة دي هي المكان الوحيد اللي بيتقرر فيه
/// التذكير والتأنيث؛ الشاشات بتنده `say.pick(...)` أو الجمل الجاهزة تحت
/// بدل ما كل شاشة تكتب `if (sex == Sex.f)` لوحدها.
class Say {
  const Say(this.sex);

  final Sex? sex;

  bool get _female => sex == Sex.f;

  String pick(String male, String female) => _female ? female : male;

  // ---- أسئلة «ظبّط يومك»
  String get wakeQuestion => pick('بتصحى الساعة كام؟', 'بتصحي الساعة كام؟');
  String get breakfastQuestion => pick('بتفطر الساعة كام؟', 'بتفطري الساعة كام؟');
  String get lunchQuestion => pick('بتتغدى الساعة كام؟', 'بتتغدّي الساعة كام؟');
  String get dinnerQuestion => pick('بتتعشى الساعة كام؟', 'بتتعشّي الساعة كام؟');
  String get sleepQuestion => pick('بتنام الساعة كام؟', 'بتنامي الساعة كام؟');
  String get notSure => pick('مش متأكد', 'مش متأكدة');

  String get wakeHint => 'يومك بيبدأ من هنا — كل المواعيد بتترتب عليه.';
  String get dinnerHint => 'لو بتتعشى بدري أو متأخر، اظبطها هنا.';
  String get sleepHint => 'لو بتنام بعد نص الليل، اختار من بدري الصبح.';
  String get routineTitle => 'خلينا نعرف يومك';
  String get routineSubtitle => 'خمس أسئلة — وبعدها أي روشتة هتتظبط لوحدها على مواعيدك.';

  // ---- الرئيسية
  String get whatNow => pick('تعمل إيه دلوقتي؟', 'تعملي إيه دلوقتي؟');

  // ---- التنبيه والسكة: الحالة اللي التطبيق بيقولها له / لها
  /// «أخدته ٨:٠٠ ص» — التطبيق بيقول للمريض إنه خده.
  String takenAt(String time) => pick('أخدته $time', 'أخدتيه $time');
  String get tookItAlready => pick('خدته خلاص', 'خدتيه خلاص');
  String get forgotIt => pick('نسيتها؟', 'نسيتيها؟');
  String get thanks => pick('تسلم.', 'تسلمي.');
  String get backToDay => pick('ارجع ليومك', 'ارجعي ليومك');
  String get allDone =>
      pick('خلصت أدوية النهاردة كلها. تسلم.', 'خلّصتي أدوية النهاردة كلها. تسلمي.');
}
