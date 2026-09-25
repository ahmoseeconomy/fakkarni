import 'package:audio_session/audio_session.dart';

import 'voice_service.dart';

/// جلسة الصوت — **الملف الوحيد اللي بيستورد `audio_session`.**
///
/// وإحنا بنتكلم: اللي شغّال في تطبيق تاني بيوطى (ما بيوقفش). ولما نخلص
/// الجلسة بتتسلّم وبتبلّغ التطبيقات التانية ترجع لصوتها. نغمة الجرعة
/// بتيجي من إشعار النظام مش من هنا — مش بتتأثر.
class AudioSessionFocus implements VoiceAudioFocus {
  AudioSession? _session;

  Future<AudioSession> _get() async {
    final s = _session ??= await AudioSession.instance;
    await s.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers | AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.assistant,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));
    return s;
  }

  @override
  Future<void> begin() async => (await _get()).setActive(true);

  @override
  Future<void> end() async => (await _get()).setActive(false);
}
