import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_scope.dart';
import 'app/bootstrap.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'data/auth/supabase_init.dart';
import 'data/push/firebase_token_source.dart';
import 'data/push/push_token_service.dart';
import 'data/sync/sync_service.dart';
import 'app/root.dart';
import 'app/splash.dart';
import 'core/widgets/patient_voice.dart';
import 'dart:async' show unawaited;

import 'core/diagnostics.dart';
import 'data/health/health_collector.dart';
import 'data/health/health_heartbeat.dart';
import 'data/health/health_watcher.dart';
import 'core/notifications/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;
import 'core/theme/theme_mode_store.dart';
import 'core/theme/tokens.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تفضيل العرض الأول — قبل أول فريم، عشان الشاشة ما تلمعش أبيض في الليل
  await ThemeModeStore.load();

  final db = AppDatabase(openConnection());

  // ------------------------------------------------------- الوعد الأول
  // **على iOS، دوسة «أخدته» من شاشة القفل والتطبيق مقفول بتوصل من هنا**
  // — مش من الـisolate ولا من `_onTap`. النظام بيشغّل التطبيق عادي والرد
  // بيستنى في `getNotificationAppLaunchDetails` لحد ما `init()` تسأل
  // عليه (الدليل من الجهاز في bootstrap.dart بتاريخه).
  //
  // واللحظة دي **إطلاق في الخلفية عمره ثواني**: في اللوج، عملية اتشغّلت
  // ٢٠:٣٠:٠٥ وواحدة تانية طلعت بعدها بـ٧ ثواني. فالكتابة المحلية لازم
  // تسبق أي حاجة بتستنى الشبكة. `initSupabaseAuth()` و
  // `FirebaseTokenSource.initialise()` الاتنين awaited وكانوا **قبل**
  // `init()`، يعني تسجيل الجرعة كان مستني تهيئة سحابة وتوكن دفع على
  // إطلاق ممكن ما يعيشش لحد ما يخلّصوا. القاعدة الخامسة، نفس ترتيب
  // `onBackgroundNotificationAction`: الصف والإلغاء أولاً، السحابة آخر حاجة.
  //
  // فالخدمات بتتبني هنا **محلية بالكامل** عشان الوعد يتنفّذ، وبتتبني تاني
  // تحت ومعاها السحابة. التانية هي اللي بتعيش في `AppScope`؛ الأولى
  // بتتقفل عليها الجرعة وخلاص. الصف بيفضل متوسّخاً لحد ما المزامنة
  // تشتغل بعد شوية — وده مقبول، الرفع مجاملة والكتابة هي الوعد.
  final promise = actionHandlerFor(await buildServices(db));
  NotificationService.onAction = (action, payload) => promise.handle(action, payload);
  NotificationResponse? launched;
  try {
    launched = await NotificationService.init(
      onBackgroundAction: onBackgroundNotificationAction,
    );
    if (launched != null) {
      diag('Notif: رد الإطلاق زرار — action=${launched.actionId}');
      await promise.handle(launched.actionId, launched.payload);
    }
  } catch (error, stack) {
    diag('التذكيرات مقدرتش تتهيّأ عند الفتح: $error\n$stack');
  }

  // ---------------------------------------------------------- السحابة
  // الهوية اختيارية: التهيئة محلية وسريعة ومتلفوفة — لو فشلت (أوفلاين،
  // إعداد ناقص، جلسة بايظة) بترجع null والتطبيق يفتح كامل زي ما هو.
  final cloud = await initSupabaseAuth();
  // مزامنة باتجاه واحد وصامتة — من غير سحابة مفيش مزامنة ومفيش أي نداء شبكة.
  final sync = cloud == null
      ? null
      : SyncService(
          db: db,
          remote: cloud.syncRemote,
          hasSession: () => cloud.auth.currentUser != null,
        );
  sync?.start(connectivity: Connectivity().onConnectivityChanged);

  // توكن الدفع — آخر درجة في السلّم بتوصل عليه. اختياري زي كل حاجة
  // سحابية: من غير Supabase أو من غير Firebase (أو على iOS لحد ما APNs
  // تتظبط) بيرجع null والتطبيق كامل زي ما هو، والتصعيد بيقف عند
  // `no_token` في السحابة بدل ما يوصل لابنه.
  //
  // التهيئة هنا **ما بتندهش تسجيل دخول** ولا بتلمس أي جلسة: بتسمع بس.
  // فتنزيلة جديدة بتوصل «يومك» من غير أي جلسة زي ما اختبار الجذر بيقفل
  // عليه.
  final tokenSource = await FirebaseTokenSource.initialise();
  final push = (cloud == null || tokenSource == null)
      ? null
      : PushTokenService(
          source: tokenSource,
          remote: cloud.pushTokens,
          signedIn: cloud.auth.authState.map((user) => user != null),
          isSignedIn: () => cloud.auth.currentUser != null,
        );
  push?.start();

  final services = await buildServices(
    db,
    auth: cloud?.auth,
    care: cloud?.care,
    caregiver: cloud?.caregiver,
    sync: sync,
    push: push,
  );

  // المسح النهائي للسجلات اللي عدّى عليها ٣٠ يوم من المسح — الوعد المكتوب.
  await launchHousekeeping(services);

  // زرار على الإشعار والتطبيق مفتوح — من دلوقتي على الخدمات الكاملة،
  // عشان التأكيد يرفع للسحابة كمان (٤.٢أ). قبل كده كانت على [promise]،
  // اللي عن قصد مالهاش سحابة.
  final actions = actionHandlerFor(services);
  NotificationService.onAction =
      (action, payload) => actions.handle(action, payload);

  // الجرعة اللي اتكتبت فوق لسه متوسّخة — المزامنة اتبنت بعديها. دفعة
  // واحدة دلوقتي بتوصّلها للسحابة قبل ما السيرفر يوصل لمهلته ويصحّي الابن
  // على جرعة أبوه خدها (٤.٢ب).
  if (launched != null) sync?.onAppForeground();

  // التذكيرات مهمة، بس مش مهمة لدرجة إن التطبيق ما يفتحش من غيرها.
  //
  // على أندرويد ١٢+ الجدولة الدقيقة بترمي استثناء لو الإذن لسه مترفض —
  // ولو ده حصل قبل runApp، المريض هيلاقي شاشة سودا بدل تطبيقه. الشاشات
  // نفسها بتطلب الإذن وبتعيد الجدولة بعد الأسئلة.
  try {
    // كل فتحة للتطبيق بتعيد بناء النافذة: الجهاز ممكن يكون اتقفل يومين، أو
    // المستخدم عدّى نص الليل. الأرقام مشتقة من الوقت فالإعادة مش بتكرّر حاجة.
    await services.scheduler.rescheduleAll();
  } catch (error, stack) {
    diag('التذكيرات مقدرتش تتجدول عند الفتح: $error\n$stack');
  }

  // ------------------------------------------------ فحص السلامة — آخر حاجة
  // **مجاملة، وبعد كل وعد.** بيقرا مدى التذكير من `pending()` بعد ما
  // الجدولة خلصت، فلازم يبقى بعدها؛ وبيقرا حالة الجرعة بعد ما اتكتبت،
  // فلازم يبقى بعد معالجة رد الإطلاق. **ومن غير await قبل `runApp`**:
  // شاشة المريض مش بتستنى فحص.
  //
  // اختبار بيقرا الملف ده ويوقع لو الترتيب اتقلب — كسرناه مرتين في يوم
  // واحد، مرة في الـisolate ومرة هنا.
  final patient = await services.routines.getPatient(services.patientId);
  unawaited(HealthWatcher(
    collector: HealthCollector(services),
    heartbeat: (cloud == null || patient == null)
        ? null
        : HealthHeartbeat(remote: cloud.health, patientUuid: patient.uuid),
  ).run());

  runApp(FakkarniApp(services: services));
}

class FakkarniApp extends StatelessWidget {
  const FakkarniApp({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    // الوضع بيغيّر كل لون في التطبيق — الشجرة كلها بتتبني من جديد لما يتقلب
    // **مفتاح على الوضع**: أي شجرة `const` (زي `const SettingsScreen()`) ما
    // بتتبنيش تاني لما متغيّر عام يتقلب — الويدجت هي هي، فـFlutter بيعدّيها.
    // المفتاح بيجبر بناء كامل، فالتطبيق كله بيقلب مرة واحدة.
    return ValueListenableBuilder<bool>(
      valueListenable: F.darkMode,
      builder: (context, dark, _) => KeyedSubtree(key: ValueKey(dark), child: _app()),
    );
  }

  Widget _app() {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'فكرني',
        debugShowCheckedModeBanner: false,
        theme: F.light,
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // العربي بيجيب RTL لوحده، بس بنثبّتها صراحة عشان أي شاشة تتبني
        // في اختبار من غير locale تفضل من اليمين لليسار.
        // شاشة البداية طبقة فوق التطبيق، مش بوابة قدامه: الشاشة الأولى
        // بتتبني تحتها من أول فريم، وهي بتتلاشى بعد ١.٦ ث.
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          // صوت المريض بجنسه فوق الـNavigator — كل شاشة بتتفتح بـpush بتشوفه
          child: PatientVoiceScope(
            child: SplashOverlay(child: child ?? const SizedBox.shrink()),
          ),
        ),
        home: const AppRoot(),
      ),
    );
  }
}
