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
    this.exactAlarmsAllowed = true,
    this.aiKeyPresent = true,
    this.rungFirstOn = true,
    this.rungSecondOn = true,
  });

  final DateTime now;
  final HealthPlatform platform;
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

  final bool exactAlarmsAllowed;
  final bool aiKeyPresent;

  /// مفاتيح درجات السلّم (+١٥ و+٣٠) — المستخدم يقدر يقفلهم من الإعدادات.
  final bool rungFirstOn;
  final bool rungSecondOn;
}
