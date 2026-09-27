// «كلّمني» — الفهم: الجمل اللي وقعت على الجهاز (٢٧ سبتمبر ٢٠٢٦).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/voice/answer_parser.dart' show SpokenTime;
import 'package:fakkarni/domain/voice/nlu/nlu.dart';
import 'package:fakkarni/domain/voice/nlu/normalize.dart';

void main() {
  // الخميس ١ أكتوبر ٢٠٢٦ — «يوم الأحد» = ٤ أكتوبر
  final now = DateTime(2026, 10, 1, 10);
  NluResult u(String s) => understandUtterance(s, now: now);

  group('التطبيع', () {
    test('«كله ١٢ ساعة» / «كلها ٨ ساعات» = «كل»', () {
      expect(normalizeUtterance('وأخذ كله 12 ساعة'), 'واخذ كل 12 ساعه');
      expect(normalizeUtterance('كلها ٨ ساعات'), 'كل 8 ساعات');
      expect(normalizeUtterance('الكلها حلوة'), 'الكلها حلوه', reason: 'مش قبل رقم');
    });
    test('همزات وتاء مربوطة وألف مقصورة وتطويل وتشكيل وأرقام', () {
      expect(normalizeUtterance('أقـرب صيدليّة إلى ٥'), 'اقرب صيدليه الي 5');
    });
  });

  group('أقرب مكان', () {
    for (final (s, place) in [
      ('عايز أقرب صيدلية', NearbyPlace.pharmacy),
      ('أقرب دكتور', NearbyPlace.doctor),
      ('أقرب مستشفى', NearbyPlace.hospital),
      ('أقرب معمل تحاليل', NearbyPlace.lab),
      ('فين أقرب أجزخانة', NearbyPlace.pharmacy),
      ('عايز عيادة قريبة مني', NearbyPlace.doctor),
    ]) {
      test(s, () {
        final r = u(s);
        expect(r.intent, NluIntent.findNearby);
        expect(r.place, place);
      });
    }
  });

  group('ضيف دوا', () {
    test('«عايزك تضيف لي دواء اسمه كونكور وآخده كل ١٢ ساعة»', () {
      final r = u('عايزك تضيف لي دواء اسمه كونكور وآخده كل ١٢ ساعة');
      expect(r.intent, NluIntent.addMedication);
      expect(r.name, 'كونكور');
      expect(r.everyHours, 12);
      expect(r.times, isEmpty, reason: 'ولا ساعة مننا');
    });

    test('«عايزك تضيف لي دواء اسم كونكور وأخذ كله 12 ساعة» — غلطة المتعرّف', () {
      final r = u('عايزك تضيف لي دواء اسم كونكور وأخذ كله 12 ساعة');
      expect(r.intent, NluIntent.addMedication);
      expect(r.name, 'كونكور');
      expect(r.everyHours, 12);
      expect(r.times, isEmpty);
    });

    test('«ضيف دوا جلوكوفاج ٥٠٠ مرتين في اليوم بعد الأكل»', () {
      final r = u('ضيف دوا جلوكوفاج ٥٠٠ مرتين في اليوم بعد الأكل');
      expect(r.intent, NluIntent.addMedication);
      expect(r.name, 'جلوكوفاج');
      expect(r.doseText, '500');
      expect(r.perDay, 2);
      expect(r.food, MealRelation.after);
      expect(r.times, isEmpty);
    });

    test('ساعة بجزء يومها بتتاخد؛ «الساعة ٩» لوحدها ما بتتاخدش', () {
      expect(u('ضيف دوا الضغط الساعة ٩ بالليل').times, [const SpokenTime(21, 0)]);
      final r = u('ضيف دوا الضغط الساعة ٩');
      expect(r.times, isEmpty);
      expect(r.hourNeedsPeriod, 9);
    });

    test('«لمدة أسبوع» ومدة بالأيام', () {
      expect(u('ضيف دوا أوجمنتين مرتين لمدة أسبوع').durationDays, 7);
      expect(u('ضيف دوا أوجمنتين لمدة ٥ أيام').durationDays, 5);
    });

    test('الجرعة عمرها ما تدخل في الاسم', () {
      final r = u('ضيفلي دوا كونكور ٥ مجم الصبح');
      expect(r.name, 'كونكور');
      expect(r.doseText, '5 مجم');
    });

    for (final s in ['ضيف دوا لا', 'ضيف دوا أيوه', 'ضيف دوا آه', 'ضيف دوا مش عارف']) {
      test('«$s» — مش اسم', () {
        final r = u(s);
        expect(r.intent, NluIntent.addMedication);
        expect(r.name, isNull);
      });
    }
  });

  group('احجز ميعاد', () {
    test('«احجزلي ميعاد عند الدكتور حسن»', () {
      final r = u('احجزلي ميعاد عند الدكتور حسن');
      expect(r.intent, NluIntent.bookAppointment);
      expect(r.doctorName, 'د. حسن');
      expect(r.date, isNull);
      expect(r.time, isNull);
    });

    test('«… يوم الأحد الساعة ٥ العصر» → الأحد الجاي ١٧:٠٠', () {
      final r = u('احجزلي ميعاد عند الدكتور حسن يوم الأحد الساعة ٥ العصر');
      expect(r.intent, NluIntent.bookAppointment);
      expect(r.doctorName, 'د. حسن');
      expect(r.date, DateTime(2026, 10, 4));
      expect(r.time, const SpokenTime(17, 0));
    });

    test('«دكتور عيون» = تخصص مش اسم', () {
      final r = u('احجز كشف دكتور عيون بكرة');
      expect(r.intent, NluIntent.bookAppointment);
      expect(r.specialty, 'عيون');
      expect(r.doctorName, isNull);
      expect(r.date, DateTime(2026, 10, 2));
    });

    test('«٥ أكتوبر» و«الأحد الجاي»', () {
      expect(u('احجزلي ميعاد يوم ٥ أكتوبر').date, DateTime(2026, 10, 5));
      expect(u('احجزلي ميعاد الأحد الجاي').date, DateTime(2026, 10, 4));
    });
  });

  group('احجز تحليل', () {
    test('«احجزلي معمل تحليل سكر بكرة»', () {
      final r = u('احجزلي معمل تحليل سكر بكرة');
      expect(r.intent, NluIntent.bookLab);
      expect(r.testName, 'سكر');
      expect(r.date, DateTime(2026, 10, 2));
    });
    test('«احجز تحليل صورة دم في معمل البرج»', () {
      final r = u('احجز تحليل صورة دم في معمل البرج');
      expect(r.intent, NluIntent.bookLab);
      expect(r.testName, 'صوره دم');
      expect(r.labName, 'البرج');
    });
  });

  group('مش مفهوم', () {
    for (final s in ['', 'لا', 'أيوه', 'الجو حلو النهارده']) {
      test('«$s»', () => expect(u(s).intent, NluIntent.none));
    }
  });
}
