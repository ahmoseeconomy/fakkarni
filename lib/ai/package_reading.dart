import 'prescription_reading.dart' show ReadField, confidenceThreshold;

/// اللي Gemini قراه من صورة علبة دوا أو شريط — **وبس اللي مطبوع عليها**.
///
/// **العلبة ما بتقولش مواعيد، ولا بتقول جرعة الراجل ده.** الجرعة والمواعيد
/// بيقولهم الدكتور. عشان كده الـschema هنا **مالوش حقل توقيت خالص**: مفيش
/// طريق يوصل منه موعد للشاشة، مش لأننا بنفلتره بعدين. ولو الموديل حشر
/// مواعيد في أي حقل نصّي، الحقول اللي بتوصل للفورم هي دي بس واللي غيرها
/// بيتاكل — [PackageReading.fromJson] ما بتقراش غير الستة دول.
///
/// دارت نقية عشان القراءة تتختبر من JSON من غير شبكة.
class PackageReading {
  const PackageReading({
    required this.brand,
    required this.activeIngredient,
    required this.strength,
    required this.form,
    required this.packSize,
    this.modelWarning,
  });

  /// الاسم التجاري زي ما هو مطبوع — «Concor».
  final ReadField<String> brand;

  /// المادة الفعّالة لو مطبوعة — «Bisoprolol». دي اللي فحص التكرار بيقارن
  /// بيها: علبتين اسمهم مختلف ونفس المادة = جرعة مضاعفة.
  final ReadField<String> activeIngredient;

  /// التركيز زي ما هو مطبوع — «5 mg».
  final ReadField<String> strength;

  /// الشكل زي ما هو مطبوع — «tablets» / «أقراص» / «شراب».
  final ReadField<String> form;

  /// حجم العلبة لو باين — «30 tablets». **مش جرعة**، وبيتعرض للتأكد بس.
  final ReadField<String> packSize;

  final String? modelWarning;

  PackageReading withModelWarning(String warning) => PackageReading(
        brand: brand,
        activeIngredient: activeIngredient,
        strength: strength,
        form: form,
        packSize: packSize,
        modelWarning: warning,
      );

  /// حقل اتقرا بثقة كفاية عشان يتحط في الفورم — وإلا null.
  ///
  /// **الثقة الواطية بتبقى فراغ، مش تخمين.** اسم دوا غلط في قايمة راجل
  /// عنده ٧٢ سنة أوحش من حقل فاضي: الفاضي بيتملا، والغلط بيتاخد.
  static String? _sure(ReadField<String> f) => f.needsReview ? null : f.value?.trim();

  /// اللي بيتحط في خانة «اسم الدوا والتركيز» — «Concor 5mg».
  ///
  /// الاتنين لازم يكونوا واضحين عشان يتلزقوا مع بعض؛ تركيز مش واضح جنب
  /// اسم واضح بيدّي «Concor» لوحده، وده صح — الراجل بيكمّله.
  String? get nameField {
    final b = _sure(brand);
    if (b == null) return null;
    final s = _sure(strength);
    return s == null || s.isEmpty ? b : '$b $s';
  }

  String? get ingredientField => _sure(activeIngredient);
  String? get formField => _sure(form);
  String? get packSizeField => _sure(packSize);

  /// ولا حاجة اتقرت بوضوح — الشاشة بتقول «صوّر تاني أو اكتبه».
  bool get nothingClear => nameField == null;

  /// فيه حقل واحد على الأقل اتقرا وحد لأ — بنقول أنهي واحد.
  List<String> get unclear => [
        if (_sure(brand) == null) 'اسم الدوا',
        if (_sure(strength) == null) 'التركيز',
        if (_sure(activeIngredient) == null) 'المادة الفعّالة',
      ];

  factory PackageReading.fromJson(Map<String, dynamic> json) => PackageReading(
        brand: _string(json['brand']),
        activeIngredient: _string(json['activeIngredient']),
        strength: _string(json['strength']),
        form: _string(json['form']),
        packSize: _string(json['packSize']),
      );

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
}

/// نفس حد الثقة اللي في الروشتة والتحاليل — مكان واحد.
const double packageConfidenceThreshold = confidenceThreshold;

const Map<String, dynamic> _stringField = {
  'type': 'OBJECT',
  'properties': {
    'value': {'type': 'STRING', 'nullable': true},
    'confidence': {'type': 'NUMBER'},
  },
  'required': ['confidence'],
};

/// الـschema: خمس حقول، **ولا واحد منهم توقيت ولا جرعة**.
///
/// ده مش فلتر بعد القراية — ده إن الطريق مش موجود أصلاً. `responseSchema`
/// بتاعة Gemini بتمنع أي حقل زيادة، فمواعيد مش هتلاقي خانة تركب فيها.
const Map<String, dynamic> packageSchema = {
  'type': 'OBJECT',
  'properties': {
    'brand': _stringField,
    'activeIngredient': _stringField,
    'strength': _stringField,
    'form': _stringField,
    'packSize': _stringField,
  },
  'required': ['brand', 'activeIngredient', 'strength', 'form', 'packSize'],
};
