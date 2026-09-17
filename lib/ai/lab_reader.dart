import 'dart:typed_data';

import 'ai_session.dart';
import 'lab_reading.dart';
import 'prescription_reader.dart';

/// بيقرا صورة تقرير تحليل — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class LabReportReader {
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// نفس نقل الروشتة ([GeminiPrescriptionReader.generate]) بـ`kind: lab`.
///
/// البرومبت وتعليمة «انقل أرقام وبس، من غير أي تفسير» (القاعدة ٦) والـschema
/// بقوا في `supabase/functions/ai-read/index.ts` من بعد C2 —
/// و`test/ai/ai_read_function_test.dart` بيقرا الملف ده وبيثبّتهم هناك.
class GeminiLabReader implements LabReportReader {
  GeminiLabReader(AiSession session, {GeminiPrescriptionReader? transport})
      : _transport = transport ?? GeminiPrescriptionReader(session);

  final GeminiPrescriptionReader _transport;

  @override
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    final result = await _transport.generate(
      image: image,
      mimeType: mimeType,
      kind: 'lab',
      failure: 'مقدرتش أقرا التقرير دلوقتي — صوّر تاني.',
    );
    final reading = LabReading.fromJson(result.json);
    return result.warning == null ? reading : reading.withModelWarning(result.warning!);
  }
}
