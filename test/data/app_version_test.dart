// «النسخة dev» كانت بتظهر في نسخة release (آيفون، ٢٦ سبتمبر ٢٠٢٦): النسخة
// كانت من `--dart-define=APP_VERSION` مش من الحزمة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fakkarni/data/app_version.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';

import '../features/scan/scan_test_support.dart';

void main() {
  group('versionLabel', () {
    test('النسخة ورقم البناء', () => expect(versionLabel(version: '2.0.0', build: '88', debug: false), '2.0.0 (88)'));
    test('من غير رقم بناء', () => expect(versionLabel(version: '2.0.0', build: '', debug: false), '2.0.0'));
    test('«dev» في debug بس', () {
      expect(versionLabel(version: '', build: '', debug: true), 'dev');
      expect(versionLabel(version: null, build: null, debug: false), '', reason: 'release عمره ما يقول dev');
    });
  });

  test('load بتقرا من الحزمة', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
        appName: 'فكرني', packageName: 'com.fakrny.app', version: '2.0.0', buildNumber: '88', buildSignature: '');
    await AppVersion.load();
    expect(AppVersion.current, '2.0.0 (88)');
    expect(AppVersion.label, '2.0.0 (88)');
    AppVersion.current = null;
  });

  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  screenTest('الإعدادات بتعرض النسخة الحقيقية، مش dev', (tester) async {
    AppVersion.current = '2.0.0 (88)';
    addTearDown(() => AppVersion.current = null);
    await tester.runAsync(() async {
      await h.pump(tester, const SettingsScreen());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    final row = find.byKey(const ValueKey('settings-version'));
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('النسخة ٢.٠.٠ (٨٨)'), findsOneWidget);
    expect(find.textContaining('dev'), findsNothing);
  });
}
