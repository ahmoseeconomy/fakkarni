import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/billing/family_plan.dart';

/// **مرايا عبر اللغات**: الأرقام في `0025` والمعرّفات في الـEdge Function
/// لازم تساوي `SubscriptionConfig` — بوستجرس ودينو ما بيقروش دارت، والفرق
/// بينهم بيظهر كمتابع اتقفل غلط، مش كبناء أحمر.
///
/// **والحارس التاني**: الجدولة والسلّم ما بيستوردوش الاشتراك خالص — ده
/// اللي بيخلّي «التذكير عمره ما يقف بسبب الدفع» حقيقة بنيوية مش نية.
void main() {
  final sql = File('supabase/migrations/0025_family_subscription.sql').readAsStringSync();
  final fn = File('supabase/functions/verify-purchase/index.ts').readAsStringSync();

  test('أرقام 0025 = SubscriptionConfig', () {
    expect(sql, contains('private.trial_days() returns integer\nlanguage sql immutable set search_path = \'\' as \$\$ select ${SubscriptionConfig.trialDays}; \$\$;'));
    expect(sql, contains('private.migration_trial_days() returns integer\nlanguage sql immutable set search_path = \'\' as \$\$ select ${SubscriptionConfig.migrationTrialDays}; \$\$;'));
    expect(sql, contains('private.subscription_grace_days() returns integer\nlanguage sql immutable set search_path = \'\' as \$\$ select ${SubscriptionConfig.graceDays}; \$\$;'));
    expect(sql, contains('private.follower_cap() returns integer\nlanguage sql immutable set search_path = \'\' as \$\$ select ${SubscriptionConfig.followerCap}; \$\$;'));
  });

  test('due_escalations بتمشي على follower_subscription_active(caregiver, patient)', () {
    expect(sql, contains('follower_subscription_active(cr.caregiver_id, p.uuid)'));
    expect(sql, contains("'circle_full'"));
  });

  test('معرّفات المنتجات في الـEdge Function = SubscriptionConfig', () {
    for (final id in SubscriptionConfig.productIds) {
      expect(fn, contains("'$id'"), reason: id);
    }
    // الأسرار من Edge secrets بس — ولا قيمة مكتوبة
    for (final name in ['APPLE_ISSUER_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'GOOGLE_SERVICE_ACCOUNT_JSON']) {
      expect(fn, contains("Deno.env.get('$name')"), reason: name);
    }
    expect(fn, contains('not_configured'));
    expect(fn, isNot(contains('BEGIN PRIVATE KEY')));
  });

  test('الجدولة والسلّم والمزامنة ما يعرفوش الاشتراك — التذكير عمره ما يقف بسبب الدفع', () {
    final offenders = <String>[];
    for (final dir in ['lib/domain/scheduling', 'lib/domain/escalation', 'lib/data/services', 'lib/core/notifications', 'lib/data/sync']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('billing/') || src.contains('SubscriptionService') || src.contains('featureAllowed')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty);
    // وbootstrap (صحوة شاشة القفل) ما بيسألش البوابة قبل الجرعة
    final boot = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(boot, isNot(contains('featureAllowed')));
    expect(boot, isNot(contains('ensureFamilyFeature')));
  });

  test('الأسعار من المتجر: ولا رقم سعر مكتوب في شاشة الاشتراك', () {
    final screen = File('lib/features/billing/family_plan_screen.dart').readAsStringSync();
    expect(screen, isNot(matches(RegExp(r'\d+\s*(EGP|جنيه|\$|USD)'))));
    expect(screen, contains('remindersStayFreeLine'));
    expect(screen, contains('!kReleaseMode'));
  });
}
