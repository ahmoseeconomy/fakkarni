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
];

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
