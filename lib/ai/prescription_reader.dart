import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;

import '../core/images/shrink_for_ai.dart';
import 'ai_session.dart';
import 'prescription_reading.dart';

/// بيقرا صورة روشتة وبيرجّع اقتراح — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class PrescriptionReader {
  Future<PrescriptionReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// القراءة فشلت — رسالة جاهزة للمستخدم، والسبب التقني في [cause].
class PrescriptionReadException implements Exception {
  const PrescriptionReadException(this.message, [this.cause, this.needsSignIn = false]);

  /// مفيش جلسة (أو السحابة رفضتها ٤٠١) — الشاشة بتعرض باب الدخول بدل «صوّر تاني».
  const PrescriptionReadException.signInRequired([Object? cause])
      : this(signInLine, cause, true);

  /// السطر الواحد الصريح — القراية بالصورة محتاجة حساب من بعد C2.
  static const signInLine = 'سجّل دخول عشان نقرا الروشتة';

  final String message;
  final Object? cause;
  final bool needsSignIn;

  @override
  String toString() => 'PrescriptionReadException($message${cause == null ? '' : '، $cause'})';
}

/// القارئ: بينادي دالتنا `ai-read` بجلسة المستخدم — **من غير أي مفتاح**.
///
/// قبل C2 الملف ده كان بيكلّم جوجل مباشرة بمفتاح متترجم جوّه التطبيق. دلوقتي
/// المفتاح، والبرومبت، والـschema، وتثبيت الموديل وبديله — كلهم في
/// `supabase/functions/ai-read/index.ts`. اللي فضل هنا: تصغير الصورة (C1)،
/// الطلب، وترجمة الرد لحالات الشاشة. **فك الرد والحكم على الثقة زي ما هم** —
/// الدالة بترجّع رد الموديل بالحرف.
class GeminiPrescriptionReader implements PrescriptionReader {
  GeminiPrescriptionReader(this.session, {http.Client? client}) : _client = client ?? http.Client();

  final AiSession session;
  final http.Client _client;

  @override
  Future<PrescriptionReading> read(
    Uint8List image, {
    String mimeType = 'image/jpeg',
  }) async {
    final result = await generate(
      image: image,
      mimeType: mimeType,
      kind: 'prescription',
      failure: 'مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.',
    );
    final reading = PrescriptionReading.fromJson(result.json);
    return result.warning == null ? reading : reading.withModelWarning(result.warning!);
  }

  /// النقل المشترك (D3.6): الروشتة والتحليل نفس الطريق. [kind] هو كل اللي
  /// بيختار البرومبت — العميل ما بيبعتش برومبت، فجلسة مسروقة ما تقدرش تحوّل
  /// مفتاحنا لبروكسي عام.
  Future<({Map<String, dynamic> json, String? warning})> generate({
    required Uint8List image,
    required String mimeType,
    required String kind,
    required String failure,
  }) async {
    // مفيش جلسة → مفيش طلب. الصورة ما بتتصغّرش ولا بتطلع من الموبايل.
    final token = await session.accessToken();
    if (token == null) throw const PrescriptionReadException.signInRequired('no session');

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

    final body = jsonEncode({'kind': kind, 'mime': wireType, 'image': base64Encode(shrunk)});

    final http.Response response;
    try {
      response = await _client.post(
        session.endpoint,
        headers: {
          'Content-Type': 'application/json',
          'apikey': session.publishableKey,
          'Authorization': 'Bearer $token',
        },
        body: body,
      );
    } catch (error) {
      debugPrint('Gemini: transport: $error');
      throw PrescriptionReadException('مفيش نت دلوقتي — جرّب تاني بعد شوية.', error);
    }
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      // السبب الحقيقي بيتسجّل — مش بنخمّن. التوكن عمره ما بيتطبع.
      final cause = 'HTTP ${response.statusCode}: ${_excerpt(raw)}';
      debugPrint('Gemini: $cause');
      switch (response.statusCode) {
        case 401:
          throw PrescriptionReadException.signInRequired(cause);
        case 429:
          // جملة السحابة زي ما هي — هي اللي عارفة أنهي حد اتقفل.
          throw PrescriptionReadException(_serverMessage(raw) ?? failure, cause);
        default:
          throw PrescriptionReadException(failure, cause);
      }
    }

    return (json: _parse(raw), warning: _warningFrom(response.headers['x-model-warning']));
  }

  /// `x-model-warning: <المثبّت>;<البديل>` — الـheader ASCII بس، فالجملة
  /// بتتبني هنا. نص رد جوجل نفسه في لوج الدالة.
  static String? _warningFrom(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final parts = header.split(';');
    final pinned = parts.first.trim();
    final fallback = parts.length > 1 ? parts[1].trim() : '';
    debugPrint('Gemini: WARNING pinned model $pinned retired — read came from $fallback');
    return 'الموديل المثبّت $pinned اتقفل — القراءة جت من $fallback. ثبّت تاني بإيدك.';
  }

  static String? _serverMessage(String raw) {
    try {
      final message = (jsonDecode(raw) as Map<String, dynamic>)['message'];
      return message is String && message.trim().isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
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
}
