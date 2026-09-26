// «نسيتها؟» بعد مهلة الـ٤٥ دقيقة بس (آيفون، ٢٦ سبتمبر ٢٠٢٦: «نسيتها؟ … كان
// معادها ٦:٥١» ظهرت في نفس الدقيقة اللي التذكير رن فيها).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setUp();
    await h.meds.addMedication(
      patientId: h.services.patientId,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: aug31,
    );
  });
  tearDown(() => h.tearDown());

  screenTest('في نفس دقيقة المعاد: «معادها دلوقتي» — مش «نسيتها؟»', (tester) async {
    await h.pump(tester, TodayScreen(routine: normalDay, now: DateTime(2026, 8, 31, 20)));
    expect(find.textContaining('معادها دلوقتي'), findsWidgets);
    expect(find.text('نسيتها؟'), findsNothing);
    expect(find.textContaining('كان معادها'), findsNothing);
    expect(find.text('لسه ما اتأكدتش'), findsNothing);
  });

  screenTest('بعد ٤٤ دقيقة: لسه «دلوقتي»', (tester) async {
    await h.pump(tester, TodayScreen(routine: normalDay, now: DateTime(2026, 8, 31, 20, 44)));
    expect(find.text('نسيتها؟'), findsNothing);
    expect(find.textContaining('معادها دلوقتي'), findsWidgets);
  });

  screenTest('بعد مهلة الـ٤٥: «نسيتها؟ — لسه ما اتأكدتش — كان معادها ٨:٠٠ م»', (tester) async {
    await h.pump(tester, TodayScreen(routine: normalDay, now: DateTime(2026, 8, 31, 20, 50)));
    expect(find.text('نسيتها؟'), findsWidgets);
    expect(find.textContaining('كان معادها'), findsWidgets);
    expect(find.textContaining('معادها دلوقتي'), findsNothing);
  });
}
