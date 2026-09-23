import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/screens/dashboard_screen.dart';
import 'package:fakkarni_admin/screens/login_screen.dart';
import 'package:fakkarni_admin/screens/widgets/account_panel.dart';
import 'package:fakkarni_admin/screens/widgets/accounts_table.dart';
import 'package:fakkarni_admin/screens/widgets/admin_ui.dart';
import 'package:fakkarni_admin/screens/widgets/sidebar.dart';
import 'package:fakkarni_admin/screens/widgets/tone_filter_chips.dart';
import 'package:fakkarni_admin/screens/widgets/triage_tile.dart';
import 'package:fakkarni_admin/screens/devices_screen.dart';
import 'package:fakkarni_admin/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

/// الهيكل الجديد: شريط جانبي على الواسع، سكة على المتوسط، تنقّل تحت على
/// الموبايل — وتلات شاشات بتتغذّى من نفس الصفوف.
final now = DateTime(2026, 9, 23, 12);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> pumpShell(
  WidgetTester tester,
  FakeAdminService service, {
  Size size = const Size(1400, 1000),
  AdminScreen screen = AdminScreen.overview,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: F.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: DashboardScreen(service: service, onSignedOut: () {}, now: now, initialScreen: screen),
    ),
  ));
  await settle(tester);
}

/// أسطول صغير بكل الحالات: ساكتين، تنبيه، ملاحظة، وتلاتة تمام.
FakeAdminService fleet() => FakeAdminService(
      counts_: const AdminCounts(totalPatients: 7, totalFollowers: 4, active7d: 5, batteryRestricted: 1),
      accounts_: [
        account(uuid: 'aaaaaa-1', name: 'سعاد', seenAt: null),
        account(uuid: 'bbbbbb-2', name: 'هدى', seenAt: now.subtract(const Duration(days: 3))),
        account(uuid: 'cccccc-3', name: 'باسم', seenAt: now, pending: 2, missed: 1),
        account(uuid: 'dddddd-4', name: 'أحمد', seenAt: now, battery: 'restricted', appVersion: '1.5.0+3'),
        account(uuid: 'eeeeee-5', name: 'ليلى', seenAt: now, appVersion: '1.6.0+4'),
        account(uuid: 'ffffff-6', name: 'كريم', seenAt: now, platform: 'ios', appVersion: '1.6.0+4'),
        account(uuid: 'gggggg-7', name: 'منى', seenAt: now, appVersion: '1.4.0+2'),
      ],
      followers_: [const AdminFollower(displayName: 'محمد', relation: 'son', status: 'accepted')],
    );

void main() {
  group('الهيكل', () {
    testWidgets('على الواسع: شريط جانبي بالأقسام التلاتة، والتبديل بيغيّر العنوان', (tester) async {
      await pumpShell(tester, fleet());

      expect(find.byType(AdminSidebar), findsOneWidget);
      expect(tester.getSize(find.byType(AdminSidebar)).width, sidebarWidth);
      expect(find.text('نظرة عامة'), findsWidgets);
      expect(find.text('لوحة فكرني'), findsOneWidget);

      await tester.tap(find.text('الأجهزة'));
      await settle(tester);
      expect(find.text('صحة الأجهزة'), findsOneWidget);
      expect(find.byType(DevicesScreen), findsOneWidget);
    });

    testWidgets('على المتوسط: سكة أيقونات بعرض ٧٢ من غير كلمات', (tester) async {
      await pumpShell(tester, fleet(), size: const Size(900, 900));

      expect(tester.getSize(find.byType(AdminSidebar)).width, railWidth);
      // جوّه الشريط الكلمات تلميحات مش نص — «الحسابات» على كارت الأرقام
      // برّه الشريط شيء تاني.
      expect(find.descendant(of: find.byType(AdminSidebar), matching: find.text('الحسابات')), findsNothing);
      expect(find.descendant(of: find.byType(AdminSidebar), matching: find.byType(Tooltip)), findsWidgets);
    });

    testWidgets('على الموبايل: شريط علوي وتنقّل تحت، ومفيش شريط جانبي', (tester) async {
      await pumpShell(tester, fleet(), size: const Size(390, 844));

      expect(find.byType(AdminSidebar), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('الأجهزة')));
      await settle(tester);
      expect(find.text('صحة الأجهزة'), findsOneWidget);
    });

    testWidgets('اللوحة الجانبية بتنزلق من النهاية — الشمال في العربي', (tester) async {
      await pumpShell(tester, fleet(), screen: AdminScreen.accounts);
      await tester.tap(find.text('باسم'));
      await settle(tester);

      final panel = find.byType(AccountPanel);
      expect(panel, findsOneWidget);
      expect(tester.getTopLeft(panel).dx, 0, reason: 'لازم تلزق في الشمال، بعيد عن الشريط الجانبي');
      expect(tester.getSize(panel).width, drawerWidth);
    });
  });

  group('النظرة العامة', () {
    testWidgets('بلاطات الفرز بعدّادها، والدوسة بتفتح الحسابات مفلترة', (tester) async {
      await pumpShell(tester, fleet());

      expect(find.byType(TriageTile), findsNWidgets(3));
      // ساكتين: سعاد (عمرها ما بعتت) وهدى (من ٣ أيام).
      final silentTile = find.ancestor(of: find.text('مش بيبعت نبضة').first, matching: find.byType(TriageTile));
      expect(find.descendant(of: silentTile, matching: find.text('٢')), findsOneWidget);

      await tester.tap(silentTile);
      await settle(tester);

      expect(find.text('الحسابات'), findsWidgets);
      expect(find.byType(AccountsTable), findsOneWidget);
      Finder inTable(String t) => find.descendant(of: find.byType(DataTable), matching: find.text(t));
      expect(inTable('سعاد'), findsOneWidget);
      expect(inTable('هدى'), findsOneWidget);
      expect(inTable('باسم'), findsNothing, reason: 'الفلتر «مش بيبعت نبضة» لازم يشيل التنبيه');
    });

    testWidgets('أوحش الحسابات بالسبب، والتمام مش فيها', (tester) async {
      await pumpShell(tester, fleet());

      expect(find.text('الموبايل عمره ما بعت نبضة'), findsOneWidget);
      expect(find.text('آخر نبضة من ٣ أيام'), findsOneWidget);
      expect(find.text('٢ تنبيه مفتوح — ١ جرعة ما اتأكدتش'), findsOneWidget);
      expect(find.text('البطارية مقيّدة — التذكير ممكن يتأخر'), findsOneWidget);
      expect(find.text('ليلى'), findsNothing, reason: 'حساب تمام مالوش مكان في «أوحش الحسابات»');
      expect(find.text('صحة الأسطول — ٧ حساب'), findsOneWidget);
    });
  });

  group('الحسابات', () {
    testWidgets('الحبّات بتعدّ على نتيجة البحث، والبحث بأول المعرّف بيشتغل', (tester) async {
      await pumpShell(tester, fleet(), screen: AdminScreen.accounts);

      expect(find.byType(ToneFilterChips), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'cccccc');
      await settle(tester);

      Finder inTable(String t) => find.descendant(of: find.byType(DataTable), matching: find.text(t));
      expect(inTable('باسم'), findsOneWidget);
      expect(inTable('سعاد'), findsNothing);
    });

    testWidgets('٢٥ في الصفحة، وذيل بيقول المدى، واللي بعدها بيكمّل', (tester) async {
      final service = FakeAdminService(accounts_: [
        for (var i = 0; i < 30; i++) account(uuid: 'u$i-x', name: 'مريض $i', seenAt: now),
      ]);
      await pumpShell(tester, fleet()..accounts_ = service.accounts_, screen: AdminScreen.accounts);

      expect(find.text('بيعرض ١–٢٥ من ٣٠'), findsOneWidget);
      expect(find.text('صفحة ١ من ٢'), findsOneWidget);

      // الذيل تحت ٢٥ صف — لازم يتشاف قبل الدوسة، وإلا الدوسة بتقع برّه الشاشة.
      await tester.ensureVisible(find.byTooltip('اللي بعدها'));
      await tester.tap(find.byTooltip('اللي بعدها'));
      await settle(tester);
      expect(find.text('بيعرض ٢٦–٣٠ من ٣٠'), findsOneWidget);
    });

    test('pageRangeLabel — أرقام عربية بفاصل الآلاف', () {
      expect(pageRangeLabel(0, 2347), 'بيعرض ١–٢٥ من ٢٬٣٤٧');
      expect(pageRangeLabel(93, 2347), 'بيعرض ٢٬٣٢٦–٢٬٣٤٧ من ٢٬٣٤٧');
      expect(pageCount(2347), 94);
      expect(pageCount(0), 1);
    });
  });

  group('صحة الأجهزة', () {
    test('ترتيب النسخ بالأرقام مش بالحروف', () {
      expect(compareVersions('1.10.0+2', '1.9.0+9'), greaterThan(0));
      expect(compareVersions('1.6.0+4', '1.6.0+4'), 0);
    });

    testWidgets('النسخ من الأحدث بعلامتها، والتقسيمة بالمنصّة', (tester) async {
      await pumpShell(tester, fleet(), screen: AdminScreen.devices);

      expect(find.text('الأحدث'), findsOneWidget);
      expect(find.text('1.6.0+4'), findsOneWidget);
      expect(find.text('أندرويد'), findsOneWidget);
      expect(find.text('آيفون'), findsOneWidget);
      expect(find.text('محتاجين تدخّل'), findsOneWidget);
      expect(find.text('البطارية مقيّدة'), findsOneWidget);
    });
  });

  group('الدخول', () {
    test('الفحص المحلي', () {
      expect(LoginScreen.validate('', ''), 'اكتب الإيميل والباسورد.');
      expect(LoginScreen.validate('me', 'x'), 'الإيميل مش مظبوط.');
      expect(LoginScreen.validate('me@x.y', 'x'), isNull);
    });

    testWidgets('حقل فاضي ما بيروحش للسيرفر، والحاشية موجودة', (tester) async {
      final service = FakeAdminService();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LoginScreen(service: service, onSignedIn: () {}),
        ),
      ));
      await settle(tester);

      expect(find.textContaining('الصلاحية بتتحقق في السيرفر'), findsOneWidget);
      await tester.tap(find.text('دخول'));
      await settle(tester);
      expect(find.text('اكتب الإيميل والباسورد.'), findsOneWidget);
      expect(service.signInCalls, 0);
    });
  });
}
