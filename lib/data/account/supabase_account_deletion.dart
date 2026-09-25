import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import 'account_deletion.dart';

/// بتنده `delete-account` (Edge Function) بجلسة المستخدم نفسه.
///
/// **مفتاح الخدمة عمره ما بيوصل هنا** — هو في أسرار الدالة بس، والدالة
/// بتعرف المستخدم من جلسته.
class SupabaseAccountDeletion implements AccountDeletionRemote {
  SupabaseAccountDeletion(this._supabase, {this.timeout = const Duration(seconds: 45)});

  final SupabaseClient _supabase;
  final Duration timeout;

  @override
  Future<DeletionOutcome> deleteAccount() async {
    try {
      final res = await _supabase.functions
          .invoke('delete-account', body: {'confirm': deleteAccountConfirm})
          .timeout(timeout);
      final data = res.data;
      final status = data is Map ? data['status'] : null;
      return status == 'deleted' ? DeletionOutcome.deleted : DeletionOutcome.failed;
    } on SocketException catch (e) {
      diag('Account: مسح الحساب — مفيش نت ($e)');
      return DeletionOutcome.offline;
    } on ClientException catch (e) {
      diag('Account: مسح الحساب — مفيش نت ($e)');
      return DeletionOutcome.offline;
    } on TimeoutException catch (e) {
      // المهلة خلصت والطلب ممكن يكون لسه شغّال — «جرّب تاني» آمنة لأن الدالة
      // بتتعاد من غير ضرر، و«مفيش نت» كانت هتبقى كدب لو النت شغّال.
      diag('Account: مسح الحساب — المهلة خلصت ($e)');
      return DeletionOutcome.failed;
    } catch (e) {
      diag('Account: مسح الحساب وقع ($e)');
      return DeletionOutcome.failed;
    }
  }
}
