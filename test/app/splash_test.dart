// البداية كانت بتعدّي في رمشة.
//
// الاختبارات تقفل على حاجتين: نفس الوقفة القصيرة بعد استقرار العلامة،
// ومن غير حد أدنى صناعي أطول من ميزانية فتح التطبيق محلياً.
import 'dart:io';

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
  List<double> frameOf(FaMarkPainter p) => [
    p.bowlProgress,
    p.tailProgress,
    p.dotOpacity,
    p.dotSlide,
    p.dotDrop,
    p.dotFlash,
    p.halo,
  ];

  testWidgets('العلامة بتقف ثابتة قبل التلاشي — مش بتروح في رمشة', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();

    // ١.٤ ث: الكلمة استقرت (١.٣٣) والتلاشي لسه ما بدأش (١.٧٥)
    await tester.pump(const Duration(milliseconds: 1400));
    final settled = frameOf(markOf(tester));
    final word = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('فكرني'), matching: find.byType(Opacity))
          .first,
    );
    expect(word.opacity, 1.0, reason: 'الكلمة كاملة قبل الوقفة');

    // كمان ٠.٣ ث جوّه الوقفة — ولا حاجة اتحرّكت
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      frameOf(markOf(tester)),
      settled,
      reason: 'العلامة اتحرّكت في وقت المفروض واقفة فيه',
    );
    expect(find.text('فكرني'), findsOneWidget);

    // والطبقة لسه كاملة الظهور — التلاشي ما بدأش
    final layer = tester.widgetList<Opacity>(find.byType(Opacity)).first;
    expect(layer.opacity, 1.0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('الوقفة قصيرة لكن الحركة كلها خلصت قبلها', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();

    // أول ما الحركة تخلص
    await tester.pump(const Duration(milliseconds: 1330));
    final atRestStart = frameOf(markOf(tester));

    // وآخر لحظة قبل التلاشي
    await tester.pump(const Duration(milliseconds: 400));
    expect(frameOf(markOf(tester)), atRestStart);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('مسار الـSplash لا يفرض انتظاراً اصطناعياً أطول من ثانيتين', () {
    expect(SplashOverlay.total, lessThanOrEqualTo(const Duration(seconds: 2)));
    expect(
      SplashOverlay.total,
      greaterThan(const Duration(milliseconds: 1500)),
    );

    final source = File('lib/app/splash.dart').readAsStringSync();
    expect(source, isNot(contains('Future.delayed')));
  });

  testWidgets('اسم فكرني أقرب للعلامة بـ١٤px من المسافة السابقة', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));

    final mark = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is FaMarkPainter,
    );
    final word = find.text('فكرني');
    expect(tester.getTopLeft(word).dy - tester.getBottomLeft(mark).dy, 8);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
