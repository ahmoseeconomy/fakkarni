import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ai/ai_session.dart';

/// جلسة Supabase كما القارئ محتاجها (C2) — ملف `supabase_*` زي باقي الواجهات.
class SupabaseAiSession implements AiSession {
  SupabaseAiSession(this._client, {required String url, required this.publishableKey})
      : endpoint = Uri.parse('${url.replaceFirst(RegExp(r'/+$'), '')}/functions/v1/ai-read');

  final SupabaseClient _client;

  @override
  final Uri endpoint;

  @override
  final String publishableKey;

  /// التوكن المنتهي بيتجدّد قبل ما يتبعت — دالة السحابة هترفضه ٤٠١ والمريض
  /// هيشوف «سجّل دخول» وهو أصلاً مسجّل. فشل التجديد = مفيش جلسة.
  @override
  Future<String?> accessToken() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    if (!session.isExpired) return session.accessToken;
    try {
      final refreshed = await _client.auth.refreshSession();
      return refreshed.session?.accessToken;
    } catch (error) {
      debugPrint('Auth: تجديد التوكن قبل قراية الصورة فشل: $error');
      return null;
    }
  }
}
