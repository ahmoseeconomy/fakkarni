import Flutter
import UIKit
import UserNotifications
// لازم عشان FlutterLocalNotificationsPlugin.setPluginRegistrantCallback
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // من غير السطر ده iOS مش بيعرض التذكير والتطبيق مفتوح قدام المستخدم.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // زرار «أخدته» والتطبيق مقفول خالص بيشغّل **محرّك فلاتر تاني خالص**،
    // مش المحرّك الرئيسي. المحرّك ده بياخد صفر إضافات لو ما سجّلناش
    // الـcallback دي، فـonBackgroundNotificationAction بتموت قبل أول
    // سطر فيها: لا drift، لا path_provider، ولا حتى debugPrint.
    //
    // الشكل ده مأخوذ من README الإضافة المتسطّبة (النسخة بتاعة دورة حياة
    // UIScene — وهي اللي التطبيق ده عليها، لأنه بيسجّل في
    // didInitializeImplicitFlutterEngine مش في didFinishLaunchingWithOptions).
    // والمصدر نفسه بيأكّدها: FlutterEngineManager.m بيعمل
    // `NSAssert(registerPlugins != nil)` وبعدين `registerPlugins(backgroundEngine)`.
    //
    // السطر التاني (تسجيل المحرّك الرئيسي) **بيفضل زي ما هو** — الاتنين
    // محرّكين مختلفين ومحتاجين تسجيل كل واحد لوحده.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // «قريب منك» من خرايط أبل — قناة صغيرة، على المحرّك الرئيسي بس (صحوة
    // الخلفية ما بتدوّرش على صيدليات).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlacesChannel") {
      PlacesChannel.register(with: registrar.messenger())
    }
  }
}
