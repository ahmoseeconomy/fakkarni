import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/health/health_collector.dart';
import 'package:fakkarni/data/health/health_watcher.dart';
import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_snapshot.dart';

import '../../features/scan/scan_test_support.dart';

/// **المريض ما يشوفش مشكلة تقنية — يا بتتصلّح لوحدها يا بتروح للأدمن.**
///
/// المراقب بيصلّح في صمت، مرة كل ست ساعات لكل كود، وبيعيد الفحص بعد
/// الإصلاح عشان النبضة تبلّغ الحالة **بعد** الإصلاح مش قبله.
void main() {
  final h = Harness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.setUp();
  });
  tearDown(h.tearDown);

  final now = DateTime(2026, 9, 24, 10);

  HealthSnapshot snapshot({
    NotificationPermission permission = NotificationPermission.granted,
    String scheduledTimezone = 'Africa/Cairo',
    bool hasPushToken = true,
    bool isCaregiver = false,
  }) =>
      HealthSnapshot(
        now: now,
        platform: HealthPlatform.ios,
        permission: permission,
        isCaregiver: isCaregiver,
        activeDoseCount: 3,
        plannedDoseCount: 12,
        pendingDoseCount: 12,
        pendingCount: 30,
        pendingLimit: 64,
        horizonUntil: now.add(const Duration(days: 5)),
        deviceTimezone: 'Africa/Cairo',
        scheduledTimezone: scheduledTimezone,
        hasCaregiver: true,
        hasPushToken: hasPushToken,
        cloudConfigured: true,
        signedIn: true,
        dirtyRowCount: 0,
        oldestDirtyAt: null,
        lastSyncedAt: now,
        caregiverName: null,
        syncBlockedForAccount: false,
        exactAlarmsAllowed: true,
        batteryState: BatteryState.unrestricted,
        aiKeyPresent: true,
        rungFirstOn: true,
        rungSecondOn: true,
      );

  test('منطقة زمنية اتغيّرت → إعادة جدولة وحفظ المنطقة، في صمت، والفحص بيتعاد بعدها', () async {
    final collector = _ScriptedCollector(h, [
      snapshot(scheduledTimezone: 'Europe/London'),
      snapshot(), // بعد الإصلاح
    ]);
    var rescheduled = 0, remembered = 0, pushed = 0, synced = 0;
    final watcher = HealthWatcher(
      collector: collector,
      autoFix: HealthAutoFix(
        reschedule: () async => rescheduled++,
        rememberTimezone: () async => remembered++,
        registerPush: () async => pushed++,
        retrySync: () async => synced++,
      ),
    );
    await watcher.run();

    expect(rescheduled, 1);
    expect(remembered, 1);
    expect(pushed, 0);
    expect(synced, 0);
    expect(collector.collects, 2, reason: 'النبضة بتقول الحالة بعد الإصلاح');
    expect(HealthWatcher.latest.value?.brokenCodes, isNot(contains(HealthCode.timezoneChanged)));
  });

  test('نفس الإصلاح ما بيتعادش قبل ست ساعات', () async {
    final collector = _ScriptedCollector(h, [
      snapshot(scheduledTimezone: 'Europe/London'),
      snapshot(scheduledTimezone: 'Europe/London'),
      snapshot(scheduledTimezone: 'Europe/London'),
    ]);
    var rescheduled = 0;
    final fix = HealthAutoFix(
      reschedule: () async => rescheduled++,
      rememberTimezone: () async {},
      registerPush: () async {},
      retrySync: () async {},
    );
    await HealthWatcher(collector: collector, autoFix: fix).run();
    await HealthWatcher(collector: collector, autoFix: fix).run();

    expect(rescheduled, 1, reason: 'الخنق بالمفتاح المحفوظ');
    expect(collector.collects, 3, reason: 'الأولى فحص + إعادة، والتانية فحص بس');
  });

  test('الإذن مقفول → مفيش إصلاح آلي ومفيش إشعار — بيتقال على «يومك» وبس', () async {
    final collector = _ScriptedCollector(h, [snapshot(permission: NotificationPermission.denied)]);
    var any = 0;
    await HealthWatcher(
      collector: collector,
      autoFix: HealthAutoFix(
        reschedule: () async => any++,
        rememberTimezone: () async => any++,
        registerPush: () async => any++,
        retrySync: () async => any++,
      ),
    ).run();
    expect(any, 0);
    expect(collector.collects, 1);
    expect(
      HealthWatcher.latest.value!.findings.any((f) => f.patientVisible),
      isTrue,
    );
  });

  test('الابن من غير توكن → إعادة تسجيل التوكن', () async {
    final collector = _ScriptedCollector(h, [
      snapshot(isCaregiver: true, hasPushToken: false),
      snapshot(isCaregiver: true),
    ]);
    var pushed = 0;
    await HealthWatcher(
      collector: collector,
      autoFix: HealthAutoFix(
        reschedule: () async {},
        rememberTimezone: () async {},
        registerPush: () async => pushed++,
        retrySync: () async {},
      ),
    ).run();
    expect(pushed, 1);
  });

  test('إصلاح وقع ما بيوقّعش الفحص — النتيجة بتتسجّل عادي', () async {
    final collector = _ScriptedCollector(h, [snapshot(scheduledTimezone: 'Europe/London')]);
    await HealthWatcher(
      collector: collector,
      autoFix: HealthAutoFix(
        reschedule: () async => throw StateError('boom'),
        rememberTimezone: () async {},
        registerPush: () async {},
        retrySync: () async {},
      ),
    ).run();
    expect(HealthWatcher.latest.value, isNotNull);
    expect(HealthWatcher.latest.value!.brokenCodes, contains(HealthCode.timezoneChanged));
  });
}

/// بيرجّع لقطات مكتوبة بالترتيب — آخر واحدة بتتكرّر.
class _ScriptedCollector extends HealthCollector {
  _ScriptedCollector(Harness h, this.snapshots) : super(h.services);

  final List<HealthSnapshot> snapshots;
  int collects = 0;

  @override
  Future<HealthSnapshot> collect() async {
    final s = snapshots[collects.clamp(0, snapshots.length - 1)];
    collects++;
    return s;
  }
}
