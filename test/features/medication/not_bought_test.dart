import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/data/repositories/not_bought_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/domain/medication/stock.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/not_bought.dart';
import 'package:fakkarni/features/medication/refill_actions.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import '../scan/scan_test_support.dart';

/// «أدوية لسه ماتشترتش»: «أيوه» افتراضياً، «لسه» بتحطّه في القايمة،
/// «اشتريته» بتشيله — **والتذكير واحد في الحالتين**.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final secondLine = ReadLine(
    name: ok('Glucophage 500'),
    amount: ok('قرص'),
    timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
    duration: const ReadField(value: null, confidence: 1),
  );

  Future<void> pumpReview(WidgetTester tester) async {
    await h.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ReviewPrescriptionScreen(
                  reading: PrescriptionReading(
                    doctor: const ReadField(value: null, confidence: 1),
                    lines: [clearLine, secondLine],
                  ),
                  routine: normalDay,
                  today: aug31,
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('confirm-review'));
    await tester.ensureVisible(button);
    await tester.tap(find.descendant(of: button, matching: find.byType(FilledButton)));
    await settle(tester);
  }

  Map<int, String> scheduled() => {
        for (final n in h.sink.scheduled.values) n.id: '${n.at.toIso8601String()}|${n.title}|${n.body}',
      };

  screenTest('من غير ما يرد على «اشتريته؟» → أيوه، ومفيش حاجة في القايمة', (tester) async {
    await pumpReview(tester);
    expect(find.text('اشتريته؟'), findsNWidgets(2));
    await confirm(tester);
    expect(await NotBoughtRepository(h.db).all(h.services.patientId), isEmpty);
  });

  screenTest('«لسه» → في القايمة — والتذكيرات **هي هي** بالظبط زي «أيوه»', (tester) async {
    await pumpReview(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('bought-no-0')));
    await tester.tap(find.byKey(const ValueKey('bought-no-0')));
    await settle(tester);
    expect(find.textContaining('والتذكير بيبدأ في ميعاده عادي'), findsOneWidget);
    await confirm(tester);

    final notBought = await NotBoughtRepository(h.db).all(h.services.patientId);
    expect([for (final m in notBought) m.name], ['Concor 5mg']);
    final withNotBought = scheduled();
    expect(withNotBought, isNotEmpty);

    // نفس القاعدة بعد «اشتريته» — الجدولة لازم تطلع نفس الأرقام والأوقات والكلام
    await NotBoughtRepository(h.db).markBought(notBought.single.id);
    h.sink.scheduled.clear();
    await h.services.scheduler.rescheduleAll();
    expect(scheduled(), withNotBought, reason: '«لسه ماتشترتش» ما بتغيّرش ولا تذكير');

    // والدوا اللي لسه ماتشتراش ليه تذكيراته فعلاً (مش متأجّل)
    final concor = (await h.meds.activeSchedules(h.services.patientId))
        .where((s) => s.medicationName == 'Concor 5mg');
    expect(concor, isNotEmpty);
  });

  screenTest('القايمة: «اشتريته» بتشيله، و«اطلبها من الصيدلية» بتفتح واتساب برسالة كلهم', (tester) async {
    final opened = <Uri>[];
    final original = openWhatsApp;
    openWhatsApp = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openWhatsApp = original);
    await PreferencesRepository(h.db).setPharmacy(name: 'صيدلية الشفا', whatsapp: '01012345678');
    final a = await h.meds.addMedication(
        patientId: h.services.patientId, name: 'Concor', timing: const AnchorTiming(DayAnchor.breakfast, 0), startDate: aug31);
    final b = await h.meds.addMedication(
        patientId: h.services.patientId, name: 'Glucophage', timing: const AnchorTiming(DayAnchor.dinner, 0), startDate: aug31);
    await NotBoughtRepository(h.db).markNotBought(a);
    await NotBoughtRepository(h.db).markNotBought(b);

    await h.pump(tester, const Scaffold(body: SingleChildScrollView(child: Column(children: [NotBoughtLine(), NotBoughtSection()]))));
    expect(find.text('فيه دوايين لسه ماتشتروش'), findsOneWidget);
    expect(find.textContaining('أدوية لسه ماتشترتش'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('not-bought-order')));
    await settle(tester);
    expect(find.text('محتاج:\n- Concor — ١ علبة\n- Glucophage — ١ علبة'), findsOneWidget, reason: 'الرسالة قدّامه قبل ما يبعت');
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('order-list-open')));
    await settle(tester);
    expect(opened.single.path, '/201012345678');
    expect(opened.single.queryParameters['text'], 'محتاج:\n- Concor — ١ علبة\n- Glucophage — ١ علبة');

    await tester.tap(find.byKey(ValueKey('not-bought-done-$a')));
    await settle(tester);
    expect([for (final m in await NotBoughtRepository(h.db).all(h.services.patientId)) m.name], ['Glucophage']);
    expect(find.text('Glucophage لسه ماتشترتش'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('القايمة فاضية → لا سطر ولا قسم', (tester) async {
    await h.pump(tester, const Scaffold(body: Column(children: [NotBoughtLine(), NotBoughtSection()])));
    expect(find.byKey(const ValueKey('not-bought-line')), findsNothing);
    expect(find.byKey(const ValueKey('not-bought-section')), findsNothing);
  });

  test('رسالة الصيدلية: دوا واحد زي رسالة المخزون، وأكتر = سطر لكل دوا', () {
    expect(pharmacyListMessage(['Concor']), 'محتاج Concor — ١ علبة');
    expect(pharmacyListMessage(['A', 'B']), 'محتاج:\n- A — ١ علبة\n- B — ١ علبة');
    expect(notBoughtLineText(['A']), 'A لسه ماتشترتش');
    expect(notBoughtLineText(['A', 'B', 'C']), 'فيه ٣ أدوية لسه ماتشتروش');
  });
}
