/// الجلسة صالحة؟ — وتجديدها لو انتهت (الفحص الآلي، ٢٨ سبتمبر ٢٠٢٦).
///
/// واجهة لوحدها بدل ما تتضاف لـ[AuthService]: كل مزيّفات الاختبار بتعمل
/// `implements AuthService`، وسطر جديد هناك كان هيكسر عشرين ملف عشان
/// فحص مجاملة. الـSDK في `supabase_session_health.dart` وبس.
library;

abstract interface class SessionHealth {
  /// null = مفيش جلسة أصلاً (تنزيلة من غير ربط — مش عطل).
  /// true = فيه جلسة وصالحة، false = فيه جلسة ومنتهية.
  Future<bool?> isValid();

  /// بيجدّد الجلسة المنتهية. true = اتجدّدت. **عمره ما يرمي.**
  Future<bool> refresh();
}
