import 'health_check.dart';
import 'health_snapshot.dart';

/// كل الفحوص في مكان واحد — الترتيب ده هو اللي بيتعرض.
///
/// المكسور قبل الملاحظة دايماً، وجوّه كل درجة الترتيب ده: أقرب حاجة
/// بتمنع الحبة توصل الأول.
const List<HealthFinding? Function(HealthSnapshot)> healthChecks = [
  checkAccountMissing,
  checkNotificationPermission,
  checkReminderHorizon,
  checkRemindersDropped,
  checkTimezoneChanged,
  checkExactAlarms,
  checkStaleSync,
  checkPushToken,
  checkPendingBandFull,
  checkBatteryOptimisation,
  checkEscalationRungs,
  checkNoCaregiver,
  checkNoMedications,
  checkAiKey,
  checkMediaSync,
  checkLowCoverage,
  checkPatternSync,
  checkListenUnavailable,
  checkSessionExpired,
  checkAppVersion,
];

/// حالة الجهاز بعد الفحص — بتتبعت للسيرفر (0037) كلمة واحدة.
enum HealthStatus {
  /// ولا كود مكسور.
  ok,

  /// كان فيه مكسور واتصلّح لوحده في الفحص ده، ومفيش مكسور فاضل.
  healed,

  /// مكسور في إيد المستخدم بس (إذن التنبيهات).
  needsUser,

  /// مكسور ومفيش إصلاح آلي ليه — للأدمن.
  broken;

  /// الكلمة على السلك — نفس قيد `device_health.status` في 0037
  /// (`device_health_sql_test` مرآة).
  String get wire => switch (this) {
        HealthStatus.ok => 'ok',
        HealthStatus.healed => 'healed',
        HealthStatus.needsUser => 'needs_user',
        HealthStatus.broken => 'broken',
      };
}

/// الحالة من التقرير **بعد** الإصلاح، وهل اتصلّح حاجة.
HealthStatus healthStatusOf(HealthReport report, {required bool healedSomething}) {
  final broken = report.brokenCodes;
  if (broken.isEmpty) {
    return healedSomething ? HealthStatus.healed : HealthStatus.ok;
  }
  if (broken.every(patientVisibleCodes.contains)) {
    return HealthStatus.needsUser;
  }
  return HealthStatus.broken;
}

class HealthReport {
  const HealthReport(this.findings, this.at);

  final List<HealthFinding> findings;
  final DateTime at;

  Iterable<HealthFinding> get broken => findings.where((f) => f.isBroken);
  bool get allWell => broken.isEmpty;

  /// أكواد اللي مكسور — ده اللي بيتبعت للسيرفر وبيتقارن بين فحص وفحص.
  Set<HealthCode> get brokenCodes => {for (final f in broken) f.code};
}

HealthReport runHealthChecks(HealthSnapshot snapshot) {
  final findings = [
    for (final check in healthChecks) ?check(snapshot),
  ];
  findings.sort((a, b) => a.isBroken == b.isBroken ? 0 : (a.isBroken ? -1 : 1));
  return HealthReport(List.unmodifiable(findings), snapshot.now);
}
