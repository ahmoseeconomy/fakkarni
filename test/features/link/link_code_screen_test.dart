import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/features/link/link_code_screen.dart';

import '../../data/care/care_circle_service_test.dart' show FakeCareCircleService;
import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

void main() {
  late FakeCareCircleService care;

  setUp(() => care = FakeCareCircleService());

  Future<void> pumpCode(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LinkCodeScreen(
            care: care,
            patientUuid: 'p-uuid-1',
            patientName: 'الحاج أحمد',
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('صف المريض بيترفع الأول وبعده الكود — بأرقام غربية ٣-٣', (tester) async {
    await pumpCode(tester);

    expect(care.upserts, [(uuid: 'p-uuid-1', name: 'الحاج أحمد')]);
    expect(care.createdFor, ['p-uuid-1']);

    // «123 451» — غربية زي ما كيبورد الابن هيكتبها، ومجمّعة ٣-٣
    expect(find.text('123 451'), findsOneWidget);
    final code = tester.widget<Text>(find.text('123 451'));
    expect(code.style?.fontSize, greaterThanOrEqualTo(48), reason: 'بيتقري عبر أوضة');
    expect(code.textDirection, TextDirection.ltr);
    expect(find.text('الكود صالح ١٥ دقيقة'), findsOneWidget);
  });

  screenTest('«كود جديد» ٦٤ وبيجيب كوداً مختلفاً', (tester) async {
    await pumpCode(tester);

    expect(tester.getSize(find.widgetWithText(FilledButton, 'كود جديد')).height,
        F.primaryButtonHeight);

    await tester.tap(find.text('كود جديد'));
    await settle(tester);

    expect(find.text('123 452'), findsOneWidget);
    expect(find.text('123 451'), findsNothing);
    expect(care.createdFor.length, 2);
  });

  screenTest('أوفلاين → الجملة المتفق عليها، من غير أحمر', (tester) async {
    care.nextFailure = const CareCircleException(CareCircleFailure.offline);
    await pumpCode(tester);

    expect(
      find.text('مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      findsOneWidget,
    );
    expectNoRedAndMinSize(tester);
  });
}
