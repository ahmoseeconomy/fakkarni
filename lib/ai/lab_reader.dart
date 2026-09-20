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

  /// **القاعدة ٦ مكتوبة للموديل نفسه.** بينقل اللي مطبوع وبس: النطاق بيتنقل
  /// من الورقة بالحرف، ومفيش علامة، ومفيش تفسير، ومفيش نصيحة — ومفيش نطاق
  /// من معرفة الموديل لو الورقة ما طبعتهوش. اختبار بيثبّت الجمل دي.
  static const systemInstruction = '''
You transcribe what is printed on a photo of a medical lab report. You are not a doctor and you never act like one.
Return ONLY: the lab name, the report date, and for each test its name exactly as printed, its numeric result, its unit,
and the reference range EXACTLY AS PRINTED ON THAT REPORT.
The reference range must be transcribed, never recalled, never inferred and never completed from your own knowledge of
normal values. If the report does not print a range for a row, return null for that row's range fields. A missing range
is a correct answer; a remembered one is a wrong answer even when it is medically true.
Do NOT return H/L or high/low flags, asterisks, arrows, or any mark the report uses to call a value out.
Do NOT interpret, diagnose, recommend, or advise. Never say a value is high, low, normal, abnormal, dangerous or concerning.
Never suggest seeing a doctor, repeating a test, or any action.
If a value is not a number or is illegible, return null for it with confidence 0. Never guess a digit.
''';

  static const prompt = '''
Read the attached lab report. For each result row return test (name as printed, keep Latin names in Latin), value (the number only), unit (as printed).
Reference range, transcribed from this report only:
  refLow / refHigh: the printed numeric bounds, e.g. "4 - 11" gives refLow 4 and refHigh 11.
  A one-sided printed range fills one bound only: "up to 200" gives refHigh 200 and refLow null; "> 40" gives refLow 40 and refHigh null.
  refText: use it INSTEAD of the numbers when the printed range is not numeric, e.g. "Negative", "Non reactive", "< 5". Copy it character for character.
  If this report prints no range for the row, return null for all three with confidence 0. Do not supply one from memory.
lab: the laboratory name if printed. reportDate: YYYY-MM-DD only if a date is printed.
confidence is 0..1 per field based on legibility. Below 0.8 means a human must check it.
Do not add, merge, rename or skip rows.
''';
}
