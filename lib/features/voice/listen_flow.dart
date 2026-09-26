import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/voice/listen_health.dart';
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

  /// «معلش، مافهمتش» — المايك **اشتغل** وما سمعش حاجة مفهومة. بيقدر يقول
  /// تاني أو يدوس بإيده.
  notUnderstood,

  /// المايك **ما اشتغلش أصلاً** (مش الإذن): «كمّل بإيدك» مرة، والزرار
  /// بيختفي من الشاشة دي. عمرها ما تتقال «مافهمتش».
  unavailable,

  /// اتطبّقت.
  done,
}

/// سؤال واحد بالصوت: اسمع ← افهم ← قول اللي فهمته ← «صح كده؟» ← طبّق.
///
/// **التطبيق بيعدّي من نفس السكّة بتاعة الزرار** ([onApply] هي الدالة اللي
/// الزرار بيندهها) — الصوت مش سكّة تانية للكتابة. و**مفيش تطبيق من غير
/// تأكيد**: [confirmYes] بس هي اللي بتنده [onApply]، سواء جات من «أيوه»
/// مسموعة أو مدووسة.
///
/// **تلات نتايج للسماع، ومش بيتلخبطوا** (آيفون، ٢٦ سبتمبر ٢٠٢٦ — «مافهمتش»
/// كانت بتطلع فوراً والمايك عمره ما اتفتح):
/// - كلام → بيتفهم؛
/// - سكوت → «مافهمتش، قول تاني»؛
/// - **السماع ما بدأش** → لو الإذن: `lis_mic_denied`؛ غير كده `gen_try_hands`
///   مرة والزرار بيختفي من الشاشة، والسبب التقني بيتكتب `Listen:` في السجل
///   وبيطلع للأدمن ([recordListenProblem]) — المريض ما بيشوفوش.
///
/// **حقل كلام حر** ([ask] + [preview]): الكلام المسموع بيتكتب في الحقل على
/// طول، والسؤال بيتقال بصوت الموبايل («اسمك أحمد، صح كده؟»)؛ «لأ» بترجّع
/// اللي كان مكتوب ([revert]) وبتسمع تاني.
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
    this.ask,
    this.preview,
    this.revert,
    this.force = false,
    this.autoApply = true,
    Future<void> Function(String reason)? onStartFailure,
  }) : _onStartFailure = onStartFailure ?? recordListenProblem;

  final VoiceService voice;
  final T? Function(String heard) parse;

  /// «الساعة ٨ الصبح» — اللي بيتقال قبل «صح كده؟».
  final String Function(T value) describe;
  final Future<void> Function(T value) onApply;

  /// سؤال التأكيد كامل بصوت الموبايل («اسمك أحمد، صح كده؟») — بداله
  /// «فهمت: …» + `lis_confirm`. للحقول الحرّة.
  final String Function(T value)? ask;

  /// الكلام المسموع بيتكتب في الحقل **قبل** «أيوه» — حقل حر بس، وهو لسه
  /// قابل للتعديل، و«كمّل» لسه بإيده.
  final void Function(T value)? preview;

  /// «لأ» أو قفل من غير «أيوه» — الحقل بيرجع زي ما كان.
  final VoidCallback? revert;

  /// المقدمة: الصوت لسه ما اتشغّلش، والجمل بتتقال برضه.
  final bool force;

  /// «أيوه» بتطبّق على طول. الزرار بيحطّها false: الورقة بتتقفل الأول وبعدين
  /// بيطبّق ([confirmed]) — عشان شاشة بتقفل نفسها بعد التطبيق (التذكير) ما
  /// تقفلش الورقة بدالها.
  final bool autoApply;

  final Future<void> Function(String reason) _onStartFailure;

  /// اللي اتأكّد ولسه ما اتطبّقش (لما [autoApply] false).
  T? confirmed;

  ListenPhase phase = ListenPhase.idle;
  T? heard;
  String? heardText;
  bool _busy = false;
  bool _retry = false;
  bool _disposed = false;
  bool _previewed = false;

  /// المايك ما اشتغلش على الشاشة دي — الزرار بيختفي لحد ما تتقفل.
  bool startFailed = false;

  /// الزرار بيظهر: فيه مايك، ومش مرفوض، واشتغل، والصوت شغّال (أو المقدمة).
  bool get available =>
      voice.listener != null && !voice.micDenied && !startFailed && (voice.enabled || force);

  /// الجملة اللي في الورقة وقت التأكيد — نفس اللي بيتقال.
  String get confirmText {
    final v = heard;
    final a = ask;
    if (v != null && a != null) return a(v);
    return 'فهمت: $heardText\nصح كده؟';
  }

  void _set(ListenPhase p) {
    if (_disposed) return;
    phase = p;
    notifyListeners();
  }

  bool _interrupted(int gen) {
    if (gen == voice.interrupts) return false;
    _undoPreview();
    if (phase != ListenPhase.idle) _set(ListenPhase.idle);
    return true;
  }

  void _undoPreview() {
    if (!_previewed) return;
    _previewed = false;
    revert?.call();
  }

  /// دوسة المايك.
  Future<void> start() async {
    final listener = voice.listener;
    if (listener == null || _busy || startFailed) return;
    _busy = true;
    try {
      await voice.stop();
      final gen = voice.interrupts;
      if (!await listener.hasPermission()) {
        // قبل ما النظام يسأل: «عشان أسمع حضرتك، محتاج إذن الميكروفون»
        await voice.speakLine('lis_mic_permission', force: true);
        if (_interrupted(gen)) return;
      }
      final failed = await listener.prepare();
      if (_interrupted(gen)) return;
      if (failed != null) {
        await _cantListen(failed);
        return;
      }
      await _round(listener, gen);
    } finally {
      _busy = false;
    }
  }

  /// المايك ما اشتغلش. الإذن = «كمّل بإيدك» ومش هنسأل تاني؛ أي سبب تاني =
  /// `gen_try_hands` مرة، والزرار يختفي، والسبب للسجل والأدمن بس.
  Future<void> _cantListen(ListenFailed failed) async {
    _undoPreview();
    if (failed.permission) {
      voice.markMicDenied();
      _set(ListenPhase.idle);
      await voice.speakLine('lis_mic_denied', force: true);
      return;
    }
    startFailed = true;
    _set(ListenPhase.unavailable);
    await _onStartFailure(failed.reason);
    await voice.speakLine('gen_try_hands', force: force);
  }

  Future<void> _round(SpeechListener listener, int gen) async {
    heard = null;
    heardText = null;
    _set(ListenPhase.listening);
    await voice.speakLine('lis_listening', force: force);
    if (_interrupted(gen)) return;
    // الجملة خلصت — والجلسة بتتسلّم قبل ما المتعرّف ياخدها
    await voice.yieldToMic();
    final result = await listener.listen();
    if (_interrupted(gen)) return;
    final String? text;
    switch (result) {
      case ListenFailed():
        return _cantListen(result);
      case ListenSilence():
        text = null;
      case ListenHeard(text: final t):
        text = t;
    }
    unawaited(clearListenProblem());
    final value = text == null ? null : parse(text);
    if (value == null) {
      _set(ListenPhase.notUnderstood);
      await voice.speakLine('lis_not_understood', force: force);
      return;
    }
    heard = value;
    heardText = describe(value);
    if (preview case final p?) {
      p(value);
      _previewed = true;
    }
    _set(ListenPhase.confirming);
    if (ask case final a?) {
      await voice.speakText(a(value), force: force);
      if (_interrupted(gen)) return;
    } else {
      await voice.speakText('فهمت: $heardText', force: force);
      if (_interrupted(gen)) return;
      await voice.speakLine('lis_confirm', force: force);
      if (_interrupted(gen)) return;
    }
    // «أيوه» بالصوت — أو بالإيد من الزرار اللي على الشاشة في نفس الوقت
    await voice.yieldToMic();
    final answer = await listener.listen();
    if (_interrupted(gen)) return;
    if (_retry) {
      // «لأ، قول تاني» بالإيد وإحنا لسه بنسمع «أيوه»
      _retry = false;
      return _round(listener, gen);
    }
    if (phase != ListenPhase.confirming) return;
    // «أيوه» ما بقتش تتسمع — الزرارين فاضلين قدّامه، مفيش «مافهمتش»
    if (answer is ListenFailed) return;
    switch (answer is ListenHeard ? parseYesNo(answer.text) : null) {
      case true:
        await confirmYes();
      case false:
        _undoPreview();
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
    _previewed = false; // اللي في الحقل بقى بتاعه
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
    _undoPreview();
    _retry = true;
    _set(ListenPhase.listening);
    await voice.listener?.stop();
  }

  /// قفل من غير تطبيق.
  Future<void> cancel() async {
    heard = null;
    _undoPreview();
    if (phase != ListenPhase.unavailable) _set(ListenPhase.idle);
    await voice.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(voice.listener?.stop());
    super.dispose();
  }
}
