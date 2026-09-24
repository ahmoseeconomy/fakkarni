import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/billing/subscription_remote.dart';
import 'package:fakkarni/data/billing/subscription_service.dart';
import 'package:fakkarni/domain/billing/family_plan.dart';
import 'package:fakkarni/features/billing/family_plan_screen.dart';

import '../../data/billing/subscription_service_test.dart' show FakeRemote, FakeStore;
import '../scan/scan_test_support.dart' show screenTest, settle;

/// «اشتراك العيلة»: الجملة الثابتة، مين متغطّي، الأسعار من المتجر، الشراء
/// بيمرّ على التحقق، والاسترجاع موجود.
void main() {
  final now = DateTime(2026, 9, 24, 12);
  late FakeRemote remote;
  late FakeStore store;
  late SubscriptionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    remote = FakeRemote()
      ..next = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: now.subtract(const Duration(days: 20)));
    store = FakeStore();
    service = SubscriptionService(remote: remote, store: store, clock: () => now)..patientUuid = 'p1';
    await service.load();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: FamilyPlanScreen(service: service, patientName: 'الحاج أحمد', coveredNames: const ['محمد', 'سارة'], now: now),
    ));
    await settle(tester);
  }

  screenTest('الجملة الثابتة، المتغطّيين بأساميهم، والقايمتين', (tester) async {
    await pump(tester);
    expect(find.text(remindersStayFreeLine), findsOneWidget);
    expect(find.text('الحاج أحمد، محمد، سارة'), findsOneWidget);
    expect(find.textContaining('خلص'), findsWidgets);
    for (final f in AppFeature.values) {
      expect(find.text(f.label), findsOneWidget, reason: f.name);
    }
  });

  screenTest('الأسعار من المتجر بالحرف، والشراء بيمرّ على التحقق وبيقول تمام', (tester) async {
    await pump(tester);
    expect(find.textContaining('49 EGP'), findsOneWidget);
    expect(find.textContaining('399 EGP'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-buy-${SubscriptionConfig.yearlyProductId}')));
    await settle(tester);
    expect(remote.verified.single.$2, SubscriptionConfig.yearlyProductId);
    expect(find.byKey(const ValueKey('plan-notice')), findsOneWidget);
    expect(find.textContaining('شغّال'), findsWidgets);
    expect(service.allowed(AppFeature.circle), isTrue);
  });

  screenTest('المتجر فاضي (المنتجات لسه ما اتعملتش): جملة، ولا زرار سعر', (tester) async {
    store.catalogue = const [];
    await pump(tester);
    expect(find.byKey(const ValueKey('plan-no-products')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-buy-${SubscriptionConfig.monthlyProductId}')), findsNothing);
    expect(find.byKey(const ValueKey('plan-restore')), findsOneWidget);
  });

  screenTest('التحقق مش متظبط: الشاشة بتقولها ومفيش قفل', (tester) async {
    remote.verifyOutcome = VerifyOutcome.notConfigured;
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('plan-buy-${SubscriptionConfig.monthlyProductId}')));
    await settle(tester);
    expect(find.textContaining('لسه مش متظبط'), findsOneWidget);
  });
}
