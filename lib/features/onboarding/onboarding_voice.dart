import 'dart:async';

import '../../data/voice/voice_service.dart';

/// جمل خطوات البداية (`onb_*`) — **بتتقال لوحدها** أول ما الصفحة تفتح، لو
/// المريض قال «أيوه، اتكلّم» في المقدمة. مرة واحدة لكل صفحة، و«ساعدني»
/// على الصفحة بيعيدها.
///
/// - **بتستنّى اللي بيتقال يخلص**: «تمام، أنا معاك» بتاعة المقدمة بتتقال
///   والصفحة بتفتح — الجملة الجديدة بتبدأ بعدها مش فوقها.
/// - **بتسكت أول ما يلمس حاجة** ([hush]): يكتب، يختار، يحرّك بكرة، يدوس
///   زرار، أو يسيب الصفحة.
/// - **برّه البداية مفيش حاجة بتتقال لوحدها** — الكلاس ده عايش في
///   `features/onboarding/` و`entry/` بس (`voice_placement_test`).
class OnboardingVoice {
  OnboardingVoice(this.voice);

  final VoiceService? voice;
  final _played = <String>{};

  bool get on => voice?.enabled == true;

  /// [ids] ورا بعض، مرة واحدة لكل [key] (أول رقم لو مش محدد) — في طابور
  /// الخدمة، فـ«دلوقتي تقدر تكلّمني» بتيجي بعد جملة الصفحة مش فوقها.
  Future<void> auto(List<String> ids, {String? key}) {
    final v = voice;
    if (v == null || !v.enabled) return Future.value();
    if (!_played.add(key ?? ids.first)) return Future.value();
    return v.speakQueued(ids);
  }

  /// بيسكّت اللي بيتقال والسماع، وبيلغي أي جملة لسه مستنية دورها.
  void hush() {
    final v = voice;
    if (v != null) unawaited(v.stop());
  }
}
