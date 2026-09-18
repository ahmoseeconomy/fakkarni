import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

/// **المفتاح بيروح في `x-goog-api-key` — وبس.**
///
/// جوجل بترفض `Authorization: Bearer <مفتاح>` بـ٤٠١
/// `ACCESS_TOKEN_TYPE_UNSUPPORTED`: الـheader ده لتوكن OAuth، مش لمفتاح API.
/// والغلطة دي **بتترجع مع الرجوع**: في جولة C2 الطلب كان رايح لدالتنا في
/// السحابة بـ`Authorization: Bearer <توكن الجلسة>` + `apikey`، فأي رجوع
/// ناقص بيسيب الشكل ده ويوجّهه لجوجل. الاختبار ده هو اللي بيمسكها.
///
/// وكمان: المفتاح **عمره ما بيدخل الرابط**. رابط فيه `?key=` بيتسجّل في كل
/// لوج وصول وكل بروكسي في الطريق.
///
/// قارئ التحاليل بيعدّي من نفس النقل ([GeminiPrescriptionReader.generate])،
/// فالاختبار بيمشي على الاتنين — مش على الروشتة بس.
final image = Uint8List.fromList(List<int>.generate(16, (i) => i));

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

const secret = 'AIza-super-secret-key-value';

void main() {
  late List<http.Request> sent;

  http.Client recorder(String body) => MockClient((request) async {
        sent.add(request);
        return http.Response.bytes(utf8.encode(body), 200);
      });

  setUp(() => sent = []);

  void expectKeyInHeaderOnly() {
    expect(sent, isNotEmpty, reason: 'مفيش طلب اتبعت أصلاً');
    for (final request in sent) {
      // الاسم بالحرف — ده اللي جوجل بتقراه
      expect(request.headers['x-goog-api-key'], secret);

      // ولا Authorization خالص: ده اللي بيرجّع ٤٠١ ACCESS_TOKEN_TYPE_UNSUPPORTED
      // (خرائط الـheaders في http بتقارن من غير حساسية حالة الحروف)
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
      // ولا `apikey` بتاعة Supabase — دي كانت لدالتنا، مش لجوجل
      expect(request.headers.containsKey('apikey'), isFalse);

      // ولا المفتاح ولا أي مفتاح في الرابط
      expect(request.url.query, isEmpty, reason: 'الرابط من غير أي باراميتر');
      expect(request.url.toString().contains(secret), isFalse);
      expect(request.url.toString().toLowerCase().contains('key='), isFalse);

      expect(request.url.host, 'generativelanguage.googleapis.com');
      expect(request.url.path, startsWith('/v1beta/models/'));
    }
  }

  test('الروشتة: المفتاح في x-goog-api-key، مفيش Authorization، ومفيش مفتاح في الرابط', () async {
    final body = geminiBody({
      'medications': [
        {
          'name': {'value': 'Concor', 'confidence': 0.9},
          'amount': {'value': 'قرص', 'confidence': 0.9},
          'timing': {'anchor': 'breakfast', 'confidence': 0.9},
          'durationDays': {'value': null, 'confidence': 1},
        },
      ],
    });
    await GeminiPrescriptionReader(const GeminiConfig(apiKey: secret), client: recorder(body)).read(image);

    expectKeyInHeaderOnly();
  });

  test('التحاليل: نفس النقل ونفس القاعدة — الحارس بيغطّي الاتنين', () async {
    const config = GeminiConfig(apiKey: secret);
    final transport = GeminiPrescriptionReader(config, client: recorder(geminiBody({'results': []})));
    await GeminiLabReader(config, transport: transport).read(image);

    expectKeyInHeaderOnly();
  });

  test('البديل بياخد نفس الـheaders — مش المحاولة الأولى بس', () async {
    const retired = '{"error":{"code":404,"status":"NOT_FOUND"}}';
    final ok = geminiBody({
      'medications': [
        {
          'name': {'value': 'Concor', 'confidence': 0.9},
          'amount': {'value': 'قرص', 'confidence': 0.9},
          'timing': {'anchor': 'breakfast', 'confidence': 0.9},
          'durationDays': {'value': null, 'confidence': 1},
        },
      ],
    });
    final client = MockClient((request) async {
      sent.add(request);
      return sent.length == 1
          ? http.Response(retired, 404)
          : http.Response.bytes(utf8.encode(ok), 200);
    });
    await GeminiPrescriptionReader(const GeminiConfig(apiKey: secret), client: client).read(image);

    expect(sent, hasLength(2));
    expect(sent.last.url.path, contains('gemini-flash-latest'));
    expectKeyInHeaderOnly();
  });
}
