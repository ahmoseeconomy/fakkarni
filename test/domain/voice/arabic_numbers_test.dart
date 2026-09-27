// بورت `numbers.ar.js` — نفس حالات `backend/test/nlu.test.js` بالحرف (القيم
// بالجنيه بدل القروش).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/arabic_numbers.dart';

void main() {
  List<double> values(String s) => [for (final n in extractNumbers(s)) n.value];

  test('الأرقام العربية والفارسية بتتحوّل', () {
    expect(normalizeDigits('٢٠٠'), '200');
    expect(normalizeDigits('۲۰۰'), '200');
    expect(normalizeDigits('١٢٣٤٥٦٧٨٩٠'), '1234567890');
    expect(normalizeDigits('١٢٫٥'), '12.5');
    expect(normalizeDigits('١٬٢٠٠'), '1200');
  });

  test('أرقام غربية', () {
    expect(values('صرفت 200 جنيه'), [200]);
    expect(values('دفعت 45.50 جنيه'), [45.5]);
    expect(values('1,250 جنيه'), [1250]);
  });

  test('أرقام عربية زي الغربية', () {
    expect(values('صرفت ٢٠٠ جنيه'), [200]);
    expect(values('٤٥٫٥٠ جنيه'), [45.5]);
  });

  test('كلام مصري', () {
    expect(values('ميتين جنيه'), [200]);
    expect(values('مية جنيه'), [100]);
    expect(values('خمسميه جنيه'), [500]);
    expect(values('ألف جنيه'), [1000]);
    expect(values('ألفين جنيه'), [2000]);
  });

  test('«تلت تلاف»', () {
    expect(values('تلت تلاف جنيه'), [3000]);
    expect(values('خمس تلاف'), [5000]);
    expect(values('عشر تلاف'), [10000]);
  });

  test('العطف بـ«و»', () {
    expect(values('ميتين وخمسين'), [250]);
    expect(values('ألف وخمسميه'), [1500]);
    expect(values('تلاتين جنيه'), [30]);
  });

  test('الأرقام من ١١ لـ١٩', () {
    expect(values('خمستاشر جنيه'), [15]);
    expect(values('حداشر جنيه'), [11]);
  });

  test('لاحقة «ك»', () {
    expect(values('٥ك'), [5000]);
    expect(values('2.5k'), [2500]);
  });

  test('رقم + كلمة آلاف', () {
    expect(values('5 آلاف جنيه'), [5000]);
    expect(values('3 ألف'), [3000]);
  });

  test('مخلوط في جملة واحدة — الكل بيتلقى', () {
    final found = values('صرفت ٢٠٠ جنيه و 50 جنيه على المواصلات');
    expect(found, contains(200));
    expect(found, contains(50));
  });

  test('صفر وسالب ما بيرجعوش', () {
    expect(values('صفر جنيه'), isEmpty);
    expect(values('مفيش حاجة'), isEmpty);
  });

  test('«ونص» و«وربع» بيتضافوا للرقم — بالأرقام وبالكلام', () {
    expect(values('تمانية ونص'), [8.5]);
    expect(values('٣ وربع'), [3.25]);
    expect(values('اتنين و نص'), [2.5]);
  });

  test('«بميه» — الباء ملزوقة', () {
    expect(values('اشتريت بنزين بميه جنيه'), [100]);
    expect(values('و٣٠٠'), [300]);
  });

  test('الجملة الحقيقية من الأصل', () {
    expect(values('صرفت ٢٠٠ جنيه على الأكل امبارح'), [200]);
  });

  test('«ثمانيه» = ٨ (الأصل كان فيه ٩ بالغلط)', () {
    expect(values('ثمانية'), [8]);
    expect(firstNumber('الضغط ١٢٠ على ٨٠'), 120);
  });
}
