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

  group('كارت «التنبيهات هتقف / واقفة»', () {
    String d(DateTime t) => '${t.day}/${t.month}';
    FamilyNotice at(FamilySubscription? s, DateTime when, {bool? last, bool? debug}) =>
        familyNotice(subscription: s, now: when, lastKnownAllowed: last, debugOverride: debug);

    test('التجربة: مفيش كارت قبل ٧ أيام، ومن ٧ لحد يوم النهاية فيه، بعلامته', () {
      final s = sub(SubscriptionStatus.trial, trialEnds: DateTime(2026, 10, 1, 12));
      expect(at(s, DateTime(2026, 9, 23, 9)).kind, FamilyNoticeKind.none); // ٨ أيام
      final seven = at(s, DateTime(2026, 9, 24, 9));
      expect(seven.kind, FamilyNoticeKind.endingSoon);
      expect((seven.daysLeft, seven.milestone), (7, 7));
      expect(at(s, DateTime(2026, 9, 28, 9)).milestone, 3);
      expect(at(s, DateTime(2026, 9, 30, 9)).milestone, 1);
      final today = at(s, DateTime(2026, 10, 1, 8));
      expect((today.kind, today.daysLeft), (FamilyNoticeKind.endingSoon, 0));
      expect(at(s, DateTime(2026, 10, 1, 13)).kind, FamilyNoticeKind.ended);
    });

    test('النشط: النهاية = الانتهاء + ٣ أيام مهلة — نفس اليوم اللي السيرفر بيقف فيه', () {
      final s = sub(SubscriptionStatus.active, expires: DateTime(2026, 10, 1, 12));
      final n = at(s, DateTime(2026, 9, 30, 9));
      expect(n.endsAt, DateTime(2026, 10, 4, 12));
      expect(n.daysLeft, 4);
      expect(at(s, DateTime(2026, 10, 4, 13)).kind, FamilyNoticeKind.ended);
      expect(at(sub(SubscriptionStatus.active), now).kind, FamilyNoticeKind.none);
    });

    test('منتهي ← واقفة؛ مجهول ← لا كارت؛ آخر حالة «مقفول» ← واقفة؛ المحاكاة بتغلب', () {
      expect(at(sub(SubscriptionStatus.expired), now).kind, FamilyNoticeKind.ended);
      expect(at(null, now).kind, FamilyNoticeKind.none);
      expect(at(null, now, last: true).kind, FamilyNoticeKind.none);
      expect(at(null, now, last: false).kind, FamilyNoticeKind.ended);
      expect(at(sub(SubscriptionStatus.active), now, debug: false).kind, FamilyNoticeKind.ended);
      expect(at(sub(SubscriptionStatus.expired), now, debug: true).kind, FamilyNoticeKind.none);
    });

    test('الكلام: أسامي المتابعين للمريض، «تنبيهاتك عن …» للمتابع، والنهارده بكلمته', () {
      final n = at(sub(SubscriptionStatus.trial, trialEnds: DateTime(2026, 9, 27, 12)), DateTime(2026, 9, 24, 9));
      expect(familyEndingLine(notice: n, date: d, followerNames: ['محمد', 'سارة']),
          'تنبيهات محمد وسارة هتقف يوم 27/9 لو الاشتراك ما اتجددش');
      expect(familyEndingLine(notice: n, date: d), 'تنبيهات اللي بيتابعوك هتقف يوم 27/9 لو الاشتراك ما اتجددش');
      expect(familyEndingLine(notice: n, date: d, patientName: 'الحاج أحمد', forFollower: true),
          'تنبيهاتك عن الحاج أحمد هتقف يوم 27/9 لو الاشتراك ما اتجددش');
      final today = at(sub(SubscriptionStatus.trial, trialEnds: DateTime(2026, 9, 24, 20)), DateTime(2026, 9, 24, 9));
      expect(familyEndingLine(notice: today, date: d, followerNames: ['محمد']), 'تنبيهات محمد هتقف النهارده لو الاشتراك ما اتجددش');
      expect(familyEndedFollowerLine('الحاج أحمد'), 'التنبيهات واقفة — مش هتتبلّغ لو الحاج أحمد فوّت جرعة');
      expect(familyEndedPatientLine, 'اللي بيتابعوك مش بيتبلّغوا دلوقتي');
      expect(joinArabicNames(['أ', 'ب', 'ج']), 'أ، ب وج');
    });
  });
}
