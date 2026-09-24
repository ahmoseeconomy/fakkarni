import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_service.dart';

/// السلك الحقيقي — upsert on conflict (uuid) do update.
///
/// owner_id بيتحقن هنا لصفوف patients: السيرفر بيطلبه وRLS بترفض غيره،
/// والخدمة نفسها ما تعرفش حاجة عن الجلسات.
class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final owner = _supabase.auth.currentUser?.id;
    final payload = table == 'patients'
        ? [
            for (final row in rows) {...row, 'owner_id': owner},
          ]
        : rows;
    await _guard(() => _supabase.from(table).upsert(payload, onConflict: 'uuid'));
  }

  /// رفض السيرفر بيتحوّل لـ[SyncRejected] بكوده، وسقوط الشبكة لـ[SyncOffline]
  /// — عشان `SyncService` تصنّف من غير ما تستورد الـSDK.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on PostgrestException catch (e) {
      throw SyncRejected(e.code ?? '', e.message);
    } on SocketException catch (e) {
      throw SyncOffline(e);
    } on TimeoutException catch (e) {
      throw SyncOffline(e);
    } on ClientException catch (e) {
      throw SyncOffline(e);
    }
  }

  @override
  Future<void> deleteByUuid(String table, List<String> uuids) async {
    if (uuids.isEmpty) return;
    // RLS بترفض مسح صف مش بتاع المالك (`records_delete` في 0012)، فمفيش
    // حاجة هنا بتفلتر بالمريض — الحيطة في السيرفر زي كل حاجة تانية.
    await _guard(() => _supabase.from(table).delete().inFilter('uuid', uuids));
  }
}
