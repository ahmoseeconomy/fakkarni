import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

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
}
