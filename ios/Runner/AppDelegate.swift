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

/// **طابور زرار الإشعار — بيتكتب هنا، في سويفت، قبل أي حاجة فلاتر.**
///
/// الدليل من `fkdiag.log` (٢٥ سبتمبر ٢٠٢٦، نسخة profile): لما النظام
/// بيشغّل التطبيق عشان الدوسة، الإضافة بترجّع `completionHandler` فوراً
/// والعملية بتتقتل بعد ~٨ ثواني قبل ما المحرّك الخلفي يسجّل إضافاته
/// (`didFinishLaunching 23:36:05.9` ← `didReceive 23:36:06.1` ← ولا سطر
/// ← `didFinishLaunching 23:36:14.2`). ولما يفشل مرة، `startEngineIfNeeded`
/// بترجع من أول سطر لباقي عمر العملية (`if (backgroundEngine) return`) —
/// فكل دوسة بعدها في نفس العملية بتتبلع (١٩:٣٦، ١٩:٣٩، ١٩:٤٥). والإضافة
/// **ما بتحفظش** رد الإطلاق لزرار مش `foreground`، فسكّة `main` ما بتشوفه.
///
/// فالدوسة بتتسجّل كملف صغير `Documents/pending_actions/<uuid>.json`
/// **قبل** ما الرد يتسلّم للإضافة، وبناخد `beginBackgroundTask` عشان
/// العملية تعيش لحد ما دارت تقرا الطابور (`main` عند الفتح، والرجوع
/// للمقدمة، والـisolate لو اشتغل). ملف لكل دوسة = مفيش سباق قراية وكتابة.
/// الأسامي دي مرآة لـ`pending_actions.dart` — اختبار بيقفل عليها.
enum PendingActionQueue {
  static let folder = "pending_actions"
  static let category = "fakkarni_dose"
  /// أطول من الوقت اللي `main` محتاجه لحد ما يوصل للطابور، وأقل من الـ٣٠
  /// ثانية اللي النظام بيسمح بيها.
  static let holdSeconds = 25.0

  static var directory: URL? {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent(folder, isDirectory: true)
  }

  /// بترجّع true لو الملف اتكتب.
  static func enqueue(_ response: UNNotificationResponse) -> Bool {
    let content = response.notification.request.content
    guard content.categoryIdentifier == category else { return false }
    let action = response.actionIdentifier
    guard action != UNNotificationDefaultActionIdentifier,
          action != UNNotificationDismissActionIdentifier else { return false }
    guard let dir = directory else { return false }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var record: [String: Any] = [
      "v": 1,
      "action": action,
      "id": Int(response.notification.request.identifier) ?? -1,
      "at": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let payload = content.userInfo["payload"] as? String { record["payload"] = payload }
    guard let data = try? JSONSerialization.data(withJSONObject: record) else { return false }
    let file = dir.appendingPathComponent("\(UUID().uuidString).json")
    return (try? data.write(to: file, options: .atomic)) != nil
  }

  /// مهلة خلفية بإيدينا — الإضافة ما بتاخدش ولا واحدة.
  static func hold() {
    var token = UIBackgroundTaskIdentifier.invalid
    token = UIApplication.shared.beginBackgroundTask(withName: "FakkarniPendingAction") {
      UIApplication.shared.endBackgroundTask(token)
      token = .invalid
    }
    guard token != .invalid else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
      if token != .invalid {
        UIApplication.shared.endBackgroundTask(token)
        token = .invalid
      }
    }
  }
}

/// **«أخدته» والتطبيق عايش** — للإنجن الرئيسي مباشرة، مش لإنجن تاني.
///
/// الإضافة بتبعت الزرار (مش `foreground`) لإنجن فلاتر تاني بتقوّمه ساعتها
/// وبترجّع `completionHandler()` فوراً — حتى والتطبيق شغّال. على الآيفون
/// (٢٦ سبتمبر ٢٠٢٦، release، التطبيق في الخلفية): أول «أخدته» ما اتسجّلتش
/// وإعادة الـ+٥ رنّت. فلو دارت على الإنجن الرئيسي قالت `ready`، الدوسة (اللي
/// اتكتبت في الطابور خلاص) بتتطبّق هناك بـ`drain`، و`completionHandler`
/// بيستنى الرد — ومفيش إنجن تاني. إطلاق جديد في الخلفية (لسه مفيش `ready`)
/// بيمشي زي الأول: الإضافة، و`main` بتطبّق الطابور لما توصله.
/// اسم القناة مرآة لـ`LiveActions.channelName` — اختبار بيقفل عليها.
enum LiveActionChannel {
  static let name = "fakkarni/actions"
  static var channel: FlutterMethodChannel?
  static var ready = false
  /// أقل من مهلة الخلفية (`holdSeconds`) — الرد لازم يرجع قبلها.
  static let replySeconds = 20.0

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      if call.method == "ready" {
        ready = true
        FKDiag.log("live — دارت جاهزة على الإنجن الرئيسي")
      }
      result(nil)
    }
    channel = ch
  }

  /// true = اتسلّمت للإنجن الرئيسي، و[done] هيتنده لما يرد (أو بعد المهلة).
  static func deliver(_ done: @escaping () -> Void) -> Bool {
    guard ready, let ch = channel else { return false }
    var finished = false
    let finish = {
      if !finished {
        finished = true
        done()
      }
    }
    ch.invokeMethod("drain", arguments: nil) { reply in
      FKDiag.log("live — drain رجع \(reply ?? "nil")")
      finish()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + replySeconds) { finish() }
    return true
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

    // مجلد المستندات لدارت **من غير قناة**: `diag` والطابور بيتقروا من
    // الـisolate، واللحظة دي مش وقت نداء قناة. `HOME` كان المفروض يكفي،
    // بس ولا سطر دارت وصل الملف على الجهاز — فالمسار بيتحط في البيئة
    // صراحةً قبل ما أي محرّك يقوم.
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      setenv("FAKKARNI_DOCS", docs.path, 1)
    }

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

    // «أخدته» والتطبيق عايش — على الإنجن الرئيسي بس
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActionChannel") {
      LiveActionChannel.register(with: registrar.messenger())
    }

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
    // **الطابور الأول، وقبل الإضافة**: لو كل اللي بعده مات، الدوسة محفوظة.
    if PendingActionQueue.enqueue(response) {
      PendingActionQueue.hold()
      FKDiag.log("queued — action=\(response.actionIdentifier) في pending_actions")
      // التطبيق عايش ودارت جاهزة: الإنجن الرئيسي بيطبّق الطابور، والإضافة ما
      // بتقوّمش إنجن تاني لنفس الدوسة
      if LiveActionChannel.deliver(completionHandler) {
        FKDiag.log("live — اتسلّمت للإنجن الرئيسي")
        return
      }
    }
    super.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
