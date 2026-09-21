import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/features/care/caregiver_status.dart';

import 'caregiver_screen_test.dart' show alert, event, now, snapshot;

/// حساب أعلى الشاشة — **أرقام، من غير ما نرسم حاجة**.
///
/// الحالات الحدّية هنا هي اللي بتكدب بسهولة على العين: يوم لسه ماشي،
/// جرعة جاية، أسبوع ناقص، صورة فاضية. أسهل تتكتب كأرقام.
void main() {
  CaregiverSnapshot withEvents(List<CaregiverDoseEvent> e, {List<CaregiverAlert> a = const []}) =>
      snapshot(e, alerts: a);

  group('الإجابة في كلمة', () {
    test('مفيش ولا صف → مش «تمام» ومش «مش تمام»', () {
      final s = careStatus(withEvents(const []), now);
      expect(s.state, CareState.noData);
      expect(s.lastTaken, isNull);
    });

    test('كل جرعات النهارده اتقفلت → تمام', () {
      final s = careStatus(
        withEvents([
          event('Concor', DateTime(2026, 8, 31, 8), 'taken', actedAt: DateTime(2026, 8, 31, 8, 5)),
          event('Telfast', DateTime(2026, 8, 31, 12), 'skipped'),
          // جاية بعد «دلوقتي» — مش نقص
          event('Glucophage', DateTime(2026, 8, 31, 20), 'pending'),
        ]),
        now,
      );
      expect(s.state, CareState.allGood);
      expect(s.unconfirmedToday, 0);
      expect(s.takenToday, 1);
      expect(s.dosesToday, 3);
    });

    test('جرعة عدّى وقتها من غير تأكيد → محتاجة انتباه', () {
      final s = careStatus(
        withEvents([event('Concor', DateTime(2026, 8, 31, 8), 'pending')]),
        now,
      );
      expect(s.state, CareState.needsAttention);
      expect(s.unconfirmedToday, 1);
    });

    test('«اتنست» اللي جهاز الأب كتبها بتتحسب برضه', () {
      final s = careStatus(
        withEvents([event('Concor', DateTime(2026, 8, 31, 8), 'missed')]),
        now,
      );
      expect(s.state, CareState.needsAttention);
      expect(s.unconfirmedToday, 1);
    });

    test('تنبيه مفتوح بيغلب حتى لو كل جرعات النهارده اتقفلت', () {
      final s = careStatus(
        withEvents(
          [event('Concor', DateTime(2026, 8, 31, 8), 'taken', actedAt: DateTime(2026, 8, 31, 8, 5))],
          a: [alert()],
        ),
        now,
      );
      expect(s.state, CareState.needsAttention);
      expect(s.openAlerts, 1);
    });

    test('تنبيه على جرعة اتقفلت مش مفتوح — فمش بيغيّر الإجابة', () {
      final s = careStatus(
        withEvents(
          [event('Concor', DateTime(2026, 8, 31, 8), 'taken', actedAt: DateTime(2026, 8, 31, 8, 5))],
          a: [alert(doseState: 'taken')],
        ),
        now,
      );
      expect(s.openAlerts, 0);
      expect(s.state, CareState.allGood);
    });
  });

  group('آخر جرعة مؤكَّدة', () {
    test('الأحدث بوقت الفعل مش بوقت الجدولة', () {
      final s = careStatus(
        withEvents([
          event('Concor', DateTime(2026, 8, 31, 8), 'taken', actedAt: DateTime(2026, 8, 31, 8, 5)),
          // اتجدولت بدري، بس اتأكّدت متأخر
          event('Telfast', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 11)),
        ]),
        now,
      );
      expect(s.lastTaken?.medicationName, 'Telfast');
    });

    test('«مش هاخده» مش جرعة مؤكَّدة هنا — الكارت بيقول «اتأكّدت»، مش «اتقفلت»', () {
      final s = careStatus(
        withEvents([event('Telfast', DateTime(2026, 8, 31, 12), 'skipped')]),
        now,
      );
      expect(s.lastTaken, isNull);
    });
  });

  group('التزام آخر أسبوع', () {
    List<CaregiverDoseEvent> day(int back, List<String> states) => [
          for (final (i, st) in states.indexed)
            event('Med$i', DateTime(2026, 8, 31 - back, 8 + i), st),
        ];

    test('النهارده مش محسوب — اليوم لسه ماشي', () {
      final s = careStatus(
        withEvents([
          ...day(0, ['pending']), // النهارده، ناقص
          ...day(1, ['taken', 'taken']),
        ]),
        now,
      );
      expect(s.daysWithDoses, 1, reason: 'امبارح بس');
      expect(s.completeDays, 1);
    });

    test('يوم فيه جرعة مفتوحة مش كامل', () {
      final s = careStatus(
        withEvents([
          ...day(1, ['taken', 'missed']),
          ...day(2, ['taken', 'skipped']),
        ]),
        now,
      );
      expect(s.daysWithDoses, 2);
      expect(s.completeDays, 1);
    });

    test('أيام من غير جرعات مش بتتعدّ لا لنا ولا علينا', () {
      final s = careStatus(withEvents(day(3, ['taken'])), now);
      expect(s.daysWithDoses, 1);
      expect(s.completeDays, 1);
    });

    test('مفيش أيام فيها جرعات → صفر، والشاشة ما بتقولش حاجة', () {
      final s = careStatus(withEvents(day(0, ['taken'])), now);
      expect(s.daysWithDoses, 0);
    });
  });

  group('شكل الجرعة', () {
    test('كل حالة ليها شكلها', () {
      expect(doseLook(event('a', DateTime(2026, 8, 31, 8), 'taken'), now), DoseLook.taken);
      expect(doseLook(event('a', DateTime(2026, 8, 31, 8), 'skipped'), now), DoseLook.skipped);
      expect(doseLook(event('a', DateTime(2026, 8, 31, 8), 'missed'), now), DoseLook.unconfirmed);
      expect(doseLook(event('a', DateTime(2026, 8, 31, 8), 'pending'), now), DoseLook.unconfirmed);
      expect(doseLook(event('a', DateTime(2026, 8, 31, 20), 'pending'), now), DoseLook.upcoming);
    });
  });
}
