import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/wording/rule_wording.dart';

/// صف الجرعة بكلام البيت — «قبل الفطار بنص ساعة»، مش «الفطار − ٣٠ د».
void main() {
  test('١٥ و٣٠ و٤٥ و٦٠ بأسمائها، وغير كده بالدقايق', () {
    expect(spokenOffset(15), 'ربع ساعة');
    expect(spokenOffset(30), 'نص ساعة');
    expect(spokenOffset(45), 'تلات أرباع ساعة');
    expect(spokenOffset(60), 'ساعة');
    expect(spokenOffset(120), 'ساعتين');
    expect(spokenOffset(20), '٢٠ دقيقة');
    expect(spokenOffset(-10), '١٠ دقيقة');
  });

  test('قبل / بعد / مع — بالاتجاه وبالمدة', () {
    expect(spokenTimingWording('الفطار', -30), 'قبل الفطار بنص ساعة');
    expect(spokenTimingWording('العشا', 15), 'بعد العشا بربع ساعة');
    expect(spokenTimingWording('الغدا', 0), 'مع الغدا');
    expect(spokenTimingWording('النوم', -20), 'قبل النوم ب٢٠ دقيقة');
    expect(spokenFixedWording('٩:٠٠ م'), 'الساعة ٩:٠٠ م');
  });

  test('مفيش نقطة وسطية ولا رمز الجدول في الكلام', () {
    for (final w in [spokenTimingWording('الفطار', -30), spokenTimingWording('العشا', 45)]) {
      expect(w, isNot(contains('·')));
      expect(w, isNot(contains('−')));
      expect(w, isNot(contains(' د')));
    }
  });
}
