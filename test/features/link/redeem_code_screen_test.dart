import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/features/link/redeem_code_screen.dart';

import '../../data/care/care_circle_service_test.dart' show FakeCareCircleService;
import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

void main() {
  late FakeCareCircleService care;

  setUp(() => care = FakeCareCircleService());

  Future<void> pumpRedeem(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RedeemCodeScreen(care: care),
        ),
      ),
    );
    await settle(tester);
  }

  FilledButton linkButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'اربط'));

  final field = find.byKey(const ValueKey('code-field'));
  String box(WidgetTester tester, int i) =>
      tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('code-box-$i')), matching: find.byType(Text))).data!;

  screenTest('ست خانات: «اربط» مقفول لحد السادس، والحروف بتتشال', (tester) async {
    await pumpRedeem(tester);
    expect(linkButton(tester).onPressed, isNull);
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey('code-box-$i')), findsOneWidget);
    }

    await tester.enterText(field, '123');
    await settle(tester);
    expect(linkButton(tester).onPressed, isNull);
    expect([for (var i = 0; i < 6; i++) box(tester, i)], ['١', '٢', '٣', '', '', '']);

    await tester.enterText(field, '12a45!');
    await settle(tester);
    expect(linkButton(tester).onPressed, isNull, reason: 'الحروف بتتشال والباقي ٤');
    expect(care.redeemed, isEmpty);
  });

  screenTest('الأرقام من الشمال لليمين حتى في الواجهة العربية', (tester) async {
    await pumpRedeem(tester);
    await tester.enterText(field, '12');
    await settle(tester);
    final first = tester.getCenter(find.byKey(const ValueKey('code-box-0')));
    final last = tester.getCenter(find.byKey(const ValueKey('code-box-5')));
    expect(first.dx, lessThan(last.dx), reason: 'الخانة الأولى على الشمال');
    expect(box(tester, 0), '١');
  });

  screenTest('المسح بيرجع خانة لورا', (tester) async {
    await pumpRedeem(tester);
    await tester.enterText(field, '1234');
    await settle(tester);
    await tester.enterText(field, '123');
    await settle(tester);
    expect([for (var i = 0; i < 6; i++) box(tester, i)], ['١', '٢', '٣', '', '', '']);
  });

  screenTest('الرقم السادس بيربط لوحده — والأرقام العربي بتتطبّع لغربي', (tester) async {
    await pumpRedeem(tester);
    await tester.enterText(field, '١٢٣٤٥٦');
    await settle(tester);
    expect(care.redeemed, ['123456']);
    expect(find.text('اتربطت بـالحاج أحمد'), findsOneWidget);
    expect(field, findsNothing);
  });

  screenTest('لصق ٦ أرقام (بمسافات أو من رسالة) بيملا الست ويربط', (tester) async {
    await pumpRedeem(tester);
    await tester.enterText(field, 'الكود: 654 321');
    await settle(tester);
    expect(care.redeemed, ['654321']);
  });

  screenTest('كود غلط → الجملة بالذهبي، والزرار فاضل يحاول تاني', (tester) async {
    care.nextFailure = const CareCircleException(CareCircleFailure.invalidOrExpiredCode);
    await pumpRedeem(tester);
    await tester.enterText(field, '000000');
    await settle(tester);

    final error = tester.widget<Text>(find.text('الكود مش مضبوط أو خلّص وقته'));
    expect(error.style?.color, F.ink);
    expect(find.ancestor(of: find.text('الكود مش مضبوط أو خلّص وقته'), matching: find.byType(GoldNote)), findsOneWidget);
    expect(linkButton(tester).onPressed, isNotNull);
    expectNoRedAndMinSize(tester);
  });

  screenTest('أوفلاين ومربوطين خلاص — رسايلهم المحددة', (tester) async {
    await pumpRedeem(tester);
    for (final (failure, message) in [
      (CareCircleFailure.offline, 'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      (CareCircleFailure.alreadyLinked, 'انتو مربوطين خلاص. كله تمام.'),
    ]) {
      care.nextFailure = CareCircleException(failure);
      await tester.enterText(field, '123456');
      await settle(tester);
      if (find.text(message).evaluate().isEmpty) {
        await tester.tap(find.text('اربط'));
        await settle(tester);
      }
      expect(find.text(message), findsOneWidget);
    }
  });

  screenTest('آيفون SE بخط ×١٫٣: الست خانات جوّه الشاشة من غير فيض', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpRedeem(tester);
    await tester.enterText(field, '12345');
    await settle(tester);
    expect(tester.takeException(), isNull);
    final right = tester.getRect(find.byKey(const ValueKey('code-box-5'))).right;
    final left = tester.getRect(find.byKey(const ValueKey('code-box-0'))).left;
    expect(left, greaterThanOrEqualTo(0));
    expect(right, lessThanOrEqualTo(375));
  });
}
