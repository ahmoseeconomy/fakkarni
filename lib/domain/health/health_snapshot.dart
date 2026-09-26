/// كل اللي فحص السلامة محتاج يعرفه عن الجهاز — **ولا حاجة زيادة**.
///
/// دارت نقي: مفيش إضافات ولا قاعدة بيانات هنا، فالاختبار بيبني لقطة
/// حرفية ويقرا النتيجة. نفس شكل محرّك الجدولة ولنفس السبب — المنطق اللي
/// بيقرر إن «الوعد مكسور» لازم يتقرا في ثانية.
library;

enum HealthPlatform { ios, android, other }

/// إذن الإشعارات زي ما النظام بيقوله.
///
/// [provisional] مش نص إذن هنا: إشعار هادي بيروح لمركز الإشعارات من غير
/// صوت، وراجل عنده ٧٢ سنة مش هيفتح المركز. للتذكير بالدوا ده مكسور.
enum NotificationPermission { granted, denied, provisional, unknown }

/// تحسين البطارية على أندرويد — **بتلات حالات عن قصد**.
///
/// [unknown] مش نفس [unrestricted]: الاتنين بيتعرضوا للمريض بنفس الشكل
/// (مفيش صف على الشاشة — إنذار كذب أسوأ من فحص ساكت)، بس على السيرفر
/// لازم يتفرّقوا. «كله تمام» و«ما قدرناش نبص» بيبقوا شكل واحد من برّه
/// وبعدين محدش ياخد باله إن القناة نفسها بايظة على ألف جهاز.
enum BatteryState { unrestricted, restricted, unknown }

class HealthSnapshot {
  const HealthSnapshot({
    required this.now,
    required this.platform,
    required this.permission,
    this.isCaregiver = false,
    this.activeDoseCount = 0,
    this.plannedDoseCount = 0,
    this.pendingDoseCount = 0,
    this.pendingCount = 0,
    this.pendingLimit = 64,
    this.horizonUntil,
    this.deviceTimezone = '',
    this.scheduledTimezone,
    this.hasCaregiver = false,
    this.hasPushToken = false,
    this.cloudConfigured = false,
    this.signedIn = false,
    this.dirtyRowCount = 0,
    this.oldestDirtyAt,
    this.lastSyncedAt,
    this.caregiverName,
    this.syncBlockedForAccount = false,
    this.exactAlarmsAllowed = true,
    this.batteryState = BatteryState.unrestricted,
    this.aiKeyPresent = true,
    this.rungFirstOn = true,
    this.rungSecondOn = true,
    this.mediaProblemSince,
    this.mediaRejectedAt,
    this.planTruncated = false,
    this.patternRejectedSince,
    this.listenProblemSince,
  });

  /// آخر مرة المايك اتداس والسماع ما بدأش (مش الإذن) — null = مفيش.
  final DateTime? listenProblemSince;

  final DateTime now;
  final HealthPlatform platform;

  /// ٠٠٢٩: أول فشل رفع صورة دوا قعد أكتر من يوم — null = الطابور ماشي.
  final DateTime? mediaProblemSince;

  /// ٠٠٢٩: آخر مرة صورة من الممرض اترفضت.
  final DateTime? mediaRejectedAt;

  /// آخر خطة جدولة اتقصّت؟ (تذكيرات أساسية أكتر من الميزانية) — من غيرها
  /// «التغطية قليلة» ما تتقالش.
  final bool planTruncated;

  /// ٠٠٣٢: أول مرة السحابة رفضت جدول بنمط أيام — null = مفيش مشكلة.
  final DateTime? patternRejectedSince;
  final NotificationPermission permission;

  /// الموبايل ده بتاع الابن (مربوط بأب) ولا بتاع المريض؟ فيه فحوص
  /// معناها بيتقلب بين الاتنين.
  final bool isCaregiver;

  /// جرعات لها قاعدة شغّالة النهارده — صفر معناه إن مفيش وعد أصلاً.
  final int activeDoseCount;

  /// اللي **إحنا** قررنا نجدوله، و اللي **الجهاز ماسكه فعلاً**.
  ///
  /// الفرق بين الرقمين هو نفسه صنف العيب اللي ضيّع يوم كامل: iOS بيرمي
  /// اللي زيادة عن ٦٤ من غير خطأ ومن غير تحذير.
  final int plannedDoseCount;
  final int pendingDoseCount;

  /// كل اللي الجهاز ماسكه (جرعات وسلّم وصيام ومتابعة) والسقف بتاعه.
  final int pendingCount;
  final int pendingLimit;

  /// آخر تذكير جرعة **الجهاز ماسكه** — محسوب من `pending()`، مش من الخطة.
  final DateTime? horizonUntil;

  final String deviceTimezone;

  /// المنطقة اللي التذكيرات اتبنت عليها آخر مرة. null = أول فحص.
  final String? scheduledTimezone;

  final bool hasCaregiver;
  final bool hasPushToken;
  final bool cloudConfigured;
  final bool signedIn;

  final int dirtyRowCount;
  final DateTime? oldestDirtyAt;
  final DateTime? lastSyncedAt;

  /// اسم اللي بيتابعه — للجملة «التأكيدات لسه ما وصلتش لـمحمد». null =
  /// «للي بيتابعك».
  final String? caregiverName;

  /// السيرفر رفض الحساب ده (مفتاح أجنبي / صلاحيات) والطابور واقف.
  final bool syncBlockedForAccount;

  final bool exactAlarmsAllowed;

  /// أندرويد: حالة تحسين البطارية. الشك بيتحسب سليم **على الشاشة**،
  /// وبيتسجّل بنفسه في النبضة.
  final BatteryState batteryState;
  final bool aiKeyPresent;

  /// مفاتيح درجات السلّم (+١٥ و+٣٠) — المستخدم يقدر يقفلهم من الإعدادات.
  final bool rungFirstOn;
  final bool rungSecondOn;
}
