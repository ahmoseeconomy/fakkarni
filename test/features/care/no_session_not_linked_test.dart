import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart';

/// **مفيش جلسة = مفيش ربط، مش «حصل خطأ».**
///
/// كان الاستعلام بيبعت `caregiver_id=eq.` (من `?? ''`)، وPostgres بيرفض
/// `''` كـuuid — فالرمية بتترجم لـ«مقدرناش نكمّل. جرّب تاني.»، وبتقع قبل
/// أي استعلام تاني فالملف الصحي يفضل فاضي كمان. جهاز اتمسح أو توكن انتهى
/// حالة عادية، والرد الصح عليها إن مفيش ربط.
///
/// الاختبار بيشاور على **مضيف مش موجود**: لو حصل أي نداء شبكة هيطلع
/// `CareCircleException` (offline) بدل null — يعني «رجّع null بسرعة» هنا
/// معناها **ولا نداء اتعمل أصلاً**، مش إن النداء رجع فاضي.
/// جلسة صالحة **محلياً** — `recoverSession` بتحفظها من غير أي شبكة لو
/// مش منتهية. بيها بنعدّي شرط الجلسة ونوصل لنداء الشبكة اللي بيقع.
String sessionJson(String userId) => jsonEncode({
      'access_token': 'ليس-توكن-حقيقي',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'ليس-توكن-حقيقي',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-20T00:00:00.000Z',
      },
    });

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://no-such-host.invalid',
      'not-a-real-anon-key',
      // من غير كده بيفضل فيه مؤقت realtime شغّال بعد الاختبار
      realtimeClientOptions: const RealtimeClientOptions(timeout: Duration(milliseconds: 1)),
    );
  });
  tearDown(() async => client.dispose());

  test('مفيش مستخدم مسجّل → linkedPatient بترجع null من غير ولا نداء', () async {
    expect(client.auth.currentUser, isNull, reason: 'الشرط المبدئي: مفيش جلسة');
    expect(await SupabaseCaregiverRemote(client).linkedPatient(), isNull);
  });

  test('ومفيش جلسة → snapshot بترجع null كمان (الشاشة بترجع لشاشة البداية)', () async {
    expect(await SupabaseCaregiverRemote(client).snapshot(), isNull);
  });

  test('عطل شبكة جوّه linkedPatient بيوصل «مش متصل» — مش «حصل خطأ»', () async {
    // اللفّة البرّانية بتاعة `snapshot` كانت بتعيد تصنيف اللي الجوّانية
    // رمته، فالأوفلاين كان بيتحوّل لـ`other`. ودي الحالة الشايعة لأن
    // `linkedPatient` أول حاجة بتتنفّذ.
    await client.auth.recoverSession(sessionJson('87d0e572-7985-4ef5-a2a4-70f2ceb861f2'));
    expect(client.auth.currentUser, isNotNull, reason: 'الشرط المبدئي: فيه جلسة');

    await expectLater(
      SupabaseCaregiverRemote(client).snapshot(),
      throwsA(isA<CareCircleException>()
          .having((e) => e.failure, 'failure', CareCircleFailure.offline)),
    );
  });

  test('ولا سطر في الملف بيبعت uuid فاضي', () {
    // حارس على الشكل نفسه: `?? ''` على id مستخدم بيوصل فلتر uuid فاضي
    // للسيرفر. الاتنين اللي فاضلين في الملف تعليقين بيحكوا القصة.
    final source = File('lib/data/care/supabase_caregiver_remote.dart').readAsLinesSync();
    final offenders = [
      for (final raw in source)
        if (!raw.trimLeft().startsWith('//') && raw.contains("currentUser?.id ?? ''")) raw.trim(),
    ];
    expect(offenders, isEmpty);
  });
}
