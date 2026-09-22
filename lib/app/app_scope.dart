import 'package:flutter/widgets.dart';

import '../ai/lab_reader.dart';
import '../ai/package_reader.dart';
import '../core/diagnostics.dart';
import '../ai/prescription_reader.dart';
import '../data/contacts/contact_picker.dart';
import '../data/contacts/native_contact_picker.dart';
import '../data/auth/auth_service.dart';
import '../data/care/care_circle_service.dart';
import '../data/care/caregiver_preferences.dart';
import '../data/care/caregiver_remote.dart';
import '../data/push/push_tokens.dart';
import '../data/sync/sync_service.dart';
import '../data/db/app_database.dart';
import '../data/files/attachment_store.dart';
import '../data/repositories/dose_event_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/services/appointment_scheduler.dart';
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
    this.packageReader,
    this.attachments = const DirectoryAttachmentStore(),
    this.contacts = const NativeContactPicker(),
    this.auth,
    this.care,
    this.caregiver,
    this.caregiverPreferences,
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

  /// **إشعارات المواعيد — سكّة لوحدها، بتتنده بعد الجرعات مش معاها.**
  ///
  /// القيد الأول في مواصفة المواعيد: **ما نلمسش تذكير الدوا**. عشان كده
  /// دي خدمة تانية بتنده `refresh()` **بعد** ما `rescheduleAll` ترجع،
  /// في `try/catch` بتاعها — فاستثناء في المواعيد مستحيل يمنع جرعة.
  AppointmentScheduler get appointments =>
      AppointmentScheduler(db: db, patientId: patientId, sink: scheduler.sink);

  /// بتتنده بعد كل `rescheduleAll` — **وبتبلع أي عطل**.
  ///
  /// ميعاد دكتور ما اتجدولش حاجة وحشة؛ جرعة ما اتجدولتش حاجة تانية خالص.
  /// السطر ده هو اللي بيفصل بينهم.
  Future<void> refreshAppointments({DateTime? now}) async {
    try {
      await appointments.refresh(now: now);
    } catch (error, stack) {
      diag('Appointments: الجدولة فشلت — التذكيرات مش متأثرة: $error\n$stack');
    }
  }

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

  /// تفضيلات المتابع — اسمه وصلته ونطاق تنبيهه وساعات هدوئه.
  ///
  /// null من غير سحابة: ساعتها أسئلة المتابع ما بتظهرش أصلاً، والتطبيق
  /// شغّال زي ما هو. **مش global**: بتتبني جنب باقي خدمات السحابة
  /// وبتتمرّر من `AppScope` زي أي حاجة تانية.
  final CaregiverPreferencesService? caregiverPreferences;

  /// المزامنة — اتجاه واحد، صامتة، والمستخدم مش المفروض يعرف إنها موجودة.
  final SyncService? sync;

  /// توكن الدفع — null من غير سحابة أو من غير Firebase (أو على iOS
  /// لحد ما APNs تتظبط). غيابه معناه إن التصعيد بيقف عند `no_token`،
  /// والتطبيق بالكامل شغّال زي ما هو.
  final PushTokens? push;

  /// قارئ تقارير التحاليل (D3.6) — نفس مفتاح Gemini. null = المفتاح مش متظبط.
  final LabReportReader? labReader;

  /// قارئ علب الأدوية — نفس المفتاح ونفس النقل. null = المفتاح مش متظبط،
  /// وشاشة التصوير هي اللي بتقول كده؛ «أكتبه بإيدي» شغّال زي ما هو.
  final MedicinePackageReader? packageReader;

  /// صور التقارير — فولدر التطبيق. الاختبارات بتحط فولدر مؤقت.
  final AttachmentStore attachments;

  /// منتقي جهة اتصال من النظام — شاشة الطوارئ بس بتستعمله، ومن زرار واحد.
  /// **ما بيقراش دفتر العناوين**: بيفتح شاشة النظام وبياخد اللي اتختار.
  final ContactPicker contacts;
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
