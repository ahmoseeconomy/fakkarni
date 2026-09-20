import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/lab_range.dart';

/// النطاق من الورقة، والمقارنة حساب على رقمين مطبوعين.
void main() {
  // ٤–١١ عرضها ٧، فهامش «قريب من الحد» = ٠.٧ من كل ناحية.
  const wbc = LabRange(low: 4, high: 11);

  group('جوّه وبرّه', () {
    test('جوّه النطاق وبعيد عن الطرفين: مفيش علامة خالص', () {
      expect(labFlagFor(7.5, wbc), isA<InsideRange>());
      expect(isFlagged(labFlagFor(7.5, wbc)), isFalse);
    });

    test('فوق الطرف الأعلى', () {
      expect(labFlagFor(12.4, wbc), isA<AboveRange>());
      expect(isFlagged(labFlagFor(12.4, wbc)), isTrue);
    });

    test('تحت الطرف الأدنى', () {
      expect(labFlagFor(3.2, wbc), isA<BelowRange>());
      expect(isFlagged(labFlagFor(3.2, wbc)), isTrue);
    });

    test('أول رقم برّه الطرف — مش «قريب»، برّه', () {
      expect(labFlagFor(11.01, wbc), isA<AboveRange>());
      expect(labFlagFor(3.99, wbc), isA<BelowRange>());
    });
  });

  group('على الحد بالظبط', () {
    // الطرف نفسه جوّه النطاق (الورقة بتكتبه كحد مقبول) — وبعده عن الحد صفر،
    // يعني «قريب من الحد» بالتعريف.
    test('على الطرف الأعلى: جوّه، وقريب', () {
      expect(labFlagFor(11, wbc), isA<NearBoundary>());
    });

    test('على الطرف الأدنى: جوّه، وقريب', () {
      expect(labFlagFor(4, wbc), isA<NearBoundary>());
    });
  });

  group('قريب من الحد — ١٠٪ من عرض النطاق', () {
    test('على حافة الهامش بالظبط لسه قريب', () {
      // ٤ + ٠.٧ = ٤.٧ و١١ − ٠.٧ = ١٠.٣
      expect(labFlagFor(4.7, wbc), isA<NearBoundary>());
      expect(labFlagFor(10.3, wbc), isA<NearBoundary>());
    });

    test('بعد الهامش بشعرة بقى جوّه عادي', () {
      expect(labFlagFor(4.71, wbc), isA<InsideRange>());
      expect(labFlagFor(10.29, wbc), isA<InsideRange>());
    });

    test('الهامش بيتمدّ مع عرض النطاق نفسه — مش رقم مطلق', () {
      // ٠–٢٠٠ عرضها ٢٠٠، فالهامش ٢٠: ١٨٥ قريب رغم إنها بعيدة بـ١٥
      const wide = LabRange(low: 0, high: 200);
      expect(labFlagFor(185, wide), isA<NearBoundary>());
      // نفس المسافة (١٥) في نطاق ضيّق مش قريبة أصلاً — هي برّه
      expect(labFlagFor(26, wbc), isA<AboveRange>());
    });

    test('نطاق من طرف واحد: جوّه/برّه وبس — مفيش عرض نحسب منه', () {
      const upTo = LabRange(high: 200);
      expect(labFlagFor(199.9, upTo), isA<InsideRange>());
      expect(labFlagFor(201, upTo), isA<AboveRange>());
      const from = LabRange(low: 40);
      expect(labFlagFor(40.1, from), isA<InsideRange>());
      expect(labFlagFor(39, from), isA<BelowRange>());
    });
  });

  group('نطاق مش رقمي أو مش موجود', () {
    test('الورقة ما طبعتش نطاق: مفيش علامة', () {
      expect(labFlagFor(5.1, null), isA<NoPrintedRange>());
      expect(labFlagFor(5.1, const LabRange()), isA<NoPrintedRange>());
      expect(isFlagged(labFlagFor(5.1, null)), isFalse);
    });

    test('نطاق مطبوع بالحروف: بيتعرض زي ما هو وعمره ما بيتقارن', () {
      const negative = LabRange(text: 'Negative');
      expect(labFlagFor(3, negative), isA<RangeNotNumeric>());
      expect(isFlagged(labFlagFor(3, negative)), isFalse);
      const lessThan = LabRange(text: '< 5');
      expect(labFlagFor(9999, lessThan), isA<RangeNotNumeric>(),
          reason: 'نص مطبوع ما بيتحوّلش لرقم عشان نحكم بيه');
    });

    test('نطاق مقلوب على الورقة ما بنصلّحهوش وما بنحكمش بيه', () {
      const reversed = LabRange(low: 11, high: 4);
      expect(reversed.comparable, isFalse);
      expect(labFlagFor(7, reversed), isA<RangeNotNumeric>());
    });
  });
}
