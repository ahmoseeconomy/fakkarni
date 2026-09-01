import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../care/care_circle_service.dart';
import '../care/supabase_care_circle_service.dart';
import '../sync/supabase_sync_remote.dart';
import '../sync/sync_service.dart';
import 'anonymous_auth_service.dart';
import 'auth_service.dart';

/// إعداد Supabase وGoogle — من `--dart-define` وبس، زي مفتاح Gemini بالظبط.
///
/// ناقص؟ التطبيق بيفتح عادي وبيشتغل كله؛ شاشة الربط بس هي اللي بتقول
/// إيه الناقص. ومفيش أي مفتاح في ملف git بيتابعه.
class SupabaseAuthConfig {
  const SupabaseAuthConfig({
    required this.url,
    required this.key,
    this.googleServerClientId,
    this.googleIosClientId,
  });

  static const missingConfigMessage =
      'إعداد الربط مش موجود. شغّل التطبيق بـ '
      '--dart-define=SUPABASE_URL=… و--dart-define=SUPABASE_ANON_KEY=… '
      '(أو --dart-define-from-file=secrets.json والملف ده برّه git).';

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  final String url;
  final String key;
  final String? googleServerClientId;
  final String? googleIosClientId;

  static SupabaseAuthConfig? tryFromEnvironment() {
    if (_url.trim().isEmpty || _key.trim().isEmpty) return null;
    return SupabaseAuthConfig(
      url: _url.trim(),
      key: _key.trim(),
      googleServerClientId:
          _serverClientId.trim().isEmpty ? null : _serverClientId.trim(),
      googleIosClientId: _iosClientId.trim().isEmpty ? null : _iosClientId.trim(),
    );
  }
}

/// خدمات السحابة مع بعض — الهوية ودائرة الرعاية فوق نفس العميل.
typedef CloudServices = ({
  AuthService auth,
  CareCircleService care,
  SyncRemote syncRemote,
});

/// بيجهّز Supabase ويرجّع خدمات السحابة — أو null لو الإعداد ناقص.
///
/// **عمره ما بيرمي وعمره ما بيعطّل الفتح**: التهيئة محلية (بتقرا الجلسة
/// المحفوظة)، وتجديد التوكن بيحصل في الخلفية لوحده. لو حاجة فشلت —
/// أوفلاين أو غيره — بنسجّل ونرجّع null، والتطبيق يكمّل زي ما هو.
Future<CloudServices?> initSupabaseAuth() async {
  final config = SupabaseAuthConfig.tryFromEnvironment();
  if (config == null) {
    debugPrint(SupabaseAuthConfig.missingConfigMessage);
    return null;
  }

  try {
    final supabase = await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
    );
    // مجهول مؤقتاً — GoogleAuthService جاهز كشقيق ويتركّب هنا لما يرجع
    // للخطة (config.googleServerClientId مستني له).
    return (
      auth: AnonymousAuthService(supabase.client),
      care: SupabaseCareCircleService(supabase.client),
      syncRemote: SupabaseSyncRemote(supabase.client),
    );
  } catch (error, stack) {
    // جلسة منتهية أو تخزين بايظ أو أي حاجة — مش هنوقّع تطبيق تذكير دوا
    // عشان الهوية الاختيارية اتعبت.
    debugPrint('Auth: Supabase init فشلت: $error\n$stack');
    return null;
  }
}
