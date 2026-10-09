import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_preferences.dart';

void main() {
  test('صوت التصعيد مفتوح افتراضياً ويتغيّر من نسخة التفضيلات فقط', () {
    const defaults = CaregiverPreferences();
    expect(defaults.escalationSound, isTrue);
    expect(defaults.copyWith(escalationSound: false).escalationSound, isFalse);
    expect(
      defaults.escalationSound,
      isTrue,
      reason: 'copyWith ما يغيّرش النسخة الأصلية',
    );
  });

  test('العمود السحابي آمن للحسابات الموجودة والجديدة', () {
    final sql = File('supabase/migrations/0040_caregiver_escalation_sound.sql')
        .readAsStringSync();
    expect(
      sql,
      contains(
        'add column if not exists escalation_sound boolean not null default true',
      ),
    );

    final remote = File('lib/data/care/supabase_caregiver_preferences.dart')
        .readAsStringSync();
    expect(
      remote,
      contains("escalationSound: row['escalation_sound'] != false"),
    );
    expect(remote, contains("'escalation_sound': preferences.escalationSound"));
  });
}
