import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'care_circle_service.dart';

/// التنفيذ الحقيقي فوق Supabase — الملف ده جوّه lib/data/ زي ما القاعدة
/// بتقول: مفيش استيراد للحزمة برّه data.
class SupabaseCareCircleService implements CareCircleService {
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
  Future<String> redeemInvite(String code) => _guard(() async {
        final patientUuid =
            await _supabase.rpc('redeem_invite', params: {'p_code': code});
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
    return CareCircleFailure.other;
  }
}
