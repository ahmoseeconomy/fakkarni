import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;

import '../core/images/shrink_for_ai.dart';
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

  Uri get endpoint => endpointFor(config.model);

  Uri endpointFor(String model) => Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent',
      );

  @override
  Future<PrescriptionReading> read(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  }) async {
    final result = await generate(
      image: image,
      mimeType: mimeType,
      prompt: prompt,
      schema: prescriptionSchema,
      failure: 'مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.',
    );
    final reading = PrescriptionReading.fromJson(result.json);
    return result.warning == null ? reading : reading.withModelWarning(result.warning!);
  }

  /// النقل المشترك (D3.6): الروشتة والتحليل نفس الطريق — نفس المفتاح، نفس
  /// التثبيت والبديل، نفس الأخطاء — ببرومبت وschema مختلفين.
  Future<({Map<String, dynamic> json, String? warning})> generate({
    required Uint8List image,
    required String mimeType,
    required String prompt,
    required Map<String, dynamic> schema,
    required String failure,
    String? systemInstruction,
  }) async {
    // التصغير هنا وبس (C1). النقل ده هو الطريق الوحيد لـGemini — الروشتة
    // والتحليل الاتنين بيعدّوا منه — فمفيش نقطة نداء تقدر تنسى تصغّر،
    // ولا واحدة جديدة هتفتكر لوحدها. الناتج JPEG دايماً، فالنوع بيتصحّح
    // معاه: بعت `image/png` مع بايتات JPEG بيرجّع ٤٠٠ من Gemini.
    //
    // وبيتنفّذ في **عزلة تانية**، مش على خيط الواجهة: التصغير شغل CPU تقيل
    // — قياس على ٢٥٦٠×١٩٢٠ (اللي الكاميرا بتدّينا إياها فعلاً) طلع ثواني،
    // والشاشة اللي بتقول «بيقرا الروشتة…» كانت هتتجمّد فيها بالظبط.
    // والسؤال «نفتح عزلة؟» بيتجاوب على الخيط ده من ترويسة الملف **فعلاً**
    // (علامة SOF / IHDR) — `startDecode` بتاع الحزمة اتقاس ١٦٩ مللي، يعني
    // ١٠ فريمات واقعة في كل تصويرة. العزلة بترجّع null لو ما غيّرتش حاجة،
    // لأن `identical` عبر عزلتين دايماً false والنوع كان هيتغلّط.
    final resized = mayNeedShrinkForAi(image) ? await compute(shrinkForAiOrNull, image) : null;
    final shrunk = resized ?? image;
    final wireType = resized == null ? mimeType : 'image/jpeg';
    final body = jsonEncode(_request(shrunk, wireType, prompt, schema, systemInstruction));

    var response = await _post(config.model, body);
    var raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    String? warning;

    // الموديل المثبّت اتقفل؟ مرة واحدة على البديل، وبصوت عالي.
    // ٤٠٠ (مشكلة schema) **ما بيعملش** ده — الإخفاء هنا هو بالظبط تغيّر
    // السلوك اللي بنحمي منه.
    if (_isRetired(response.statusCode, raw)) {
      warning = 'الموديل المثبّت ${config.model} اتقفل — '
          'القراءة جت من ${config.fallbackModel}. ثبّت تاني بإيدك. '
          '(${_excerpt(raw, 200)})';
      debugPrint('Gemini: WARNING pinned model ${config.model} retired: '
          '${_excerpt(raw, 200)} — retrying once with ${config.fallbackModel}');
      response = await _post(config.fallbackModel, body);
      raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    }

    if (response.statusCode != 200) {
      // السبب الحقيقي بيتسجّل هنا — مش بنخمّن. المفتاح عمره ما بيتطبع.
      final cause = 'HTTP ${response.statusCode}: ${_excerpt(raw)}'
          '${warning == null ? '' : ' (after fallback ${config.fallbackModel})'}';
      debugPrint('Gemini: $cause');
      throw PrescriptionReadException(failure, cause);
    }

    return (json: _parse(raw), warning: warning);
  }

  Future<http.Response> _post(String model, String body) async {
    try {
      return await _client.post(
        endpointFor(model),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': config.apiKey,
        },
        body: body,
      );
    } catch (error) {
      debugPrint('Gemini: transport: $error');
      throw PrescriptionReadException('مفيش نت دلوقتي — جرّب تاني بعد شوية.', error);
    }
  }

  /// ٤٠٤ ونصه بيقول NOT_FOUND — ده تقاعد موديل، مش مسار غلط.
  static bool _isRetired(int status, String body) =>
      status == 404 && body.contains('NOT_FOUND');

  Map<String, dynamic> _parse(String raw) {
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final text = (((body['candidates'] as List).first as Map)['content']
          as Map)['parts'] as List;
      return jsonDecode((text.first as Map)['text'] as String)
          as Map<String, dynamic>;
    } catch (error) {
      final cause = 'parse: $error — body: ${_excerpt(raw)}';
      debugPrint('Gemini: $cause');
      throw PrescriptionReadException('الرد رجع بشكل غريب — صوّر تاني.', cause);
    }
  }

  /// أول ٨٠٠ حرف — كفاية عشان نقرا رسالة الخطأ من غير ما نغرق اللوج.
  static String _excerpt(String body, [int max = 800]) =>
      body.length <= max ? body : '${body.substring(0, max)}…';

  Map<String, dynamic> _request(
    Uint8List image,
    String mimeType,
    String prompt,
    Map<String, dynamic> schema,
    String? systemInstruction,
  ) =>
      {
        if (systemInstruction != null)
          'systemInstruction': {
            'parts': [
              {'text': systemInstruction},
            ],
          },
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
          'responseSchema': schema,
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
