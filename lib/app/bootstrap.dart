import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;

import '../ai/gemini_config.dart';
import '../ai/prescription_reader.dart';
import '../core/notifications/notification_service.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/repositories/dose_event_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/services/notification_actions.dart';
import '../data/services/reminder_scheduler.dart';
import 'app_scope.dart';

/// بيبني كل خدمات التطبيق فوق قاعدة بيانات مفتوحة.
///
/// نفس الدالة بتتستخدم من `main` ومن صحوة الخلفية — عشان الاتنين يشوفوا
/// نفس المريض ونفس خانة الإشعارات، ومفيش نسختين من المنطق تتفرّقا.
Future<AppServices> buildServices(AppDatabase db) async {
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
    ),
    patientId: patientId,
    tapPayload: NotificationService.lastPayload,
    prescriptionReader: _readerFromEnvironment(),
  );
}

/// المفتاح من `--dart-define` وبس. لو مش موجود بنرجّع null ونقولها في
/// الشاشة — مش بنكسر فتح التطبيق، ومش بننده الـAPI بمفتاح فاضي أبداً.
PrescriptionReader? _readerFromEnvironment() {
  final config = GeminiConfig.tryFromEnvironment();
  if (config == null) {
    debugPrint(GeminiConfig.missingKeyMessage);
    return null;
  }
  return GeminiPrescriptionReader(config);
}

NotificationActionHandler actionHandlerFor(AppServices services) =>
    NotificationActionHandler(
      routines: services.routines,
      medications: services.medications,
      events: services.events,
      scheduler: services.scheduler,
      patientId: services.patientId,
    );

/// زرار على الإشعار والتطبيق مقفول.
///
/// النظام بيصحّي التطبيق على isolate منفصل ويندَه الدالة دي. مفيش واجهة
/// ولا `runApp`: بنفتح قاعدة البيانات، نسجّل، نمدّ النافذة، ونقفل. لازم
/// تفضل دالة عليا بالـpragma ده وإلا المترجم بيشيلها.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse response) async {
  // الـisolate ده جديد: الإضافات (path_provider، الإشعارات) لازم تتسجّل فيه.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final db = AppDatabase(openConnection());
  try {
    await NotificationService.init();
    final services = await buildServices(db);
    await actionHandlerFor(services).handle(response.actionId, response.payload);
  } catch (error, stack) {
    debugPrint('زرار الإشعار مقدرش يتعالج في الخلفية: $error\n$stack');
  } finally {
    await db.close();
  }
}
