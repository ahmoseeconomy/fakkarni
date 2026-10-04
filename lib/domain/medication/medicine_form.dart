/// نوع الدوا — قرص، كبسولة، حقنة… (طلب المدير، ٤ أكتوبر ٢٠٢٦).
///
/// دارت نقية. **اختياري**: null = ما اتحددش (كل الأدوية القديمة) والوحدة
/// بتفضل من كلام الجرعة زي ما كانت — مفيش تخمين للقديم. الاسم على السلك
/// ([wire]) هو نفس قايمة قيد `medications_form_check` في 0038 بالحرف.
enum MedicineForm {
  tablet('قرص', 'قرص'),
  capsule('كبسولة', 'كبسولة'),
  injection('حقنة', 'حقنة'),
  ointment('مرهم', null),
  syrup('شراب', 'ملعقة'),
  drops('نقط', 'نقط'),
  inhaler('بخاخة', null),
  suppository('لبوس', 'لبوس'),
  other('تاني', null);

  const MedicineForm(this.label, this.stockUnit);

  /// الكلمة على الشريحة.
  final String label;

  /// وحدة كارت المخزون — null = **مفيش مخزون** للنوع ده (قرار المالك: المرهم
  /// والبخاخة مالهمش عدّ يومي) أو «تاني» (الوحدة من كلام الجرعة زي الأول).
  final String? stockUnit;

  String get wire => name;

  /// المرهم والبخاخة: كارت المخزون مش بيظهر خالص.
  bool get tracksStock => this != ointment && this != inhaler;

  static MedicineForm? fromWire(String? value) {
    for (final f in values) {
      if (f.name == value) return f;
    }
    return null;
  }

  /// من كلمة الشكل اللي اتقرت من العلبة («Film-coated tablets»، «كبسولات»،
  /// «Oral suspension»…). مش واضح = null — **مفيش تخمين**.
  static MedicineForm? fromPackageText(String? text) {
    final t = (text ?? '').toLowerCase();
    if (t.trim().isEmpty) return null;
    bool has(List<String> words) => words.any(t.contains);
    if (has(['capsule', 'caps', 'كبسول'])) return capsule;
    if (has(['tablet', 'tab.', 'tabs', 'قرص', 'أقراص', 'اقراص'])) return tablet;
    if (has(['inject', 'ampoule', 'ampule', 'vial', 'syringe', 'حقن', 'أمبول', 'امبول'])) return injection;
    if (has(['ointment', 'cream', 'gel', 'مرهم', 'كريم', 'جل'])) return ointment;
    if (has(['inhaler', 'inhalation', 'spray', 'بخاخ'])) return inhaler;
    if (has(['suppositor', 'لبوس'])) return suppository;
    if (has(['drop', 'نقط', 'قطرة', 'قطره'])) return drops;
    if (has(['syrup', 'suspension', 'solution', 'شراب', 'معلق'])) return syrup;
    return null;
  }
}
