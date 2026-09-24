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
  other;

  String get label => switch (this) {
        pressure => 'ضغط',
        sugar => 'سكر',
        heart => 'قلب',
        stomach => 'معدة وقولون',
        cholesterol => 'كوليسترول',
        vitamins => 'فيتامينات',
        antibiotic => 'مضاد حيوي',
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
}
