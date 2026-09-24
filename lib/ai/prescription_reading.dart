import '../domain/scheduling/day_routine.dart';
import '../domain/scheduling/dose_schedule.dart';

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
  });

  final ReadField<String> name;
  final ReadField<String> amount;

  /// تعليمات مكتوبة على السطر («مع كوباية مية كاملة») — مش توقيت ولا
  /// جرعة. مش مكتوبة = null بثقة كاملة، زي رأس الورقة.
  final ReadField<String> instructions;

  /// جرعة أو أكتر في اليوم — كل واحدة مرساة + إزاحة، أو ساعة ثابتة لو
  /// الورقة كاتبة ساعة بالحرف.
  final ReadField<List<DoseTiming>> timings;

  /// null = مفتوحة. **ما بتتخمّنش أبداً** — لو الورقة مش كاتبة مدة، مفتوحة.
  final ReadField<int?> duration;

  bool get needsReview =>
      name.needsReview || amount.needsReview || timings.needsReview;

  /// اللي بيقفل «تمام»: الاسم والتوقيت. من غيرهم مفيش حاجة تتجدول.
  ///
  /// الجرعة **مش** بتقفل: تذكير بيقول «وقت Telfast» مفيد من غير «قرص واحد».
  /// بتفضل ذهبية بملاحظتها، وبتتحفظ «مش معروفة» — مش بنخترع قيمة عشان
  /// نفتح زرار.
  bool get blocksConfirm => name.needsReview || timings.needsReview;

  /// «الفطار − ٣٠ د + الغدا − ٣٠ د» — للعرض.
  String get timingLabel =>
      (timings.value ?? const []).map((t) => t.ruleLabel).join(' + ');
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

  static ReadLine _line(Map<String, dynamic> m) => ReadLine(
        name: _string(m['name']),
        amount: _string(m['amount']),
        timings: _timings(m['timing']),
        duration: _duration(m['durationDays']),
        instructions: _headerString(m['instructions']),
      );

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

  /// التوقيت — القلب. مرساة + قبل/بعد، أو ساعة بالحرف، أو «١×٣».
  static ReadField<List<DoseTiming>> _timings(dynamic field) {
    if (field is! Map) return const ReadField.missing(unclearTimingNote);
    final confidence = _confidence(field);
    final note = _note(field);

    // ساعة مكتوبة بالحرف → ثابتة. غير كده المرساة.
    final clock = field['clockTime'];
    if (clock is String && clock.isNotEmpty) {
      final minute = _parseClock(clock);
      if (minute == null) return const ReadField.missing(unclearTimingNote);
      return ReadField(
        value: [FixedTiming(minute)],
        confidence: confidence,
        note: note,
      );
    }

    final anchor = _anchor(field['anchor']);
    final relation = field['relation'];
    final offset = (field['offsetMinutes'] is num)
        ? (field['offsetMinutes'] as num).toInt()
        : null;
    final timesPerDay = field['timesPerDay'] is num
        ? (field['timesPerDay'] as num).toInt()
        : null;

    if (anchor != null) {
      final signed = switch (relation) {
        'before' => -(offset ?? defaultOffsetBefore(anchor)),
        'after' => offset ?? 0,
        _ => offset ?? 0,
      };
      return ReadField(
        value: [AnchorTiming(anchor, signed)],
        confidence: confidence,
        note: note,
      );
    }

    // «١×٣» من غير مرساة: بنقترح الوجبات التلاتة — عرف شائع مش نصيحة —
    // وبنعلّمها «محتاج تحديد» عشان إنسان يأكّدها مهما كانت الثقة.
    if (timesPerDay != null && timesPerDay >= 1 && timesPerDay <= 3) {
      final anchors = switch (timesPerDay) {
        1 => [DayAnchor.breakfast],
        2 => [DayAnchor.breakfast, DayAnchor.dinner],
        _ => [DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner],
      };
      // وجبات بس هنا، فالافتراضي ٣٠
      final signed =
          relation == 'before' ? -(offset ?? defaultOffsetBefore(anchors.first)) : (offset ?? 0);
      return ReadField(
        value: [for (final a in anchors) AnchorTiming(a, signed)],
        // أقل من العتبة عن قصد: ده اقتراح توزيع، مش قراءة من الورقة.
        confidence: confidence < confidenceThreshold ? confidence : confidenceThreshold - 0.01,
        note: note ?? timesPerDayNote,
      );
    }

    return ReadField.missing(note ?? unclearTimingNote);
  }

  static DayAnchor? _anchor(dynamic value) => switch (value) {
        'wake' => DayAnchor.wake,
        'breakfast' => DayAnchor.breakfast,
        'lunch' => DayAnchor.lunch,
        'dinner' => DayAnchor.dinner,
        'sleep' => DayAnchor.sleep,
        _ => null,
      };

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

const String timesPerDayNote = 'الورقة كاتبة عدد المرات بس — أكّد الوجبات';

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
              'anchor': {
                'type': 'STRING',
                'nullable': true,
                'enum': ['wake', 'breakfast', 'lunch', 'dinner', 'sleep'],
              },
              'relation': {
                'type': 'STRING',
                'nullable': true,
                'enum': ['before', 'after', 'at'],
              },
              'offsetMinutes': {'type': 'INTEGER', 'nullable': true},
              'clockTime': {'type': 'STRING', 'nullable': true},
              'timesPerDay': {'type': 'INTEGER', 'nullable': true},
              'confidence': {'type': 'NUMBER'},
              'note': {'type': 'STRING', 'nullable': true},
            },
            'required': ['confidence'],
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
