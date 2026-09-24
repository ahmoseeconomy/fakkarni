import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
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
              timing: {'anchor': 'breakfast', 'relation': 'after', 'confidence': 0.9},
            ),
            'instructions': field('مع كوباية مية كاملة', 0.9),
          },
          {
            ...med(
              name: field('Concor 5mg', 0.95),
              amount: field('قرص', 0.9),
              timing: {'anchor': 'breakfast', 'relation': 'after', 'confidence': 0.9},
            ),
            'instructions': field(null, 1),
          },
          med(
            name: field('Panadol', 0.95),
            amount: field('قرص', 0.9),
            timing: {'anchor': 'dinner', 'relation': 'at', 'confidence': 0.9},
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
          timing: {'anchor': 'breakfast', 'relation': 'after', 'confidence': 0.93},
          duration: field(30, 0.88),
        ),
      ],
    });

    test('كل الحقول فوق العتبة → مفيش «محتاج تحديد»', () {
      final line = reading.lines.single;
      expect(line.needsReview, isFalse);
      expect(line.name.value, 'Concor 5mg');
      expect(line.amount.value, 'قرص واحد');
      expect(line.timings.value, [const AnchorTiming(DayAnchor.breakfast, 0)]);
      expect(line.duration.value, 30);
      expect(reading.doctor.value, 'هشام سلام');
    });
  });

  group('التوقيت — القاعدة الأولى', () {
    test('قبل الأكل من غير دقايق → الإزاحة الافتراضية ٣٠', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('Antodine', 0.9),
            amount: field('قرص', 0.9),
            timing: {'anchor': 'lunch', 'relation': 'before', 'confidence': 0.9},
          ),
        ],
      }).lines.single;
      expect(line.timings.value, [const AnchorTiming(DayAnchor.lunch, -30)]);
    });

    test('ساعة مكتوبة بالحرف → ثابتة، مش مرساة', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('Eltroxin', 0.9),
            amount: field('قرص', 0.9),
            timing: {'clockTime': '06:30', 'confidence': 0.9},
          ),
        ],
      }).lines.single;
      expect(line.timings.value, [FixedTiming(MinuteOfDay.hm(6, 30))]);
      expect(line.timings.needsReview, isFalse);
    });

    test('«١×٣» من غير وجبة → تلات مراسي، ومعلّمة «محتاج تحديد» مهما كانت الثقة', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('Augmentin', 0.9),
            amount: field('قرص', 0.9),
            timing: {'timesPerDay': 3, 'relation': 'after', 'confidence': 0.99},
          ),
        ],
      }).lines.single;
      expect(
        line.timings.value,
        [
          const AnchorTiming(DayAnchor.breakfast, 0),
          const AnchorTiming(DayAnchor.lunch, 0),
          const AnchorTiming(DayAnchor.dinner, 0),
        ],
      );
      expect(line.timings.needsReview, isTrue, reason: 'اقتراح توزيع، مش قراءة');
      expect(line.timings.note, timesPerDayNote);
    });

    test('توقيت غامض أو «عند اللزوم» → «مش متأكد — اسأل الصيدلي»، مفيش تخمين', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('Cataflam', 0.9),
            amount: field('قرص', 0.9),
            timing: {'confidence': 0.2, 'note': 'مش متأكد — اسأل الصيدلي'},
          ),
        ],
      }).lines.single;
      expect(line.timings.value, isNull);
      expect(line.timings.needsReview, isTrue);
      expect(line.timings.note, unclearTimingNote);
      expect(line.needsReview, isTrue);
    });

    test('ساعة بشكل غلط → محتاج تحديد بدل ما تتقبل غلط', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(
            name: field('X', 0.9),
            amount: field('قرص', 0.9),
            timing: {'clockTime': '25:99', 'confidence': 0.9},
          ),
        ],
      }).lines.single;
      expect(line.timings.value, isNull);
      expect(line.timings.needsReview, isTrue);
    });
  });

  group('المدة — القاعدة التالتة', () {
    test('مش مكتوبة → مفتوحة بثقة كاملة، مش نقص', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(name: field('Concor', 0.9), amount: field('قرص', 0.9), timing: {'anchor': 'breakfast', 'confidence': 0.9}),
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
            timing: {'anchor': 'breakfast', 'confidence': 0.9},
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
      expect(reading.lines.single.timings.needsReview, isTrue);
    });

    test('من غير medications خالص → قراءة فاضية', () {
      expect(PrescriptionReading.fromJson(jsonDecode('{}') as Map<String, dynamic>).isEmpty, isTrue);
    });
  });

  group('الإزاحة الافتراضية «قبل» — ٣٠ للأكل و١٥ للنوم', () {
    ReadLine before(String anchor) => PrescriptionReading.fromJson({
          'medications': [
            med(
              name: field('X', 0.9),
              amount: field('قرص', 0.9),
              timing: {'anchor': anchor, 'relation': 'before', 'confidence': 0.9},
            ),
          ],
        }).lines.single;

    test('قبل النوم → −١٥', () {
      expect(before('sleep').timings.value, [const AnchorTiming(DayAnchor.sleep, -15)]);
    });

    test('قبل الغدا → −٣٠', () {
      expect(before('lunch').timings.value, [const AnchorTiming(DayAnchor.lunch, -30)]);
    });

    test('المحرر والقارئ بيستخدموا نفس الدالة', () {
      expect(defaultOffsetBefore(DayAnchor.sleep), 15);
      expect(defaultOffsetBefore(DayAnchor.breakfast), 30);
    });
  });

  group('اللي بيقفل «تمام» واللي لأ', () {
    final ok = field('x', 0.95);

    test('جرعة مش معروفة → محتاج تحديد بس ما بتقفلش', () {
      final line = PrescriptionReading.fromJson({
        'medications': [
          med(name: field('Telfast 180', 0.95), amount: field(null, 0), timing: {'anchor': 'dinner', 'confidence': 0.9}),
        ],
      }).lines.single;
      expect(line.amount.needsReview, isTrue);
      expect(line.needsReview, isTrue);
      expect(line.blocksConfirm, isFalse);
    });

    test('توقيت أو اسم مش واضح → بيقفل', () {
      final noTiming = PrescriptionReading.fromJson({
        'medications': [med(name: ok, amount: ok, timing: {'confidence': 0.1})],
      }).lines.single;
      expect(noTiming.blocksConfirm, isTrue);

      final weakName = PrescriptionReading.fromJson({
        'medications': [med(name: field('C?nc?r', 0.3), amount: ok, timing: {'anchor': 'lunch', 'confidence': 0.9})],
      }).lines.single;
      expect(weakName.blocksConfirm, isTrue);
    });
  });
}
