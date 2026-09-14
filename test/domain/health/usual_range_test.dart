import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/usual_range.dart';

void main() {
  test('أقل من الحد → مفيش نطاق خالص (مش نطاق من كتاب)', () {
    expect(usualRangeOf([110, 120, 130, 125], minimum: minGlucoseReadings), isNull);
    expect(usualRangeOf([7.1], minimum: minLabValues), isNull);
    expect(usualRangeOf([], minimum: 1), isNull);
  });

  test('النطاق من أقل لأعلى في آخر ١٠ بس — الأقدم منهم ما بيتحسبش', () {
    final previous = [118, 125, 110, 131, 122, 119, 127, 115, 120, 124, 300, 40];
    final r = usualRangeOf(previous, minimum: minGlucoseReadings)!;
    expect(r.low, 110);
    expect(r.high, 131);
    expect(r.count, 10);
  });

  test('المقارنة رقم وفرق', () {
    const r = UsualRange(110, 131, 10);
    expect(compareToUsual(152, r), isA<AboveUsual>().having((c) => c.by, 'by', 21));
    expect(compareToUsual(95, r), isA<BelowUsual>().having((c) => c.by, 'by', 15));
    expect(compareToUsual(131, r), isA<WithinUsual>(), reason: 'الحدود جوّه');
    expect(compareToUsual(110, r), isA<WithinUsual>());
  });

  test('الدومين نقي — مفيش Flutter ولا drift (القاعدة ٢)', () {
    final source = File('lib/domain/health/usual_range.dart').readAsStringSync();
    expect(source.contains("import 'package:"), isFalse);
  });
}
