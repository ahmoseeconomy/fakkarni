import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // الشاشة بقت أطول من ٦٠٠ بكسل — نكبّر النافذة بدل السكرول
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  screenTest('صف المريض بيترفع الأول وبعده الكود — بأرقام عربي ٣-٣، والشرح بالبساطة', (tester) async {
    await pumpCode(tester);

    expect(care.upserts, [(uuid: 'p-uuid-1', name: 'الحاج أحمد')]);
    expect(care.createdFor, ['p-uuid-1']);

    // «١٢٣ ٤٥١» — عربي زي باقي التطبيق، ومجمّعة ٣-٣
    expect(find.text('١٢٣ ٤٥١'), findsOneWidget);
    final code = tester.widget<Text>(find.text('١٢٣ ٤٥١'));
    expect(code.style?.fontSize, greaterThanOrEqualTo(48), reason: 'بيتقري عبر أوضة');
    expect(find.text('دائرة الرعاية'), findsOneWidget);
    expect(find.textContaining('يشوف أدويتك ومواعيدك'), findsOneWidget);
    expect(find.textContaining('صالح ١٥ دقيقة'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«انسخ الكود» بتنسخ الأرقام الغربية — اللي كيبورد الابن بيكتبها', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpCode(tester);

    final copy = find.widgetWithText(OutlinedButton, 'انسخ الكود');
    expect(copy, findsOneWidget);
    expect(tester.getSize(copy).height, F.minTapTarget);
    await tester.tap(copy);
    await settle(tester);

    expect(copied, '123451');
    expect(find.textContaining('اتنسخ'), findsOneWidget);
  });

  screenTest('«ابعته» بكلمة، وبتسلّم رسالة فيها الكود لورقة المشاركة لو موجودة', (tester) async {
    String? shared;
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LinkCodeScreen(
            care: care,
            patientUuid: 'p-uuid-1',
            patientName: 'الحاج أحمد',
            share: (text) async => shared = text,
          ),
        ),
      ),
    );
    await settle(tester);

    final send = find.widgetWithText(OutlinedButton, 'ابعته');
    expect(send, findsOneWidget);
    expect(find.byIcon(Icons.send_outlined), findsOneWidget, reason: 'أيقونة وكلمة');
    await tester.tap(send);
    await settle(tester);

    expect(shared, contains('123451'));
    expect(shared, contains('عندي كود'));
  });

  screenTest('«كود جديد» ٦٤ وبيجيب كوداً مختلفاً', (tester) async {
    await pumpCode(tester);

    expect(tester.getSize(find.widgetWithText(FilledButton, 'كود جديد')).height,
        F.primaryButtonHeight);

    await tester.tap(find.text('كود جديد'));
    await settle(tester);

    expect(find.text('١٢٣ ٤٥٢'), findsOneWidget);
    expect(find.text('١٢٣ ٤٥١'), findsNothing);
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
