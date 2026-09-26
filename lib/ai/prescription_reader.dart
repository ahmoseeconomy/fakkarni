import 'dart:async';
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

/// محاولة واحدة عند جوجل: الحالة، نص الرد، وهل المهلة خلصت.
/// `status = 0` معناها ما وصلناش لرد أصلاً.
typedef _Attempt = ({int status, String raw, bool timedOut});

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
  GeminiPrescriptionReader(this.config, {http.Client? client, Duration? attemptTimeout})
      : _client = client ?? http.Client(),
        _attemptTimeout = attemptTimeout ?? GeminiPrescriptionReader.attemptTimeout {
    if (config.apiKey.trim().isEmpty) {
      throw StateError(GeminiConfig.missingKeyMessage);
    }
  }

  final GeminiConfig config;
  final http.Client _client;

  /// للاختبارات — المهلة الحقيقية [attemptTimeout].
  final Duration _attemptTimeout;

  /// مهلة النداء الواحد عند جوجل. محاولتين على الأكتر (المثبّت والبديل)،
  /// فالأسوأ بيفضل تحت [readTimeout].
  static const attemptTimeout = Duration(seconds: 35);

  /// سقف القراية كلها من ناحية المستخدم — محاولتين بمهلتهم.
  static const readTimeout = Duration(seconds: 75);

  /// جملة الزحمة: الصورة سليمة، والمشكلة عند الخدمة.
  static const busyMessage = 'الخدمة زحمة دلوقتي — استنى شوية وجرّب تاني.';

  /// الموديل ده رفض `thinkingConfig`؟ بيتفتكر للجلسة — فالثمن محاولة واحدة
  /// زيادة أول مرة، مش في كل قراية.
  static bool _thinkingRejected = false;

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
    //
    // واللوج بيتطبع **هنا**، مش جوّه العزلة: `debugPrint` هناك ما بيوصلش
    // ترمنال `flutter run`. العزلة بترجّع التقرير مع البايتات.
    final report = mayNeedShrinkForAi(image)
        ? await compute(shrinkForAiOrNull, image)
        : unchangedShrinkReport(image);
    debugPrint('Gemini: ${describeShrink(report)}');
    final shrunk = report.bytes ?? image;
    final wireType = report.bytes == null ? mimeType : 'image/jpeg';
    String bodyFor(bool thinking) => jsonEncode(
          _request(shrunk, wireType, prompt, schema, systemInstruction,
              thinking ? config.thinkingBudget : null),
        );

    final started = DateTime.now();

    // التفكير مقفول افتراضياً، **إلا لو الموديل رفض الحقل**: الرفض ٤٠٠ فوري
    // (من غير أي شغل موديل)، فبنعيد مرة من غيره وبنفتكر للجلسة دي. ده **مش**
    // إخفاء ٤٠٠ — مربوط باسم الحقل بالحرف وبيتسجّل، ورفض الـschema بيفضل
    // بيطلع زي ما هو.
    final sendThinking = config.thinkingBudget != null && !_thinkingRejected;
    var res = await _post(config.model, bodyFor(sendThinking));
    if (sendThinking && res.status == 400 && res.raw.toLowerCase().contains('thinking')) {
      _thinkingRejected = true;
      debugPrint('Gemini: WARNING ${config.model} رفض thinkingConfig — إعادة من غيره: '
          '${_excerpt(res.raw, 200)}');
      res = await _post(config.model, bodyFor(false));
    }
    final body = bodyFor(sendThinking && !_thinkingRejected);

    String? warning;
    final reason = _fallbackReason(res.status, res.raw, res.timedOut);
    if (reason != null) {
      debugPrint('Gemini: WARNING pinned model ${config.model} $reason '
          '(HTTP ${res.status}): ${_excerpt(res.raw, 200)} — retrying once with ${config.fallbackModel}');
      warning = reason == 'retired'
          ? 'الموديل المثبّت ${config.model} اتقفل — '
              'القراءة جت من ${config.fallbackModel}. ثبّت تاني بإيدك. '
              '(${_excerpt(res.raw, 200)})'
          // زحمة أو مهلة: الموديل سليم، مفيش حاجة تتثبّت من جديد.
          : 'الموديل المثبّت ${config.model} كان بطيء أو زحمة — '
              'القراءة جت من ${config.fallbackModel}.';
      res = await _post(config.fallbackModel, body);
    }

    final elapsed = DateTime.now().difference(started).inMilliseconds;
    debugPrint('Gemini: ${res.status} في ${elapsed}ms (رفع + موديل)');

    if (res.status != 200) {
      // السبب الحقيقي بيتسجّل هنا — مش بنخمّن. المفتاح عمره ما بيتطبع.
      final cause = 'HTTP ${res.status}: ${_excerpt(res.raw)}'
          '${warning == null ? '' : ' (after fallback ${config.fallbackModel})'}';
      debugPrint('Gemini: $cause');
      // زحمة أو مهلة **مش** «صوّر تاني»: الصورة سليمة والمشكلة عندهم، وإعادة
      // التصوير مش هتحل حاجة.
      final busy = res.timedOut || res.status == 503 || res.status == 429;
      throw PrescriptionReadException(busy ? busyMessage : failure, cause);
    }

    return (json: _parse(res.raw), warning: warning);
  }

  /// **نص بس** (المرحلة ٣ — طلب مسموع): نفس المفتاح ونفس الرأس ونفس الموديل،
  /// من غير صورة ومن غير رجوع لبديل: محاولة واحدة، واللي بينده بيحط مهلته.
  /// الجسم فيه [prompt] وبس — ولا بايت زيادة عن اللي اتبعت هنا.
  Future<Map<String, dynamic>> generateText({
    required String prompt,
    required Map<String, dynamic> schema,
    required String failure,
    String? systemInstruction,
  }) async {
    final body = jsonEncode({
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
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0,
        'responseMimeType': 'application/json',
        'responseSchema': schema,
        if (config.thinkingBudget != null && !_thinkingRejected) 'thinkingConfig': {'thinkingBudget': config.thinkingBudget},
      },
    });
    final res = await _post(config.model, body);
    if (res.status != 200) {
      final cause = 'HTTP ${res.status}: ${_excerpt(res.raw)}';
      debugPrint('Gemini: $cause');
      throw PrescriptionReadException(failure, cause);
    }
    return _parse(res.raw);
  }

  Future<_Attempt> _post(String model, String body) async {
    try {
      final response = await _client
          .post(
            endpointFor(model),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': config.apiKey,
            },
            body: body,
          )
          .timeout(_attemptTimeout);
      return (
        status: response.statusCode,
        raw: utf8.decode(response.bodyBytes, allowMalformed: true),
        timedOut: false,
      );
    } on TimeoutException {
      // **مهلة صريحة.** من غيرها الطلب بيفضل معلّق على الشبكة والشاشة قاعدة
      // على «بيقرا الروشتة…» بالدقايق من غير ما تقول حاجة. والمهلة سبب بديل
      // زي الزحمة: الموديل اللي سكت بياخد فرصة واحدة على التاني.
      debugPrint('Gemini: مهلة $model بعد ${_attemptTimeout.inSeconds}ث');
      return (status: 0, raw: 'timeout بعد ${_attemptTimeout.inSeconds}ث', timedOut: true);
    } catch (error) {
      debugPrint('Gemini: transport: $error');
      throw PrescriptionReadException('مفيش نت دلوقتي — جرّب تاني بعد شوية.', error);
    }
  }

  /// إمتى المثبّت يسيب مكانه للبديل — **مرة واحدة**، وبصوت عالي.
  ///
  ///   retired     ٤٠٤ + NOT_FOUND — جوجل قفلت الموديل. لازم تثبيت جديد بالإيد.
  ///   overloaded  ٥٠٣ أو ٤٢٩ — تحت ضغط أو الحصة خلصت دلوقتي.
  ///   timeout     المهلة خلصت من غير رد.
  ///
  /// ٤٠٠ **مش هنا**: إخفاء رفض الـschema هو بالظبط تغيّر السلوك الصامت اللي
  /// التثبيت موجود عشان يمنعه.
  static String? _fallbackReason(int status, String body, bool timedOut) {
    if (timedOut) return 'timeout';
    if (status == 404 && body.contains('NOT_FOUND')) return 'retired';
    if (status == 503 || status == 429) return 'overloaded';
    return null;
  }

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
    int? thinkingBudget,
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
          if (thinkingBudget != null) 'thinkingConfig': {'thinkingBudget': thinkingBudget},
        },
      };

  /// التعليمات — القاعدة السادسة مكتوبة للموديل نفسه: ما تخمّنش.
  static const prompt = '''
You are reading a photo of a paper medical prescription from Egypt (Arabic and/or English, often handwritten).
Extract ONLY what is literally written. Never guess, infer, or complete anything.

First, read the paper's own header — these three are about the prescription, not about any medicine:
- doctor: the prescribing doctor's name as printed.
- clinic: the clinic or hospital name as printed — usually the letterhead at the top.
- issuedAt: the date written on the paper, as "YYYY-MM-DD".
If one of them is not written on the paper, return value null with confidence 1. A missing one is NOT an error and must never be guessed or filled from today's date.

For each medication line return: name (as written, keep Latin drug names in Latin), amount (e.g. "قرص واحد", "1 tablet", "5 ml"), timing, durationDays, instructions.

Timing rules:
- Prefer meal-relative timing: anchor ∈ {wake, breakfast, lunch, dinner, sleep}, relation ∈ {before, after, at}, offsetMinutes only if a number of minutes is written.
- "1×3" / "3 times daily" style with no meal named: set timesPerDay and leave anchor null.
- Set clockTime "HH:MM" (24h) ONLY if an explicit clock time is written on the paper.
- If timing is unclear, illegible, or "when needed": leave anchor, clockTime and timesPerDay null, set a low confidence, and set note to "مش متأكد — اسأل الصيدلي".

durationDays: ONLY if a duration is written ("لمدة ٧ أيام" → 7, "for 5 days" → 5). "اليوم فقط" / "مرة واحدة" / "single dose" means one day → 1. If not written, value must be null with confidence 1 — a missing duration is not an error.

instructions: a handling note written on the line that is neither timing nor amount (e.g. "مع كوباية مية كاملة", "بعد الأكل مباشرة", "ماتاخدوش على معدة فاضية"), copied as written. If none is written, value must be null with confidence 1. Never invent one.

confidence is 0..1 for each field based on legibility. Below 0.8 means a human must check it.
Do not add, remove, rename or substitute any medication. Do not give medical advice.
''';
}
