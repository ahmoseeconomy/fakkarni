/// نافذة الابن — قراءة من السحابة مباشرة، من غير أي نسخة في drift.
///
/// جهاز الابن ما فيهوش نسخة من بيانات والده عن قصد (3.4): موبايله عمره ما
/// يرن على جرعات أبوه. الشاشة دي بتعرض اللي جهاز الأب دفعه — **وعمرها ما
/// تحسب مواعيد**: حلّ المراسي محتاج روتين الأب ومحرّكه، ونسخة تانية من
/// المحرّك هنا معناها جدولين ممكن يختلفوا في صمت. الجدول الوحيد في المنتج
/// هو اللي على موبايل الأب؛ إحنا بنعرض اللي كتبه، أو ما نعرضش.
library;

export 'care_circle_service.dart' show CareCircleException, CareCircleFailure;

class CaregiverPatient {
  const CaregiverPatient({required this.uuid, required this.name});
  final String uuid;
  final String name;
}

class CaregiverMedication {
  const CaregiverMedication({
    required this.uuid,
    required this.name,
    this.amountLabel,
  });
  final String uuid;
  final String name;
  final String? amountLabel;
}

/// حدث جرعة زي ما جهاز الأب كتبه — الحالة بالحرف، والوقت اللي هو حسبه.
class CaregiverDoseEvent {
  const CaregiverDoseEvent({
    required this.uuid,
    required this.medicationName,
    required this.scheduledAt,
    required this.state,
    this.amountLabel,
    this.actedAt,
  });

  final String uuid;
  final String medicationName;
  final String? amountLabel;

  /// اللحظة اللي محرّك الأب حسبها — محلية الجهاز ده للعرض.
  final DateTime scheduledAt;

  /// 'pending' | 'taken' | 'skipped' | 'missed' — بالحرف من السحابة
  /// ('superseded' بيتفلتر في الاستعلام وما بيوصلش هنا).
  final String state;
  final DateTime? actedAt;

  /// اتأكدت بإيد حد: اتاخدت أو قال مش هياخدها.
  bool get confirmed => state == 'taken' || state == 'skipped';
}

/// صف من `escalations` — سجل اللي السيرفر عمله، مش حكم على الأب.
///
/// بس الصفوف اللي اتقرّر مصيرها: `sent` (وصل FCM) أو `no_token`/`failed`
/// (السيرفر حاول وما وصلش). `claimed` بتتشال — الإرسال لسه شغّال، وبعد
/// ٥ دقايق بيتقرّر أو بيتعاد.
class CaregiverAlert {
  const CaregiverAlert({
    required this.uuid,
    required this.medicationName,
    required this.scheduledAt,
    required this.doseState,
    required this.deliveryStatus,
    required this.createdAt,
    this.sentAt,
  });

  final String uuid;
  final String medicationName;

  /// وقت الجرعة زي ما جهاز الأب كتبه على dose_events.
  final DateTime scheduledAt;

  /// حالة الجرعة **دلوقتي** — ممكن تكون اتغيّرت بعد التنبيه.
  final String doseState;

  /// 'sent' | 'no_token' | 'failed' — بالحرف من السحابة.
  final String deliveryStatus;

  /// لحظة ما السيرفر حجز التنبيه.
  final DateTime createdAt;

  /// موجود بس لما FCM قبل الرسالة.
  final DateTime? sentAt;

  bool get delivered => deliveryStatus == 'sent' && sentAt != null;

  /// اتاخدت بعد التنبيه. «مش هاخده» مش ✓ — ما خدهاش.
  bool get takenLater => doseState == 'taken';
}

class CaregiverSnapshot {
  const CaregiverSnapshot({
    required this.patient,
    required this.medications,
    required this.events,
    this.alerts = const [],
    this.lastUpdated,
  });

  final CaregiverPatient patient;
  final List<CaregiverMedication> medications;

  /// آخر ٧ أيام، تصاعدياً بالوقت.
  final List<CaregiverDoseEvent> events;

  /// تنبيهات السيرفر **ليّا أنا** في آخر ٤٨ ساعة، الأحدث الأول. RLS بتوريني
  /// تنبيهات إخواتي كمان؛ الفلترة على caregiver_id هنا عشان «بلّغك» تبقى
  /// صادقة، مش عشان الصلاحية.
  final List<CaregiverAlert> alerts;

  /// أكبر updated_at **من السيرفر** عبر صفوفه. تحديث بيانات — مش «آخر
  /// ظهور»: مفيش حاجة هنا بتثبت إن الموبايل عايش، بس إن بيانات اتغيّرت.
  final DateTime? lastUpdated;
}

/// RLS هي اللي بتحدّد المدى — مفيش فلترة عميل بالمالك أبداً.
abstract interface class CaregiverRemote {
  /// المريض المربوط بعلاقة accepted — null لو مفيش.
  Future<CaregiverPatient?> linkedPatient();

  /// اللقطة كاملة — null لو مفيش ربط.
  Future<CaregiverSnapshot?> snapshot();
}
