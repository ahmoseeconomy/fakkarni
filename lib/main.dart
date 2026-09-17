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
import 'core/notifications/notification_service.dart';
import 'core/theme/theme_mode_store.dart';
import 'core/theme/tokens.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تفضيل العرض الأول — قبل أول فريم، عشان الشاشة ما تلمعش أبيض في الليل
  await ThemeModeStore.load();

  final db = AppDatabase(openConnection());
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
    aiSession: cloud?.aiSession,
  );

  // المسح النهائي للسجلات اللي عدّى عليها ٣٠ يوم من المسح — الوعد المكتوب.
  await launchHousekeeping(services);

  // زرار على الإشعار والتطبيق مفتوح — نفس المعالج، بنفس الخدمات.
  final actions = actionHandlerFor(services);
  NotificationService.onAction =
      (action, payload) => actions.handle(action, payload);

  // التذكيرات مهمة، بس مش مهمة لدرجة إن التطبيق ما يفتحش من غيرها.
  //
  // على أندرويد ١٢+ الجدولة الدقيقة بترمي استثناء لو الإذن لسه مترفض —
  // ولو ده حصل قبل runApp، المريض هيلاقي شاشة سودا بدل تطبيقه. الشاشات
  // نفسها بتطلب الإذن وبتعيد الجدولة بعد الأسئلة.
  try {
    await NotificationService.init(
      onBackgroundAction: onBackgroundNotificationAction,
    );

    // كل فتحة للتطبيق بتعيد بناء النافذة: الجهاز ممكن يكون اتقفل يومين، أو
    // المستخدم عدّى نص الليل. الأرقام مشتقة من الوقت فالإعادة مش بتكرّر حاجة.
    await services.scheduler.rescheduleAll();
  } catch (error, stack) {
    debugPrint('التذكيرات مقدرتش تتجدول عند الفتح: $error\n$stack');
  }

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
