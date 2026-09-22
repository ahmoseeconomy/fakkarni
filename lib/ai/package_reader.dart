import 'dart:typed_data';

import 'gemini_config.dart';
import 'package_reading.dart';
import 'prescription_reader.dart';

/// بيقرا صورة علبة دوا أو شريط — واجهة عشان الشاشات تتختبر من غير شبكة.
abstract interface class MedicinePackageReader {
  Future<PackageReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// **نفس نقل Gemini بتاع الروشتة بالحرف** ([GeminiPrescriptionReader.generate]):
/// نفس الموديل، نفس المهلة، نفس الرجوع للبديل على ٥٠٣/٤٢٩/تقاعد الموديل،
/// ونفس رسايل الأعطال. سطح شبكة جديد مش موجود هنا — برومبت مختلف وبس.
class GeminiPackageReader implements MedicinePackageReader {
  GeminiPackageReader(GeminiConfig config, {GeminiPrescriptionReader? transport})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  @override
  Future<PackageReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    final result = await _transport.generate(
      image: image,
      mimeType: mimeType,
      prompt: prompt,
      schema: packageSchema,
      systemInstruction: systemInstruction,
      failure: 'مقدرتش أقرا العلبة دلوقتي — صوّر تاني.',
    );
    final reading = PackageReading.fromJson(result.json);
    return result.warning == null ? reading : reading.withModelWarning(result.warning!);
  }

  /// **القاعدة ٤ والقاعدة ٦ مكتوبين للموديل نفسه.**
  ///
  /// العلبة بتقول الدوا إيه، مش الراجل ده بياخده إمتى ولا قد إيه. الجملة
  /// دي أهم سطر في الملف: موديل بيقترح «قرص كل ١٢ ساعة» من علبة بيخترع
  /// وصفة، ولو حد دوس «احفظ» وهو مستعجل بيبقى ده تذكير حقيقي بجرعة
  /// ماحدّش وصفها.
  static const systemInstruction = '''
You transcribe what is printed on a photo of a medicine box, carton or blister strip. You are not a doctor and you never act like one.
Return ONLY what is printed on the packaging: the brand name, the active ingredient, the strength, the dosage form, and the pack size.
NEVER return a dose, a frequency, a schedule, a time of day, a duration, or any instruction about when or how much to take.
The packaging cannot know what THIS patient was told to take - only their doctor knows that. If the box prints dosing directions, ignore them completely.
Do NOT interpret, diagnose, recommend or advise. Never say what the medicine is for, never mention conditions, side effects or warnings.
Copy text character for character. Keep Latin names in Latin and Arabic names in Arabic, exactly as printed.
If a field is not printed, or you cannot read it clearly, return null for it with confidence 0. Never guess a brand name, never complete a half-visible word, and never supply a strength or an ingredient from your own knowledge of the drug.
A blank field is a correct answer. A confident wrong name is the worst answer: it becomes a medicine on an elderly patient's list.
''';

  /// **الشريط مكتوب له فقرته هو.** الاسم على ورق قصدير بيلمع، وغالباً
  /// مقطوع بين الحبوب: «نص اسم» بثقة عالية هو بالظبط الغلط اللي بيوصل
  /// لقايمة أدوية راجل عنده ٧٢ سنة.
  static const prompt = '''
Read the attached photo of medicine packaging.
brand: the trade name exactly as printed on the pack (e.g. "Concor").
activeIngredient: the active substance if printed (e.g. "Bisoprolol fumarate"). Often in smaller print under or beside the brand name. Return null if it is not printed - do not supply it from what you know about the brand.
strength: the printed strength with its unit exactly as written (e.g. "5 mg", "40 mg/5 ml"). Return null if not printed.
form: the printed dosage form (e.g. "tablets", "capsules", "syrup", "أقراص"). Copy the wording on the pack.
packSize: the printed pack contents if visible (e.g. "30 tablets", "٢٠ قرص"). This is what is in the box, never a dose.
If the photo is a blister strip: the name is printed on reflective foil and is usually repeated and cut across the pills. Read only what you can actually see; letters hidden behind a pill or under glare are not letters you read. If the visible text is a fragment of a name, return null rather than completing it - a retake is cheap and a wrong medicine name is not. Partial text is a reason for low confidence, not for inference.
confidence is 0..1 per field based on how clearly you can read that exact text. Below 0.8 means a human must check it.
Return nothing about dosing, timing, frequency or duration, even if the pack prints it.
''';
}
