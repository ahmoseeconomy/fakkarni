import 'dart:async';

import '../core/diagnostics.dart';
import 'gemini_config.dart';
import 'prescription_reader.dart';

/// **استخراج منظّم بأدوات** («كلّمني» v2): السحابة بتختار أداة واحدة من
/// [CloudTool.tools] وبتملى خاناتها — **من الكلام المكتوب وتاريخ النهارده
/// وبس**. مفيش اسم مريض، ولا سن، ولا قايمة أدوية، ولا روتين في الطلب —
/// `command_reader_test` بيمسك جسم الطلب نفسه ويثبت ده. المطابقة على أدوية
/// المريض والتنفيذ بيحصلوا **بعدها على الموبايل** (`cloud_tools.dart`).
class CloudTool {
  const CloudTool({required this.tool, this.args = const {}});

  /// واحدة من [tools] — أي حاجة تانية = الرد كله مرفوض.
  final String tool;

  /// الخانات زي ما جت (نص / رقم / قايمة / null) — التحقق الصارم لكل أداة في
  /// `commandFromCloudTool`.
  final Map<String, Object?> args;

  static const tools = {
    'add_medication',
    'add_appointment',
    'mark_taken',
    'snooze',
    'add_vital',
    'add_doctor_question',
    'mark_bought',
    'next_dose',
    'today_list',
    'upcoming_appointments',
    'stock_status',
    'medical_question',
    'unknown',
  };

  /// كل الخانات المسموحة — مفتاح تاني = الرد كله مرفوض.
  static const argKeys = {
    'name', 'dose', 'times', 'meal_relation', 'pattern', 'every_hours', 'weekdays', 'duration_days', 'start_date',
    'kind', 'with_whom', 'date', 'time', 'place', 'note',
    'med_name', 'minutes', 'vital_type', 'values', 'text',
  };

  static bool _scalarOk(Object? v) => v == null || v is String || v is num;

  /// صارم: `tool` من القايمة، كل المفاتيح التانية من [argKeys]، والقيم نص أو
  /// رقم أو قايمة نصوص/أرقام أو null. أي حاجة تانية = null (= مش مفهوم).
  static CloudTool? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tool = raw['tool'];
    if (tool is! String || !tools.contains(tool)) return null;
    final args = <String, Object?>{};
    for (final entry in raw.entries) {
      final k = entry.key;
      if (k == 'tool') continue;
      if (k is! String || !argKeys.contains(k)) return null;
      final v = entry.value;
      if (v is List) {
        if (!v.every(_scalarOk) || v.any((e) => e == null)) return null;
        if (v.isNotEmpty) args[k] = List<Object>.from(v);
        continue;
      }
      if (!_scalarOk(v)) return null;
      if (v is String) {
        final t = v.trim();
        if (t.isNotEmpty) args[k] = t;
        continue;
      }
      if (v != null) args[k] = v;
    }
    return CloudTool(tool: tool, args: args);
  }
}

/// نتيجة سؤال السحابة: فهمت ([tool])، أو ما فهمتش (الاتنين null)، أو
/// **مقدرناش** ([error]: مهلة، شبكة، رد بايظ) — الفرق بين «معلش مافهمتش»
/// و«كمّل بإيدك». الكود التقني في [error] للسجل بس، عمره ما يوصل الشاشة.
class CloudReadResult {
  const CloudReadResult({this.tool, this.error, this.latency = Duration.zero});
  final CloudTool? tool;
  final String? error;
  final Duration latency;
  bool get failed => error != null;
}

/// بيفهم طلب من الكلام المكتوب — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class VoiceCommandReader {
  /// [now] بيروح للسحابة كتاريخ النهارده ويومه — عشان «يوم الحد» تبقى تاريخ.
  Future<CloudReadResult> read(String transcript, {DateTime? now});
}

/// **الخطوة (ج)**: بس لو القارئ المحلي ما فهمش، وفيه نت، والحد اليومي لسه.
///
/// نفس نقل Gemini بتاع الروشتة ([GeminiPrescriptionReader.generateText]) —
/// نفس المفتاح ونفس الموديل — ببرومبت نص بس (مفيش صورة) وschema صارم.
/// **المفتاح الحالي (مجاني، في التطبيق) مش للاستخدام مع بيانات مرضى
/// حقيقيين** — مفتاح مدفوع قبل النشر (الدين 2b). عشان كده الطلب ما فيهوش
/// غير الكلام المكتوب وتاريخ النهارده.
class GeminiCommandReader implements VoiceCommandReader {
  GeminiCommandReader(GeminiConfig config, {GeminiPrescriptionReader? transport, this.timeout = const Duration(seconds: 8)})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  /// ٨ ثواني — أطول من كده الراجل واقف بيستنّى، و«كمّل بإيدك» أحسن.
  final Duration timeout;

  /// عمرها ما بترمي: كل عطل بيرجع [CloudReadResult.error] بكوده — والكلام
  /// المكتوب نفسه **ما بيتكتبش** في أي سجل.
  @override
  Future<CloudReadResult> read(String transcript, {DateTime? now}) async {
    final started = DateTime.now();
    Duration elapsed() => DateTime.now().difference(started);
    try {
      final json = await _transport
          .generateText(
            prompt: promptFor(transcript, now ?? DateTime.now()),
            schema: schema,
            systemInstruction: systemInstruction,
            failure: 'cloud',
          )
          .timeout(timeout);
      final tool = CloudTool.fromJson(json);
      if (tool == null) diag('Cmd: cloud رد برّه الشكل المتفق — اتعامل معاه كمش مفهوم (${elapsed().inMilliseconds}ms)');
      return CloudReadResult(tool: tool, latency: elapsed());
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

  static const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  /// «2026-09-26 (Saturday)».
  static String dateLine(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} (${_weekdayNames[now.weekday - 1]})';

  /// الطلب كله: الكلام المكتوب وتاريخ النهارده — **ولا حاجة تانية عن المريض.**
  static String promptFor(String transcript, DateTime now) =>
      'Today is ${dateLine(now)}.\nThe patient said (Egyptian Arabic, from speech recognition, may have errors):\n"""$transcript"""';

  static const _nullable = {'type': 'STRING', 'nullable': true};
  static const _nullableInt = {'type': 'INTEGER', 'nullable': true};
  static const _stringList = {'type': 'ARRAY', 'items': {'type': 'STRING'}, 'nullable': true};

  static const schema = <String, dynamic>{
    'type': 'OBJECT',
    'properties': {
      'tool': {'type': 'STRING', 'enum': [
        'add_medication', 'add_appointment', 'mark_taken', 'snooze', 'add_vital', 'add_doctor_question', 'mark_bought',
        'next_dose', 'today_list', 'upcoming_appointments', 'stock_status', 'medical_question', 'unknown',
      ]},
      'name': _nullable,
      'dose': _nullable,
      'times': _stringList,
      'meal_relation': _nullable,
      'pattern': _nullable,
      'every_hours': _nullableInt,
      'weekdays': {'type': 'ARRAY', 'items': {'type': 'INTEGER'}, 'nullable': true},
      'duration_days': _nullableInt,
      'start_date': _nullable,
      'kind': _nullable,
      'with_whom': _nullable,
      'date': _nullable,
      'time': _nullable,
      'place': _nullable,
      'note': _nullable,
      'med_name': _nullable,
      'minutes': _nullableInt,
      'vital_type': _nullable,
      'values': {'type': 'ARRAY', 'items': {'type': 'NUMBER'}, 'nullable': true},
      'text': _nullable,
    },
    'required': ['tool'],
  };

  /// القاعدة ٦ مكتوبة للموديل: أي سؤال طبي = medical_question، ولا كلمة نصيحة.
  static const systemInstruction = '''
You extract ONE tool call from a short spoken request by an elderly Egyptian patient using a medication-reminder app. You are not a doctor and you never give medical advice.
Return ONLY the JSON object. Nothing else. Use null (or omit) for anything not said. NEVER invent a medicine name, a time, a dose, a date or a frequency that was not said.

tool must be exactly one of:
- "add_medication": add a medicine. name (as said), dose (as said, e.g. "قرص", "نص قرص"), times as clock strings "HH:MM" 24h (e.g. "الساعة ٩ بالليل" → ["21:00"]), meal_relation as one of: before_meal, with_meal, after_meal, empty_stomach — ONLY when the patient relates the dose to eating (e.g. "بعد الفطار" → after_meal); it is an instruction label, never a time, so do not turn a meal word into a clock time. pattern: "daily" | "every_n_hours" (then every_hours) | "weekdays" (then weekdays: 1=Monday … 7=Sunday) | "once". duration_days, start_date "YYYY-MM-DD" (resolve بكرة / الأسبوع الجاي from today's date).
- "add_appointment": book a visit. kind: "doctor" | "lab" | "scan" | "other". with_whom (doctor's name if said), date "YYYY-MM-DD" resolved from today's date and weekday (يوم الحد = the next Sunday), time "HH:MM" only if a day part makes it unambiguous, place, note.
- "mark_taken": the patient says they took a medicine now. med_name as said (or null).
- "snooze": remind later. minutes if said.
- "add_vital": a measurement with numbers. vital_type: "bp" | "sugar" | "pulse" | "weight" | "temp" | "o2". values: the numbers as said (bp: [systolic, diastolic, pulse?]).
- "add_doctor_question": something to ask the doctor. text as said.
- "mark_bought": the patient bought a medicine. med_name.
- "next_dose", "today_list", "upcoming_appointments", "stock_status": read-only questions.
- "medical_question": ANY question or statement about dosage, changing or stopping a medicine, side effects, symptoms, interactions, whether something is safe, what a medicine is for, whether a reading is high or low, or a diagnosis. When in doubt between medical_question and anything else, choose medical_question.
- "unknown": anything else.

Never add advice, comments or extra fields.
''';
}
