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
  int _token = 0;

  bool get on => voice?.enabled == true;

  /// [ids] ورا بعض، مرة واحدة لكل [key] (أول رقم لو مش محدد).
  Future<void> auto(List<String> ids, {String? key}) async {
    final v = voice;
    if (v == null || !v.enabled) return;
    if (!_played.add(key ?? ids.first)) return;
    final token = ++_token;
    await _quiet(v);
    if (token != _token || !v.enabled) return;
    await v.speakLines(ids);
  }

  /// بيسكّت اللي بيتقال، وبيلغي أي جملة لسه مستنية دورها.
  void hush() {
    _token++;
    final v = voice;
    if (v != null && v.speaking) unawaited(v.stop());
  }

  static Future<void> _quiet(VoiceService v) {
    if (!v.speaking) return Future.value();
    final done = Completer<void>();
    void listen() {
      if (v.caption.value == null && !done.isCompleted) {
        v.caption.removeListener(listen);
        done.complete();
      }
    }

    v.caption.addListener(listen);
    return done.future;
  }
}
