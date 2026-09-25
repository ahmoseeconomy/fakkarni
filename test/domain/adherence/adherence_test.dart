import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/domain/adherence/adherence.dart';
import 'package:fakkarni/features/adherence/adherence_sources.dart';

/// الخميس ٢٤ سبتمبر ٢٠٢٦ الساعة ٦ المسا. الأسبوع المصري: السبت ١٩ ← الجمعة ٢٥.
final now = DateTime(2026, 9, 24, 18);
final today = DateTime(2026, 9, 24);

var _n = 0;
AdherenceDose dose(DateTime day, int hour, AdherenceState state, {String med = 'Concor', int minute = 0, DateTime? at}) =>
    AdherenceDose(
      id: 'd${_n++}',
      medicationName: med,
      routineDay: day,
      scheduledAt: at ?? DateTime(day.year, day.month, day.day, hour, minute),
      state: state,
    );

DateTime d(int day) => DateTime(2026, 9, day);

const taken = AdherenceState.taken;
const skipped = AdherenceState.skipped;
const pending = AdherenceState.pending;
const missedS = AdherenceState.missed;

/// أيام كاملة: جرعتين اتاخدوا في كل يوم.
List<AdherenceDose> fullDays(Iterable<int> days) => [
      for (final day in days) ...[dose(d(day), 8, taken), dose(d(day), 20, taken)],
    ];

Adherence run(List<AdherenceDose> doses, {DateTime? at, DateTime? dataFrom}) =>
    computeAdherence(doses, today: today, now: at ?? now, dataFrom: dataFrom);

void main() {
  group('قواعد اليوم', () {
    test('كامل = كل جرعة اتاخدت أو اتخطّت بقراره — والمتخطّية مش بتكسر', () {
      final a = run([...fullDays([22]), dose(d(23), 8, taken), dose(d(23), 20, skipped)]);
      expect(a.week.firstWhere((w) => w.day == d(23)).mark, DayMark.complete);
      expect(a.currentStreak, 2, reason: 'النهارده لسه مفيهوش جرعات = محايد، وامبارح وأول امبارح كاملين');
    });

    test('فايت = جرعة عدّت مهلتها (٤٥ د) من غير تأكيد — والصف «missed» زيها', () {
      expect(markDay([dose(d(23), 8, pending)], d(23), today: today, now: now), DayMark.missed);
      expect(markDay([dose(d(23), 8, missedS)], d(23), today: today, now: now), DayMark.missed);
      // ٥:٣٠ والمهلة لسه ما خلصتش (٥:٣٠ + ٤٥ = ٦:١٥) → لسه
      expect(markDay([dose(today, 17, pending, minute: 30)], today, today: today, now: now), DayMark.upcoming);
      expect(markDay([dose(today, 17, pending, minute: 15)], today, today: today, now: now), DayMark.missed,
          reason: '٥:١٥ + ٤٥ = ٦:٠٠ بالظبط — المهلة خلصت');
    });

    test('يوم مفيهوش جرعات محايد — لا بيكسر ولا بيزوّد', () {
      final a = run([...fullDays([20, 21]), ...fullDays([23])]); // ٢٢ مفيهوش ولا صف
      expect(a.week.firstWhere((w) => w.day == d(22)).mark, DayMark.neutral);
      expect(a.currentStreak, 3);
    });

    test('النهارده وفيه جرعة لسه في وقتها: ما بيكسرش العدّ ولا بيتحسب', () {
      final a = run([...fullDays([21, 22, 23]), dose(today, 8, taken), dose(today, 21, pending)]);
      expect(a.week.firstWhere((w) => w.day == today).mark, DayMark.upcoming);
      expect(a.currentStreak, 3, reason: 'النهارده لسه بيتحسم');
    });

    test('النهارده بيتحسب أول ما يكمل', () {
      final a = run([...fullDays([21, 22, 23]), dose(today, 8, taken), dose(today, 17, taken)]);
      expect(a.week.firstWhere((w) => w.day == today).mark, DayMark.complete);
      expect(a.currentStreak, 4);
    });

    test('فاتته جرعة الصبح واليوم لسه مفتوح → الرقم زي ما هو، والنقطة رمادي', () {
      final a = run([...fullDays([21, 22, 23]), dose(today, 8, pending), dose(today, 21, pending)]);
      expect(a.week.firstWhere((w) => w.day == today).mark, DayMark.missed, reason: 'النقطة رمادي على النهارده');
      expect(a.currentStreak, 3, reason: 'اليوم لسه مفتوح — الرقم ما يتصفّرش');
      expect(a.missed.single.routineDay, today);
      // «أخدتها متأخر» → النهارده بيكمل وبيتحسب
      final b = run([...fullDays([21, 22, 23]), dose(today, 8, taken), dose(today, 17, taken)]);
      expect(b.currentStreak, 4);
    });

    test('اليوم قفل وفيه فايت → العدّ بيبدأ من جديد من اليوم اللي بعده', () {
      final doses = [...fullDays([20, 21, 22]), dose(d(23), 8, missedS), dose(today, 8, pending)];
      // النهارده ٢٤ لسه مفتوح: امبارح ٢٣ قفل بفايت → صفر (والنهارده لسه)
      final a = run(doses);
      expect(a.currentStreak, 0);
      expect(streakLine(a.currentStreak), 'النهارده بداية جديدة');
      expect(a.bestStreak, 3);
      // ونفس الحكاية بعد ما ٢٤ نفسه يقفل بفايت: بكرة ٢٥ بيبدأ من الصفر
      final next = computeAdherence(
        [...fullDays([21, 22, 23]), dose(today, 8, pending)],
        today: d(25),
        now: DateTime(2026, 9, 25, 9),
      );
      expect(next.currentStreak, 0, reason: 'يوم ٢٤ قفل وفيه فايت');
      expect(next.bestStreak, 3);
    });

    test('جرعة بعد نص الليل تبع يوم الروتين اللي قبلها', () {
      // جرعة «قبل النوم» ١ الصبح يوم ٢٤ بالساعة — بس يوم روتينها ٢٣
      final lateNight = dose(d(23), 0, taken, at: DateTime(2026, 9, 24, 1));
      final a = run([...fullDays([22]), dose(d(23), 8, taken), lateNight]);
      expect(a.week.firstWhere((w) => w.day == d(23)).mark, DayMark.complete);
      expect(a.week.firstWhere((w) => w.day == today).mark, DayMark.neutral,
          reason: 'النهارده مالوش صفوف — الجرعة مش بتاعته');
      expect(a.currentStreak, 2);

      // ونفس الجرعة لو فاتت بتكسر يوم ٢٣ مش النهارده
      final missedLate = dose(d(23), 0, pending, at: DateTime(2026, 9, 24, 1));
      final b = run([dose(d(23), 8, taken), missedLate]);
      expect(b.week.firstWhere((w) => w.day == d(23)).mark, DayMark.missed);
      expect(b.missed.single.routineDay, d(23));
    });

    test('رمضان والروتين المتحرّك: اليوم بيتحسب بيوم الروتين، مش بالساعة', () {
      // إفطار ٦ المسا وسحور ٣:٣٠ الصبح — الاتنين يوم روتين ٢٣
      final a = run([
        dose(d(23), 18, taken),
        dose(d(23), 3, taken, at: DateTime(2026, 9, 24, 3, 30)),
        ...fullDays([22]),
      ]);
      expect(a.week.firstWhere((w) => w.day == d(23)).mark, DayMark.complete);
      expect(a.currentStreak, 2);
    });

    test('دوا اتضاف في نص الأسبوع: الأيام اللي قبله مالهاش صفوف = محايدة', () {
      final a = run([...fullDays([22, 23])]);
      expect([for (final w in a.week) w.mark], [
        DayMark.neutral, DayMark.neutral, DayMark.neutral, // سبت ١٩، حد ٢٠، اتنين ٢١
        DayMark.complete, DayMark.complete, // تلات ٢٢، أربع ٢٣
        DayMark.neutral, // النهارده الخميس — مفيش صفوف
        DayMark.upcoming, // الجمعة لسه
      ]);
      expect(a.currentStreak, 2);
    });

    test('جرعة مرة واحدة: يوم بصف واحد، ويوم من غيرها محايد', () {
      final a = run([dose(d(21), 10, taken)]);
      expect(a.week.firstWhere((w) => w.day == d(21)).mark, DayMark.complete);
      expect(a.week.firstWhere((w) => w.day == d(22)).mark, DayMark.neutral);
      expect(a.currentStreak, 1);
      expect(streakLine(1), 'يوم كامل');
    });
  });

  group('العدّ', () {
    test('أحسن مرة على كل التاريخ، والحالي بيقف عند أول يوم فايت', () {
      final a = run([
        ...fullDays([1, 2, 3, 4, 5, 6]),
        dose(d(7), 8, missedS),
        ...fullDays([8, 9]),
        dose(d(10), 8, pending), // فات
        ...fullDays([21, 22, 23]),
      ]);
      expect(a.bestStreak, 6);
      expect(a.currentStreak, 3, reason: '١١–٢٠ محايدين ما كسروش، و١٠ فايت وقف العدّ عنده');
      expect(bestStreakLine(6), 'أحسن مرة: ٦ أيام ورا بعض');
    });

    test('العيلة شايفة أسبوع بس: العدّ اللي يوصل أول الداتا بيتقال «أو أكتر»', () {
      final a = run([...fullDays([18, 19, 20, 21, 22, 23])], dataFrom: d(18));
      expect(a.currentStreak, 6);
      expect(a.currentAtLeast, isTrue);
      expect(streakLine(a.currentStreak, atLeast: a.currentAtLeast), '٦ أيام أو أكتر ورا بعض');
      // اليوم الناقص قبل dataFrom ما بيدخلش الحساب
      final b = run([dose(d(17), 8, pending), ...fullDays([18, 19])], dataFrom: d(18));
      expect(b.missed, isEmpty);
      expect(b.currentAtLeast, isTrue);
      // وعدّ اتكسر جوّه الأسبوع مش «أو أكتر»
      final c = run([dose(d(19), 8, missedS), ...fullDays([20, 21])], dataFrom: d(18));
      expect(c.currentAtLeast, isFalse);
      expect(c.currentStreak, 2);
    });
  });

  group('الأسبوع والنسبة واللي فات', () {
    test('الأسبوع من السبت للجمعة', () {
      final a = run(const []);
      expect(a.week.first.day, d(19));
      expect(a.week.first.day.weekday, DateTime.saturday);
      expect(a.week.last.day, d(25));
      expect(weekStart(d(19)), d(19), reason: 'السبت نفسه أول أسبوعه');
      expect(weekStart(d(25)), d(19));
    });

    test('النسبة: اتاخد ÷ (اتاخد + فات) في آخر ٧ أيام — المتخطّي واللي لسه برّه', () {
      final a = run([
        dose(d(17), 8, missedS), // قبل آخر ٧ أيام (١٨–٢٤) — برّه
        dose(d(18), 8, taken),
        dose(d(19), 8, taken),
        dose(d(20), 8, taken),
        dose(d(21), 8, missedS),
        dose(d(22), 8, skipped),
        dose(today, 21, pending), // لسه
      ]);
      expect(a.takenPercent, 75);
      expect(takenPercentLine(75), 'اتاخد ٧٥٪ من الجرعات في آخر ٧ أيام');
      expect(run(const []).takenPercent, isNull);
    });

    test('اللي فات في آخر ٧ أيام: الأحدث الأول، بالاسم واليوم والساعة', () {
      final a = run([
        dose(d(20), 8, missedS, med: 'Glucophage'),
        dose(today, 9, pending, med: 'Concor'),
        dose(d(22), 20, taken),
      ]);
      expect([for (final m in a.missed) m.medicationName], ['Concor', 'Glucophage']);
      expect(missedWhen(a.missed.first, today), 'النهارده ٩:٠٠ ص');
      expect(missedWhen(a.missed.last, today), 'الحد ٨:٠٠ ص');
    });
  });

  group('من صورة العيلة', () {
    CaregiverSnapshot snap(List<CaregiverDoseEvent> events, {Map<String, String?> proxied = const {}}) =>
        CaregiverSnapshot(
          patient: const CaregiverPatient(uuid: 'p', name: 'أحمد'),
          medications: const [],
          events: events,
          proxied: proxied,
        );

    test('تأكيد الممرض اللي لسه ما اتسحبش بيتحسب «اتاخدت»', () {
      final e = CaregiverDoseEvent(
        uuid: 'e1',
        medicationName: 'Concor',
        scheduledAt: DateTime(2026, 9, 23, 8),
        routineDay: d(23),
        state: 'pending',
      );
      final withProxy = adherenceFromSnapshot(snap([e], proxied: {'e1': 'سارة'}), now);
      expect(withProxy.week.firstWhere((w) => w.day == d(23)).mark, DayMark.complete);
      final without = adherenceFromSnapshot(snap([e]), now);
      expect(without.week.firstWhere((w) => w.day == d(23)).mark, DayMark.missed);
    });

    test('يوم الروتين من السحابة بيغلب تاريخ الساعة', () {
      final late = CaregiverDoseEvent(
        uuid: 'e2',
        medicationName: 'Concor',
        scheduledAt: DateTime(2026, 9, 24, 1),
        routineDay: d(23),
        state: 'taken',
      );
      final a = adherenceFromSnapshot(snap([late]), now);
      expect(a.week.firstWhere((w) => w.day == d(23)).mark, DayMark.complete);
      expect(a.week.firstWhere((w) => w.day == today).mark, DayMark.neutral);
    });
  });

  group('الإخفاء والكلام', () {
    test('الكارت بيستخبّى أول يومين بعد أول جرعة', () {
      expect(adherenceWorthShowing(null, today), isFalse);
      expect(adherenceWorthShowing(today, today), isFalse);
      expect(adherenceWorthShowing(d(23), today), isFalse);
      expect(adherenceWorthShowing(d(22), today), isTrue);
    });

    test('صيغ العدّ بالعربي المصري', () {
      expect(streakLine(2), 'يومين ورا بعض');
      expect(streakLine(5), '٥ أيام ورا بعض');
      expect(streakLine(14), '١٤ يوم ورا بعض');
    });

    test('ولا كلمة لوم ولا تحذير في كلام الكارت', () {
      for (final t in adherenceSampleTexts()) {
        for (final w in ['فشل', 'فاشل', 'خطر', 'خطير', 'مقلق', 'لازم', 'غلط', 'حذار', 'تحذير', 'مرض']) {
          expect(t.contains(w), isFalse, reason: '«$w» في: $t');
        }
      }
    });
  });
}
