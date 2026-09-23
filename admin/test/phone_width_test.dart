import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/screens/dashboard_screen.dart';
import 'package:fakkarni_admin/screens/widgets/accounts_cards.dart';
import 'package:fakkarni_admin/screens/widgets/accounts_table.dart';
import 'package:fakkarni_admin/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

/// **المدير ممكن يفتح اللوحة من موبايله.** جدول بعشرة أعمدة على ٣٩٠ بكسل
/// بيبقى تمرير أفقي — فتحت ٧٠٠ الصفوف بتبقى كروت. السطح العريض زي ما هو،
/// واختبار بيثبت الاتنين.
final now = DateTime(2026, 9, 23, 12);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> openAt(
  WidgetTester tester,
  Size size,
  FakeAdminService service,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: F.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: DashboardScreen(service: service, onSignedOut: () {}, now: now),
    ),
  ));
  await settle(tester);
}

FakeAdminService seeded() => FakeAdminService(
      counts_: const AdminCounts(
          totalPatients: 12, totalFollowers: 7, active7d: 9, batteryRestricted: 2),
      accounts_: [
        account(seenAt: now, missed: 3, pending: 1, week: 4, followers: 2),
        account(uuid: 'p2', name: 'سعاد', seenAt: now, battery: 'restricted'),
      ],
    );

void main() {
  // ٣٩٠×٨٤٤ = آيفون حديث؛ ٣٧٥×٦٦٧ = SE، أضيق حاجة بنقيس عليها.
  for (final size in [const Size(390, 844), const Size(375, 667)]) {
    testWidgets('كروت مش جدول على ${size.width.toInt()} بكسل', (tester) async {
      await openAt(tester, size, seeded());

      expect(find.byType(AccountsCards), findsOneWidget);
      expect(find.byType(AccountsTable), findsNothing,
          reason: 'الجدول على موبايل بيبقى تمرير أفقي');
      expect(find.text('الحاج عاشور'), findsOneWidget);
      expect(find.text('سعاد'), findsOneWidget);
    });

    testWidgets('ومفيش فيض على ${size.width.toInt()} بكسل', (tester) async {
      await openAt(tester, size, seeded());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('كل أرقام الصف موجودة في الكارت — ولا عمود اتشال', (tester) async {
    await openAt(tester, const Size(390, 844), seeded());

    for (final label in [
      'ما اتأكدتش ٢٤ س',
      'تنبيهات مفتوحة',
      'تنبيهات ٧ أيام',
      'متابعين',
      'أكواد مستنية',
    ]) {
      expect(find.textContaining(label, findRichText: true), findsWidgets,
          reason: '«$label» مش على الكارت');
    }
  });

  testWidgets('والدوسة على كارت بتفتح اللوحة الجانبية', (tester) async {
    final service = seeded();
    await openAt(tester, const Size(390, 844), service);

    await tester.tap(find.text('سعاد'));
    await settle(tester);

    expect(service.opened, ['p2']);
    expect(find.text('مين بيتابعه'), findsOneWidget);
  });

  testWidgets('وفوق ٧٠٠ الجدول زي ما هو', (tester) async {
    await openAt(tester, const Size(1400, 1000), seeded());

    expect(find.byType(AccountsTable), findsOneWidget);
    expect(find.byType(AccountsCards), findsNothing);
  });
}
