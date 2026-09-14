import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/splash.dart';
import 'package:fakkarni/core/format/name_direction.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/fa_mark.dart';
import 'package:fakkarni/core/widgets/primitives.dart';

void main() {
  group('الخطوط متحزّمة — مش بتتحمّل وقت التشغيل', () {
    test('كل ملف معلن في pubspec موجود فعلاً في assets/fonts', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets = RegExp(r'asset:\s*(assets/fonts/\S+)')
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .toList();
      expect(assets.length, 8, reason: 'Alexandria ٢ + Plex Sans Arabic ٤ + Plex Mono ٢');
      for (final path in assets) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(File(path).lengthSync(), greaterThan(50000), reason: '$path مش فاضي');
      }
    });

    test('Alexandria الاتنين static — وزن ٥٠٠ و٧٠٠ ملفّين مختلفين', () {
      // ملف variable واحد كان هيخلّي Bold = Medium على الجهاز
      final medium = File('assets/fonts/Alexandria-Medium.ttf').readAsBytesSync();
      final bold = File('assets/fonts/Alexandria-Bold.ttf').readAsBytesSync();
      expect(medium, isNot(equals(bold)));
      // جدول fvar هو علامة الخط المتغيّر — مش موجود في أي منهم
      for (final bytes in [medium, bold]) {
        final head = String.fromCharCodes(bytes.take(4096));
        expect(head.contains('fvar'), isFalse, reason: 'static مش variable');
      }
    });

    test('العائلات في الثيم هي هي اللي في pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final family in [F.displayFamily, F.bodyFamily, F.monoFamily]) {
        expect(pubspec.contains('family: $family'), isTrue, reason: family);
      }
      expect(F.light.textTheme.bodyLarge?.fontFamily ?? F.light.typography.black.bodyLarge?.fontFamily,
          anyOf(F.bodyFamily, isNull));
      expect(F.light.appBarTheme.titleTextStyle?.fontFamily, F.displayFamily);
      expect(F.monoFallback.first, F.bodyFamily, reason: 'mono من غير عربي محتاج بديل عربي');
    });
  });

  group('التوكنز', () {
    test('أرضية الصفحة عاجي، ومفيش نص في البدائيات أقل من ١٧', () {
      expect(F.light.scaffoldBackgroundColor, F.ivory);
      expect(F.minTextSize, 17.0);
      expect(F.kicker1, lessThan(F.minTextSize), reason: 'سلّم التصميم مسجّل...');
    });
  });

  testWidgets('البدائيات: كل نص ≥ ١٧، الأهداف ≥ ٥٦، الأساسي ٦٤، والذهبي للنشط بس', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ListView(
              children: [
                const Kicker('مراجعة وتأكيد'),
                const SectionHead('قسم'),
                FCard(child: const Text('كارت')),
                FPrimaryButton(label: 'احفظ', onPressed: () {}),
                FSecondaryButton(label: 'رجوع', onPressed: () {}),
                AnchorChip(label: 'قبل الفطار', selected: true, onTap: () {}),
                AnchorChip(label: 'بعد الفطار', selected: false, onTap: () {}),
                const StatusChip(label: 'اتاخد', tone: StatusTone.ok),
                FSwitch(label: 'وضع رمضان', value: true, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
    }
    expect(tester.getSize(find.byType(FilledButton)).height, F.primaryButtonHeight);
    expect(tester.getSize(find.byType(OutlinedButton)).height, F.minTapTarget);
    expect(tester.getSize(find.widgetWithText(AnchorChip, 'قبل الفطار')).height, F.minTapTarget);

    final selected = tester.widget<Material>(
      find.descendant(of: find.widgetWithText(AnchorChip, 'قبل الفطار'), matching: find.byType(Material)).first,
    );
    final unselected = tester.widget<Material>(
      find.descendant(of: find.widgetWithText(AnchorChip, 'بعد الفطار'), matching: find.byType(Material)).first,
    );
    expect(selected.color, F.gold);
    expect(unselected.color, isNot(F.gold));
    expect(anchorChipLabels.length, 8);
  });

  testWidgets('علامة ف بترسم — كاملة، مختزلة تحت ١٦، ومن غير نبضة مع تقليل الحركة', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ColoredBox(
            color: F.greenDeep,
            child: Row(
              children: [
                FaMark(size: 120, breathing: true),
                FaMark(size: 14),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<FaMarkPainter>()
        .toList();
    expect(painters.length, 2);
    expect(painters.first.reduced, isFalse);
    expect(painters.last.reduced, isTrue);
    expect(painters.first.beat, 0, reason: 'تقليل الحركة → النقطة ساكنة');
  });

  testWidgets('شاشة البداية طبقة فوق التطبيق — الشاشة الأولى موجودة من أول فريم وبتتشال بعد ١.٩ ث',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashOverlay(child: Scaffold(body: Text('الشاشة الأولى'))),
      ),
    );
    await tester.pump();
    expect(find.text('الشاشة الأولى'), findsOneWidget, reason: 'مش بوابة');
    expect(find.text('فكرني'), findsOneWidget);

    await tester.pump(SplashOverlay.total + const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('فكرني'), findsNothing);
    expect(find.text('الشاشة الأولى'), findsOneWidget);
  });

  test('اتجاه اسم الدوا من أول حرف قوي: لاتيني LTR، عربي RTL', () {
    expect(nameDirection('Antodine 40 mg'), TextDirection.ltr);
    expect(nameDirection('40 mg Telfast'), TextDirection.ltr);
    expect(nameDirection('كونكور ٥'), TextDirection.rtl);
    expect(nameDirection('١٢٣'), TextDirection.rtl);
  });
}
