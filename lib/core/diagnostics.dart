import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

/// سطر تشخيص للمطوّر — **بيطبع في debug وprofile، وساكت في release**.
///
/// `debugPrint` نفسها **مالهاش أي بوابة**: توثيقها بيقول بالنص إنها
/// «بتطبع على الكونسول حتى في release». فالسطور دي كانت بتشحن جوّه كل
/// IPA وAPK، وفيها أسماء جداول وحالات جرعات ورسايل أخطاء خام.
///
/// والبوابة الغلط هي `kDebugMode`: نسخة الـprofile هي **الوحيدة** اللي
/// تقدر ترد على سؤال صحوة شاشة القفل على iOS — من iOS 14 النظام بيرفض
/// يشغّل تطبيق debug من غير أدوات التطوير، فأول ما `flutter run` يفصل،
/// الـisolate عمره ما هيشتغل. تشخيص متقفل على `kDebugMode` بيسكت بالظبط
/// في النسخة اللي محتاجينه فيها.
///
/// فالقاعدة بقت: **تشخيص بيطبع بس → `!kReleaseMode`؛ تشخيص بيظهر على
/// الشاشة → `kDebugMode`.** لوحة خام قدام مريض في نسخة profile حاجة
/// تانية خالص عن سطر في Console.app.
void diag(String message) {
  if (kReleaseMode) return;
  debugPrint(message);
}
