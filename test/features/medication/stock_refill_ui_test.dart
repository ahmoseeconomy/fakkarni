import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
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
        timings: const [AnchorTiming(DayAnchor.breakfast, -30), AnchorTiming(DayAnchor.dinner, 0)],
        startDate: aug31,
      );

  Future<double?> quantity(int id) async => (await StockRepository(h.db).rowFor(id))?.quantity;

  screenTest('صفحة الدوا: المخزون فاضي لحد ما البكرة تتحرك، و«تمام» بتكتبه', (tester) async {
    final id = await seedConcor();
    await h.pump(tester, EditMedicationScreen(medicationId: id));

    expect(find.text('عندك كام قرص دلوقتي؟'), findsOneWidget, reason: 'الوحدة من خانة الجرعة');
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
    final id = await seedConcor();
    await StockRepository(h.db).setQuantity(id, 2);
    await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: RefillLines())));

    await tester.tap(find.byKey(ValueKey('refill-order-$id')));
    await settle(tester);
    // مفيش صيدلية متسجّلة → بنسأل عنها الأول
    await tester.enterText(find.byKey(const ValueKey('pharmacy-name')), 'صيدلية الشفا');
    await tester.enterText(find.byKey(const ValueKey('pharmacy-number')), '0101 234 5678');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pharmacy-save')));
    await settle(tester);
    expect(await PreferencesRepository(h.db).pharmacy(), (name: 'صيدلية الشفا', whatsapp: '0101 234 5678'));

    expect(find.text('محتاج Concor 5mg — ١ علبة'), findsOneWidget, reason: 'الرسالة قدّامه قبل ما يفتح');
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('order-open')));
    await settle(tester);
    expect(opened.single.host, 'wa.me');
    expect(opened.single.path, '/201012345678');
    expect(opened.single.queryParameters['text'], 'محتاج Concor 5mg — ١ علبة');
  });
}
