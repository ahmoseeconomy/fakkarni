import 'package:fakkarni_admin/app.dart';
import 'package:fakkarni_admin/data/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

/// بنبضّ عدد محدود من الفريمات بدل `pumpAndSettle` — نفس قاعدة التطبيق.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> signIn(WidgetTester tester, FakeAdminService service) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(AdminApp(service: service));
  await settle(tester);
  await tester.enterText(find.byType(TextField).first, 'me@example.com');
  await tester.enterText(find.byType(TextField).last, 'pw');
  await tester.tap(find.text('دخول'));
  await settle(tester);
}

void main() {
  testWidgets('حساب حقيقي بس مش أدمن: الجملة بتظهر، والجلسة بتتقفل', (tester) async {
    final service = FakeAdminService()
      ..countsFailure = const AdminException(AdminFailure.notAdmin);

    await signIn(tester, service);

    expect(find.text('الحساب ده مش أدمن.'), findsOneWidget);
    // **الخروج مش تفصيلة**: جلسة واقفة على حساب مش مسموح له حاجة ملهاش لازمة.
    expect(service.signOutCalls, 1);
    expect(find.text('لوحة فكرني'), findsOneWidget); // لسه على شاشة الدخول
    expect(find.text('حدّث'), findsNothing); // اللوحة ما اتفتحتش
  });

  testWidgets('باسورد غلط: جملة عربية، من غير نص سيرفر', (tester) async {
    final service = FakeAdminService()
      ..signInFailure = const AdminException(AdminFailure.badCredentials, 'invalid grant');

    await signIn(tester, service);

    expect(find.text('الإيميل أو الباسورد غلط.'), findsOneWidget);
    expect(find.textContaining('invalid grant'), findsNothing);
    expect(service.signOutCalls, 0, reason: 'ما دخلش أصلاً، مفيش جلسة تتقفل');
  });

  testWidgets('أدمن: بيدخل على اللوحة', (tester) async {
    final service = FakeAdminService(accounts_: [account()]);

    await signIn(tester, service);

    expect(find.text('حدّث'), findsOneWidget);
    expect(find.text('الحاج عاشور'), findsOneWidget);
  });
}
