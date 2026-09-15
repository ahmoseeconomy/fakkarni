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

  screenTest('«اربط» مقفول لحد ٦ أرقام كاملة — والحقل أرقام بس', (tester) async {
    await pumpRedeem(tester);
    expect(linkButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '123');
    await tester.pumpAndSettle();
    expect(linkButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '12a456!');
    await tester.pumpAndSettle();
    expect(linkButton(tester).onPressed, isNull, reason: 'الحروف بتتشال والباقي ٥');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    expect(linkButton(tester).onPressed, isNotNull);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'اربط')).height,
        F.primaryButtonHeight);
  });

  screenTest('الأرقام العربي مقبولة — بتتطبّع لغربي قبل ما تروح للسيرفر', (tester) async {
    await pumpRedeem(tester);
    await tester.enterText(find.byType(TextField), '١٢٣٤٥٦');
    await settle(tester);
    expect(linkButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('اربط'));
    await settle(tester);
    expect(care.redeemed, ['123456']);
  });

  screenTest('كود صح → «اتربطت بـ…» باسم الأب', (tester) async {
    await pumpRedeem(tester);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    await tester.tap(find.text('اربط'));
    await settle(tester);

    expect(care.redeemed, ['123456']);
    expect(find.text('اتربطت بـالحاج أحمد'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  screenTest('كود غلط أو منتهي → الجملة بالذهبي، مش أحمر', (tester) async {
    care.nextFailure =
        const CareCircleException(CareCircleFailure.invalidOrExpiredCode);
    await pumpRedeem(tester);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('اربط'));
    await settle(tester);

    final error = tester.widget<Text>(find.text('الكود مش مضبوط أو خلّص وقته'));
    // ذهبي على الحافة، والنص غامق يتقري (الذهبي كنص ≈ ١.٩:١)
    expect(error.style?.color, F.ink);
    expect(find.ancestor(of: find.text('الكود مش مضبوط أو خلّص وقته'), matching: find.byType(GoldNote)), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('أوفلاين ومربوطين خلاص — رسايلهم المحددة', (tester) async {
    await pumpRedeem(tester);
    for (final (failure, message) in [
      (CareCircleFailure.offline, 'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      (CareCircleFailure.alreadyLinked, 'انتو مربوطين خلاص. كله تمام.'),
    ]) {
      care.nextFailure = CareCircleException(failure);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      await tester.tap(find.text('اربط'));
      await settle(tester);
      expect(find.text(message), findsOneWidget);
    }
  });
}
