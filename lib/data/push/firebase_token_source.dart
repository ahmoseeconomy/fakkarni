import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, TargetPlatform;

import 'push_tokens.dart';

/// **الملف الوحيد في التطبيق اللي بيستورد Firebase.** أي ملف تاني
/// بيستورده يبقى كسر للحاجز — زي ما `lib/data/auth/` بيلمّ Supabase.
///
/// أندرويد بس هذه الجولة. iOS محتاج شهادة APNs وحساب مطوّر مدفوع (البند
/// ٣ في «دين تقني»)، و`getToken()` على iOS من غيرها بترمي. فبنرجّع null
/// عند التهيئة بدل ما نكسر إقلاع التطبيق على أيفون.
class FirebaseTokenSource implements DeviceTokenSource {
  FirebaseTokenSource._();

  /// بترجّع null لو Firebase مش متاح — والتطبيق بيكمّل كامل من غير دفع،
  /// زي ما بيكمّل من غير Supabase ومن غير Gemini.
  ///
  /// `Firebase.initializeApp()` من غير `firebase_options.dart`: على
  /// أندرويد إضافة google-services بتولّد الموارد من
  /// `android/app/google-services.json` وقت البناء، فمفيش داعي لملف
  /// مولّد من flutterfire CLI ولا لمفاتيح في الكود.
  static Future<FirebaseTokenSource?> initialise() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      debugPrint('Push: الدفع أندرويد بس دلوقتي — iOS مستني APNs');
      return null;
    }
    try {
      await Firebase.initializeApp();
      return FirebaseTokenSource._();
    } catch (error) {
      // أشهر سبب: google-services.json ناقص أو الإضافة مش مطبّقة.
      debugPrint('Push: Firebase ما اتهيّأش — $error');
      return null;
    }
  }

  @override
  PushPlatform get platform => PushPlatform.android;

  @override
  Future<bool> ensurePermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error) {
      debugPrint('Push: طلب الإذن فشل — $error');
      return false;
    }
  }

  @override
  Future<String?> token() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('Push: getToken فشل — $error');
      return null;
    }
  }

  @override
  Stream<String> get refreshes => FirebaseMessaging.instance.onTokenRefresh;
}
