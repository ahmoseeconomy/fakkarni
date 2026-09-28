import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/health/health_collector.dart';
import 'package:fakkarni/data/health/health_heartbeat.dart';
import 'package:fakkarni/data/health/health_watcher.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/medication_save_service.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_report.dart';
import 'package:fakkarni/domain/health/health_snapshot.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

import '../../features/scan/scan_test_support.dart';
import '../../support/seeded_clock.dart';

/// **الفحص الآلي بيشتغل لوحده، وبيصلّح في صمت، وبيبلّغ الحالة بعد الإصلاح.**
///
/// المستخدم عمره ما يفحص حاجة بإيده: الفتحة الباردة، الرجوع للمقدمة، وأي
/// تغيير في الجدول بيندهوا الفحص — مرة كل عشر دقايق إلا بعد تغيير جدول.
/// ولا إشعار ولا شاشة من هنا (`health_is_last_test` بيثبت الملف نفسه).
void main() {
  final h = Harness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    HealthWatcher.instance = null;
    HealthWatcher.lastStatus = null;
    await h.setUp();
  });
  tearDown(h.tearDown);

  final now = DateTime(2026, 9, 28, 10);

  HealthSnapshot snapshot({
    DateTime? at,
    bool? sessionExpired,
    bool appVersionKnown = true,
    NotificationPermission permission = NotificationPermission.granted,
    bool hasPushToken = true,
  }) =>
      HealthSnapshot(
        now: at ?? now,
        platform: HealthPlatform.ios,
        permission: permission,
        activeDoseCount: 3,
        plannedDoseCount: 12,
        pendingDoseCount: 12,
        pendingCount: 30,
        pendingLimit: 64,
        horizonUntil: (at ?? now).add(const Duration(days: 5)),
        deviceTimezone: 'Africa/Cairo',
        scheduledTimezone: 'Africa/Cairo',
        hasCaregiver: true,
        hasPushToken: hasPushToken,
        cloudConfigured: true,
        signedIn: true,
        dirtyRowCount: 0,
        lastSyncedAt: at ?? now,
        exactAlarmsAllowed: true,
        batteryState: BatteryState.unrestricted,
        aiKeyPresent: true,
        rungFirstOn: true,
        rungSecondOn: true,
        sessionExpired: sessionExpired,
        appVersionKnown: appVersionKnown,
      );

  group('الخنق — عشر دقايق', () {
    test('تاني نداء جوّه عشر دقايق ما بيفحصش؛ بعدها بيفحص', () async {
      final c = _Clocked(h, snapshot());
      final w = HealthWatcher(collector: c, autoFix: HealthAutoFix.none);
      await w.runIfDue();
      await w.runIfDue();
      expect(c.collects, 1, reason: 'جوّه العشر دقايق = مفيش فحص');
      c.at = now.add(const Duration(minutes: 9));
      await w.runIfDue();
      expect(c.collects, 1);
      c.at = now.add(const Duration(minutes: 10));
      await w.runIfDue();
      expect(c.collects, 2);
    });

    test('force بيفحص جوّه العشر دقايق — وده باب تغيير الجدول', () async {
      final c = _Clocked(h, snapshot());
      final w = HealthWatcher(collector: c, autoFix: HealthAutoFix.none);
      await w.runIfDue();
      await w.runIfDue(force: true);
      expect(c.collects, 2);
    });

    test('scheduleChanged من غير مراقب متركّب = ولا حاجة (الاختبارات)', () async {
      await HealthWatcher.scheduleChanged();
      HealthWatcher.instance = HealthWatcher(collector: _Clocked(h, snapshot()), autoFix: HealthAutoFix.none);
      await HealthWatcher.instance!.runIfDue();
      await HealthWatcher.scheduleChanged();
      expect((HealthWatcher.instance!.collector as _Clocked).collects, 2, reason: 'بعد تغيير الجدول = فحص فوري');
    });
  });

  group('الحالة بعد الإصلاح', () {
    test('كله تمام → ok', () async {
      await HealthWatcher(collector: _Clocked(h, snapshot()), autoFix: HealthAutoFix.none).run();
      expect(HealthWatcher.lastStatus, HealthStatus.ok);
    });

    test('جلسة منتهية → تجديد في صمت، والفحص بيتعاد، والحالة healed', () async {
      var refreshed = 0;
      final c = _Scripted(h, [snapshot(sessionExpired: true), snapshot(sessionExpired: false)]);
      await HealthWatcher(
        collector: c,
        autoFix: HealthAutoFix(
          reschedule: () async {},
          rememberTimezone: () async {},
          registerPush: () async {},
          retrySync: () async {},
          refreshSession: () async {
            refreshed++;
            return true;
          },
        ),
      ).run();
      expect(refreshed, 1);
      expect(c.collects, 2, reason: 'الفحص بيتعاد بعد الإصلاح');
      expect(HealthWatcher.latest.value!.brokenCodes, isEmpty);
      expect(HealthWatcher.lastStatus, HealthStatus.healed);
    });

    test('التجديد وقع → الكود فاضل مكسور، والحالة broken (للأدمن)', () async {
      final c = _Scripted(h, [snapshot(sessionExpired: true)]);
      await HealthWatcher(collector: c, autoFix: HealthAutoFix.none).run();
      expect(c.collects, 1, reason: 'مفيش إصلاح = مفيش إعادة فحص');
      expect(HealthWatcher.latest.value!.brokenCodes, {HealthCode.sessionExpired});
      expect(HealthWatcher.lastStatus, HealthStatus.broken);
    });

    test('مفيش جلسة أصلاً (null) مش عطل', () {
      expect(runHealthChecks(snapshot(sessionExpired: null)).brokenCodes, isEmpty);
    });

    test('إذن التنبيهات مقفول → needsUser — الحاجة الوحيدة اللي بتوصل المريض', () async {
      await HealthWatcher(
        collector: _Clocked(h, snapshot(permission: NotificationPermission.denied)),
        autoFix: HealthAutoFix.none,
      ).run();
      expect(HealthWatcher.lastStatus, HealthStatus.needsUser);
    });

    test('نسخة مش معروفة → ملاحظة للأدمن، مش مكسور، والحالة ok', () async {
      await HealthWatcher(collector: _Clocked(h, snapshot(appVersionKnown: false)), autoFix: HealthAutoFix.none).run();
      final r = HealthWatcher.latest.value!;
      expect(r.findings.map((f) => f.code), contains(HealthCode.appVersionUnknown));
      expect(r.brokenCodes, isEmpty);
      expect(HealthWatcher.lastStatus, HealthStatus.ok);
    });

    test('healthStatusOf — نقية', () {
      final ok = runHealthChecks(snapshot());
      expect(healthStatusOf(ok, healedSomething: false), HealthStatus.ok);
      expect(healthStatusOf(ok, healedSomething: true), HealthStatus.healed);
      final needs = runHealthChecks(snapshot(permission: NotificationPermission.denied));
      expect(healthStatusOf(needs, healedSomething: true), HealthStatus.needsUser, reason: 'اللي في إيده بيكسب على healed');
      final both = runHealthChecks(snapshot(permission: NotificationPermission.denied, sessionExpired: true));
      expect(healthStatusOf(both, healedSomething: false), HealthStatus.broken, reason: 'مكسور برّه إيده = broken');
    });
  });

  group('النبضة — الحالة والأكواد (0037)', () {
    test('الصف فيه status وcodes، وتغيير الحالة لوحده بيرفع صف', () async {
      final remote = _Recording();
      final beat = HealthHeartbeat(remote: remote, patientUuid: 'p1');
      final s = snapshot();
      expect(await beat.report(runHealthChecks(s), s, status: HealthStatus.ok), isTrue);
      expect(remote.rows.single['status'], 'ok');
      expect(remote.rows.single['codes'], isEmpty);
      // نفس الأكواد (فاضية) بس الحالة بقت healed → صف تاني
      expect(await beat.report(runHealthChecks(s), s, status: HealthStatus.healed), isTrue);
      expect(remote.rows.last['status'], 'healed');
      // ولا حاجة اتغيّرت → مفيش
      expect(await beat.report(runHealthChecks(s), s, status: HealthStatus.healed), isFalse);
      // والكلمة على السلك بالشرطة السفلية — نفس قيد 0037
      expect(await beat.report(runHealthChecks(s), s, status: HealthStatus.needsUser), isTrue);
      expect(remote.rows.last['status'], 'needs_user');
      expect(remote.rows.last.containsKey('user_id'), isFalse, reason: 'من غير userId مفيش مفتاح');
    });

    test('من غير جلسة: ولا نداء، والصف بيتبعت أول ما الجلسة تيجي — من غير ما نستنى ست ساعات', () async {
      final remote = _Recording();
      var eligible = false;
      final beat = HealthHeartbeat(remote: remote, patientUuid: 'p1', eligible: () async => eligible);
      final s = snapshot();
      expect(await beat.report(runHealthChecks(s), s), isFalse);
      expect(remote.rows, isEmpty, reason: 'مفيش جلسة = مفيش نداء');
      eligible = true;
      final later = snapshot(at: now.add(const Duration(minutes: 20)));
      expect(await beat.report(runHealthChecks(later), later), isTrue, reason: 'الطابور المحلي: اللي ما اتبعتش بيتبعت');
      expect(remote.rows, hasLength(1));
    });

    test('الصف أكواد وبس — ولا اسم دوا ولا بيان صحي', () async {
      final remote = _Recording();
      final s = snapshot();
      await HealthHeartbeat(remote: remote, patientUuid: 'p1').report(runHealthChecks(s), s);
      final keys = remote.rows.single.keys.toSet();
      expect(keys, isNot(anyElement(anyOf(contains('med'), contains('dose_event'), contains('name'), contains('record')))));
      for (final v in remote.rows.single.values) {
        expect(v, anyOf(isNull, isA<String>(), isA<bool>(), isA<int>(), isA<List<String>>()));
      }
    });
  });

  group('التوصيل', () {
    test('MedicationSaveService بينده afterSchedule بعد الجدولة، وفشله ما بيلمسش الحفظ', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final meds = MedicationRepository(db, clock: seededLongAgo);
      final patientId = await PatientRepository(db).ensurePatient();
      final sink = RecordingSink();
      final scheduler = ReminderScheduler(medications: meds, events: DoseEventRepository(db), patientId: patientId, sink: sink);
      var calls = 0;
      var scheduledWhenCalled = 0;
      final saves = MedicationSaveService(
        medications: meds,
        scheduler: scheduler,
        afterSchedule: () async {
          calls++;
          scheduledWhenCalled = sink.scheduled.length;
          throw StateError('boom');
        },
      );
      final id = await saves.add(
        patientId: patientId,
        name: 'Concor',
        timings: [FixedTiming(MinuteOfDay.hm(21))],
        startDate: DateTime(2026, 9, 1),
      );
      expect(id, greaterThan(0));
      expect(calls, 1);
      expect(scheduledWhenCalled, greaterThan(0), reason: 'بعد الجدولة مش قبلها');
      await saves.stop(id);
      expect(calls, 2);
    });

    test('AppScope بيمرّر الفحص للحفظ، وroot بينده الفحص آخر حاجة في الرجوع للمقدمة، وmain بيحطّهم', () {
      final scope = File('lib/app/app_scope.dart').readAsStringSync();
      expect(scope, contains('afterSchedule: afterScheduleChange'));
      final root = File('lib/app/root.dart').readAsStringSync();
      final pull = root.indexOf('services.pullFromCircle()');
      final check = root.indexOf('services.healthCheckIfDue()');
      expect(pull, greaterThan(0));
      expect(check, greaterThan(pull), reason: 'الفحص بعد كل وعد — مجاملة');
      expect(root, isNot(contains('HealthWatcher')), reason: 'root ما بيعرفش الفاحص بالاسم');
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('AppServices.afterScheduleChange = HealthWatcher.scheduleChanged'));
      expect(main, contains('AppServices.checkHealthIfDue = () => HealthWatcher.instance!.runIfDue()'));
      expect(main, contains('unawaited(HealthWatcher.instance!.runIfDue(force: true))'));
      // ولا إشعار ولا شاشة من الفاحص
      final watcher = File('lib/data/health/health_watcher.dart').readAsStringSync();
      expect(watcher, isNot(contains('NotificationService')));
      expect(watcher, isNot(contains('showNow')));
      expect(watcher, isNot(contains('Navigator')));
    });
  });
}

class _Clocked extends HealthCollector {
  _Clocked(Harness h, this.base) : super(h.services, clock: () => _at[base] ?? base.now);
  final HealthSnapshot base;
  static final _at = <HealthSnapshot, DateTime>{};
  set at(DateTime v) => _at[base] = v;
  int collects = 0;

  @override
  Future<HealthSnapshot> collect() async {
    collects++;
    return base;
  }
}

class _Scripted extends HealthCollector {
  _Scripted(Harness h, this.snapshots) : super(h.services, clock: () => snapshots.first.now);
  final List<HealthSnapshot> snapshots;
  int collects = 0;

  @override
  Future<HealthSnapshot> collect() async {
    final s = snapshots[collects.clamp(0, snapshots.length - 1)];
    collects++;
    return s;
  }
}

class _Recording implements HealthRemote {
  final List<Map<String, dynamic>> rows = [];
  @override
  Future<void> upsert(Map<String, dynamic> row) async => rows.add(row);
}
