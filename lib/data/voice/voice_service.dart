import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/voice/voice_catalog.dart';

/// تشغيل تسجيل من الحزمة. `true` = اتقال لآخره، `false` = ما عرفش
/// (ملف ناقص، عطل في المشغّل) — ساعتها الخدمة بترجع لصوت الموبايل.
/// التنفيذ الحقيقي في `audio_voice_player.dart` (الملف الوحيد اللي بيستورد
/// `audioplayers`).
abstract interface class VoicePlayer {
  Future<bool> play(String assetPath, {required double volume});
  Future<void> stop();
}

/// صوت الموبايل (TTS) — عربي، ومصري لو موجود. التنفيذ في `device_tts.dart`
/// (الملف الوحيد اللي بيستورد `flutter_tts`).
abstract interface class VoiceTts {
  Future<void> speak(String text, {required double rate, required double volume});
  Future<void> stop();
}

/// جلسة الصوت: نوطّي اللي شغّال من تطبيقات تانية وإحنا بنتكلم، ونسيبه بعدها.
/// **ما بتلمسش نغمة الجرعة** — دي إشعار من النظام مش من المشغّل ده.
abstract interface class VoiceAudioFocus {
  Future<void> begin();
  Future<void> end();
}

/// السرعة — للـTTS بس (التسجيل بسرعته). **البطيء هو الافتراضي**: بنكلّم حد
/// كبير في السن.
enum VoiceSpeed {
  slow(0.38, 'بطيء'),
  normal(0.5, 'عادي'),
  fast(0.62, 'سريع');

  const VoiceSpeed(this.rate, this.label);
  final double rate;
  final String label;
}

enum VoiceVolume {
  low(0.5, 'واطي'),
  normal(0.8, 'عادي'),
  high(1.0, 'عالي');

  const VoiceVolume(this.level, this.label);
  final double level;
  final String label;
}

/// «الرفيق الصوتي» — المرحلة ١: **بيتكلم بس.** مفيش مايك، مفيش شبكة، مفيش
/// ذكاء. كل جملة من الكتالوج (تسجيل) أو قالب ملخص اليوم (صوت الموبايل).
///
/// **تنبيه الجرعة بيكسب دايماً**: [attachAlertSignal] بيوقّف أي كلام أول ما
/// إشعار جرعة يتداس أو شاشة التذكير تتفتح. الخدمة دي ما بتعرفش حاجة عن
/// الجدولة ولا الإشعارات — `voice_guard_test` بيقفل على ده.
class VoiceService extends ChangeNotifier {
  VoiceService({
    required this.player,
    required this.tts,
    this.focus,
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  final VoicePlayer player;
  final VoiceTts tts;
  final VoiceAudioFocus? focus;
  final Future<SharedPreferences> Function() _prefs;

  static const enabledKey = 'voice.enabled';
  static const speedKey = 'voice.speed';
  static const volumeKey = 'voice.volume';
  static const introDoneKey = 'voice.introDone';
  static const briefingDayKey = 'voice.briefingDay';

  bool _enabled = false;
  VoiceSpeed _speed = VoiceSpeed.slow;
  VoiceVolume _volume = VoiceVolume.normal;
  bool _introDone = false;
  String? _briefingDay;

  bool get enabled => _enabled;
  VoiceSpeed get speed => _speed;
  VoiceVolume get volume => _volume;

  /// المقدمة اتعرضت (أو اتخطّت) مرة — ما بتترجعش غير من الإعدادات.
  bool get introDone => _introDone;

  /// اللي بيتقال دلوقتي — الشاشة بتكتبه (ترجمة مكتوبة لكل جملة).
  final ValueNotifier<String?> caption = ValueNotifier<String?>(null);

  bool get speaking => caption.value != null;

  int _generation = 0;
  ValueListenable<String?>? _alert;

  Future<void> load() async {
    try {
      final p = await _prefs();
      _enabled = p.getBool(enabledKey) ?? false;
      _speed = VoiceSpeed.values.asNameMap()[p.getString(speedKey)] ?? VoiceSpeed.slow;
      _volume = VoiceVolume.values.asNameMap()[p.getString(volumeKey)] ?? VoiceVolume.normal;
      _introDone = p.getBool(introDoneKey) ?? false;
      _briefingDay = p.getString(briefingDayKey);
    } catch (e) {
      diag('Voice: قراية الإعدادات وقعت ($e)');
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    if (!on) await stop();
    notifyListeners();
    await _put((p) => p.setBool(enabledKey, on));
  }

  Future<void> setSpeed(VoiceSpeed s) async {
    _speed = s;
    notifyListeners();
    await _put((p) => p.setString(speedKey, s.name));
  }

  Future<void> setVolume(VoiceVolume v) async {
    _volume = v;
    notifyListeners();
    await _put((p) => p.setString(volumeKey, v.name));
  }

  Future<void> markIntroDone() async {
    _introDone = true;
    notifyListeners();
    await _put((p) => p.setBool(introDoneKey, true));
  }

  /// ملخص اليوم مرة واحدة لكل يوم روتين — [dayKey] هو اليوم بصيغة ثابتة.
  bool shouldBrief(String dayKey) => _enabled && _briefingDay != dayKey;

  Future<void> markBriefed(String dayKey) async {
    _briefingDay = dayKey;
    await _put((p) => p.setString(briefingDayKey, dayKey));
  }

  /// جملة من الكتالوج: التسجيل الأول، ولو ناقص أو وقع → صوت الموبايل بنفس
  /// النص. بترجع لما الكلام يخلص أو يتقطع. [force] للمقدمة (قبل ما يجاوب
  /// «تحب أكلّمك؟») ولإعادتها من الإعدادات — غير كده الصوت المقفول صامت.
  Future<void> speakLine(String id, {bool force = false}) async {
    if (!_enabled && !force) return;
    final text = voiceLine(id);
    final gen = await _begin(text);
    try {
      var ok = false;
      try {
        ok = await player.play(voiceAssetPath(id), volume: _volume.level);
      } catch (e) {
        diag('Voice: التسجيل $id وقع ($e) — صوت الموبايل بداله');
      }
      if (gen != _generation) return;
      if (!ok) await _tts(text);
    } finally {
      await _end(gen);
    }
  }

  /// كذا جملة ورا بعض (المقدمة). بتقف أول ما حاجة توقّفها.
  Future<void> speakLines(List<String> ids, {bool force = false}) async {
    for (final id in ids) {
      final gen = _generation;
      await speakLine(id, force: force);
      if (_generation != gen + 1) return; // اتقطعت في النص
    }
  }

  /// نص حر (ملخص اليوم) — **صوت الموبايل بس**، مفيش تسجيل ليه.
  Future<void> speakText(String text, {bool force = false}) async {
    if (!_enabled && !force) return;
    final gen = await _begin(text);
    try {
      await _tts(text);
    } finally {
      await _end(gen);
    }
  }

  /// بيوقّف كل حاجة فوراً — تسجيل وصوت موبايل — ويشيل الترجمة.
  Future<void> stop() async {
    _generation++;
    caption.value = null;
    await Future.wait([
      player.stop().catchError((Object e) => diag('Voice: وقف التسجيل ($e)')),
      tts.stop().catchError((Object e) => diag('Voice: وقف الصوت ($e)')),
    ]);
    await _release();
  }

  /// **تنبيه الجرعة بيكسب.** أي قيمة جديدة على الإشارة دي (دوسة على إشعار
  /// جرعة) بتوقّف الكلام في لحظتها.
  void attachAlertSignal(ValueListenable<String?> signal) {
    _alert?.removeListener(_onAlert);
    _alert = signal..addListener(_onAlert);
  }

  void _onAlert() {
    if (_alert?.value != null) unawaited(stop());
  }

  Future<int> _begin(String text) async {
    await stop();
    final gen = ++_generation;
    caption.value = text;
    try {
      await focus?.begin();
    } catch (e) {
      diag('Voice: جلسة الصوت ($e)');
    }
    return gen;
  }

  Future<void> _tts(String text) async {
    try {
      await tts.speak(text, rate: _speed.rate, volume: _volume.level);
    } catch (e) {
      diag('Voice: صوت الموبايل وقع ($e)');
    }
  }

  Future<void> _end(int gen) async {
    if (gen != _generation) return;
    caption.value = null;
    await _release();
  }

  Future<void> _release() async {
    try {
      await focus?.end();
    } catch (e) {
      diag('Voice: تسليم جلسة الصوت ($e)');
    }
  }

  Future<void> _put(Future<void> Function(SharedPreferences p) write) async {
    try {
      await write(await _prefs());
    } catch (e) {
      diag('Voice: حفظ الإعدادات وقع ($e)');
    }
  }

  @override
  void dispose() {
    _alert?.removeListener(_onAlert);
    caption.dispose();
    super.dispose();
  }
}
