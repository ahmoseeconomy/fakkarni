import '../domain/medication/meal_relation.dart';
import 'prescription_timing.dart';
import '../domain/scheduling/dose_schedule.dart';
import '../domain/scheduling/minute_of_day.dart';

/// اللي الذكاء الاصطناعي قراه من الروشتة — **اقتراح**، مش جرعة.
///
/// ولا حاجة هنا بتتجدول من نفسها. كل حقل معاه ثقة، واللي ثقته قليلة بيتعلّم
/// «محتاج تحديد» وبيستنى إنسان يحدده. الملف ده دارت نقية عشان القراءة
/// تتختبر من ملفات JSON من غير شبكة.

/// تحت الرقم ده الحقل بيتعرض بالذهبي وبيستنى تحديد.
const double confidenceThreshold = 0.8;

/// حقل مقروء: قيمة + ثقة + ملاحظة اختيارية.
class ReadField<T> {
  const ReadField({required this.value, required this.confidence, this.note});

  const ReadField.missing([this.note])
      : value = null,
        confidence = 0;

  final T? value;

  /// من ٠ لـ ١.
  final double confidence;

  /// ليه محتاج تحديد — بتتعرض تحت الحقل.
  final String? note;

  /// بالثقة وبس: قيمة ناقصة بتيجي بثقة ٠ ([ReadField.missing])، أما null
  /// بثقة كاملة فمعناها «مش مكتوب عن قصد» — زي المدة المفتوحة.
  bool get needsReview => confidence < confidenceThreshold;

  ReadField<T> withNote(String note, {double? confidence}) =>
      ReadField(value: value, confidence: confidence ?? this.confidence, note: note);
}

/// سطر دوا واحد زي ما اتقرا.
class ReadLine {
  const ReadLine({
    required this.name,
    required this.amount,
    required this.timings,
    required this.duration,
    this.instructions = const ReadField(value: null, confidence: 1),
    this._mealRelation,
    this.facts = const TimingFacts(unclear: true),
  });

  final ReadField<String> name;
  final ReadField<String> amount;

  /// «قبل الأكل» وأخواتها زي ما الورقة قالتها — **كلمة تعليمات**، مش
  /// توقيت: ما بتحرّكش الساعة (قرار المالك، ٢٧ سبتمبر ٢٠٢٦). null = مش مكتوبة.
  MealRelation? get mealRelation => _mealRelation ?? facts.mealRelation;
  final MealRelation? _mealRelation;

  /// اللي الورقة قالته عن التوقيت: كل كام ساعة، كام مرة، قبل النوم، مش
  /// واضح… **مفيش فيه ساعة غير المكتوبة بالحرف.** بيتعرض ملاحظات على الكارت.
  final TimingFacts facts;

  /// تعليمات مكتوبة على السطر («مع كوباية مية كاملة») — مش توقيت ولا
  /// جرعة. مش مكتوبة = null بثقة كاملة، زي رأس الورقة.
  final ReadField<String> instructions;

  /// **الساعات المكتوبة على الورقة بالحرف وبس** — فاضية لو الورقة ما
  /// كتبتش ساعة. التطبيق عمره ما بيختار ساعة من روشتة (قرار المالك، ٢٧
  /// سبتمبر ٢٠٢٦ بعد تجربة الجهاز): «كل ١٢ ساعة» معلومة، والساعات بيختارها
  /// الإنسان على شاشة المراجعة.
  final ReadField<List<FixedTiming>> timings;

  /// null = مفتوحة. **ما بتتخمّنش أبداً** — لو الورقة مش كاتبة مدة، مفتوحة.
  final ReadField<int?> duration;

  bool get needsReview =>
      name.needsReview || amount.needsReview || timings.needsReview;

  /// الورقة كاتبة الساعات بالحرف — تتعرض «من الروشتة».
  bool get timesFromPaper => (timings.value ?? const []).isNotEmpty;

  /// اللي بيقفل «تمام»: الاسم والتوقيت. من غيرهم مفيش حاجة تتجدول.
  ///
  /// الجرعة **مش** بتقفل: تذكير بيقول «وقت Telfast» مفيد من غير «قرص واحد».
  /// بتفضل ذهبية بملاحظتها، وبتتحفظ «مش معروفة» — مش بنخترع قيمة عشان
  /// نفتح زرار.
  bool get blocksConfirm => name.needsReview || timings.needsReview;

  /// «09:00 + 15:00 + 21:00» — للاختبارات والتشخيص.
  String get timingLabel =>
      (timings.value ?? const []).map((t) => t.minuteOfDay.toString()).join(' + ');
}

/// الروشتة كلها.
class PrescriptionReading {
  const PrescriptionReading({
    required this.doctor,
    this.clinic = const ReadField(value: null, confidence: 1),
    this.issuedAt = const ReadField(value: null, confidence: 1),
    required this.lines,
    this.modelWarning,
  });

  final ReadField<String> doctor;

  /// اسم العيادة أو المستشفى زي ما هو مطبوع — غالباً في ترويسة الورقة.
  final ReadField<String> clinic;

  /// تاريخ الورقة نفسها. **null بثقة كاملة = الورقة مش كاتبة تاريخ** — ده
  /// مش نقص، زي المدة المفتوحة بالظبط. وما بنخترعش تاريخ: تاريخ غلط في ملف
  /// طبي أوحش من تاريخ ناقص.
  final ReadField<DateTime?> issuedAt;
  final List<ReadLine> lines;

  /// الموديل المثبّت اتقفل والقراءة جت من البديل — تحذير للمطوّر، مش للمريض.
  final String? modelWarning;

  bool get isEmpty => lines.isEmpty;

  PrescriptionReading withModelWarning(String warning) =>
      PrescriptionReading(
        doctor: doctor,
        clinic: clinic,
        issuedAt: issuedAt,
        lines: lines,
        modelWarning: warning,
      );

  /// بيفكّ JSON بالشكل اللي طلبناه من Gemini في [prescriptionSchema].
  ///
  /// أي حاجة ناقصة أو غريبة بتبقى «محتاج تحديد» — مش خطأ ومش تخمين.
  factory PrescriptionReading.fromJson(Map<String, dynamic> json) {
    final meds = json['medications'];
    return PrescriptionReading(
      doctor: _headerString(json['doctor']),
      clinic: _headerString(json['clinic']),
      issuedAt: _date(json['issuedAt']),
      lines: [
        if (meds is List)
          for (final m in meds)
            if (m is Map<String, dynamic>) _line(m),
      ],
    );
  }

  static ReadLine _line(Map<String, dynamic> m) {
    final facts = timingFactsOf(m['timing']);
    return ReadLine(
      name: _string(m['name']),
      amount: _string(m['amount']),
      timings: _timings(m['timing'], facts),
      duration: _duration(m['durationDays']),
      instructions: _headerString(m['instructions']),
      facts: facts,
    );
  }

  /// الحقايق من الورقة: الكلام المكتوب (`text`) بيتقرا بقارئنا، والحقول
  /// المنظّمة من الموديل بتكمّل اللي الكلام ما قالوش. ولا واحد فيهم بيطلّع
  /// ساعة غير المكتوبة.
  static TimingFacts timingFactsOf(dynamic field) {
    if (field is! Map) return const TimingFacts(unclear: true);
    final text = field['text'];
    final fromText = parseTimingText(text is String ? text : null);
    final clocks = <MinuteOfDay>[
      if (field['clockTimes'] is List)
        for (final c in field['clockTimes'] as List)
          if (c is String && _parseClock(c) != null) _parseClock(c)!,
    ];
    int? positive(dynamic v, int max) => v is num && v >= 1 && v <= max ? v.toInt() : null;
    final structured = TimingFacts(
      clockTimes: clocks,
      everyHours: positive(field['everyHours'], 24),
      timesPerDay: positive(field['timesPerDay'], 12),
      mealRelation: MealRelation.fromStorage(switch (field['mealRelation']) {
        'before' => 'before',
        'after' => 'after',
        'with' => 'with',
        'empty_stomach' => 'empty_stomach',
        _ => null,
      }),
      moments: {?TimingMoment.fromStorage(field['moment'] as String?)},
      unclear: field['unclear'] == true,
    );
    return fromText.orElse(structured);
  }

  /// حقل من ترويسة الورقة: **مش مكتوب ≠ مش متأكد**.
  ///
  /// الورقة اللي مفيهاش اسم عيادة مش ورقة ناقصة — فالغياب بيرجع null بثقة
  /// كاملة (زي المدة المفتوحة)، ومفيش علامة ذهبية عليه. الذهبي محجوز
  /// لحاجة الذكاء قراها وهو مش متأكد منها.
  static ReadField<String> _headerString(dynamic field) {
    if (field is! Map) return const ReadField(value: null, confidence: 1);
    final value = field['value'];
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) return ReadField(value: null, confidence: 1, note: _note(field));
    return ReadField(value: text, confidence: _confidence(field), note: _note(field));
  }

  static ReadField<String> _string(dynamic field) {
    if (field is! Map) return const ReadField.missing();
    final value = field['value'];
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) return const ReadField.missing();
    return ReadField(value: text, confidence: _confidence(field), note: _note(field));
  }

  /// المدة: بس لو مكتوبة. مفيش مدة = مفتوحة، بثقة كاملة — ده مش نقص.
  static ReadField<int?> _duration(dynamic field) {
    if (field is! Map) return const ReadField(value: null, confidence: 1);
    final value = field['value'];
    if (value == null) return ReadField(value: null, confidence: 1, note: _note(field));
    final days = value is num ? value.toInt() : int.tryParse(value.toString());
    if (days == null || days <= 0) return const ReadField(value: null, confidence: 1);
    return ReadField(value: days, confidence: _confidence(field), note: _note(field));
  }

  /// تاريخ الورقة: `yyyy-MM-dd` بالحرف. مش مكتوب = null بثقة كاملة.
  ///
  /// أي شكل تاني (أو تاريخ مش منطقي) بيترمي بدل ما يتخمّن — الورقة اللي
  /// مفيهاش تاريخ بتتسجّل بتاريخ النهاردة والشاشة بتقول كده.
  static ReadField<DateTime?> _date(dynamic field) {
    if (field is! Map) return const ReadField(value: null, confidence: 1);
    final value = field['value'];
    if (value is! String || value.trim().isEmpty) {
      return ReadField(value: null, confidence: 1, note: _note(field));
    }
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null || parsed.year < 2000 || parsed.year > 2100) {
      return const ReadField.missing('التاريخ مش واضح');
    }
    return ReadField(
      value: DateTime(parsed.year, parsed.month, parsed.day),
      confidence: _confidence(field),
      note: _note(field),
    );
  }

  /// التوقيت — **الساعات المكتوبة بالحرف وبس.** مفيش ساعة مكتوبة = قايمة
  /// فاضية بثقة كاملة: الورقة ما قالتش ساعة، وده مش شك — ده مكان الإنسان.
  /// (كانت بتطلّع ٩ و٩ من «مرتين» — اتشالت، ٢٧ سبتمبر ٢٠٢٦.)
  static ReadField<List<FixedTiming>> _timings(dynamic field, TimingFacts facts) {
    if (field is! Map) return const ReadField(value: [], confidence: 1, note: unclearTimingNote);
    final times = [for (final m in facts.clockTimes) FixedTiming(m)];
    if (times.isEmpty) {
      return ReadField(value: const [], confidence: 1, note: facts.unclear ? unclearTimingNote : null);
    }
    return ReadField(value: times, confidence: _confidence(field), note: _note(field));
  }

  static MinuteOfDay? _parseClock(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return MinuteOfDay.hm(h, m);
  }

  static double _confidence(Map field) {
    final c = field['confidence'];
    if (c is! num) return 0;
    return c.toDouble().clamp(0, 1);
  }

  static String? _note(Map field) {
    final n = field['note'];
    return n is String && n.trim().isNotEmpty ? n.trim() : null;
  }
}

/// النص الثابت للتوقيت الغامض — القاعدة السادسة: ما بنخمّنش.
const String unclearTimingNote = 'مش متأكد — اسأل الصيدلي';

/// الورقة ما قالتش حاجة واضحة عن التوقيت — الكارت بيقولها بالكلام.
const String unclearTimingCardLine = 'التوقيت مش واضح في الروشتة — اسأل الصيدلي واختار الساعات';

/// الساعات الافتراضية من عدد المرات — عُرف تشغيلي لـ«ضيف دوا» و«كلّمني»
/// لما **الإنسان** يختار «كام مرة» بإيده. **مش للروشتة**: الروشتة عمرها ما
/// بتطلّع ساعة ما اتكتبتش (٢٧ سبتمبر ٢٠٢٦).
List<FixedTiming> defaultTimesFor(int timesPerDay) => [
      for (final m in defaultMinutesFor(timesPerDay)) FixedTiming(m),
    ];

/// مرة ٩ص؛ مرتين ٩ص و٩م؛ ٣ مرات ٩ص و٣م و٩م؛ ٤ مرات ٨ص و١م و٦م و١١م.
/// أكتر من ٤: موزّعة بالتساوي من ٨ الصبح لـ١١ بالليل.
List<MinuteOfDay> defaultMinutesFor(int timesPerDay) {
  switch (timesPerDay) {
    case <= 1:
      return [MinuteOfDay.hm(9)];
    case 2:
      return [MinuteOfDay.hm(9), MinuteOfDay.hm(21)];
    case 3:
      return [MinuteOfDay.hm(9), MinuteOfDay.hm(15), MinuteOfDay.hm(21)];
    case 4:
      return [MinuteOfDay.hm(8), MinuteOfDay.hm(13), MinuteOfDay.hm(18), MinuteOfDay.hm(23)];
    default:
      const first = 8 * 60, last = 23 * 60;
      final step = (last - first) ~/ (timesPerDay - 1);
      return [for (var k = 0; k < timesPerDay; k++) MinuteOfDay(first + k * step)];
  }
}

/// شكل الـJSON اللي بنطلبه من Gemini (responseSchema).
///
/// كل قيمة معاها ثقة. المدة والساعة بالحرف بس لو مكتوبين.
const Map<String, dynamic> prescriptionSchema = {
  'type': 'OBJECT',
  'properties': {
    'doctor': _stringField,
    'clinic': _stringField,
    'issuedAt': _stringField,
    'medications': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'name': _stringField,
          'amount': _stringField,
          'timing': {
            'type': 'OBJECT',
            'properties': {
              'text': {'type': 'STRING', 'nullable': true},
              'clockTimes': {
                'type': 'ARRAY',
                'nullable': true,
                'items': {'type': 'STRING'},
              },
              'everyHours': {'type': 'INTEGER', 'nullable': true},
              'timesPerDay': {'type': 'INTEGER', 'nullable': true},
              'mealRelation': {
                'type': 'STRING',
                'nullable': true,
                'enum': ['before', 'after', 'with', 'empty_stomach'],
              },
              'moment': {
                'type': 'STRING',
                'nullable': true,
                'enum': ['bedtime', 'wake'],
              },
              'unclear': {'type': 'BOOLEAN', 'nullable': true},
              'confidence': {'type': 'NUMBER'},
              'note': {'type': 'STRING', 'nullable': true},
            },
            'required': ['text', 'confidence'],
          },
          'durationDays': {
            'type': 'OBJECT',
            'properties': {
              'value': {'type': 'INTEGER', 'nullable': true},
              'confidence': {'type': 'NUMBER'},
              'note': {'type': 'STRING', 'nullable': true},
            },
            'required': ['confidence'],
          },
          'instructions': _stringField,
        },
        'required': ['name', 'amount', 'timing', 'durationDays', 'instructions'],
      },
    },
  },
  'required': ['medications'],
};

const Map<String, dynamic> _stringField = {
  'type': 'OBJECT',
  'properties': {
    'value': {'type': 'STRING', 'nullable': true},
    'confidence': {'type': 'NUMBER'},
    'note': {'type': 'STRING', 'nullable': true},
  },
  'required': ['confidence'],
};
