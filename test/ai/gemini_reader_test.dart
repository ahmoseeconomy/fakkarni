import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintThrottled;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/prescription_reader.dart';

import '../support/fake_ai_session.dart';

final image = Uint8List.fromList(List<int>.generate(64, (i) => i));

/// رد Gemini اللي بيشيل جوّاه الـJSON بتاعنا كنص — والدالة بترجّعه زي ما هو.
String geminiBody(Map<String, dynamic> json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
        },
      ],
    });

final okBody = geminiBody({
  'medications': [
    {
      'name': {'value': 'Concor 5mg', 'confidence': 0.95},
      'amount': {'value': 'قرص', 'confidence': 0.9},
      'timing': {'anchor': 'breakfast', 'relation': 'after', 'confidence': 0.9},
      'durationDays': {'value': null, 'confidence': 1},
    },
  ],
});

http.Response ok({Map<String, String> headers = const {}}) => http.Response.bytes(
      utf8.encode(okBody),
      200,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );

/// C2: القارئ بينادي دالتنا `ai-read` بجلسة المستخدم — **من غير أي مفتاح**.
/// كل الطلبات هنا على `MockClient`؛ مفيش اختبار بيلمس الدالة الحقيقية.
void main() {
  group('الطلب: جلسة، مش مفتاح', () {
    test('بيروح لدالتنا بتوكن الجلسة والمفتاح المنشور — ومفيش مفتاح Gemini في أي مكان', () async {
      http.Request? sent;
      final session = FakeAiSession();
      final reader = GeminiPrescriptionReader(session, client: MockClient((request) async {
        sent = request;
        return ok();
      }));

      final reading = await reader.read(image);

      expect(sent!.method, 'POST');
      expect(sent!.url, session.endpoint);
      expect(sent!.url.host, isNot(contains('googleapis')));
      expect(sent!.headers['Authorization'], 'Bearer user-access-token');
      expect(sent!.headers['apikey'], 'sb_publishable_test');
      expect(sent!.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-goog-api-key')));
      expect(sent!.url.queryParameters, isEmpty, reason: 'ولا حاجة في الرابط');

      expect(reading.lines.single.name.value, 'Concor 5mg', reason: 'الرد بيتفك زي قبل C2 بالظبط');
    });

    test('الجسم: kind وصورة ونوع ملف **وبس** — العميل ما بيبعتش برومبت ولا schema ولا موديل', () async {
      late Map<String, dynamic> body;
      final reader = GeminiPrescriptionReader(FakeAiSession(), client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return ok();
      }));

      await reader.read(image, mimeType: 'image/png');

      expect(body.keys.toSet(), {'kind', 'mime', 'image'});
      expect(body['kind'], 'prescription');
      expect(body['mime'], 'image/png');
      expect(body['image'], base64Encode(image));
    });

    test('مفيش جلسة → ولا طلب بيطلع، والاستثناء بيقول «سجّل دخول»', () async {
      var requests = 0;
      final reader = GeminiPrescriptionReader(FakeAiSession(token: null), client: MockClient((_) async {
        requests++;
        return ok();
      }));

      await expectLater(
        () => reader.read(image),
        throwsA(
          isA<PrescriptionReadException>()
              .having((e) => e.needsSignIn, 'needsSignIn', isTrue)
              .having((e) => e.message, 'message', 'سجّل دخول عشان نقرا الروشتة'),
        ),
      );
      expect(requests, 0, reason: 'الصورة ما بتطلعش من الموبايل من غير جلسة');
    });
  });

  group('الردود → حالات الشاشة', () {
    Future<PrescriptionReadException> failureFor(http.Response response) async {
      final reader = GeminiPrescriptionReader(FakeAiSession(), client: MockClient((_) async => response));
      try {
        await reader.read(image);
      } on PrescriptionReadException catch (e) {
        return e;
      }
      fail('المفروض يرمي');
    }

    http.Response jsonResponse(Object body, int status) => http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    test('٤٢٩ → جملة السحابة زي ما هي على الشاشة', () async {
      final e = await failureFor(
        jsonResponse({'error': 'daily_cap', 'message': 'وصلت لحد القراءات النهارده — جرّب بكرة'}, 429),
      );
      expect(e.message, 'وصلت لحد القراءات النهارده — جرّب بكرة');
      expect(e.needsSignIn, isFalse);
      expect(e.cause.toString(), contains('429'));
    });

    test('٤٢٩ من غير جملة مفهومة → الفشل العادي، مش نص خام', () async {
      final e = await failureFor(http.Response('quota', 429));
      expect(e.message, contains('صوّر تاني'));
    });

    test('٤٠١ → حالة الدخول، مش «صوّر تاني»', () async {
      final e = await failureFor(jsonResponse({'error': 'session_required'}, 401));
      expect(e.needsSignIn, isTrue);
      expect(e.message, PrescriptionReadException.signInLine);
    });

    test('أي حاجة تانية (٤٠٠، ٥٠٢، ٥٠٣) → «مقدرتش أقرا…» والسبب جوّه', () async {
      for (final status in [400, 502, 503]) {
        final e = await failureFor(jsonResponse({'error': 'x'}, status));
        expect(e.message, 'مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.', reason: '$status');
        expect(e.needsSignIn, isFalse);
        expect(e.cause.toString(), contains('$status'));
      }
    });

    test('رد مش JSON → استثناء مش crash', () async {
      final e = await failureFor(http.Response('<html>', 200));
      expect(e.message, contains('صوّر تاني'));
    });

    test('مفيش نت → رسالة «مفيش نت»', () async {
      final reader = GeminiPrescriptionReader(
        FakeAiSession(),
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(
        () => reader.read(image),
        throwsA(isA<PrescriptionReadException>().having((e) => e.message, 'message', contains('نت'))),
      );
    });
  });

  group('تحذير الموديل البديل — بييجي من السحابة في header', () {
    test('من غير header → مفيش تحذير', () async {
      final reading = await GeminiPrescriptionReader(FakeAiSession(), client: MockClient((_) async => ok())).read(image);
      expect(reading.modelWarning, isNull);
    });

    test('x-model-warning: المثبّت;البديل → القراءة معلّمة بالاسمين، بجملة عربي مبنية هنا', () async {
      final reading = await GeminiPrescriptionReader(
        FakeAiSession(),
        client: MockClient((_) async => ok(headers: {'x-model-warning': 'gemini-3.6-flash;gemini-flash-latest'})),
      ).read(image);

      expect(reading.lines.single.name.value, 'Concor 5mg');
      expect(reading.modelWarning, contains('gemini-3.6-flash'));
      expect(reading.modelWarning, contains('gemini-flash-latest'));
      expect(reading.modelWarning, contains('ثبّت تاني بإيدك'));
    });
  });

  group('اللوج بيقول السبب الحقيقي', () {
    late List<String> log;

    setUp(() {
      log = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        // سطر حجم الصورة (C1) بيطلع في كل نداء وله اختباره في
        // shrink_on_the_wire_test — هنا بنعدّ سطور الأعطال بس.
        if (message != null && !message.contains('shrinkForAi')) log.add(message);
      };
    });

    tearDown(() => debugPrint = debugPrintThrottled);

    test('٥٠٢ → الحالة ونص رد السحابة في اللوج، والتوكن مش فيه', () async {
      const body = '{"error":"gemini_failed","detail":"HTTP 400: Invalid JSON payload: Unknown name nullable"}';
      final reader = GeminiPrescriptionReader(
        FakeAiSession(token: 'secret-session-token'),
        client: MockClient((_) async => http.Response(body, 502)),
      );

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));

      expect(log, hasLength(1));
      expect(log.single, contains('HTTP 502'));
      expect(log.single, contains('Unknown name'));
      expect(log.single, isNot(contains('secret-session-token')));
    });

    test('رد مش JSON → سبب التحليل ونص الرد في اللوج', () async {
      final reader = GeminiPrescriptionReader(
        FakeAiSession(),
        client: MockClient((_) async => http.Response('<html>oops</html>', 200)),
      );

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));
      expect(log.single, contains('parse:'));
      expect(log.single, contains('<html>oops</html>'));
    });

    test('نص طويل بيتقصّ على ٨٠٠ حرف', () async {
      final reader = GeminiPrescriptionReader(
        FakeAiSession(),
        client: MockClient((_) async => http.Response('x' * 5000, 500)),
      );

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));
      expect(log.single.length, lessThan(900));
      expect(log.single, endsWith('…'));
    });

    test('قراية ناجحة من الموديل المثبّت → ولا سطر عطل', () async {
      await GeminiPrescriptionReader(FakeAiSession(), client: MockClient((_) async => ok())).read(image);
      expect(log, isEmpty);
    });
  });
}
