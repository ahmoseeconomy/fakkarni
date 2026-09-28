// أرقام «صيدليتي»: موبايل = اتصال وواتساب، أرضي = اتصال بس، وعمر الأرضي ما
// يبقى واتساب.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/places/pharmacy_numbers.dart';

void main() {
  test('التطبيع: أرقام عربي، +٢٠ و٠٠٢٠، مسافات وشرط — والأرضي زي ما هو', () {
    expect(normalizeEgyptPhone('٠١٠١ ٢٣٤ ٥٦٧٨'), '01012345678');
    expect(normalizeEgyptPhone('+20 101-234-5678'), '01012345678');
    expect(normalizeEgyptPhone('00201012345678'), '01012345678');
    expect(normalizeEgyptPhone('201012345678'), '01012345678');
    expect(normalizeEgyptPhone('1012345678'), '01012345678');
    expect(normalizeEgyptPhone('02-2345-6789'), '0223456789');
    expect(normalizeEgyptPhone('+20 2 2345 6789'), '0223456789');
    expect(normalizeEgyptPhone('١٢٣'), isNull, reason: 'مش رقم');
  });

  test('موبايل واحد → اتصال وواتساب نفس الرقم، ومفيش سؤال', () {
    final n = choosePharmacyNumbers(phones: ['٠١٢٢٣٤٥٦٧٨٩']);
    expect(n.call, '01223456789');
    expect(n.whatsapp, '01223456789');
    expect(n.needsWhatsAppQuestion, isFalse);
  });

  test('أرضي → اتصال بس، الواتساب فاضي والسؤال بيظهر', () {
    final n = choosePharmacyNumbers(phones: ['02 2345 6789']);
    expect(n.call, '0223456789');
    expect(n.whatsapp, isNull);
    expect(n.needsWhatsAppQuestion, isTrue);
  });

  test('مفيش رقم خالص → السؤال بيظهر', () {
    final n = choosePharmacyNumbers();
    expect(n.call, isNull);
    expect(n.needsWhatsAppQuestion, isTrue);
  });

  test('موبايلين → شرايح يختار منها، مش تخمين', () {
    final n = choosePharmacyNumbers(phones: ['01012345678', '+20 115 555 4444']);
    expect(n.whatsapp, isNull);
    expect(n.mobileChoices, ['01012345678', '01155554444']);
    expect(n.needsWhatsAppQuestion, isFalse);
  });

  test('الرقم اللي عليه «واتساب» بيكسب — والاتصال بيروح للأرضي', () {
    final n = choosePharmacyNumbers(whatsapp: '0100 999 8888', phones: ['0223456789', '01012345678']);
    expect(n.whatsapp, '01009998888');
    expect(n.call, '0223456789');
    expect(n.mobileChoices, isEmpty);
  });

  test('رقم «واتساب» أرضي عمره ما يبقى واتساب', () {
    final n = choosePharmacyNumbers(whatsapp: '0223456789', phones: ['0223456789']);
    expect(n.whatsapp, isNull);
    expect(n.needsWhatsAppQuestion, isTrue);
  });
}
