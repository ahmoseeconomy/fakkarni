import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// أزرار الإشعار — نفس المعرّفات على أندرويد وiOS.
///
/// المريض بيأكّد من شاشة القفل من غير ما يفتح التطبيق: النظام بيصحّي
/// التطبيق في الخلفية، وإحنا بنسجّل الجرعة **ونمدّ نافذة التذكيرات** في
/// نفس الصحوة. من غير كده التغطية كانت بتتجدد بس لما يفتح التطبيق — وهو
/// معندوش سبب يفتحه؛ التطبيق موجود عشان يفكّره هو.
abstract final class NotificationActions {
  static const taken = 'taken';
  static const snooze = 'snooze';

  static const takenLabel = 'أخدته';
  static const snoozeLabel = 'فكّرني بعدين';

  static bool isAction(String? id) => id == taken || id == snooze;
}

/// بيتنده في الخلفية لما المستخدم يدوس زرار على الإشعار.
typedef BackgroundActionHandler = Future<void> Function(
  NotificationResponse response,
);

/// خدمة التذكيرات المحلية.
///
/// كل التذكيرات بتتجدول **على الجهاز نفسه** — مش على سيرفر. يعني بتشتغل
/// من غير نت، ومليون مستخدم = مليون جهاز شغال لوحده بصفر تكلفة تشغيل.
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  /// آخر إشعار المستخدم دَس عليه.
  ///
  /// الشاشة بتسمع للقيمة دي وتفتح «يومك» على الجرعة الصح. من غيرها الـpayload
  /// بيروح في اللا مكان والدوسة على الإشعار بتفتح التطبيق على أول شاشة بس.
  static final ValueNotifier<String?> lastPayload = ValueNotifier<String?>(null);

  /// زرار على الإشعار والتطبيق مفتوح — بيتعالج هنا بخدمات التطبيق نفسها.
  ///
  /// شبكة أمان: الأزرار متعلّمة إنها ما بتفتحش واجهة، فالنظام بيبعتها
  /// للخلفية حتى والتطبيق مفتوح. لو وصلت هنا برضه، بنعالجها بدل ما نضيّعها.
  static void Function(String actionId, String? payload)? onAction;

  /// قناة الجرعات — أولوية عالية عشان تظهر فوق الشاشة وتصوّت.
  static const _doseChannel = AndroidNotificationChannel(
    'fakkarni_doses',
    'تذكير الأدوية',
    description: 'تنبيهات مواعيد الجرعات',
    importance: Importance.max,
  );

  /// فئة إشعار الجرعة على iOS — هي اللي بتحدد الأزرار.
  ///
  /// من غير `foreground` عن قصد: الزرار بيصحّي التطبيق في الخلفية بس، والمريض
  /// بيفضل على شاشة القفل.
  static final _doseCategory = DarwinNotificationCategory(
    'fakkarni_dose',
    actions: [
      DarwinNotificationAction.plain(
        NotificationActions.taken,
        NotificationActions.takenLabel,
      ),
      DarwinNotificationAction.plain(
        NotificationActions.snooze,
        NotificationActions.snoozeLabel,
      ),
    ],
  );

  /// [onBackgroundAction] لازم يكون دالة عليا معلّمة `@pragma('vm:entry-point')`
  /// — بتتنفذ في isolate منفصل والتطبيق ممكن يكون مقفول خالص.
  static Future<void> init({BackgroundActionHandler? onBackgroundAction}) async {
    if (_initialised) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _deviceTimezone()));

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // بنطلب الأذونات بأنفسنا في وقت مناسب، مش عند أول فتح
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [_doseCategory],
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundAction,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_doseChannel);

    // لو التطبيق كان مقفول خالص واتفتح من الإشعار نفسه، الدوسة دي مش بتعدّي
    // على _onTap — لازم نسألوا عليها بإيدنا.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      lastPayload.value = launch.notificationResponse?.payload;
    }

    _initialised = true;
  }

  static void _onTap(NotificationResponse response) {
    final action = response.actionId;
    if (NotificationActions.isAction(action) && onAction != null) {
      onAction!(action!, response.payload);
      return;
    }
    lastPayload.value = response.payload;
  }

  /// المنطقة الزمنية بتوقيت المريض — مش بتوقيت السيرفر.
  static Future<String> _deviceTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'Africa/Cairo';
    }
  }

  // ---------------------------------------------------------------- أذونات

  static Future<bool> requestPermissions() async {
    await init();

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  /// أندرويد ١٢+ بيمنع المنبّه الدقيق افتراضيًا.
  ///
  /// من غير الإذن ده النظام بيأجّل التذكير لحد ما "يشوفه مناسب" — وممكن
  /// يتأخر نص ساعة. ده مقبول لتطبيق أخبار، مش لجرعة دوا.
  static Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  static Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  // --------------------------------------------------------------- الجدولة

  static Future<void> scheduleDose({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    await init();

    final when = tz.TZDateTime.from(at, tz.local);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _doseChannel.id,
          _doseChannel.name,
          channelDescription: _doseChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // ملاحظة: مش بنستخدم fullScreenIntent — جوجل بلاي بتقصره على
          // تطبيقات المكالمات والمنبّهات، واستخدامه بيعرّض المراجعة للرفض.
          actions: const [
            // showsUserInterface: false → بتتعالج في الخلفية من غير ما
            // التطبيق يتفتح. الإشعار بيختفي بعد «أخدته» بس.
            AndroidNotificationAction(
              NotificationActions.taken,
              NotificationActions.takenLabel,
            ),
            AndroidNotificationAction(
              NotificationActions.snooze,
              NotificationActions.snoozeLabel,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          categoryIdentifier: _doseCategory.identifier,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();

  static Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();
}
