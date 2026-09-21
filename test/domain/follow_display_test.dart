import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_display.dart';
import 'package:fakkarni/domain/health/follow_up.dart';

/// **مصدر واحد لعرض المتابعة — والعطل اللي عمله.**
///
/// من جهاز حقيقي: زيارة محجوزة بكرة كانت بتتعرض «١٣ سبتمبر ٢٠٢٣» —
/// تاريخ الورقة اللي المتابعة اتبدت منها.
void main() {
  final now = DateTime(2026, 9, 15, 10);

  group('سطر التاريخ', () {
    test('قريّب بيتقال بالكلام', () {
      expect(followDateLine(DateTime(2026, 9, 15, 7), now), 'النهارده');
      expect(followDateLine(DateTime(2026, 9, 16, 7), now), 'بكرة');
      expect(followDateLine(DateTime(2026, 9, 17, 7), now), 'بعد بكرة');
      expect(followDateLine(DateTime(2026, 9, 20, 7), now), 'بعد ٥ أيام');
    });

    test('والبعيد بتاريخه', () {
      expect(followDateLine(DateTime(2026, 11, 2, 7), now), '٢ نوفمبر ٢٠٢٦');
    });

    test('**ومفيش ميعاد بيتقال بالحرف** — مش بيرجع لتاريخ تاني', () {
      expect(followDateLine(null, now), 'لسه ما اتحددش ميعاد');
    });

    test('بأيام تقويمية — ميعاد بعد ٢٠ ساعة «بكرة» مش «النهارده»', () {
      expect(followDateLine(DateTime(2026, 9, 16, 7), DateTime(2026, 9, 15, 23)), 'بكرة');
    });
  });

  group('الاسم — باللي بنتابعه مش بالورقة', () {
    test('عدّاد نتايج الورقة بيتشال', () {
      expect(followDisplayTitle(FollowKind.lab, 'تقرير تحليل — ٦ نتايج'), 'متابعة تحليل');
      expect(followDisplayTitle(FollowKind.lab, 'تقرير تحليل — 6 نتايج'), 'متابعة تحليل');
      expect(followDisplayTitle(FollowKind.lab, 'تقرير تحليل — نتيجتين'), 'متابعة تحليل');
    });

    test('واسم التحليل بيفضل لما يكون معروف', () {
      expect(followDisplayTitle(FollowKind.lab, 'تقرير تحليل — HbA1c'), 'متابعة HbA1c');
    });

    test('و«من غير اسم دكتور» بتبقى «متابعة زيارة»', () {
      expect(followDisplayTitle(FollowKind.visit, 'من غير اسم دكتور'), 'متابعة زيارة');
      expect(followDisplayTitle(FollowKind.visit, ''), 'متابعة زيارة');
    });

    test('واسم كتبه إنسان بيفضل زي ما هو', () {
      expect(followDisplayTitle(FollowKind.visit, 'د. حسام'), 'د. حسام');
      expect(followDisplayTitle(FollowKind.lab, 'صورة دم كاملة'), 'صورة دم كاملة');
    });
  });

  test('الأصل بيتقال كأصل، مش كميعاد', () {
    expect(followOriginLine(FollowKind.visit, DateTime(2023, 9, 13)), 'من روشتة ١٣ سبتمبر ٢٠٢٣');
    expect(followOriginLine(FollowKind.lab, DateTime(2023, 9, 13)), 'من تقرير ١٣ سبتمبر ٢٠٢٣');
  });

  test('ولا رقم لاتيني في أي سطر بتطلّعه', () {
    final latin = RegExp(r'[0-9]');
    for (final s in [
      followDateLine(DateTime(2026, 9, 20, 7), now),
      followDateLine(DateTime(2026, 11, 2, 7), now),
      followDateLine(null, now),
      followDisplayTitle(FollowKind.lab, 'تقرير تحليل — 6 نتايج'),
      followOriginLine(FollowKind.visit, DateTime(2023, 9, 13)),
    ]) {
      expect(latin.hasMatch(s), isFalse, reason: '«$s» فيه رقم لاتيني');
    }
  });
  group('مفتوحة ولا خلصت', () {
    test('المتابعة مفتوحة طول ما هي قبل آخر مرحلة', () {
      expect(followIsOpen(FollowKind.visit, VisitStage.booked), isTrue);
      expect(followIsOpen(FollowKind.visit, VisitStage.done), isTrue);
      expect(followIsOpen(FollowKind.lab, CheckupStage.waitingResult), isTrue);
    });

    test('وآخر مرحلة معناها خلصت — بتتعرض زي أي سجل، بتاريخها', () {
      expect(followIsOpen(FollowKind.visit, VisitStage.followUp), isFalse);
      expect(followIsOpen(FollowKind.lab, CheckupStage.doctorReview), isFalse);
    });

    test('وصف مش متابعة أصلاً مش مفتوح', () {
      expect(followIsOpen(FollowKind.lab, null), isFalse);
    });
  });

  group('ميعاد المرحلة — تعريف واحد للناحيتين', () {
    final booking = DateTime(2026, 9, 16);
    final ready = DateTime(2026, 9, 18);
    final visit = DateTime(2026, 9, 20);

    DateTime? at(FollowStage s) => followStageDate(s,
        labBookingAt: booking, resultReadyAt: ready, doctorVisitAt: visit);

    test('كل مرحلة بتقرا عمودها', () {
      expect(at(CheckupStage.labBooking), booking);
      expect(at(CheckupStage.waitingResult), ready);
      expect(at(CheckupStage.resultArrived), visit);
    });

    test('**وميعاد الزيارة في نفس عمود «معاد الدكتور»** — الصف نوعه واحد بس', () {
      expect(at(VisitStage.booked), visit);
    });

    test('ومرحلة ما بتسألش عن ميعاد مالهاش ميعاد، مهما كانت الأعمدة مليانة', () {
      expect(at(CheckupStage.preparation), isNull);
      expect(at(VisitStage.done), isNull);
      expect(at(VisitStage.followUp), isNull);
    });
  });

  group('السطر الكامل', () {
    test('الكلمة والتاريخ جنب بعض', () {
      expect(followDateFull(DateTime(2026, 9, 16, 7), now), 'بكرة — ١٦ سبتمبر ٢٠٢٦');
    });

    test('**ومفيش تكرار** لما العدّ نفسه بيرجّع التاريخ', () {
      expect(followDateFull(DateTime(2026, 11, 2, 7), now), '٢ نوفمبر ٢٠٢٦');
    });

    test('ومن غير ميعاد: نفس الجملة اللي في كل مكان', () {
      expect(followDateFull(null, now), noFollowDateText);
    });
  });

  group('الاسم جوّه جملة', () {
    test('النوع بيتسمّى لما الاسم مش بيسمّيه', () {
      expect(followRowName(FollowKind.lab, 'صورة دم كاملة'), 'متابعة تحليل صورة دم كاملة');
      expect(followRowName(FollowKind.visit, 'د. حسام'), 'متابعة زيارة د. حسام');
    });

    test('**ومفيش «متابعة متابعة»** لما الاسم بيبدأ بيها خلاص', () {
      expect(followRowName(FollowKind.lab, 'تقرير تحليل — CBC'), 'متابعة CBC');
      expect(followRowName(FollowKind.visit, 'من غير اسم دكتور'), 'متابعة زيارة');
    });
  });

}
