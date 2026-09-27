import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

Map<String, dynamic> field(Object? value, double confidence, {String? note}) => {
      'value': value,
      'confidence': confidence,
      'note': ?note,
    };

Map<String, dynamic> med({
  required Map<String, dynamic> name,
  required Map<String, dynamic> amount,
  required Map<String, dynamic> timing,
  Map<String, dynamic>? duration,
}) =>
    {
      'name': name,
      'amount': amount,
      'timing': timing,
      'durationDays': duration ?? field(null, 1),
    };

void main() {
  group('التعليمات (الجولة اللي ملت الفورم من الورقة)', () {
    test('مكتوبة → بتتقرا بثقتها، ومش مكتوبة → null بثقة كاملة مش «محتاج تحديد»', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          {
            ...med(
              name: field('Augmentin 1g', 0.95),
              amount: field('قرص', 0.9),
              timing: {'text': 'بعد الفطار', 'confidence': 0.9},
            ),
            'instructions': field('مع كوباية مية كاملة', 0.9),
          },
          {
            ...med(
              name: field('Concor 5mg', 0.95),
              amount: field('قرص', 0.9),
              timing: {'text': 'بعد الفطار', 'confidence': 0.9},
            ),
            'instructions': field(null, 1),
          },
          med(
            name: field('Panadol', 0.95),
            amount: field('قرص', 0.9),
            timing: {'text': 'مع العشا', 'confidence': 0.9},
          ),
        ],
      }).lines;
      expect(line[0].instructions.value, 'مع كوباية مية كاملة');
      expect(line[0].instructions.needsReview, isFalse);
      expect(line[1].instructions.value, isNull);
      expect(line[1].instructions.needsReview, isFalse);
      expect(line[2].instructions.value, isNull, reason: 'مفتاح ناقص خالص = مش مكتوبة');
      expect(line[2].needsReview, isFalse, reason: 'التعليمات ما بتحجزش «تمام»');
    });

    test('الـschema بيطلبها كحقل مطلوب بقيمة nullable، والبرومبت بيقول «اليوم فقط» = يوم', () {
      final item = (prescriptionSchema['properties'] as Map)['medications']['items'] as Map;
      expect((item['properties'] as Map).containsKey('instructions'), isTrue);
      expect(item['required'], contains('instructions'));
      expect(GeminiPrescriptionReader.prompt, contains('instructions'));
      expect(GeminiPrescriptionReader.prompt, contains('اليوم فقط'));
      expect(GeminiPrescriptionReader.prompt, contains('Never invent one'));
    });
  });

  group('قراءة واضحة', () {
    final reading = PrescriptionReading.fromJson({
      'doctor': field('هشام سلام', 0.9),
      'medications': [
        med(
          name: field('Concor 5mg', 0.96),
          amount: field('قرص واحد', 0.91),
          timing: {'text': 'بعد الفطار', 'confidence': 0.93},
          duration: field(30, 0.88),
        ),
      ],
    });

    test('كل الحقول فوق العتبة → مفيش «محتاج تحديد»', () {
      final line = reading.lines.single;
      expect(line.needsReview, isFalse);
      expect(line.name.value, 'Concor 5mg');
      expect(line.amount.value, 'قرص واحد');
      expect(line.timings.value, isEmpty, reason: 'الورقة ما كتبتش ساعة — مفيش ساعة مننا');
      expect(line.mealRelation, MealRelation.after);
      expect(line.duration.value, 30);
      expect(reading.doctor.value, 'هشام سلام');
    });
  });

  group('التوقيت — الروشتة عمرها ما بتختار ساعة (٢٧ سبتمبر ٢٠٢٦)', () {
    ReadLine lineOf(Map<String, dynamic> timing) => PrescriptionReading.fromJson({
          'medications': [med(name: field('X', 0.9), amount: field('قرص', 0.9), timing: timing)],
        }).lines.single;

    test('«كل ١٢ ساعة» → فاصل ١٢، والساعات فاضية', () {
      final line = lineOf({'text': 'كل ١٢ ساعة', 'confidence': 0.9});
      expect(line.facts.everyHours, 12);
      expect(line.timings.value, isEmpty);
      expect(line.timings.needsReview, isFalse, reason: 'مفيش ساعة مقروءة يتشك فيها');
      expect(line.timesFromPaper, isFalse);
    });

    test('«٣ مرات يوميا بعد الأكل» → ٣ + بعد الأكل، والساعات فاضية', () {
      final line = lineOf({'text': '٣ مرات يوميا بعد الأكل', 'confidence': 0.99});
      expect(line.facts.timesPerDay, 3);
      expect(line.mealRelation, MealRelation.after);
      expect(line.timings.value, isEmpty);
    });

    test('«الساعة ٨ صباحا» → [٠٨:٠٠] من الروشتة', () {
      final line = lineOf({'text': 'الساعة ٨ صباحا', 'confidence': 0.9});
      expect(line.timings.value, [FixedTiming(MinuteOfDay.hm(8))]);
      expect(line.timesFromPaper, isTrue);
    });

    test('«قبل النوم» → ملاحظة، والساعات فاضية', () {
      final line = lineOf({'text': 'قبل النوم', 'confidence': 0.9});
      expect(line.facts.words, ['قبل النوم']);
      expect(line.timings.value, isEmpty);
    });

    test('مش واضح → «مش واضح»، والساعات فاضية', () {
      final line = lineOf({'text': null, 'unclear': true, 'confidence': 0.2, 'note': 'مش متأكد — اسأل الصيدلي'});
      expect(line.facts.unclear, isTrue);
      expect(line.timings.value, isEmpty);
      expect(line.timings.note, unclearTimingNote);
    });

    test('الحقول المنظّمة بتكمّل الكلام — ومش بتطلّع ساعة', () {
      final line = lineOf({'text': '1×2', 'mealRelation': 'before', 'confidence': 0.9});
      expect(line.facts.timesPerDay, 2);
      expect(line.mealRelation, MealRelation.before);
      expect(line.timings.value, isEmpty);
    });

    test('ساعة بشكل غلط → بتترمي، مش بتتقبل غلط', () {
      final line = lineOf({'text': null, 'clockTimes': ['25:99'], 'confidence': 0.9});
      expect(line.timings.value, isEmpty);
      expect(line.facts.unclear, isTrue);
    });

    test('البرومبت بيمنع تحويل «كام مرة» لساعات، والـschema مالوش مرساة', () {
      expect(GeminiPrescriptionReader.prompt, contains('NEVER convert a frequency into clock times'));
      final timing = ((prescriptionSchema['properties'] as Map)['medications']['items']['properties'] as Map)['timing'] as Map;
      final props = (timing['properties'] as Map).keys;
      expect(props, containsAll(['text', 'clockTimes', 'everyHours', 'timesPerDay', 'mealRelation', 'moment', 'unclear']));
      expect(props, isNot(contains('anchor')));
    });
  });

  group('المدة — القاعدة التالتة', () {
    test('مش مكتوبة → مفتوحة بثقة كاملة، مش نقص', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(name: field('Concor', 0.9), amount: field('قرص', 0.9), timing: {'text': 'بعد الفطار', 'confidence': 0.9}),
        ],
      }).lines.single;
      expect(line.duration.value, isNull);
      expect(line.duration.needsReview, isFalse);
    });

    test('مدة صفر أو بالسالب → مفتوحة', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('Concor', 0.9),
            amount: field('قرص', 0.9),
            timing: {'text': 'بعد الفطار', 'confidence': 0.9},
            duration: field(0, 0.9),
          ),
        ],
      }).lines.single;
      expect(line.duration.value, isNull);
    });
  });

  group('الثقة والنقص', () {
    test('ثقة تحت ٠٫٨ → محتاج تحديد، وفوقها لأ', () {
      expect(const ReadField<String>(value: 'x', confidence: 0.79).needsReview, isTrue);
      expect(const ReadField<String>(value: 'x', confidence: 0.8).needsReview, isFalse);
      // قيمة null بثقة كاملة = «مش مكتوب عن قصد» (زي المدة المفتوحة) — مش نقص
      expect(const ReadField<String>(value: null, confidence: 1).needsReview, isFalse);
      expect(const ReadField<String>.missing().needsReview, isTrue);
    });

    test('اسم فاضي أو JSON ناقص → محتاج تحديد بدل ما يرمي', () {
      final reading = PrescriptionReading.fromJson({
        'medications': [
          {'name': field('  ', 0.9), 'timing': 'غلط'},
          'مش object',
        ],
      });
      expect(reading.lines.length, 1);
      expect(reading.lines.single.name.needsReview, isTrue);
      expect(reading.lines.single.amount.needsReview, isTrue);
      expect(reading.lines.single.timings.value, isEmpty, reason: 'توقيت مش مفهوم = مفيش ساعات');
      expect(reading.lines.single.facts.unclear, isTrue);
    });

    test('من غير medications خالص → قراءة فاضية', () {
      expect(PrescriptionReading.fromJson(jsonDecode('{}') as Map<String, dynamic>).isEmpty, isTrue);
    });
  });

  group('ساعات «كام مرة» الافتراضية — للفورم و«كلّمني» بس، مش للروشتة', () {
    test('مرة ٩ص، مرتين ٩ص و٩م، ٣ مرات ٩ و٣ و٩، ٤ مرات ٨ و١ و٦ و١١', () {
      List<int> m(int n) => [for (final t in defaultTimesFor(n)) t.minuteOfDay.minutes];
      expect(m(1), [9 * 60]);
      expect(m(2), [9 * 60, 21 * 60]);
      expect(m(3), [9 * 60, 15 * 60, 21 * 60]);
      expect(m(4), [8 * 60, 13 * 60, 18 * 60, 23 * 60]);
      expect(m(6).first, 8 * 60);
      expect(m(6).last, 23 * 60);
    });

    test('قبل / مع / بعد الأكل / على الريق كلمة — و«قبل النوم» مش أكل', () {
      MealRelation? meal(String text) => PrescriptionReading.fromJson({
            'medications': [med(name: field('X', 0.9), amount: field('قرص', 0.9), timing: {'text': text, 'confidence': 0.9})],
          }).lines.single.mealRelation;
      expect(meal('قبل الفطار'), MealRelation.before);
      expect(meal('مع الغدا'), MealRelation.with_);
      expect(meal('بعد العشا'), MealRelation.after);
      expect(meal('على الريق'), MealRelation.emptyStomach);
      expect(meal('قبل النوم'), isNull);
    });
  });

  group('اللي بيقفل «تمام» واللي لأ', () {
    final ok = field('x', 0.95);

    test('جرعة مش معروفة → محتاج تحديد بس ما بتقفلش', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(name: field('Telfast 180', 0.95), amount: field(null, 0), timing: {'text': 'بعد العشا', 'confidence': 0.9}),
        ],
      }).lines.single;
      expect(line.amount.needsReview, isTrue);
      expect(line.needsReview, isTrue);
      expect(line.blocksConfirm, isFalse);
    });

    test('اسم مش واضح → بيقفل؛ توقيت مش واضح ما بيقفلش القراية — الإنسان بيختار الساعات', () {
      final noTiming = PrescriptionReading.fromJson({
        'medications': [med(name: ok, amount: ok, timing: {'confidence': 0.1})],
      }).lines.single;
      expect(noTiming.blocksConfirm, isFalse);
      expect(noTiming.timings.value, isEmpty);

      final weakName = PrescriptionReading.fromJson({
        'medications': [med(name: field('C?nc?r', 0.3), amount: ok, timing: {'text': 'قبل الغدا', 'confidence': 0.9})],
      }).lines.single;
      expect(weakName.blocksConfirm, isTrue);
    });
  });
}
