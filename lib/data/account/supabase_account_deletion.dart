import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import 'account_deletion.dart';

/// بتنده `delete-account` (Edge Function) بجلسة المستخدم نفسه.
///
/// **مفتاح الخدمة عمره ما بيوصل هنا** — هو في أسرار الدالة بس، والدالة
/// بتعرف المستخدم من جلسته (الـSDK بيحط `Authorization: Bearer <الجلسة>`
/// على كل نداء دالة).
///
/// **السبب الحقيقي بيتكتب في سجل التشخيص، والمريض بيشوف جملة واحدة.**
/// ٢٦ سبتمبر ٢٠٢٦: «مقدرناش نكمّل المسح» على الجهاز، والسبب طلع من نداء
/// مباشر على المشروع الحقيقي: الدالة المنشورة ردّت `200 {"message":"Hello
/// undefined!"}` — قالب سوپابيز، مش الكود بتاعنا. من غير السطر اللي بيكتب
/// حالة الرد وجسمه، ده كان بيبان زي عطل شبكة.
class SupabaseAccountDeletion implements AccountDeletionRemote {
  SupabaseAccountDeletion(this._supabase, {this.timeout = const Duration(seconds: 45)});

  final SupabaseClient _supabase;
  final Duration timeout;

  static const functionName = 'delete-account';

  @override
  Future<DeletionOutcome> deleteAccount() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      // من غير جلسة الدالة هترفض (401) قبل ما تعرف مين — ما نبعتش أصلاً
      diag('Account: مسح الحساب — مفيش جلسة على الموبايل ده');
      return DeletionOutcome.failed;
    }
    try {
      final res = await _supabase.functions
          .invoke(functionName, body: {'confirm': deleteAccountConfirm})
          .timeout(timeout);
      final data = res.data;
      final status = data is Map ? data['status'] : null;
      if (status == 'deleted') return DeletionOutcome.deleted;
      // رد من غير `status: deleted` = الدالة اللي هناك مش بتاعتنا، أو وقعت
      // في خطوة (`failed` + `step`) — الجسم كله للسجل، مش للشاشة
      diag('Account: delete-account ردّت HTTP ${res.status} بجسم مش متوقّع: $data');
      return DeletionOutcome.failed;
    } on FunctionException catch (e) {
      // الـSDK بيلفّ عطل الشبكة نفسه في FunctionException بحالة ٠ — ده
      // «مفيش نت»، مش رفض من السيرفر (ولا حاجة اتبعتت)
      if (e.status == 0) {
        diag('Account: مسح الحساب — مفيش نت (${e.details})');
        return DeletionOutcome.offline;
      }
      // 401/403 = البوابة أو الدالة رفضت الجلسة؛ 404 = مفيش دالة بالاسم ده؛
      // 5xx = وقعت هناك
      diag('Account: delete-account رفضت — HTTP ${e.status} ${e.reasonPhrase ?? ''}: ${e.details}');
      return DeletionOutcome.failed;
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
    } catch (e, stack) {
      diag('Account: مسح الحساب وقع (${e.runtimeType}: $e)\n$stack');
      return DeletionOutcome.failed;
    }
  }
}
