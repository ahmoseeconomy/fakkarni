import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/care/follower_profile.dart';
import '../../domain/care/follower_role.dart';
import 'care_circle_service.dart';

/// التنفيذ الحقيقي فوق Supabase — الملف ده جوّه lib/data/ زي ما القاعدة
/// بتقول: مفيش استيراد للحزمة برّه data.
class SupabaseCareCircleService implements CareCircleService, CareCircleAdmin, RoleRedeem {
  SupabaseCareCircleService(this._supabase);

  final SupabaseClient _supabase;

  static const inviteLifetime = Duration(minutes: 15);

  @override
  Future<void> upsertPatient({required String uuid, required String name}) =>
      _guard(() async {
        final owner = _supabase.auth.currentUser?.id;
        if (owner == null) {
          throw const CareCircleException(CareCircleFailure.other, 'no session');
        }
        // on conflict (uuid) do update — uuid هو المفتاح الأساسي سحابياً،
        // فإعادة الرفع بتحدّث بدل ما تكرّر.
        await _supabase.from('patients').upsert({
          'uuid': uuid,
          'owner_id': owner,
          'name': name,
        });
      });

  @override
  Future<InviteCode> createInvite(String patientUuid) => _guard(() async {
        final code = await _supabase
            .rpc('create_invite', params: {'p_patient_uuid': patientUuid});
        return InviteCode(
          code: code as String,
          expiresAt: DateTime.now().add(inviteLifetime),
        );
      });

  @override
  Future<InviteCode> createRoleInvite(String patientUuid, FollowerRole role, {bool canEditMeds = false}) =>
      _guard(() async {
        final code = await _supabase.rpc('create_invite', params: {
          'p_patient_uuid': patientUuid,
          'p_role': role.name,
          'p_can_edit_meds': role == FollowerRole.nurse && canEditMeds,
        });
        return InviteCode(code: code as String, expiresAt: DateTime.now().add(inviteLifetime));
      });

  @override
  Future<List<FollowerWithPermissions>> followersWithPermissions(String patientUuid) => _guard(() async {
        final rows = await _supabase
            .rpc('followers_with_permissions', params: {'p_patient_uuid': patientUuid});
        return [
          for (final row in (rows as List).cast<Map<String, dynamic>>())
            FollowerWithPermissions(
              caregiverId: row['caregiver_id'] as String,
              profile: (row['display_name'] as String?)?.trim().isNotEmpty == true
                  ? FollowerProfile(
                      name: (row['display_name'] as String).trim(),
                      relation: FollowerRelation.fromStored(row['relation'] as String?),
                      relationOther: row['relation_other'] as String?,
                    )
                  : null,
              permissions: FollowerPermissions(
                role: FollowerRole.fromStored(row['role'] as String?),
                canConfirm: row['can_confirm'] == true,
                canEditMeds: row['can_edit_meds'] == true,
              ),
              linkedAt: row['linked_at'] is String ? DateTime.parse(row['linked_at'] as String).toLocal() : null,
            ),
        ];
      });

  @override
  Future<void> setFollowerPermissions(
    String patientUuid,
    String caregiverId,
    FollowerPermissions permissions,
  ) =>
      _guard(() async {
        await _supabase.rpc('set_follower_permissions', params: {
          'p_patient_uuid': patientUuid,
          'p_caregiver_id': caregiverId,
          'p_role': permissions.role.name,
          'p_can_confirm': permissions.canConfirm,
          'p_can_edit_meds': permissions.canEditMeds,
        });
      });

  @override
  Future<void> removeFollower(String patientUuid, String caregiverId) => _guard(() async {
        await _supabase.rpc('remove_follower', params: {
          'p_patient_uuid': patientUuid,
          'p_caregiver_id': caregiverId,
        });
      });

  @override
  Future<String> redeemInvite(String code) => _redeem({'p_code': code});

  @override
  Future<String> redeemInviteAt(String code, FollowerRole door) =>
      _redeem({'p_code': code, 'p_expect_role': door.name});

  Future<String> _redeem(Map<String, dynamic> params) => _guard(() async {
        final patientUuid = await _supabase.rpc('redeem_invite', params: params);
        // بعد الاستبدال بقى له حق القراءة — نجيب الاسم للشاشة
        final row = await _supabase
            .from('patients')
            .select('name')
            .eq('uuid', patientUuid as String)
            .single();
        return row['name'] as String;
      });

  /// ترجمة موحّدة: رموز الدالتين ← عربي محدد، والشبكة ← «مفيش نت».
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CareCircleException {
      rethrow;
    } on PostgrestException catch (e) {
      // الرسالة العربية بتخفي السبب — لازم يبان في الترمنال.
      debugPrint('Care: Postgrest ${e.code}: ${e.message} | ${e.details} | ${e.hint}');
      throw CareCircleException(_mapPostgrest(e), e);
    } on SocketException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on AuthRetryableFetchException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } catch (e, stack) {
      debugPrint('Care: فشل غير متوقع: $e\n$stack');
      throw CareCircleException(CareCircleFailure.other, e);
    }
  }

  static CareCircleFailure _mapPostgrest(PostgrestException e) {
    final message = e.message;
    if (message.contains('invalid_code')) {
      return CareCircleFailure.invalidOrExpiredCode;
    }
    if (message.contains('own_code')) return CareCircleFailure.ownCode;
    if (message.contains('already_linked')) return CareCircleFailure.alreadyLinked;
    // الرمز بيقول نوع **الكود** — الباب هو العكس
    if (message.contains('wrong_role_follower')) return CareCircleFailure.followerCodeAtNurseDoor;
    if (message.contains('wrong_role_nurse')) return CareCircleFailure.nurseCodeAtFollowerDoor;
    if (message.contains('circle_full')) return CareCircleFailure.circleFull;
    return CareCircleFailure.other;
  }
}
