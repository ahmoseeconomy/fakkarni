// «للمطوّر» (سجل التشخيص + «اطمن إن التذكير هيشتغل») **مش موجود في نسخة
// المتجر** — إلا من باب المطوّر (٧ دوسات على سطر النسخة). `kReleaseMode`
// ثابت وقت الترجمة، فالشاشة بتاخد `releaseMode` بارامتر (افتراضيه
// kReleaseMode) عشان الاختبار يقدر يشغّل الحالتين.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/features/settings/settings_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester, {required bool release}) async {
    final h = Harness();
    await h.setUp();
    addTearDown(h.tearDown);
    await tester.runAsync(() async {
      await h.pump(tester, SettingsScreen(releaseMode: release));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    // القسم آخر الصفحة — نلفّ لحد سطر النسخة اللي بعده
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-version')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }

  screenTest('release: مفيش «للمطوّر» ولا «سجل التشخيص» ولا «اطمن إن التذكير هيشتغل»', (tester) async {
    await pumpSettings(tester, release: true);
    expect(find.text('للمطوّر'), findsNothing);
    expect(find.text('سجل التشخيص'), findsNothing);
    expect(find.text('اطمن إن التذكير هيشتغل'), findsNothing);
    // وسطر النسخة موجود — هو الباب
    expect(find.byKey(const ValueKey('settings-version')), findsOneWidget);
  });

  screenTest('debug/profile: القسم ظاهر', (tester) async {
    await pumpSettings(tester, release: false);
    expect(find.text('للمطوّر'), findsOneWidget);
    expect(find.text('سجل التشخيص'), findsOneWidget);
    expect(find.text('اطمن إن التذكير هيشتغل'), findsOneWidget);
  });
}
