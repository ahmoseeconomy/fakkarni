import 'package:fakkarni_admin/screens/widgets/admin_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';
import 'shell_test.dart' show now, pumpShell, settle;

/// أكواد كل جهاز على اللوحة — نظرة عامة، صحة الأجهزة، ولوحة الحساب.
void main() {
  FakeAdminService withDevices() => FakeAdminService(
        accounts_: [
          account(uuid: 'p1', name: 'الحاج عاشور', seenAt: now),
          account(uuid: 'p2', name: 'هدى', seenAt: now),
          account(uuid: 'p3', name: 'ليلى', seenAt: now),
        ],
        devices_: [
          device(
            uuid: 'p1',
            name: 'الحاج عاشور',
            checkedAt: now.subtract(const Duration(hours: 1)),
            codes: ['notificationPermission', 'staleSync'],
            lastSyncAt: now.subtract(const Duration(days: 2)),
          ),
          device(uuid: 'p2', name: 'هدى', checkedAt: now.subtract(const Duration(days: 3))),
          device(uuid: 'p3', name: 'ليلى', checkedAt: now),
        ],
      );

  testWidgets('نظرة عامة: العدّ والقايمة بالكلمات، والساكت بمدّته', (tester) async {
    await pumpShell(tester, withDevices());

    expect(find.text('أجهزة فيها مشكلة — ٢'), findsOneWidget);
    expect(find.text('الإشعارات مقفولة'), findsOneWidget);
    expect(find.text('مزامنة واقفة من يومين'), findsOneWidget);
    expect(find.text('ماوصلش منه حاجة من ٣ أيام'), findsOneWidget);
    expect(find.text('آخر فحص من ساعة'), findsOneWidget);
    // السليمة مش في القايمة
    expect(find.textContaining('ليلى'), findsNothing);
    // ولا كود بالاسم اللاتيني
    expect(find.textContaining('notificationPermission'), findsNothing);
    expect(find.textContaining('staleSync'), findsNothing);
  });

  testWidgets('صحة الأجهزة: نفس القايمة كاملة', (tester) async {
    await pumpShell(tester, withDevices(), screen: AdminScreen.devices);
    expect(find.byKey(const ValueKey('devices-device-problems')), findsOneWidget);
    expect(find.text('أجهزة فيها مشكلة — ٢'), findsOneWidget);
    expect(find.text('الإشعارات مقفولة'), findsOneWidget);
  });

  testWidgets('دوسة على جهاز بتفتح حساب صاحبه، ولوحته فيها «مشاكل الجهاز»', (tester) async {
    await pumpShell(tester, withDevices());
    await tester.tap(find.text('الإشعارات مقفولة'));
    await settle(tester);

    expect(find.text('مشاكل الجهاز'), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-device-problems')), findsOneWidget);
    // الكود في الصف وفي اللوحة — اتنين
    expect(find.text('الإشعارات مقفولة'), findsNWidgets(2));
  });

  testWidgets('مفيش أجهزة فيها مشكلة → جملة واحدة، والعدّ صفر', (tester) async {
    await pumpShell(tester, FakeAdminService(
      accounts_: [account(uuid: 'p3', name: 'ليلى', seenAt: now)],
      devices_: [device(uuid: 'p3', name: 'ليلى', checkedAt: now)],
    ));
    expect(find.text('أجهزة فيها مشكلة — ٠'), findsOneWidget);
    expect(find.textContaining('مفيش جهاز فيه مشكلة'), findsOneWidget);
  });
}
