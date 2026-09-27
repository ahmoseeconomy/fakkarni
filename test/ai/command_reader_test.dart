// السحابة بتاخد الكلام المكتوب وتاريخ النهارده وبس، وبترجّع **أداة** بخاناتها
// بشكل صارم — وأي حاجة برّه الشكل أو أي عطل بيرجع بأمان: مش مفهوم أو «كمّل
// بإيدك»، ولا رمية واحدة.
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
  final now = DateTime(2026, 9, 26, 10);

  GeminiCommandReader readerWith(http.Client client, {Duration timeout = const Duration(seconds: 8)}) =>
      GeminiCommandReader(config, transport: GeminiPrescriptionReader(config, client: client), timeout: timeout);

  test('**الجسم فيه الكلام المكتوب وتاريخ النهارده وبس** — ولا صورة، ولا اسم دوا من القاعدة، ولا اسم مريض', () async {
    const dbMeds = ['Concor 5mg', 'Glucophage 1000', 'Augmentin'];
    const patientName = 'الحاج أحمد';
    http.Request? sent;
    final client = MockClient((req) async {
      sent = req;
      return geminiReply({'tool': 'mark_taken', 'med_name': 'الضغط'});
    });
    final result = await readerWith(client).read('أخدت دوا الضغط', now: now);
    expect(result.tool?.tool, 'mark_taken');
    expect(result.tool?.args['med_name'], 'الضغط');

    final body = jsonDecode(sent!.body) as Map<String, dynamic>;
    final parts = ((body['contents'] as List).single as Map)['parts'] as List;
    expect(parts, hasLength(1), reason: 'جزء واحد — نص');
    final text = (parts.single as Map)['text'] as String;
    expect(text, GeminiCommandReader.promptFor('أخدت دوا الضغط', now), reason: 'الكلام المكتوب وتاريخ النهارده — وبس');
    expect(text, contains('2026-09-26 (Saturday)'));
    expect(sent!.body, isNot(contains('inline_data')));
    for (final med in dbMeds) {
      expect(sent!.body, isNot(contains(med)));
    }
    expect(sent!.body, isNot(contains(patientName)));
    // روتين المريض نفسه ما بيروحش — التعليمات الثابتة بتسمّي أداة `set_routine` وبس
    expect(text, isNot(contains('routine')));
    expect(sent!.body, isNot(contains('"wake"')));
    expect(sent!.headers['x-goog-api-key'], 'test-key');
    expect(sent!.headers.containsKey('Authorization'), isFalse);
    expect(sent!.url.toString(), isNot(contains('test-key')));
  });

  test('JSON صحيح → أداة بخاناتها، والفاضي بيتشال', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({
          'tool': 'add_medication',
          'name': 'الكونكور',
          'anchors': ['after_breakfast'],
          'times': [],
          'pattern': '',
          'note': null,
        }))).read('ضيفلي الكونكور الصبح بعد الفطار');
    expect(r.failed, isFalse);
    expect(r.tool!.tool, 'add_medication');
    expect(r.tool!.args['anchors'], ['after_breakfast']);
    expect(r.tool!.args.containsKey('times'), isFalse, reason: 'قايمة فاضية = مش موجودة');
    expect(r.tool!.args.containsKey('pattern'), isFalse, reason: 'فاضي = null');
  });

  test('خانة مش من القايمة → مش مفهوم (الرد كله مرفوض)', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({'tool': 'mark_taken', 'advice': 'خد قرصين'}))).read('x');
    expect(r.tool, isNull);
    expect(r.failed, isFalse);
  });

  test('أداة مش من القايمة → مش مفهوم', () async {
    final r = await readerWith(MockClient((_) async => geminiReply({'tool': 'stop_med'}))).read('x');
    expect(r.tool, isNull);
    expect(r.failed, isFalse);
  });

  test('قيمة مش نص/رقم/قايمة → مش مفهوم', () async {
    final wrongType = await readerWith(MockClient((_) async => geminiReply({'tool': 'next_dose', 'med_name': {'a': 1}}))).read('x');
    expect(wrongType.tool, isNull);
    final nested = await readerWith(MockClient((_) async => geminiReply({'tool': 'add_vital', 'values': [[1]]}))).read('x');
    expect(nested.tool, isNull);
    final noTool = await readerWith(MockClient((_) async => geminiReply({'name': 'x'}))).read('x');
    expect(noTool.tool, isNull);
  });

  test('رد مش JSON → عطل (مش «مافهمتش») — ومفيش رمية', () async {
    final r = await readerWith(MockClient((_) async => geminiReply('خد قرصين بعد الأكل'))).read('x');
    expect(r.tool, isNull);
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
        return geminiReply({'tool': 'unknown'});
      }),
      timeout: const Duration(milliseconds: 50),
    ).read('x');
    expect(r.failed, isTrue);
    expect(r.error, 'timeout');
  });

  test('كل أداة في الـschema وفي التعليمات، والتعليمات بتمنع النصيحة الطبية', () {
    final enumTools = ((GeminiCommandReader.schema['properties'] as Map)['tool'] as Map)['enum'] as List;
    expect(enumTools.toSet(), CloudTool.tools);
    for (final t in CloudTool.tools) {
      expect(GeminiCommandReader.systemInstruction, contains('"$t"'));
    }
    expect(GeminiCommandReader.systemInstruction, contains('never give medical advice'));
    expect(GeminiCommandReader.systemInstruction, contains('choose medical_question'));
    expect(GeminiCommandReader.systemInstruction, contains('NEVER invent'));
    final props = (GeminiCommandReader.schema['properties'] as Map).keys.toSet()..remove('tool');
    expect(props, CloudTool.argKeys, reason: 'الخانات اللي الموديل يقدر يرجّعها هي اللي بنقبلها — بالظبط');
  });
}
