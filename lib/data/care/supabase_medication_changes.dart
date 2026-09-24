import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/care/medication_change.dart';
import 'care_circle_service.dart';
import 'medication_changes.dart';

class SupabaseMedicationChangeRemote implements MedicationChangeRemote {
  SupabaseMedicationChangeRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<void> submit({
    required String patientUuid,
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? medicationUuid,
    String? medicationName,
    String? actorName,
  }) =>
      _guard(() async {
        final me = _supabase.auth.currentUser?.id;
        if (me == null) throw const CareCircleException(CareCircleFailure.other, 'no session');
        await _supabase.from('medication_changes').insert({
          'patient_uuid': patientUuid,
          'actor_id': me,
          'actor_name': actorName,
          'kind': kind.name,
          'medication_uuid': medicationUuid,
          'medication_name': medicationName,
          'payload': payload.toJson(),
        });
      });

  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) => pendingFor(patientUuid);

  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) => _guard(() async {
        final rows = await _supabase
            .from('medication_changes')
            .select('uuid, kind, medication_uuid, medication_name, payload, actor_name, created_at')
            .eq('patient_uuid', patientUuid)
            .isFilter('applied_at', null)
            .order('created_at');
        return [
          for (final row in rows)
            if (MedicationChangeKind.fromStored(row['kind'] as String?) case final kind?)
              MedicationChange(
                uuid: row['uuid'] as String,
                kind: kind,
                medicationUuid: row['medication_uuid'] as String?,
                medicationName: row['medication_name'] as String?,
                payload: MedicationChangePayload.fromJson((row['payload'] as Map?)?.cast<String, dynamic>() ?? const {}),
                actorName: row['actor_name'] as String?,
                createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
              ),
        ];
      });

  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) => _guard(() async {
        await _supabase.from('medication_changes').update({
          'applied_at': DateTime.now().toUtc().toIso8601String(),
          'outcome': outcome.name,
        }).eq('uuid', changeUuid);
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
