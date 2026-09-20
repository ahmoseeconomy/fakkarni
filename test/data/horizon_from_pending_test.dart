import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

/// **الخطة هي اللي احنا فاكرينه؛ الـpending هو اللي الجهاز ماسكه.**
/// الفحص بيقرا من التاني عن قصد، فالدالة دي لازم ترجّع الوقت من الرقم
/// نفسه — من غير ما تسأل الخطة عن حاجة.
void main() {
  final now = DateTime(2026, 9, 20, 10);

  test('رقم تذكير بكرة بيرجع لوقته', () {
    final at = DateTime(2026, 9, 21, 7, 30);
    final id = notificationIdFor(at);

    expect(horizonFromPendingDoseIds([id], now: now), at);
  });

  test('بياخد الأبعد، مش الأول ولا الآخر في القايمة', () {
    final near = notificationIdFor(DateTime(2026, 9, 20, 20));
    final far = notificationIdFor(DateTime(2026, 9, 25, 7));
    final mid = notificationIdFor(DateTime(2026, 9, 22, 14));

    expect(horizonFromPendingDoseIds([far, near, mid], now: now),
        DateTime(2026, 9, 25, 7));
  });

  test('اللي معاده عدّى مش بيتحسب', () {
    final past = notificationIdFor(DateTime(2026, 9, 20, 7));
    expect(horizonFromPendingDoseIds([past], now: now), isNull);
  });

  test('أرقام برّه نطاق الجرعات بتتجاهل — السلّم والصيام مش تذكير جرعة', () {
    final escalation = escalationIdFor(DateTime(2026, 9, 25, 7), EscalationRung.first);
    final fasting = fastingIdFor(7);
    expect(horizonFromPendingDoseIds([escalation, fasting], now: now), isNull);
  });

  test('قايمة فاضية → null، وده معناه «الجهاز مش ماسك حاجة»', () {
    expect(horizonFromPendingDoseIds(const [], now: now), isNull);
  });

  test('بيحترم خانة المريض', () {
    final at = DateTime(2026, 9, 23, 9);
    final id = notificationIdFor(at, patientIndex: 3);

    expect(horizonFromPendingDoseIds([id], now: now, patientIndex: 3), at);
    // بخانة غلط الرقم بيقع برّه النطاق وبيتشال بدل ما يرجّع وقت مخترع
    expect(horizonFromPendingDoseIds([id], now: now), isNot(at));
  });

  test('نفس نافذة السبع أيام: أبعد يوم في النافذة بيترجّع صح', () {
    final at = DateTime(2026, 9, 27, 23, 30);
    expect(horizonFromPendingDoseIds([notificationIdFor(at)], now: now), at);
  });
}
