// «نسيتها؟» بعد مهلة الـ٤٥ دقيقة بس — في معادها «معادها دلوقتي» (آيفون،
// ٢٦ سبتمبر ٢٠٢٦: «نسيتها؟ … كان معادها ٦:٥١» في نفس دقيقة التذكير).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/escalation/dose_moment.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

void main() {
  final at = DateTime(2026, 9, 26, 18, 51);
  DoseMoment m(Duration after, {bool missed = false}) =>
      doseMomentOf(scheduledAt: at, now: at.add(after), markedMissed: missed);

  test('قبل معادها: الجاية', () => expect(m(const Duration(minutes: -1)), DoseMoment.upcoming));
  test('في نفس الدقيقة: دلوقتي — مش نسيتها', () => expect(m(Duration.zero), DoseMoment.dueNow));
  test('بعد ١٠ و٤٤ دقيقة: لسه دلوقتي', () {
    expect(m(const Duration(minutes: 10)), DoseMoment.dueNow);
    expect(m(const Duration(minutes: 44, seconds: 59)), DoseMoment.dueNow);
  });
  test('عند المهلة بالظبط (٤٥) وبعدها: نسيتها', () {
    expect(m(graceWindow), DoseMoment.missed);
    expect(m(const Duration(hours: 2)), DoseMoment.missed);
  });
  test('الجهاز كتب «اتنست» = نسيتها مهما كانت الساعة', () => expect(m(const Duration(minutes: 5), missed: true), DoseMoment.missed));
}
