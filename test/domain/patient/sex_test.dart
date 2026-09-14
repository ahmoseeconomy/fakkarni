import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/patient/sex.dart';

void main() {
  test('المؤنث للست بس — والمجهول (قبل نسخة ٨) بيفضل على المذكّر اللي كان عليه', () {
    const f = Say(Sex.f), m = Say(Sex.m), unknown = Say(null);
    expect(f.breakfastQuestion, 'بتفطري الساعة كام؟');
    expect(m.breakfastQuestion, 'بتفطر الساعة كام؟');
    expect(unknown.breakfastQuestion, 'بتفطر الساعة كام؟');
    expect(f.takenAt('٨:٠٠ ص'), 'أخدتيه ٨:٠٠ ص');
    expect(m.takenAt('٨:٠٠ ص'), 'أخدته ٨:٠٠ ص');
    expect(f.notSure, 'مش متأكدة');
    expect(f.forgotIt, 'نسيتيها؟');
    expect(f.backToDay, 'ارجعي ليومك');
  });
}
