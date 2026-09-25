import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'voice_service.dart';

/// التسجيلات من الحزمة — **الملف الوحيد اللي بيستورد `audioplayers`.**
///
/// سياق الصوت: كلام (speech) بيوطّي اللي شغّال — مش بيوقّفه — وبيسيبه لما
/// يخلص. نفس اللي `AudioSessionFocus` بيظبطه، عشان المشغّل ما يعيدش ضبط
/// الجلسة بشكل مختلف على iOS.
class AudioVoicePlayer implements VoicePlayer {
  AudioVoicePlayer() {
    _player.setReleaseMode(ReleaseMode.release);
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.assistant,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.mixWithOthers, AVAudioSessionOptions.duckOthers},
      ),
    ));
  }

  final AudioPlayer _player = AudioPlayer(playerId: 'fakkarni_voice');
  Completer<bool>? _done;
  StreamSubscription<void>? _complete;

  @override
  Future<bool> play(String assetPath, {required double volume}) async {
    await stop();
    final done = _done = Completer<bool>();
    // `AssetSource` بيضيف `assets/` لوحده
    final path = assetPath.startsWith('assets/') ? assetPath.substring(7) : assetPath;
    _complete = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete(true);
    });
    try {
      await _player.setVolume(volume);
      await _player.play(AssetSource(path));
    } catch (_) {
      if (!done.isCompleted) done.complete(false);
    }
    final ok = await done.future;
    await _complete?.cancel();
    return ok;
  }

  @override
  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(true);
    await _complete?.cancel();
    await _player.stop();
  }
}
