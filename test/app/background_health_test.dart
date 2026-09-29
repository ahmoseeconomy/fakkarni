// الفحص اليومي في الخلفية: نفس المراقب، ولا إشعار، ومعرّفه مرآة بين دارت
// وInfo.plist، والتسجيل على iOS في didFinishLaunching (UIScene).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/background_health.dart';

void main() {
  final src = File('lib/app/background_health.dart').readAsStringSync();
  final main = File('lib/main.dart').readAsStringSync();
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  test('نقطة دخول للـisolate، وبتنده المراقب نفسه بخنقه', () {
    expect(src, contains("@pragma('vm:entry-point')\nvoid healthBackgroundDispatcher()"));
    expect(src, contains('HealthWatcher(collector: HealthCollector(services), heartbeat: heartbeat).runIfDue()'));
    expect(src, contains('DartPluginRegistrant.ensureInitialized()'));
  });

  test('ولا إشعار ولا شاشة ولا جدولة جديدة من الخلفية — وdiag مش debugPrint', () {
    for (final banned in ['NotificationService', 'showNow', 'zonedSchedule', 'scheduleDose', 'Navigator', 'runApp', 'debugPrint(']) {
      expect(src, isNot(contains(banned)), reason: '$banned في الفحص الخلفي');
    }
    expect(src, contains("diag('Health:"));
  });

  test('المعرّف مرآة بين دارت وInfo.plist، والوضع fetch وبس', () {
    expect(BackgroundHealth.taskId, 'com.fakrny.app.health-daily');
    expect(plist, contains('<key>BGTaskSchedulerPermittedIdentifiers</key>\n\t<array>\n\t\t<string>${BackgroundHealth.taskId}</string>\n\t</array>'));
    expect(plist, contains('<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>fetch</string>\n\t</array>'));
    // مفيش remote-notification ولا processing — مفيش APNs (الدين ٣) ومفيش شغل خلفية تاني
    expect(plist, isNot(contains('remote-notification')));
    expect(plist, isNot(contains('<string>processing</string>')));
    expect(BackgroundHealth.every, const Duration(hours: 24));
  });

  test('iOS: registerLaunchHandlers قبل ما didFinishLaunching ترجع، والمحرّك الخلفي بياخد الإضافات', () {
    final launch = delegate.indexOf('didFinishLaunchingWithOptions launchOptions');
    final reg = delegate.indexOf('WorkmanagerPlugin.registerLaunchHandlers()');
    final ret = delegate.indexOf('return super.application(application, didFinishLaunchingWithOptions: launchOptions)');
    expect(reg, greaterThan(launch));
    expect(reg, lessThan(ret), reason: 'لازم قبل return — UIScene');
    expect(delegate, contains('WorkmanagerPlugin.setPluginRegistrantCallback { registry in\n      GeneratedPluginRegistrant.register(with: registry)'));
    expect(delegate, contains('import workmanager_apple'));
  });

  // أول فتحة كانت بتقع: submit لمعرّف مالوش معالج = استثناء ObjC ما بيتمسكش.
  // المعالج لازم يتسجّل لمعرّفنا بالاسم قبل return — مش من المتخزّن بس.
  test('iOS: معالج المعرّف بيتسجّل بالاسم قبل return (وإلا أول فتحة بتقع)', () {
    final call = 'WorkmanagerPlugin.registerPeriodicTask(\n'
        '      withIdentifier: "${BackgroundHealth.taskId}",\n'
        '      earliestBeginInSeconds: ${BackgroundHealth.every.inSeconds}\n'
        '    )';
    final at = delegate.indexOf(call);
    final ret = delegate.indexOf('return super.application(application, didFinishLaunchingWithOptions: launchOptions)');
    expect(at, greaterThan(0), reason: 'التسجيل بالمعرّف مش موجود في AppDelegate');
    expect(at, lessThan(ret), reason: 'لازم قبل return');
  });

  test('main: التسجيل بعد المراقب وبعد إعادة الجدولة، من غير await', () {
    final resched = main.indexOf('services.scheduler.rescheduleAll()');
    final watcher = main.indexOf('HealthWatcher.instance = HealthWatcher(');
    final reg = main.indexOf('unawaited(BackgroundHealth.register())');
    expect(reg, greaterThan(watcher));
    expect(watcher, greaterThan(resched));
  });

  test('التسجيل من غير منصة ما بيرميش (الاختبار نفسه)', () async {
    await BackgroundHealth.register();
  });
}
