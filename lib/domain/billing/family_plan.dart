// **اشتراك العيلة** — دارت نقية (قرار المالك، تعليق المختبِر ٣).
//
// اشتراك **واحد** بيغطّي المريض ولحد خمس ناس بيتابعوه (متابعين أو ممرضين).
// مش «كل واحد بيدفع». أي حد في الدائرة يقدر يشتريه للمريض.
//
// **قاعدتين ما بيتنازلش عنهم:**
// ١. تذكير المريض بدواه **عمره ما يقف** بسبب الدفع ولا انتهاء التجربة ولا
//    فشل التحقق. البوابة على مزايا العيلة والزيادات بس — وفيه حارس بيقرا
//    المصدر ويوقع لو الجدولة استوردت أي حاجة من هنا.
// ٢. لو التحقق مش واصل، آخر حالة معروفة هي اللي بتمشي (مهلة) — عمرنا ما
//    نقفل على حد بسبب شبكة.

/// حالة الاشتراك زي ما هي على السيرفر.
enum SubscriptionStatus {
  trial,
  active,
  expired;

  static SubscriptionStatus? fromStored(String? s) => values.asNameMap()[s];
}

/// الأرقام والمعرّفات — **مكان واحد**، ومرآته في SQL (`0025`) بتتقفل باختبار.
class SubscriptionConfig {
  const SubscriptionConfig._();

  /// تجربة المريض الجديد: ١٤ يوم من إنشاء حسابه.
  static const trialDays = 14;

  /// المرضى الموجودين وقت الترحيل: ٣٠ يوم من تاريخ الترحيل.
  static const migrationTrialDays = 30;

  /// مهلة بعد الانتهاء المكتوب — التحقق ممكن يتأخر، وآخر حالة معروفة بتمشي.
  static const graceDays = 3;

  /// أقصى عدد ناس بيتابعوا مريض واحد — نفس `followerCap` بتاع الشاشة.
  static const followerCap = 5;

  /// معرّفات المنتجات في المتجرين — **عناصر نائبة** لحد ما الشركة تعملها
  /// (HANDOVER B7). الأسعار **من المتجر** دايماً، مش هنا.
  static const monthlyProductId = 'fakkarni_family_monthly';
  static const yearlyProductId = 'fakkarni_family_yearly';
  static const productIds = {monthlyProductId, yearlyProductId};
}

/// حالة اشتراك مريض واحد.
class FamilySubscription {
  const FamilySubscription({
    required this.status,
    required this.trialEndsAt,
    this.expiresAt,
    this.store,
    this.productId,
    this.lastVerifiedAt,
  });

  final SubscriptionStatus status;
  final DateTime trialEndsAt;
  final DateTime? expiresAt;
  final String? store;
  final String? productId;
  final DateTime? lastVerifiedAt;

  /// المزايا العائلية مسموحة دلوقتي؟ التجربة لحد نهايتها، والنشط لحد
  /// انتهائه + مهلة [SubscriptionConfig.graceDays].
  bool allowsFamilyAt(DateTime now) => switch (status) {
        SubscriptionStatus.trial => now.isBefore(trialEndsAt),
        SubscriptionStatus.active =>
          expiresAt == null || now.isBefore(expiresAt!.add(const Duration(days: SubscriptionConfig.graceDays))),
        SubscriptionStatus.expired => false,
      };

  Map<String, Object?> toJson() => {
        'status': status.name,
        'trial_ends_at': trialEndsAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'store': store,
        'product_id': productId,
        'last_verified_at': lastVerifiedAt?.toIso8601String(),
      };

  static FamilySubscription? fromJson(Map<String, dynamic> json) {
    final status = SubscriptionStatus.fromStored(json['status'] as String?);
    final trial = json['trial_ends_at'];
    if (status == null || trial is! String) return null;
    DateTime? at(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return FamilySubscription(
      status: status,
      trialEndsAt: at(trial)!,
      expiresAt: at(json['expires_at']),
      store: json['store'] as String?,
      productId: json['product_id'] as String?,
      lastVerifiedAt: at(json['last_verified_at']),
    );
  }
}

/// **إيه المجاني وإيه بتاع العيلة** — قايمة واحدة، سهلة تتغيّر.
///
/// **افتراضي مستني تأكيد المالك.**
enum AppFeature {
  // ---- مجاني للأبد
  reminders('كل التذكيرات — الجرعة والسلّم والإعادات', family: false),
  medications('إضافة الأدوية وتعديلها', family: false),
  today('«يومك»', family: false),
  medicalFile('الملف الصحي على الموبايل', family: false),
  emergencyCard('بطاقة الطوارئ', family: false),
  // ---- اشتراك العيلة
  circle('ربط متابعين وممرضين وتنبيهاتهم', family: true),
  nurseMirror('مرآة الممرض والتأكيد بداله', family: true),
  scans('قراية الروشتة والعلبة والتحليل بالكاميرا', family: true),
  exportBeyondFree('تصدير الملف PDF بعد أول ٣ مرات', family: true);

  const AppFeature(this.label, {required this.family});

  final String label;

  /// true = محتاج اشتراك العيلة؛ false = مجاني للأبد مهما حصل.
  final bool family;

  static List<AppFeature> get freeForever => [for (final f in values) if (!f.family) f];
  static List<AppFeature> get familyOnly => [for (final f in values) if (f.family) f];
}

/// عدد التصديرات المجانية قبل ما البوابة تتقفل.
const int freeExports = 3;

/// **قرار البوابة** — لميزة عائلية: التجربة/النشط بيسمحوا؛ مفيش حالة
/// معروفة (التحقق مش واصل ولا مرة) = مسموح؛ الحالة القديمة المحفوظة بتمشي
/// كمهلة. الميزة المجانية مسموحة **دايماً** مهما كانت الحالة.
bool featureAllowed(
  AppFeature feature, {
  required FamilySubscription? subscription,
  required DateTime now,
  bool? lastKnownAllowed,
  bool? debugOverride,
}) {
  if (!feature.family) return true;
  if (debugOverride != null) return debugOverride;
  if (subscription != null) return subscription.allowsFamilyAt(now);
  return lastKnownAllowed ?? true;
}

/// سطر الحالة على شاشة الاشتراك — بكلام البيت.
String subscriptionStatusLine(FamilySubscription? sub, DateTime now, String Function(DateTime) date) {
  if (sub == null) return 'لسه ما قدرناش نتأكد من الاشتراك — كل حاجة شغّالة لحد ما نتأكد.';
  return switch (sub.status) {
    SubscriptionStatus.trial when now.isBefore(sub.trialEndsAt) => 'التجربة المجانية شغّالة لحد ${date(sub.trialEndsAt)}.',
    SubscriptionStatus.trial => 'التجربة المجانية خلّصت ${date(sub.trialEndsAt)}.',
    SubscriptionStatus.active when sub.expiresAt == null => 'اشتراك العيلة شغّال.',
    SubscriptionStatus.active => 'اشتراك العيلة شغّال لحد ${date(sub.expiresAt!)}.',
    SubscriptionStatus.expired => 'اشتراك العيلة خلص — التذكيرات شغّالة زي ما هي.',
  };
}

/// الجملة اللي لازم تبقى على الشاشة بالحرف.
const String remindersStayFreeLine = 'تذكير الدوا مجاني للأبد — ما بيقفش بسبب الاشتراك.';

// ---------------------------------------------------------------------------
// **الدائرة لازم تعرف قبل ما التنبيهات تقف، وبعد ما تقف.**
//
// لما الاشتراك يخلص السيرفر بيبطّل يبلّغ المتابعين عن جرعة فايتة
// (`follower_subscription_active` في 0025). ده صح — بس لو محدش اتقال له،
// الأب فاكر إن فيه حد شايفه والابن فاكر إنه هيتبلّغ. فيه تلات حالات بس،
// محسوبة هنا مرة واحدة والشاشتين بيقروا منها.

/// الأيام اللي الإشعار قبل النهاية بيتقال عندها — ٧ و٣ و١. الكارت ظاهر من
/// أول ما يفضل ٧ أيام، وكلامه بيتغيّر عند كل واحدة منهم.
const List<int> familyNoticeMilestones = [7, 3, 1];

enum FamilyNoticeKind {
  /// مفيش حاجة تتقال.
  none,

  /// فاضل ٧ أيام أو أقل والتنبيهات هتقف.
  endingSoon,

  /// التنبيهات واقفة دلوقتي.
  ended,
}

class FamilyNotice {
  const FamilyNotice._(this.kind, {this.endsAt, this.daysLeft, this.milestone});

  static const none = FamilyNotice._(FamilyNoticeKind.none);
  static const ended = FamilyNotice._(FamilyNoticeKind.ended);

  final FamilyNoticeKind kind;

  /// اللحظة اللي السيرفر بيبطّل يبلّغ فيها — نفس حدّ `allowsFamilyAt`.
  final DateTime? endsAt;

  /// أيام تقويم من النهارده لحد يوم النهاية (٠ = النهارده).
  final int? daysLeft;

  /// أقرب علامة من ٧/٣/١ وصلنا لها — بتفرّق الكلام، مش الظهور.
  final int? milestone;
}

/// آخر لحظة المزايا العائلية فيها شغّالة — `null` = مفيش نهاية معروفة
/// (نشط من غير تاريخ انتهاء). **نفس الحساب اللي في [FamilySubscription.allowsFamilyAt]**
/// بالظبط، عشان الكارت ما يقولش يوم غير اليوم اللي السيرفر هيقف فيه.
DateTime? familyEndsAt(FamilySubscription sub) => switch (sub.status) {
      SubscriptionStatus.trial => sub.trialEndsAt,
      SubscriptionStatus.active => sub.expiresAt?.add(const Duration(days: SubscriptionConfig.graceDays)),
      SubscriptionStatus.expired => null,
    };

/// **القرار الواحد**: هل الدائرة محتاجة تتقال لها حاجة، وإيه.
///
/// المحاكاة (للمطوّر) بتمشي هنا زي البوابة بالظبط، فـ«منتهي» من شاشة
/// الاشتراك بيوري الكارت. مفيش حالة معروفة = مفيش كارت: ما نقولش لحد إن
/// تنبيهاته واقفة من غير ما نكون عارفين.
FamilyNotice familyNotice({
  required FamilySubscription? subscription,
  required DateTime now,
  bool? lastKnownAllowed,
  bool? debugOverride,
}) {
  if (debugOverride != null) return debugOverride ? FamilyNotice.none : FamilyNotice.ended;
  if (subscription == null) return lastKnownAllowed == false ? FamilyNotice.ended : FamilyNotice.none;
  if (!subscription.allowsFamilyAt(now)) return FamilyNotice.ended;
  final end = familyEndsAt(subscription);
  if (end == null) return FamilyNotice.none;
  final today = DateTime.utc(now.year, now.month, now.day);
  final local = end.toLocal();
  final endDay = DateTime.utc(local.year, local.month, local.day);
  final days = endDay.difference(today).inDays;
  if (days > familyNoticeMilestones.first) return FamilyNotice.none;
  final milestone = familyNoticeMilestones.lastWhere((m) => days <= m, orElse: () => familyNoticeMilestones.last);
  return FamilyNotice._(FamilyNoticeKind.endingSoon, endsAt: end, daysLeft: days, milestone: milestone);
}

/// «محمد» / «محمد وسارة» / «محمد، سارة وأحمد».
String joinArabicNames(List<String> names) {
  final clean = [for (final n in names) if (n.trim().isNotEmpty) n.trim()];
  if (clean.isEmpty) return '';
  if (clean.length == 1) return clean.single;
  return '${clean.sublist(0, clean.length - 1).join('، ')} و${clean.last}';
}

/// كلام «هتقف» — المريض بيسمع أسامي اللي بيتابعوه، والمتابع بيسمع «تنبيهاتك».
/// [date] بيتحقن عشان الدومين يفضل دارت نقية.
String familyEndingLine({
  required FamilyNotice notice,
  required String Function(DateTime) date,
  List<String> followerNames = const [],
  String? patientName,
  bool forFollower = false,
}) {
  final when = notice.daysLeft == 0 ? 'النهارده' : 'يوم ${date(notice.endsAt!)}';
  final who = forFollower
      ? (patientName == null || patientName.trim().isEmpty ? 'تنبيهاتك' : 'تنبيهاتك عن ${patientName.trim()}')
      : (joinArabicNames(followerNames).isEmpty ? 'تنبيهات اللي بيتابعوك' : 'تنبيهات ${joinArabicNames(followerNames)}');
  return '$who هتقف $when لو الاشتراك ما اتجددش';
}

/// الكارت الدايم عند المتابع/الممرض بعد النهاية.
String familyEndedFollowerLine(String? patientName) {
  final name = patientName?.trim();
  return 'التنبيهات واقفة — مش هتتبلّغ لو ${name == null || name.isEmpty ? 'اللي بتتابعه' : name} فوّت جرعة';
}

/// السطر الواحد عند المريض بعد النهاية.
const String familyEndedPatientLine = 'اللي بيتابعوك مش بيتبلّغوا دلوقتي';
