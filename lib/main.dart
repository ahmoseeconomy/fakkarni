import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_scope.dart';
import 'app/bootstrap.dart';
import 'data/auth/supabase_init.dart';
import 'app/root.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/tokens.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase(openConnection());
  // الهوية اختيارية: التهيئة محلية وسريعة ومتلفوفة — لو فشلت (أوفلاين،
  // إعداد ناقص، جلسة بايظة) بترجع null والتطبيق يفتح كامل زي ما هو.
  final auth = await initSupabaseAuth();
  final services = await buildServices(db, auth: auth);

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
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AppRoot(),
      ),
    );
  }
}
