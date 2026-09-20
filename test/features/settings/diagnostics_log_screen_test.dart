import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/diagnostics.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/settings/diagnostics_log_screen.dart';

import '../scan/scan_test_support.dart';

/// الشاشة دي هي كل اللي بيشوفه المطوّر من سكّة صحوة شاشة القفل، فلازم
/// تفضل تشتغل حتى لما مفيش ملف أصلاً — وده حال أي جهاز غير iOS وحال
/// `flutter test` نفسه.
void main() {
  Widget app() => MaterialApp(
        theme: F.light,
        locale: const Locale('ar'),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: DiagnosticsLogScreen(),
        ),
      );

  // `find.byType` بيقارن النوع بالظبط مش بالوراثة، فلازم `OutlinedButton`
  // نفسه — `ButtonStyleButton` (الأب) ما بيلاقيش حاجة.
  OutlinedButton buttonFor(WidgetTester tester, String label) =>
      tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
      );

  screenTest('من غير ملف: بتقول مفيش حاجة، والنسخ والمسح مقفولين',
      (tester) async {
    // قراية السجل بتمرّ على path_provider، وده نداء قناة حقيقي:
    // من غير runAsync الـzone الوهمي ما بيدوّرهوش خالص والشاشة بتفضل
    // على «بنقرا…» للأبد — نفس الفخ المكتوب في أعراف الاختبارات.
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);

    expect(find.textContaining('لسه مفيش حاجة هنا'), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-line')), findsNothing);

    for (final label in ['انسخ', 'امسح']) {
      expect(buttonFor(tester, label).onPressed, isNull,
          reason: 'زرار على سجل فاضي بيوعد بحاجة مش موجودة');
    }
    // «حدّث» بيفضل شغّال: سطر ممكن ينزل والشاشة مفتوحة
    expect(buttonFor(tester, 'حدّث').onPressed, isNotNull);
  });

  test('الثوابت اللي الناحيتين متفقين عليها', () {
    // سويفت بتكتب نفس القيم دي في ios/Runner/AppDelegate.swift — لو
    // واحدة اتحرّكت لوحدها، الفلتر بيولّع نص السكّة والملف بيتقسم.
    expect(diagPrefix, 'FKDIAG ');
    expect(diagFileName, 'fkdiag.log');
    expect(diagMaxLines, 200);
  });
}
