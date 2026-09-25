// «امسح حسابي» على الجهاز قال «مقدرناش نكمّل المسح» — والسؤال الأول كان:
// الطلب بيطلع من الموبايل أصلاً؟ الاختبار ده بيمسك الطلب نفسه: نفس الاسم،
// نفس الجسم، ونفس جلسة المستخدم — وبيقرا اللي بيتكتب في سجل التشخيص.
import 'dart:convert';

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fakkarni/data/account/account_deletion.dart';
import 'package:fakkarni/data/account/supabase_account_deletion.dart';

import '../../features/care/no_session_not_linked_test.dart' show sessionJson;

void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late SupabaseClient client;
  late List<String> log;
  late DebugPrintCallback originalPrint;

  setUp(() {
    sent = [];
    reply = (_) => http.Response(jsonEncode({'status': 'deleted', 'kind': 'patient'}), 200,
        headers: {'content-type': 'application/json'});
    client = SupabaseClient(
      'https://project.invalid',
      'anon-key',
      httpClient: MockClient((req) async {
        sent.add(req);
        return reply(req);
      }),
      realtimeClientOptions: const RealtimeClientOptions(timeout: Duration(milliseconds: 1)),
    );
    log = [];
    originalPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) log.add(m);
    };
  });
  tearDown(() async {
    debugPrint = originalPrint;
    await client.dispose();
  });

  Future<void> signIn() => client.auth.recoverSession(sessionJson('87d0e572-7985-4ef5-a2a4-70f2ceb861f2'));

  test('بينده functions.invoke(delete-account) بالجسم المتفق عليه وبجلسة المستخدم', () async {
    await signIn();
    final outcome = await SupabaseAccountDeletion(client).deleteAccount();
    expect(outcome, DeletionOutcome.deleted);

    final req = sent.singleWhere((r) => r.url.path.contains('/functions/v1/'));
    expect(req.method, 'POST');
    expect(req.url.toString(), 'https://project.invalid/functions/v1/delete-account');
    expect(jsonDecode(req.body), {'confirm': deleteAccountConfirm});
    expect(req.headers['Authorization'], 'Bearer ليس-توكن-حقيقي', reason: 'جلسة المستخدم، مش مفتاح النشر');
    expect(req.headers['apikey'], 'anon-key');
  });

  test('الدالة المنشورة قالب «Hello»: failed، والسبب الحقيقي في السجل مش على الشاشة', () async {
    await signIn();
    reply = (_) => http.Response(jsonEncode({'message': 'Hello undefined!'}), 200,
        headers: {'content-type': 'application/json'});
    expect(await SupabaseAccountDeletion(client).deleteAccount(), DeletionOutcome.failed);
    expect(log.any((l) => l.contains('HTTP 200') && l.contains('Hello undefined!')), isTrue);
  });

  test('401 من البوابة: failed وبالكود في السجل — والطلب اتبعت فعلاً', () async {
    await signIn();
    reply = (_) => http.Response(jsonEncode({'code': 401, 'message': 'Invalid JWT'}), 401,
        headers: {'content-type': 'application/json'});
    expect(await SupabaseAccountDeletion(client).deleteAccount(), DeletionOutcome.failed);
    expect(sent.where((r) => r.url.path.endsWith('/delete-account')), hasLength(1));
    expect(log.any((l) => l.contains('HTTP 401')), isTrue);
  });

  test('من غير جلسة: ما بيبعتش، وبيقول كده في السجل', () async {
    expect(await SupabaseAccountDeletion(client).deleteAccount(), DeletionOutcome.failed);
    expect(sent, isEmpty);
    expect(log.any((l) => l.contains('مفيش جلسة')), isTrue);
  });

  test('عطل شبكة = offline (ولا حاجة اتمسحت)', () async {
    await signIn();
    reply = (_) => throw http.ClientException('Connection refused');
    expect(await SupabaseAccountDeletion(client).deleteAccount(), DeletionOutcome.offline);
  });
}
