/// هوية اختيارية — **مش بوابة أبداً**.
///
/// التطبيق كله شغّال من غير حساب: الأسئلة، التصوير، التذكيرات. الحساب
/// بيلزم لحاجة واحدة هي ربط ابنه بيه (التصعيد محتاج موبايل تاني)، والدخول
/// ليه باب واحد: «اربط ابني». لو لقيت نفسك بتحط شاشة دخول عند فتح
/// التطبيق — ده التصميم الغلط.
///
/// الواجهة دي هي الوحيدة اللي الشاشات تعرفها. النهاردة التنفيذ الحي هو
/// الدخول المجهول (وقتي للتطوير — شوف «دين تقني» في CLAUDE.md)، وGoogle
/// وApple جايين **كملفات شقيقة** بنفس العقد — مش تعديل في بعض.
library;

/// المستخدم زي ما الشاشات محتاجاه — من غير أي نوع من حزم SDK.
class FakkarniUser {
  const FakkarniUser({
    required this.id,
    this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  final String id;
  final String? email;
  final String? displayName;

  /// من claim اسمه `is_anonymous` في الـJWT. محدش بيستخدمه لسه —
  /// جولات الترقية (linkIdentity) الجاية هي اللي هتحتاجه.
  final bool isAnonymous;

  @override
  bool operator ==(Object other) =>
      other is FakkarniUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.isAnonymous == isAnonymous;

  @override
  int get hashCode => Object.hash(id, email, displayName, isAnonymous);

  @override
  String toString() => 'FakkarniUser($id، ${email ?? 'من غير إيميل'})';
}

/// ليه الدخول فشل — أنواع محدودة عشان الشاشة تتكلم عربي محدد، مش
/// رسالة SDK إنجليزي خام.
enum SignInFailure {
  /// المستخدم قفل الشاشة بنفسه — **ولا رسالة خالص**، ده مش خطأ.
  aborted,

  offline,
  noGoogleAccount,
  other,
}

class SignInException implements Exception {
  const SignInException(this.reason, [this.cause]);

  final SignInFailure reason;

  /// التقني — للوج، عمره ما بيوصل للشاشة.
  final Object? cause;

  /// الرسالة العربية المتفق عليها — null للإلغاء (صامت).
  String? get message => switch (reason) {
        SignInFailure.aborted => null,
        SignInFailure.offline =>
          'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.',
        SignInFailure.noGoogleAccount => 'مفيش حساب جوجل على الجهاز ده.',
        SignInFailure.other => 'مقدرناش نكمّل التسجيل. جرّب تاني.',
      };

  @override
  String toString() => 'SignInException($reason${cause == null ? '' : '، $cause'})';
}

/// عقد الهوية — Google دلوقتي، وApple بعدين بنفس العقد ده بالظبط.
abstract interface class AuthService {
  /// بيبدأ بالحالة الحالية (جلسة محفوظة أو null) وبيكمّل مع كل تغيير.
  ///
  /// جلسة منتهية بترجع null بهدوء — مفيش crash ومفيش stack trace للمريض.
  Stream<FakkarniUser?> get authState;

  FakkarniUser? get currentUser;

  /// «اربط ابني» — **المكان الوحيد** اللي بينده الدالة دي هو زرار الشاشة.
  /// مش في main ولا splash ولا أي provider بيتحمّل بدري: التنزيلة الجديدة
  /// لازم توصل «يومك» من غير أي جلسة خالص.
  ///
  /// بينجح أو بيرمي [SignInException] — مفيش استثناء تالت بيهرب منه.
  Future<void> signInToLink();

  Future<void> signOut();
}
