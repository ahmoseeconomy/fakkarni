// ملخص الأسبوع فوق «متابعة» عند الابن (طلب المدير، ٤ أكتوبر ٢٠٢٦).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/care/caregiver_screen.dart';

import '../scan/scan_test_support.dart' show settle, screenTest, expectCaregiverDensity;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, alert, event, snapshot, now;

void main() {
  screenTest('فوق «متابعة»: الـ٧ أيام الكاملة بس — النهارده برّه — وبكثافة الابن', (tester) async {
    final remote = FakeCaregiverRemote()
      ..next = snapshot([
        event('Concor 5mg', DateTime(2026, 8, 30, 8), 'taken', actedAt: DateTime(2026, 8, 30, 8, 5)),
        event('Concor 5mg', DateTime(2026, 8, 29, 8), 'missed'),
        event('Concor 5mg', DateTime(2026, 8, 28, 8), 'skipped'),
        event('Concor 5mg', DateTime(2026, 8, 31, 8), 'pending'), // النهارده — برّه
      ]);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverScreen(remote: remote, now: now)),
    ));
    await settle(tester);

    expect(find.byKey(const ValueKey('care-weekly-summary')), findsOneWidget);
    expect(find.text('ملخص الأسبوع — ٢٤ أغسطس لـ٣٠ أغسطس'), findsOneWidget);
    expect(find.text('اتاخد ١ من ٣ جرعات — و١ متخطّية'), findsOneWidget);
    expect(find.text('ما اتأكدتش: ١ — Concor 5mg (السبت ٨:٠٠ ص)'), findsOneWidget);
    expect(find.text('مفيش مواعيد جاية'), findsOneWidget);
    expectCaregiverDensity(tester);
  });

  screenTest('الملخص تحت التنبيهات المفتوحة — التنبيه جرعة بتفوت دلوقتي', (tester) async {
    final remote = FakeCaregiverRemote()
      ..next = snapshot([
        event('Concor 5mg', DateTime(2026, 8, 31, 8), 'pending'),
      ], alerts: [alert()]);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverScreen(remote: remote, now: now)),
    ));
    await settle(tester);
    final alertsY = tester.getTopLeft(find.text('تنبيهات')).dy;
    final summaryY = tester.getTopLeft(find.byKey(const ValueKey('care-weekly-summary'))).dy;
    expect(summaryY, greaterThan(alertsY));
  });
}
