// «يومك» بعد إعادة التصميم (المرحلة ٤، ٤ أكتوبر ٢٠٢٦): التحية بأيقونتها،
// الدايرة «X من Y» وسطرها، كارت «الجرعة الجاية» برسمته وشريحته، «باقي اليوم»
// من غير جرعات الكارت، والألوان: مفيش دهبي على الجاية ولا أحمر في أي حتة.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
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

/// بالخطوط الحقيقية — خط الاختبار بيرسم كل حرف مربّع، وقياس «الكلام جوّه
/// الدايرة» بيه بيقيس حاجة تانية (نفس سبب `wheels_se_test`).
Future<void> _loadFonts() async {
  final loader = FontLoader('Cairo');
  for (final f in [
    'Cairo-Regular.ttf',
    'Cairo-Medium.ttf',
    'Cairo-SemiBold.ttf',
    'Cairo-Bold.ttf',
    'Cairo-ExtraBold.ttf',
  ]) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFonts);

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

    screenTest('التحية: شمس الصبح، وهلال بالليل — والأيقونة **قبل** الكلام (يمينه في RTL)', (tester) async {
      await h.services.patients.saveProfile(h.services.patientId, name: 'محمد');
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
      expect(find.text('صباح الخير يا محمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-sun')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const ValueKey('greeting-sun'))).color, isNot(F.gold));
      // قبل = على يمين التحية في RTL (مراجعة المالك، ٥ أكتوبر ٢٠٢٦)
      expect(
        tester.getCenter(find.byKey(const ValueKey('greeting-sun'))).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('home-greeting'))).dx),
        reason: 'الشمس بعد التحية — المفروض قبلها زي التصميم',
      );

      // **الضهر صباح** — الحد بقى الشروق/الغروب الحقيقيين (٥ أكتوبر ٢٠٢٦)،
      // مش ١٢: الساعة ١ الضهر لسه «صباح الخير» وشمسها، لحد الغروب
      await tester.pumpWidget(const SizedBox.shrink());
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 13)));
      expect(find.text('صباح الخير يا محمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-sun')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 21)));
      expect(find.text('مساء الخير يا محمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-moon')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('greeting-moon'))).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('home-greeting'))).dx),
      );
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

  group('الدايرة — الكلام جوّاها، مش لازقها (المالك، ٥ أكتوبر ٢٠٢٦)', () {
    Future<void> pumpRing(WidgetTester tester, Widget child, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(375, 667); // آيفون SE
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: F.light,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: c!),
          ),
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(F.s16), child: Center(child: child))),
        ),
      );
      await tester.pump();
    }

    /// كل ركن من كل نص جوّه الدايرة الداخلية (نص القطر − سمك الخط − هامش).
    void expectInsideRing(WidgetTester tester) {
      final ring = find.byKey(const ValueKey('today-progress-ring'));
      expect(ring, findsOneWidget);
      final rect = tester.getRect(ring);
      final radius = rect.width / 2 - ringStroke - 2;
      for (final e in find.descendant(of: ring, matching: find.byType(Text)).evaluate()) {
        final box = tester.getRect(find.byWidget(e.widget));
        for (final corner in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
          expect(
            (corner - rect.center).distance,
            lessThanOrEqualTo(radius),
            reason: '«${(e.widget as Text).data}» لازق في الدايرة أو طالع منها '
                '(ركنه بعيد ${(corner - rect.center).distance.toStringAsFixed(1)} ونص القطر الحر ${radius.toStringAsFixed(1)})',
          );
        }
      }
    }

    for (final scale in [1.0, 1.3]) {
      screenTest('الكبيرة على SE بخط ×$scale — وبعدّ عريض «١٠ من ١٢»', (tester) async {
        await pumpRing(
          tester,
          const TodayProgressRow(progress: TodayProgress(taken: 10, total: 12, line: goingWellLine)),
          scale: scale,
        );
        expectInsideRing(tester);
        expect(find.text('جرعات اليوم'), findsOneWidget);
        expect(find.text('١٠ من ١٢'), findsOneWidget);
      });

      screenTest('المدمجة (جنب التحية) بخط ×$scale', (tester) async {
        await pumpRing(
          tester,
          const TodayProgressRing(progress: TodayProgress(taken: 10, total: 12, line: goingWellLine)),
          scale: scale,
        );
        expectInsideRing(tester);
      });
    }
  });

  group('دواءين في الكارت — شكل التصميم برضه (المالك، ٥ أكتوبر ٢٠٢٦)', () {
    final h = Harness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    Future<int> add(String name, int hour, {MedicineForm? form}) => h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: name,
          timings: [FixedTiming(MinuteOfDay.hm(hour))],
          startDate: aug31,
          amountLabel: 'قرص واحد',
          form: form,
        );

    screenTest('العنوان «الجرعة الجاية»، رسمة كبيرة لكل سطر، وزرار «أخدتها» أخضر مليان لكل دوا', (tester) async {
      await add('Concor', 7, form: MedicineForm.tablet); // فاتت
      await add('Telfast', 10, form: MedicineForm.syrup); // معادها دلوقتي
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 10)));

      final card = find.byType(NowBlock);
      expect(find.descendant(of: card, matching: find.text('الجرعة الجاية')), findsOneWidget);
      expect(find.textContaining('الجرعات —'), findsNothing, reason: 'العدّاد اتشال من العنوان');

      // رسمة التصميم لكل سطر — الوسطانية، مش مصغّرة لـ٥٦
      for (final key in ['med-type-art-tablet', 'med-type-art-syrup']) {
        final art = find.descendant(of: card, matching: find.byKey(ValueKey(key)));
        expect(art, findsOneWidget);
        expect(tester.getSize(art).width, nextDosePictureCompactSize, reason: key);
      }

      // زرار **محدّد أخضر** لكل سطر («أخدتها») — المليان الوحيد «أخدتهم
      // كلهم» (قاعدة «زرارين أساسيين كحد أقصى»، المالك ٥ أكتوبر) — ومفيش
      // «تأكيد» المحدّد القديم
      expect(find.descendant(of: card, matching: find.widgetWithText(OutlinedButton, 'تأكيد')), findsNothing);
      final lineButtons = find.descendant(of: card, matching: find.widgetWithText(OutlinedButton, 'أخدتها'));
      expect(lineButtons, findsNWidgets(2));
      for (final b in tester.widgetList<OutlinedButton>(lineButtons)) {
        expect(b.style!.foregroundColor!.resolve({}), F.green);
        expect(b.style!.side!.resolve({})!.color, F.green);
      }
      expect(find.descendant(of: card, matching: find.widgetWithText(FilledButton, 'أخدتها')), findsNothing);
      expect(find.text('أخدتهم كلهم'), findsOneWidget);

      // **الساعة مرة واحدة لكل دوا**: في صفها الكبير بس — مفيش «كان معادها»
      // ولا «معادها دلوقتي — ١٠:٠٠ ص» ولا كلمة «دلوقتي» فوق الاسم.
      expect(find.text('٧:٠٠ ص'), findsOneWidget);
      expect(find.text('١٠:٠٠ ص'), findsOneWidget);
      expect(find.textContaining('كان معادها'), findsNothing);
      expect(find.text('معادها دلوقتي'), findsOneWidget);
      expect(find.text('لسه ما اتأكدتش'), findsOneWidget);
      expect(find.text('دلوقتي'), findsNothing);
      expect(find.text('الجاية'), findsNothing);

      expectNoRedAndMinSize(tester);
    });

    screenTest('«أخدتهم كلهم» عمره ما يكتب جرعة لسه ما جاش معادها — والجاية في «باقي اليوم»', (tester) async {
      await add('Concor', 7); // فاتت
      await add('Telfast', 10); // معادها دلوقتي
      final zyrtec = await add('Zyrtec', 20); // لسه جاية
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 10)));

      // الجاية برّه الكارت وجوّه «باقي اليوم»
      final card = find.byType(NowBlock);
      expect(find.descendant(of: card, matching: find.text('Zyrtec')), findsNothing);
      expect(find.descendant(of: find.byType(DayRail), matching: find.text('Zyrtec')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm-all')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      // القاعدة (المالك، ٥ أكتوبر): «أخدتهم كلهم» عمره ما يأكّد جرعة
      // الساعة ٨ م وإحنا الساعة ١٠ الصبح — بنقراها من القاعدة مباشرة.
      final rows = await h.db.customSelect(
        'SELECT e.state AS state FROM dose_events e '
        'JOIN dose_schedules s ON s.id = e.dose_schedule_id '
        'WHERE s.medication_id = ?',
        variables: [Variable.withInt(zyrtec)],
      ).get();
      for (final r in rows) {
        expect(r.read<String>('state'), isNot('taken'), reason: 'جرعة بكرة/بالليل اتأكّدت بدري في صمت');
      }
      // وبعد التأكيد هي بقت «الجرعة الجاية»
      expect(find.descendant(of: find.byType(NowBlock), matching: find.text('Zyrtec')), findsOneWidget);
    });

    screenTest('تأكيد سطر بزراره الأخضر بيمشي على جرعته هو', (tester) async {
      final concor = await add('Concor', 7);
      await add('Telfast', 10);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 10)));

      final key = find.byKey(ValueKey('confirm-${await _scheduleOf(h, concor)}'));
      expect(key, findsOneWidget);
      await tester.tap(key);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      // الكارت بقى عن دوا واحد، والتاني لسه مستني
      expect(find.descendant(of: find.byType(NowBlock), matching: find.text('Telfast')), findsOneWidget);
      expect(find.descendant(of: find.byType(NowBlock), matching: find.text('Concor')), findsNothing);
    });
  });
}

/// رقم جدول الجرعة بتاع دوا برقمه — لمفتاح زرار السطر.
Future<int> _scheduleOf(Harness h, int medicationId) async {
  final rows = await h.db.customSelect(
    'SELECT id FROM dose_schedules WHERE medication_id = ?',
    variables: [Variable.withInt(medicationId)],
  ).get();
  return rows.single.read<int>('id');
}
