import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/care/caregiver_settings_screen.dart';

void main() {
  testWidgets('إعداد صوت التصعيد واضح ويحفظ اختيار القفل والفتح', (
    tester,
  ) async {
    var on = true;
    final writes = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) => CareEscalationSoundRow(
                on: on,
                onTap: () => setState(() {
                  on = !on;
                  writes.add(on);
                }),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('صوت تنبيهات الجرعات'), findsOneWidget);
    expect(find.text('شغّال'), findsOneWidget);
    await tester.tap(find.byType(CareEscalationSoundRow));
    await tester.pump();
    expect(writes, [false]);
    expect(find.text('مقفول'), findsOneWidget);
    expect(find.text('التنبيه بيوصلك ظاهر بس من غير صوت'), findsOneWidget);
  });
}
