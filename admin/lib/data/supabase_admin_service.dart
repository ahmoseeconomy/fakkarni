import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_models.dart';
import 'admin_service.dart';

/// التنفيذ الحقيقي — **الملف الوحيد اللي بيستورد `supabase_flutter`** هنا،
/// نفس قاعدة `supabase_*` في التطبيق.
///
/// **مفيش مفتاح خدمة في اللوحة دي خالص** (`test/no_privileged_key_test.dart`
/// بيوقع حتى لو الاسم اتكتب في تعليق): دي عميل عادي بمفتاح النشر، والحاجز
/// كله في السيرفر — `private.is_admin()` جوّه كل دالة. ومفيش دخول مجهول:
/// `is_admin()` بترفضه حتى بإيميل معروف.
///
/// **ومفيش `dart:io` هنا** — `SocketException` مش بتتترجم على الويب، فحالة
/// «مفيش نت» بتتمسك من `AuthRetryableFetchException` ومن `ClientException`.
class SupabaseAdminService implements AdminService {
  SupabaseAdminService(this._supabase);

  final SupabaseClient _supabase;

  @override
  String? get currentEmail => _supabase.auth.currentUser?.email;

  @override
  Future<void> signIn({required String email, required String password}) => _guard(
        () async {
          await _supabase.auth
              .signInWithPassword(email: email.trim(), password: password);
        },
      );

  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // الخروج محلي في كل الأحوال — شبكة واقعة ما تمنعش حد إنه يقفل جلسته.
    }
  }

  @override
  Future<AdminCounts> counts() => _guard(() async {
        final rows = await _supabase.rpc<dynamic>('admin_counts');
        final list = _rows(rows);
        return list.isEmpty ? AdminCounts.empty : AdminCounts.fromRow(list.first);
      });

  @override
  Future<List<AdminAccount>> accounts() => _guard(() async {
        final rows = await _supabase.rpc<dynamic>('admin_accounts');
        return [for (final row in _rows(rows)) AdminAccount.fromRow(row)];
      });

  @override
  Future<List<AdminFollower>> followers(String patientUuid) => _guard(() async {
        final rows = await _supabase.rpc<dynamic>(
          'admin_patient_followers',
          params: {'p_patient_uuid': patientUuid},
        );
        return [for (final row in _rows(rows)) AdminFollower.fromRow(row)];
      });

  @override
  Future<List<AdminEscalation>> escalations(String patientUuid, {int limit = 20}) =>
      _guard(() async {
        final rows = await _supabase.rpc<dynamic>(
          'admin_patient_escalations',
          params: {'p_patient_uuid': patientUuid, 'p_limit': limit},
        );
        return [for (final row in _rows(rows)) AdminEscalation.fromRow(row)];
      });

  static List<Map<String, dynamic>> _rows(Object? result) =>
      result is List ? result.cast<Map<String, dynamic>>() : const [];

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AdminException {
      // اتصنّفت خلاص — حارس برّه ما يعيدش تصنيف اللي جوّه صنّفه.
      rethrow;
    } on PostgrestException catch (e) {
      // **`raise exception 'not admin'` بيوصل هنا كنص في `message`** —
      // نفس شكل `_mapPostgrest` في `supabase_care_circle_service.dart`.
      if (e.message.contains('not admin')) {
        throw AdminException(AdminFailure.notAdmin, e);
      }
      throw AdminException(AdminFailure.other, e);
    } on AuthApiException catch (e) {
      throw AdminException(AdminFailure.badCredentials, e);
    } on AuthRetryableFetchException catch (e) {
      throw AdminException(AdminFailure.offline, e);
    } on AuthException catch (e) {
      throw AdminException(AdminFailure.badCredentials, e);
    } catch (e) {
      // `ClientException` من http = الشبكة على الويب؛ مفيش `SocketException`.
      if (e.runtimeType.toString().contains('ClientException')) {
        throw AdminException(AdminFailure.offline, e);
      }
      throw AdminException(AdminFailure.other, e);
    }
  }
}
