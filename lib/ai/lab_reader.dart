import 'dart:typed_data';

import 'gemini_config.dart';
import 'lab_reading.dart';
import 'prescription_reader.dart';

/// بيقرا صورة تقرير تحليل — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class LabReportReader {
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// نفس نقل Gemini بتاع الروشتة ([GeminiPrescriptionReader.generate]).
class GeminiLabReader implements LabReportReader {
  GeminiLabReader(GeminiConfig config, {GeminiPrescriptionReader? transport})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  @override
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    final result = await _transport.generate(
      image: image,
      mimeType: mimeType,
      prompt: prompt,
      schema: labSchema,
      systemInstruction: systemInstruction,
      failure: 'مقدرتش أقرا التقرير دلوقتي — صوّر تاني.',
    );
    final reading = LabReading.fromJson(result.json);
    return result.warning == null ? reading : reading.withModelWarning(result.warning!);
  }

  /// **القاعدة ٦ مكتوبة للموديل نفسه.** بينقل أرقام وبس: مفيش نطاق مرجعي،
  /// مفيش علامة، مفيش تفسير، مفيش نصيحة. اختبار بيثبّت الجمل دي.
  static const systemInstruction = '''
You transcribe numbers from a photo of a medical lab report. You are not a doctor and you never act like one.
Return ONLY: the lab name, the report date, and for each test its name exactly as printed, its numeric result, and its unit.
Do NOT return reference ranges. Do NOT return H/L or high/low flags or asterisks.
Do NOT interpret, diagnose, recommend, or advise. Never say a value is high, low, normal, abnormal, dangerous or concerning.
Never suggest seeing a doctor, repeating a test, or any action.
If a value is not a number or is illegible, return null for it with confidence 0. Never guess a digit.
''';

  static const prompt = '''
Read the attached lab report. For each result row return test (name as printed, keep Latin names in Latin), value (the number only), unit (as printed).
lab: the laboratory name if printed. reportDate: YYYY-MM-DD only if a date is printed.
confidence is 0..1 per field based on legibility. Below 0.8 means a human must check it.
Do not add, merge, rename or skip rows.
''';
}
