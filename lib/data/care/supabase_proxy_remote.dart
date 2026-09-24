import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'care_circle_service.dart';
import 'proxy_confirmations.dart';

/// `proxy_confirmations` على Supabase — الإدخال تحت RLS بتاعة ٠٠٢٣
/// (الممرض المسموح له، على حدث مستحق لمريضه، وباسمه هو).
class SupabaseProxyRemote implements ProxyConfirmRemote {
  SupabaseProxyRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<void> confirmOnBehalf({
    required String patientUuid,
    required String doseEventUuid,
    required String? actorName,
  }) =>
      _guard(() async {
        final me = _supabase.auth.currentUser?.id;
        if (me == null) {
          throw const CareCircleException(CareCircleFailure.other, 'no session');
        }
        await _supabase.from('proxy_confirmations').insert({
          'dose_event_uuid': doseEventUuid,
          'patient_uuid': patientUuid,
          'actor_id': me,
          'actor_name': actorName,
        });
      });

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) =>
      _guard(() async {
        final rows = await _supabase
            .from('proxy_confirmations')
            .select('dose_event_uuid, actor_name, confirmed_at')
            .eq('patient_uuid', patientUuid)
            .gte('confirmed_at', since.toUtc().toIso8601String())
            .order('confirmed_at');
        return [
          for (final row in rows)
            ProxyConfirmation(
              doseEventUuid: row['dose_event_uuid'] as String,
              actorName: row['actor_name'] as String?,
              confirmedAt: DateTime.parse(row['confirmed_at'] as String).toLocal(),
            ),
        ];
      });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CareCircleException {
      rethrow;
    } on PostgrestException catch (e) {
      throw CareCircleException(CareCircleFailure.other, e);
    } on SocketException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on AuthRetryableFetchException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } catch (e) {
      throw CareCircleException(CareCircleFailure.other, e);
    }
  }
}
