import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/diagnostics.dart';
import 'speech_listener.dart';

/// متعرّف كلام الموبايل — **الملف الوحيد اللي بيستورد `speech_to_text`.**
///
/// - اللغة: `ar_EG` لو الموبايل عنده، وإلا أي عربي، وإلا لغة النظام.
/// - **على الموبايل الأول**: أول سماع بيطلب التعرّف على الجهاز
///   (`onDevice`). لو الموبايل ما بيعرفش (آيفون قديم، أو اللغة مش منزّلة)
///   المتعرّف بيرفض بـ`onDeviceError`، وساعتها بنعيد **مرة** من غير الشرط —
///   يعني الصوت بيتبعت لأبل/جوجل — وبنكتب ده في سجل التشخيص، ومش بنحاول
///   على الجهاز تاني في الجلسة دي. `lastOnDevice` بيقول اللي حصل فعلاً.
///   على أندرويد `EXTRA_PREFER_OFFLINE` طلب مش أمر: من أندرويد ١٢ بيتعمل
///   متعرّف على الجهاز لو موجود، وقبلها جوجل هي اللي بتقرر — فـ`true` هناك
///   معناه «طلبنا»، مش «اتأكدنا».
class SpeechToTextListener implements SpeechListener {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;
  bool _onDeviceRefused = false;
  bool? _lastOnDevice;
  Completer<String?>? _pending;
  String _partial = '';
  Timer? _guard;

  @override
  bool? get lastOnDevice => _lastOnDevice;

  @override
  Future<bool> hasPermission() async {
    try {
      return await _stt.hasPermission;
    } catch (e) {
      diag('Listen: قراية الإذن وقعت ($e)');
      return false;
    }
  }

  @override
  Future<bool> prepare() async {
    if (_ready) return true;
    try {
      final ok = await _stt.initialize(onError: _onError, onStatus: _onStatus);
      if (!ok) {
        diag('Listen: المتعرّف رفض يتجهّز (${_stt.lastError?.errorMsg ?? 'إذن'})');
        return false;
      }
      final locales = await _stt.locales();
      String norm(String id) => id.toLowerCase().replaceAll('-', '_');
      final ids = [for (final l in locales) l.localeId];
      _localeId = ids.cast<String?>().firstWhere((id) => norm(id!) == 'ar_eg',
          orElse: () => ids.cast<String?>().firstWhere((id) => norm(id!).startsWith('ar'), orElse: () => null));
      diag('Listen: جاهز — اللغة ${_localeId ?? 'لغة النظام'}');
      _ready = true;
      return true;
    } catch (e) {
      diag('Listen: التجهيز وقع ($e)');
      return false;
    }
  }

  @override
  Future<String?> listen({
    Duration silence = const Duration(seconds: 6),
    Duration maxLength = const Duration(seconds: 12),
  }) async {
    if (!_ready) return null;
    await stop();
    final result = _pending = Completer<String?>();
    _partial = '';
    final onDevice = !_onDeviceRefused;
    try {
      await _start(onDevice: onDevice, silence: silence, maxLength: maxLength);
    } catch (e) {
      diag('Listen: بدء السماع وقع ($e)');
      _finish(null);
    }
    // حارس: لو المتعرّف ما رجّعش ولا حالة (بيحصل)، بنقفل بإيدنا
    _guard = Timer(maxLength + silence + const Duration(seconds: 2), () {
      unawaited(_stt.stop());
      _finish(_partial.isEmpty ? null : _partial);
    });
    return result.future;
  }

  Future<void> _start({required bool onDevice, required Duration silence, required Duration maxLength}) async {
    _lastOnDevice = onDevice;
    await _stt.listen(
      onResult: (r) {
        if (r.recognizedWords.isNotEmpty) _partial = r.recognizedWords;
        if (r.finalResult) _finish(_partial.isEmpty ? null : _partial);
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        onDevice: onDevice,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        pauseFor: silence,
        listenFor: maxLength,
      ),
    );
  }

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg;
    // آيفون: «التعرّف على الجهاز مش متاح» → نعيد مرة عبر أبل، ونقولها
    if (!_onDeviceRefused && msg.toLowerCase().contains('ondevice') && _pending != null && !_pending!.isCompleted) {
      _onDeviceRefused = true;
      diag('Listen: التعرّف على الجهاز مش متاح — الصوت هيتبعت للسيرفر بتاع النظام');
      unawaited(_start(onDevice: false, silence: const Duration(seconds: 6), maxLength: const Duration(seconds: 12))
          .catchError((Object err) {
        diag('Listen: الإعادة وقعت ($err)');
        _finish(null);
      }));
      return;
    }
    if (msg == 'error_no_match' || msg == 'error_speech_timeout') {
      _finish(_partial.isEmpty ? null : _partial);
      return;
    }
    diag('Listen: $msg (${e.permanent ? 'دايم' : 'عابر'})');
    _finish(_partial.isEmpty ? null : _partial);
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // النهاية من غير نتيجة نهائية — آخر جزء مسموع هو الإجابة
      Future<void>.delayed(const Duration(milliseconds: 300), () => _finish(_partial.isEmpty ? null : _partial));
    }
  }

  void _finish(String? text) {
    _guard?.cancel();
    _guard = null;
    final p = _pending;
    if (p == null || p.isCompleted) return;
    _pending = null;
    p.complete(text);
  }

  @override
  Future<void> stop() async {
    _finish(null);
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (e) {
      diag('Listen: الوقف وقع ($e)');
    }
  }
}
