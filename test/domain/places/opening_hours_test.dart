import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/places/distance.dart';
import 'package:fakkarni/domain/places/opening_hours.dart';

void main() {
  // ١٥ سبتمبر ٢٠٢٦ تلات
  DateTime tue(int h, [int m = 0]) => DateTime(2026, 9, 15, h, m);
  DateTime fri(int h, [int m = 0]) => DateTime(2026, 9, 18, h, m);

  test('24/7 دايماً فاتحة', () {
    expect(openStateAt('24/7', tue(3)), OpenState.open);
  });

  test('Mo-Su 09:30-21:30', () {
    expect(openStateAt('Mo-Su 09:30-21:30', tue(10)), OpenState.open);
    expect(openStateAt('Mo-Su 09:30-21:30', tue(9, 29)), OpenState.closed);
    expect(openStateAt('Mo-Su 09:30-21:30', tue(21, 30)), OpenState.closed);
  });

  test('أيام وفترات متعددة، والجمعة off، وقاعدة بعد بتغطي اللي قبل', () {
    const tag = 'Mo-Su 10:00-14:00,17:00-23:00; Fr off';
    expect(openStateAt(tag, tue(15)), OpenState.closed);
    expect(openStateAt(tag, tue(18)), OpenState.open);
    expect(openStateAt(tag, fri(12)), OpenState.closed);
  });

  test('بتعدّي نص الليل، وأيام بتلف (Sa-Th)', () {
    expect(openStateAt('Sa-Th 18:00-02:00', DateTime(2026, 9, 16, 1)), OpenState.open, reason: 'الأربع ١ ص من فترة التلات');
    expect(openStateAt('Sa-Th 18:00-02:00', DateTime(2026, 9, 19, 1)), OpenState.closed, reason: 'السبت ١ ص — الجمعة مش في الأيام');
    expect(openStateAt('10:00-22:00', tue(11)), OpenState.open, reason: 'من غير أيام = كل يوم');
  });

  test('أي حاجة مش مفهومة بالكامل → null (مفيش حكم)', () {
    for (final tag in ['Mo-Fr 09:00-17:00; PH off', 'sunrise-sunset', 'Jan-Mar Mo 10:00-12:00', '"by appointment"', 'Mo-Fr', '', 'Mo-Fr 9-17']) {
      expect(openStateAt(tag, tue(10)), isNull, reason: tag);
    }
  });

  test('المسافة: ميدان التحرير لرمسيس ≈ ٢.٢ كم', () {
    final m = metersBetween(30.0444, 31.2357, 30.0626, 31.2497);
    expect(m, inInclusiveRange(2100, 2500));
  });
}
