// **مين بيتابع وبيقدر يعمل إيه** — دارت نقية.
//
// المتابع **علاقة** ليها دور وصلاحيات، مش دخول مشترك (قرار المالك، تعليق
// المختبِر ٧). موبايل الأب هو مصدر الحقيقة للتذكير — مفيش دور بيغيّر
// السلّم ولا مهلة السيرفر ولا تنبيه الابن.

/// «متابع»: بيشوف وبيتنبّه. «ممرض / مرافق»: مرآة — بيشوف زي «يومك» وبيأكّد
/// نيابة عن المريض لو مسموح له.
enum FollowerRole {
  follower('متابع', 'بيشوف أدويتك ومواعيدك، ولو جرعة اتنست يوصله تنبيه.'),
  nurse('ممرض / مرافق', 'بيشوف يومك زي ما إنت بتشوفه، ويقدر يأكّد الجرعة بدالك.');

  const FollowerRole(this.label, this.explain);

  final String label;
  final String explain;

  /// على شريحة عمل الكود — النوعين اللي حوالين المريض بالاسم.
  String get inviteLabel => switch (this) {
        follower => 'متابع — من العيلة',
        nurse => 'ممرض أو مرافق',
      };

  /// اللي بيكتب الكود ده — للجمل اللي بتقول للمريض يعمل إيه بيه.
  String get holder => switch (this) {
        follower => 'ابنك أو بنتك',
        nurse => 'الممرض',
      };

  /// الباب اللي بيتكتب فيه الكود على الموبايل التاني.
  String get door => switch (this) {
        follower => 'معايا كود متابعة',
        nurse => 'أنا ممرض / مرافق',
      };

  static FollowerRole fromStored(String? stored) => stored == 'nurse' ? nurse : follower;

  /// افتراضياً الممرض يقدر يأكّد؛ المتابع لأ. تعديل الأدوية للاتنين مقفول
  /// لحد ما المريض يفتحه بنفسه.
  bool get confirmsByDefault => this == nurse;
}

/// صلاحيات علاقة واحدة زي ما هي على السيرفر.
class FollowerPermissions {
  const FollowerPermissions({
    required this.role,
    required this.canConfirm,
    required this.canEditMeds,
  });

  final FollowerRole role;
  final bool canConfirm;
  final bool canEditMeds;

  static const plainFollower = FollowerPermissions(
    role: FollowerRole.follower,
    canConfirm: false,
    canEditMeds: false,
  );
}

/// «أكّدها محمد» — الجملة على صف الجرعة عند الأب لما حد تاني أكّد بداله.
/// الاسم فاضي = «أكّدها حد بيتابعك»: مفيش اسم مخترع.
String proxyConfirmedLine(String? actorName) {
  final name = actorName?.trim() ?? '';
  return name.isEmpty ? 'أكّدها حد بيتابعك' : 'أكّدها $name';
}

/// عند الممرض بعد ما يأكّد: الصف بيقول إن التأكيد مستني موبايل المريض.
const String proxyPendingLine = 'أكّدتها ✓ — مستنية موبايله يوصله';
