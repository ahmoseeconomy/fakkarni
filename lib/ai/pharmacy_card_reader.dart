import 'dart:typed_data';

import 'gemini_config.dart';
import 'prescription_reader.dart';

/// اللي اتقرا من كارت صيدلية — المكتوب عليه وبس.
class PharmacyCardReading {
  const PharmacyCardReading({this.name, this.phones = const [], this.whatsapp, this.address, this.highConfidence = false});

  final String? name;
  final List<String> phones;
  final String? whatsapp;
  final String? address;
  final bool highConfidence;

  /// ولا حاجة تنفع تتعبّى — نفس معاملة الثقة الواطية.
  bool get nothingFound => name == null && phones.isEmpty && whatsapp == null;

  /// «مش قادر أقرا الكارت كويس»: ثقة واطية أو مفيش حاجة.
  bool get unreadable => !highConfidence || nothingFound;

  /// صارم: أي نوع غلط = مش موجود. JSON فاضي = مفيش حاجة.
  factory PharmacyCardReading.fromJson(Map<String, dynamic> json) {
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final phones = json['phones'];
    return PharmacyCardReading(
      name: text(json['name']),
      phones: phones is List ? [for (final p in phones) if (text(p) != null) text(p)!] : const [],
      whatsapp: text(json['whatsapp']),
      address: text(json['address']),
      highConfidence: json['confidence'] == 'high',
    );
  }
}

/// «صوّر كارت الصيدلية» — واجهة عشان الورقة تتختبر من غير شبكة.
abstract interface class PharmacyCardReader {
  Future<PharmacyCardReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// **نفس نقل Gemini بتاع الروشتة بالحرف** ([GeminiPrescriptionReader.generate]):
/// نفس المفتاح في الرأس، نفس التصغير، نفس المهلة والبديل، ونفس رسالة الزحمة.
/// **ولا الصورة ولا اللي اتقرا بيتسجّل** — النقل بيسجّل المقاس والحالة وبس.
class GeminiPharmacyCardReader implements PharmacyCardReader {
  GeminiPharmacyCardReader(GeminiConfig config, {GeminiPrescriptionReader? transport})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  @override
  Future<PharmacyCardReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    final result = await _transport.generate(
      image: image,
      mimeType: mimeType,
      prompt: prompt,
      schema: pharmacyCardSchema,
      systemInstruction: systemInstruction,
      failure: pharmacyCardUnreadable,
    );
    return PharmacyCardReading.fromJson(result.json);
  }

  static const systemInstruction = '''
You transcribe what is printed on a photo of a pharmacy business card, sticker, bag or sign. Return JSON only.
Return ONLY what is printed. Never invent, complete or look up a name, a phone number or an address.
If something is not printed or you cannot read it clearly, leave it null (or out of the phones list).
''';

  static const prompt = '''
Read the attached photo of a pharmacy card.
name: the pharmacy name exactly as printed (Arabic stays Arabic, Latin stays Latin), or null.
phones: every phone number printed, digits only, in the order printed. Do not add a country code that is not printed.
whatsapp: a number printed next to the WhatsApp logo or the word «واتساب» / "WhatsApp", digits only; otherwise null. Put it here, not only in phones.
address: the printed address, or null.
confidence: "high" only if you could read the name or the numbers clearly; otherwise "low".
''';
}

/// الجملة الواحدة لما الكارت ما يتقراش — الورقة والعطل بيقروا منها.
const pharmacyCardUnreadable = 'مش قادر أقرا الكارت كويس — صوّره تاني في نور أحسن أو اكتب البيانات بإيدك';

const Map<String, dynamic> pharmacyCardSchema = {
  'type': 'OBJECT',
  'properties': {
    'name': {'type': 'STRING', 'nullable': true},
    'phones': {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
    'whatsapp': {'type': 'STRING', 'nullable': true},
    'address': {'type': 'STRING', 'nullable': true},
    'confidence': {
      'type': 'STRING',
      'enum': ['high', 'low'],
    },
  },
  'required': ['name', 'phones', 'whatsapp', 'address', 'confidence'],
};
