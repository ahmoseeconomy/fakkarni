import '../domain/health/lab_range.dart';
import 'prescription_reading.dart' show ReadField, confidenceThreshold;

/// اللي Gemini قراه من تقرير تحليل — **اقتراح**، وبس اللي مطبوع.
///
/// النطاق اللي بيرجع هنا هو **نطاق الورقة منقول بالحرف**، مش نطاق من عندنا
/// ولا من عند الموديل: الـsystem instruction بيقول ده صراحة، والسطر اللي
/// الورقة مفيهاش نطاق ليه بيرجع null وبيفضل null. ولسه **مفيش** علامة H/L
/// ولا تفسير ولا نص حر — الـschema ما بيطلبهمش، فمفيش طريق يوصلوا منه
/// للشاشة (القاعدة ٦). دارت نقية عشان تتختبر من JSON من غير شبكة.
class LabLine {
  const LabLine({
    required this.test,
    required this.value,
    required this.unit,
    this.refLow = const ReadField.missing(),
    this.refHigh = const ReadField.missing(),
    this.refText = const ReadField.missing(),
  });

  final ReadField<String> test;
  final ReadField<double> value;
  final ReadField<String> unit;

  /// طرفا النطاق المطبوع — واحد منهم ممكن يكون null («لحد ١١»).
  final ReadField<double> refLow;
  final ReadField<double> refHigh;

  /// النطاق المطبوع لما ما يكونش رقم — «Negative»، «< 5».
  final ReadField<String> refText;

  /// النطاق زي ما الورقة طبعته، أو null لو ما طبعتش.
  ///
  /// **قراءة مش متأكدة = مفيش نطاق.** نطاق نصّه مش واضح أسوأ من غير نطاق:
  /// من غيره الرقم بيتعرض عادي، وبيه بنعلّم على حاجة ما اتقريتش صح.
  LabRange? get range {
    final low = refLow.needsReview ? null : refLow.value;
    final high = refHigh.needsReview ? null : refHigh.value;
    final text = refText.needsReview ? null : refText.value;
    final r = LabRange(low: low, high: high, text: text);
    return r.isEmpty ? null : r;
  }

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
            if (r is Map)
              LabLine(
                test: _string(r['test']),
                value: _number(r['value']),
                unit: _string(r['unit']),
                refLow: _number(r['refLow']),
                refHigh: _number(r['refHigh']),
                refText: _string(r['refText']),
              ),
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

const Map<String, dynamic> _numberField = {
  'type': 'OBJECT',
  'properties': {
    'value': {'type': 'NUMBER', 'nullable': true},
    'confidence': {'type': 'NUMBER'},
  },
  'required': ['confidence'],
};

const Map<String, dynamic> _stringField = {
  'type': 'OBJECT',
  'properties': {
    'value': {'type': 'STRING', 'nullable': true},
    'confidence': {'type': 'NUMBER'},
  },
  'required': ['confidence'],
};

/// الـschema: اسم التحليل، الرقم، الوحدة، والنطاق **زي ما هو مطبوع على
/// الورقة**. **مفيش** flag، **مفيش** interpretation، ومفيش نطاق من عند
/// الموديل: الحقول دي نقل، والسطر اللي الورقة مفيهاش نطاق ليه بيرجع null.
const Map<String, dynamic> labSchema = {
  'type': 'OBJECT',
  'properties': {
    'lab': _stringField,
    'reportDate': _stringField,
    'results': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'test': _stringField,
          'value': _numberField,
          'unit': _stringField,
          'refLow': _numberField,
          'refHigh': _numberField,
          'refText': _stringField,
        },
        'required': ['test', 'value', 'unit'],
      },
    },
  },
  'required': ['results'],
};
