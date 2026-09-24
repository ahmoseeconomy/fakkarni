/// حالة اشتراك العيلة من السحابة والتحقق من الشراء — الواجهة. الـSDK في
/// `supabase_subscription_remote.dart` وبس.
library;

import '../../domain/billing/family_plan.dart';

enum VerifyOutcome {
  /// المتجر أكّد والصف اتكتب.
  active,

  /// أسرار المتجر مش متظبطة عندنا (HANDOVER B7) — الموبايل بيفضل في التجربة/المهلة.
  notConfigured,

  /// المتجر رفض الإيصال.
  invalid,

  /// شبكة أو خطأ — بنسيب آخر حالة معروفة.
  failed,
}

abstract interface class SubscriptionRemote {
  /// null = مفيش صف (مريض من قبل التريجر) أو الطلب ما وصلش؛ المُنادي هو
  /// اللي بيفرّق بالاستثناء.
  Future<FamilySubscription?> load(String patientUuid);

  Future<VerifyOutcome> verify({
    required String patientUuid,
    required String store,
    required String productId,
    required String receipt,
  });
}
