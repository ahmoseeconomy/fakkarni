// «مرة واحدة» كان أول حرفها بيتقصّ في «نوع التنبيه» (مراجعة المالك على
// الجهاز، ٥ أكتوبر ٢٠٢٦ مساءً): أربع شرايح متساوية في صف واحد على ٣٤٣
// بكسل، والفيض `TextOverflow.visible` بيترسم تحت الشريحة الجنبية — يعني
// الحرف بيضيع **من غير أي خطأ ولا فيض مُبلَّغ**. الحل اتنين في الصف (نفس
// سابقة شبكة الأكل)، والحارس هنا **هندسي**: عرض الكلمة الحقيقي (TextPainter
// بنفس الستايل والتكبير) لازم يدخل في عرض شريحتها — على ٣٧٥ وبخط ×١٫٣،
// للـ٤ شرايح (الفورم) والـ٣ (الإعدادات). عدّ الواجهات كان هيعدّي على قصّ
// بيحصل وقت الرسم.
import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/escalation/alert_mode.dart';
import 'package:fakkarni/features/medication/alert_mode_chips.dart';

import '../scan/scan_test_support.dart';

/// بالخطوط الحقيقية — خط الاختبار بيرسم كل حرف مربّع، فالقياس الهندسي
/// عليه بيضخّم العرض لضعفه تقريباً (نفس سبب wheels_se).
Future<void> _loadFonts() async {
  final loader = FontLoader('Cairo');
  for (final f in [
    'Cairo-Regular.ttf',
    'Cairo-Medium.ttf',
    'Cairo-SemiBold.ttf',
    'Cairo-Bold.ttf',
    'Cairo-ExtraBold.ttf',
  ]) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFonts);

  Future<void> pump(WidgetTester tester, {required bool allowDefault, required double scale}) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: AlertModeChips(allowDefault: allowDefault, value: null, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  void expectLabelsFit(WidgetTester tester, List<String> labels) {
    for (final label in labels) {
      final textWidget = tester.widget<Text>(find.text(label));
      final box = tester.renderObject<RenderBox>(find.text(label));
      final painter = TextPainter(
        text: TextSpan(text: label, style: DefaultTextStyle.of(tester.element(find.text(label))).style.merge(textWidget.style)),
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.of(tester.element(find.text(label))).textScaler,
      )..layout();
      expect(
        painter.width,
        lessThanOrEqualTo(box.size.width + 0.5),
        reason: '«$label» أعرض من شريحتها (${painter.width} > ${box.size.width}) — هتتقصّ',
      );
    }
  }

  List<String> labels(bool allowDefault) => [
        if (allowDefault) AlertModeChips.defaultLabel,
        for (final m in AlertMode.values) m.label,
      ];

  for (final scale in [1.0, 1.3]) {
    testWidgets('فورم الدوا (٤ شرايح) على ٣٧٥ بخط ×$scale: ولا كلمة بتتقصّ، واتنين في الصف', (tester) async {
      await pump(tester, allowDefault: true, scale: scale);
      expectLabelsFit(tester, labels(true));
      // اتنين في الصف: «الافتراضي» وأول نوع على نفس السطر، والتالت تحتهم
      final first = tester.getRect(find.byKey(const ValueKey('alert-mode-default')));
      final second = tester.getRect(find.byKey(ValueKey('alert-mode-${AlertMode.values.first.name}')));
      final third = tester.getRect(find.byKey(ValueKey('alert-mode-${AlertMode.values[1].name}')));
      expect(first.top, second.top, reason: 'صف واحد للاتنين الأولانيين');
      expect(third.top, greaterThan(first.bottom), reason: 'التالتة في صف جديد');
      expect(tester.takeException(), isNull);
    });

    testWidgets('الإعدادات (٣ شرايح) على ٣٧٥ بخط ×$scale: ولا كلمة بتتقصّ', (tester) async {
      await pump(tester, allowDefault: false, scale: scale);
      expectLabelsFit(tester, labels(false));
      expect(tester.takeException(), isNull);
    });
  }
}
