// الروشتة بتقول التوقيت إزاي — وإحنا ما بنختارش ساعة عنها (٢٧ سبتمبر ٢٠٢٦).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_timing.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

void main() {
  test('«كل ١٢ ساعة» → فاصل ١٢، ومفيش ساعات', () {
    final f = parseTimingText('كل ١٢ ساعة');
    expect(f.everyHours, 12);
    expect(f.clockTimes, isEmpty);
    expect(f.unclear, isFalse);
    expect(f.words, ['كل ١٢ ساعة']);
    expect(f.stepHours, 12);
  });

  test('«٣ مرات يوميا بعد الأكل» → ٣ في اليوم + بعد الأكل، ومفيش ساعات', () {
    final f = parseTimingText('٣ مرات يوميا بعد الأكل');
    expect(f.timesPerDay, 3);
    expect(f.mealRelation, MealRelation.after);
    expect(f.clockTimes, isEmpty);
    expect(f.words, ['٣ مرات في اليوم', 'بعد الأكل']);
  });

  test('«الساعة ٨ صباحا» → [٠٨:٠٠] — الساعة المكتوبة بالحرف بس', () {
    final f = parseTimingText('الساعة ٨ صباحا');
    expect(f.clockTimes, [MinuteOfDay.hm(8)]);
    expect(f.unclear, isFalse);
  });

  test('«قبل النوم» → ملاحظة، ومفيش ساعات', () {
    final f = parseTimingText('قبل النوم');
    expect(f.moments, {TimingMoment.bedtime});
    expect(f.clockTimes, isEmpty);
    expect(f.words, ['قبل النوم']);
  });

  test('مش واضح → «مش واضح»، ومفيش ساعات', () {
    for (final s in ['', 'xx؟؟', 'حسب', null]) {
      final f = parseTimingText(s);
      expect(f.unclear, isTrue, reason: '$s');
      expect(f.clockTimes, isEmpty);
    }
  });

  group('حالات تانية من الورق', () {
    test('«١×٣» = ٣ مرات', () => expect(parseTimingText('1×3').timesPerDay, 3));
    test('«مرتين» + «قبل الفطار»', () {
      final f = parseTimingText('مرتين قبل الفطار');
      expect(f.timesPerDay, 2);
      expect(f.mealRelation, MealRelation.before);
      expect(f.stepHours, 12);
    });
    test('«كل ٨ ساعات» = ٣ جرعات، والفاصل ٨', () {
      final f = parseTimingText('كل ٨ ساعات');
      expect(f.dosesPerDay, 3);
      expect(f.stepHours, 8);
    });
    test('«على الريق» = على معدة فاضية', () => expect(parseTimingText('على الريق').mealRelation, MealRelation.emptyStomach));
    test('«الساعة ٩» من غير الصبح/بالليل ما بتتخمّنش', () {
      final f = parseTimingText('الساعة ٩');
      expect(f.clockTimes, isEmpty);
      expect(f.unclear, isTrue);
    });
    test('«الساعة ٩ مساء» = ٢١:٠٠', () => expect(parseTimingText('الساعة ٩ مساء').clockTimes, [MinuteOfDay.hm(21)]));
    test('«عند اللزوم» مش جدول', () {
      final f = parseTimingText('عند اللزوم');
      expect(f.asNeeded, isTrue);
      expect(f.clockTimes, isEmpty);
    });
    test('إنجليزي: «twice daily after meals»', () {
      final f = parseTimingText('twice daily after meals');
      expect(f.timesPerDay, 2);
      expect(f.mealRelation, MealRelation.after);
    });
  });
}
