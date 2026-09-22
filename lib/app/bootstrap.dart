import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;

import '../ai/gemini_config.dart';
import '../ai/lab_reader.dart';
import '../ai/package_reader.dart';
import '../ai/prescription_reader.dart';
import '../core/notifications/background_task.dart';
import '../core/notifications/notification_service.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/supabase_init.dart';
import '../data/care/care_circle_service.dart';
import '../data/care/caregiver_preferences.dart';
import '../data/care/caregiver_remote.dart';
import '../data/push/push_tokens.dart';
import '../data/sync/sync_service.dart';
import '../core/format/arabic_time.dart';
import 'package:drift/drift.dart' show Value;

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
  CaregiverPreferencesService? caregiverPreferences,
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
    caregiverPreferences: caregiverPreferences,
    prescriptionReader: _readerFromEnvironment(),
    labReader: _labReaderFromEnvironment(),
    packageReader: _packageReaderFromEnvironment(),
    auth: auth,
    care: care,
    caregiver: caregiver,
    sync: sync,
    push: push,
  );
}

/// شغل البيت عند فتح التطبيق — مش في صحوة الخلفية.
///
/// كان بيمسح السجلات اللي عدّى على مسحها ٣٠ يوم؛ المهلة دي اتشالت
/// (المسح بقى بيمسح في لحظته). الباب فضل مفتوح ومربوط ومتغطّي باختبار
/// **لأول حاجة تحتاجه** — ودي أهي.
///
/// **أرقام لاتينية جوّه عناوين عربية متخزّنة.** عنوان تقرير التحليل
/// كان بيتكتب `'تقرير تحليل — $count نتايج'` برقم لاتيني، فالعنوان
/// اتخزّن كده وبيتعرض كده على «يومك» وفي الملف الصحي وعلى شاشة الابن.
/// المصدر اتصلّح؛ ودي بتظبّط اللي اتكتب قبله.
///
/// **وبتلمس العناوين اللي إحنا كتبناها بالشكل ده وبس** — بنمط مقفول.
/// عنوان كتبه إنسان بإيده ما بيتلمسش: الأرقام اللي جواه بتاعته هو، وفيه
/// أسماء تحاليل فيها أرقام لاتينية (`HbA1c`) تحويلها بيبوّظها.
Future<void> launchHousekeeping(AppServices services, {DateTime? now}) async {
  await normaliseLabReportTitles(services.db);
}

/// النمط: «تقرير تحليل — ‹رقم لاتيني› نتايج» — ولا حاجة تانية.
final RegExp labReportTitlePattern = RegExp(r'^تقرير تحليل — (\d+) نتايج$');

Future<void> normaliseLabReportTitles(AppDatabase db) async {
  final rows = await db.select(db.records).get();
  for (final row in rows) {
    final match = labReportTitlePattern.firstMatch(row.title);
    if (match == null) continue;
    await (db.update(db.records)..where((t) => t.id.equals(row.id)))
        .write(RecordsCompanion(title: Value('تقرير تحليل — ${arabicDigits(match.group(1)!)} نتايج')));
  }
}

/// نفس المفتاح ونفس النقل — سطح شبكة جديد مش موجود هنا.
MedicinePackageReader? _packageReaderFromEnvironment() {
  final config = GeminiConfig.tryFromEnvironment();
  return config == null ? null : GeminiPackageReader(config);
}

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
/// **الباب الواحد**: كل زرار إشعار على المنصتين بيعدّي من هنا.
///
/// الطريقين مختلفين تماماً وده مش اختيارنا — iOS بيفتح التطبيق ويسيب الرد
/// في `getNotificationAppLaunchDetails`، وأندرويد بيصحّي isolate لوحده.
/// **اللي اتعمل هنا إن الاختلاف اتحبس في محوّلين رفيعين**، والشغل الحقيقي
/// بقى في دالة واحدة الاتنين بينادوها: لو طريق منهم اتصلّح، التاني بياخد
/// الإصلاح من غير ما حد يفتكر.
///
/// [services] بتتبعت لما اللي بينده يكون بناها خلاص (المقدمة) — الـisolate
/// بيسيبها فاضية فبتتبني هنا. الاتنين بيوصلوا لنفس
/// [NotificationActionHandler.handle] وبنفس الترتيب: الصف، الإلغاء،
/// النافذة، وبعدين السحابة.
Future<void> handleNotificationAction({
  required AppDatabase db,
  required String? actionId,
  required String? payload,
  AppServices? services,
  Future<void> Function()? prepareNotifications,
  Future<SyncService?> Function()? cloud,
}) async {
  final resolved = services ?? await buildServices(db);
  await actionHandlerFor(
    resolved,
    prepareNotifications: prepareNotifications,
    cloud: cloud,
  ).handle(actionId, payload);
}

/// **دي سكّة أندرويد، مش سكّة iOS — والجهاز قال كده** (٢٠ سبتمبر ٢٠٢٦،
/// نسخة profile على آيفون، من `fkdiag.log` لحظة الدوسة):
///
/// ```
/// 20:30:05.961  didFinishLaunching — launchOptions=nil state=background
/// 20:30:06.042  didInitializeImplicitFlutterEngine
/// 20:30:06.096  didReceive — action=taken category=fakkarni_dose
/// ```
///
/// ومفيش سطر `registerPlugins`، ومفيش `Isolate:`، ومفيش `_onTap`. يعني iOS
/// شغّل التطبيق في الخلفية وسلّم الرد، **والإضافة ما ندهتش أي callback
/// خالص**: الرد استنى في `getNotificationAppLaunchDetails()`، و
/// `NotificationService.init()` كانت بتاخد منه الـpayload وترمي الـactionId
/// — فالزرار بيتحوّل لدوسة عادية والجرعة عمرها ما اتكتبت. الإصلاح في
/// `main.dart`، مش هنا.
///
/// **ومع ذلك الدالة دي بتفضل مكانها**: على أندرويد الصحوة دي هي الطريق
/// الحقيقي (BroadcastReceiver + isolate)، واللوج ده عن iOS بس. شيلها
/// وأندرويد بيبطّل يسجّل من شاشة القفل. وكمان `didFinishLaunching` تانية
/// طلعت بعد ٧ ثواني — العملية اللي النظام شغّلها ما عاشتش، وهو السبب اللي
/// خلّى `BackgroundTask` والترتيب تحت مش رفاهية.
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
    // الشغل نفسه في [handleNotificationAction] — نفس الدالة اللي
    // المقدمة بتنادي عليها. اللي فاضل هنا محوّل أندرويد وبس.
    await handleNotificationAction(
      db: db,
      actionId: response.actionId,
      payload: response.payload,
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
    );
    // **سطر النهاية الناجحة — تسجيل وبس، مفيش أي سلوك وراه.**
    // من غيره مفيش أي طريقة من برّه تعرف إن المعالج خلص: السطر الوحيد
    // اللي كان موجود هو سطر الفشل، فالسكوت كان بيعني «نجح» أو «لسه
    // شغّال» أو «العملية اتقتلت» — تلاتة من غير فرق بينهم. الاختبار
    // المُجهَّز بيستنّى السطر ده (أو سطر الفشل) بدل ما يفتح القاعدة
    // ويزاحم اللي بيكتبها.
    diag('Isolate: خلص المعالج — handled=ok action=${response.actionId}');
  } catch (error, stack) {
    diag('زرار الإشعار مقدرش يتعالج في الخلفية: $error\n$stack');
  } finally {
    await cloud?.shutdown();
    await db.close();
    // من غير ده النظام بيقفل التطبيق قفل لما المهلة تخلص.
    await BackgroundTask.end(task);
  }
}
