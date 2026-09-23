import 'package:fakkarni_admin/app.dart';
import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/screens/dashboard_screen.dart';
import 'package:fakkarni_admin/screens/widgets/brand_mark.dart';
import 'package:fakkarni_admin/screens/widgets/dark_mode_toggle.dart';
import 'package:fakkarni_admin/theme/theme_mode_store.dart';
import 'package:fakkarni_admin/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

/// مخزن في الذاكرة — الاختبار بيشوف اتحفظ إيه، وبيقدر يبدأ باختيار سابق.
class MemoryThemeStore implements ThemeStore {
  MemoryThemeStore({this.initial = ThemePreference.system});
  ThemePreference initial;
  ThemePreference? saved;

  @override
  Future<ThemePreference> load() async => initial;

  @override
  Future<void> save(ThemePreference preference) async => saved = preference;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> pumpApp(WidgetTester tester, FakeAdminService service, MemoryThemeStore store) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AdminApp(service: service, themeStore: store));
  await settle(tester);
}

void main() {
  // `F.darkMode` عام — اختبار سابه ليلي كان هيلوّن اللي بعده.
  tearDown(() => F.setDark(on: false));

  group('العلامة', () {
    testWidgets('كبيرة على شاشة الدخول', (tester) async {
      await pumpApp(tester, FakeAdminService(), MemoryThemeStore());
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('لوحة فكرني'), findsOneWidget);
    });

    testWidgets('وصغيرة في الشريط العلوي', (tester) async {
      final service = FakeAdminService(accounts_: [account()])..email = 'a@b.c';
      await pumpApp(tester, service, MemoryThemeStore());
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('لوحة فكرني'), findsOneWidget);
      expect(find.text('a@b.c'), findsOneWidget);
    });
  });

  group('الوضع الليلي', () {
    testWidgets('الزرار بيقلب الوضع وبيحفظ الاختيار', (tester) async {
      final store = MemoryThemeStore();
      final service = FakeAdminService()..email = 'a@b.c';
      await pumpApp(tester, service, store);
      expect(F.isDark, isFalse);

      await tester.tap(find.byKey(DarkModeToggle.toggleKey));
      await settle(tester);

      expect(F.isDark, isTrue);
      expect(store.saved, ThemePreference.dark, reason: 'اختيار ما اتحفظش بيضيع مع التحديث');
      expect(find.text('نهاري'), findsOneWidget, reason: 'الكلمة بتقول هيعمل إيه لما يدوس تاني');
    });

    testWidgets('والاختيار المحفوظ بيرجع مع فتحة جديدة من غير دوسة', (tester) async {
      final service = FakeAdminService()..email = 'a@b.c';
      await pumpApp(tester, service, MemoryThemeStore(initial: ThemePreference.dark));
      expect(F.isDark, isTrue);
    });

    testWidgets('ومن غير اختيار بيمشي مع النظام', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final service = FakeAdminService()..email = 'a@b.c';
      await pumpApp(tester, service, MemoryThemeStore());
      expect(F.isDark, isTrue);
    });
  });

  group('تقليل الحركة', () {
    Future<void> pumpDashboard(WidgetTester tester) async {
      final service = FakeAdminService(
        counts_: const AdminCounts(totalPatients: 12, totalFollowers: 0, active7d: 0, batteryRestricted: 0),
        accounts_: [account()],
      );
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DashboardScreen(service: service, onSignedOut: () {}, now: DateTime(2026, 9, 23)),
        ),
      ));
      // فريمين من غير وقت: الداتا بتوصل في الأول، وبتترسم في التاني.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('**الضبط**: مع الحركة الرقم لسه بيعدّ في أول فريم', (tester) async {
      await pumpDashboard(tester);
      expect(find.text('١٢'), findsNothing, reason: 'لو ظهر كامل فوراً، الاختبار اللي بعده مش بيثبت حاجة');
      await settle(tester);
      expect(find.text('١٢'), findsOneWidget);
    });

    testWidgets('مع prefers-reduced-motion الرقم بيظهر كامل من أول فريم', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await pumpDashboard(tester);
      expect(find.text('١٢'), findsOneWidget, reason: 'العدّ لازم يتعطّل مع تقليل الحركة');
    });
  });
}
