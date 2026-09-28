// كارت الصيدلية: المكتوب بس، JSON صارم، ونفس نقل الروشتة — من غير شبكة.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/pharmacy_card_reader.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

http.Client _gemini(Map<String, dynamic> body, {void Function(http.Request)? onRequest}) =>
    MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(body)},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

GeminiPharmacyCardReader _reader(http.Client client) {
  const config = GeminiConfig(apiKey: 'test-key');
  return GeminiPharmacyCardReader(config, transport: GeminiPrescriptionReader(config, client: client));
}

final _image = Uint8List.fromList(List.filled(64, 7));

void main() {
  test('اسم وموبايل واحد → الاتنين موجودين، والثقة عالية', () async {
    final r = await _reader(_gemini({
      'name': 'صيدلية الشفا',
      'phones': ['01012345678'],
      'whatsapp': null,
      'address': 'شارع التحرير',
      'confidence': 'high',
    })).read(_image);
    expect(r.name, 'صيدلية الشفا');
    expect(r.phones, ['01012345678']);
    expect(r.unreadable, isFalse);
  });

  test('رقم «واتساب» بيتقرا لوحده', () async {
    final r = await _reader(_gemini({
      'name': 'صيدلية النور',
      'phones': ['0223456789', '01012345678'],
      'whatsapp': '01155554444',
      'address': null,
      'confidence': 'high',
    })).read(_image);
    expect(r.whatsapp, '01155554444');
  });

  test('JSON فاضي → مش مقروء (رسالة الثقة الواطية)', () async {
    final r = await _reader(_gemini({})).read(_image);
    expect(r.nothingFound, isTrue);
    expect(r.unreadable, isTrue);
  });

  test('ثقة واطية → مش مقروء حتى لو فيه اسم', () {
    final r = PharmacyCardReading.fromJson({'name': 'صيد', 'phones': [], 'confidence': 'low'});
    expect(r.unreadable, isTrue);
  });

  test('نوع غلط = مش موجود، مش رمية', () {
    final r = PharmacyCardReading.fromJson({'name': 5, 'phones': 'x', 'whatsapp': [1], 'confidence': 'high'});
    expect(r.name, isNull);
    expect(r.phones, isEmpty);
    expect(r.whatsapp, isNull);
  });

  test('نفس النقل: المفتاح في x-goog-api-key، مش في الرابط، والـschema بتاع الكارت', () async {
    late http.Request sent;
    await _reader(_gemini({'name': null, 'phones': [], 'whatsapp': null, 'address': null, 'confidence': 'low'},
        onRequest: (r) => sent = r)).read(_image);
    expect(sent.headers['x-goog-api-key'], 'test-key');
    expect(sent.url.toString(), isNot(contains('test-key')));
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(jsonEncode(body), contains('whatsapp'));
    expect(jsonEncode(body), contains('confidence'));
  });

  test('البرومبت: المكتوب بس، أرقام بس، واتساب من اللوجو أو الكلمة', () {
    expect(GeminiPharmacyCardReader.systemInstruction, contains('Never invent'));
    expect(GeminiPharmacyCardReader.prompt, contains('digits only'));
    expect(GeminiPharmacyCardReader.prompt, contains('WhatsApp logo'));
    expect(GeminiPharmacyCardReader.prompt, contains('واتساب'));
  });
}
