import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/repositories/stock_unit_store.dart';
import 'package:fakkarni/domain/medication/stock.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/medication/refill_actions.dart';
import 'package:fakkarni/features/today/widgets/refill_lines.dart';

import '../scan/scan_test_support.dart';

/// المخزون اختياري، بيتكتب على بكرة، و«قرب يخلص» سطر ذهبي على «يومك» بزرارين
/// — والطلب من الصيدلية بيفتح واتساب برسالة جاهزة والمستخدم هو اللي بيبعت.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<int> seedConcor() => h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Concor 5mg',
        amountLabel: 'قرص واحد',
        timings: const [FixedTiming(MinuteOfDay.hm(7)), FixedTiming(MinuteOfDay.hm(20))],
        startDate: aug31,
      );

  Future<double?> quantity(int id) async => (await StockRepository(h.db).rowFor(id))?.quantity;

  screenTest('صفحة الدوا: المخزون فاضي لحد ما البكرة تتحرك، و«تمام» بتكتبه', (tester) async {
    final id = await seedConcor();
    await h.pump(tester, EditMedicationScreen(medicationId: id));

    expect(find.text('باقي كام قرص؟'), findsOneWidget, reason: 'الوحدة من خانة الجرعة — كارت لوحده');
    expect(find.byKey(const ValueKey('stock-left-card')), findsOneWidget);
    expect(await quantity(id), isNull, reason: 'مكان البكرة مش إجابة');
    await tester.drag(find.byKey(const ValueKey('stock-wheel')), const Offset(0, -FNumberWheel.itemExtent * 2));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('stock-edit-done')));
    await settle(tester);
    expect(await quantity(id), isNotNull);
    expect(find.byKey(const ValueKey('stock-summary')), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«يومك»: سطر ذهبي لما يفضل ≤٥ أيام، و«اشتريت علبة جديدة» بتزوّد', (tester) async {
    final id = await seedConcor();
    await StockRepository(h.db).setQuantity(id, 20); // ١٠ أيام
    await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));
    expect(find.byKey(ValueKey('refill-$id')), findsNothing, reason: 'مش قرب يخلص');

    await StockRepository(h.db).setQuantity(id, 8); // ٤ أيام
    await settle(tester);
    expect(find.text('Concor 5mg فاضله ٤ أيام'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('refill-restock-$id')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('restock-save')));
    await settle(tester);
    expect(await quantity(id), 38, reason: 'البكرة بتستريح على ٣٠');
    await settle(tester);
    expect(find.byKey(ValueKey('refill-$id')), findsNothing, reason: 'بقى مش قرب يخلص');
    expectNoRedAndMinSize(tester);
  });

  screenTest('«اطلبه من الصيدلية»: الصيدلية الأول، وبعدها واتساب برسالة جاهزة — مفيش إرسال تلقائي', (tester) async {
    final opened = <Uri>[];
    final original = openWhatsApp;
    openWhatsApp = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openWhatsApp = original);
    SharedPreferences.setMockInitialValues({}); // رقم الاتصال بتاع «صيدليتي»
    final id = await seedConcor();
    await StockRepository(h.db).setQuantity(id, 2);
    await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));

    await tester.tap(find.byKey(ValueKey('refill-order-$id')));
    await settle(tester);
    // مفيش صيدلية متسجّلة → بنسأل عنها الأول
    await tester.enterText(find.byKey(const ValueKey('pharmacy-name')), 'صيدلية الشفا');
    await tester.enterText(find.byKey(const ValueKey('pharmacy-number')), '0101 234 5678');
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('pharmacy-save')));
    await tester.tap(find.byKey(const ValueKey('pharmacy-save')));
    await settle(tester);
    // الرقم بيتحفظ مطبّع (0035) — مسافات وشرط بتتشال
    expect(await PreferencesRepository(h.db).pharmacy(), (name: 'صيدلية الشفا', whatsapp: '01012345678', call: null));

    expect(find.text('محتاج Concor 5mg — ١ علبة'), findsOneWidget, reason: 'الرسالة قدّامه قبل ما يفتح');
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('order-open')));
    await settle(tester);
    expect(opened.single.host, 'wa.me');
    expect(opened.single.path, '/201012345678');
    expect(opened.single.queryParameters['text'], 'محتاج Concor 5mg — ١ علبة');
  });

  // «باقي كام قرص؟» كارت لوحده، والشريط جنب العلبة (طلب المالك، ٢٩ سبتمبر ٢٠٢٦)
  group('«باقي كام؟» والشريط', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<int> seedUnknown() => h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: 'Sirup X',
          timings: const [FixedTiming(MinuteOfDay.hm(9))],
          startDate: aug31,
        );

    screenTest('الجرعة ما بتقولش هو إيه: «ده إيه؟» الأول — مش بنفترض أقراص', (tester) async {
      final id = await seedUnknown();
      await h.pump(tester, EditMedicationScreen(medicationId: id));
      expect(find.text('باقي كام؟'), findsOneWidget);
      expect(find.text('ده إيه؟'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-wheel')), findsNothing, reason: 'مفيش عدّ قبل ما نعرف بيعدّ إيه');
      expect(find.textContaining('وحدة'), findsNothing, reason: '«وحدة» كانت اللي محدش فاهمها');

      await tester.tap(find.byKey(const ValueKey('stock-unit-ملعقة')));
      await settle(tester);
      expect(find.text('باقي كام ملعقة؟'), findsOneWidget);
      expect(await tester.runAsync(() => StockUnitStore.read(id)), 'ملعقة');
      expect(await quantity(id), isNull, reason: 'اختيار النوع مش رقم');
      expect(find.byKey(const ValueKey('stock-unit-change')), findsOneWidget);
    });

    screenTest('الشريط: «كام قرص في الشريط؟» — مقفول لحد ما البكرة تتحرك، وبيزوّد', (tester) async {
      final id = await seedConcor();
      await StockRepository(h.db).setQuantity(id, 20);
      await h.pump(tester, EditMedicationScreen(medicationId: id));
      await tester.ensureVisible(find.byKey(const ValueKey('stock-restock-strip')));
      await tester.tap(find.byKey(const ValueKey('stock-restock-strip')));
      await settle(tester);
      expect(find.text('اشتريت شريط'), findsNWidgets(2), reason: 'الزرار وعنوان الورقة');
      expect(find.text('كام قرص في الشريط من Concor 5mg؟'), findsOneWidget);
      final save = tester.widget<FilledButton>(
          find.descendant(of: find.byKey(const ValueKey('restock-save')), matching: find.byType(FilledButton)));
      expect(save.onPressed, isNull, reason: 'عدد الشريط مش بتاعنا');

      await tester.drag(find.byKey(const ValueKey('restock-wheel')), const Offset(0, -FNumberWheel.itemExtent * 2));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('restock-save')));
      await settle(tester);
      final q = await quantity(id);
      expect(q, greaterThan(20));
    });

    screenTest('«يومك»: «اشتريت شريط» للأقراص؛ الشراب مالوش شريط', (tester) async {
      final pills = await seedConcor();
      final syrup = await h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Sirup Y',
        amountLabel: 'معلقة كبيرة',
        timings: const [FixedTiming(MinuteOfDay.hm(9))],
        startDate: aug31,
      );
      await StockRepository(h.db).setQuantity(pills, 2);
      await StockRepository(h.db).setQuantity(syrup, 1);
      await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));
      expect(find.byKey(ValueKey('refill-strip-$pills')), findsOneWidget);
      expect(find.byKey(ValueKey('refill-strip-$syrup')), findsNothing);
    });

    screenTest('«اطلبه من الصيدلية» للأقراص: «علبة ولا شريط؟» والرسالة بالشريط', (tester) async {
      final opened = <Uri>[];
      final original = openWhatsApp;
      openWhatsApp = (uri) async {
        opened.add(uri);
        return true;
      };
      addTearDown(() => openWhatsApp = original);
      final id = await seedConcor();
      await StockRepository(h.db).setQuantity(id, 2);
      await PreferencesRepository(h.db).setPharmacy(name: 'صيدلية الشفا', whatsapp: '01012345678');
      await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));

      await tester.tap(find.byKey(ValueKey('refill-order-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('order-pack-strip')));
      await settle(tester);
      expect(find.text('محتاج Concor 5mg — ١ شريط'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-open')));
      await settle(tester);
      expect(opened.single.queryParameters['text'], 'محتاج Concor 5mg — ١ شريط');
    });
  });

  test('الكلام: الشريط والعلبة بالعدد، والسؤال بوحدته', () {
    expect(packCount(1, StockPack.strip), '١ شريط');
    expect(packCount(2, StockPack.strip), 'شريطين');
    expect(packCount(3, StockPack.strip), '٣ شرايط');
    expect(packCount(12, StockPack.strip), '١٢ شريط');
    expect(packCount(2, StockPack.box), 'علبتين');
    expect(stockLeftQuestion('قرص'), 'باقي كام قرص؟');
    expect(stockLeftQuestion('نقط'), 'باقي كام نقطة؟');
    expect(resolveStockUnit(null), isNull, reason: 'مش بنفترض أقراص');
    expect(resolveStockUnit('', chosen: 'كبسولة'), 'كبسولة');
    expect(resolveStockUnit('قرص واحد', chosen: 'ملعقة'), 'قرص', reason: 'الجرعة بتغلب');
    expect(stripAllowed('قرص'), isTrue);
    expect(stripAllowed('ملعقة'), isFalse);
    expect(stripAllowed(null), isFalse);
  });
}
