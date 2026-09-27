import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/doctor_match.dart';

void main() {
  const saved = ['د. حسن علي', 'دكتور حسين محمود', 'د. هشام', 'Dr. Magdy Hanna'];

  test('اسم واحد بيطابق — مهما اتكتب اللقب', () {
    expect(matchDoctors('د. حسن', saved), ['د. حسن علي']);
    expect(matchDoctors('الدكتور هشام', saved), ['د. هشام']);
    expect(matchDoctors('dr magdy', saved), ['Dr. Magdy Hanna']);
  });

  test('«حسن» مش «حسين» — الأسامي القصيرة لازم تتطابق', () {
    expect(matchDoctors('د. حسين', saved), ['دكتور حسين محمود']);
  });

  test('غلطة متعرّف بحرف في اسم طويل بتتقبل', () {
    expect(matchDoctors('د. محمود', saved), ['دكتور حسين محمود']);
    expect(matchDoctors('د. محمد', saved), isEmpty, reason: 'محمد مش محمود — الاتنين قصيرين عن الحد');
  });

  test('أكتر من واحد → الكل، ومفيش → فاضي', () {
    expect(matchDoctors('د. حسن', ['د. حسن علي', 'د. حسن فؤاد']), hasLength(2));
    expect(matchDoctors('د. شريف', saved), isEmpty);
    expect(matchDoctors('دكتور', saved), isEmpty, reason: 'لقب من غير اسم');
  });

  test('دكاترته من الملف من غير تكرار ومن غير فاضي', () {
    expect(distinctDoctors(['د. حسن', null, '', 'دكتور حسن', 'د. هشام', ' د. هشام ']), ['د. حسن', 'د. هشام']);
  });
}
