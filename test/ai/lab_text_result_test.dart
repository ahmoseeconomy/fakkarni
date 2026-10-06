// النتيجة النصية (المرحلة ٥، قرار المالك 1A) — القارئ النقي، من JSON من
// غير شبكة: «Negative» بتتنقل بالحرف، واحدة من الاتنين، والسطر اللي مالوش
// ولا نتيجة واضحة بيقفل «تمام».
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reading.dart';

Map<String, dynamic> field(dynamic value, [double confidence = 0.95]) =>
    {'value': value, 'confidence': confidence};

LabLine lineFrom(Map<String, dynamic> json) =>
    LabReading.fromJson({'results': [json]}).lines.single;

void main() {
  test('نتيجة نصية: بتتنقل بالحرف، الرقم null، ومش بتقفل «تمام»', () {
    final l = lineFrom({
      'test': field('Pus Cells'),
      'value': field(null),
      'valueText': field('Negative'),
      'unit': field(null),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.numberResult, isNull);
    expect(l.textResult, 'Negative', reason: 'بالحرف — مش مترجمة ولا متحوّلة رقم');
    expect(l.blocksConfirm, isFalse);
  });

  test('نتيجة رقمية زي زمان: النص null ومفيش حاجة اتغيّرت', () {
    final l = lineFrom({
      'test': field('HbA1c'),
      'value': field(7.6),
      'valueText': field(null),
      'unit': field('%'),
      'refLow': field(4),
      'refHigh': field(6),
      'refText': field(null),
    });
    expect(l.numberResult, 7.6);
    expect(l.textResult, isNull);
    expect(l.blocksConfirm, isFalse);
  });

  test('الاتنين جم بثقة (مخالفة للبرومبت): الرقم بيكسب والنص بيتساب', () {
    // الكلمة جنب رقم غالباً علامة H/L — ودي ممنوعة أصلاً، فما بنحفظهاش.
    final l = lineFrom({
      'test': field('WBC'),
      'value': field(12.4),
      'valueText': field('High'),
      'unit': field(null),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.numberResult, 12.4);
    expect(l.textResult, isNull);
  });

  test('نص بثقة واطية = مفيش نتيجة — السطر بيقفل «تمام» ما بيتخمّنش', () {
    final l = lineFrom({
      'test': field('Pus Cells'),
      'value': field(null),
      'valueText': field('Negat?', 0.4),
      'unit': field(null),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.textResult, isNull);
    expect(l.blocksConfirm, isTrue);
  });

  test('ولا رقم ولا نص (مش مقروء) = السطر بيقفل «تمام»', () {
    final l = lineFrom({
      'test': field('Albumin'),
      'value': field(null),
      'valueText': field(null),
      'unit': field(null),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.blocksConfirm, isTrue);
  });

  test('نص فاضي أو مسافات مش نتيجة', () {
    final l = lineFrom({
      'test': field('Albumin'),
      'value': field(null),
      'valueText': field('   '),
      'unit': field(null),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.textResult, isNull);
    expect(l.blocksConfirm, isTrue);
  });

  test('حقل valueText ساقط من رد قديم/ناقص = missing — مش رمية', () {
    final l = lineFrom({
      'test': field('HbA1c'),
      'value': field(7.1),
      'unit': field('%'),
      'refLow': field(null),
      'refHigh': field(null),
      'refText': field(null),
    });
    expect(l.textResult, isNull);
    expect(l.blocksConfirm, isFalse);
  });
}
