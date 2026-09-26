import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/diagnostics.dart';
import 'speech_listener.dart';

/// متعرّف كلام الموبايل — **الملف الوحيد اللي بيستورد `speech_to_text`.**
///
/// - اللغة: `ar_EG` لو الموبايل عنده، وإلا أي عربي، وإلا لغة النظام.
/// - **على الموبايل الأول**: أول سماع بيطلب التعرّف على الجهاز
///   (`onDevice`). لو الموبايل ما بيعرفش (آيفون: العربي مش من اللغات اللي
///   أبل بتعرّفها على الجهاز) بنعيد **مرة** من غير الشرط — يعني الصوت
///   بيتبعت لأبل/جوجل — وبنكتب ده في سجل التشخيص، ومش بنحاول على الجهاز
///   تاني في الجلسة دي. `lastOnDevice` بيقول اللي حصل فعلاً.
///   على أندرويد `EXTRA_PREFER_OFFLINE` طلب مش أمر: من أندرويد ١٢ بيتعمل
///   متعرّف على الجهاز لو موجود، وقبلها جوجل هي اللي بتقرر — فـ`true` هناك
///   معناه «طلبنا»، مش «اتأكدنا».
///
/// **الرفض ده بيجي كاستثناء من `listen()`، مش كنداء `onError`** (مقروء من
/// مصدر الإضافة `SpeechToTextPlugin.swift`: `result(FlutterError(onDeviceError))`
/// ثم بتكمّل وتشغّل مهمة تعرّف بشرط «على الجهاز» بيفشل بعدها). أول نسخة
/// كانت مستنياه في `onError` بس، فالاستثناء كان بيتعامل معاه على إنه
/// «سكوت» — والمريض بيسمع «معلش، مافهمتش» فوراً من غير ما المايك يتفتح
/// (آيفون، ٢٦ سبتمبر ٢٠٢٦). والمهمة اللي الإضافة سابتها شغّالة كانت بتخلّي
/// كل سماع بعده يرجع «مشغول» — عشان كده [stop] بتلغي على الناحية الأصلية
/// **دايماً**، مش بس لما دارت فاكرة إنها بتسمع.
class SpeechToTextListener implements SpeechListener {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;
  bool _onDeviceRefused = false;
  bool? _lastOnDevice;
  Completer<ListenResult>? _pending;
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
  Future<ListenFailed?> prepare() async {
    if (_ready) return null;
    try {
      final ok = await _stt.initialize(onError: _onError, onStatus: _onStatus);
      if (!ok) {
        // الإضافة بترجّع false للرفض وللموبايل اللي مفيهوش تعرّف — الإذن
        // هو اللي بيفرّق بينهم
        final permitted = await hasPermission();
        final why = _stt.lastError?.errorMsg ?? (permitted ? 'init_failed' : 'permission');
        diag('Listen: المتعرّف رفض يتجهّز ($why${permitted ? '' : ' — الإذن'})');
        return ListenFailed(why, permission: !permitted);
      }
      final locales = await _stt.locales();
      String norm(String id) => id.toLowerCase().replaceAll('-', '_');
      final ids = [for (final l in locales) l.localeId];
      _localeId = ids.cast<String?>().firstWhere((id) => norm(id!) == 'ar_eg',
          orElse: () => ids.cast<String?>().firstWhere((id) => norm(id!).startsWith('ar'), orElse: () => null));
      diag('Listen: جاهز — اللغة ${_localeId ?? 'لغة النظام'} (${ids.length} لغة)');
      _ready = true;
      return null;
    } catch (e) {
      diag('Listen: التجهيز وقع ($e)');
      return ListenFailed('init: $e');
    }
  }

  @override
  Future<ListenResult> listen({
    Duration silence = const Duration(seconds: 6),
    Duration maxLength = const Duration(seconds: 12),
  }) async {
    if (!_ready) return const ListenFailed('not_ready');
    await stop();
    final result = _pending = Completer<ListenResult>();
    _partial = '';
    final onDevice = !_onDeviceRefused;
    try {
      await _start(onDevice: onDevice, silence: silence, maxLength: maxLength);
    } catch (e) {
      if (onDevice && _isOnDeviceRefusal(e)) {
        _onDeviceRefused = true;
        diag('Listen: التعرّف على الجهاز مش متاح للعربي هنا — الصوت هيتبعت للسيرفر بتاع النظام ($e)');
        // الإضافة بتسيب مهمة شغّالة ورا الاستثناء — لازم تتلغي قبل الإعادة
        await _cancelNative();
        try {
          await _start(onDevice: false, silence: silence, maxLength: maxLength);
        } catch (e2) {
          return _startFailed('start(server): $e2');
        }
      } else {
        return _startFailed('start: $e');
      }
    }
    // حارس: لو المتعرّف ما رجّعش ولا حالة (بيحصل)، بنقفل بإيدنا
    _guard = Timer(maxLength + silence + const Duration(seconds: 2), () {
      unawaited(_cancelNative());
      _finish(_heardOr(const ListenSilence()));
    });
    return result.future;
  }

  ListenResult _startFailed(String why) {
    diag('Listen: بدء السماع وقع ($why)');
    final failed = ListenFailed(why, permission: why.contains('not_authorized') || why.contains('permission'));
    _finish(failed);
    return failed;
  }

  static bool _isOnDeviceRefusal(Object e) {
    final s = e.toString().toLowerCase().replaceAll(' ', '');
    return s.contains('ondevice');
  }

  Future<void> _start({required bool onDevice, required Duration silence, required Duration maxLength}) async {
    _lastOnDevice = onDevice;
    await _stt.listen(
      onResult: (r) {
        if (r.recognizedWords.isNotEmpty) _partial = r.recognizedWords;
        if (r.finalResult) _finish(_heardOr(const ListenSilence()));
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

  ListenResult _heardOr(ListenResult otherwise) => _partial.isEmpty ? otherwise : ListenHeard(_partial);

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg;
    // آيفون قديم: الرفض ممكن يجي كنداء كمان — نعيد مرة عبر أبل، ونقولها
    if (!_onDeviceRefused && msg.toLowerCase().contains('ondevice') && _pending != null && !_pending!.isCompleted) {
      _onDeviceRefused = true;
      diag('Listen: التعرّف على الجهاز مش متاح — الصوت هيتبعت للسيرفر بتاع النظام');
      unawaited(_cancelNative().then((_) => _start(onDevice: false, silence: const Duration(seconds: 6), maxLength: const Duration(seconds: 12)))
          .catchError((Object err) {
        _finish(ListenFailed('retry: $err'));
        diag('Listen: الإعادة وقعت ($err)');
      }));
      return;
    }
    if (msg == 'error_no_match' || msg == 'error_speech_timeout') {
      _finish(_heardOr(const ListenSilence()));
      return;
    }
    diag('Listen: $msg (${e.permanent ? 'دايم' : 'عابر'})');
    _finish(_heardOr(ListenFailed(msg, permission: msg.contains('not_authorized') || msg.contains('permission'))));
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // النهاية من غير نتيجة نهائية — آخر جزء مسموع هو الإجابة
      Future<void>.delayed(const Duration(milliseconds: 300), () => _finish(_heardOr(const ListenSilence())));
    }
  }

  void _finish(ListenResult result) {
    _guard?.cancel();
    _guard = null;
    final p = _pending;
    if (p == null || p.isCompleted) return;
    _pending = null;
    p.complete(result);
  }

  /// إلغاء على الناحية الأصلية — **من غير شرط `isListening`**: بعد استثناء من
  /// `listen()` دارت فاكرة إنها مش بتسمع والإضافة سايبة مهمة شغّالة.
  Future<void> _cancelNative() async {
    if (!_ready) return;
    try {
      await _stt.cancel();
    } catch (e) {
      diag('Listen: الإلغاء وقع ($e)');
    }
  }

  @override
  Future<void> stop() async {
    _finish(const ListenSilence());
    await _cancelNative();
  }
}
