import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_scope.dart';
import 'app/root.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/tokens.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/dose_event_repository.dart';
import 'data/repositories/medication_repository.dart';
import 'data/repositories/routine_repository.dart';
import 'data/services/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase(openConnection());
  final routines = RoutineRepository(db);
  final patientId = await routines.ensurePatient();
  final patientIndex = await routines.patientIndex(patientId);

  final medications = MedicationRepository(db);
  final scheduler = ReminderScheduler(
    routines: routines,
    medications: medications,
    patientId: patientId,
    patientIndex: patientIndex,
  );

  // التذكيرات مهمة، بس مش مهمة لدرجة إن التطبيق ما يفتحش من غيرها.
  //
  // على أندرويد ١٢+ الجدولة الدقيقة بترمي استثناء لو الإذن لسه مترفض —
  // ولو ده حصل قبل runApp، المريض هيلاقي شاشة سودا بدل تطبيقه. الشاشات
  // نفسها بتطلب الإذن وبتعيد الجدولة بعد الأسئلة.
  try {
    await NotificationService.init();

    // كل فتحة للتطبيق بتعيد بناء النافذة: الجهاز ممكن يكون اتقفل يومين، أو
    // المستخدم عدّى نص الليل. الأرقام مشتقة من الوقت فالإعادة مش بتكرّر حاجة.
    await scheduler.rescheduleAll();
  } catch (error, stack) {
    debugPrint('التذكيرات مقدرتش تتجدول عند الفتح: $error\n$stack');
  }

  runApp(
    FakkarniApp(
      services: AppServices(
        db: db,
        routines: routines,
        medications: medications,
        events: DoseEventRepository(db),
        scheduler: scheduler,
        patientId: patientId,
        tapPayload: NotificationService.lastPayload,
      ),
    ),
  );
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
