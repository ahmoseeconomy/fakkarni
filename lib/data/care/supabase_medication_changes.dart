import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/care/medication_change.dart';
import 'care_circle_service.dart';
import 'medication_changes.dart';

class SupabaseMedicationChangeRemote implements MedicationChangeRemote {
  SupabaseMedicationChangeRemote(this._supabase);

  final SupabaseClient _supabase;

  static const _columns =
      'uuid, kind, medication_uuid, medication_name, payload, actor_name, created_at, applied_at, outcome, reverted_at';

  @override
  Future<void> submit({
    required String patientUuid,
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? uuid,
    String? medicationUuid,
    String? medicationName,
    String? actorName,
  }) =>
      _guard(() async {
        final me = _supabase.auth.currentUser?.id;
        if (me == null) throw const CareCircleException(CareCircleFailure.other, 'no session');
        try {
          await _supabase.from('medication_changes').insert({
            'uuid': ?uuid,
            'patient_uuid': patientUuid,
            'actor_id': me,
            'actor_name': actorName,
            'kind': kind.stored,
            'medication_uuid': medicationUuid,
            'medication_name': medicationName,
            'payload': payload.toJson(),
          });
        } on PostgrestException catch (e) {
          // نفس الـuuid اتكتب قبل كده (الطابور بيعيد بعد نت وقع في النص):
          // ده نجاح، مش عطل — المفتاح الأساسي هو اللي بيمنع التكرار.
          if (e.code != '23505') rethrow;
        }
      });

  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) => pendingFor(patientUuid);

  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) => _guard(() async {
        final rows = await _supabase
            .from('medication_changes')
            .select(_columns)
            .eq('patient_uuid', patientUuid)
            .isFilter('applied_at', null)
            .order('created_at');
        return _parse(rows);
      });

  @override
  Future<List<MedicationChange>> history(String patientUuid, {int limit = 50}) => _guard(() async {
        final rows = await _supabase
            .from('medication_changes')
            .select(_columns)
            .eq('patient_uuid', patientUuid)
            .order('created_at', ascending: false)
            .limit(limit);
        return _parse(rows);
      });

  List<MedicationChange> _parse(List<Map<String, dynamic>> rows) => [
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
              appliedAt: row['applied_at'] is String ? DateTime.parse(row['applied_at'] as String).toLocal() : null,
              outcome: ChangeOutcome.values.asNameMap()[row['outcome'] as String?],
            ),
      ];

  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) => _guard(() async {
        await _supabase.from('medication_changes').update({
          'applied_at': DateTime.now().toUtc().toIso8601String(),
          'outcome': outcome.name,
        }).eq('uuid', changeUuid);
      });

  @override
  Future<void> markReverted(String changeUuid) => _guard(() async {
        final now = DateTime.now().toUtc().toIso8601String();
        try {
          await _supabase
              .from('medication_changes')
              .update({'outcome': 'reverted', 'reverted_at': now}).eq('uuid', changeUuid);
        } on PostgrestException catch (e) {
          // قبل 0035: مفيش 'reverted' ولا `reverted_at` — الرجوع حصل على
          // الموبايل، والصف بيفضل «اتطبّق». الهجرة هي اللي بتكمّل الصورة.
          if (e.code != '23514' && e.code != 'PGRST204' && e.code != '42703') rethrow;
        }
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
