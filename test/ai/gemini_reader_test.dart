import 'dart:convert';
import 'dart:typed_data';

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
      expect(sent!.url.path, contains('gemini-2.5-flash:generateContent'));
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
