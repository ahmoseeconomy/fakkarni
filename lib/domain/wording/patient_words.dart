/// الجمل اللي التطبيق بيقولها للمريض عن حالته — **صيغة واحدة للكل.**
///
/// كان فيه طبقة بتختار «نسيتها؟» / «نسيتيها؟» حسب سؤال «راجل ولا ست؟» في
/// البداية؛ السؤال اتشال بقرار المالك (٢٧ سبتمبر ٢٠٢٦) والكلام رجع للصيغة
/// المحايدة اللي كان عليها قبل نسخة ٨. دارت نقية.
library;

/// «أخدته ٨:٠٠ ص» — التطبيق بيقول للمريض إنه خده.
String takenAtLine(String time) => 'أخدته $time';
const String tookItAlreadyLine = 'خدته خلاص';
const String forgotItLine = 'نسيتها؟';
const String thanksLine = 'تسلم.';
const String backToDayLine = 'ارجع ليومك';
const String allDoneLine = 'خلصت أدوية النهاردة كلها. تسلم.';
const String progressTitle = 'إنت ماشي إزاي';
