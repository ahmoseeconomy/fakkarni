import 'package:supabase_flutter/supabase_flutter.dart';

import 'health_heartbeat.dart';

/// الـSDK في ملف واحد باسمه، زي `supabase_*` كلها — والتطبيق بيشوف
/// [HealthRemote] بس.
class SupabaseHealthRemote implements HealthRemote {
  const SupabaseHealthRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert(Map<String, dynamic> row) =>
      _client.from('device_health').upsert(row, onConflict: 'patient_uuid,install_id');
}
