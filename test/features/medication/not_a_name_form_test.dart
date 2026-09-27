// «ضيف دوا … لا» فتح الفورم متعبّي بـ«لا» و«احفظ» شغّال — كده اتعمل دوا اسمه «لا».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/features/medication/add_medication_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  FilledButton save(WidgetTester tester) => tester.widget<FilledButton>(find.descendant(
      of: find.byKey(const ValueKey('save-medication')), matching: find.byType(FilledButton)));

  screenTest('اسم متعبّي «لا» → الحقل فاضي و«احفظ» مقفول', (tester) async {
    await h.pump(tester, AddMedicationScreen(initialName: 'لا'));
    expect(find.widgetWithText(TextField, 'لا'), findsNothing);
    expect(save(tester).onPressed, isNull);
  });

  screenTest('كتب «أيوه» بإيده → «ده مش اسم دوا» و«احفظ» مقفول؛ الاسم الحقيقي بيفتحه', (tester) async {
    await h.pump(tester, AddMedicationScreen());
    // الساعة متختارة — فالمانع الوحيد الباقي هو الاسم
    await tester.tap(find.byKey(ValueKey('quick-time-${9 * 60}')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'أيوه');
    await settle(tester);
    expect(find.byKey(const ValueKey('not-a-name')), findsOneWidget);
    expect(save(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, 'Concor 5mg');
    await settle(tester);
    expect(find.byKey(const ValueKey('not-a-name')), findsNothing);
    expect(save(tester).onPressed, isNotNull);
  });
}
