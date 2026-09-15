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
    this.rules = const [],
  });
  final String uuid;
  final String name;
  final String? amountLabel;

  /// قاعدة كل جرعة زي ما اتسجلت — «الفطار − ٣٠ د» أو «ساعة ثابتة · ٨:٠٠ ص».
  /// نص من `domain/wording`، مش ساعة محسوبة: جانب الابن ما بيحلّش مراسي.
  final List<String> rules;
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
    this.records = const [],
    this.readings = const [],
    this.emergency,
    this.questions = const [],
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

  // ---- الملف الصحي (D5.2) — كله محدود في الاستعلام، وكله قراية بس.

  /// السجلات اللي **مش** ممسوحة، الأحدث وصولاً الأول، بسطور تحاليلها.
  final List<CaregiverRecord> records;

  /// قياسات السكر في آخر ٣٠ يوم، الأحدث الأول.
  final List<CaregiverReading> readings;

  /// فصيلة الدم والحساسية والأمراض المزمنة. null = الأب ما ملاش حاجة.
  /// **مفيش أرقام تليفونات** — مش في السحابة أصلاً (0012).
  final CaregiverEmergency? emergency;

  /// أسئلة الدكتور، الأحدث الأول.
  final List<CaregiverQuestion> questions;
}

/// نوع السجل بالحرف المخزّن: imaging | visit | lab | prescription | booking.
class CaregiverRecord {
  const CaregiverRecord({
    required this.uuid,
    required this.kind,
    required this.title,
    required this.happenedAt,
    required this.updatedAt,
    this.doctor,
    this.place,
    this.notes,
    this.labLines = const [],
  });

  final String uuid;
  final String kind;
  final String title;

  /// تاريخ الحدث نفسه — اللي بيتعرض.
  final DateTime happenedAt;

  /// لحظة الوصول للسحابة — اللي «الجديد» بيترتّب بيه.
  final DateTime updatedAt;
  final String? doctor;
  final String? place;
  final String? notes;
  final List<CaregiverLabLine> labLines;
}

class CaregiverLabLine {
  const CaregiverLabLine({required this.testName, required this.value, this.unit});
  final String testName;
  final double value;
  final String? unit;
}

/// قياس سكر — `context` بالحرف: fasting | afterMeal.
class CaregiverReading {
  const CaregiverReading({
    required this.uuid,
    required this.valueMgDl,
    required this.measuredAt,
    required this.context,
    required this.updatedAt,
  });
  final String uuid;
  final int valueMgDl;
  final DateTime measuredAt;
  final String context;
  final DateTime updatedAt;
}

class CaregiverEmergency {
  const CaregiverEmergency({this.bloodType, this.allergies, this.chronicConditions});
  final String? bloodType;
  final String? allergies;
  final String? chronicConditions;
}

class CaregiverQuestion {
  const CaregiverQuestion({
    required this.uuid,
    required this.body,
    required this.writtenAt,
    required this.asked,
    required this.updatedAt,
  });
  final String uuid;
  final String body;
  final DateTime writtenAt;
  final bool asked;
  final DateTime updatedAt;
}

/// حاجة واحدة في «الجديد» — أي نوع.
enum NewItemType { record, reading, question }

class CaregiverNewItem {
  const CaregiverNewItem({
    required this.type,
    required this.arrivedAt,
    required this.happenedAt,
    this.record,
    this.reading,
    this.question,
  });
  final NewItemType type;

  /// الترتيب — لحظة الوصول.
  final DateTime arrivedAt;

  /// التاريخ اللي بيتعرض — تاريخ الحدث نفسه.
  final DateTime happenedAt;
  final CaregiverRecord? record;
  final CaregiverReading? reading;
  final CaregiverQuestion? question;
}

/// «الجديد» (PHASE_D5 قاعدة ٤): آخر [limit] حاجات **وصلت**، من أي نوع،
/// مترتبة بـ`updated_at` مش بتاريخ الحدث — تحليل من ٢٠١٩ اتسجّل النهارده جديد
/// بالنسبة للابن. أحداث الجرعات مش هنا: `updated_at` بتاعها بيتغيّر مع كل
/// تأكيد، وليها «النهارده» والأسبوع.
List<CaregiverNewItem> newestArrivals(CaregiverSnapshot snapshot, {int limit = 10}) {
  final items = [
    for (final r in snapshot.records)
      CaregiverNewItem(type: NewItemType.record, arrivedAt: r.updatedAt, happenedAt: r.happenedAt, record: r),
    for (final r in snapshot.readings)
      CaregiverNewItem(type: NewItemType.reading, arrivedAt: r.updatedAt, happenedAt: r.measuredAt, reading: r),
    for (final q in snapshot.questions)
      CaregiverNewItem(type: NewItemType.question, arrivedAt: q.updatedAt, happenedAt: q.writtenAt, question: q),
  ]..sort((a, b) => b.arrivedAt.compareTo(a.arrivedAt));
  return items.take(limit).toList();
}

/// RLS هي اللي بتحدّد المدى — مفيش فلترة عميل بالمالك أبداً.
abstract interface class CaregiverRemote {
  /// المريض المربوط بعلاقة accepted — null لو مفيش.
  Future<CaregiverPatient?> linkedPatient();

  /// اللقطة كاملة — null لو مفيش ربط.
  Future<CaregiverSnapshot?> snapshot();
}
