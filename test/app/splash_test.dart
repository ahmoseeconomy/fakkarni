// البداية كانت بتعدّي في رمشة.
//
// الحركة كانت ٢.٧٥ ث وبعدها ٠.٢٥ ث بس قبل التلاشي، وعلى فتحة حقيقية
// التطبيق بيبقى جاهز قبل ما العين تستقر: العلامة بتتجمّع والكلمة بتطلع
// والطبقة بتروح كلها على بعض. اللي بيفتح التطبيق أول مرة مش بيشوف
// علامته أصلاً.
//
// الاختبار ده على **الوقفة**: بعد ما الكلمة تستقر، لازم يعدّي وقت
// محسوس من غير ولا حركة قبل ما التلاشي يبدأ. بيتقاس من الرسّام نفسه —
// نفس القيم في لحظتين بعيدين عن بعض يعني العلامة واقفة فعلاً، مش
// «الاختبار صابر».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/splash.dart';
import 'package:fakkarni/core/widgets/fa_mark.dart';

void main() {
  /// الرسّام اللي على الشاشة دلوقتي.
  FaMarkPainter markOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<FaMarkPainter>()
      .single;

  /// كل اللي بيتحرّك في العلامة، في سطر واحد يتقارن.
  List<double> frameOf(FaMarkPainter p) =>
      [p.bowlProgress, p.tailProgress, p.dotOpacity, p.dotSlide, p.dotDrop, p.dotFlash, p.halo];

  testWidgets('العلامة بتقف ثابتة قبل التلاشي — مش بتروح في رمشة', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();

    // ٣.٩ ث: الكلمة استقرت (٣.٨٥) والتلاشي لسه ما بدأش (٥.٠٥)
    await tester.pump(const Duration(milliseconds: 3900));
    final settled = frameOf(markOf(tester));
    final word = tester.widget<Opacity>(
      find.ancestor(of: find.text('فكرني'), matching: find.byType(Opacity)).first,
    );
    expect(word.opacity, 1.0, reason: 'الكلمة كاملة قبل الوقفة');

    // كمان ثانية جوّه الوقفة — ولا حاجة اتحرّكت
    await tester.pump(const Duration(milliseconds: 1000));
    expect(frameOf(markOf(tester)), settled, reason: 'العلامة اتحرّكت في وقت المفروض واقفة فيه');
    expect(find.text('فكرني'), findsOneWidget);

    // والطبقة لسه كاملة الظهور — التلاشي ما بدأش
    final layer = tester.widgetList<Opacity>(find.byType(Opacity)).first;
    expect(layer.opacity, 1.0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('الوقفة مش أقل من ثانية — والحركة كلها خلصت قبلها', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();

    // أول ما الحركة تخلص
    await tester.pump(const Duration(milliseconds: 3850));
    final atRestStart = frameOf(markOf(tester));

    // وآخر لحظة قبل التلاشي
    await tester.pump(const Duration(milliseconds: 1190));
    expect(frameOf(markOf(tester)), atRestStart);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
