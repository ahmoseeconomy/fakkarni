// تخصص الدكتور بكلام المصريين (طلب المالك، ٢٩ سبتمبر ٢٠٢٦): «احجز دكتور بطنه»
// = باطنة، مش دكتور اسمه «بطنه». والتخصص عمره ما بيتخمّن — بيتفهم من
// الكلمة اللي اتقالت وبس.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/places/specialty.dart';
import 'package:fakkarni/domain/voice/nlu/nlu.dart';
import 'package:fakkarni/features/records/health_file_screen.dart' show bookingTitle;

void main() {
  final now = DateTime(2026, 10, 1, 10);
  NluResult u(String s) => understandUtterance(s, now: now);

  group('الكلمة لوحدها ← التخصص', () {
    for (final (word, sp) in [
      ('بطنة', Specialty.internal),
      ('بطنه', Specialty.internal),
      ('باطنة', Specialty.internal),
      ('باطني', Specialty.internal),
      ('معدة', Specialty.internal),
      ('عنين', Specialty.eyes),
      ('رمد', Specialty.eyes),
      ('سنان', Specialty.dental),
      ('ضروس', Specialty.dental),
      ('عيال', Specialty.children),
      ('أطفال', Specialty.children),
      ('عضم', Specialty.bones),
      ('العضام', Specialty.bones),
      ('كسور', Specialty.bones),
      ('جلدية', Specialty.skin),
      ('نسا', Specialty.women),
      ('ولادة', Specialty.women),
      ('قلب', Specialty.heart),
      ('ودان', Specialty.ent),
      ('زور', Specialty.ent),
      ('مخ', Specialty.neuro),
      ('أعصاب', Specialty.neuro),
      ('مسالك', Specialty.urology),
      ('بروستاتا', Specialty.urology),
      ('كلاوي', Specialty.kidney),
      ('كلى', Specialty.kidney),
      ('صدر', Specialty.chest),
      ('سكر', Specialty.diabetes),
      ('غدد', Specialty.diabetes),
      ('نفساني', Specialty.psych),
      ('روماتيزم', Specialty.rheumatology),
      ('روماتزم', Specialty.rheumatology),
    ]) {
      test('«$word» ← ${sp.label}', () => expect(specialtyFromWord(word), sp));
    }

    test('«عين» لوحدها مش تخصص — «عين شمس» مكان', () {
      expect(specialtyFromWord('عين'), isNull);
    });
    test('كلمة عادية مش تخصص', () {
      for (final w in ['حسن', 'بكرة', 'الساعة', 'ميعاد']) {
        expect(specialtyFromWord(w), isNull, reason: w);
      }
    });
  });

  group('«احجز»: التخصص بيتفهم ومش بيبقى اسم دكتور', () {
    for (final (s, sp) in [
      ('احجز دكتور بطنه', Specialty.internal),
      ('احجزلي دكتور بطنة بكرة', Specialty.internal),
      ('عايز احجز دكتور أمراض باطنة', Specialty.internal),
      ('احجز ميعاد عند دكتور سنان', Specialty.dental),
      ('احجزلي دكتور عيال يوم الحد', Specialty.children),
      ('احجز دكتور عضم', Specialty.bones),
      ('احجز دكتور أنف وأذن', Specialty.ent),
      ('احجز دكتور ودان', Specialty.ent),
      ('احجز دكتورة نسا', Specialty.women),
      ('احجز أخصائي عظام عند الدكتور', Specialty.bones),
      ('احجز دكتور طب أطفال', Specialty.children),
      ('احجز دكتور كلاوي', Specialty.kidney),
      ('احجز دكتور نفساني', Specialty.psych),
      ('احجز دكتور عنين', Specialty.eyes),
    ]) {
      test('«$s» ← ${sp.label}، من غير اسم دكتور', () {
        final n = u(s);
        expect(n.intent, NluIntent.bookAppointment);
        expect(n.specialtyKind, sp);
        expect(n.doctorName, isNull, reason: 'التخصص مش اسم');
      });
    }

    test('اسم الدكتور وتخصصه مع بعض: «احجز دكتور حسن بطنة» ← د. حسن، باطنة', () {
      final n = u('احجز دكتور حسن بطنة');
      expect(n.doctorName, 'د. حسن');
      expect(n.specialtyKind, Specialty.internal);
    });

    test('من غير كلمة تخصص = مفيش تخصص (مش بنخمّن)', () {
      final n = u('احجز ميعاد عند الدكتور حسن');
      expect(n.specialtyKind, isNull);
    });
  });

  test('«أقرب دكتور عيال» ← القريب مني، دكاترة أطفال', () {
    final n = u('أقرب دكتور عيال');
    expect(n.intent, NluIntent.findNearby);
    expect(n.place, NearbyPlace.doctor);
    expect(n.specialtyKind, Specialty.children);
  });

  group('اسم الميعاد (التخصص جوّه الاسم)', () {
    test('من غير اسم = «دكتور باطنة»؛ من غير الاتنين = «زيارة دكتور»', () {
      expect(bookingTitle(FollowKind.visit, '', Specialty.internal), 'دكتور باطنة');
      expect(bookingTitle(FollowKind.visit, '  ', null), 'زيارة دكتور');
    });
    test('اسم + تخصص = «د. حسن — باطنة»', () {
      expect(bookingTitle(FollowKind.visit, ' د. حسن ', Specialty.internal), 'د. حسن — باطنة');
    });
    test('الاسم فيه التخصص خلاص = مفيش تكرار', () {
      expect(bookingTitle(FollowKind.visit, 'عيادة العيون', Specialty.eyes), 'عيادة العيون');
    });
    test('المعمل مالوش تخصص', () {
      expect(bookingTitle(FollowKind.lab, '', Specialty.internal), 'تحليل');
      expect(bookingTitle(FollowKind.lab, 'صورة دم', null), 'صورة دم');
    });
  });
}
