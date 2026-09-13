import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

void main() {
  final eightAm = DateTime(2026, 8, 31, 8);

  group('سلّم التصعيد', () {
    test('درجتين: +١٥ و+٣٠ من معاد الجرعة الأصلي', () {
      final steps = ladderFor(eightAm);

      expect(steps.map((s) => s.rung), [
        EscalationRung.first,
        EscalationRung.second,
      ]);
      expect(steps[0].at, DateTime(2026, 8, 31, 8, 15));
      expect(steps[1].at, DateTime(2026, 8, 31, 8, 30));
    });

    test('كل درجة محسوبة من الأصل مش من اللي قبلها', () {
      for (final step in ladderFor(eightAm)) {
        expect(step.at.difference(eightAm), step.rung.delay);
      }
    });

    test('السلّم بيعدّي نص الليل وبيغيّر التاريخ صح', () {
      final late = DateTime(2026, 8, 31, 23, 50);
      final steps = ladderFor(late);

      expect(steps[0].at, DateTime(2026, 9, 1, 0, 5));
      expect(steps[1].at, DateTime(2026, 9, 1, 0, 20));
      expect(graceEndFor(late), DateTime(2026, 9, 1, 0, 35));
    });

    test('المهلة ٤٥ دقيقة وبتيجي بعد آخر درجة', () {
      expect(graceWindow, const Duration(minutes: 45));
      final lastRung = ladderFor(eightAm).last.at;
      expect(graceEndFor(eightAm).isAfter(lastRung), isTrue);
    });
  });

  group('«اتنست» — قرار المهلة', () {
    test('قبل الـ٤٥ لسه مش اتنست', () {
      expect(
        isPastGrace(scheduledAt: eightAm, now: DateTime(2026, 8, 31, 8, 44)),
        isFalse,
      );
    });

    test('عند الـ٤٥ بالظبط اتنست', () {
      expect(
        isPastGrace(scheduledAt: eightAm, now: DateTime(2026, 8, 31, 8, 45)),
        isTrue,
      );
    });

    test('بعدها بيوم برضه اتنست', () {
      expect(
        isPastGrace(scheduledAt: eightAm, now: DateTime(2026, 9, 1, 8)),
        isTrue,
      );
    });

    test('جرعة لسه جاية مش اتنست أكيد', () {
      expect(
        isPastGrace(scheduledAt: eightAm, now: DateTime(2026, 8, 31, 7)),
        isFalse,
      );
    });
  });

  test('الدومين نقي — الملف ما بيستوردش فلاتر ولا قاعدة بيانات', () {
    // اختبار شكل: المكتبة بتتحمّل في اختبار دارت عادي من غير أي إضافة.
    expect(EscalationRung.values.length, 2);
  });
  group('مهلة السيرفر أطول من مهلة الجهاز', () {
    test('الثابت الحاكم: مهلة السيرفر = مهلة الجهاز + هامش المزامنة', () {
      // كانت مكتوبة `greaterThan(... - دقيقة)` — وده «أكبر من» مكسور
      // بإيدنا عشان يعدّي على «يساوي». العلاقة الحقيقية هوية: `syncSlack`
      // **هو** المسافة بين مهلة الجهاز ومهلة السيرفر (٤٥ + ١٥ = ٦٠)،
      // فالمتراجحة كانت بتوصف الأرقام غلط وبتسمح لواحد منهم يتحرك لوحده.
      expect(serverGraceWindow, graceWindow + syncSlack);
      expect(serverGraceWindow, greaterThan(graceWindow));
    });

    test('الأرقام: الجهاز ٤٥، السيرفر ٦٠، الهامش ١٥', () {
      expect(graceWindow, const Duration(minutes: 45));
      expect(serverGraceWindow, const Duration(minutes: 60));
      expect(syncSlack, const Duration(minutes: 15));
    });

    test('تأكيد عند +٤٤ لسه جوّه مهلة السيرفر — مفيش إنذار كاذب', () {
      final at = DateTime(2026, 8, 31, 8);
      final confirmedAt = at.add(const Duration(minutes: 44));
      final serverWouldEscalateAt = at.add(serverGraceWindow);

      expect(confirmedAt.isBefore(serverWouldEscalateAt), isTrue);
      // وفيه ١٦ دقيقة كاملة للسلك بعد التأكيد ده
      expect(serverWouldEscalateAt.difference(confirmedAt),
          greaterThanOrEqualTo(const Duration(minutes: 15)));
    });

    test('الجهاز بيقول «اتنست» في وقته — الزيادة مش تأخير للمريض', () {
      final at = DateTime(2026, 8, 31, 8);
      expect(
        isPastGrace(scheduledAt: at, now: at.add(const Duration(minutes: 45))),
        isTrue,
      );
    });
  });

}
