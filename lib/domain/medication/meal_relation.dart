/// علاقة الجرعة بالأكل — **كلمة تعليمات، مش توقيت.**
///
/// «قبل الأكل» / «مع الأكل» / «بعد الأكل» / «على معدة فاضية» بتتعرض جنب
/// الجرعة في التذكير وفي متن الإشعار وفي تفاصيل الدوا، **وعمرها ما
/// بتحرّك ساعة**: الساعة ثابتة زي ما المستخدم كتبها (قرار المالك، ٢٧ سبتمبر
/// ٢٠٢٦ — الروتين والمراسي اتشالوا من التطبيق كله).
///
/// دارت نقية — جانب الابن بيقراها من غير ما يستورد الجدولة.
enum MealRelation {
  before('قبل الأكل'),
  with_('مع الأكل'),
  after('بعد الأكل'),
  emptyStomach('على معدة فاضية');

  const MealRelation(this.label);

  /// الكلمة زي ما بتتقال للمريض.
  final String label;

  /// الاسم المخزّن (drift والسحابة): `before` / `with` / `after` / `empty_stomach`.
  String get storageName => switch (this) {
        MealRelation.before => 'before',
        MealRelation.with_ => 'with',
        MealRelation.after => 'after',
        MealRelation.emptyStomach => 'empty_stomach',
      };

  /// من الاسم المخزّن — اسم غريب (نسخة أحدث) = null، مش وقعة.
  static MealRelation? fromStorage(String? name) {
    for (final r in values) {
      if (r.storageName == name) return r;
    }
    return null;
  }

  /// الكلمة من الاسم المخزّن مباشرة — لجانب الابن والممرض.
  static String? labelOf(String? name) => fromStorage(name)?.label;
}
