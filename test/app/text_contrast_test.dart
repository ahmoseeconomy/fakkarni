// **كل نص يتقري، في الوضعين** — من الجهاز (٢٧ سبتمبر ٢٠٢٦، الوضع الليلي):
// «خلصت أدوية النهارده كلها. تسلم.» أخضر غامق على كارت غامق، أول صف في
// «خلال ٤٨ ساعة» باهت، و«أعدّل» أبيض على أبيض. الاختبار ده بيبني الشاشات
// اللي اتشافت فيها الحاجات دي (ومعاها البداية والإعدادات وضيف دوا) في
// النهاري والليلي، وبيحسب تباين كل نص على أرضيته الحقيقية.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/onboarding/profile_onboarding_screen.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart';
import '../support/contrast_audit.dart';

void main() {
  final h = Harness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.setUp();
  });
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  final aug31 = DateTime(2026, 8, 31);

  for (final dark in [false, true]) {
    final mode = dark ? 'ليلي' : 'نهاري';

    screenTest('$mode — «يومك»: كله اتاخد، و«خلال ٤٨ ساعة»، والجدول', (tester) async {
      F.setDark(on: dark);
      await h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Concor 5mg',
        timing: FixedTiming(MinuteOfDay.hm(9)),
        startDate: aug31,
        amountLabel: 'قرص واحد',
      );
      await h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Telfast',
        timing: FixedTiming(MinuteOfDay.hm(9, 30)),
        startDate: aug31,
        amountLabel: 'قرص واحد',
      );
      final now = DateTime(2026, 8, 31, 11);
      await h.services.scheduler.rescheduleAll(now: now);
      for (final s in await h.meds.activeSchedules(h.services.patientId)) {
        await h.services.events.markTaken(int.parse(s.id), aug31);
      }
      await h.pump(tester, TodayScreen(now: now));
      expect(find.textContaining('خلصت أدوية النهاردة'), findsOneWidget);
      expect(find.text('خلال ٤٨ ساعة'), findsOneWidget);
      expectReadableText(tester, where: 'يومك — كله اتاخد');
    });

    screenTest('$mode — «يومك»: جرعة مستنية وجرعة فاتت', (tester) async {
      F.setDark(on: dark);
      await h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Concor 5mg',
        timing: FixedTiming(MinuteOfDay.hm(8)),
        startDate: aug31,
      );
      await h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Augmentin',
        timing: FixedTiming(MinuteOfDay.hm(14)),
        startDate: aug31,
      );
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 10)));
      expectReadableText(tester, where: 'يومك — مستنية');
    });

    screenTest('$mode — «ضيف دوا» بشرايح مختارة', (tester) async {
      F.setDark(on: dark);
      await h.pump(tester, AddMedicationScreen(today: aug31));
      await tester.tap(find.text('مرتين'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('meal-after')));
      await settle(tester);
      expectReadableText(tester, where: 'ضيف دوا');
    });

    screenTest('$mode — مراجعة الروشتة: «أعدّل» و«تمام» والملاحظات', (tester) async {
      F.setDark(on: dark);
      final every12 = PrescriptionReading.fromJson({
        'medications': [
          {
            'name': {'value': 'Augmentin 1g', 'confidence': 0.95},
            'amount': {'value': 'قرص', 'confidence': 0.95},
            'timing': {'text': 'كل ١٢ ساعة بعد الأكل', 'confidence': 0.95},
          },
        ],
      }).lines.single;
      await h.pump(tester, ReviewPrescriptionScreen(
        reading: PrescriptionReading(
          doctor: const ReadField(value: null, confidence: 1),
          lines: [clearLine, unclearLine, every12],
        ),
        today: aug31,
      ));
      expect(find.text('أعدّل'), findsOneWidget);
      expectReadableText(tester, where: 'مراجعة الروشتة');
    });

    screenTest('$mode — مراجعة الروشتة و«تمام» مقفولة (نص الزرار المقفول يتقري)', (tester) async {
      F.setDark(on: dark);
      await h.pump(tester, ReviewPrescriptionScreen(
        reading: PrescriptionReading(
          doctor: const ReadField(value: null, confidence: 1),
          lines: [unclearLine],
        ),
        today: aug31,
      ));
      final confirm = tester.widget<FilledButton>(find.descendant(
          of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)));
      expect(confirm.onPressed, isNull, reason: 'الحالة المقفولة لازم تبقى متختبرة');
      expectReadableText(tester, where: 'مراجعة — تمام مقفولة');
    });

    screenTest('$mode — الإعدادات', (tester) async {
      F.setDark(on: dark);
      await h.pump(tester, const SettingsScreen());
      expectReadableText(tester, where: 'الإعدادات');
    });

    screenTest('$mode — البداية: الاسم («كمّل» مقفولة) والسن', (tester) async {
      F.setDark(on: dark);
      await h.pump(tester, const ProfileOnboardingScreen());
      expectReadableText(tester, where: 'البداية — الاسم');
      await tester.enterText(find.byKey(const ValueKey('profile-name')), 'الحاج أحمد');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('profile-next')));
      await settle(tester);
      expectReadableText(tester, where: 'البداية — السن');
    });
  }
}
