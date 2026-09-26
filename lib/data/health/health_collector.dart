import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/health/health_report.dart';
import '../../domain/health/health_snapshot.dart';
import '../battery/battery_optimisation.dart';
import '../services/reminder_plan.dart';
import '../files/med_photo_sync.dart' show mediaProblemSince, mediaRejectedAt;
import '../voice/listen_health.dart' show listenProblemSince;
import '../sync/sync_service.dart' show SyncBlockReason, patternRejectedSince;

/// بيجمع اللقطة من الجهاز الحقيقي — **الطرف الوسخ من الفحص**.
///
/// كل قرار في `domain/health/` نقي؛ هنا بس القراية. وكل نداء متلفوف:
/// الفحص مجاملة، وفشله المفروض يبقى «مش عارفين» مش شاشة بايظة.
class HealthCollector {
  const HealthCollector(
    this.services, {
    this.isCaregiver = false,
    this.clock = DateTime.now,
  });

  final AppServices services;

  /// **بيتقال صراحةً، مش بيتخمّن**: شاشة الابن بتبعت true. تخمينه من
  /// «مفيش أدوية» كان هيخلّي مريض لسه ما ضافش دوا يتعامل كابن.
  final bool isCaregiver;

  final DateTime Function() clock;

  /// المنطقة اللي التذكيرات اتبنت عليها آخر مرة اتفحصنا فيها.
  ///
  /// بتتخزن **من هنا، مش من الجدولة**: الجدولة بتشتغل في isolate صحوة
  /// شاشة القفل، وده آخر مكان يتحط فيه نداء إضافة زيادة.
  static const _tzKey = 'health.scheduledTz';

  Future<HealthSnapshot> collect() async {
    final now = clock();
    final platform = Platform.isIOS
        ? HealthPlatform.ios
        : Platform.isAndroid
            ? HealthPlatform.android
            : HealthPlatform.other;

    final pendingIds = await _pendingIds();
    final active = await _activeDoseCount();
    final deviceTz = await _deviceTimezone();
    final prefs = await _prefs();
    final stats = await services.sync?.stats();
    final settings = await _deviceSettings();
    final blocked = await services.sync?.blockedReason();

    return HealthSnapshot(
      now: now,
      platform: platform,
      permission: await NotificationService.permissionState(),
      isCaregiver: isCaregiver,
      activeDoseCount: active,
      plannedDoseCount: services.scheduler.lastPlannedDoseCount ?? 0,
      pendingDoseCount: pendingIds.where(isDoseId).length,
      pendingCount: pendingIds.length,
      pendingLimit: iosPendingLimit,
      horizonUntil: horizonFromPendingDoseIds(
        pendingIds,
        now: now,
        patientIndex: services.scheduler.patientIndex,
      ),
      deviceTimezone: deviceTz,
      scheduledTimezone: prefs?.getString(_tzKey),
      hasCaregiver: services.auth?.currentUser != null,
      hasPushToken: services.push != null,
      cloudConfigured: services.sync != null,
      signedIn: services.auth?.currentUser != null,
      dirtyRowCount: stats?.dirtyCount ?? 0,
      oldestDirtyAt: stats?.oldestDirtyAt,
      lastSyncedAt: stats?.lastSyncedAt,
      caregiverName: await _caregiverName(),
      syncBlockedForAccount: blocked == SyncBlockReason.accountMissing,
      exactAlarmsAllowed: await _exactAlarms(platform),
      batteryState: await BatteryOptimisation.state(),
      aiKeyPresent: services.prescriptionReader != null,
      rungFirstOn: settings.$1,
      rungSecondOn: settings.$2,
      mediaProblemSince: await mediaProblemSince(),
      mediaRejectedAt: await mediaRejectedAt(),
      planTruncated: services.scheduler.lastPlanTruncated,
      patternRejectedSince: await patternRejectedSince(),
      listenProblemSince: await listenProblemSince(),
    );
  }

  Future<HealthReport> run() async => runHealthChecks(await collect());

  /// بتتحط بعد كل إعادة جدولة ناجحة من شاشة الفحص — فالمرة الجاية
  /// المقارنة بتبقى مع منطقة حقيقية.
  Future<void> rememberTimezone() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(_tzKey, await _deviceTimezone());
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _pendingIds() async {
    try {
      return (await services.scheduler.sink.pendingIds()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String> _deviceTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return '';
    }
  }

  /// اسم أول متابع — للجملة «لسه ما وصلتش لـ…». فشل القراية = null، والجملة
  /// بتقول «للي بيتابعك».
  Future<String?> _caregiverName() async {
    try {
      final preferences = services.caregiverPreferences;
      if (preferences == null) return null;
      final uuid = (await services.routines.getPatient(services.patientId))?.uuid;
      if (uuid == null) return null;
      final followers = await preferences.followers(uuid);
      final name = followers.firstOrNull?.name.trim();
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }

  Future<int> _activeDoseCount() async {
    try {
      return (await services.medications.activeSchedules(services.patientId))
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<(bool, bool)> _deviceSettings() async {
    try {
      final settings = await services.preferences.get();
      return (settings.rungFirstOn, settings.rungSecondOn);
    } catch (_) {
      return (true, true);
    }
  }

  Future<bool> _exactAlarms(HealthPlatform platform) async {
    if (platform != HealthPlatform.android) return true;
    try {
      return await NotificationService.canScheduleExact();
    } catch (_) {
      return true;
    }
  }
}
