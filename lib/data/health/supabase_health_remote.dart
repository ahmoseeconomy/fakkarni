import 'package:supabase_flutter/supabase_flutter.dart';

import 'health_heartbeat.dart';

/// الـSDK في ملف واحد باسمه، زي `supabase_*` كلها — والتطبيق بيشوف
/// [HealthRemote] بس.
class SupabaseHealthRemote implements HealthRemote {
  const SupabaseHealthRemote(this._client);

  final SupabaseClient _client;

  /// 0037 لسه ما اتشغّلتش: `status` و`codes` و`user_id` مش موجودين → نفس
  /// الصف من غيرهم (زي `_optionalColumns` في الدفع).
  static const optionalColumns = {'status', 'codes', 'user_id'};

  @override
  Future<void> upsert(Map<String, dynamic> row) async {
    try {
      await _client.from('device_health').upsert(row, onConflict: 'patient_uuid,install_id');
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204' && e.code != '42703') rethrow;
      await _client.from('device_health').upsert(
        {for (final en in row.entries) if (!optionalColumns.contains(en.key)) en.key: en.value},
        onConflict: 'patient_uuid,install_id',
      );
    }
  }
}
