import 'prescription_reading.dart' show ReadField, confidenceThreshold;

/// اللي Gemini قراه من تقرير تحليل — **اقتراح**، وبس أرقام.
///
/// مفيش هنا نطاق مرجعي، ولا علامة H/L، ولا تفسير، ولا نص حر من الموديل:
/// الـschema ما بيطلبهمش، فمفيش طريق يوصلوا منه للشاشة (القاعدة ٦). دارت
/// نقية عشان تتختبر من JSON من غير شبكة.
class LabLine {
  const LabLine({required this.test, required this.value, required this.unit});

  final ReadField<String> test;
  final ReadField<double> value;
  final ReadField<String> unit;

  /// اسم أو رقم مش واضح بيقفل «تمام» — رقم غلط في ملف حد بيبوّظ المقارنة
  /// بتاعته بعدين. الوحدة مش بتقفل.
  bool get blocksConfirm => test.needsReview || value.needsReview || test.value == null || value.value == null;
}

class LabReading {
  const LabReading({required this.lab, required this.date, required this.lines, this.modelWarning});

  final ReadField<String> lab;

  /// تاريخ التقرير لو مطبوع — وإلا null.
  final ReadField<DateTime> date;
  final List<LabLine> lines;
  final String? modelWarning;

  LabReading withModelWarning(String warning) =>
      LabReading(lab: lab, date: date, lines: lines, modelWarning: warning);

  factory LabReading.fromJson(Map<String, dynamic> json) {
    final results = json['results'];
    return LabReading(
      lab: _string(json['lab']),
      date: _date(json['reportDate']),
      lines: [
        if (results is List)
          for (final r in results)
            if (r is Map) LabLine(test: _string(r['test']), value: _number(r['value']), unit: _string(r['unit'])),
      ],
    );
  }

  static double _confidence(Map field) {
    final c = field['confidence'];
    return c is num ? c.toDouble().clamp(0, 1) : 0;
  }

  static ReadField<String> _string(dynamic field) {
    if (field is! Map) return const ReadField.missing();
    final v = field['value'];
    final text = v is String && v.trim().isNotEmpty ? v.trim() : null;
    return ReadField(value: text, confidence: text == null ? 0 : _confidence(field));
  }

  static ReadField<double> _number(dynamic field) {
    if (field is! Map) return const ReadField.missing();
    final v = field['value'];
    final n = v is num ? v.toDouble() : null;
    return ReadField(value: n, confidence: n == null ? 0 : _confidence(field));
  }

  static ReadField<DateTime> _date(dynamic field) {
    if (field is! Map) return const ReadField.missing();
    final v = field['value'];
    final d = v is String ? DateTime.tryParse(v) : null;
    return ReadField(
      value: d == null ? null : DateTime(d.year, d.month, d.day),
      confidence: d == null ? 0 : _confidence(field),
    );
  }
}

/// ثقة الحد — نفس الروشتة.
const double labConfidenceThreshold = confidenceThreshold;
