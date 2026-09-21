import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../domain/health/health_snapshot.dart' show NotificationPermission;
import '../diagnostics.dart';

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

  /// الردود اللي اتعالجت خلاص — عشان رد واحد ما يتحسبش مرتين.
  ///
  /// نفس الدوسة ممكن توصل من بابين: رد الإطلاق اللي
  /// `getNotificationAppLaunchDetails` بترجّعه، و[_onTap] لو النظام قرر
  /// يبعتها كمان. تأكيد جرعة مرتين مش بيأذي الصف (نفس الحالة تتكتب تاني)
  /// بس بيعيد الجدولة ويرفع للسحابة على الفاضي في إطلاق عمره ثواني.
  static final Set<String> _handled = <String>{};

  static String _keyOf(NotificationResponse r) =>
      '${r.actionId}|${r.id}|${r.payload}';

  /// بترجّع true مرة واحدة بس لكل (جرعة، زرار).
  static bool claimResponse(NotificationResponse response) =>
      _handled.add(_keyOf(response));

  /// **القرار اللي رد الإطلاق بيتاخد عليه، في مكان واحد.**
  ///
  /// بترجّع الرد اللي محتاج يتعالج كزرار، أو null لو مفيش. الدوسة
  /// العادية (من غير `actionId`) بتنزل في [lastPayload] زي ما كانت —
  /// الجذر بيسمع لها ويفتح شاشة التذكير.
  ///
  /// **زرار عمره ما ينزل في [lastPayload]**: ساعتها كان بيتحوّل لدوسة
  /// عادية، يعني التطبيق بيفتح على الجرعة والصف ما اتكتبش — وده بالظبط
  /// اللي كان بيحصل على iOS (شوف [init]).
  @visibleForTesting
  static NotificationResponse? applyLaunchResponse(
      NotificationResponse? response) {
    if (response == null) return null;
    if (!NotificationActions.isAction(response.actionId)) {
      lastPayload.value = response.payload;
      return null;
    }
    return claimResponse(response) ? response : null;
  }

  /// بيشغّل [_onTap] زي ما الإضافة بتعمل — الاختبار محتاج الباب التاني
  /// عشان يثبت إن الرد الواحد ما بيتعالجش مرتين.
  @visibleForTesting
  static void tapForTest(NotificationResponse response) => _onTap(response);

  @visibleForTesting
  static void resetForTest() {
    _handled.clear();
    lastPayload.value = null;
  }

  /// قناة الجرعات — أولوية عالية عشان تظهر فوق الشاشة وتصوّت.
  static const _doseChannel = AndroidNotificationChannel(
    'fakkarni_doses',
    'تذكير الأدوية',
    description: 'تنبيهات مواعيد الجرعات',
    importance: Importance.max,
  );

  /// قناة تذكير الصيام (D3.7) — لوحدها عشان تتسكّت من غير ما الجرعات تتسكّت.
  static const _checkupChannel = AndroidNotificationChannel(
    'fakkarni_checkup',
    'تذكير الصيام قبل التحليل',
    description: 'تذكير بيتظبط بإيدك قبل ميعاد سحب العينة',
    importance: Importance.high,
  );

  /// قناة التصعيد — نفس الأولوية، بس بتهزّ بنمط أطول.
  ///
  /// «نغمة أعلى» على أندرويد معناها قناة تانية: مستوى الصوت بتاع القناة
  /// المستخدم هو اللي بيحدده، وإحنا نقدر نديه قناة يعلّيها لوحدها من غير
  /// ما يعلّي تذكير الجرعة العادي. على iOS الاتنين timeSensitive؛ اللي
  /// أعلى من كده (Critical Alerts) محتاج موافقة آبل — راجع «دين تقني».
  static final _escalationChannel = AndroidNotificationChannel(
    'fakkarni_escalation',
    'لسه ما أخدتش الدوا',
    description: 'تنبيه أعلى لما تذكير الجرعة يعدّي من غير تأكيد',
    importance: Importance.max,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 900]),
  );

  /// قناة المواعيد — مكشوفة عشان الاختبار يقارنها بقناة الجرعات.
  static const appointmentChannelId = 'fakkarni_appointment';

  /// **قناة المواعيد — لوحدها عن الجرعات وعن الصيام.**
  ///
  /// السبب مش ترتيب: الابن والأب ممكن يسكّتوا مواعيد الدكتور من غير ما
  /// يسكّتوا تذكير الدوا — ولو كانوا قناة واحدة، إسكات واحدة بيسكّت
  /// التانية. وهي كمان مش قناة الصيام: نغمة الصيام مش نغمة ميعاد.
  ///
  /// **وإشعار امبارح الميعاد بيتبعت `silent` على مستوى الإشعار نفسه**
  /// (`NotificationCompat.Builder.setSilent`) مش بقناة تانية: القناة
  /// واحدة زي ما المواصفة طلبت، والهدوء بيتحدد لكل إشعار. إشعار صامت
  /// ما بيطلعش فوق الشاشة كمان، فالراجل بيلاقيه في الستارة لما يبص.
  static const _appointmentChannel = AndroidNotificationChannel(
    appointmentChannelId,
    'مواعيد الدكتور والمعمل',
    description: 'تنبيه امبارح الميعاد وفي يومه',
    importance: Importance.high,
  );

  /// الـid بتاع قناة الابن، مكشوف عشان الاختبار يقارنه بالـTypeScript.
  static const caregiverChannelId = 'fakkarni_caregiver';

  /// قناة تنبيه **الابن** — الدرجة الأخيرة في السلّم.
  ///
  /// الـid `fakkarni_caregiver` مكرر حرفياً في
  /// `supabase/functions/escalate/index.ts` (`CAREGIVER_CHANNEL`). لو
  /// الاتنين اختلفوا، أندرويد بيرمي الإشعار على القناة الافتراضية
  /// وبيفقد أولويته — **من غير أي خطأ يبان في أي مكان**. اختبار
  /// `push_channel_test.dart` بيقفل على النصّين مع بعض.
  ///
  /// قناة لوحدها مش عشان الشكل: الابن ممكن يسكّت تذكيرات أبوه العادية
  /// على موبايله (هو مش بياخد الدوا) ويسيب دي شغّالة. ولو كانوا قناة
  /// واحدة، إسكات واحدة بيسكّت التانية.
  static final _caregiverChannel = AndroidNotificationChannel(
    caregiverChannelId,
    'تنبيه عن والدك',
    description: 'لما جرعة تعدّي من غير تأكيد على موبايل والدك',
    importance: Importance.max,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 900]),
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
  ///
  /// **بترجّع رد الإطلاق لو كان زرار** — لازم اللي بينده يعالجه، وفوراً.
  /// على iOS والتطبيق مقفول خالص، دوسة «أخدته» **مش** بتعدّي لا على
  /// [onBackgroundAction] ولا على [_onTap]: النظام بيشغّل التطبيق عادي
  /// والرد بيستنى هنا في `getNotificationAppLaunchDetails`.
  static Future<NotificationResponse?> init(
      {BackgroundActionHandler? onBackgroundAction}) async {
    // نداء تاني ما بيرجّعش الرد تاني — ده نص الحماية من المعالجة المكرّرة
    if (_initialised) return null;

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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_escalationChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_caregiverChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_checkupChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_appointmentChannel);

    // لو التطبيق كان مقفول خالص واتفتح من الإشعار نفسه، الدوسة دي مش بتعدّي
    // على _onTap — لازم نسألوا عليها بإيدنا.
    //
    // **وكانت بتتقري ناقصة**: السطر ده كان بياخد `.payload` ويرمي
    // `.actionId`، فزرار «أخدته» كان بيتحوّل لدوسة عادية في صمت —
    // التطبيق بيفتح على الجرعة والصف عمره ما اتكتب. ده هو العيب اللي
    // خلّى تأكيد شاشة القفل على iOS ما يعملش حاجة خالص.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = (launch != null && launch.didNotificationLaunchApp)
        ? launch.notificationResponse
        : null;
    final action = applyLaunchResponse(response);

    _initialised = true;
    return action;
  }

  static void _onTap(NotificationResponse response) {
    final action = response.actionId;
    // تشخيص: بيقول لنا إن الضغطة وصلت دارت أصلاً، وبأي actionId.
    diag('Notif: _onTap action=$action payload=${response.payload}');
    if (NotificationActions.isAction(action) && onAction != null) {
      // نفس الرد ممكن يكون اتعالج خلاص من رد الإطلاق
      if (claimResponse(response)) onAction!(action!, response.payload);
      return;
    }
    lastPayload.value = response.payload;
  }

  /// قناة تنبيه السلامة — نفس أهمية التذكير، وقناة لوحدها عشان تتقفل
  /// لوحدها لو حد مش عايزها.
  static const healthChannelId = 'fakkarni_health';

  static const _healthChannel = AndroidNotificationChannel(
    healthChannelId,
    'سلامة التذكير',
    description: 'لما حاجة بتمنع التذكير من إنه يرن',
    importance: Importance.high,
  );

  /// **بيتعرض حالاً — `show`، مش `zonedSchedule`. ده شرط، مش أسلوب.**
  ///
  /// iOS بيمسك ٦٤ إشعار **معلّق** بس، والأربعة وستين كلهم متوزّعين خلاص
  /// (٤٤ جرعة + ١٤ سلّم + ٢ تأجيل + ٢ صيام + ٢ متابعة). أي إشعار
  /// **متجدول** من هنا بياخد خانة من جرعة حقيقية — يعني تنبيه بيقول
  /// «التذكير ممكن ما يشتغلش» هو نفسه اللي بيعطّله. إشعار معروض دلوقتي
  /// ما بياخدش خانة خالص.
  ///
  /// ومالوش payload ولا أزرار: الأزرار دي بتسجّل جرعات.
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_healthChannel);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          healthChannelId,
          _healthChannel.name,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
    );
  }

  /// إذن الإشعارات زي ما النظام بيقوله دلوقتي — لفحص السلامة.
  ///
  /// **«هادي» بتتحسب مكسورة**: إشعار provisional بينزل في مركز الإشعارات
  /// من غير صوت، وراجل عنده ٧٢ سنة مش هيفتح المركز. للتذكير بالدوا ده
  /// مش نص إذن، ده لا إذن.
  ///
  /// أي فشل بيرجّع [NotificationPermission.unknown] — مش بنخوّف بالشك.
  static Future<NotificationPermission> permissionState() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final enabled = await android?.areNotificationsEnabled();
        if (enabled == null) return NotificationPermission.unknown;
        return enabled
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final options = await ios?.checkPermissions();
        if (options == null) return NotificationPermission.unknown;
        if (!options.isEnabled) return NotificationPermission.denied;
        if (options.isProvisionalEnabled) {
          return NotificationPermission.provisional;
        }
        return NotificationPermission.granted;
      }
    } catch (_) {
      // فحص السلامة مجاملة — عمره ما يوقّع حاجة بسببه
    }
    return NotificationPermission.unknown;
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

    /// درجة على سلّم التصعيد — قناة بتهزّ. نفس الأزرار ونفس الحمولة.
    bool escalation = false,
  }) async {
    await init();

    final when = tz.TZDateTime.from(at, tz.local);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    final channel = escalation ? _escalationChannel : _doseChannel;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: channel.enableVibration,
          vibrationPattern: channel.vibrationPattern,
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

  /// تذكير صيام (D3.7). **مفيش أزرار «أخدته»/«فكّرني بعدين» ومفيش فئة
  /// الجرعة ومفيش payload**: الأزرار دي بتسجّل جرعات، وتذكير الصيام مش جرعة.
  /// الدوسة عليه بتفتح التطبيق وبس.
  static Future<void> scheduleCheckup({
    required int id,
    required String title,
    required String body,
    required DateTime at,
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
          _checkupChannel.id,
          _checkupChannel.name,
          channelDescription: _checkupChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.active),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// **ميعاد متابعة — قناته هو، ومنبّه غير دقيق.**
  ///
  /// `inexactAllowWhileIdle` عن قصد: المنبّه الدقيق مورد مقنّن على
  /// أندرويد ومحجوز للجرعات. إشعار ميعاد بيتأخر دقايق مالوش أي ضرر،
  /// وجرعة بتتأخر دقايق ليها ضرر — فالمواعيد **عمرها ما تزاحم** الجرعة
  /// على المورد ده. اختبار بيقفل على السطر ده.
  ///
  /// و[quiet] بيخلّي إشعار امبارح الميعاد صامت تماماً — من غير صوت ولا
  /// هزاز ولا ظهور فوق الشاشة — من غير ما يحتاج قناة تانية.
  ///
  /// **مفيش أزرار ومفيش payload**: ده مش جرعة، والدوسة بتفتح التطبيق وبس.
  static Future<void> scheduleAppointment({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required bool quiet,
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
          _appointmentChannel.id,
          _appointmentChannel.name,
          channelDescription: _appointmentChannel.description,
          importance: quiet ? Importance.low : Importance.high,
          priority: quiet ? Priority.low : Priority.high,
          silent: quiet,
          category: AndroidNotificationCategory.event,
        ),
        iOS: DarwinNotificationDetails(
          // iOS: الهادي `passive` — بيدخل مركز الإشعارات من غير ما يقاطع.
          // واللي في اليوم نفسه `active` زي أي تنبيه عادي.
          interruptionLevel: quiet ? InterruptionLevel.passive : InterruptionLevel.active,
          presentSound: !quiet,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();

  static Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();
}
