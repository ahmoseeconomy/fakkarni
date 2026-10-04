import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, TargetPlatform;

import 'confirm_signals.dart';
import 'firebase_ios_options.dart';
import 'push_tokens.dart';

/// **الملف الوحيد في التطبيق اللي بيستورد Firebase.** أي ملف تاني
/// بيستورده يبقى كسر للحاجز — زي ما `lib/data/auth/` بيلمّ Supabase.
///
/// أندرويد وiOS (الدين ٣ اتدفع ٤ أكتوبر ٢٠٢٦: مفتاح APNs ‏Production-only
/// ‏`SD46FFWC42` اترفع على Firebase للتطبيق `com.fakrny.app`). على iOS
/// التهيئة بالقيم الصريحة ([firebaseIosOptions]) — مش بالـplist جوّه
/// الحزمة، عشان `project.pbxproj` عمره ما بيتكوميت. والمفتاح Production
/// بس: نسخة TestFlight/المتجر بتستلم، و`flutter run` على الجهاز (توكن
/// sandbox) **لأ** — بيتسجّل التوكن وبيقف عند `InvalidApnsCredential`
/// في سجل دالة `escalate`، مش عندنا.
class FirebaseTokenSource implements DeviceTokenSource, PushMessages {
  FirebaseTokenSource._();

  /// بترجّع null لو Firebase مش متاح — والتطبيق بيكمّل كامل من غير دفع،
  /// زي ما بيكمّل من غير Supabase ومن غير Gemini.
  ///
  /// `Firebase.initializeApp()` من غير `firebase_options.dart`: على
  /// أندرويد إضافة google-services بتولّد الموارد من
  /// `android/app/google-services.json` وقت البناء، فمفيش داعي لملف
  /// مولّد من flutterfire CLI ولا لمفاتيح في الكود.
  static Future<FirebaseTokenSource?> initialise() async {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (!ios && defaultTargetPlatform != TargetPlatform.android) {
      debugPrint('Push: الدفع على أندرويد وiOS بس');
      return null;
    }
    try {
      // أندرويد: الموارد من google-services.json وقت البناء.
      // iOS: القيم صراحةً — الـplist متكوميت كمرجع ومرآة، مش في الحزمة.
      await Firebase.initializeApp(options: ios ? firebaseIosOptions : null);
      return FirebaseTokenSource._();
    } catch (error) {
      // أشهر سبب: google-services.json ناقص أو الإضافة مش مطبّقة.
      debugPrint('Push: Firebase ما اتهيّأش — $error');
      return null;
    }
  }

  @override
  PushPlatform get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? PushPlatform.ios : PushPlatform.android;

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
      // iOS: توكن FCM بيستنى توكن APNs، واللي بيوصل بعد `requestPermission`
      // بلحظة — `getToken` بدري بيرمي «APNS token has not been set».
      // تلات محاولات بثانيتين كفاية؛ بعدها بنسيبها للـrefresh العادي.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        for (var attempt = 0; attempt < 3; attempt++) {
          if (await FirebaseMessaging.instance.getAPNSToken() != null) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('Push: getToken فشل — $error');
      return null;
    }
  }

  @override
  Stream<String> get refreshes => FirebaseMessaging.instance.onTokenRefresh;

  /// رسايل الدفع الصامتة (0035 — إشارة «اتأكّدت») والتطبيق في المقدمة أو
  /// اتفتح من إشعار. الخلفية عندها بابها في [onBackgroundPush].
  @override
  Stream<Map<String, dynamic>> get data => StreamGroupLite.merge([
        FirebaseMessaging.onMessage.map((m) => m.data),
        FirebaseMessaging.onMessageOpenedApp.map((m) => m.data),
      ]);
}

/// دمج بسيط من غير حزمة — رسايل قليلة.
class StreamGroupLite {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    final controller = StreamController<T>.broadcast();
    for (final s in streams) {
      s.listen(controller.add, onError: controller.addError);
    }
    return controller.stream;
  }
}
