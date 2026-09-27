// سؤال السن اختياري — «مش عايز أقول» بالصوت تخطّي، مش سن ومش «مافهمتش».
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/answer_parser.dart';

void main() {
  for (final s in ['مش عايز أقول', 'مش عايزة أقول', 'لا', 'لأ', 'عدّي', 'عدي', 'بعدين', 'لا مش عايز']) {
    test('«$s» تخطّي', () => expect(parseAgeAnswer(s), isA<AgeSkipped>()));
  }
  test('الرقم بيكسب', () {
    final a = parseAgeAnswer('اتنين وسبعين');
    expect(a, isA<AgeGiven>());
    expect((a as AgeGiven).age, 72);
  });
  test('كلام مش مفهوم مش تخطّي', () => expect(parseAgeAnswer('الجو حلو'), isA<AgeUnclear>()));
  test('فاضي مش تخطّي', () => expect(parseAgeAnswer(''), isA<AgeUnclear>()));
}
