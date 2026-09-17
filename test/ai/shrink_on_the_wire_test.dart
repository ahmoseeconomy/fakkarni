import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/core/images/shrink_for_ai.dart';

/// C1 عند نقطة النداء نفسها: اللي بيطلع على السلك هو اللي بيتحاسب عليه.
///
/// الاختبارات دي بتعدّي من `compute` الحقيقي — عزلة بجد — فبتثبت كمان إن
/// الغلاف اللي بيرجّع null شغّال عبر العزلتين.
void main() {
  const okBody = '{"candidates":[{"content":{"parts":[{"text":"{\\"lines\\":[]}"}]}}]}';

  Future<Map<String, dynamic>> inlineDataFor(Uint8List image, String mimeType) async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(okBody, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final reader = GeminiPrescriptionReader(const GeminiConfig(apiKey: 'AQ.k'), client: client);
    await reader.generate(
      image: image,
      mimeType: mimeType,
      prompt: 'p',
      schema: const {'type': 'object'},
      failure: 'f',
    );
    final parts = ((sent['contents'] as List).first as Map)['parts'] as List;
    return (parts[1] as Map)['inline_data'] as Map<String, dynamic>;
  }

  test('صورة ٢٥٦٠×١٩٢٠ بتطلع على السلك ١٦٠٠ وبنوع jpeg — حتى لو دخلت PNG', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 2560, height: 1920)));

    final data = await inlineDataFor(png, 'image/png');

    expect(data['mime_type'], 'image/jpeg', reason: 'البايتات بقت JPEG — النوع لازم يمشي معاها');
    final size = quickImageSizeOf(base64Decode(data['data'] as String))!;
    expect(size.width, aiMaxSide);
    expect(size.height, 1200);
  });

  test('صورة صغيرة بتطلع زي ما هي بالبايت وبنوعها', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 640, height: 480)));

    final data = await inlineDataFor(png, 'image/png');

    expect(data['mime_type'], 'image/png');
    expect(base64Decode(data['data'] as String), png);
  });

  test('بايتات العزلة ما قدرتش تفكّها بترجع زي ما هي **وبنوعها** — مش image/jpeg', () async {
    // صيغة مش معروفة للبوّابة → بتروح العزلة → بترجع null → الأصل ونوعه
    final odd = Uint8List.fromList(List<int>.generate(4000, (i) => i % 251));

    final data = await inlineDataFor(odd, 'image/heic');

    expect(data['mime_type'], 'image/heic');
    expect(base64Decode(data['data'] as String), odd);
  });
}
