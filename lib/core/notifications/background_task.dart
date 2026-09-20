import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// طلب من iOS إنه يسيب العملية شغّالة شوية كمان.
///
/// **ده مش رفاهية، ده اللي بيخلّي تأكيد من شاشة القفل يتسجّل أصلاً.**
/// الإضافة (`flutter_local_notifications` 22.3.0) بتنده
/// `completionHandler()` فوراً — قبل ما أول سطر دارت يشتغل — وما بتاخدش
/// `beginBackgroundTask` ولا مرة. الـcompletion handler ده هو الحاجة
/// الوحيدة اللي بتقول للنظام «لسه بشتغل»؛ أول ما يرجع، النظام من حقه
/// يوقّف العملية في أي لحظة. يعني الـisolate بيكتب الجرعة وهو مش مضمون
/// إنه يخلّص السطر اللي بعده.
///
/// فبنطلب المهلة بإيدينا: `begin()` أول حاجة في الصحوة، و`end()` في
/// `finally`. **من غير `end` النظام بيقفل التطبيق قفل** لما المهلة تخلص،
/// فالتوكن بيترجّع دايماً — وناحية Swift فيه `expirationHandler` بينهيها
/// لو إحنا ما لحقناش.
///
/// أندرويد مالوش نظير: هناك الصحوة `BroadcastReceiver` وبتمسك wake lock
/// بنفسها — القناة مش متسجّلة فبيرجع null والـ`end` بتبقى لا-عملية.
/// نفس الحال في `flutter test`.
abstract final class BackgroundTask {
  static const _channel = MethodChannel('fakkarni/background_task');

  /// أقصى استنى للقناة نفسها.
  ///
  /// نداء محلي المفروض يخلص في أجزاء من الملي ثانية؛ لو علّق، يبقى
  /// إحنا بنضيّع من الوقت اللي طالبينه أصلاً. بنكمّل من غيره.
  static const _limit = Duration(milliseconds: 500);

  /// بترجّع توكن يترد لـ[end]، أو null لو النظام مش بيدي واحد.
  static Future<int?> begin() async {
    try {
      final token = await _channel.invokeMethod<int>('begin').timeout(_limit);
      debugPrint('Isolate: مهلة الخلفية — ${token == null ? 'مفيش' : 'اتاخدت'}');
      return token;
    } catch (error) {
      debugPrint('Isolate: مهلة الخلفية — ما اتاخدتش ($error)');
      return null;
    }
  }

  /// لازم تتنده، وفي `finally`.
  static Future<void> end(int? token) async {
    if (token == null) return;
    try {
      await _channel.invokeMethod<void>('end', token).timeout(_limit);
    } catch (error) {
      debugPrint('Isolate: إنهاء مهلة الخلفية فشل ($error)');
    }
  }
}
