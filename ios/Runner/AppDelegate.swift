import Flutter
import UIKit
import UserNotifications
import os
// لازم عشان FlutterLocalNotificationsPlugin.setPluginRegistrantCallback
import flutter_local_notifications

/// أثر تشخيصي بيعيش من غير مصحّح متوصّل.
///
/// السؤال اللي الملف ده موجود عشانه: دوسة «أخدته» على شاشة القفل بتوصل
/// لفين بالظبط؟ النظام بيشغّل العملية أصلاً؟ المحرّك بيقوم؟ سلسلة الإضافة
/// بتبلع الرد؟ ولا حاجة من دي ليها اختبار، والتطبيق مقفول فمفيش terminal.
///
/// فكل سطر بيروح لمكانين: `os_log` (Console.app، فلتر واحد على `FKDIAG`)
/// وملف نصي في Documents. **دارت بتكتب في نفس الملف** عن طريق
/// `lib/core/diagnostics.dart`، فترتيب سويفت ودارت مع بعض بيبان في مكان
/// واحد — وده بالظبط اللي محتاجين نشوفه.
enum FKDiag {
  /// نفس السابقة اللي في `diagnostics.dart` — فلتر واحد للسكّة كلها.
  private static let prefix = "FKDIAG "
  private static let fileName = "fkdiag.log"
  private static let maxLines = 200
  private static let trimAtBytes = 32 * 1024

  private static let logger = OSLog(subsystem: "com.fakkarni.fakkarni", category: "diag")

  private static let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  static func log(_ message: String) {
    let line = prefix + message
    os_log("%{public}@", log: logger, type: .default, line)
    append("\(stamp.string(from: Date()))  \(line)")
  }

  /// نفس مجلد `getApplicationDocumentsDirectory()` على iOS بالظبط.
  private static var file: URL? {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent(fileName)
  }

  /// تشخيص فاشل عمره ما يوقّع اللي بيشخّصه — كل حاجة هنا `try?`.
  private static func append(_ line: String) {
    guard let file else { return }
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: file) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: file)
    }
    trimIfNeeded(file)
  }

  private static func trimIfNeeded(_ file: URL) {
    guard
      let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
      size > trimAtBytes,
      let text = try? String(contentsOf: file, encoding: .utf8)
    else { return }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.last?.isEmpty == true { lines.removeLast() }
    guard lines.count > maxLines else { return }
    let kept = lines.suffix(maxLines).joined(separator: "\n") + "\n"
    try? kept.write(to: file, atomically: true, encoding: .utf8)
  }

  static func name(of state: UIApplication.State) -> String {
    switch state {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown(\(state.rawValue))"
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // أول سطر في العملية كلها. لو ده ما ظهرش، النظام أصلاً ما شغّلش
    // التطبيق — والباقي كله مش هيحصل.
    let keys = launchOptions.map { "\($0.keys.map(\.rawValue))" } ?? "nil"
    FKDiag.log("didFinishLaunching — launchOptions=\(keys) "
      + "state=\(FKDiag.name(of: UIApplication.shared.applicationState))")

    // من غير السطر ده iOS مش بيعرض التذكير والتطبيق مفتوح قدام المستخدم.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FKDiag.log("didInitializeImplicitFlutterEngine")

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
      // بيتنده ساعة ما المحرّك التاني يقوم بجد — مش دلوقتي. ظهوره معناه
      // إن النظام وصل لمرحلة تشغيل محرّك خلفي.
      FKDiag.log("registerPlugins — المحرّك الخلفي بيتسجّل")
      GeneratedPluginRegistrant.register(with: registry)
      // مهلة الخلفية — **على المحرّك الخلفي قبل أي حاجة تانية**. الإضافة
      // بترجّع completionHandler فوراً وما بتاخدش assertion، فمن غير
      // القناة دي الـisolate بيكتب الجرعة والنظام من حقه يوقّفه في نُصّها.
      if let registrar = registry.registrar(forPlugin: "BackgroundTaskChannel") {
        BackgroundTaskChannel.register(with: registrar.messenger())
      }
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // «قريب منك» من خرايط أبل — قناة صغيرة، على المحرّك الرئيسي بس (صحوة
    // الخلفية ما بتدوّرش على صيدليات).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlacesChannel") {
      PlacesChannel.register(with: registrar.messenger())
    }

    // ونفس القناة على المحرّك الرئيسي كمان: لو نفس كود دارت اتنفّذ جوّه
    // التطبيق، لازم يلاقي القناة بدل ما يرمي MissingPluginException.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskChannel") {
      BackgroundTaskChannel.register(with: registrar.messenger())
    }
  }

  /// **بيسجّل وبس، وبعدين بيندَه super.** السلوك زي ما هو بالظبط —
  /// اللي بيعالج الرد فعلاً هي سلسلة الإضافات جوّه `FlutterAppDelegate`.
  /// لو السطر ده ظهر والـ`Isolate:` اللي بعده ما ظهرش، يبقى النظام سلّم
  /// الرد والسلسلة بلعته.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    FKDiag.log("didReceive — action=\(response.actionIdentifier) "
      + "category=\(response.notification.request.content.categoryIdentifier)")
    super.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
