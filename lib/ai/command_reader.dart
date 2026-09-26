import 'dart:async';

import '../core/diagnostics.dart';
import 'gemini_config.dart';
import 'prescription_reader.dart';

/// اللي السحابة بترجّعه عن طلب مسموع — **الكلام المكتوب بس بيروح، وبس.**
///
/// مفيش اسم مريض، ولا سن، ولا قايمة أدوية، ولا روتين، ولا أي حاجة تانية في
/// الطلب — `command_reader_test` بيمسك جسم الطلب نفسه ويثبت ده. المطابقة على
/// أدوية المريض بتحصل **بعدها على الموبايل** (`matchMedication`).
class CloudCommand {
  const CloudCommand({required this.intent, this.medNameAsSpoken, this.timingWords, this.patternWords});

  /// واحد من [intents] — أي حاجة تانية = الرد كله مرفوض.
  final String intent;
  final String? medNameAsSpoken;
  final String? timingWords;
  final String? patternWords;

  static const intents = {'mark_taken', 'next_dose', 'today_list', 'add_med', 'medical_question', 'unknown'};
  static const keys = {'intent', 'med_name_as_spoken', 'timing_words', 'pattern_words'};

  /// صارم: المفاتيح الأربعة بالظبط، ولا مفتاح زيادة، والقيم نص أو null،
  /// والنية من القايمة. أي حاجة تانية = null (= مش مفهوم).
  static CloudCommand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw.keys.toSet().difference(keys).isNotEmpty) return null;
    if (!keys.every(raw.containsKey)) return null;
    final intent = raw['intent'];
    if (intent is! String || !intents.contains(intent)) return null;
    String? str(String k) {
      final v = raw[k];
      if (v == null) return null;
      if (v is! String) throw const FormatException('not a string');
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    try {
      return CloudCommand(
        intent: intent,
        medNameAsSpoken: str('med_name_as_spoken'),
        timingWords: str('timing_words'),
        patternWords: str('pattern_words'),
      );
    } on FormatException {
      return null;
    }
  }
}

/// نتيجة سؤال السحابة: فهمت ([command])، أو ما فهمتش (الاتنين null)، أو
/// **مقدرناش** ([error]: مهلة، شبكة، رد بايظ) — الفرق بين «معلش مافهمتش»
/// و«كمّل بإيدك». الكود التقني في [error] للسجل بس، عمره ما يوصل الشاشة.
class CloudReadResult {
  const CloudReadResult({this.command, this.error, this.latency = Duration.zero});
  final CloudCommand? command;
  final String? error;
  final Duration latency;
  bool get failed => error != null;
}

/// بيفهم طلب من الكلام المكتوب — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class VoiceCommandReader {
  Future<CloudReadResult> read(String transcript);
}

/// **الخطوة (ج)**: بس لو القارئ المحلي ما فهمش، وفيه نت، والحد اليومي لسه.
///
/// نفس نقل Gemini بتاع الروشتة ([GeminiPrescriptionReader.generateText]) —
/// نفس المفتاح ونفس الموديل — ببرومبت نص بس (مفيش صورة) وschema صارم.
/// **المفتاح الحالي (مجاني، في التطبيق) مش للاستخدام مع بيانات مرضى
/// حقيقيين** — مفتاح مدفوع قبل النشر (الدين 2b). عشان كده الطلب ما فيهوش
/// غير الكلام المكتوب.
class GeminiCommandReader implements VoiceCommandReader {
  GeminiCommandReader(GeminiConfig config, {GeminiPrescriptionReader? transport, this.timeout = const Duration(seconds: 8)})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  /// ٨ ثواني — أطول من كده الراجل واقف بيستنّى، و«كمّل بإيدك» أحسن.
  final Duration timeout;

  /// عمرها ما بترمي: كل عطل بيرجع [CloudReadResult.error] بكوده — والكلام
  /// المكتوب نفسه **ما بيتكتبش** في أي سجل.
  @override
  Future<CloudReadResult> read(String transcript) async {
    final started = DateTime.now();
    Duration elapsed() => DateTime.now().difference(started);
    try {
      final json = await _transport
          .generateText(
            prompt: promptFor(transcript),
            schema: schema,
            systemInstruction: systemInstruction,
            failure: 'cloud',
          )
          .timeout(timeout);
      final command = CloudCommand.fromJson(json);
      if (command == null) diag('Cmd: cloud رد برّه الشكل المتفق — اتعامل معاه كمش مفهوم (${elapsed().inMilliseconds}ms)');
      return CloudReadResult(command: command, latency: elapsed());
    } on TimeoutException {
      return CloudReadResult(error: 'timeout', latency: elapsed());
    } on PrescriptionReadException catch (e) {
      final cause = e.cause?.toString() ?? '';
      final code = cause.startsWith('HTTP') ? cause.split(':').first.replaceAll(' ', '_').toLowerCase() : (cause.startsWith('parse') ? 'invalid_json' : 'transport');
      return CloudReadResult(error: code, latency: elapsed());
    } catch (e) {
      return CloudReadResult(error: 'error_${e.runtimeType}', latency: elapsed());
    }
  }

  /// الطلب كله: الكلام المكتوب وسطر تعريف — **ولا حاجة تانية عن المريض.**
  static String promptFor(String transcript) =>
      'The patient said (Egyptian Arabic, from speech recognition, may have errors):\n"""$transcript"""';

  static const schema = <String, dynamic>{
    'type': 'OBJECT',
    'properties': {
      'intent': {
        'type': 'STRING',
        'enum': ['mark_taken', 'next_dose', 'today_list', 'add_med', 'medical_question', 'unknown'],
      },
      'med_name_as_spoken': {'type': 'STRING', 'nullable': true},
      'timing_words': {'type': 'STRING', 'nullable': true},
      'pattern_words': {'type': 'STRING', 'nullable': true},
    },
    'required': ['intent', 'med_name_as_spoken', 'timing_words', 'pattern_words'],
  };

  /// القاعدة ٦ مكتوبة للموديل: أي سؤال طبي = medical_question، ولا كلمة نصيحة.
  static const systemInstruction = '''
You classify ONE short spoken request from an elderly Egyptian patient using a medication-reminder app. You are not a doctor and you never give medical advice.
Return ONLY the JSON object. Nothing else.

intent must be exactly one of:
- "mark_taken": the patient says they took a medicine now ("أخدت دوا الضغط", "خدت الدوا").
- "next_dose": asks what or when the next medicine is ("إيه دوايا الجاي", "الدوا الجاي إمتى").
- "today_list": asks for today's medicines ("إيه أدويتي النهارده").
- "add_med": asks to add a medicine ("ضيفلي دوا الضغط الصبح بعد الفطار").
- "medical_question": ANY question or statement about dosage, changing or stopping a medicine, side effects, symptoms, interactions, whether something is safe, what a medicine is for, or a diagnosis. When in doubt between medical_question and anything else, choose medical_question.
- "unknown": anything else.

med_name_as_spoken: the medicine name or purpose word exactly as the patient said it (e.g. "الضغط", "الكونكور"), or null.
timing_words: the timing words exactly as said (e.g. "الصبح بعد الفطار", "قبل النوم", "الساعة تمانية"), or null.
pattern_words: how often, exactly as said (e.g. "مرتين في اليوم", "كل تمن ساعات", "مرة واحدة"), or null.

Never invent a medicine name, a time, a dose or a frequency that was not said. Never add advice, comments or extra fields.
''';
}
