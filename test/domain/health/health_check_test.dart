import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_report.dart';
import 'package:fakkarni/domain/health/health_snapshot.dart';

/// كل فحص ليه لقطة بتعدّيه ولقطة بتوقّعه — **الاتنين**.
///
/// الدرس اللي كلّفنا ٢٣ ملف: تأكيد عمره ما اتحقّق شرطه مش حارس. فحص
/// هنا من غير لقطة بتكسّره هو نفس الحاجة بالظبط.
void main() {
  final now = DateTime(2026, 9, 20, 10);

  /// موبايل مريض كل حاجة فيه تمام — الأساس اللي كل اختبار بيغيّر فيه
  /// حاجة واحدة بس.
  HealthSnapshot well({
    HealthPlatform platform = HealthPlatform.ios,
    NotificationPermission permission = NotificationPermission.granted,
    bool isCaregiver = false,
    int activeDoseCount = 3,
    int plannedDoseCount = 12,
    int pendingDoseCount = 12,
    int pendingCount = 30,
    int pendingLimit = 64,
    DateTime? horizonUntil,
    String deviceTimezone = 'Africa/Cairo',
    String? scheduledTimezone = 'Africa/Cairo',
    bool hasCaregiver = true,
    bool hasPushToken = true,
    bool cloudConfigured = true,
    bool signedIn = true,
    int dirtyRowCount = 0,
    DateTime? oldestDirtyAt,
    DateTime? lastSyncedAt,
    bool exactAlarmsAllowed = true,
    bool aiKeyPresent = true,
    bool rungFirstOn = true,
    bool rungSecondOn = true,
  }) =>
      HealthSnapshot(
        now: now,
        platform: platform,
        permission: permission,
        isCaregiver: isCaregiver,
        activeDoseCount: activeDoseCount,
        plannedDoseCount: plannedDoseCount,
        pendingDoseCount: pendingDoseCount,
        pendingCount: pendingCount,
        pendingLimit: pendingLimit,
        horizonUntil: horizonUntil ?? now.add(const Duration(days: 5)),
        deviceTimezone: deviceTimezone,
        scheduledTimezone: scheduledTimezone,
        hasCaregiver: hasCaregiver,
        hasPushToken: hasPushToken,
        cloudConfigured: cloudConfigured,
        signedIn: signedIn,
        dirtyRowCount: dirtyRowCount,
        oldestDirtyAt: oldestDirtyAt,
        lastSyncedAt: lastSyncedAt ?? now.subtract(const Duration(minutes: 5)),
        exactAlarmsAllowed: exactAlarmsAllowed,
        aiKeyPresent: aiKeyPresent,
        rungFirstOn: rungFirstOn,
        rungSecondOn: rungSecondOn,
      );

  HealthFinding? findingFor(HealthSnapshot s, HealthCode code) =>
      runHealthChecks(s).findings.where((f) => f.code == code).firstOrNull;

  void expectClean(HealthSnapshot s, HealthCode code) =>
      expect(findingFor(s, code), isNull);

  HealthFinding expectRaised(
      HealthSnapshot s, HealthCode code, Severity severity) {
    final finding = findingFor(s, code);
    expect(finding, isNotNull, reason: 'الفحص ده عمره ما اتحقّق شرطه');
    expect(finding!.severity, severity);
    return finding;
  }

  group('الموبايل السليم بيعدّي نضيف', () {
    test('مفيش ولا ملاحظة على موبايل كل حاجة فيه تمام', () {
      final report = runHealthChecks(well());
      expect(report.findings, isEmpty);
      expect(report.allWell, isTrue);
    });
  });

  group('مدى التذكير — الدين ٠ج', () {
    test('خمس أيام قدام → نضيف', () => expectClean(well(), HealthCode.reminderHorizon));

    test('أقل من يوم → مكسور', () {
      expectRaised(
        well(horizonUntil: now.add(const Duration(hours: 20))),
        HealthCode.reminderHorizon,
        Severity.broken,
      );
    });

    test('عدّى خلاص → مكسور، والجملة بتقول إنه وقف', () {
      final finding = expectRaised(
        well(horizonUntil: now.subtract(const Duration(hours: 1))),
        HealthCode.reminderHorizon,
        Severity.broken,
      );
      expect(finding.why, contains('عدّى معاده'));
    });

    test('يومين → ملاحظة', () {
      expectRaised(
        well(horizonUntil: now.add(const Duration(hours: 48))),
        HealthCode.reminderHorizon,
        Severity.note,
      );
    });

    test('مفيش تذكير خالص → مكسور', () {
      final s = HealthSnapshot(
        now: now,
        platform: HealthPlatform.ios,
        permission: NotificationPermission.granted,
        activeDoseCount: 2,
        deviceTimezone: 'Africa/Cairo',
      );
      expectRaised(s, HealthCode.reminderHorizon, Severity.broken);
    });

    test('مفيش أدوية → الفحص ده ساكت (مش شغله)', () {
      expectClean(
          well(activeDoseCount: 0, plannedDoseCount: 0, pendingDoseCount: 0),
          HealthCode.reminderHorizon);
    });

    test('موبايل الابن → ساكت', () {
      expectClean(
          well(isCaregiver: true, horizonUntil: now.subtract(const Duration(days: 1))),
          HealthCode.reminderHorizon);
    });
  });

  group('اللي اتجدول ≠ اللي الجهاز ماسكه', () {
    test('الرقمين متساويين → نضيف',
        () => expectClean(well(), HealthCode.remindersDropped));

    test('الجهاز ماسك أقل → مكسور', () {
      expectRaised(well(plannedDoseCount: 12, pendingDoseCount: 9),
          HealthCode.remindersDropped, Severity.broken);
    });
  });

  group('إذن التنبيهات', () {
    test('مسموح → نضيف',
        () => expectClean(well(), HealthCode.notificationPermission));

    test('مرفوض → مكسور', () {
      expectRaised(well(permission: NotificationPermission.denied),
          HealthCode.notificationPermission, Severity.broken);
    });

    test('هادي (provisional) → مكسور برضه: تذكير من غير صوت مش تذكير', () {
      expectRaised(well(permission: NotificationPermission.provisional),
          HealthCode.notificationPermission, Severity.broken);
    });

    test('مش معروف → ساكت، مش بنخوّف بالشك', () {
      expectClean(well(permission: NotificationPermission.unknown),
          HealthCode.notificationPermission);
    });
  });

  group('سقف الإشعارات', () {
    test('تلاتين من أربعة وستين → نضيف',
        () => expectClean(well(), HealthCode.pendingBandFull));

    test('قرّب على السقف → ملاحظة', () {
      expectRaised(well(pendingCount: 62), HealthCode.pendingBandFull, Severity.note);
    });

    test('أندرويد مالوش السقف ده', () {
      expectClean(well(platform: HealthPlatform.android, pendingCount: 62),
          HealthCode.pendingBandFull);
    });
  });

  group('التوقيت', () {
    test('نفس المنطقة → نضيف', () => expectClean(well(), HealthCode.timezoneChanged));

    test('اتغيّرت → مكسور', () {
      expectRaised(well(deviceTimezone: 'Europe/Berlin'),
          HealthCode.timezoneChanged, Severity.broken);
    });

    test('أول فحص (مفيش منطقة محفوظة) → ساكت', () {
      expectClean(well(scheduledTimezone: null), HealthCode.timezoneChanged);
    });
  });

  group('دائرة الرعاية', () {
    test('مربوط → نضيف', () => expectClean(well(), HealthCode.noCaregiver));

    test('محدش مربوط → ملاحظة، والجملة بتطمّن إن التذكير شغّال', () {
      final finding = expectRaised(
          well(hasCaregiver: false), HealthCode.noCaregiver, Severity.note);
      expect(finding.why, contains('شغّال'));
    });
  });

  group('توكن الدفع — موبايل الابن بس', () {
    test('عند الابن وفيه توكن → نضيف',
        () => expectClean(well(isCaregiver: true), HealthCode.pushToken));

    test('عند الابن ومفيش توكن → مكسور', () {
      expectRaised(well(isCaregiver: true, hasPushToken: false),
          HealthCode.pushToken, Severity.broken);
    });

    test('عند المريض ومفيش توكن → ساكت: مش بتاعه أصلاً', () {
      expectClean(well(hasPushToken: false), HealthCode.pushToken);
    });
  });

  group('الرفع للسحابة', () {
    test('كله مرفوع → نضيف', () => expectClean(well(), HealthCode.staleSync));

    test('صف متوسّخ أقدم من مهلة السيرفر → مكسور', () {
      expectRaised(
        well(
            dirtyRowCount: 1,
            oldestDirtyAt: now.subtract(serverGraceWindow + const Duration(minutes: 1))),
        HealthCode.staleSync,
        Severity.broken,
      );
    });

    test('صف متوسّخ لسه جوّه المهلة → ساكت', () {
      expectClean(
        well(
            dirtyRowCount: 1,
            oldestDirtyAt: now.subtract(serverGraceWindow - const Duration(minutes: 5))),
        HealthCode.staleSync,
      );
    });

    test('آخر رفع من أكتر من يوم → مكسور', () {
      expectRaised(
        well(lastSyncedAt: now.subtract(const Duration(hours: 25))),
        HealthCode.staleSync,
        Severity.broken,
      );
    });

    test('مفيش ربط → ساكت: مفيش حد هيتضرر', () {
      expectClean(
        well(
            hasCaregiver: false,
            oldestDirtyAt: now.subtract(const Duration(days: 3))),
        HealthCode.staleSync,
      );
    });
  });

  group('أندرويد', () {
    test('التنبيه الدقيق مسموح → نضيف', () {
      expectClean(well(platform: HealthPlatform.android), HealthCode.exactAlarms);
    });

    test('التنبيه الدقيق مقفول → مكسور', () {
      expectRaised(
          well(platform: HealthPlatform.android, exactAlarmsAllowed: false),
          HealthCode.exactAlarms,
          Severity.broken);
    });

    test('على iOS مش بيتسأل', () {
      expectClean(well(exactAlarmsAllowed: false), HealthCode.exactAlarms);
    });

  });

  group('درجات السلّم', () {
    test('الاتنين شغّالين → نضيف',
        () => expectClean(well(), HealthCode.escalationRungsOff));

    test('واحدة مقفولة → ساكت: لسه فيه تفكير تاني', () {
      expectClean(well(rungFirstOn: false), HealthCode.escalationRungsOff);
    });

    test('الاتنين مقفولين → ملاحظة', () {
      expectRaised(well(rungFirstOn: false, rungSecondOn: false),
          HealthCode.escalationRungsOff, Severity.note);
    });
  });

  group('مفيش أدوية — عشان السطر الأخضر ما يكدبش', () {
    test('فيه أدوية → ساكت', () => expectClean(well(), HealthCode.noMedications));

    test('مفيش → ملاحظة، ومفيش سطر أخضر يقول «كله تمام»', () {
      final s = well(activeDoseCount: 0, plannedDoseCount: 0, pendingDoseCount: 0);
      expectRaised(s, HealthCode.noMedications, Severity.note);
      expect(runHealthChecks(s).findings, isNotEmpty);
    });
  });

  group('مفتاح الذكاء', () {
    test('موجود → نضيف', () => expectClean(well(), HealthCode.aiKeyMissing));

    test('ناقص → ملاحظة، والجملة بتقول إن التذكير شغّال', () {
      final finding = expectRaised(
          well(aiKeyPresent: false), HealthCode.aiKeyMissing, Severity.note);
      expect(finding.why, contains('شغّالة'));
    });
  });

  group('الترتيب والتجميع', () {
    test('المكسور بيطلع فوق الملاحظة', () {
      final report = runHealthChecks(well(
        hasCaregiver: false, // ملاحظة
        permission: NotificationPermission.denied, // مكسور
      ));
      expect(report.findings.first.isBroken, isTrue);
      expect(report.findings.last.isBroken, isFalse);
      expect(report.allWell, isFalse);
    });

    test('brokenCodes بيرجّع المكسور بس', () {
      final report = runHealthChecks(
          well(hasCaregiver: false, permission: NotificationPermission.denied));
      expect(report.brokenCodes, {HealthCode.notificationPermission});
    });

    test('كل كود ليه فحص، وكل فحص بيرجّع كوده', () {
      // لو كود اتضاف من غير فحص، أو فحص رجّع كود غيره، ده بيبان هنا.
      expect(healthChecks.length, HealthCode.values.length);
    });

    test('كل مكسور معاه حل أو جملة بتقول مين يتصرف', () {
      // صف أحمر المستخدم ما يقدرش يعمل فيه حاجة هو ضوضا. اللي مالوش
      // زرار لازم تكون جملته بتقول إيه اللي بيحصل بدل ما تسيبه ساكت.
      for (final make in healthChecks) {
        final finding = make(_allBroken(now));
        if (finding == null || !finding.isBroken) continue;
        if (finding.fix == HealthFix.none) {
          expect(finding.why.length, greaterThan(40),
              reason: '${finding.code} مالهوش زرار، فالجملة هي كل اللي عنده');
        }
      }
    });
  });
}

/// لقطة كل حاجة فيها مكسورة — للتأكد إن كل مكسور بيقول لصاحبه يعمل إيه.
HealthSnapshot _allBroken(DateTime now) => HealthSnapshot(
      now: now,
      platform: HealthPlatform.android,
      permission: NotificationPermission.denied,
      isCaregiver: true,
      activeDoseCount: 0,
      plannedDoseCount: 4,
      pendingDoseCount: 0,
      pendingCount: 64,
      horizonUntil: null,
      deviceTimezone: 'Europe/Berlin',
      scheduledTimezone: 'Africa/Cairo',
      hasCaregiver: false,
      hasPushToken: false,
      cloudConfigured: true,
      signedIn: true,
      dirtyRowCount: 9,
      oldestDirtyAt: now.subtract(const Duration(days: 2)),
      lastSyncedAt: now.subtract(const Duration(days: 2)),
      exactAlarmsAllowed: false,
      aiKeyPresent: false,
      rungFirstOn: false,
      rungSecondOn: false,
    );
