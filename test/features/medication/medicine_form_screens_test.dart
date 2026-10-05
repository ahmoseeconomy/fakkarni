// «نوعه؟» على «ضيف دوا» والتعديل (طلب المدير، ٤ أكتوبر ٢٠٢٦): اختياري،
// بيقول وحدة المخزون، المرهم والبخاخة من غير مخزون، والتغيير ما بيلمسش
// التذكيرات.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/package_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/today/widgets/refill_lines.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<int> seed({String? amount = 'واحدة', MedicineForm? form}) => h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Omeprazole 20mg',
        amountLabel: amount,
        timings: const [FixedTiming(MinuteOfDay.hm(8))],
        startDate: aug31,
        form: form,
      );

  Future<String?> formOf(int id) async =>
      (await (h.db.select(h.db.medications)..where((t) => t.id.equals(id))).getSingle()).form;

  screenTest('التعديل: «كبسولة» بتتحفظ، والمخزون بيسأل «باقي كام كبسولة؟» — ومفيش إشعار اتلمس', (tester) async {
    final id = await seed();
    // نفس الساعة اللي باب الحفظ بيجدول بيها (الحقيقية) — فالفرق الوحيد الممكن هو النوع
    await h.services.scheduler.rescheduleAll();
    final before = Map.of(h.sink.scheduled);
    final cancelledBefore = h.sink.cancelled.length;
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, EditMedicationScreen(medicationId: id));

    // «كبسولة» تالت صف في البكرة (أول صف «من غير تحديد»)
    await tester.drag(find.byKey(const ValueKey('edit-form-wheel')), const Offset(0, -2 * 44.0));
    await settle(tester);
    expect(await formOf(id), 'capsule');
    expect(find.text('باقي كام كبسولة؟'), findsOneWidget);
    expect(h.sink.scheduled.keys.toSet(), before.keys.toSet(), reason: 'النوع مش جرعة — نفس الأرقام');
    expect({for (final e in h.sink.scheduled.entries) e.key: e.value.body},
        {for (final e in before.entries) e.key: e.value.body}, reason: 'ولا متن إشعار اتغيّر');
    expect(h.sink.cancelled.length, cancelledBefore);

    // الرجوع لـ«من غير تحديد» بيمسح — اختياري فعلاً
    await tester.drag(find.byKey(const ValueKey('edit-form-wheel')), const Offset(0, 2 * 44.0));
    await settle(tester);
    expect(await formOf(id), isNull);
    expectNoRedAndMinSize(tester);
  });

  screenTest('التعديل: المرهم مالوش كارت مخزون', (tester) async {
    final id = await seed(form: MedicineForm.ointment);
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, EditMedicationScreen(medicationId: id));
    expect(find.byKey(const ValueKey('stock-left-card')), findsNothing);
  });

  screenTest('«يومك»: بخاخة عليها مخزون قديم ما بتطلّعش «قرب يخلص»', (tester) async {
    final id = await seed(form: MedicineForm.inhaler);
    await StockRepository(h.db).setQuantity(id, 1);
    await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));
    expect(find.byKey(ValueKey('refill-$id')), findsNothing);
    expect(await StockRepository(h.db).all(h.services.patientId), isEmpty);
  });

  screenTest('«ضيف دوا» من علبة مكتوب عليها Capsules: «كبسولة» متعلّمة، والحفظ بيكتبها', (tester) async {
    ReadField<String> sure(String v) => ReadField(value: v, confidence: 0.95);
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(
      tester,
      AddMedicationScreen(
        today: aug31,
        initialName: 'Omeprazole 20 mg',
        packageReading: PackageReading(
          brand: sure('Omeprazole'),
          activeIngredient: sure('Omeprazole'),
          strength: sure('20 mg'),
          form: sure('Capsules'),
          packSize: sure('14 capsules'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('نوعه؟ (لو حابب)'), findsOneWidget);
    // النوع من العلبة واقف على البكرة (البكرة بدل الشرايح — ٥ أكتوبر)
    expect(find.byKey(const ValueKey('form-wheel')), findsOneWidget);
    expect(find.text('كبسولة'), findsWidgets);
    // جرعة واحدة = مفيش كارت صفوف (٥ أكتوبر مساءً) — الساعة من بكرة
    // «الساعة كام؟» على طول (الشرايح السريعة اتشالت)
    await pickTime(tester, const MinuteOfDay(9 * 60));
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    final med = (await h.db.select(h.db.medications).get()).single;
    expect(med.form, 'capsule');
  });

  screenTest('«ضيف دوا» بالإيد: من غير ما يختار، النوع فاضي — مفيش تخمين', (tester) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, AddMedicationScreen(today: aug31, initialName: 'Concor', initialAmount: 'قرص'));
    await settle(tester);
    // لفّة للشراب ولفّة راجعة لـ«من غير تحديد» — null برضه (البكرة بدل
    // دوستين على الشريحة)
    await tester.drag(find.byKey(const ValueKey('form-wheel')), const Offset(0, -5 * 44.0));
    await settle(tester);
    await tester.drag(find.byKey(const ValueKey('form-wheel')), const Offset(0, 5 * 44.0));
    await settle(tester);
    // جرعة واحدة = مفيش كارت صفوف (٥ أكتوبر مساءً) — الساعة من بكرة
    // «الساعة كام؟» على طول (الشرايح السريعة اتشالت)
    await pickTime(tester, const MinuteOfDay(9 * 60));
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    expect((await h.db.select(h.db.medications).get()).single.form, isNull);
  });
}
