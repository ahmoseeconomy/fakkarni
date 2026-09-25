import 'package:flutter_tts/flutter_tts.dart';

import '../../core/diagnostics.dart';
import 'voice_service.dart';

/// صوت الموبايل — **الملف الوحيد اللي بيستورد `flutter_tts`.**
///
/// عربي، والمصري (`ar-EG`) لو الموبايل عنده، وإلا أي عربي. لو مفيش عربي
/// خالص، الكلام بيطلع باللغة الافتراضية للموبايل — أحسن من السكوت،
/// والترجمة المكتوبة على الشاشة بتغطّي.
class DeviceTts implements VoiceTts {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _prepare() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
      final langs = await _tts.getLanguages;
      final available = langs is List ? langs.map((l) => l.toString()).toList() : const <String>[];
      final pick = available.firstWhere(
        (l) => l.toLowerCase().replaceAll('_', '-') == 'ar-eg',
        orElse: () => available.firstWhere((l) => l.toLowerCase().startsWith('ar'), orElse: () => 'ar'),
      );
      await _tts.setLanguage(pick);
    } catch (e) {
      diag('Voice: تجهيز صوت الموبايل ($e)');
    }
  }

  @override
  Future<void> speak(String text, {required double rate, required double volume}) async {
    await _prepare();
    await _tts.setSpeechRate(rate);
    await _tts.setVolume(volume);
    await _tts.speak(text, focus: true);
  }

  @override
  Future<void> stop() => _tts.stop();
}
