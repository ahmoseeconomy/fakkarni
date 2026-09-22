// **«الدوا ده عندك خلاص؟» — دارت نقية.**
//
// علبة تانية من نفس الدوا بتتضاف كدوا جديد معناها **جرعة مضاعفة**: تذكيرين
// في نفس اليوم لنفس المادة، والراجل بياخد الاتنين. ده مش سيناريو نادر —
// ده اللي بيحصل لما حد يشتري علبة جديدة قبل ما القديمة تخلص.
//
// **وإحنا بنقول، مش بنمنع.** ممكن يكون الدكتور فعلاً كتب تركيزين، فالشاشة
// بتقول اللي هي شايفاه بالاسم وبتسيب القرار للإنسان — نفس قاعدة ٤.

/// دوا موجود في القايمة — الاسم، والمادة الفعّالة لو متسجّلة.
class ExistingMedicine {
  const ExistingMedicine({required this.name, this.activeIngredient});

  final String name;

  /// null لأي دوا اتضاف بالإيد أو من روشتة — ماحدش قالنا مادته.
  final String? activeIngredient;
}

/// نوع التطابق — عشان الجملة تقول **ليه** الدوا ده اتقال عنه ده.
enum DuplicateKind { name, ingredient }

class DuplicateMatch {
  const DuplicateMatch({required this.kind, required this.existing, this.ingredient});

  final DuplicateKind kind;

  /// اسم الدوا اللي في القايمة — بيتقال بالحرف عشان يعرفه.
  final String existing;

  /// المادة المشتركة — للنوع [DuplicateKind.ingredient] بس.
  final String? ingredient;

  /// الجملة اللي الراجل بيقراها قبل ما يحفظ.
  String get message => switch (kind) {
        DuplicateKind.name => 'الدوا ده عندك في القايمة باسم «$existing».',
        DuplicateKind.ingredient =>
          'نفس المادة الفعّالة ($ingredient) عندك في «$existing».',
      };
}

/// **التطبيع: الاسم من غير تركيزه.**
///
/// «Concor 5mg» و«Concor 10mg» نفس الدوا بتركيزين، والمقارنة بالحرف كانت
/// هتعدّي عليهم. فبنشيل الأرقام ووحداتها وبنقارن اللي فاضل. وبنشيل كمان
/// التشكيل والتطويل العربي، لأن نفس الكلمة بتتكتب بالاتنين.
String normaliseMedicineName(String raw) {
  final stripped = raw
      .replaceAll(RegExp('[ؐ-ًؚ-ْٰـ]'), '')
      .toLowerCase();
  final tokens = <String>[];
  for (final t in stripped.split(RegExp(r'[\s،,/\-+()]+'))) {
    final token = t.trim();
    if (token.isEmpty) continue;
    // «5mg» و«5» و«mg» و«mg/5ml» — كلها تركيز، مش اسم.
    if (RegExp(r'^[0-9٠-٩]').hasMatch(token)) continue;
    if (_units.contains(token)) continue;
    tokens.add(token);
  }
  return tokens.join(' ');
}

const _units = {
  'mg', 'mcg', 'g', 'gm', 'ml', 'iu', 'ui', '%',
  'مجم', 'مج', 'جم', 'مل', 'ملجم', 'وحدة',
};

/// أول دوا في القايمة بيتطابق مع اللي داخل — أو null.
///
/// الاسم الأول لأنه اللي الراجل بيعرف يربطه؛ والمادة بعده، ودي اللي
/// بتمسك الحالة الخطرة: علبتين اسمهم مختلف ونفس المادة.
DuplicateMatch? findDuplicate({
  required String name,
  String? activeIngredient,
  required List<ExistingMedicine> existing,
}) {
  final key = normaliseMedicineName(name);
  if (key.isNotEmpty) {
    for (final m in existing) {
      if (normaliseMedicineName(m.name) == key) {
        return DuplicateMatch(kind: DuplicateKind.name, existing: m.name);
      }
    }
  }

  final ingredient = activeIngredient?.trim();
  if (ingredient == null || ingredient.isEmpty) return null;
  final ingredientKey = normaliseMedicineName(ingredient);
  if (ingredientKey.isEmpty) return null;
  for (final m in existing) {
    final theirs = m.activeIngredient?.trim();
    // **مادة مش متسجّلة مش «مادة مختلفة»** — دي مش معروفة، وبنعدّي عليها
    // بدل ما ندّعي إننا قارنّا.
    if (theirs == null || theirs.isEmpty) continue;
    if (normaliseMedicineName(theirs) == ingredientKey) {
      return DuplicateMatch(
        kind: DuplicateKind.ingredient,
        existing: m.name,
        ingredient: ingredient,
      );
    }
  }
  return null;
}
