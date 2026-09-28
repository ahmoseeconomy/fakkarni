// أسماء الأدوية كانت بتطلع بخط mono (المالك، ٢٨ سبتمبر ٢٠٢٦). خط التطبيق
// فيه لاتيني — ولا نص على شاشة مريض بيتحلّ لخط mono.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/doctor/doctor_page_screen.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart';

bool _isMono(String? family) {
  if (family == null) return false;
  final f = family.toLowerCase();
  return f.contains('mono') || f.contains('courier') || f.contains('menlo') || f.contains('consolas');
}

void main() {
  test('مفيش خط mono في lib — غير شاشتين المطوّر', () {
    const devOnly = {'lib/features/settings/diagnostics_log_screen.dart', 'lib/features/scan/debug_panel.dart', 'lib/core/theme/tokens.dart'};
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r"'monospace'|Courier|Menlo|RobotoMono|Consolas").hasMatch(src)) offenders.add('${f.path}: خط نظام mono');
      if (!devOnly.contains(f.path) && src.contains('monoFamily')) offenders.add('${f.path}: F.monoFamily');
    }
    expect(offenders, isEmpty);
    expect(F.fontFallback.any(_isMono), isFalse, reason: 'الاحتياطي خطوط التطبيق بس');
    expect(F.light.textTheme.bodyMedium!.fontFamilyFallback, isNot(contains('monospace')));
  });

  final h = Harness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.setUp();
  });
  tearDown(h.tearDown);

  void expectNoMonoText(WidgetTester tester, String where) {
    final bad = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final style = DefaultTextStyle.of(e).style.merge(w.style);
      final families = [style.fontFamily, ...?style.fontFamilyFallback];
      if (families.any(_isMono)) bad.add('«${w.data ?? w.textSpan?.toPlainText()}» → $families');
    }
    expect(bad, isEmpty, reason: where);
  }

  final now = DateTime(2026, 8, 31, 10);
  for (final (name, screen) in <(String, Widget Function())>[
    ('يومك', () => TodayScreen(now: now)),
    ('الأدوية', () => const MedicationsScreen()),
    ('ملفّي', () => const HealthFileScreen()),
    ('نمط كبار السن', () => ElderHomeScreen(now: now)),
    ('للدكتور', () => const DoctorPageScreen()),
    ('الإعدادات', () => const SettingsScreen()),
  ]) {
    screenTest('«$name»: ولا نص بخط mono — «Augmentin 1g» و«concor» بخط التطبيق', (tester) async {
      for (final (n, hr) in [('Augmentin 1g', 9), ('concor', 21)]) {
        await h.meds.addMedication(patientId: h.services.patientId, name: n, timing: FixedTiming(MinuteOfDay.hm(hr)), startDate: DateTime(2026, 8, 31));
      }
      await h.services.scheduler.rescheduleAll(now: now);
      // جوّه Scaffold زي الهيكل — من غير Material فلاتر بيحط خط «غلط» mono
      await h.pump(tester, Scaffold(body: screen()));
      expect(find.byType(Text), findsWidgets);
      expectNoMonoText(tester, name);
    });
  }
}
