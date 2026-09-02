import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../care/care_circle_service.dart';
import '../care/caregiver_remote.dart';
import '../care/supabase_care_circle_service.dart';
import '../care/supabase_caregiver_remote.dart';
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

/// اتهيّأت من `main` في الـisolate ده؟
///
/// `Supabase.initialize` singleton **لكل isolate**، فالعلامة دي في الـisolate
/// بتاع الخلفية بتفضل false على طول (ذاكرته لوحده) وبتبقى true في isolate
/// التطبيق. بنستخدمها عشان لو مسار الخلفية اتنده في isolate التطبيق —
/// بيحصل على iOS في حالات — ما نقفلش تجديد التوكن على عميل شغّال.
bool _initialisedByApp = false;

/// السحابة زي ما الـisolate محتاجها: سلك الرفع بس، ومفتاح إقفال.
typedef IsolateCloud = ({
  SyncRemote syncRemote,
  bool Function() hasSession,
  Future<void> Function() shutdown,
});

/// تهيئة Supabase جوّه isolate الخلفية — بتقرا الجلسة المحفوظة، من غير شبكة.
///
/// الـisolate بتاع زرار الإشعار ذاكرته لوحده، فلازم تهيئة جديدة فيه. اتنين
/// مهمين، الاتنين متحققين من مصدر الحزم المتسطّبة (supabase_flutter 2.17.2،
/// gotrue 2.27.2):
///
/// * `detectSessionInUri: false` — مراقب الروابط العميقة (app_links) مالوش
///   أي لازمة في صحوة خلفية.
/// * `autoRefreshToken` بيفضل `true` (الافتراضي) وبنقفله بإيدنا في
///   [IsolateCloud.shutdown]. **مغريّة وغلط** إننا نبعته `false`: ساعتها
///   لو التوكن منتهي، `recoverSession` بتنده `_signOut` محلي — يعني
///   الـisolate بيطلّع المريض من حسابه في التطبيق كله وهو بيسجّل جرعة.
///
/// الجلسة بتترجع من التخزين المحلي جوّه `Supabase.initialize` نفسها (بتستنى
/// `setInitialSession`)، فبعد الـawait `currentUser` جاهز من غير أي نداء
/// شبكة. والتوكن المنتهي بيتجدد لوحده عند أول نداء، لأن كل نداء بياخد
/// توكنه من `getSession()` اللي بتجدد قبل ما تبعت.
///
/// **بمهلة، لأن دي بتحصل قبل الكتابة المحلية.** التهيئة محلية (قناة
/// SharedPreferences) ومفروض تخلص في لحظة، بس «مفروض» مش ضمان: قناة
/// بتتعلّق هنا كانت هتأخّر تسجيل الجرعة وإلغاء التصعيد — وهما الوعد
/// للمريض. المهلة بتحوّل التعليقة دي لصحوة أوفلاين، والصفوف بتفضل
/// متوسّخة لدفعة المقدمة الجاية.
const Duration isolateCloudInitTimeout = Duration(seconds: 2);

Future<IsolateCloud?> initSupabaseForIsolate() async {
  final config = SupabaseAuthConfig.tryFromEnvironment();
  if (config == null) return null;

  try {
    final supabase = await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    ).timeout(isolateCloudInitTimeout);
    return (
      syncRemote: SupabaseSyncRemote(supabase.client),
      hasSession: () => supabase.client.auth.currentUser != null,
      // المؤقّت الدوري بتاع تجديد التوكن بيبدأ مع مُنشئ GoTrueClient؛
      // بنوقّفه عشان ما يفضلش شغّال في isolate إحنا خلصنا منه — إلا لو
      // العميل ده بتاع التطبيق أصلاً، ساعتها إحنا ضيوف عليه.
      shutdown: _initialisedByApp
          ? () async {}
          : () async => supabase.client.auth.stopAutoRefresh(),
    );
  } catch (error, stack) {
    // نفس سياسة الفتح: السحابة اختيارية، والجرعة لأ.
    debugPrint('Sync: تهيئة Supabase في الخلفية فشلت: $error\n$stack');
    return null;
  }
}

/// خدمات السحابة مع بعض — الهوية ودائرة الرعاية فوق نفس العميل.
typedef CloudServices = ({
  AuthService auth,
  CareCircleService care,
  CaregiverRemote caregiver,
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
    _initialisedByApp = true;
    // مجهول مؤقتاً — GoogleAuthService جاهز كشقيق ويتركّب هنا لما يرجع
    // للخطة (config.googleServerClientId مستني له).
    return (
      auth: AnonymousAuthService(supabase.client),
      care: SupabaseCareCircleService(supabase.client),
      caregiver: SupabaseCaregiverRemote(supabase.client),
      syncRemote: SupabaseSyncRemote(supabase.client),
    );
  } catch (error, stack) {
    // جلسة منتهية أو تخزين بايظ أو أي حاجة — مش هنوقّع تطبيق تذكير دوا
    // عشان الهوية الاختيارية اتعبت.
    debugPrint('Auth: Supabase init فشلت: $error\n$stack');
    return null;
  }
}
