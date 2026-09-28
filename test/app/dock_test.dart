// الدوك (المالك، ٢٨ سبتمبر ٢٠٢٦): «ضيف» جوّه الدوك مش طالع فوقه، «ملفّي»،
// الدهبي بالليل، واللي بيتزحلق تحته ما يتقريش.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';

import '../features/scan/scan_test_support.dart';
import '../support/contrast_audit.dart';

void main() {
  final h = Harness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.setUp();
  });
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  Future<void> pumpShell(WidgetTester tester, {double scale = 1.0, Size size = const Size(375, 667)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppScope(
      services: h.services,
      child: MaterialApp(
        theme: F.light,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: AppShell(now: DateTime(2026, 8, 31, 10)),
      ),
    ));
    await settle(tester);
  }

  Rect dockRect(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('dock-blur')));

  for (final scale in [1.0, 1.3]) {
    screenTest('«ضيف» جوّه الدوك (×$scale): حافة الدايرة اللي فوق على حافة الدوك بالظبط — وكلمته جوّاه', (tester) async {
      await pumpShell(tester, scale: scale);
      final dock = dockRect(tester);
      final circle = tester.getRect(find.byType(FloatingActionButton));
      expect(circle.top, closeTo(dock.top, 0.5), reason: 'مش طالع فوق الدوك');
      expect(circle.height, 62, reason: 'نفس المقاس');
      final label = tester.getRect(find.text('ضيف'));
      expect(label.bottom, lessThanOrEqualTo(dock.bottom + 0.5), reason: 'الكلمة جوّه الدوك');
      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect((fab.shape as RoundedRectangleBorder).side.color, F.gold, reason: 'الحلقة الدهبي زي ما هي');
    });
  }

  // ×١٫٣ هو أكبر خط بيتجرّب عليه التطبيق كله (اختبارات SE)
  for (final scale in [1.0, 1.3]) {
    screenTest('الكلمات على ٣٧٥ (×$scale): «ملفّي» وكل تبويب سطر واحد جوّه الدوك من غير قصّ', (tester) async {
      await pumpShell(tester, scale: scale);
      final dock = dockRect(tester);
      expect(find.text('ملفّي'), findsWidgets);
      expect(find.text('الملف الطبي'), findsNothing);
      for (final tab in AppShell.tabs) {
        final text = find.text(tab).last;
        final r = tester.getRect(text);
        expect(r.left, greaterThanOrEqualTo(dock.left), reason: tab);
        expect(r.right, lessThanOrEqualTo(dock.right), reason: tab);
        expect(r.bottom, lessThanOrEqualTo(dock.bottom + 0.5), reason: tab);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$tab اتقص');
        expect(tester.widget<Text>(text).maxLines, 1, reason: '$tab سطر واحد');
      }
      expect(tester.takeException(), isNull);
    });
  }

  screenTest('عنوان الشاشة زي اسم التبويب — «ملفّي»', (tester) async {
    await pumpShell(tester, size: const Size(1000, 2000));
    await tester.tap(find.text('ملفّي').last);
    await settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('ملفّي')), findsOneWidget);
  });

  screenTest('اللي تحت الدوك ما يتقريش: ضباب ٢٠ وفوق، صبغة شبه مصمتة، وتلاشي فوقه', (tester) async {
    await pumpShell(tester);
    final blur = tester.widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')));
    expect(blur.filter, ImageFilter.blur(sigmaX: 24, sigmaY: 24));
    final glass = tester.widget<Container>(
      find.descendant(of: find.byKey(const ValueKey('dock-blur')), matching: find.byType(Container)).first,
    );
    expect((glass.decoration! as BoxDecoration).color!.a, greaterThanOrEqualTo(0.85));
    final ground = tester.widget<ColoredBox>(find.byKey(const ValueKey('dock-ground')));
    expect(ground.color.a, greaterThanOrEqualTo(0.9), reason: 'حوالين الدوك وتحته كمان');
    final fade = tester.getRect(find.byKey(const ValueKey('dock-fade')));
    expect(fade.bottom, closeTo(dockRect(tester).top, 0.5), reason: 'التلاشي لازق فوق الدوك');
    final gradient = (tester.widget<Container>(find.byKey(const ValueKey('dock-fade'))).decoration! as BoxDecoration).gradient!
        as LinearGradient;
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last.a, greaterThanOrEqualTo(0.9));
  });

  screenTest('بالليل: اللي إنت فيه دهبي — نفس دهب حلقة «ضيف»', (tester) async {
    F.setDark(on: true);
    await pumpShell(tester);
    final selected = tester.widget<Text>(find.text('اليوم').last);
    expect(selected.style!.color, F.gold);
    expect(tester.widget<Text>(find.text('ضيف')).style!.color, F.gold);
    final tileIcon = tester.widget<Icon>(find.byIcon(Icons.today_outlined));
    expect(tileIcon.color, F.onGold, reason: 'حبر على البلاطة الدهبي');
    expect(tester.widget<Icon>(find.byIcon(Icons.medication_outlined)).color, F.gold, reason: 'أيقونات الدوك دهبي');
  });

  screenTest('بالنهار زي ما هو — أخضر', (tester) async {
    await pumpShell(tester);
    expect(tester.widget<Text>(find.text('اليوم').last).style!.color, F.green);
    expect(tester.widget<Icon>(find.byIcon(Icons.medication_outlined)).color, F.mutedDark);
  });

  for (final dark in [false, true]) {
    screenTest('${dark ? 'ليلي' : 'نهاري'} — كل كلمة في الدوك بتتقري', (tester) async {
      F.setDark(on: dark);
      await pumpShell(tester);
      expectReadableText(tester, where: 'الدوك');
    });
  }
}
