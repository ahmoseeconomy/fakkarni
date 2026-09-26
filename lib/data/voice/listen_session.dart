import 'speech_listener.dart';

/// اللي المتعرّف قال عليه وقرارنا فيه.
sealed class ListenDecision {
  const ListenDecision();
}

/// السماع خلص بالنتيجة دي.
final class ListenFinish extends ListenDecision {
  const ListenFinish(this.result);
  final ListenResult result;
}

/// ابدأ تاني بعد [ListenSession.retryAfter]. [onDevice] false = عبر سيرفر
/// النظام (مكتوب في سياسة الخصوصية).
final class ListenRetry extends ListenDecision {
  const ListenRetry(this.why, {required this.onDevice});
  final String why;
  final bool onDevice;
}

/// **مين صاحب الحدث ده، ونعمل إيه؟** — دارت نقية، من غير الإضافة، عشان
/// تتختبر.
///
/// **من لوج الجهاز (آيفون، profile، صفحة الجنس، ٢٦ سبتمبر ٢٠٢٦):**
/// ```
/// Listen: جاهز — اللغة ar-SA (62 لغة)
/// Listen: بدء السماع وقع (start: Instance of 'ListenFailedException')
/// Listen: error_listen_failed (دايم)
/// ```
/// `error_listen_failed` بيتبعت من `catch` بتاع `listenForSpeech` في سويفت
/// بس — يعني تجهيز جلسة الصوت أو تشغيل محرّك الصوت رمى. والإضافة بتبعت
/// **الاتنين** لنفس الوقعة (الاستثناء من `listen()` والعطل بعده)، فالتانية
/// مش وقعة جديدة. والقاعدة:
/// - وقعة في البداية (استثناء أو `error_listen_failed` قبل «listening») =
///   **إعادة مرة** بعد [retryAfter]؛ رفض «على الجهاز» = الإعادة عبر السيرفر.
///   التانية = [ListenFailed] (`started: false`) — «كمّل بإيدك» والسبب للسجل.
/// - وإحنا مستنيين الإعادة، أي حدث تاني من المحاولة اللي وقعت بيتساب.
/// - حالة أو عطل **قبل** «listening» بتاع المحاولة دي = بقايا مهمة قديمة.
/// - أكواد الإلغاء (إحنا اللي لغينا) عمرها ما تبقى نتيجة.
/// - «مفيش كلام» (`error_no_match` / `error_speech_timeout`) = سكوت.
/// - عطل **بعد ما بدأ** = [ListenFailed] (`started: true`) — تعثّرة زي
///   «مافهمتش»، مش «المايك ما اشتغلش».
class ListenSession {
  ListenSession({required this.onDevice, this.serverRetried = false});

  static const retryAfter = Duration(milliseconds: 300);

  /// المحاولة دي على الجهاز؟
  bool onDevice;

  /// اتعاد عبر السيرفر مرة خلاص.
  bool serverRetried;

  /// اتعاد بعد وقعة في البداية مرة خلاص.
  bool startRetried = false;

  /// قرار إعادة اتاخد ولسه ما بدأش — أحداث المحاولة اللي وقعت بتتساب.
  bool awaitingRestart = false;

  /// المتعرّف قال «listening» للمحاولة دي.
  bool listeningSeen = false;
  String words = '';

  static const cancelCodes = {
    'error_request_cancelled',
    'error_unknown (216)',
    'error_unknown (301)',
    'error_client',
  };

  static bool isPermission(String msg) =>
      msg.contains('not_authorized') || msg.contains('permission') || msg.contains('insufficient_permissions');

  static bool isOnDeviceRefusal(String msg) {
    final s = msg.toLowerCase().replaceAll(' ', '');
    return s.contains('ondevice') || s.contains('assets_not_installed') || s.contains('language_unavailable');
  }

  ListenResult _heardOr(ListenResult otherwise) => words.isEmpty ? otherwise : ListenHeard(words);

  /// المحاولة الجديدة بدأت.
  void restart({required bool onDevice}) {
    this.onDevice = onDevice;
    listeningSeen = false;
    awaitingRestart = false;
  }

  void heard(String recognized) {
    if (recognized.isNotEmpty) words = recognized;
  }

  /// null = كمّل.
  ListenDecision? status(String s) {
    if (awaitingRestart) return null;
    if (s == 'listening') {
      listeningSeen = true;
      return null;
    }
    if (s == 'done' || s == 'notListening' || s == 'doneNoResult') {
      if (!listeningSeen) return null; // بقايا مهمة قبلها
      return ListenFinish(_heardOr(const ListenSilence()));
    }
    return null;
  }

  /// null = اتساب (بقايا، إلغاء إحنا عملناه، أو مستنيين إعادة).
  ListenDecision? error(String msg) {
    if (awaitingRestart) return null;
    if (isPermission(msg)) return ListenFinish(ListenFailed(msg, permission: true, started: listeningSeen));
    if (cancelCodes.contains(msg)) return null;
    if (msg == 'error_no_match' || msg == 'error_speech_timeout') {
      return listeningSeen || words.isNotEmpty ? ListenFinish(_heardOr(const ListenSilence())) : null;
    }
    if (!listeningSeen) {
      if (msg == 'error_listen_failed' || isOnDeviceRefusal(msg)) return startFailure(msg);
      return null;
    }
    if (onDevice && !serverRetried && words.isEmpty) return _retry(msg, onDevice: false);
    return ListenFinish(_heardOr(ListenFailed(msg, started: true)));
  }

  /// البداية وقعت — استثناء من `listen()` أو `error_listen_failed` قبل
  /// «listening». null = نفس الوقعة اتعاملت خلاص.
  ListenDecision? startFailure(String msg) {
    if (awaitingRestart) return null;
    if (isPermission(msg)) return ListenFinish(ListenFailed(msg, permission: true));
    if (onDevice && !serverRetried && isOnDeviceRefusal(msg)) return _retry(msg, onDevice: false);
    if (!startRetried) {
      startRetried = true;
      return _retry(msg, onDevice: onDevice);
    }
    return ListenFinish(ListenFailed(msg));
  }

  ListenDecision _retry(String why, {required bool onDevice}) {
    if (!onDevice && this.onDevice) serverRetried = true;
    awaitingRestart = true;
    return ListenRetry(why, onDevice: onDevice);
  }
}
