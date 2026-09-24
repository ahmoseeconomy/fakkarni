import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/health/health_watcher.dart';
import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_report.dart';
import 'package:fakkarni/features/today/notifications_off_line.dart';

import '../scan/scan_test_support.dart';

/// السطر الوحيد عن «مشكلة» على شاشة المريض: إذن التنبيهات مقفول.
void main() {
  final now = DateTime(2026, 9, 24, 10);

  HealthReport report(List<HealthFinding> findings) => HealthReport(findings, now);

  const denied = HealthFinding(
    code: HealthCode.notificationPermission,
    severity: Severity.broken,
    title: 'إذن التنبيهات مقفول',
    why: '',
    fix: HealthFix.openNotificationSettings,
  );
  const stale = HealthFinding(
    code: HealthCode.staleSync,
    severity: Severity.broken,
    title: 'التأكيدات لسه ما وصلتش',
    why: '',
    fix: HealthFix.syncNow,
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: NotificationsOffLine()),
      ),
    ));
    await tester.pump();
  }

  tearDown(() => HealthWatcher.latest.value = null);

  testWidgets('الإذن مقفول → الجملة والزرار، من غير كود ولا شرح', (tester) async {
    HealthWatcher.latest.value = report(const [denied]);
    await pump(tester);

    expect(find.text('التنبيهات مقفولة — افتحها عشان نفكّرك'), findsOneWidget);
    expect(find.text('افتح الإعدادات'), findsOneWidget);
    expect(find.textContaining('notificationPermission'), findsNothing);
    expect(find.text('إذن التنبيهات مقفول'), findsNothing, reason: 'عنوان الفحص مش للمريض');
    expectNoRedAndMinSize(tester);

    // الدوسة ما بتوقّعش وقناة النظام مش موجودة في الاختبار
    await tester.tap(find.text('افتح الإعدادات'));
    await tester.pump();
  });

  testWidgets('أي كود تاني مكسور → مفيش ولا سطر — بيتصلّح لوحده أو بيروح للأدمن', (tester) async {
    HealthWatcher.latest.value = report(const [stale]);
    await pump(tester);
    expect(find.byKey(const ValueKey('notifications-off')), findsNothing);
    expect(find.textContaining('التأكيدات'), findsNothing);
  });

  testWidgets('الإذن اتفتح → السطر بيختفي من نتيجة الفحص الجديدة', (tester) async {
    HealthWatcher.latest.value = report(const [denied]);
    await pump(tester);
    expect(find.byKey(const ValueKey('notifications-off')), findsOneWidget);

    HealthWatcher.latest.value = report(const []);
    await tester.pump();
    expect(find.byKey(const ValueKey('notifications-off')), findsNothing);
  });
}
