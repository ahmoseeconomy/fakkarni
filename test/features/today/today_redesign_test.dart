// «يومك» بعد إعادة التصميم (المرحلة ٤، ٤ أكتوبر ٢٠٢٦): التحية بأيقونتها،
// الدايرة «X من Y» وسطرها، كارت «الجرعة الجاية» برسمته وشريحته، «باقي اليوم»
// من غير جرعات الكارت، والألوان: مفيش دهبي على الجاية ولا أحمر في أي حتة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/med_groups.dart';
import 'package:fakkarni/features/today/today_progress.dart';
import 'package:fakkarni/features/today/today_screen.dart';
import 'package:fakkarni/features/today/widgets/day_rail.dart';
import 'package:fakkarni/features/today/widgets/now_block.dart';
import 'package:fakkarni/features/today/widgets/progress_ring.dart';

import '../scan/scan_test_support.dart';

DoseEventView _dose(int h, DoseState state, {int id = 1}) => DoseEventView(
      doseScheduleId: id,
      medicationName: 'M$id',
      scheduledAt: DateTime(2026, 8, 31, h),
      state: state,
    );

void main() {
  group('الدايرة — حساب', () {
    final noon = DateTime(2026, 8, 31, 12);

    test('مفيش جرعات → مفيش دايرة، و«مفيش أدوية النهارده»', () {
      final p = todayProgress(const [], noon);
      expect(p.showsRing, isFalse);
      expect(p.line, noDosesTodayLine);
    });

    test('مفيش حاجة فاتت → «إنت ماشي كويس النهارده»، و«مش هاخده» برّه العد', () {
      final p = todayProgress([
        _dose(9, DoseState.taken, id: 1),
        _dose(10, DoseState.skipped, id: 2),
        _dose(20, DoseState.pending, id: 3),
      ], noon);
      expect((p.taken, p.total), (1, 2), reason: 'المتخطّية لا في X ولا في Y');
      expect(p.line, goingWellLine);
    });

    test('فاتت وفاضل → «فاضل لك جرعات النهارده» — من غير لوم', () {
      final p = todayProgress([_dose(8, DoseState.pending, id: 1), _dose(20, DoseState.pending, id: 2)], noon);
      expect(p.line, dosesLeftLine);
      expect((p.taken, p.total), (0, 2));
    });

    test('فاتت ومفيش فاضل → مفيش سطر، والدايرة فاضلة', () {
      final p = todayProgress([_dose(8, DoseState.missed, id: 1), _dose(9, DoseState.taken, id: 2)], noon);
      expect(p.line, isNull);
      expect(p.showsRing, isTrue);
      expect((p.taken, p.total), (1, 2));
    });

    test('جوّه المهلة لسه مش «فاتت» — دي «فاضلة»', () {
      final p = todayProgress([_dose(12, DoseState.pending)], DateTime(2026, 8, 31, 12, 30));
      expect(p.line, goingWellLine);
    });

    test('مفيش كلمة لوم في أي سطر', () {
      for (final line in [goingWellLine, dosesLeftLine, noDosesTodayLine]) {
        for (final w in ['فاتت', 'نسيت', 'غلط', 'متأخر']) {
          expect(line, isNot(contains(w)));
        }
      }
    });
  });

  group('الشاشة', () {
    final h = Harness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    Future<int> add(String name, int hour, {MedicationPurpose? purpose, MedicineForm? form}) =>
        h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: name,
          timings: [FixedTiming(MinuteOfDay.hm(hour))],
          startDate: aug31,
          amountLabel: 'قرص واحد',
          purpose: purpose,
          form: form,
        );

    screenTest('التحية: شمس الصبح، وهلال بالليل', (tester) async {
      await h.services.patients.saveProfile(h.services.patientId, name: 'محمد');
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
      expect(find.text('صباح الخير يا محمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-sun')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const ValueKey('greeting-sun'))).color, isNot(F.gold));

      await tester.pumpWidget(const SizedBox.shrink());
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 21)));
      expect(find.text('مساء الخير يا محمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-moon')), findsOneWidget);
    });

    screenTest('الدايرة «X من Y» وسطرها، وعلى الشاشة الطويلة دايرة كبيرة تحت التحية', (tester) async {
      await add('Concor', 9);
      await add('Telfast', 20);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
      expect(find.text('٠ من ٢'), findsOneWidget);
      expect(find.text(goingWellLine), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('today-progress-ring'))).width, TodayProgressRow.ringSize);
      expect(find.byIcon(Icons.eco), findsOneWidget, reason: 'الورقة جنب السطر');
    });

    screenTest('مفيش أدوية → مفيش دايرة، والسطر «مفيش أدوية النهارده»', (tester) async {
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
      expect(find.byKey(const ValueKey('today-progress-ring')), findsNothing);
      expect(find.text(noDosesTodayLine), findsOneWidget);
    });

    screenTest('كارت «الجرعة الجاية»: رسمة نوعه من غير كلام، الاسم، شريحة الغرض الهادية، الجرعة والساعة بـص/م، و«أخدتها» أخضر', (tester) async {
      await add('Concor 5 mg', 9, purpose: MedicationPurpose.pressure, form: MedicineForm.tablet);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));

      final card = find.byType(NowBlock);
      expect(find.descendant(of: card, matching: find.text('الجرعة الجاية')), findsOneWidget);
      final art = find.descendant(of: card, matching: find.byKey(const ValueKey('med-type-art-tablet')));
      expect(art, findsOneWidget);
      expect(tester.getSize(art).width, nextDosePictureSize);
      expect(find.descendant(of: art, matching: find.byType(Text)), findsNothing, reason: 'الرسمة نضيفة');
      expect(find.descendant(of: card, matching: find.text('Concor 5 mg')), findsOneWidget);
      // الشريحة هادية — القلب الأحمر لعناوين «أدويتك» بس
      final chip = find.descendant(of: card, matching: find.byType(MedPurposeChip));
      expect(tester.widget<MedPurposeChip>(chip).neutral, isTrue);
      for (final icon in tester.widgetList<Icon>(find.descendant(of: chip, matching: find.byType(Icon)))) {
        expect(icon.color, F.mutedDark);
      }
      expect(find.descendant(of: card, matching: find.text('قرص واحد')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('٩:٠٠ ص')), findsOneWidget);
      final button = tester.widget<FilledButton>(find.descendant(of: find.byKey(const ValueKey('confirm-all')), matching: find.byType(FilledButton)));
      expect(button.style!.backgroundColor!.resolve({}), F.green, reason: '«أخدتها» أخضر مش أحمر');
      expect(find.text('أخدتها'), findsOneWidget);
      expect(find.text('فكّرني بعد ١٥ دقيقة'), findsOneWidget);
      // ولا أيقونة دهبي غير الحافة: الساعة هادية
      for (final icon in tester.widgetList<Icon>(find.descendant(of: card, matching: find.byType(Icon)))) {
        expect(icon.color, isNot(F.gold));
      }
      expectNoRedAndMinSize(tester);
    });

    screenTest('«باقي اليوم»: من غير جرعات الكارت، رسمة صغيرة نضيفة، والجاية مش دهبي', (tester) async {
      await add('Concor', 9);
      await add('Telfast', 20, form: MedicineForm.syrup);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));

      final rail = find.byType(DayRail);
      expect(find.text('باقي اليوم'), findsOneWidget);
      expect(find.descendant(of: rail, matching: find.text('Concor')), findsNothing, reason: 'في الكارت');
      expect(find.descendant(of: rail, matching: find.text('Telfast')), findsOneWidget);
      expect(find.descendant(of: rail, matching: find.text('٨:٠٠ م')), findsOneWidget, reason: 'الساعة بـص/م');
      final art = find.descendant(of: rail, matching: find.byKey(const ValueKey('med-type-art-syrup')));
      expect(art, findsOneWidget);
      expect(find.descendant(of: art, matching: find.byType(Text)), findsNothing);
      expect(find.byKey(const ValueKey('rail-mark-upcoming')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-mark-needs-you')), findsNothing, reason: 'الجاية مش دهبي');
      expectNoRedAndMinSize(tester);
    });

    screenTest('مفيش شرايح «حبوب / قطرة / كريم»', (tester) async {
      await add('Concor', 9);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
      for (final chip in ['حبوب', 'قطرة', 'كريم']) {
        expect(find.text(chip), findsNothing);
      }
    });
  });
}
