import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_config.dart';
import 'prescription_reading.dart';

/// بيقرا صورة روشتة وبيرجّع اقتراح — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class PrescriptionReader {
  Future<PrescriptionReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// القراءة فشلت — رسالة جاهزة للمستخدم، والسبب التقني في [cause].
class PrescriptionReadException implements Exception {
  const PrescriptionReadException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'PrescriptionReadException($message${cause == null ? '' : '، $cause'})';
}

/// Gemini عن طريق REST مباشرة.
///
/// من غير حزمة `google_generative_ai` — متوقّفة — ومن غير أي مفتاح في
/// الكود: [GeminiConfig] هو المصدر الوحيد، والمُنشئ بيرمي لو المفتاح فاضي
/// عشان مفيش ولا طلب يخرج من غير مفتاح.
class GeminiPrescriptionReader implements PrescriptionReader {
  GeminiPrescriptionReader(this.config, {http.Client? client})
      : _client = client ?? http.Client() {
    if (config.apiKey.trim().isEmpty) {
      throw StateError(GeminiConfig.missingKeyMessage);
    }
  }

  final GeminiConfig config;
  final http.Client _client;

  Uri get endpoint => Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/${config.model}:generateContent',
      );

  @override
  Future<PrescriptionReading> read(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': config.apiKey,
        },
        body: jsonEncode(_request(image, mimeType)),
      );
    } catch (error) {
      throw PrescriptionReadException('مفيش نت دلوقتي — جرّب تاني بعد شوية.', error);
    }

    if (response.statusCode != 200) {
      throw PrescriptionReadException(
        'مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.',
        'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes, allowMalformed: true)}',
      );
    }

    try {
      // utf8 صراحة: الرد فيه عربي، وترميز http الافتراضي latin1 لو الهيدر ناقص.
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final text = (((body['candidates'] as List).first as Map)['content']
          as Map)['parts'] as List;
      final json = jsonDecode((text.first as Map)['text'] as String)
          as Map<String, dynamic>;
      return PrescriptionReading.fromJson(json);
    } catch (error) {
      throw PrescriptionReadException('الرد رجع بشكل غريب — صوّر تاني.', error);
    }
  }

  Map<String, dynamic> _request(Uint8List image, String mimeType) => {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Encode(image),
                }
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0,
          'responseMimeType': 'application/json',
          'responseSchema': prescriptionSchema,
        },
      };

  /// التعليمات — القاعدة السادسة مكتوبة للموديل نفسه: ما تخمّنش.
  static const prompt = '''
You are reading a photo of a paper medical prescription from Egypt (Arabic and/or English, often handwritten).
Extract ONLY what is literally written. Never guess, infer, or complete anything.

For each medication line return: name (as written, keep Latin drug names in Latin), amount (e.g. "قرص واحد", "1 tablet", "5 ml"), timing, durationDays.

Timing rules:
- Prefer meal-relative timing: anchor ∈ {wake, breakfast, lunch, dinner, sleep}, relation ∈ {before, after, at}, offsetMinutes only if a number of minutes is written.
- "1×3" / "3 times daily" style with no meal named: set timesPerDay and leave anchor null.
- Set clockTime "HH:MM" (24h) ONLY if an explicit clock time is written on the paper.
- If timing is unclear, illegible, or "when needed": leave anchor, clockTime and timesPerDay null, set a low confidence, and set note to "مش متأكد — اسأل الصيدلي".

durationDays: ONLY if a duration is written. If not written, value must be null with confidence 1 — a missing duration is not an error.

confidence is 0..1 for each field based on legibility. Below 0.8 means a human must check it.
Do not add, remove, rename or substitute any medication. Do not give medical advice.
''';
}
