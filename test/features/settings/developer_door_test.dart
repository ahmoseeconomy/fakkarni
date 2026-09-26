// باب المطوّر في نسخة release: ٧ دوسات على سطر النسخة بتكتب `fkdiag.on`
// جنب السجل، و`diag` بتقرا العلامة دي من غير أي قناة — فالـisolate بيشوفها
// هو كمان. في debug/profile القسم ظاهر على طول، والباب بيغيّر العلامة بس.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fakkarni/core/diagnostics.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';

import '../scan/scan_test_support.dart';

class _Docs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Docs(this.dir);
  final Directory dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  late Directory docs;

  setUpAll(() {
    docs = Directory.systemTemp.createTempSync('fkdiag-door');
    PathProviderPlatform.instance = _Docs(docs);
  });
  tearDownAll(() => docs.deleteSync(recursive: true));

  File marker() => File('${docs.path}/$diagOptInFileName');

  test('العلامة ملف جنب السجل — بتتكتب وبتتشال، والقراية بتقول الحقيقة', () async {
    expect(await diagReleaseOptIn(), isFalse);
    expect(await setDiagReleaseOptIn(true), isTrue);
    expect(marker().existsSync(), isTrue);
    expect(await diagReleaseOptIn(), isTrue);
    expect(await setDiagReleaseOptIn(false), isFalse);
    expect(marker().existsSync(), isFalse);
    expect(await diagReleaseOptIn(), isFalse);
  });

  test('الثابت اللي التوثيق بيسمّيه', () {
    expect(diagOptInFileName, 'fkdiag.on');
  });

  screenTest('٧ دوسات على سطر النسخة بتفتح الباب، و٧ تاني بتقفله', (tester) async {
    final h = Harness();
    await h.setUp();
    addTearDown(h.tearDown);
    await tester.runAsync(() async {
      await h.pump(tester, const SettingsScreen());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    final row = find.byKey(const ValueKey('settings-version'));
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('النسخة dev'), findsOneWidget, reason: 'من غير APP_VERSION');

    Future<void> tapTimes(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() async {
          await tester.tap(row, warnIfMissed: false);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await settle(tester);
      }
    }

    await tapTimes(6);
    expect(marker().existsSync(), isFalse, reason: '٦ مش كفاية');
    await tapTimes(1);
    expect(marker().existsSync(), isTrue);
    expect(find.textContaining('باب المطوّر اتفتح'), findsOneWidget);
    // القسم موجود في الاختبار أصلاً (مش release) — الباب بيغيّر العلامة بس
    expect(find.text('للمطوّر'), findsOneWidget);

    await tapTimes(7);
    expect(marker().existsSync(), isFalse);
    expect(find.text('النسخة dev'), findsOneWidget);
  });
}
