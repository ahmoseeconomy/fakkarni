/// إعداد اللوحة — **من `--dart-define` وبس**، زي `SupabaseAuthConfig` في
/// التطبيق، وبنفس أسامي المفاتيح عشان `--dart-define-from-file` بيشتغل على
/// نفس الملف.
///
/// مفيش مفتاح مكتوب في الكود، ومفيش مفتاح خدمة (اختبار بيقفل على ده).
class AdminConfig {
  const AdminConfig({required this.url, required this.key});

  static const missingMessage =
      'الإعداد ناقص. شغّل اللوحة بـ '
      '--dart-define=SUPABASE_URL=… و--dart-define=SUPABASE_ANON_KEY=… '
      '(أو --dart-define-from-file=../secrets.json).';

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');

  static AdminConfig? tryFromEnvironment() {
    if (_url.trim().isEmpty || _key.trim().isEmpty) return null;
    return AdminConfig(url: _url.trim(), key: _key.trim());
  }

  final String url;
  final String key;
}
