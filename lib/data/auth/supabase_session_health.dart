import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import 'session_health.dart';

/// الجلسة من gotrue: `isExpired` على الجلسة الحالية، والتجديد بـ`refreshSession`.
/// الـSDK في الملف ده وبس (قاعدة `supabase_*`).
class SupabaseSessionHealth implements SessionHealth {
  const SupabaseSessionHealth(this._client);

  final SupabaseClient _client;

  @override
  Future<bool?> isValid() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    return !session.isExpired;
  }

  @override
  Future<bool> refresh() async {
    try {
      final res = await _client.auth.refreshSession();
      return res.session != null && !res.session!.isExpired;
    } catch (e) {
      // أوفلاين أو توكن تجديد ميت — الفحص الجاي بيقول، ومفيش خروج من هنا
      diag('Health: تجديد الجلسة وقع (${e.runtimeType})');
      return false;
    }
  }
}
