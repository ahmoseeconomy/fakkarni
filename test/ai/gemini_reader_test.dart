import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintThrottled;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

final image = Uint8List.fromList(List<int>.generate(64, (i) => i));

/// رد Gemini اللي بيشيل جوّاه الـJSON بتاعنا كنص.
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

void main() {
  group('المفتاح', () {
    test('مفتاح فاضي → بيرمي فوراً برسالة --dart-define، ومفيش ولا طلب', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });

      expect(
        () => GeminiPrescriptionReader(const GeminiConfig(apiKey: '  '), client: client),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('--dart-define=GEMINI_API_KEY'),
          ),
        ),
      );
      expect(requests, 0);
    });

    test('من غير --dart-define في الاختبارات → null، وfromEnvironment بترمي', () {
      // الاختبارات بتتشغّل من غير تعريف، فده بيثبت إن الافتراضي مش مفتاح فاضي.
      expect(GeminiConfig.tryFromEnvironment(), isNull);
      expect(GeminiConfig.fromEnvironment, throwsA(isA<StateError>()));
    });
  });

  group('اللوج بيقول السبب الحقيقي', () {
    late List<String> log;

    setUp(() {
      log = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) log.add(message);
      };
    });

    tearDown(() => debugPrint = debugPrintThrottled);

    test('٤٠٠ → الحالة ونص الرد في اللوج، والمفتاح مش فيه', () async {
      const body = '{"error":{"code":400,"message":"Invalid JSON payload: Unknown name nullable"}}';
      final client = MockClient((_) async => http.Response(body, 400));
      final reader = GeminiPrescriptionReader(
        const GeminiConfig(apiKey: 'AQ.secret-key-value'),
        client: client,
      );

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));

      expect(log, hasLength(1));
      expect(log.single, contains('HTTP 400'));
      expect(log.single, contains('Unknown name'));
      expect(log.single, isNot(contains('secret-key-value')));
    });

    test('٤٠٣ (مفتاح مقيّد) → نفس الشيء، والسبب في الاستثناء كمان', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":{"code":403,"message":"PERMISSION_DENIED"}}', 403),
      );
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client);

      await expectLater(
        () => reader.read(image),
        throwsA(isA<PrescriptionReadException>().having((e) => e.cause.toString(), 'cause', contains('403'))),
      );
      expect(log.single, contains('PERMISSION_DENIED'));
    });

    test('رد مش JSON → سبب التحليل ونص الرد في اللوج', () async {
      final client = MockClient((_) async => http.Response('<html>oops</html>', 200));
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client);

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));
      expect(log.single, contains('parse:'));
      expect(log.single, contains('<html>oops</html>'));
    });

    test('نص طويل بيتقصّ على ٨٠٠ حرف', () async {
      final long = 'x' * 5000;
      final client = MockClient((_) async => http.Response(long, 500));
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client);

      await expectLater(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));
      expect(log.single.length, lessThan(900));
      expect(log.single, endsWith('…'));
    });

    test('مفتاح بيبدأ بـAQ. بيتقبل زي أي مفتاح — مفيش افتراض عن البادئة', () {
      expect(
        () => GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.abc'), client: MockClient((_) async => http.Response('{}', 200))),
        returnsNormally,
      );
    });
  });

  group('اسم الموديل', () {
    test('الافتراضي هو اللي جوجل قالته في رد الـ٤٠٤', () {
      expect(GeminiConfig.defaultModel, 'gemini-3.6-flash');
      // الاختبارات بتتشغّل من غير GEMINI_MODEL → الافتراضي
      expect(GeminiConfig.modelFromEnvironment, GeminiConfig.defaultModel);
    });

    test('اسم تاني بيدخل في المسار زي ما هو — تغيير من برّه من غير كود', () {
      final reader = GeminiPrescriptionReader(
        const GeminiConfig(apiKey: 'AQ.k', model: 'gemini-9-flash'),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(reader.endpoint.path, '/v1beta/models/gemini-9-flash:generateContent');
    });
  });

  group('تقاعد الموديل — مرة واحدة على البديل وبصوت عالي', () {
    late List<String> log;
    setUp(() {
      log = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) log.add(message);
      };
    });
    tearDown(() => debugPrint = debugPrintThrottled);

    final okBody = geminiBody({
      'medications': [
        {
          'name': {'value': 'Concor', 'confidence': 0.9},
          'amount': {'value': 'قرص', 'confidence': 0.9},
          'timing': {'anchor': 'breakfast', 'confidence': 0.9},
          'durationDays': {'value': null, 'confidence': 1},
        },
      ],
    });
    const retired = '{"error":{"code":404,"message":"models/gemini-3.6-flash is no longer available to new users.","status":"NOT_FOUND"}}';

    test('المثبّت شغّال → طلب واحد ومفيش تحذير', () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        return http.Response.bytes(utf8.encode(okBody), 200);
      });
      final reading = await GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client).read(image);

      expect(paths, ['/v1beta/models/gemini-3.6-flash:generateContent']);
      expect(reading.modelWarning, isNull);
      expect(log, isEmpty);
    });

    test('٤٠٤ NOT_FOUND → إعادة مرة واحدة على gemini-flash-latest، تحذير، والقراءة معلّمة', () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        return paths.length == 1
            ? http.Response(retired, 404)
            : http.Response.bytes(utf8.encode(okBody), 200);
      });
      final reading = await GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client).read(image);

      expect(paths, [
        '/v1beta/models/gemini-3.6-flash:generateContent',
        '/v1beta/models/gemini-flash-latest:generateContent',
      ]);
      expect(reading.lines.single.name.value, 'Concor');
      expect(reading.modelWarning, contains('gemini-3.6-flash'));
      expect(reading.modelWarning, contains('gemini-flash-latest'));
      expect(log, hasLength(1));
      expect(log.single, contains('WARNING'));
      expect(log.single, contains('retired'));
      expect(log.single, isNot(contains('AQ.k')));
    });

    test('البديل كمان وقع → استثناء بيقول إنه بعد البديل، ومفيش محاولة تالتة', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(retired, 404);
      });
      await expectLater(
        () => GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client).read(image),
        throwsA(isA<PrescriptionReadException>().having((e) => e.cause.toString(), 'cause', contains('after fallback'))),
      );
      expect(calls, 2);
    });

    test('٤٠٤ من غير NOT_FOUND، أو ٤٠٠ → مفيش إعادة (ده مش تقاعد)', () async {
      for (final response in [http.Response('nope', 404), http.Response('{"error":{"status":"INVALID_ARGUMENT"}}', 400)]) {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return response;
        });
        await expectLater(
          () => GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client).read(image),
          throwsA(isA<PrescriptionReadException>()),
        );
        expect(calls, 1, reason: '${response.statusCode}');
      }
    });

    test('اسم البديل بيتغيّر من الإعدادات زي المثبّت', () {
      const config = GeminiConfig(apiKey: 'AQ.k', fallbackModel: 'gemini-x');
      expect(config.fallbackModel, 'gemini-x');
      expect(GeminiConfig.fallbackFromEnvironment, GeminiConfig.defaultFallbackModel);
    });
  });

  group('الطلب والرد', () {
    test('المفتاح في الهيدر، الصورة inline، والـschema مطلوبة', () async {
      http.Request? sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response.bytes(
          utf8.encode(geminiBody({
            'medications': [
              {
                'name': {'value': 'Concor 5mg', 'confidence': 0.95},
                'amount': {'value': 'قرص', 'confidence': 0.9},
                'timing': {'anchor': 'breakfast', 'relation': 'after', 'confidence': 0.9},
                'durationDays': {'value': null, 'confidence': 1},
              },
            ],
          })),
          200,
        );
      });

      final reader = GeminiPrescriptionReader(
        const GeminiConfig(apiKey: 'test-key'),
        client: client,
      );
      final reading = await reader.read(image);

      expect(sent!.url.host, 'generativelanguage.googleapis.com');
      expect(sent!.url.path, '/v1beta/models/gemini-3.6-flash:generateContent');
      expect(sent!.headers['x-goog-api-key'], 'test-key');
      expect(sent!.url.queryParameters.containsKey('key'), isFalse, reason: 'مش في الـURL');

      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      final parts = ((body['contents'] as List).first as Map)['parts'] as List;
      expect((parts[1] as Map)['inline_data']['data'], base64Encode(image));
      expect(body['generationConfig']['responseMimeType'], 'application/json');
      expect(body['generationConfig']['responseSchema'], isNotNull);
      expect((parts[0] as Map)['text'], contains('Never guess'));

      expect(reading.lines.single.name.value, 'Concor 5mg');
    });

    test('HTTP مش ٢٠٠ → استثناء برسالة للمستخدم والسبب جوّه', () async {
      final client = MockClient((_) async => http.Response('quota', 429));
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: client);

      expect(
        () => reader.read(image),
        throwsA(
          isA<PrescriptionReadException>()
              .having((e) => e.message, 'message', contains('صوّر تاني'))
              .having((e) => e.cause.toString(), 'cause', contains('429')),
        ),
      );
    });

    test('رد مش JSON → استثناء مش crash', () async {
      final client = MockClient((_) async => http.Response('<html>', 200));
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: client);

      expect(() => reader.read(image), throwsA(isA<PrescriptionReadException>()));
    });

    test('مفيش نت → رسالة «مفيش نت»', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: client);

      expect(
        () => reader.read(image),
        throwsA(isA<PrescriptionReadException>().having((e) => e.message, 'message', contains('نت'))),
      );
    });
  });
}
