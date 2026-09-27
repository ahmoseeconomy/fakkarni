import 'package:flutter/foundation.dart';

/// «كلّمني» بيسأل السحابة لو القارئ المحلي ما فهمش (المرحلة ٣، الخطوة ج).
///
/// **شغّال في debug/profile، ومقفول في release** — لحد ما يبقى فيه مفتاح
/// مدفوع (الدين 2b): المفتاح الحالي مجاني وجوّه التطبيق، ومش للاستخدام مع
/// كلام مرضى حقيقيين. متغيّر مش ثابت عشان يتقفل من بعيد بعدين من غير نسخة.
///
/// **TestFlight**: `--dart-define=VOICE_COMMANDS_CLOUD=true` بيفتحها في نسخة
/// release (المالك، ٢٦ سبتمبر ٢٠٢٦) — ونسخة المتجر من غير التعريف ده لحد
/// المفتاح المدفوع. الحد اليومي (٢٠) شغّال في الحالتين.
bool voiceCommandsCloud = const bool.fromEnvironment('VOICE_COMMANDS_CLOUD', defaultValue: !kReleaseMode);
