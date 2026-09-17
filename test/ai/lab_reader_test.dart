import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

import '../support/fake_ai_session.dart';

final image = Uint8List.fromList(List<int>.generate(32, (i) => i));

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
  GeminiLabReader readerWith(http.Client client) {
    final session = FakeAiSession();
    return GeminiLabReader(session, transport: GeminiPrescriptionReader(session, client: client));
  }

  // التعليمة اللي بتمنع النطاق والعلامات والتفسير، والـschema اللي مفيهوش
  // مكان ليهم، بقوا في دالة السحابة من بعد C2 — `ai_read_function_test`
  // بيقرا الملف ده وبيثبّتهم هناك. هنا: العميل بيطلب `lab` وبس.
  test('الطلب: kind = lab وصورة ونوع ملف — ومفيش برومبت ولا تعليمة ولا schema من العميل', () async {
    Map<String, dynamic>? sent;
    final reader = readerWith(MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(geminiBody({'results': []}), 200);
    }));
    await reader.read(image);

    expect(sent!.keys.toSet(), {'kind', 'mime', 'image'});
    expect(sent!['kind'], 'lab');
  });

  test('القراءة: الأرقام بثقتها، والرقم اللي مش واضح بيقفل «تمام»', () async {
    final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(geminiBody({
            'lab': {'value': 'معمل البرج', 'confidence': 0.95},
            'reportDate': {'value': '2026-09-12', 'confidence': 0.9},
            'results': [
              {
                'test': {'value': 'HbA1c', 'confidence': 0.97},
                'value': {'value': 7.6, 'confidence': 0.95},
                'unit': {'value': '%', 'confidence': 0.9},
              },
              {
                'test': {'value': 'Creatinine', 'confidence': 0.9},
                'value': {'value': null, 'confidence': 0},
                'unit': {'value': 'mg/dL', 'confidence': 0.9},
              },
            ],
          })),
          200,
        ));
    final reading =
        await readerWith(client).read(image);

    expect(reading.lab.value, 'معمل البرج');
    expect(reading.date.value, DateTime(2026, 9, 12));
    expect(reading.lines, hasLength(2));
    expect(reading.lines.first.value.value, 7.6);
    expect(reading.lines.first.blocksConfirm, isFalse);
    expect(reading.lines.last.blocksConfirm, isTrue);
  });

  test('فشل الشبكة → رسالة التقرير مش رسالة الروشتة', () async {
    final client = MockClient((_) async => http.Response('{"error":"boom"}', 500));
    final reader = readerWith(client);
    expect(
      () => reader.read(image),
      throwsA(isA<PrescriptionReadException>().having((e) => e.message, 'message', contains('التقرير'))),
    );
  });
}
