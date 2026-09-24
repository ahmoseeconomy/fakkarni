import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/billing/store_purchases.dart';
import 'package:fakkarni/data/billing/subscription_remote.dart';
import 'package:fakkarni/data/billing/subscription_service.dart';
import 'package:fakkarni/domain/billing/family_plan.dart';

class FakeRemote implements SubscriptionRemote {
  FamilySubscription? next;
  Object? failure;
  VerifyOutcome verifyOutcome = VerifyOutcome.active;
  final verified = <(String, String, String)>[];

  @override
  Future<FamilySubscription?> load(String patientUuid) async {
    if (failure != null) throw failure!;
    return next;
  }

  @override
  Future<VerifyOutcome> verify({required String patientUuid, required String store, required String productId, required String receipt}) async {
    verified.add((store, productId, receipt));
    if (verifyOutcome == VerifyOutcome.active) {
      next = FamilySubscription(status: SubscriptionStatus.active, trialEndsAt: DateTime(2026), expiresAt: DateTime(2027));
    }
    return verifyOutcome;
  }
}

class FakeStore implements StorePurchases {
  List<StoreProduct> catalogue = const [
    StoreProduct(id: SubscriptionConfig.monthlyProductId, title: 'شهري', price: '49 EGP'),
    StoreProduct(id: SubscriptionConfig.yearlyProductId, title: 'سنوي', price: '399 EGP'),
  ];
  bool cancel = false;
  List<StorePurchase> restored = const [];

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => [for (final p in catalogue) if (ids.contains(p.id)) p];
  @override
  Future<StorePurchase?> buy(StoreProduct product) async =>
      cancel ? null : StorePurchase(store: 'apple', productId: product.id, receipt: 'tx-${product.id}');
  @override
  Future<List<StorePurchase>> restore() async => restored;
}

void main() {
  final now = DateTime(2026, 9, 24, 12);
  late FakeRemote remote;
  late FakeStore store;
  late SubscriptionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    remote = FakeRemote();
    store = FakeStore();
    service = SubscriptionService(remote: remote, store: store, clock: () => now)..patientUuid = 'p1';
    await service.load();
  });

  test('من غير أي قراية: كل حاجة مسموحة', () {
    for (final f in AppFeature.values) {
      expect(service.allowed(f), isTrue, reason: f.name);
    }
  });

  test('منتهي: العائلي بيتقفل، والمجاني لأ', () async {
    remote.next = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: now.subtract(const Duration(days: 40)));
    await service.refresh();
    expect(service.allowed(AppFeature.circle), isFalse);
    expect(service.allowed(AppFeature.scans), isFalse);
    expect(service.allowed(AppFeature.reminders), isTrue);
    expect(service.allowed(AppFeature.medications), isTrue);
  });

  test('التحقق مش واصل: آخر حالة معروفة بتمشي — نشط يفضل نشط، ومنتهي يفضل منتهي', () async {
    remote.next = FamilySubscription(status: SubscriptionStatus.active, trialEndsAt: now, expiresAt: now.add(const Duration(days: 20)));
    await service.refresh();
    remote.failure = Exception('offline');
    final again = SubscriptionService(remote: remote, store: store, clock: () => now)..patientUuid = 'p1';
    await again.load();
    await again.refresh();
    expect(again.current, isNull);
    expect(again.allowed(AppFeature.circle), isTrue);

    remote.failure = null;
    remote.next = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: now);
    await again.refresh();
    remote.failure = Exception('offline');
    final third = SubscriptionService(remote: remote, store: store, clock: () => now)..patientUuid = 'p1';
    await third.load();
    await third.refresh();
    expect(third.allowed(AppFeature.circle), isFalse);
    expect(third.allowed(AppFeature.reminders), isTrue);
  });

  test('التصدير: أول ٣ مجاني حتى لو منتهي، والرابع بوابة', () async {
    remote.next = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: now);
    await service.refresh();
    for (var i = 0; i < freeExports; i++) {
      expect(service.allowed(AppFeature.exportBeyondFree), isTrue, reason: 'export $i');
      await service.noteExport();
    }
    expect(service.allowed(AppFeature.exportBeyondFree), isFalse);
    // العدّ محفوظ
    final again = SubscriptionService(remote: remote, store: store, clock: () => now);
    await again.load();
    expect(again.exportsUsed, freeExports);
  });

  test('الشراء: المتجر ← التحقق على السيرفر بالإيصال ← الحالة بتتحدّث', () async {
    remote.next = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: now);
    await service.refresh();
    final products = await service.products();
    expect(products.map((p) => p.id), containsAll(SubscriptionConfig.productIds));
    final outcome = await service.buy(products.first);
    expect(outcome, VerifyOutcome.active);
    expect(remote.verified.single, ('apple', SubscriptionConfig.monthlyProductId, 'tx-${SubscriptionConfig.monthlyProductId}'));
    expect(service.allowed(AppFeature.circle), isTrue);
  });

  test('لغى الشراء = null ومفيش تحقق؛ التحقق مش متظبط = بيتقال ومفيش قفل', () async {
    store.cancel = true;
    expect(await service.buy(store.catalogue.first), isNull);
    expect(remote.verified, isEmpty);
    store.cancel = false;
    remote.verifyOutcome = VerifyOutcome.notConfigured;
    expect(await service.buy(store.catalogue.first), VerifyOutcome.notConfigured);
    expect(service.allowed(AppFeature.circle), isTrue);
  });

  test('الاسترجاع بيمشي على المشتريات لحد ما واحدة تنجح', () async {
    store.restored = const [
      StorePurchase(store: 'google', productId: 'other', receipt: 'x'),
      StorePurchase(store: 'google', productId: SubscriptionConfig.yearlyProductId, receipt: 'tok'),
    ];
    remote.verifyOutcome = VerifyOutcome.invalid;
    expect(await service.restore(), VerifyOutcome.invalid);
    remote.verifyOutcome = VerifyOutcome.active;
    expect(await service.restore(), VerifyOutcome.active);
  });

  test('من غير متجر ولا مريض: الشراء بيرجّع failed من غير ما يرمي', () async {
    final bare = SubscriptionService(remote: remote, clock: () => now);
    expect(await bare.buy(store.catalogue.first), VerifyOutcome.failed);
    expect(await bare.products(), isEmpty);
  });

  test('المحاكاة (مش في نسخة المتجر) بتقلب الحالة وبتتحفظ', () async {
    await service.setDebugOverride(false);
    expect(service.allowed(AppFeature.circle), isFalse);
    expect(service.allowed(AppFeature.reminders), isTrue);
    final again = SubscriptionService(remote: remote, store: store, clock: () => now);
    await again.load();
    expect(again.debugOverride, isFalse);
    await again.setDebugOverride(null);
    expect(again.allowed(AppFeature.circle), isTrue);
  });
}
