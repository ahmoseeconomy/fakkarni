import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;

import '../ai/ai_session.dart';
import '../ai/lab_reader.dart';
import '../ai/prescription_reader.dart';
import '../core/notifications/notification_service.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/supabase_init.dart';
import '../data/care/care_circle_service.dart';
import '../data/care/caregiver_remote.dart';
import '../data/push/push_tokens.dart';
import '../data/sync/sync_service.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/repositories/dose_event_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/services/notification_actions.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/records_repository.dart';
import '../data/services/reminder_scheduler.dart';
import 'app_scope.dart';

/// بيبني كل خدمات التطبيق فوق قاعدة بيانات مفتوحة.
///
/// نفس الدالة بتتستخدم من `main` ومن صحوة الخلفية — عشان الاتنين يشوفوا
/// نفس المريض ونفس خانة الإشعارات، ومفيش نسختين من المنطق تتفرّقا.
Future<AppServices> buildServices(
  AppDatabase db, {
  AuthService? auth,
  CareCircleService? care,
  CaregiverRemote? caregiver,
  SyncService? sync,
  PushTokens? push,
  AiSession? aiSession,
}) async {
  final routines = RoutineRepository(db);
  final patientId = await routines.ensurePatient();
  final patientIndex = await routines.patientIndex(patientId);
  final medications = MedicationRepository(db);
  final events = DoseEventRepository(db);

  return AppServices(
    db: db,
    routines: routines,
    medications: medications,
    events: events,
    scheduler: ReminderScheduler(
      routines: routines,
      medications: medications,
      events: events,
      patientId: patientId,
      patientIndex: patientIndex,
      preferences: PreferencesRepository(db),
    ),
    patientId: patientId,
    tapPayload: NotificationService.lastPayload,
    // قراية الصور بتعدّي من دالتنا في السحابة بجلسة المستخدم (C2). من غير
    // Supabase متظبط مفيش قارئ — والشاشة بتقولها، والإدخال بالإيد شغّال.
    prescriptionReader: aiSession == null ? null : GeminiPrescriptionReader(aiSession),
    labReader: aiSession == null ? null : GeminiLabReader(aiSession),
    auth: auth,
    care: care,
    caregiver: caregiver,
    sync: sync,
    push: push,
  );
}

/// شغل البيت عند فتح التطبيق — مش في صحوة الخلفية.
///
/// الملف الصحي بيقول للمستخدم «هيتمسح نهائي بعد ٣٠ يوم»؛ السطر ده هو اللي
/// بيخلّي الجملة دي حقيقية. فشله ما بيوقفش الفتح — الصفوف بتتمسح الفتحة
/// الجاية.
Future<void> launchHousekeeping(AppServices services, {DateTime? now}) async {
  try {
    final purged = await RecordsRepository(services.db).purgeDeleted(now: now, attachments: services.attachments);
    if (purged > 0) debugPrint('الملف الصحي: اتمسح نهائي $purged صف عدّى عليهم ٣٠ يوم');
  } catch (error, stack) {
    debugPrint('تنظيف الملف الصحي ما اشتغلش: $error\n$stack');
  }
}

NotificationActionHandler actionHandlerFor(AppServices services) =>
    NotificationActionHandler(
      routines: services.routines,
      medications: services.medications,
      events: services.events,
      scheduler: services.scheduler,
      patientId: services.patientId,
      sync: services.sync,
    );

/// زرار على الإشعار والتطبيق مقفول.
///
/// النظام بيصحّي التطبيق على isolate منفصل ويندَه الدالة دي. مفيش واجهة
/// ولا `runApp`: بنفتح قاعدة البيانات، نسجّل، نمدّ النافذة، **وبعدين بس**
/// نرفع للسحابة، ونقفل. لازم تفضل دالة عليا بالـpragma ده وإلا المترجم
/// بيشيلها.
///
/// المزامنة هنا مش رفاهية: «أخدته» من شاشة القفل هي أكتر طريق بيأكّد بيه
/// راجل عنده ٧٢ سنة، ومن غير الرفع ده الجرعة بتفضل على الجهاز لحد ما
/// يفتح التطبيق — وهو مالوش سبب يفتحه.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse response) async {
  // الـisolate ده جديد: الإضافات (path_provider، الإشعارات) لازم تتسجّل فيه.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // تشخيص: أول سطر في الـisolate — لو ما ظهرش، الضغطة عمرها ما وصلت دارت.
  debugPrint('Isolate: دخلنا المعالج — action=${response.actionId} payload=${response.payload}');

  final db = AppDatabase(openConnection());
  IsolateCloud? cloud;
  try {
    await NotificationService.init();
    // تهيئة محلية بتقرا الجلسة المحفوظة — من غير جلسة أو من غير إعداد
    // بترجع null والصحوة بتفضل أوفلاين بالكامل.
    cloud = await initSupabaseForIsolate();
    final services = await buildServices(
      db,
      sync: cloud == null
          ? null
          // من غير start(): مفيش مستمعين ولا مؤقّتات في صحوة بتموت
          // بعد ثواني — دفعة واحدة محدودة وبس.
          : SyncService(
              db: db,
              remote: cloud.syncRemote,
              hasSession: cloud.hasSession,
            ),
    );
    await actionHandlerFor(services).handle(response.actionId, response.payload);
  } catch (error, stack) {
    debugPrint('زرار الإشعار مقدرش يتعالج في الخلفية: $error\n$stack');
  } finally {
    await cloud?.shutdown();
    await db.close();
  }
}
