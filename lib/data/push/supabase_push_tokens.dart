import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_tokens.dart';

/// الناحية السحابية من التوكن. Supabase بيفضل هنا، زي
/// `supabase_sync_remote.dart` و`supabase_care_circle_service.dart`.
class SupabasePushTokenRemote implements PushTokenRemote {
  SupabasePushTokenRemote(this._client);

  final SupabaseClient _client;

  /// عن طريق الدالة، مش `upsert` مباشر.
  ///
  /// السبب في `0006_push.sql` بالتفصيل: نفس النسخة المتسطّبة ممكن يكون
  /// عليها صف بتوكن واحد باسم مستخدم مجهول قديم (الخروج المحلي بيولّد
  /// مستخدم جديد). upsert تحت RLS بيقع بـ42501 على صف مش بتاعك، وسياسة
  /// UPDATE واسعة كانت هتدي أي مستخدم حق يكتب على صف غيره.
  @override
  Future<void> claim(String token, PushPlatform platform) async {
    await _client.rpc<void>(
      'claim_device_token',
      params: {'p_token': token, 'p_platform': platform.name},
    );
  }

  /// المسح عادي تحت RLS: سياسة الحذف بتسمح لصاحب الصف وبس، والمستخدم
  /// لسه داخل وقت النداء ده (القاعدة في [PushTokens.clear]).
  @override
  Future<void> remove(String token) async {
    await _client.from('device_tokens').delete().eq('token', token);
  }
}
