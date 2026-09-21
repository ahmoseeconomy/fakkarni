import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/features/care/caregiver_status.dart';
import 'package:fakkarni/features/care/caregiver_words.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_up.dart';

import 'caregiver_screen_test.dart' show event, now, snapshot;

/// **ترتيب أقسام «متابعة» — أرقام، من غير ما نرسم شاشة.**
///
/// الترتيب نفسه هو المعنى هنا: «الأقرب الأول» في الجاية لأنه اللي جاي،
/// و«الأحدث الأول» في المأخوذة لأن السؤال هو «خد آخر واحدة؟». لو الترتيب
/// اتقلب، الشاشة بتفضل شكلها صح وبتجاوب على سؤال تاني.
void main() {
  CaregiverSnapshot withRecords(List<CaregiverRecord> records) => CaregiverSnapshot(
        patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
        medications: const [],
        events: const [],
        alerts: const [],
        records: records,
      );

  CaregiverRecord follow({
    required String title,
    required int stage,
    String? kind,
    String? doctor,
    DateTime? labBookingAt,
    DateTime? resultReadyAt,
    DateTime? doctorVisitAt,
    DateTime? stageSince,
  }) =>
      CaregiverRecord(
        uuid: title,
        kind: kind == 'visit' ? 'visit' : 'lab',
        title: title,
        happenedAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        doctor: doctor,
        checkupStage: stage,
        followKind: kind,
        checkupStageSince: stageSince,
        labBookingAt: labBookingAt,
        resultReadyAt: resultReadyAt,
        doctorVisitAt: doctorVisitAt,
      );

  group('أقسام الجرعات', () {
    test('الجاية بالأقرب الأول، والمأخوذة بالأحدث الأول', () {
      final s = careDoseSections(
        snapshot([
          event('Late', DateTime(2026, 8, 31, 22), 'pending'),
          event('Soon', DateTime(2026, 8, 31, 15), 'pending'),
          event('Mid', DateTime(2026, 8, 31, 18), 'pending'),
          event('First', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 7, 2)),
          event('Last', DateTime(2026, 8, 31, 9), 'taken', actedAt: DateTime(2026, 8, 31, 11, 40)),
        ]),
        now,
      );
      expect([for (final e in s.upcomingToday) e.medicationName], ['Soon', 'Mid', 'Late']);
      // **الأحدث الأول بوقت التأكيد** — «خد آخر واحدة؟» هو السؤال
      expect([for (final e in s.taken) e.medicationName], ['Last', 'First']);
    });

    test('اللي ما اتأكدتش بالأقدم الأول — اللي فاتت من ساعتين أهم', () {
      final s = careDoseSections(
        snapshot([
          event('B', DateTime(2026, 8, 31, 13), 'pending'),
          event('A', DateTime(2026, 8, 31, 8), 'missed'),
        ]),
        now,
      );
      expect([for (final e in s.missed) e.medicationName], ['A', 'B']);
    });

    test('بكرة في مجموعتها، وبعد بكرة مش داخلة', () {
      final s = careDoseSections(
        snapshot([
          event('Tomorrow2', DateTime(2026, 9, 1, 21), 'pending'),
          event('Tomorrow1', DateTime(2026, 9, 1, 7), 'pending'),
          event('DayAfter', DateTime(2026, 9, 2, 7), 'pending'),
        ]),
        now,
      );
      expect([for (final e in s.tomorrow) e.medicationName], ['Tomorrow1', 'Tomorrow2']);
      expect(s.upcomingToday, isEmpty);
    });

    test('«مش هاخده» ليها قسمها — لا فايتة ولا اتاخدت', () {
      final s = careDoseSections(
        snapshot([event('X', DateTime(2026, 8, 31, 12), 'skipped')]),
        now,
      );
      expect(s.skipped, hasLength(1));
      expect(s.missed, isEmpty);
      expect(s.taken, isEmpty);
    });

    test('يوم فاضي → كل القوايم فاضية، والشاشة بتخفي العناوين', () {
      final s = careDoseSections(snapshot(const []), now);
      expect(s.missed, isEmpty);
      expect(s.upcomingToday, isEmpty);
      expect(s.tomorrow, isEmpty);
      expect(s.taken, isEmpty);
      expect(s.skipped, isEmpty);
    });
  });

  group('المتابعات', () {
    test('الأقرب الأول، واللي من غير ميعاد آخر القايمة', () {
      final all = careFollowUps(
        withRecords([
          follow(title: 'بعيدة', stage: 2, labBookingAt: DateTime(2026, 9, 10)),
          follow(title: 'من غير ميعاد', stage: 2),
          follow(title: 'قريبة', stage: 2, labBookingAt: DateTime(2026, 9, 2)),
        ]),
        now,
      );
      expect([for (final f in all) f.record.title], ['قريبة', 'بعيدة', 'من غير ميعاد']);
    });

    test('النوع بيحدّد المرحلة — الرقم ٢ مش نفس الكلمة في الاتنين', () {
      final all = careFollowUps(
        withRecords([
          follow(title: 'تحليل', stage: 2),
          follow(title: 'زيارة', stage: 2, kind: 'visit'),
        ]),
        now,
      );
      final lab = all.firstWhere((f) => f.kind == FollowKind.lab);
      final visit = all.firstWhere((f) => f.kind == FollowKind.visit);
      expect(lab.stage, CheckupStage.labBooking);
      expect(lab.stage.label, 'حجز المعمل');
      // الرقم ٢ في الزيارة هو «الزيارة تمت» — مش «حجز المعمل». ده
      // بالظبط السبب اللي `follow_kind` اتضاف عشانه في الجولة ٢٤.
      expect(visit.stage, VisitStage.done);
      expect(visit.stage.label, 'الزيارة تمت');
    });

    test('null في العمود = تحليل — مش تخمين، دي الحقيقة الوحيدة اللي كانت', () {
      final all = careFollowUps(withRecords([follow(title: 'قديمة', stage: 1)]), now);
      expect(all.single.kind, FollowKind.lab);
    });

    test('صف مالوش مرحلة مش متابعة أصلاً', () {
      final all = careFollowUps(
        withRecords([
          CaregiverRecord(
            uuid: 'r',
            kind: 'lab',
            title: 'تقرير عادي',
            happenedAt: DateTime(2026, 8, 1),
            updatedAt: DateTime(2026, 8, 1),
          ),
        ]),
        now,
      );
      expect(all, isEmpty);
    });

    test('واقفة: مرحلة بتسأل عن ميعاد + مفيش ميعاد + عدّى أسبوع', () {
      final stalled = careFollowUps(
        withRecords([
          follow(title: 'واقفة', stage: 2, stageSince: DateTime(2026, 8, 20)),
          follow(title: 'لسه بدري', stage: 2, stageSince: DateTime(2026, 8, 29)),
          follow(
            title: 'ليها ميعاد',
            stage: 2,
            stageSince: DateTime(2026, 8, 20),
            labBookingAt: DateTime(2026, 9, 5),
          ),
        ]),
        now,
      );
      expect({for (final f in stalled) f.record.title: f.stalled},
          {'ليها ميعاد': false, 'واقفة': true, 'لسه بدري': false});
    });

    test('ميعاد الزيارة بيتقرا من نفس عمود «معاد الدكتور»', () {
      final all = careFollowUps(
        withRecords([
          follow(title: 'زيارة', stage: 1, kind: 'visit', doctorVisitAt: DateTime(2026, 9, 3)),
        ]),
        now,
      );
      expect(all.single.stageDate, DateTime(2026, 9, 3));
    });
  });

  group('الوقت النسبي — الصيغة العربية بتعدّ تلاتة', () {
    final t = DateTime(2026, 8, 31, 14);
    test('قدّام', () {
      expect(timeAhead(t, t.add(const Duration(seconds: 30))), 'دلوقتي');
      expect(timeAhead(t, t.add(const Duration(minutes: 1))), 'كمان دقيقة');
      expect(timeAhead(t, t.add(const Duration(minutes: 2))), 'كمان دقيقتين');
      expect(timeAhead(t, t.add(const Duration(minutes: 40))), 'كمان ٤٠ دقيقة');
      expect(timeAhead(t, t.add(const Duration(minutes: 5))), 'كمان ٥ دقايق');
      expect(timeAhead(t, t.add(const Duration(hours: 1))), 'كمان ساعة');
      expect(timeAhead(t, t.add(const Duration(hours: 6))), 'كمان ٦ ساعات');
      expect(timeAhead(t, DateTime(2026, 9, 1, 7)), 'بكرة');
      expect(timeAhead(t, DateTime(2026, 9, 2, 7)), 'بعد بكرة');
      expect(timeAhead(t, DateTime(2026, 9, 4, 7)), 'كمان ٤ أيام');
    });

    test('ورا', () {
      expect(timeSince(t, t.subtract(const Duration(minutes: 40))), 'من ٤٠ دقيقة');
      expect(timeSince(t, t.subtract(const Duration(hours: 2))), 'من ساعتين');
      expect(timeSince(t, DateTime(2026, 8, 30, 9)), 'من امبارح');
      expect(timeSince(t, DateTime(2026, 8, 24, 9)), 'من ٧ أيام');
    });
  });
}
