import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;

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
      // النطاق بقى بيتنقل من الورقة — والجملتين دول هما اللي بيمنعوا
      // إن الموديل يجيبه من معرفته هو.
      'EXACTLY AS PRINTED ON THAT REPORT',
      'never recalled, never inferred',
      'A missing range\nis a correct answer',
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

  test('الـschema فيه نطاق الورقة — وما فيهوش علامة ولا تفسير ولا نص حر', () {
    final results = ((labSchema['properties']! as Map)['results']! as Map);
    final fields = (((results['items']! as Map)['properties']!) as Map).keys.toSet();
    // نقل اللي مطبوع: الاسم والرقم والوحدة والنطاق.
    expect(fields, {'test', 'value', 'unit', 'refLow', 'refHigh', 'refText'});

    // ولا خانة يقدر يحكم أو يفسّر من خلالها.
    final text = jsonEncode(labSchema).toLowerCase();
    for (final forbidden in ['flag', 'interpret', 'normal', 'comment', 'note', 'advice', 'status']) {
      expect(text.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('الحقول التلاتة مطلوبة — الموديل مش مسموح له يسيب حد منهم', () {
    // حقل **ناقص** وحقل **null** معناهم مختلف عندنا: الناقص بيخلّي نطاق
    // «٠.١ إلى ١.٢» يوصل الشاشة «أكتر من ٠.١»، والحد الأعلى بيضيع في
    // صمت ومعاه «قريب من الحد» اللي محتاج الطرفين.
    final items = ((labSchema['properties']! as Map)['results']! as Map)['items']! as Map;
    expect(items['required'], containsAll(['refLow', 'refHigh', 'refText']));
  });

  test('رقم جاي كنص لسه بيتقرا — الحد ما بيضيعش عشان شكله', () {
    // الـschema بيقول NUMBER، والموديل ساعات بيبعت "1.2". قراية النص مش
    // اختراع قيمة: الرقم مكتوب، إحنا بس كنا بنرفض شكله ونرمي الحد كله.
    final reading = LabReading.fromJson({
      'results': [
        {
          'test': {'value': 'TSH', 'confidence': 0.95},
          'value': {'value': 0.9, 'confidence': 0.95},
          'unit': {'value': 'mIU/L', 'confidence': 0.95},
          'refLow': {'value': 0.1, 'confidence': 0.95},
          'refHigh': {'value': '1.2', 'confidence': 0.95},
        },
      ],
    });
    final range = reading.lines.single.range!;
    expect((range.low, range.high), (0.1, 1.2));
  });

  test('حقل ناقص خالص لسه بيرجع طرف واحد — وده اللي الـrequired بيمنعه', () {
    // لو موديل خالف الـschema، السلوك بيفضل معروف: الطرف اللي وصل بس.
    final reading = LabReading.fromJson({
      'results': [
        {
          'test': {'value': 'FT4', 'confidence': 0.95},
          'value': {'value': 1.1, 'confidence': 0.95},
          'unit': {'value': 'ng/dL', 'confidence': 0.95},
          'refLow': {'value': 0.8, 'confidence': 0.95},
        },
      ],
    });
    final range = reading.lines.single.range!;
    expect(range.low, 0.8);
    expect(range.high, isNull);
    expect(range.width, isNull, reason: 'من غير عرض مفيش «قريب من الحد»');
  });

  test('نطاق مش متأكد = مفيش نطاق — أحسن من علامة على قراءة غلط', () {
    LabLine lineWith(double confidence) => LabLine(
          test: const ReadField(value: 'WBC', confidence: 0.95),
          value: const ReadField(value: 12.4, confidence: 0.95),
          unit: const ReadField.missing(),
          refLow: ReadField(value: 4, confidence: confidence),
          refHigh: ReadField(value: 11, confidence: confidence),
        );
    expect(lineWith(0.95).range, isNotNull);
    expect(lineWith(0.4).range, isNull);
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
