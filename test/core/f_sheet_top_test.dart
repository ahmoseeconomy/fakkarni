// الشيت الطويل كان بيطلع لحد شريط الحالة.
//
// «ميعاد جديد» (اليوم + الساعة بالبكرة) أطول من الشاشة على آيفون، و
// `showModalBottomSheet` بـ`isScrollControlled` من غير `useSafeArea` بيسيبه
// يكبر لحد أول الشاشة — فالعنوان بقى جنب الساعة تحت النوتش (طلب المالك،
// ٢٩ سبتمبر ٢٠٢٦). الإصلاح في `FSheet` نفسها عشان يشمل كل شيت: الشيت
// بيبدأ تحت شريط الحالة بمسافة، والحجاب باين فوقه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_sheet.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../features/scan/scan_test_support.dart';

/// آيفون ١٧ برو بالنقط: ٤٠٢×٨٧٤ وشريط حالة ٦٢.
const _phone = Size(402, 874);
const _statusBar = 62.0;

void setPhone(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: _statusBar, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void main() {
  testWidgets('شيت أطول من الشاشة بيبدأ تحت شريط الحالة بمسافة', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => FSheet.show<void>(
                  context,
                  title: 'طويل',
                  children: const [SizedBox(height: 3000)],
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(FSheet));
    expect(sheet.top, greaterThanOrEqualTo(_statusBar + F.s12),
        reason: 'الشيت فوق شريط الحالة — العنوان جنب الساعة');
    final title = tester.getRect(find.text('طويل'));
    expect(title.top, greaterThan(_statusBar + F.s12));
    // والجسم لسه بيتزحلق جوّاه، مش بيفيض
    expect(tester.takeException(), isNull);
  });

  testWidgets('شيت قصير زي ما هو: تحت خالص، على قد محتواه', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => FSheet.show<void>(context, title: 'قصير', children: const [SizedBox(height: 100)]),
            child: const Text('افتح'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(FSheet));
    expect(sheet.bottom, _phone.height);
    expect(sheet.height, lessThan(_phone.height / 2));
  });

  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  screenTest('«ميعاد جديد» الحقيقي بخط ×١٫٣: العنوان تحت شريط الحالة', (tester) async {
    await h.pump(tester, HealthFileScreen(today: DateTime(2026, 9, 29)));
    setPhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(tester);
    // ملخص الأسبوع فوق المواعيد (٤ أكتوبر ٢٠٢٦) — الزرار بقى تحت أول شاشة
    await tester.scrollUntilVisible(find.byKey(const ValueKey('new-appointment')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('new-appointment')));
    await settle(tester);

    final sheet = tester.getRect(find.byType(FSheet));
    expect(sheet.top, greaterThanOrEqualTo(_statusBar + F.s12));
    expect(tester.takeException(), isNull);
  });
}
