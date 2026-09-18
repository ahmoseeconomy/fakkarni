import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

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
  const config = GeminiConfig(apiKey: 'test-key');

  test('الـsystem instruction بيمنع النطاق والعلامات والتفسير والنصيحة صراحةً — ومتبعت في الطلب', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(geminiBody({'results': []}), 200);
    });
    final reader = GeminiLabReader(config, transport: GeminiPrescriptionReader(config, client: client));
    await reader.read(image);

    final instruction = GeminiLabReader.systemInstruction;
    for (final phrase in [
      'not a doctor',
      'Do NOT return reference ranges',
      'Do NOT return H/L',
      'Do NOT interpret, diagnose, recommend, or advise',
      'Never say a value is high, low, normal, abnormal',
      'Never suggest seeing a doctor',
      'Never guess a digit',
    ]) {
      expect(instruction, contains(phrase));
    }
    final parts = ((sent!['systemInstruction'] as Map)['parts'] as List).first as Map;
    expect(parts['text'], instruction);
    expect(sent!['generationConfig']['responseSchema'], labSchema);
  });

  test('الـschema مفيهوش مكان لنطاق مرجعي ولا علامة ولا تفسير', () {
    final text = jsonEncode(labSchema).toLowerCase();
    for (final forbidden in ['range', 'reference', 'flag', 'interpret', 'normal', 'comment', 'note']) {
      expect(text.contains(forbidden), isFalse, reason: forbidden);
    }
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
        await GeminiLabReader(config, transport: GeminiPrescriptionReader(config, client: client)).read(image);

    expect(reading.lab.value, 'معمل البرج');
    expect(reading.date.value, DateTime(2026, 9, 12));
    expect(reading.lines, hasLength(2));
    expect(reading.lines.first.value.value, 7.6);
    expect(reading.lines.first.blocksConfirm, isFalse);
    expect(reading.lines.last.blocksConfirm, isTrue);
  });

  test('فشل الشبكة → رسالة التقرير مش رسالة الروشتة', () async {
    final client = MockClient((_) async => http.Response('{"error":"boom"}', 500));
    final reader = GeminiLabReader(config, transport: GeminiPrescriptionReader(config, client: client));
    expect(
      () => reader.read(image),
      throwsA(isA<PrescriptionReadException>().having((e) => e.message, 'message', contains('التقرير'))),
    );
  });
}
