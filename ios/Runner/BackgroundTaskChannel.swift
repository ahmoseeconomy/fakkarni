import Flutter
import UIKit

/// `UIApplication.beginBackgroundTask` من دارت — للـisolate اللي بيصحى
/// من زرار على الإشعار.
///
/// **ليه ده موجود:** `FlutterLocalNotificationsPlugin` بينده
/// `completionHandler()` بتاع `didReceiveNotificationResponse` **فوراً**،
/// قبل ما المحرّك التاني يشتغل أصلاً، وما بياخدش أي background task
/// assertion. الـcompletion handler ده هو الحاجة الوحيدة اللي بتقول للنظام
/// «لسه بشتغل»، فأول ما يرجع، العملية ممكن تتوقّف في أي لحظة — وسط كتابة
/// الجرعة أو قبل إلغاء درجات السلّم. التأكيد من شاشة القفل بيبقى وقتها
/// «اتداس» من غير ما يتسجّل.
///
/// القناة دي بتتسجّل على **المحرّكين**: الرئيسي والخلفي (شوف
/// `AppDelegate.didInitializeImplicitFlutterEngine`) — الرئيسي عشان نفس
/// كود دارت ما يفشلش لو اتنفّذ جوّه التطبيق.
enum BackgroundTaskChannel {
  private static let name = "fakkarni/background_task"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "begin":
        if let token = begin() {
          result(token)
        } else {
          result(nil)
        }
      case "end":
        end(call.arguments as? Int)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// بترجّع التوكن كـInt، أو nil لو النظام رفض.
  ///
  /// `expirationHandler` **مش اختياري**: لو المهلة خلصت وإحنا لسه ماسكينها،
  /// النظام بيقفل التطبيق قفل. فبننهيها بنفسنا هناك — دارت ساعتها بتكون
  /// بتنادي `end` على توكن خلص، وده آمن.
  private static func begin() -> Int? {
    var token = UIBackgroundTaskIdentifier.invalid
    token = UIApplication.shared.beginBackgroundTask(withName: "FakkarniDoseConfirm") {
      UIApplication.shared.endBackgroundTask(token)
      token = .invalid
    }
    return token == .invalid ? nil : token.rawValue
  }

  private static func end(_ raw: Int?) {
    guard let raw else { return }
    let token = UIBackgroundTaskIdentifier(rawValue: raw)
    guard token != .invalid else { return }
    UIApplication.shared.endBackgroundTask(token)
  }
}
