import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../core/diagnostics.dart';
import '../../domain/health/health_check.dart';
import '../../domain/health/health_report.dart';
import 'health_collector.dart';
import 'health_heartbeat.dart';

/// الإصلاحات الآلية — **في صمت، ومن غير ما المريض يشوف حاجة**.
///
/// قاعدة المالك: المريض عمره ما يشوف مشكلة تقنية. اللي التطبيق يقدر يصلّحه
/// بيصلّحه هنا؛ واللي ما يقدرش بيروح للوحة الأدمن مع النبضة. كل إصلاح
/// بيتسجّل بـ`diag` عشان الأثر يبقى موجود من غير شاشة.
///
/// الدوال متحقونة عشان الاختبار يعدّ الندوات من غير جدولة حقيقية.
class HealthAutoFix {
  const HealthAutoFix({
    required this.reschedule,
    required this.rememberTimezone,
    required this.registerPush,
    required this.retrySync,
  });

  factory HealthAutoFix.forServices(AppServices services, HealthCollector collector) =>
      HealthAutoFix(
        reschedule: services.scheduler.rescheduleAll,
        rememberTimezone: collector.rememberTimezone,
        registerPush: () async => services.push?.registerNow(),
        retrySync: () async => services.sync?.push(),
      );

  /// للاختبار — ولا إصلاح بيتعمل.
  static final HealthAutoFix none = HealthAutoFix(
    reschedule: () async {},
    rememberTimezone: () async {},
    registerPush: () async {},
    retrySync: () async {},
  );

  final Future<void> Function() reschedule;
  final Future<void> Function() rememberTimezone;
  final Future<void> Function() registerPush;
  final Future<void> Function() retrySync;

  /// بيصلّح كود واحد. بيرجع وصف اللي اتعمل، أو null لو الكود مالوش إصلاح.
  Future<String?> apply(HealthCode code) async {
    switch (code) {
      case HealthCode.reminderHorizon:
      case HealthCode.remindersDropped:
        await reschedule();
        return 'إعادة جدولة التذكيرات';
      case HealthCode.timezoneChanged:
        await reschedule();
        await rememberTimezone();
        return 'إعادة جدولة على المنطقة الزمنية الجديدة';
      case HealthCode.pushToken:
        await registerPush();
        return 'إعادة تسجيل توكن الدفع';
      case HealthCode.staleSync:
        await retrySync();
        return 'إعادة محاولة الرفع';
      case HealthCode.notificationPermission:
      case HealthCode.pendingBandFull:
      case HealthCode.noCaregiver:
      case HealthCode.exactAlarms:
      case HealthCode.aiKeyMissing:
      case HealthCode.batteryOptimisation:
      case HealthCode.escalationRungsOff:
      case HealthCode.noMedications:
      case HealthCode.accountMissing:
      // صور الأدوية: الطابور نفسه بيعيد بتراجعه مع كل سحبة
      case HealthCode.mediaSync:
      // التغطية بتتجدد مع كل فتحة وتأكيد — إعادة الجدولة ما بتزوّدش خانات
      case HealthCode.lowCoverage:
        return null;
    }
  }
}

/// بيشغّل الفحص، وبيصلّح اللي يتصلّح **في صمت**، وبيرفع النبضة.
///
/// **مفيش إشعار ومفيش شاشة للمريض من هنا.** كان بينبّه مرة في اليوم لكل
/// كود؛ اتشال بقرار المالك: المريض ما يشوفش مشكلة تقنية أبداً — يا بتتصلّح
/// لوحدها يا بتتبلّغ للأدمن. الاستثناء الوحيد (إذن التنبيهات) سطر على
/// «يومك» بيقرا [latest]، مش إشعار.
///
/// **مجاملة بالكامل.** بيتنده بعد ما كل وعد اتنفّذ — تسجيل الجرعة وإلغاء
/// السلّم والجدولة — وعمره ما بيتستنى قبل واحد منهم. أي فشل جواه بيتسجّل
/// وبيتساب.
class HealthWatcher {
  HealthWatcher({required this.collector, this.heartbeat, HealthAutoFix? autoFix})
      : autoFix = autoFix ?? HealthAutoFix.forServices(collector.services, collector);

  final HealthCollector collector;
  final HealthHeartbeat? heartbeat;
  final HealthAutoFix autoFix;

  /// آخر نتيجة — سطر إذن التنبيهات على «يومك» بيسمع لها.
  static final ValueNotifier<HealthReport?> latest =
      ValueNotifier<HealthReport?>(null);

  /// نفس الإصلاح ما بيتعادش قبل المدة دي: إعادة جدولة على مدى قصير بسبب
  /// كتر الأدوية ما بتغيّرش حاجة، وتكرارها كل فتحة ضوضا في السجل.
  static const autoFixEvery = Duration(hours: 6);

  static const _fixedKeyPrefix = 'health.autoFixed.';

  Future<void> run() async {
    try {
      var snapshot = await collector.collect();
      var report = runHealthChecks(snapshot);

      final fixed = await _autoFix(report, snapshot.now);
      if (fixed.isNotEmpty) {
        // اللي اتصلّح ما يتبلّغش كمكسور: النبضة بتقول الحالة **بعد** الإصلاح
        snapshot = await collector.collect();
        report = runHealthChecks(snapshot);
      }

      latest.value = report;
      await heartbeat?.report(report, snapshot);
    } catch (error) {
      diag('Health: الفحص وقع ($error)');
    }
  }

  /// بيصلّح كل كود مكسور ليه إصلاح، مرة كل [autoFixEvery]. بيرجع اللي اتصلّح.
  Future<List<HealthCode>> _autoFix(HealthReport report, DateTime now) async {
    final fixable = report.findings.where((f) => f.autoFixes).toList();
    if (fixable.isEmpty) return const [];

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    final done = <HealthCode>[];
    for (final finding in fixable) {
      final key = '$_fixedKeyPrefix${finding.code.name}';
      final lastMs = prefs?.getInt(key);
      if (lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) < autoFixEvery) {
        continue;
      }
      try {
        final what = await autoFix.apply(finding.code);
        if (what == null) continue;
        diag('Health: إصلاح آلي — ${finding.code.name}: $what');
        done.add(finding.code);
        await prefs?.setInt(key, now.millisecondsSinceEpoch);
      } catch (error) {
        diag('Health: الإصلاح الآلي لـ${finding.code.name} وقع ($error)');
      }
    }
    return done;
  }

  /// مفتاح الخنق لكود — للاختبار.
  @visibleForTesting
  static String fixedKey(HealthCode code) => '$_fixedKeyPrefix${code.name}';
}
