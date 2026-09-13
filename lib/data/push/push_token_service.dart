// ignore_for_file: prefer_initializing_formals
// المُنشئ بيربط معاملات عامة بحقول خاصة — نفس أسلوب SyncService.
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'push_tokens.dart';

/// القرار: إمتى نسجّل التوكن وإمتى نمسحه. دارت خالص — مفيش Firebase ولا
/// Supabase هنا، عشان الاختبار يشغّل الحكاية كلها بمزيّفين.
///
/// السياسة زي المزامنة بالظبط: **صامتة**. أي فشل بيتسجّل في اللوج
/// وبيتساب؛ المحاولة الجاية بتيجي لوحدها عند أقرب دخول أو تدوير توكن أو
/// فتحة تطبيق. المريض ولا ابنه المفروض يشوفوا كلمة عن «تسجيل التوكن».
///
/// وفيه فرق واحد مهم عن المزامنة: فشل هنا معناه **مفيش تنبيه خالص**، مش
/// صف متأخر. عشان كده التسجيل بيتعاد عند كل دخول وكل تدوير، والفحص
/// السحابي بيقول `no_token` بصوت عالي في اللوج بدل ما يعدّي في صمت.
class PushTokenService implements PushTokens {
  PushTokenService({
    required DeviceTokenSource source,
    required PushTokenRemote remote,
    required Stream<bool> signedIn,
    required bool Function() isSignedIn,
  })  : _source = source,
        _remote = remote,
        _signedIn = signedIn,
        _isSignedIn = isSignedIn;

  final DeviceTokenSource _source;
  final PushTokenRemote _remote;
  final Stream<bool> _signedIn;
  final bool Function() _isSignedIn;

  StreamSubscription<bool>? _authSub;
  StreamSubscription<String>? _refreshSub;

  /// آخر توكن اتحجز بنجاح — عشان ما نرجعش نكلّم السحابة من غير داعي.
  /// بيتصفّر عند الخروج، فأي دخول جديد بيحجز من أول وجديد حتى لو نفس
  /// التوكن: صاحبه اتغيّر، وده بالظبط اللي `claim_device_token` بيحلّه.
  String? _claimed;

  @override
  void start() {
    _authSub = _signedIn.listen((signedIn) {
      if (signedIn) {
        unawaited(registerNow());
      } else {
        // مش بنمسح الصف من هنا: الخروج بيكون خلص خلاص ومفيش صلاحية.
        // المسح مكانه [clear] قبل الخروج.
        _claimed = null;
      }
    });

    _refreshSub = _source.refreshes.listen((token) {
      if (!_isSignedIn()) return;
      unawaited(_claim(token));
    });
  }

  @override
  Future<void> registerNow() async {
    if (!_isSignedIn()) return;

    // الإذن بيتطلب، بس رفضه **مش** بيمنع التسجيل: التوكن بيفضل صالح،
    // والابن ممكن يفتح الإشعارات من إعدادات الموبايل بعدين من غير ما
    // يرجع للتطبيق. صف ناقص ساعتها معناه صمت دايم من غير سبب.
    final granted = await _source.ensurePermission();
    if (!granted) {
      debugPrint('Push: إذن الإشعارات مترفض — بنسجّل التوكن برضه');
    }

    final token = await _source.token();
    if (token == null || token.isEmpty) {
      debugPrint('Push: مفيش توكن من الجهاز — التنبيه مش هيوصل');
      return;
    }
    await _claim(token);
  }

  Future<void> _claim(String token) async {
    if (token == _claimed) return;
    try {
      await _remote.claim(token, _source.platform);
      _claimed = token;
      debugPrint('Push: التوكن اتسجّل');
    } catch (error) {
      // بنسيب `_claimed` زي ما هو عشان المحاولة الجاية تعيد الكرّة.
      debugPrint('Push: تسجيل التوكن فشل — $error');
    }
  }

  @override
  Future<void> clear() async {
    final token = _claimed ?? await _safeToken();
    if (token == null) return;
    try {
      await _remote.remove(token);
      debugPrint('Push: التوكن اتشال قبل الخروج');
    } catch (error) {
      debugPrint('Push: مسح التوكن فشل — $error');
    }
    _claimed = null;
    // **مش** بنمسح توكن Firebase نفسه: هو بتاع النسخة المتسطّبة مش بتاع
    // الحساب، ولو مسحناه التذكيرات المحلية ما بتتأثرش لكن الدخول الجاي
    // بيستنى توكن جديد بلا داعي. إعادة ربطه لصاحبه الجديد شغلانة
    // `claim_device_token`.
  }

  Future<String?> _safeToken() async {
    try {
      return await _source.token();
    } catch (error) {
      debugPrint('Push: مقدرناش نجيب التوكن للمسح — $error');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _refreshSub?.cancel();
    _authSub = null;
    _refreshSub = null;
  }
}
