/// «الدوا ده لإيه؟» — اختياري، وكلمة واحدة من قايمة مقفولة.
///
/// مش تشخيص ولا تصنيف طبي: الراجل بيقول «ده بتاع الضغط» زي ما بيقولها
/// للصيدلي، وبعدين «يومك» هتعرف تقول له كلمة عن الضغط. مفيش قيمة
/// بتتخمّن — null = ما قالش.
library;

enum MedicationPurpose {
  pressure,
  sugar,
  heart,
  stomach,
  cholesterol,
  vitamins,
  antibiotic,
  eye,
  skin,
  other;

  /// الكلمة على الشريحة والكارت — بصيغة «لل» زي التصميم (المالك، ٤ أكتوبر
  /// ٢٠٢٦). التلاتة اللي «لل» ما بتركبش عليهم بيفضلوا أسماء بقراره.
  String get label => switch (this) {
        pressure => 'للضغط',
        sugar => 'للسكر',
        heart => 'للقلب',
        stomach => 'للمعدة والقولون',
        cholesterol => 'للكوليسترول',
        vitamins => 'فيتامينات',
        antibiotic => 'مضاد حيوي',
        eye => 'للعين',
        skin => 'للجلد',
        other => 'حاجة تانية',
      };

  /// الكلمة من غير «لل» — اللي الراجل بيقولها لـ«كلّمني» («دوا الضغط»).
  /// المطابقة بالصوت بتقارن بيها مش بـ[label].
  String get word => switch (this) {
        pressure => 'ضغط',
        sugar => 'سكر',
        heart => 'قلب',
        stomach => 'معدة وقولون',
        cholesterol => 'كوليسترول',
        vitamins => 'فيتامينات',
        antibiotic => 'مضاد حيوي',
        eye => 'عين',
        skin => 'جلد',
        other => 'حاجة تانية',
      };

  /// الاسم المخزّن — الحروف دي هي اللي في العمود، فما تتغيّرش.
  String get storageName => name;

  static MedicationPurpose? fromStorage(String? name) {
    if (name == null) return null;
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// من كلمة **متقالة** (مطبّعة: ة→ه، أ→ا) — «للضغط» / «الضغط» / «ضغط».
  /// «لل» و«ال» بيتشالوا الأول؛ مش واضحة = null. «مضاد حيوي» كلمتين،
  /// فالقارئ بيبعتهم متوصّلين («مضادحيوي») أو بيمسك الزوج بنفسه.
  /// مطابقة **متسامحة** على القايمة المقفولة — `contains` زي ما زرار
  /// «نوع التنبيه» القديم كان بيعمل (المرحلة ٢، المالك 1A): المتعرّف
  /// الحقيقي بيرجّع جُمل بحشو وترقيم («اه للضغط») والتوكنة الصارمة كانت
  /// بتقع عليها. الترتيب مقصود: «مضاد حيوي» قبل الكلمات القصيرة.
  static MedicationPurpose? fromSpokenText(String normalized) {
    for (final (purpose, keys) in _spokenKeys) {
      for (final k in keys) {
        if (normalized.contains(k)) return purpose;
      }
    }
    return null;
  }

  static const _spokenKeys = <(MedicationPurpose, List<String>)>[
    (antibiotic, ['مضاد حيوي', 'مضادحيوي']),
    (pressure, ['ضغط']),
    (sugar, ['سكر']),
    (heart, ['قلب']),
    (stomach, ['معده', 'قولون']),
    (cholesterol, ['كوليسترول', 'كولسترول', 'دهون']),
    (vitamins, ['فيتامين']),
    (eye, ['عيون', 'عين']),
    (skin, ['جلد', 'بشره']),
  ];

  static MedicationPurpose? fromSpokenWord(String token) {
    var t = token;
    if (t.startsWith('لل')) t = 'ال${t.substring(2)}';
    if (t.startsWith('ال')) t = t.substring(2);
    return switch (t) {
      'ضغط' => pressure,
      'سكر' || 'سكري' => sugar,
      'قلب' => heart,
      'معده' || 'قولون' => stomach,
      'كوليسترول' || 'كولسترول' || 'دهون' => cholesterol,
      'فيتامين' || 'فيتامينات' => vitamins,
      'مضادحيوي' => antibiotic,
      'عين' || 'عيون' || 'عينيه' => eye,
      'جلد' || 'بشره' => skin,
      _ => null,
    };
  }
}
