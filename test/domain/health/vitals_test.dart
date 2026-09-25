import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/vitals.dart';
import 'package:fakkarni/features/health/usual_words.dart' show adviceWords;

void main() {
  final now = DateTime(2026, 9, 25, 12);
  Vital v(VitalKind k, double value, int daysAgo, {double? dia, int? pulse}) =>
      Vital(kind: k, value: value, value2: dia, pulse: pulse, measuredAt: now.subtract(Duration(days: daysAgo)));

  group('الكتابة', () {
    test('أرقام عربي وفاصلة عربي', () {
      expect(parseVitalNumber('٧٢٫٥'), 72.5);
      expect(parseVitalNumber('37,2'), 37.2);
      expect(parseVitalNumber('abc'), isNull);
    });

    test('برّه اللي الأجهزة بتقراه → «الرقم ده غريب — راجعه»', () {
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.spo2, value: 97)), isNull);
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.spo2, value: 140)), 'الرقم ده غريب — راجعه');
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.temperature, value: 50)), 'الرقم ده غريب — راجعه');
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.weight, value: 72.5)), isNull);
    });

    test('الضغط: الرقمين لازم، والصغير أصغر من الكبير، والنبض الاختياري بحدوده', () {
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.bloodPressure, value: 130)), 'اكتب الرقم التاني كمان');
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.bloodPressure, value: 130, value2: 85)), isNull);
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.bloodPressure, value: 80, value2: 120)), isNotNull);
      expect(vitalEntryProblem(const VitalEntry(kind: VitalKind.bloodPressure, value: 130, value2: 85, pulse: 400)), isNotNull);
    });
  });

  group('المعتاد ليك والفرق', () {
    test('محتاج ٣ في آخر ٣٠ يوم — وإلا بيقول كده', () {
      final two = [v(VitalKind.weight, 70, 1), v(VitalKind.weight, 72, 2)];
      expect(vitalUsual(two, VitalKind.weight, now), isNull);
      expect(vitalUsualLine(null, VitalKind.weight), contains('لسه ما عندناش قياسات كفاية'));
      final old = [...two, v(VitalKind.weight, 90, 40)];
      expect(vitalUsual(old, VitalKind.weight, now), isNull, reason: 'اللي أقدم من ٣٠ يوم مش محسوب');
    });

    test('المتوسط بتاعه هو، والفرق رقم بإشارة — من غير «عالي» ولا «واطي»', () {
      final all = [v(VitalKind.weight, 70, 1), v(VitalKind.weight, 72, 2), v(VitalKind.weight, 74, 3)];
      final usual = vitalUsual(all, VitalKind.weight, now)!;
      expect(usual.average, 72);
      expect(vitalUsualLine(usual, VitalKind.weight), 'المعتاد ليك (متوسط آخر ٣٠ يوم): ٧٢ كيلو');
      expect(vitalDifferenceLine(v(VitalKind.weight, 73.5, 0), usual), 'الفرق عن المعتاد ليك: +١٫٥');
      expect(vitalDifferenceLine(v(VitalKind.weight, 72, 0), usual), 'الفرق عن المعتاد ليك: زي المعتاد');
    });

    test('الضغط: متوسطين وفرقين', () {
      final all = [
        v(VitalKind.bloodPressure, 120, 1, dia: 80),
        v(VitalKind.bloodPressure, 130, 2, dia: 84),
        v(VitalKind.bloodPressure, 125, 3, dia: 82),
      ];
      final usual = vitalUsual(all, VitalKind.bloodPressure, now)!;
      expect((usual.average, usual.average2), (125, 82));
      expect(vitalDifferenceLine(v(VitalKind.bloodPressure, 135, 0, dia: 80), usual), 'الفرق عن المعتاد ليك: +١٠ / −٢');
      expect(vitalValueText(v(VitalKind.bloodPressure, 130, 0, dia: 85, pulse: 72)), '١٣٠/٨٥ مم زئبق — نبض ٧٢');
    });
  });

  test('الرسم: الفترة بتقصّ، والضغط خطين', () {
    final all = [
      v(VitalKind.bloodPressure, 120, 1, dia: 80),
      v(VitalKind.bloodPressure, 130, 20, dia: 85),
      v(VitalKind.bloodPressure, 140, 60, dia: 90),
    ];
    expect(vitalSeries(all, VitalKind.bloodPressure, now, 7).first, hasLength(1));
    expect(vitalSeries(all, VitalKind.bloodPressure, now, 30).first, hasLength(2));
    expect(vitalSeries(all, VitalKind.bloodPressure, now, 90).second, hasLength(3));
  });

  test('آخر قياس لكل نوع بترتيب الأنواع', () {
    final latest = latestVitals([v(VitalKind.weight, 70, 3), v(VitalKind.weight, 71, 1), v(VitalKind.pulse, 72, 2)]);
    expect(latest.map((x) => x.kind), [VitalKind.pulse, VitalKind.weight]);
    expect(latest.last.value, 71);
  });

  test('**الخطوط الحمرا**: ولا كلمة حكم ولا نصيحة في كلام القياسات — إلا «اسأل دكتورك» بس', () {
    final files = [
      'lib/domain/health/vitals.dart',
      ...Directory('lib/features/health/vitals').listSync().whereType<File>().map((f) => f.path),
      'lib/features/care/caregiver_vitals_screen.dart',
      'lib/features/nurse/nurse_vitals_screen.dart',
    ];
    final literal = RegExp(r"'([^'\\]|\\.)*'");
    for (final path in files) {
      final lines = File(path).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//'));
      for (final m in lines.expand((l) => literal.allMatches(l))) {
        final text = m.group(0)!;
        if (text.contains('اسأل دكتورك')) continue; // الجملة المسموحة الوحيدة (C3)
        for (final word in adviceWords) {
          expect(text.contains(word), isFalse, reason: '$path: «$word» في $text');
        }
      }
    }
    expect(vitalsAskDoctor, contains('اسأل دكتورك'));
  });
}
