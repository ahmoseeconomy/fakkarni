/// نافذة الابن — قراءة من السحابة مباشرة، من غير أي نسخة في drift.
///
/// جهاز الابن ما فيهوش نسخة من بيانات والده عن قصد (3.4): موبايله عمره ما
/// يرن على جرعات أبوه. الشاشة دي بتعرض اللي جهاز الأب دفعه — **وعمرها ما
/// تحسب مواعيد**: حلّ المراسي محتاج روتين الأب ومحرّكه، ونسخة تانية من
/// المحرّك هنا معناها جدولين ممكن يختلفوا في صمت. الجدول الوحيد في المنتج
/// هو اللي على موبايل الأب؛ إحنا بنعرض اللي كتبه، أو ما نعرضش.
library;

import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/health/lab_range.dart';
import '../dose_state.dart';

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

/// التنبيه لسه مفتوح والجرعة لسه محتاجة حد؟
///
/// **الحالتين المفتوحتين هما اللي السيرفر بيصعّد عليهم أصلاً** (`0011`):
///   * `pending` — محدش عمل حاجة لسه.
///   * `missed`  — جهاز الأب عدّى المهلة وكتبها. الاتنين معناهم واحد:
///                 «ما اتاخدتش»، والفرق مين اللي علّم مش حالة تانية.
///
/// والتلاتة التانية مقفولة، وكل واحدة لسبب مختلف:
///   * `taken`      — خدها. تنبيه بيقول «ما أكّدش» عن جرعة اتاخدت هو **كدب**،
///                    والابن اللي يكتشف إن التنبيهات بتكدب بيبطّل يقراها.
///   * `skipped`    — قرار إنسان: «مش هاخده». مش نسيان، ومش حاجة تتنبّه عليها.
///   * `superseded` — القاعدة اتغيّرت، فالجرعة دي ما كانتش موجودة أصلاً
///                    (`0010`)، والسيرفر نفسه ما بيختارهاش.
///
/// **والـswitch هنا شامل عن قصد**: حالة جديدة في [DoseState] بتكسر الترجمة
/// هنا بالظبط، فحد لازم يقرر هي مفتوحة ولا مقفولة. من غير كده كانت
/// هتتحسب مقفولة في صمت — أو أسوأ، تبقى تنبيه محدش قرره.
bool isOpenDoseState(DoseState state) => switch (state) {
      DoseState.pending || DoseState.missed => true,
      DoseState.taken || DoseState.skipped || DoseState.superseded => false,
    };

/// نفس القايمة بأسماء السلك — دي اللي بتروح للاستعلام.
final List<String> openDoseStateNames = [
  for (final s in DoseState.values)
    if (isOpenDoseState(s)) s.name,
];

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

  /// الجرعة لسه محتاجة حد؟ الاستعلام بيفلتر على ده في السحابة، والسطر ده
  /// خط دفاع تاني لو صف قديم عدّى.
  bool get open {
    final s = DoseState.values.asNameMap()[doseState];
    // اسم مش معروف = مش بنعرضه. تنبيه عن حالة محدش يعرفها مش تنبيه.
    return s != null && isOpenDoseState(s);
  }
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
    this.checkupStage,
    this.followKind,
    this.checkupStageSince,
    this.labBookingAt,
    this.resultReadyAt,
    this.doctorVisitAt,
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

  // ----------------------------------------------------------- المتابعات
  // **قراية بس، وجوّه اللي الابن بيشوفه أصلاً.** الأعمدة دي على
  // `public.records` نفسه — نفس الصف اللي `records_select` بيسمح له بيه
  // من `0012` عن طريق `private.can_access_patient`. سياسات RLS في
  // بوستجرس على مستوى **الصف** مش العمود، و`0015`/`0017` زوّدوا أعمدة
  // على نفس الجدول من غير ما يلمسوا ولا سياسة. يعني مفيش هجرة ولا سياسة
  // جديدة محتاجة هنا — الاستعلام بس هو اللي كان ناقصهم.

  /// رقم المرحلة زي ما جهاز الأب كتبه. null = الصف ده مش متابعة أصلاً.
  final int? checkupStage;

  /// `lab` / `visit`. **null معناها `lab`** — قبل الجولة ٢٤ ما كانش فيه
  /// نوع تاني، فده مش تخمين.
  final String? followKind;

  /// ساعة دخول المرحلة الحالية — منها بس بيتحسب «واقفة من أسبوع».
  final DateTime? checkupStageSince;

  final DateTime? labBookingAt;
  final DateTime? resultReadyAt;

  /// معاد الدكتور — **وهو نفسه معاد الزيارة** في متابعة الزيارة: المعنى
  /// واحد، والصف نوعه واحد بس.
  final DateTime? doctorVisitAt;
}

class CaregiverLabLine {
  const CaregiverLabLine({required this.testName, required this.value, this.unit, this.range});
  final String testName;
  final double value;
  final String? unit;

  /// نطاق الورقة زي ما جهاز الأب رفعه — null لو الورقة ما طبعتش نطاق.
  /// الابن بيشوف نفس اللي الأب شافه بنفس القاعدة؛ مفيش حساب تاني هنا، زي
  /// ما مفيش حلّ مراسي.
  final LabRange? range;
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
    // **المتابعة المفتوحة مش «جديد»، هي حاجة شغّالة** — وليها قسمها فوق.
    // وكل ما الأب يقدّم مرحلة بيتغيّر `updated_at`، فكانت بتطلع أول
    // «الجديد» كأنها حاجة وصلت دلوقتي، بتاريخ ورقتها القديم جنبها.
    for (final r in snapshot.records)
      if (!followIsOpen(FollowKind.fromStored(r.followKind),
          FollowKind.fromStored(r.followKind).stageFromNumber(r.checkupStage)))
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
