import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintThrottled;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/core/images/shrink_for_ai.dart';

import '../support/fake_ai_session.dart';

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
    final reader = GeminiPrescriptionReader(FakeAiSession(), client: client);
    await reader.generate(image: image, mimeType: mimeType, kind: 'prescription', failure: 'f');
    // الجسم من بعد C2: {kind, mime, image} — نفس المعلومتين بأسامي دالتنا.
    return {'mime_type': sent['mime'], 'data': sent['image']};
  }

  group('اللوج بيطلع من generate على العزلة الرئيسية — سطر واحد لكل نداء', () {
    final log = <String>[];
    setUp(() {
      log.clear();
      debugPrint = (String? message, {int? wrapWidth}) => log.add(message ?? '');
    });
    tearDown(() => debugPrint = debugPrintThrottled);

    test('صورة كبيرة (مسار العزلة): الأبعاد والحجمين قبل وبعد', () async {
      final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 2560, height: 1920)));

      await inlineDataFor(jpg, 'image/jpeg');

      final lines = log.where((l) => l.contains('shrinkForAi')).toList();
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('Gemini: shrinkForAi: 2560×1920 → 1600×1200 — '));
      expect(lines.single, matches(RegExp(r'\d+KB → \d+KB \(\d+%\)$')));
    });

    test('صورة صغيرة (من غير عزلة): برضه سطر واحد، وبيقول إنها ما اتغيّرتش', () async {
      final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 640, height: 480)));

      await inlineDataFor(jpg, 'image/jpeg');

      final lines = log.where((l) => l.contains('shrinkForAi')).toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('640×480 — أصغر من الحد'));
      expect(lines.single, endsWith('(100%)'));
    });
  });

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
