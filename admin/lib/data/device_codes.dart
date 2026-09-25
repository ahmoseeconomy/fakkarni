// أكواد السلامة → كلام الأدمن. **دارت ساذجة** — بتتختبر بجُمل من غير شاشة.
//
// الأكواد هي `HealthCode.name` زي ما `lib/domain/health/health_check.dart`
// في حزمة التطبيق بيكتبها في النبضة (`failing_codes`). كود جديد هناك من غير
// سطر هنا بيتعرض بالاسم اللاتيني — اللوحة للأدمن، فكود خام أحسن من سكوت.

import 'admin_models.dart';
import '../format/relative_time.dart';

/// جهاز ما بعتش نبضة من المدة دي = «ماوصلش منه حاجة» — **الغياب أخطر من
/// أي كود** (قاعدة ٠٠١٨): الجهاز الساكت مش بيقدر يقول عن نفسه.
const Duration deviceSilentAfter = Duration(hours: 24);

/// آخر نبضة أقدم من [deviceSilentAfter]، أو مفيش نبضة أصلاً.
bool deviceIsSilent(AdminDevice device, DateTime now) {
  final at = device.checkedAt;
  return at == null || now.difference(at) > deviceSilentAfter;
}

/// «فيه مشكلة» = فيه كود مكسور، أو الجهاز ساكت.
bool deviceHasProblem(AdminDevice device, DateTime now) =>
    device.failingCodes.isNotEmpty || deviceIsSilent(device, now);

/// سطر آخر فحص: «آخر فحص من ساعتين» أو «ماوصلش منه حاجة من ٣ أيام».
String deviceCheckedLine(AdminDevice device, DateTime now) {
  final at = device.checkedAt;
  if (at == null) return 'ماوصلش منه حاجة خالص';
  if (deviceIsSilent(device, now)) return 'ماوصلش منه حاجة ${timeSince(now, at)}';
  return 'آخر فحص ${timeSince(now, at)}';
}

/// الكود بكلام الأدمن — عربي عادي، من غير أسماء دوال.
///
/// [device] و[now] للجُمل اللي بتحتاج مدة (المزامنة الواقفة).
String deviceCodeLabel(String code, {AdminDevice? device, DateTime? now}) => switch (code) {
      'accountMissing' => 'الحساب مش موجود على السيرفر',
      'mediaSync' => 'صور الأدوية ما بتترفعش (أو صورة من الممرض اترفضت)',
      'lowCoverage' => 'التذكيرات المتجهّزة أقل من ٤٨ ساعة (مواعيد كتير)',
      'patternSync' => 'جدول بأيام معيّنة مستني هجرة ٠٠٣٢ على السيرفر',
      'staleSync' => _staleSyncLabel(device, now),
      'notificationPermission' => 'الإشعارات مقفولة',
      'pushToken' => 'مفيش توكن',
      'reminderHorizon' => 'مدى التذكير قرّب يخلص',
      'remindersDropped' => 'الجهاز رمى تذكيرات من المجدولة',
      'pendingBandFull' => 'حد الإشعارات المعلّقة اتملى',
      'timezoneChanged' => 'المنطقة الزمنية اتغيّرت والتذكير على القديمة',
      'noCaregiver' => 'مفيش حد بيتابعه',
      'exactAlarms' => 'التنبيه في معاده مش مسموح',
      'aiKeyMissing' => 'مفتاح قراية الصور ناقص في النسخة',
      'batteryOptimisation' => 'البطارية بتقفل التطبيق',
      'escalationRungsOff' => 'درجات السلّم +١٥ و+٣٠ مقفولة',
      'noMedications' => 'مفيش أدوية متسجّلة',
      _ => 'كود مش معروف: $code',
    };

String _staleSyncLabel(AdminDevice? device, DateTime? now) {
  final at = device?.lastSyncAt;
  if (at == null || now == null) return 'مزامنة واقفة — ولا مرة وصلت';
  return 'مزامنة واقفة ${timeSince(now, at)}';
}

/// كل الأكواد اللي اللوحة عارفة تترجمها — الاختبار بيقارنها بقايمة التطبيق.
const List<String> knownDeviceCodes = [
  'reminderHorizon',
  'remindersDropped',
  'notificationPermission',
  'pendingBandFull',
  'timezoneChanged',
  'noCaregiver',
  'pushToken',
  'staleSync',
  'exactAlarms',
  'aiKeyMissing',
  'batteryOptimisation',
  'escalationRungsOff',
  'noMedications',
  'accountMissing',
  'mediaSync',
  'lowCoverage',
  'patternSync',
];
