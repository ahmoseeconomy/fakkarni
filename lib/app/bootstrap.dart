import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;

import '../ai/gemini_config.dart';
import '../ai/lab_reader.dart';
import '../ai/prescription_reader.dart';
import '../core/notifications/background_task.dart';
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
import '../data/services/reminder_scheduler.dart';
import 'app_scope.dart';
import '../core/diagnostics.dart';

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
    prescriptionReader: _readerFromEnvironment(),
    labReader: _labReaderFromEnvironment(),
    auth: auth,
    care: care,
    caregiver: caregiver,
    sync: sync,
    push: push,
  );
}

/// شغل البيت عند فتح التطبيق — مش في صحوة الخلفية.
///
/// **فاضي دلوقتي، ومتساب عن قصد.** كان بيمسح السجلات اللي عدّى على مسحها
/// ٣٠ يوم، عشان الجملة «هيتمسح نهائي بعد ٣٠ يوم» تبقى حقيقية. المهلة دي
/// اتشالت: المسح بقى بيمسح المحتوى في لحظته، واللي فاضل شاهدة فاضية
/// المزامنة محتاجاها. الدالة بتفضل مكانها لأن أول حاجة محتاجة تنضيف عند
/// الفتح هتلاقي بابها مفتوح ومربوط ومتغطّي باختبار.
Future<void> launchHousekeeping(AppServices services, {DateTime? now}) async {}

/// نفس المفتاح ونفس القاعدة: من غيره null، ومفيش طلب بمفتاح فاضي.
LabReportReader? _labReaderFromEnvironment() {
  final config = GeminiConfig.tryFromEnvironment();
  return config == null ? null : GeminiLabReader(config);
}

/// المفتاح من `--dart-define` وبس. لو مش موجود بنرجّع null ونقولها في
/// الشاشة — مش بنكسر فتح التطبيق، ومش بننده الـAPI بمفتاح فاضي أبداً.
PrescriptionReader? _readerFromEnvironment() {
  final config = GeminiConfig.tryFromEnvironment();
  if (config == null) {
    diag(GeminiConfig.missingKeyMessage);
    return null;
  }
  return GeminiPrescriptionReader(config);
}

NotificationActionHandler actionHandlerFor(
  AppServices services, {
  Future<void> Function()? prepareNotifications,
  Future<SyncService?> Function()? cloud,
}) {
  final ready = services.sync;
  return NotificationActionHandler(
    routines: services.routines,
    medications: services.medications,
    events: services.events,
    scheduler: services.scheduler,
    patientId: services.patientId,
    prepareNotifications: prepareNotifications,
    // جوّه التطبيق المزامنة مبنية خلاص — الدالة بترجّعها زي ما هي.
    cloud: cloud ?? (ready == null ? null : () async => ready),
  );
}

/// زرار على الإشعار والتطبيق مقفول.
///
/// النظام بيصحّي التطبيق على isolate منفصل ويندَه الدالة دي. مفيش واجهة
/// ولا `runApp`. لازم تفضل دالة عليا بالـpragma ده وإلا المترجم بيشيلها.
///
/// **الترتيب هنا هو الميزة، مش تفصيلة.** كان: تهيئة إشعارات ← تهيئة
/// سحابة (لحد ثانيتين) ← خدمات ← تسجيل الجرعة. يعني نداءين قناة وتهيئة
/// سحابة قدام الوعد، على منصة مش مضمون فيها إننا هنكمّل السطر اللي بعده.
/// بقى: مهلة خلفية ← قاعدة البيانات ← **تسجيل الجرعة** ← تهيئة الإشعارات
/// ← إلغاء درجات السلّم ← مدّ النافذة ← تهيئة السحابة والرفع.
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
  diag('Isolate: دخلنا المعالج — action=${response.actionId} payload=${response.payload}');

  // **أول نداء خالص، قبل قاعدة البيانات وقبل أي حاجة.** كل سطر تحت ده
  // بيتنفّذ في وقت مستعار: الإضافة رجّعت completionHandler خلاص، والنظام
  // من حقه يوقّف العملية في أي لحظة من غير ما يقول. شوف [BackgroundTask].
  final task = await BackgroundTask.begin();

  final db = AppDatabase(openConnection());
  IsolateCloud? cloud;
  try {
    // **محلي بس.** الخدمات دي مش محتاجة لا إشعارات ولا سحابة عشان
    // تتبني — والاتنين بقوا وراء الوعد، مش قدامه.
    final services = await buildServices(db);
    await actionHandlerFor(
      services,
      // بتتنده بعد صف الجرعة، قبل الإلغاء.
      prepareNotifications: () => NotificationService.init(),
      // بتتنده في آخر سطر خالص — تهيئة بثانيتين مالهاش أي حق تقف قدام
      // تسجيل جرعة (القاعدة الخامسة).
      cloud: () async {
        final ready = await initSupabaseForIsolate();
        cloud = ready;
        return ready == null
            ? null
            // من غير start(): مفيش مستمعين ولا مؤقّتات في صحوة بتموت
            // بعد ثواني — دفعة واحدة محدودة وبس.
            : SyncService(
                db: db,
                remote: ready.syncRemote,
                hasSession: ready.hasSession,
              );
      },
    ).handle(response.actionId, response.payload);
  } catch (error, stack) {
    diag('زرار الإشعار مقدرش يتعالج في الخلفية: $error\n$stack');
  } finally {
    await cloud?.shutdown();
    await db.close();
    // من غير ده النظام بيقفل التطبيق قفل لما المهلة تخلص.
    await BackgroundTask.end(task);
  }
}
