// اتكتب الأول **قياساً** لسلوك التقارير الكتيرة الكلام (خطوة ٢، ٥ أكتوبر
// ٢٠٢٦ مساءً)، وجزء التواريخ اتقلب عمداً مع إصلاح المرحلة ١ (المالك 2A):
// حد السنين وحارس المستقبل بقوا زي الروشتة. والنتيجة النصية («Negative»)
// اتصلّحت في المرحلة ٥ — ليها خانتها (valueText) ومش بتقفل «تمام»؛ اللي
// فاضل هنا قياسها هو حالة موديل بيحطّها في خانة **الرقم** غلط.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reading.dart';

Map<String, dynamic> field(dynamic value, [double confidence = 0.99]) =>
    {'value': value, 'confidence': confidence};

Map<String, dynamic> reportWith({dynamic value, dynamic reportDate}) => {
  if (reportDate != null) 'reportDate': field(reportDate),
  'results': [
    {
      'test': field('Albumin'),
      'value': field(value),
      'unit': field(null, 0),
      'refLow': field(null, 0),
      'refHigh': field(null, 0),
      'refText': field('Negative'),
    },
  ],
};

void main() {
  // النهارده الثابت بتاع الاختبارات — بيتحقن في fromJson عشان حارس المستقبل
  final today = DateTime(2026, 10, 5, 14);

  test('(ب) بعد المرحلة ٥: نص في خانة **الرقم** غلط (مخالفة للبرومبت) لسه بيقفل «تمام» — '
      'والطريق الصح valueText مفتوح', () {
    final wrongSlot = LabReading.fromJson(reportWith(value: 'Negative'), now: today);
    final line = wrongSlot.lines.single;
    // _number ما بيعرفش يقرا غير رقم — النص في الخانة الغلط بيضيع وثقته بتصفّر،
    // ومن غير valueText السطر مالوش نتيجة واضحة فبيقفل. مفيش تخمين.
    expect(line.value.value, isNull);
    expect(line.value.confidence, 0);
    expect(line.blocksConfirm, isTrue, reason: 'نص في خانة الرقم مش نتيجة — بيتراجع بإيد إنسان');
    expect(line.refText.value, 'Negative');

    // ونفس النتيجة في خانتها الصح (المرحلة ٥) بتعدّي: بالحرف، ومش بتقفل.
    final report = reportWith(value: null);
    (report['results'] as List).single['valueText'] = field('Negative');
    final right = LabReading.fromJson(report, now: today).lines.single;
    expect(right.textResult, 'Negative');
    expect(right.blocksConfirm, isFalse);
  });

  test('(ج١) اتصلّح: تاريخ في المستقبل («١٢/٠٩» اتقرت أمريكي) = مراجعة — مش تاريخ غلط صامت', () {
    final reading = LabReading.fromJson(
      reportWith(value: 1.2, reportDate: '2026-12-09'),
      now: today,
    );
    expect(reading.date.value, DateTime(2026, 12, 9), reason: 'القيمة موجودة — مش مخفية');
    expect(reading.date.needsReview, isTrue,
        reason: 'تقرير معمل عن حاجة حصلت — المستقبل ثقته صفر والشاشة بتقع على النهارده بالذهبي');
  });

  test('(ج١ب) تاريخ ماضي سليم بثقة عالية بيعدّي زي ما هو — والنهارده نفسه مش «مستقبل»', () {
    for (final (d, want) in [('2026-09-12', DateTime(2026, 9, 12)), ('2026-10-05', DateTime(2026, 10, 5))]) {
      final reading = LabReading.fromJson(reportWith(value: 1.2, reportDate: d), now: today);
      expect(reading.date.value, want, reason: d);
      expect(reading.date.needsReview, isFalse, reason: d);
    }
  });

  test('قياس (ج٢): تاريخ مش ISO («12/09/2026») بيبقى مفقود — والشاشة بتقول «هيتسجّل بتاريخ النهارده»', () {
    final reading = LabReading.fromJson(
      reportWith(value: 1.2, reportDate: '12/09/2026'),
      now: today,
    );
    expect(reading.date.value, isNull);
    expect(reading.date.confidence, 0);
  });

  test('(ج٣) اتصلّح: حد سنين زي الروشتة — ١٩٢٦ و٢١٢٦ بيرجعوا مفقودين', () {
    for (final y in ['1926-12-09', '2126-01-01']) {
      final reading = LabReading.fromJson(reportWith(value: 1.2, reportDate: y), now: today);
      expect(reading.date.value, isNull, reason: y);
      expect(reading.date.confidence, 0, reason: y);
    }
  });

  test('البرومبت بيقول للموديل إن الورق المصري يوم/شهر — الجملة نفسها هي العقد، زي تثبيتات الشريط', () {
    final src = File('lib/ai/lab_reader.dart').readAsStringSync();
    for (final s in [
      'DAY/MONTH',
      '12 September, never December 9',
      'confidence below 0.8',
    ]) {
      expect(src.contains(s), isTrue, reason: s);
    }
  });
}
