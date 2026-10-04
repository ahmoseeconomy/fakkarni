import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_sheet.dart';
import 'package:fakkarni/core/widgets/med_name.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/add_sheet.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/medication/med_groups.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';

import '../../support/contrast_audit.dart';
import '../scan/scan_test_support.dart';

/// «أدويتك» بعد إعادة التصميم (٤ أكتوبر ٢٠٢٦): مجموعات بالغرض، صف لكل دوا
/// برسمته والاسم عليها، شريحة الغرض، الساعة وسطر القاعدة، «تعديل» بس، و«ضيف
/// دوا» أخضر تحت. الإيقاف والرجوع والشيل جوّه شاشة التعديل.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<int> add(
    String name,
    FixedTiming timing, {
    String? amount,
    bool unknown = false,
    MedicationPurpose? purpose,
    MedicineForm? form,
    DateTime? start,
  }) =>
      h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: name,
        timings: [timing],
        startDate: start ?? aug31,
        amountLabel: amount,
        amountUnknown: unknown,
        purpose: purpose,
        form: form,
      );

  Future<void> pump(WidgetTester tester, {Size size = const Size(1000, 3000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, MedicationsScreen(today: aug31));
  }

  double y(WidgetTester tester, Finder f) => tester.getCenter(f).dy;

  screenTest('العنوان «أدويتك» على اليمين — ومن غير سطر عدد تحته (المالك)', (tester) async {
    await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(9)), amount: 'قرص', purpose: MedicationPurpose.pressure);
    await add('Glucophage 500 mg', FixedTiming(MinuteOfDay.hm(9)), amount: 'قرص', purpose: MedicationPurpose.sugar);
    final stopped = await add('Telfast 180 mg', FixedTiming(MinuteOfDay.hm(20)), amount: 'قرص');
    await h.meds.stopMedication(stopped);
    await pump(tester);

    expect(find.text('أدويتك'), findsOneWidget);
    final title = tester.getRect(find.text('أدويتك'));
    final list = tester.getRect(find.byType(ListView));
    expect(title.right, closeTo(list.right - F.gap, 1.5), reason: 'العنوان على البداية (اليمين)');
    for (final count in ['دواءين', 'دوا واحد', '٢ أدوية', '٣ أدوية']) {
      expect(find.text(count), findsNothing, reason: 'سطر العدد اتشال');
    }
    expect(find.byIcon(Icons.arrow_back), findsNothing, reason: 'تبويب — مفيش رجوع');
    expect(find.byIcon(Icons.arrow_back_ios), findsNothing);
  });

  screenTest('المجموعات بالغرض بترتيب التصميم، و«من غير تصنيف» بعدهم و«موقوفة» آخر حاجة', (tester) async {
    await add('Fucidin', FixedTiming(MinuteOfDay.hm(21)), purpose: MedicationPurpose.skin);
    await add('Glucophage 500 mg', FixedTiming(MinuteOfDay.hm(9)), purpose: MedicationPurpose.sugar);
    await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(9)), purpose: MedicationPurpose.pressure);
    await add('Aspocid', FixedTiming(MinuteOfDay.hm(14)), purpose: MedicationPurpose.heart);
    await add('Systane', FixedTiming(MinuteOfDay.hm(8)), purpose: MedicationPurpose.eye);
    await add('Zyrtec', FixedTiming(MinuteOfDay.hm(22)));
    final stopped = await add('Telfast 180 mg', FixedTiming(MinuteOfDay.hm(20)), purpose: MedicationPurpose.pressure);
    await h.meds.stopMedication(stopped);
    await pump(tester);

    Finder head(MedGroup g) => find.byKey(ValueKey('med-group-${g.name}'));
    final order = [MedGroup.heartPressure, MedGroup.sugar, MedGroup.eyeSkin, MedGroup.unclassified, MedGroup.stopped];
    for (final g in order) {
      expect(head(g), findsOneWidget, reason: g.label);
    }
    for (var i = 1; i < order.length; i++) {
      expect(y(tester, head(order[i - 1])), lessThan(y(tester, head(order[i]))), reason: '${order[i - 1].label} قبل ${order[i].label}');
    }
    expect(find.text('للقلب والضغط'), findsOneWidget);
    expect(find.text('للعين والجلد'), findsOneWidget);
    expect(find.text('من غير تصنيف'), findsOneWidget);
    // القلب والضغط مع بعض، والعين والجلد مع بعض
    final cardio = [y(tester, find.byKey(const ValueKey('med-row-3'))), y(tester, find.byKey(const ValueKey('med-row-4')))];
    expect(cardio.every((v) => v > y(tester, head(MedGroup.heartPressure)) && v < y(tester, head(MedGroup.sugar))), isTrue);
    // الموقوف تحت «موقوفة» مش تحت مجموعته
    expect(y(tester, find.byKey(ValueKey('med-row-$stopped'))), greaterThan(y(tester, head(MedGroup.stopped))));
    // المجموعات اللي مفيهاش حاجة مش موجودة
    expect(head(MedGroup.cholesterol), findsNothing);
    expect(head(MedGroup.vitamins), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('دوا بجرعتين = صف واحد، والساعتين بـص/م في سطر القاعدة مع كلمة الأكل', (tester) async {
    final id = await h.meds.addMedicationWithDoses(
      patientId: h.services.patientId,
      name: 'Augmentin 1g',
      timings: const [FixedTiming(MinuteOfDay.hm(20)), FixedTiming(MinuteOfDay.hm(8))],
      startDate: aug31,
      amountLabel: 'قرص',
    );
    await pump(tester);

    expect(find.byKey(ValueKey('med-row-$id')), findsOneWidget);
    // الجرعة في سطر، والساعات بالترتيب وبـص/م في السطر اللي تحته — من غير شَرطة
    expect(tester.widget<Text>(find.byKey(ValueKey('med-dose-$id'))).data, 'قرص');
    expect(tester.widget<Text>(find.byKey(ValueKey('med-times-$id'))).data, '٨:٠٠ ص و٨:٠٠ م');
    expect(y(tester, find.byKey(ValueKey('med-dose-$id'))), lessThan(y(tester, find.byKey(ValueKey('med-times-$id')))));
    expect(find.byKey(ValueKey('med-extra-$id')), findsNothing, reason: 'مفيش كلمة أكل ولا أيام — مفيش سطر تالت');
  });

  screenTest('الجرعة مش معروفة في سطر والساعة تحته، وكلمة الأكل في سطر تالت', (tester) async {
    final id = await h.meds.addMedicationWithDoses(
      patientId: h.services.patientId,
      name: 'Telfast 180 mg',
      timings: const [FixedTiming(MinuteOfDay.hm(10))],
      startDate: aug31,
      amountUnknown: true,
      mealRelation: MealRelation.after,
    );
    await pump(tester);

    final dose = tester.widget<Text>(find.byKey(ValueKey('med-dose-$id'))).data!;
    final times = tester.widget<Text>(find.byKey(ValueKey('med-times-$id'))).data!;
    final extra = tester.widget<Text>(find.byKey(ValueKey('med-extra-$id'))).data!;
    expect(dose, 'الجرعة مش معروفة');
    expect(times, '١٠:٠٠ ص');
    expect(extra, MealRelation.after.label);
    for (final line in [dose, times]) {
      expect(line, isNot(contains('—')), reason: 'مفيش شَرطة في سطر الجرعة ولا الساعة');
    }
    final ys = ['med-dose-$id', 'med-times-$id', 'med-extra-$id'].map((k) => y(tester, find.byKey(ValueKey(k)))).toList();
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: 'الجرعة ← الساعة ← كلمة الأكل');
    // الساعة جنب سطر الساعات مش جنب الجرعة
    final clock = find.descendant(of: find.byKey(ValueKey('med-row-$id')), matching: find.byIcon(Icons.schedule));
    expect((y(tester, clock) - ys[1]).abs(), lessThan(12));
  });

  screenTest('الصف: الاسم بخط التطبيق ٢٤+، شريحة الغرض، وأيقونة ساعة — ولا حاجة دهبي', (tester) async {
    final id = await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(9)), amount: 'قرص', purpose: MedicationPurpose.pressure);
    await pump(tester);

    final name = tester.widget<Text>(find.descendant(of: find.byType(MedName), matching: find.text('Concor 5 mg')));
    expect(name.style?.fontSize, greaterThanOrEqualTo(F.medicationNameSize));
    expect(name.style?.fontFamily, F.bodyFamily);
    expect(find.byKey(const ValueKey('purpose-chip-pressure')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('purpose-chip-pressure')), matching: find.text('للضغط')), findsOneWidget);
    final row = find.byKey(ValueKey('med-row-$id'));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.schedule)), findsOneWidget);

    // الدهبي لـ«محتاجك دلوقتي» بس — مش على الساعة ولا على شريحة الغرض
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      expect(icon.color, isNot(F.gold), reason: '${icon.icon} دهبي');
    }
    for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
      final d = box.decoration;
      if (d is BoxDecoration) {
        expect(d.color, isNot(F.gold));
        expect((d.border as Border?)?.top.color, isNot(F.gold));
      }
    }
    expect(find.byIcon(Icons.mic), findsNothing, reason: 'مفيش زرار صوت');
    expectNoRedAndMinSize(tester);
  });

  screenTest('من غير صورة: رسمة نوعه ١٢٠ نضيفة من غير اسم عليها؛ من غير نوع: الرسمة العامة', (tester) async {
    await add('Systane', FixedTiming(MinuteOfDay.hm(8)), purpose: MedicationPurpose.eye, form: MedicineForm.drops);
    await add('Zyrtec', FixedTiming(MinuteOfDay.hm(22)));
    await pump(tester);

    final art = find.byKey(const ValueKey('med-type-art-drops'));
    expect(art, findsOneWidget);
    expect(tester.getSize(art), const Size(medRowPictureSize, medRowPictureSize));
    expect(find.descendant(of: art, matching: find.byType(Text)), findsNothing, reason: 'الرسمة زي الأصل — مفيش كلام عليها');
    expect(find.byKey(const ValueKey('med-type-art-generic')), findsOneWidget, reason: 'من غير نوع');
    // الاسم مكتوب مرة واحدة — جنب الرسمة
    expect(find.text('Systane'), findsOneWidget);
    expect(find.descendant(of: find.byType(MedName), matching: find.text('Systane')), findsOneWidget);
  });

  group('الإيقاف والرجوع والشيل — جوّه «تعديل»', () {
    Future<void> openEdit(WidgetTester tester, int id) async {
      await tester.tap(find.byKey(ValueKey('med-edit-$id')));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsOneWidget);
    }

    screenTest('على كل صف «تعديل» بس — مفيش «خيارات» ولا شيت', (tester) async {
      final id = await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
      await pump(tester);
      expect(find.byKey(ValueKey('med-edit-$id')), findsOneWidget);
      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('خيارات'), findsNothing);
      expect(tester.getSize(find.byKey(ValueKey('med-edit-$id'))).height, greaterThanOrEqualTo(F.minTapTarget));
    });

    screenTest('«وقّف الدوا ده» بينقله لـ«موقوفة»، و«رجّعه تاني» من التعديل بترجّعه', (tester) async {
      final id = await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
      await pump(tester);

      await openEdit(tester, id);
      expect(find.byKey(const ValueKey('resume-medication')), findsNothing, reason: 'شغّال — مفيش «رجّعه»');
      await tester.tap(find.text('وقّف الدوا ده'));
      await settle(tester);
      await tester.tap(find.text('أيوه، وقّفه'));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsNothing);
      expect(find.text('موقوفة'), findsOneWidget);
      expect(find.text('موقوف — التذكيرات واقفة'), findsOneWidget);

      await openEdit(tester, id);
      expect(find.text('وقّف الدوا ده'), findsNothing, reason: 'موقوف خلاص');
      await tester.tap(find.byKey(const ValueKey('resume-medication')));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsNothing);
      expect(find.text('موقوفة'), findsNothing);
    });

    screenTest('**التأكيد شرط**: «شيله خالص» بتسأل بالاسم، و«لا، سيبه» ما بتشيلش', (tester) async {
      final id = await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
      await pump(tester);

      await openEdit(tester, id);
      await tester.ensureVisible(find.byKey(const ValueKey('remove-medication')));
      await tester.tap(find.byKey(const ValueKey('remove-medication')));
      await settle(tester);
      expect(find.text('تشيل Concor 5 mg؟'), findsOneWidget);
      expect(find.textContaining('مفيش رجوع'), findsOneWidget);
      expectNoRedAndMinSize(tester);

      await tester.tap(find.text('لا، سيبه'));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsOneWidget, reason: 'لسه في التعديل');
      expect((await h.db.select(h.db.medications).get()).single.removedAt, isNull);
    });

    screenTest('«أيوه، شيله» بتشيله من القايمة — ومن غير مسح، ومن الموقوف كمان', (tester) async {
      final id = await add('Concor 5 mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
      final other = await add('Telfast 180 mg', FixedTiming(MinuteOfDay.hm(20)), amount: 'قرص');
      await h.meds.stopMedication(other);
      await pump(tester);

      await openEdit(tester, id);
      await tester.ensureVisible(find.byKey(const ValueKey('remove-medication')));
      await tester.tap(find.byKey(const ValueKey('remove-medication')));
      await settle(tester);
      await tester.tap(find.text('أيوه، شيله'));
      await settle(tester);
      expect(find.byType(EditMedicationScreen), findsNothing);
      expect(find.byKey(ValueKey('med-row-$id')), findsNothing);

      // الموقوف بيتشال من التعديل برضه
      await openEdit(tester, other);
      await tester.ensureVisible(find.byKey(const ValueKey('remove-medication')));
      await tester.tap(find.byKey(const ValueKey('remove-medication')));
      await settle(tester);
      await tester.tap(find.text('أيوه، شيله'));
      await settle(tester);
      expect(find.text('موقوفة'), findsNothing, reason: 'المتشال مش موقوف — مش في أي قسم');
      // الصفوف مكانها — شيل ناعم مش مسح
      expect((await h.db.select(h.db.medications).get()), hasLength(2));
    });
  });

  screenTest('جرعة مش معروفة → «الجرعة مش معروفة» بهدوء، مش ذهبي ولا أحمر', (tester) async {
    await add('Telfast 180 mg', FixedTiming(MinuteOfDay.hm(20)), unknown: true);
    await pump(tester);
    final line = tester.widget<Text>(find.textContaining('الجرعة مش معروفة'));
    expect(line.style?.color, F.mutedDark);
    expectNoRedAndMinSize(tester);
  });

  screenTest('دوا بدايته جاية بيقول «هيبدأ يوم …» — واللي بدأ لأ', (tester) async {
    await add('Augmentin', FixedTiming(MinuteOfDay.hm(7, 30)), amount: 'قرص', start: DateTime(2026, 9, 3));
    await add('Concor', FixedTiming(MinuteOfDay.hm(7, 30)), amount: 'قرص');
    await pump(tester);
    expect(find.text('هيبدأ يوم ٣ سبتمبر ٢٠٢٦'), findsOneWidget);
    expect(find.textContaining('هيبدأ'), findsOneWidget, reason: 'Concor بدأ خلاص');
  });

  screenTest('فاضي → «لسه مفيش أدوية.» و«ضيف دوا» موجود — مفيش مجموعات', (tester) async {
    await pump(tester);
    expect(find.text('لسه مفيش أدوية.'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-medication-card')), findsOneWidget);
    expect(find.byType(MedGroupHead), findsNothing);
  });

  screenTest('زرار «قريب منك» مش على الشاشة دي — مكانه حبّاية الرئيسية', (tester) async {
    await add('Concor 5mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
    await pump(tester);
    expect(find.textContaining('قريب منك'), findsNothing);
    expect(find.textContaining('صيدليات'), findsNothing);
  });

  screenTest('«ضيف دوا» تحت المجموعات: أخضر، ٦٤، وبيفتح نفس شيت الدوك بنفس المداخل', (tester) async {
    final stopped = await add('Telfast', FixedTiming(MinuteOfDay.hm(20)), amount: 'قرص');
    await h.meds.stopMedication(stopped);
    await add('Concor 5mg', FixedTiming(MinuteOfDay.hm(7)), amount: 'قرص');
    await pump(tester);

    final button = find.byKey(const ValueKey('add-medication-card'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(F.primaryButtonHeight));
    expect(tester.widget<FilledButton>(button).style!.backgroundColor!.resolve({}), F.green, reason: 'أخضر مش مرجاني');
    expect(find.descendant(of: button, matching: find.text('ضيف دوا')), findsOneWidget);
    expect(y(tester, button), greaterThan(y(tester, find.byKey(const ValueKey('med-group-stopped')))), reason: 'آخر حاجة');

    await tester.tap(button);
    await tester.pump();
    await tester.pump(F.sheetDuration);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FSheet), findsOneWidget);
    for (final label in addSheetLabels) {
      expect(find.descendant(of: find.byType(FSheet), matching: find.text(label)), findsOneWidget, reason: label);
    }
    expectNoRedAndMinSize(tester);
  });

  for (final dark in [false, true]) {
    screenTest('كل المجموعات مقروءة — ${dark ? 'بالليل' : 'بالنهار'}', (tester) async {
      F.setDark(on: dark);
      addTearDown(() => F.setDark(on: false));
      final purposes = [...MedicationPurpose.values, null];
      for (final (i, p) in purposes.indexed) {
        await add('Med $i', FixedTiming(MinuteOfDay.hm(8 + i)), amount: 'قرص', purpose: p);
      }
      final stopped = await add('Stopped', FixedTiming(MinuteOfDay.hm(22)), amount: 'قرص');
      await h.meds.stopMedication(stopped);
      await pump(tester, size: const Size(1000, 6000));
      for (final g in MedGroup.values) {
        expect(find.byKey(ValueKey('med-group-${g.name}')), findsOneWidget, reason: g.label);
      }
      expectReadableText(tester, where: '«أدويتك» ${dark ? 'ليلي' : 'نهاري'}');
    });
  }

  for (final dark in [false, true]) {
    test('أيقونة كل مجموعة ≥٣:١ على أرضيتها — ${dark ? 'بالليل' : 'بالنهار'}', () {
      F.setDark(on: dark);
      addTearDown(() => F.setDark(on: false));
      for (final g in MedGroup.values) {
        expect(contrastRatio(g.ink, g.tint), greaterThanOrEqualTo(3), reason: g.label);
        expect(contrastRatio(F.ink, g.tint), greaterThanOrEqualTo(4.5), reason: '${g.label}: الكلمة');
      }
    });
  }

  test('كل غرض ليه مجموعة، والقلب مع الضغط والعين مع الجلد', () {
    expect(MedGroup.of(MedicationPurpose.heart), MedGroup.heartPressure);
    expect(MedGroup.of(MedicationPurpose.pressure), MedGroup.heartPressure);
    expect(MedGroup.of(MedicationPurpose.eye), MedGroup.eyeSkin);
    expect(MedGroup.of(MedicationPurpose.skin), MedGroup.eyeSkin);
    expect(MedGroup.of(MedicationPurpose.cholesterol), MedGroup.cholesterol);
    expect(MedGroup.of(null), MedGroup.unclassified);
  });
}
