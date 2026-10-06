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
    this.valueText = const ReadField.missing(),
    this.refLow = const ReadField.missing(),
    this.refHigh = const ReadField.missing(),
    this.refText = const ReadField.missing(),
  });

  final ReadField<String> test;
  final ReadField<double> value;

  /// النتيجة المطبوعة لما ما تكونش رقم — «Negative»، «Nil»، «2 - 4»
  /// (المرحلة ٥، قرار المالك 1A). **بالحرف زي الورقة**، بتتعرض وعمرها ما
  /// بتتقارن بمعتاد ولا نطاق — زي [refText] بالظبط. واحدة من الاتنين:
  /// سطر رقمه واضح رقم، وإلا نصّه الواضح هو النتيجة. لو الموديل بعت
  /// الاتنين بثقة (مخالفة للبرومبت) الرقم بيكسب — الكلمة جنب رقم غالباً
  /// علامة H/L، ودي ممنوعة أصلاً.
  final ReadField<String> valueText;
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

  /// النتيجة الرقمية الواضحة — null لو مفيش (ساعتها [textResult] هو الأمل).
  double? get numberResult => value.needsReview ? null : value.value;

  /// النتيجة النصية الواضحة — بس لما مفيش رقم واضح (الرقم بيكسب، فوق).
  String? get textResult {
    if (numberResult != null) return null;
    final t = valueText.needsReview ? null : valueText.value?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// اسم مش واضح، أو سطر من غير **ولا** نتيجة واضحة — رقم أو نص — بيقفل
  /// «تمام»: نتيجة غلط في ملف حد بتبوّظ المقارنة بتاعته بعدين. الوحدة مش
  /// بتقفل.
  bool get blocksConfirm =>
      test.needsReview || test.value == null || (numberResult == null && textResult == null);
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

  /// [now] لحارس «تاريخ في المستقبل» — بيتحقن في الاختبار، وإلا ساعة الجهاز.
  factory LabReading.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final results = json['results'];
    return LabReading(
      lab: _string(json['lab']),
      date: _date(json['reportDate'], now ?? DateTime.now()),
      lines: [
        if (results is List)
          for (final r in results)
            if (r is Map)
              LabLine(
                test: _string(r['test']),
                value: _number(r['value']),
                valueText: _string(r['valueText']),
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
    // الموديل ساعات بيبعت الرقم كنص («1.2») رغم إن الـschema بيقول NUMBER،
    // وكنا بنرمي الحد كله ونخلّي النطاق من طرف واحد. قراية النص **مش**
    // اختراع قيمة — الرقم مكتوب، إحنا بس كنا بنرفض شكله.
    final n = switch (v) {
      final num x => x.toDouble(),
      final String x => num.tryParse(x.trim())?.toDouble(),
      _ => null,
    };
    return ReadField(value: n, confidence: n == null ? 0 : _confidence(field));
  }

  /// التاريخ بحارسين زي الروشتة (المالك 2A، ٥ أكتوبر ٢٠٢٦):
  /// سنة برّه ٢٠٠٠–٢١٠٠ = مفيش تاريخ (نفس حد `prescription_reading.dart`)؛
  /// وتاريخ **في المستقبل** = القيمة موجودة بثقة صفر — تقرير معمل بيتكتب
  /// عن حاجة حصلت، والمستقبل هنا أغلبه «١٢/٠٩» اتقرت أمريكي. الشاشة ساعتها
  /// بتقع على النهارده وبتقولها بالذهبي («هيتسجّل بتاريخ النهارده»).
  static ReadField<DateTime> _date(dynamic field, DateTime now) {
    if (field is! Map) return const ReadField.missing();
    final v = field['value'];
    final d = v is String ? DateTime.tryParse(v) : null;
    if (d == null || d.year < 2000 || d.year > 2100) return const ReadField.missing();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    return ReadField(
      value: day,
      confidence: day.isAfter(today) ? 0 : _confidence(field),
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
          // النتيجة المطبوعة اللي مش رقم («Negative») — بالحرف، بديل value
          // مش معاه. مطلوب زي حقول النطاق: الغياب لازم يبقى null مكتوبة.
          'valueText': _stringField,
          'unit': _stringField,
          'refLow': _numberField,
          'refHigh': _numberField,
          'refText': _stringField,
        },
        // **التلاتة الجداد مطلوبين برضه** — بقيمة null لو الورقة ما طبعتش.
        // من غير كده الموديل مسموح له **يسيب الحقل خالص**، واللي بيحصل
        // ساعتها إن النطاق المطبوع «٠.١ إلى ١.٢» بيوصل الشاشة «أكتر من
        // ٠.١»: الحد الأعلى ضاع في صمت، ومعاه «قريب من الحد» اللي محتاج
        // الطرفين. الإجبار على الحقل بيخلّي الغياب **قرار مكتوب** (null)
        // مش سطر ناقص.
        'required': ['test', 'value', 'valueText', 'unit', 'refLow', 'refHigh', 'refText'],
      },
    },
  },
  'required': ['results'],
};
