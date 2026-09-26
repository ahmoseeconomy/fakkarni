// السحابة بتاخد الكلام المكتوب وبس، وبترجّع JSON صارم — وأي حاجة برّه الشكل
// أو أي عطل بيرجع بأمان: مش مفهوم أو «كمّل بإيدك»، ولا رمية واحدة.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/command_reader.dart';
import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

http.Response geminiReply(Object json) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': json is String ? json : jsonEncode(json)}
              ]
            }
          }
        ]
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  const config = GeminiConfig(apiKey: 'test-key');

  GeminiCommandReader readerWith(http.Client client, {Duration timeout = const Duration(seconds: 8)}) =>
      GeminiCommandReader(config, transport: GeminiPrescriptionReader(config, client: client), timeout: timeout);

  test('**الجسم فيه الكلام المكتوب وبس** — ولا صورة، ولا اسم دوا من القاعدة، ولا اسم مريض', () async {
    // أدوية «القاعدة» — لو واحدة منهم ظهرت في الطلب، الخصوصية اتكسرت
    const dbMeds = ['Concor 5mg', 'Glucophage 1000', 'Augmentin'];
    const patientName = 'الحاج أحمد';
    http.Request? sent;
    final client = MockClient((req) async {
      sent = req;
      return geminiReply({'intent': 'mark_taken', 'med_name_as_spoken': 'الضغط', 'timing_words': null, 'pattern_words': null});
    });
    final result = await readerWith(client).read('أخدت دوا الضغط');
    expect(result.command?.intent, 'mark_taken');
    expect(result.command?.medNameAsSpoken, 'الضغط');

    final body = jsonDecode(sent!.body) as Map<String, dynamic>;
    final parts = ((body['contents'] as List).single as Map)['parts'] as List;
    expect(parts, hasLength(1), reason: 'جزء واحد — نص');
    final text = (parts.single as Map)['text'] as String;
    expect(text, contains('أخدت دوا الضغط'));
    expect(text, GeminiCommandReader.promptFor('أخدت دوا الضغط'), reason: 'الكلام المكتوب وسطر التعريف — وبس');
    expect(sent!.body, isNot(contains('inline_data')));
    for (final med in dbMeds) {
      expect(sent!.body, isNot(contains(med)));
    }
    expect(sent!.body, isNot(contains(patientName)));
    expect(sent!.body, isNot(contains('routine')));
    expect(sent!.headers['x-goog-api-key'], 'test-key');
    expect(sent!.headers.containsKey('Authorization'), isFalse);
    expect(sent!.url.toString(), isNot(contains('test-key')));
  });

  test('JSON صحيح → أمر، والفاضي null', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({
          'intent': 'add_med',
          'med_name_as_spoken': 'الكونكور',
          'timing_words': 'الصبح بعد الفطار',
          'pattern_words': '',
        }))).read('ضيفلي الكونكور الصبح بعد الفطار');
    expect(r.failed, isFalse);
    expect(r.command!.intent, 'add_med');
    expect(r.command!.timingWords, 'الصبح بعد الفطار');
    expect(r.command!.patternWords, isNull, reason: 'فاضي = null');
  });

  test('حقل زيادة → مش مفهوم (الرد كله مرفوض)', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({
          'intent': 'mark_taken',
          'med_name_as_spoken': null,
          'timing_words': null,
          'pattern_words': null,
          'advice': 'خد قرصين',
        }))).read('x');
    expect(r.command, isNull);
    expect(r.failed, isFalse);
  });

  test('نية مش من القايمة → مش مفهوم', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({
          'intent': 'stop_med',
          'med_name_as_spoken': null,
          'timing_words': null,
          'pattern_words': null,
        }))).read('x');
    expect(r.command, isNull);
    expect(r.failed, isFalse);
  });

  test('حقل ناقص أو قيمة مش نص → مش مفهوم', () async {
    final missing = await readerWith(MockClient((_) async => geminiReply({'intent': 'next_dose'}))).read('x');
    expect(missing.command, isNull);
    final wrongType = await readerWith(MockClient((_) async => geminiReply({
          'intent': 'next_dose',
          'med_name_as_spoken': 5,
          'timing_words': null,
          'pattern_words': null,
        }))).read('x');
    expect(wrongType.command, isNull);
    expect(wrongType.failed, isFalse);
  });

  test('رد مش JSON → عطل (مش «مافهمتش») — ومفيش رمية', () async {
    final r = await readerWith(MockClient((_) async => geminiReply('خد قرصين بعد الأكل'))).read('x');
    expect(r.command, isNull);
    expect(r.failed, isTrue);
    expect(r.error, 'invalid_json');
  });

  test('HTTP 503 / 400 → عطل بكوده', () async {
    final r = await readerWith(MockClient((_) async => http.Response('busy', 503))).read('x');
    expect(r.failed, isTrue);
    expect(r.error, 'http_503');
  });

  test('عطل شبكة → عطل، مفيش رمية', () async {
    final r = await readerWith(MockClient((_) async => throw http.ClientException('no route'))).read('x');
    expect(r.failed, isTrue);
    expect(r.error, 'transport');
  });

  test('المهلة (٨ ثواني) → timeout — والشاشة بتقول «كمّل بإيدك»', () async {
    final r = await readerWith(
      MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return geminiReply({'intent': 'unknown', 'med_name_as_spoken': null, 'timing_words': null, 'pattern_words': null});
      }),
      timeout: const Duration(milliseconds: 50),
    ).read('x');
    expect(r.failed, isTrue);
    expect(r.error, 'timeout');
  });

  test('تعليمات الموديل بتمنع النصيحة الطبية وبتوجّه الشك لـmedical_question', () {
    expect(GeminiCommandReader.systemInstruction, contains('never give medical advice'));
    expect(GeminiCommandReader.systemInstruction, contains('choose medical_question'));
    expect(GeminiCommandReader.systemInstruction, contains('Never invent'));
    expect(CloudCommand.intents, hasLength(6));
  });
}
