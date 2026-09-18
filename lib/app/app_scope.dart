import 'package:flutter/widgets.dart';

import '../ai/lab_reader.dart';
import '../ai/prescription_reader.dart';
import '../data/auth/auth_service.dart';
import '../data/care/care_circle_service.dart';
import '../data/care/caregiver_remote.dart';
import '../data/push/push_tokens.dart';
import '../data/sync/sync_service.dart';
import '../data/db/app_database.dart';
import '../data/files/attachment_store.dart';
import '../data/repositories/dose_event_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/services/checkup_service.dart';
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
    this.labReader,
    this.attachments = const DirectoryAttachmentStore(),
    this.auth,
    this.care,
    this.caregiver,
    this.sync,
    this.push,
  });

  final AppDatabase db;
  final RoutineRepository routines;
  final MedicationRepository medications;
  final DoseEventRepository events;
  final ReminderScheduler scheduler;
  final int patientId;

  /// تفضيلات الجهاز (D3.3) — مشتقة من القاعدة، فكل مكان بيبني الخدمات
  /// بيلاقيها من غير سطر زيادة. الجدولة بتقراها من نسخة بتاعتها في
  /// `buildServices`.
  PreferencesRepository get preferences => PreferencesRepository(db);

  /// دورة الفحص وتذكير الصيام (D3.7) — نفس جهاز الإشعارات بتاع الجدولة.
  CheckupService get checkups => CheckupService(db, scheduler.sink);

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

  /// نافذة الابن — قراءة مباشرة من السحابة، مفيش نسخة محلية.
  final CaregiverRemote? caregiver;

  /// المزامنة — اتجاه واحد، صامتة، والمستخدم مش المفروض يعرف إنها موجودة.
  final SyncService? sync;

  /// توكن الدفع — null من غير سحابة أو من غير Firebase (أو على iOS
  /// لحد ما APNs تتظبط). غيابه معناه إن التصعيد بيقف عند `no_token`،
  /// والتطبيق بالكامل شغّال زي ما هو.
  final PushTokens? push;

  /// قارئ تقارير التحاليل (D3.6) — نفس مفتاح Gemini. null = المفتاح مش متظبط.
  final LabReportReader? labReader;

  /// صور التقارير — فولدر التطبيق. الاختبارات بتحط فولدر مؤقت.
  final AttachmentStore attachments;
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
