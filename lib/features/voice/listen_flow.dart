import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/voice/speech_listener.dart';
import '../../data/voice/voice_service.dart';
import '../../domain/voice/answer_parser.dart';

/// مراحل السماع — الشاشة بترسمها، والاختبار بيقراها.
enum ListenPhase {
  idle,

  /// «اتكلم، أنا سامعك» — المايك مفتوح.
  listening,

  /// «فهمت: …» + «صح كده؟» — مستني «أيوه» (بالصوت أو بالإيد).
  confirming,

  /// «معلش، مافهمتش» — بيقدر يقول تاني أو يدوس بإيده.
  notUnderstood,

  /// اتطبّقت.
  done,
}

/// سؤال واحد مقفول بالصوت: اسمع ← افهم ← قول اللي فهمته ← «صح كده؟» ← طبّق.
///
/// **التطبيق بيعدّي من نفس السكّة بتاعة الزرار** ([onApply] هي الدالة اللي
/// الزرار بيندهها) — الصوت مش سكّة تانية للكتابة. و**مفيش تطبيق من غير
/// تأكيد**: [confirmYes] بس هي اللي بتنده [onApply]، سواء جات من «أيوه»
/// مسموعة أو مدووسة.
///
/// **تنبيه الجرعة بيكسب**: كل خطوة بتقارن [VoiceService.interrupts] قبل
/// وبعد؛ أي `stop()` من برّه (إشعار، شاشة اتقفلت، لمسة) بيرجّع الكل
/// لـ[ListenPhase.idle] في صمت — من غير «مافهمتش» على حاجة إحنا اللي قطعناها.
class ListenFlow<T> extends ChangeNotifier {
  ListenFlow({
    required this.voice,
    required this.parse,
    required this.describe,
    required this.onApply,
    this.force = false,
    this.autoApply = true,
  });

  final VoiceService voice;
  final T? Function(String heard) parse;

  /// «الساعة ٨ الصبح» — اللي بيتقال قبل «صح كده؟».
  final String Function(T value) describe;
  final Future<void> Function(T value) onApply;

  /// المقدمة: الصوت لسه ما اتشغّلش، والجمل بتتقال برضه.
  final bool force;

  /// «أيوه» بتطبّق على طول. الزرار بيحطّها false: الورقة بتتقفل الأول وبعدين
  /// بيطبّق ([confirmed]) — عشان شاشة بتقفل نفسها بعد التطبيق (التذكير) ما
  /// تقفلش الورقة بدالها.
  final bool autoApply;

  /// اللي اتأكّد ولسه ما اتطبّقش (لما [autoApply] false).
  T? confirmed;

  ListenPhase phase = ListenPhase.idle;
  T? heard;
  String? heardText;
  bool _busy = false;
  bool _retry = false;
  bool _disposed = false;

  /// الزرار بيظهر: فيه مايك، ومش مرفوض، والصوت شغّال (أو المقدمة).
  bool get available => voice.listener != null && !voice.micDenied && (voice.enabled || force);

  void _set(ListenPhase p) {
    if (_disposed) return;
    phase = p;
    notifyListeners();
  }

  bool _interrupted(int gen) {
    if (gen == voice.interrupts) return false;
    if (phase != ListenPhase.idle) _set(ListenPhase.idle);
    return true;
  }

  /// دوسة المايك.
  Future<void> start() async {
    final listener = voice.listener;
    if (listener == null || _busy) return;
    _busy = true;
    try {
      await voice.stop();
      final gen = voice.interrupts;
      if (!await listener.hasPermission()) {
        // قبل ما النظام يسأل: «عشان أسمع حضرتك، محتاج إذن الميكروفون»
        await voice.speakLine('lis_mic_permission', force: true);
        if (_interrupted(gen)) return;
      }
      final ok = await listener.prepare();
      if (_interrupted(gen)) return;
      if (!ok) {
        // رفض = الزرار يختفي وكل حاجة بالإيد — ومش هنسأل تاني
        voice.markMicDenied();
        _set(ListenPhase.idle);
        await voice.speakLine('lis_mic_denied', force: true);
        return;
      }
      await _round(listener, gen);
    } finally {
      _busy = false;
    }
  }

  Future<void> _round(SpeechListener listener, int gen) async {
    heard = null;
    heardText = null;
    _set(ListenPhase.listening);
    await voice.speakLine('lis_listening', force: force);
    if (_interrupted(gen)) return;
    final text = await listener.listen();
    if (_interrupted(gen)) return;
    final value = text == null ? null : parse(text);
    if (value == null) {
      _set(ListenPhase.notUnderstood);
      await voice.speakLine('lis_not_understood', force: force);
      return;
    }
    heard = value;
    heardText = describe(value);
    _set(ListenPhase.confirming);
    await voice.speakText('فهمت: $heardText', force: force);
    if (_interrupted(gen)) return;
    await voice.speakLine('lis_confirm', force: force);
    if (_interrupted(gen)) return;
    // «أيوه» بالصوت — أو بالإيد من الزرار اللي على الشاشة في نفس الوقت
    final answer = await listener.listen();
    if (_interrupted(gen)) return;
    if (_retry) {
      // «لأ، قول تاني» بالإيد وإحنا لسه بنسمع «أيوه»
      _retry = false;
      return _round(listener, gen);
    }
    if (phase != ListenPhase.confirming) return;
    switch (answer == null ? null : parseYesNo(answer)) {
      case true:
        await confirmYes();
      case false:
        await _round(listener, gen);
      case null:
        break; // الزرارين فاضلين قدّامه
    }
  }

  /// «أيوه» — التطبيق الوحيد.
  Future<void> confirmYes() async {
    final value = heard;
    if (value == null || phase != ListenPhase.confirming) return;
    heard = null;
    _set(ListenPhase.done);
    await voice.listener?.stop();
    if (autoApply) {
      await onApply(value);
    } else {
      confirmed = value;
    }
  }

  /// بيطبّق اللي اتأكّد (بعد ما الورقة اتقفلت) — مرة واحدة.
  Future<void> applyConfirmed() async {
    final value = confirmed;
    if (value == null) return;
    confirmed = null;
    await onApply(value);
  }

  /// «لأ» — اسمع تاني. السماع الجاري بيتقفل، والدورة بتبدأ من أول
  /// «اتكلم، أنا سامعك».
  Future<void> confirmNo() async {
    if (phase != ListenPhase.confirming) return;
    heard = null;
    _retry = true;
    _set(ListenPhase.listening);
    await voice.listener?.stop();
  }

  /// قفل من غير تطبيق.
  Future<void> cancel() async {
    heard = null;
    _set(ListenPhase.idle);
    await voice.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(voice.listener?.stop());
    super.dispose();
  }
}
