import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/billing/family_plan.dart';

/// بوابة اشتراك العيلة (دارت نقية): المجاني مجاني مهما حصل، والعائلي
/// بيمشي على التجربة/النشط، والمجهول = مسموح، والمهلة بتتحسب.
void main() {
  final now = DateTime(2026, 9, 24, 12);
  FamilySubscription sub(SubscriptionStatus s, {DateTime? trialEnds, DateTime? expires}) =>
      FamilySubscription(status: s, trialEndsAt: trialEnds ?? now.add(const Duration(days: 14)), expiresAt: expires);

  test('الميزة المجانية مسموحة دايماً — منتهي، محاكاة منتهية، مجهول', () {
    for (final f in AppFeature.freeForever) {
      expect(featureAllowed(f, subscription: sub(SubscriptionStatus.expired), now: now), isTrue);
      expect(featureAllowed(f, subscription: null, now: now, lastKnownAllowed: false, debugOverride: false), isTrue);
    }
    expect(AppFeature.freeForever, contains(AppFeature.reminders));
    expect(AppFeature.freeForever, contains(AppFeature.medications));
    expect(AppFeature.freeForever, contains(AppFeature.emergencyCard));
  });

  test('التجربة بتسمح لحد نهايتها وبعدها لأ', () {
    final s = sub(SubscriptionStatus.trial, trialEnds: now.add(const Duration(days: 1)));
    expect(featureAllowed(AppFeature.circle, subscription: s, now: now), isTrue);
    expect(featureAllowed(AppFeature.circle, subscription: s, now: now.add(const Duration(days: 2))), isFalse);
  });

  test('النشط بيسمح لحد الانتهاء + ٣ أيام مهلة', () {
    final s = sub(SubscriptionStatus.active, expires: now);
    expect(featureAllowed(AppFeature.scans, subscription: s, now: now.add(const Duration(days: 2))), isTrue);
    expect(featureAllowed(AppFeature.scans, subscription: s, now: now.add(const Duration(days: 4))), isFalse);
    expect(SubscriptionConfig.graceDays, 3);
  });

  test('المنتهي بيقفل العائلي بس', () {
    expect(featureAllowed(AppFeature.nurseMirror, subscription: sub(SubscriptionStatus.expired), now: now), isFalse);
    expect(featureAllowed(AppFeature.reminders, subscription: sub(SubscriptionStatus.expired), now: now), isTrue);
  });

  test('التحقق مش واصل: آخر حالة معروفة، ومن غيرها مسموح — عمرنا ما نقفل بسبب شبكة', () {
    expect(featureAllowed(AppFeature.circle, subscription: null, now: now), isTrue);
    expect(featureAllowed(AppFeature.circle, subscription: null, now: now, lastKnownAllowed: true), isTrue);
    expect(featureAllowed(AppFeature.circle, subscription: null, now: now, lastKnownAllowed: false), isFalse);
  });

  test('المحاكاة بتغلب الحقيقة — للتطوير بس', () {
    expect(featureAllowed(AppFeature.circle, subscription: sub(SubscriptionStatus.expired), now: now, debugOverride: true), isTrue);
    expect(featureAllowed(AppFeature.circle, subscription: sub(SubscriptionStatus.active), now: now, debugOverride: false), isFalse);
  });

  test('JSON رايح جاي', () {
    final s = FamilySubscription(status: SubscriptionStatus.active, trialEndsAt: now, expiresAt: now.add(const Duration(days: 30)), store: 'apple', productId: SubscriptionConfig.yearlyProductId);
    final back = FamilySubscription.fromJson(s.toJson().cast<String, dynamic>())!;
    expect(back.status, SubscriptionStatus.active);
    expect(back.expiresAt, s.expiresAt);
    expect(back.productId, SubscriptionConfig.yearlyProductId);
    expect(FamilySubscription.fromJson({'status': 'weird', 'trial_ends_at': 'x'}), isNull);
  });

  test('سطر الحالة بكلام البيت، والجملة الثابتة بالحرف', () {
    String d(DateTime t) => '${t.day}/${t.month}';
    expect(subscriptionStatusLine(null, now, d), contains('كل حاجة شغّالة'));
    expect(subscriptionStatusLine(sub(SubscriptionStatus.trial), now, d), contains('التجربة المجانية شغّالة'));
    expect(subscriptionStatusLine(sub(SubscriptionStatus.expired), now, d), contains('التذكيرات شغّالة'));
    expect(remindersStayFreeLine, 'تذكير الدوا مجاني للأبد — ما بيقفش بسبب الاشتراك.');
  });
}
