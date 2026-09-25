import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_report.dart';
import 'package:fakkarni/domain/health/health_snapshot.dart';

/// «التغطية قليلة»: الخطة اتقصّت **و** آخر تذكير متجهّز أقرب من ٤٨ ساعة.
/// للأدمن بس — المريض ما بيشوفهاش.
void main() {
  final now = DateTime(2026, 9, 1, 6);
  HealthSnapshot snap({required bool truncated, required Duration left}) => HealthSnapshot(
        now: now,
        platform: HealthPlatform.ios,
        permission: NotificationPermission.granted,
        activeDoseCount: 18,
        horizonUntil: now.add(left),
        planTruncated: truncated,
      );

  test('اتقصّت و٤٢ ساعة → مكسور، ومش ظاهر للمريض', () {
    final f = checkLowCoverage(snap(truncated: true, left: const Duration(hours: 42)))!;
    expect(f.code, HealthCode.lowCoverage);
    expect(f.isBroken, isTrue, reason: 'المكسور بس بيروح مع النبضة للأدمن');
    expect(f.patientVisible, isFalse);
    expect(runHealthChecks(snap(truncated: true, left: const Duration(hours: 42))).brokenCodes,
        contains(HealthCode.lowCoverage));
  });

  test('اتقصّت و٥٩ ساعة → لأ', () {
    expect(checkLowCoverage(snap(truncated: true, left: const Duration(hours: 59))), isNull);
  });

  test('ما اتقصّتش (دوا بيخلص بكرة) → لأ، حتى لو آخر تذكير قريب', () {
    expect(checkLowCoverage(snap(truncated: false, left: const Duration(hours: 10))), isNull);
  });
}
