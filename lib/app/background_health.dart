import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/diagnostics.dart';
import '../data/auth/supabase_init.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/health/health_collector.dart';
import '../data/health/health_heartbeat.dart';
import '../data/health/health_watcher.dart';
import '../data/sync/sync_service.dart';
import 'bootstrap.dart';

/// الفحص الآلي **مرة في اليوم في الخلفية** — من غير ما المريض يفتح التطبيق.
///
/// أندرويد: WorkManager دوري (٢٤ ساعة). iOS: BGAppRefreshTask بنفس المعرّف
/// (`BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: fetch` في
/// Info.plist، و`WorkmanagerPlugin.registerLaunchHandlers()` في
/// `didFinishLaunching` لأن التطبيق على دورة حياة UIScene — مقروء من مصدر
/// الإضافة المتسطّبة). النظام هو اللي بيقرر إمتى؛ «يومياً» طلب مش ضمان.
///
/// **ولا إشعار ولا شاشة من هنا.** نفس [HealthWatcher] بتاع المقدمة: بيقرا،
/// بيصلّح اللي يتصلّح (الإصلاح = `rescheduleAll` الموجودة، مفيش جدولة
/// جديدة)، وبيرفع النبضة لو فيه جلسة. الخنق (١٠ دقايق) شغّال هنا كمان.
///
/// **ما اتجرّبش على جهاز.** iOS ممكن ما يشغّلهاش أيام؛ ده مقبول — الفتحة
/// والرجوع للمقدمة والحفظ هما الطريق الأساسي، ودي شبكة أمان للي ما بيفتحش.
class BackgroundHealth {
  BackgroundHealth._();

  /// معرّف المهمة — **مرآة** لـ`BGTaskSchedulerPermittedIdentifiers` في
  /// Info.plist (`background_health_test` بيقفل عليها).
  static const taskId = 'com.fakrny.app.health-daily';
  static const taskName = 'health_daily';
  static const every = Duration(hours: 24);

  /// بيتنده من `main` بعد ما المراقب اتركّب — مجاملة، عمره ما يرمي.
  static Future<void> register() async {
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(healthBackgroundDispatcher);
      await Workmanager().registerPeriodicTask(
        taskId,
        taskName,
        frequency: every,
        initialDelay: every,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
    } catch (error) {
      // اختبارات / منصة من غيرها — الفحص في المقدمة شغّال زي ما هو
      diag('Health: تسجيل الفحص اليومي في الخلفية وقع ($error)');
    }
  }
}

/// نقطة دخول الـisolate — النظام بيندهها والتطبيق مقفول.
@pragma('vm:entry-point')
void healthBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundHealth.taskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    diag('Health: فحص يومي في الخلفية — بدأ');
    final db = AppDatabase(openConnection());
    IsolateCloud? cloud;
    try {
      final services = await buildServices(db);
      // السحابة اختيارية وبمهلة (نفس صحوة شاشة القفل): من غيرها الفحص محلي
      // والصف بيستنى لحد ما جلسة تيجي
      cloud = await initSupabaseForIsolate();
      final patient = await services.patients.getPatient(services.patientId);
      HealthHeartbeat? heartbeat;
      if (cloud != null && patient != null) {
        final c = cloud;
        final sync = SyncService(db: db, remote: c.syncRemote, hasSession: c.hasSession);
        // دفعة واحدة محدودة الأول — هي اللي بتقول إن السيرفر قابل الحساب
        await sync.pushOnce();
        heartbeat = HealthHeartbeat(
          remote: c.health,
          patientUuid: patient.uuid,
          eligible: sync.cloudOwnsPatient,
          userId: () async => c.userId(),
        );
      }
      await HealthWatcher(collector: HealthCollector(services), heartbeat: heartbeat).runIfDue();
      diag('Health: فحص يومي في الخلفية — خلص (${HealthWatcher.lastStatus?.wire ?? 'متخنوق'})');
      return true;
    } catch (error, stack) {
      diag('Health: الفحص اليومي في الخلفية وقع ($error)\n$stack');
      return true; // مفيش إعادة فورية — بكرة فيه فحص تاني
    } finally {
      await cloud?.shutdown();
      await db.close();
    }
  });
}
