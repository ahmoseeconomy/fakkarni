// كذا صفحة من نفس الورقة = **طلب واحد** بكل الصور (طلب المدير، ٤ أكتوبر
// ٢٠٢٦) — وصفحة واحدة بتفضل نفس الطلب بالحرف.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

import 'gemini_reader_test.dart' show geminiBody;

void main() {
  final p1 = Uint8List.fromList([1, 2, 3]);
  final p2 = Uint8List.fromList([4, 5, 6]);

  ({MockClient client, List<http.Request> sent}) recorder(Map<String, dynamic> answer) {
    final sent = <http.Request>[];
    return (
      client: MockClient((req) async {
        sent.add(req);
        return http.Response.bytes(utf8.encode(geminiBody(answer)), 200);
      }),
      sent: sent,
    );
  }

  List parts(http.Request r) => (((jsonDecode(r.body) as Map)['contents'] as List).first as Map)['parts'] as List;

  test('الروشتة بصفحتين: طلب واحد، صورتين، والبرومبت بيقول إنهم ورقة واحدة', () async {
    final rec = recorder({'medications': []});
    final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: rec.client);
    await reader.read(p1, morePages: [p2]);

    expect(rec.sent, hasLength(1));
    final ps = parts(rec.sent.single);
    expect(ps, hasLength(3));
    expect(ps[1]['inline_data']['data'], base64Encode(p1));
    expect(ps[2]['inline_data']['data'], base64Encode(p2));
    expect(ps[0]['text'], contains('pages (or parts) of ONE single paper'));
  });

  test('صفحة واحدة: نفس الطلب القديم بالحرف — مفيش سطر الصفحات', () async {
    final rec = recorder({'medications': []});
    final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: rec.client);
    await reader.read(p1);

    final ps = parts(rec.sent.single);
    expect(ps, hasLength(2));
    expect(ps[0]['text'], GeminiPrescriptionReader.prompt);
  });

  test('التحليل بنفس النقل، والسقف ٤ صفحات حتى لو اتبعت أكتر', () async {
    final rec = recorder({'lines': []});
    final reader = GeminiLabReader(
      const GeminiConfig(apiKey: 'k'),
      transport: GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: rec.client),
    );
    await reader.read(p1, morePages: List.filled(6, p2));

    expect(rec.sent, hasLength(1));
    expect(parts(rec.sent.single), hasLength(1 + maxScanPages));
  });
}
