import 'package:flutter/widgets.dart';

import '../ai/prescription_reader.dart';
import '../data/auth/auth_service.dart';
import '../data/care/care_circle_service.dart';
import '../data/db/app_database.dart';
import '../data/repositories/dose_event_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/services/reminder_scheduler.dart';

/// كل خدمات التطبيق في مكان واحد.
///
/// مفيش مكتبة إدارة حالة هنا عن قصد: drift بيدي `Stream` جاهز لكل استعلام،
/// و`StreamBuilder` بيكفي. أقل اعتماديات = أقل حاجات تقع.
class AppServices {
  const AppServices({
    required this.db,
    required this.routines,
    required this.medications,
    required this.events,
    required this.scheduler,
    required this.patientId,
    this.tapPayload,
    this.prescriptionReader,
    this.auth,
    this.care,
  });

  final AppDatabase db;
  final RoutineRepository routines;
  final MedicationRepository medications;
  final DoseEventRepository events;
  final ReminderScheduler scheduler;
  final int patientId;

  /// آخر إشعار المستخدم دَس عليه — بيجي من [NotificationService.lastPayload].
  ///
  /// null في الاختبارات اللي مش بتهمها الدوسة. الجذر بيسمع له ويفتح شاشة
  /// التذكير على الجرعة الصح، وبيصفّره بعد ما يقرأه.
  final ValueNotifier<String?>? tapPayload;

  /// قارئ الروشتة — null لو مفتاح Gemini مش متظبط. التذكيرات ما بتعتمدش
  /// عليه؛ شاشة التصوير بس هي اللي بتقول إنه ناقص.
  final PrescriptionReader? prescriptionReader;

  /// الهوية الاختيارية — null لو إعداد Supabase مش موجود، والتطبيق كامل
  /// من غيرها. بابها الوحيد «اربط ابني».
  final AuthService? auth;

  /// دائرة الرعاية — نفس شرط الهوية، ونفس الغياب الهادي.
  final CareCircleService? care;
}

class AppScope extends InheritedWidget {
  const AppScope({
    required this.services,
    required super.child,
    super.key,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope مش موجود فوق الشجرة');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
