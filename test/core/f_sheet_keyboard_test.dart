// الكيبورد كان بيغطّي الشيت.
//
// تعديل الدكتور أو العيادة في شاشة المراجعة بيفتح شيت فيه حقل واحد
// و«احفظ». الشيت كان بيتبني على ارتفاعه الطبيعي والكيبورد بيطلع **فوقه**:
// الراجل بيكتب وهو مش شايف الحروف، و«احفظ» بيبقى تحت الكيبورد فمفيش طريق
// يحفظ بيه غير إنه يقفل الكيبورد الأول — ولا حاجة على الشاشة بتقول كده.
//
// الإصلاح في `FSheet` نفسها عشان يشمل كل شيت، فالاختبار هنا على الأداة
// مش على شاشة واحدة. الشرط: الحقل والزرار الاتنين **فوق** الكيبورد
// وبيتلمسوا فعلاً — مش «موجودين في الشجرة».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_sheet.dart';
import 'package:fakkarni/core/widgets/primitives.dart';

/// شاشة قصيرة: أقصر من أي تليفون حقيقي عشان الضغط يبان.
const _screen = Size(400, 600);
const _keyboard = 336.0;

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required List<Widget> children,
  }) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => FSheet.show<void>(context, title: 'الدكتور', children: children),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    // الكيبورد طلع
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pumpAndSettle();
  }

  /// فوق الكيبورد فعلاً، بالبكسل.
  void expectAboveKeyboard(WidgetTester tester, Finder f, String what) {
    final rect = tester.getRect(f);
    expect(
      rect.bottom,
      lessThanOrEqualTo(_screen.height - _keyboard),
      reason: '$what تحت الكيبورد — آخره ${rect.bottom} والكيبورد بيبدأ من '
          '${_screen.height - _keyboard}',
    );
  }

  testWidgets('شيت بحقل كتابة: الحقل و«احفظ» فوق الكيبورد وبيتلمسوا', (tester) async {
    var saved = false;
    await openSheet(tester, children: [
      const TextField(key: ValueKey('field'), style: TextStyle(fontSize: F.minBodySize)),
      FPrimaryButton(label: 'احفظ', onPressed: () => saved = true),
    ]);

    expectAboveKeyboard(tester, find.byKey(const ValueKey('field')), 'الحقل');
    expectAboveKeyboard(tester, find.text('احفظ'), 'زرار الحفظ');

    // بيتكتب فيه وبيتقرا
    await tester.enterText(find.byKey(const ValueKey('field')), 'د. هشام مام');
    await tester.pump();
    expect(find.text('د. هشام مام'), findsOneWidget);

    // والدوسة بتوصل — مش مغطّى بحاجة
    await tester.tap(find.text('احفظ'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });

  testWidgets('شيت أطول من المساحة الفاضلة بيتزحلق بدل ما يتقص', (tester) async {
    var saved = false;
    await openSheet(tester, children: [
      for (var i = 0; i < 6; i++)
        Container(height: F.minTapTarget, color: F.railGround, child: Text('سطر $i')),
      const TextField(key: ValueKey('field'), style: TextStyle(fontSize: F.minBodySize)),
      FPrimaryButton(label: 'احفظ', onPressed: () => saved = true),
    ]);

    // موجود، ومحتاج زحلقة — دي الحالة اللي كانت بتضيع
    expect(find.byType(Scrollable).hitTestable(), findsWidgets);
    await tester.ensureVisible(find.text('احفظ'));
    await tester.pumpAndSettle();

    expectAboveKeyboard(tester, find.text('احفظ'), 'زرار الحفظ بعد الزحلقة');
    await tester.tap(find.text('احفظ'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
  });
}
