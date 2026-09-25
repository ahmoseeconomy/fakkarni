import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/stock.dart';

void main() {
  test('الجرعة بالرقم — والمش مفهومة ١', () {
    expect(doseAmountOf('قرص واحد'), 1);
    expect(doseAmountOf('نص قرص'), 0.5);
    expect(doseAmountOf('قرصين'), 2);
    expect(doseAmountOf('كبسولتين'), 2);
    expect(doseAmountOf('٢ قرص'), 2);
    expect(doseAmountOf('10 نقط'), 10);
    expect(doseAmountOf('ربع قرص'), 0.25);
    expect(doseAmountOf(null), 1);
    expect(doseAmountOf('فيتامين د'), 1, reason: 'مش أي كلمة آخرها «ين» اتنين');
    expect(doseAmountOf('بعد الأكل'), 1);
  });

  test('الوحدة من كلام الجرعة، وإلا «وحدة»', () {
    expect(stockUnitOf('قرص واحد'), 'قرص');
    expect(stockUnitOf('كبسولة'), 'كبسولة');
    expect(stockUnitOf('معلقة صغيرة'), 'ملعقة');
    expect(stockUnitOf('٣ نقط'), 'نقط');
    expect(stockUnitOf('حقنة تحت الجلد'), 'حقنة');
    expect(stockUnitOf(null), 'وحدة');
  });

  test('الجرعة بتنقّص وعمرها ما تنزّل تحت الصفر، والإلغاء بيرجّعها', () {
    expect(stockAfterTaken(10, 1), 9);
    expect(stockAfterTaken(0.5, 1), 0);
    expect(stockAfterUndo(9, 1), 10);
  });

  test('فاضله كام يوم = المخزون ÷ (جرعات اليوم × الجرعة)، مقرّب لتحت', () {
    expect(stockDaysLeft(stock: 20, dosesPerDay: 2, amount: 1), 10);
    expect(stockDaysLeft(stock: 9, dosesPerDay: 2, amount: 1), 4);
    expect(stockDaysLeft(stock: 3, dosesPerDay: 3, amount: 0.5), 2);
    expect(stockDaysLeft(stock: 10, dosesPerDay: 0, amount: 1), isNull, reason: 'مفيش جدول يومي = مفيش تخمين');
  });

  test('«قرب يخلص» عند الحد بالظبط، ومش قبله', () {
    expect(stockIsLow(daysLeft: 5, warnDays: 5), isTrue);
    expect(stockIsLow(daysLeft: 6, warnDays: 5), isFalse);
    expect(stockIsLow(daysLeft: null, warnDays: 5), isFalse);
    expect(defaultRefillWarnDays, 5);
  });

  test('الكلام', () {
    expect(stockLowLine('كونكور', stock: 8, daysLeft: 4), 'كونكور فاضله ٤ أيام');
    expect(stockLowLine('كونكور', stock: 2, daysLeft: 1), 'كونكور فاضله يوم واحد');
    expect(stockLowLine('كونكور', stock: 0.5, daysLeft: 0), 'كونكور فاضله أقل من يوم');
    expect(stockLowLine('كونكور', stock: 0, daysLeft: 0), 'كونكور خلص');
    expect(stockSummaryLine(stock: 20, unit: 'قرص', daysLeft: 10), 'معاك ٢٠ قرص — تكفّي ١٠ أيام');
    expect(stockSummaryLine(stock: 20, unit: 'قرص', daysLeft: null), 'معاك ٢٠ قرص');
    expect(pharmacyOrderMessage('Concor 5mg', 1), 'محتاج Concor 5mg — ١ علبة');
    expect(pharmacyOrderMessage('Concor 5mg', 2), 'محتاج Concor 5mg — علبتين');
    expect(pharmacyOrderMessage('Concor 5mg', 3), 'محتاج Concor 5mg — ٣ علب');
  });

  test('رقم الواتساب المصري', () {
    expect(whatsappNumber('01012345678'), '201012345678');
    expect(whatsappNumber('٠١٠١٢٣٤٥٦٧٨'), '201012345678');
    expect(whatsappNumber('+20 101 234 5678'), '201012345678');
    expect(whatsappNumber('123'), isNull);
  });

  test('متوسط الجرعات في اليوم: تعريف واحد — كل ٨ ساعات = ٣، ومرة واحدة والموقوف صفر', () {
    expect(averageDosesPerDay([
      for (var i = 0; i < 3; i++) (repeat: 'daily', stopped: false, share: 1.0),
    ]), 3);
    expect(averageDosesPerDay(const [(repeat: 'once', stopped: false, share: 1.0)]), 0);
    expect(averageDosesPerDay(const [(repeat: 'daily', stopped: true, share: 1.0), (repeat: 'daily', stopped: false, share: 1.0)]), 1);
    // كل ٤ ساعات = ٦ جداول يومية → ٣٠ قرص = ٥ أيام
    final perDay = averageDosesPerDay([for (var i = 0; i < 6; i++) (repeat: 'daily', stopped: false, share: 1.0)]);
    expect(stockDaysLeft(stock: 30, dosesPerDay: perDay, amount: 1), 5);
  });
}
