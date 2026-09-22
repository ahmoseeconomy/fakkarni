// **مين بيتابع، وإمتى يوصله الكلام** — الجزء النقي.
//
// تلات قرارات من المالك (٢٢ سبتمبر ٢٠٢٦) محبوسة هنا:
//   ١. الصيغة بتمشي مع **الصلة**، مش مع الاسم.
//   ٢. الهدوء للمواعيد والملخصات بس — والجرعة الفايتة بتعدّي في أي وقت.
//   ٣. اللي بيتأجّل بيتأجّل لآخر النافذة، **ما بيتلغيش**.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/care/follower_profile.dart';

void main() {
  group('الصيغة بتمشي مع الصلة', () {
    test('ابن وبنت ليهم صيغتهم', () {
      expect(
        const FollowerProfile(name: 'محمد', relation: FollowerRelation.son).sentence,
        'محمد ابنك بيتابعك',
      );
      expect(
        const FollowerProfile(name: 'سارة', relation: FollowerRelation.daughter).sentence,
        'سارة بنتك بتتابعك',
      );
    });

    test('و«حد تاني» بياخد النص اللي هو كتبه', () {
      expect(
        const FollowerProfile(
          name: 'أحمد',
          relation: FollowerRelation.other,
          relationOther: 'أخوه',
        ).title,
        'أحمد (أخوه)',
      );
    });

    test('**ومن غير صلة مفيش تخمين من الاسم**', () {
      // الاسم ما بيقولش ولد ولا بنت، والتخمين منه بيغلط في ناس حقيقيين.
      const p = FollowerProfile(name: 'نور');
      expect(p.title, 'نور');
      expect(p.sentence, 'نور بيتابعك');
    });

    test('و«حد تاني» من غير نص بيرجع للاسم لوحده', () {
      expect(
        const FollowerProfile(name: 'أحمد', relation: FollowerRelation.other).title,
        'أحمد',
      );
    });
  });

  group('سطر «مين بيتابعك»', () {
    test('محدش', () {
      expect(followersLine(const []), 'محدش بيتابعك لسه — اربط ابنك أو بنتك');
    });

    test('واحد بياخد جملته كاملة', () {
      expect(
        followersLine(const [FollowerProfile(name: 'محمد', relation: FollowerRelation.son)]),
        'محمد ابنك بيتابعك',
      );
    });

    test('وأكتر من واحد بصلاتهم', () {
      expect(
        followersLine(const [
          FollowerProfile(name: 'محمد', relation: FollowerRelation.son),
          FollowerProfile(name: 'سارة', relation: FollowerRelation.daughter),
        ]),
        'بيتابعوك: محمد ابنك، سارة بنتك',
      );
    });
  });

  group('نافذة الهدوء', () {
    const night = QuietHours(fromMinute: 0, toMinute: 7 * 60); // ١٢ → ٧
    const wrapping = QuietHours(fromMinute: 22 * 60, toMinute: 8 * 60); // ١٠م → ٨ص

    test('نافذة عادية بتمسك اللي جوّاها بس', () {
      expect(night.contains(DateTime(2026, 9, 22, 2)), isTrue);
      expect(night.contains(DateTime(2026, 9, 22, 7)), isFalse, reason: 'النهاية مش جوّه');
      expect(night.contains(DateTime(2026, 9, 22, 20)), isFalse);
    });

    test('ونافذة بتلفّ حوالين نص الليل بتمسك الطرفين', () {
      expect(wrapping.contains(DateTime(2026, 9, 22, 23)), isTrue);
      expect(wrapping.contains(DateTime(2026, 9, 23, 3)), isTrue);
      expect(wrapping.contains(DateTime(2026, 9, 22, 12)), isFalse);
    });

    test('**نافذة بدايتها = نهايتها مرفوضة** — يوم كامل صمت مش إعداد', () {
      expect(const QuietHours(fromMinute: 60, toMinute: 60).isValid, isFalse);
      expect(const QuietHours(fromMinute: 60, toMinute: 60).contains(DateTime(2026, 9, 22, 1)),
          isFalse);
    });
  });

  group('التأجيل بيأجّل، ما بيلغيش', () {
    const night = QuietHours(fromMinute: 0, toMinute: 7 * 60);
    const wrapping = QuietHours(fromMinute: 22 * 60, toMinute: 8 * 60);

    test('اللي جوّه النافذة بيتحجز لآخرها', () {
      expect(
        heldUntil(DateTime(2026, 9, 22, 2, 30), night),
        DateTime(2026, 9, 22, 7),
      );
    });

    test('واللي برّاها بيعدّي بوقته', () {
      final at = DateTime(2026, 9, 22, 20);
      expect(heldUntil(at, night), at);
    });

    test('ونافذة بتلفّ: اللي قبل نص الليل بيستنى لصبح **بكرة**', () {
      expect(
        heldUntil(DateTime(2026, 9, 22, 23, 10), wrapping),
        DateTime(2026, 9, 23, 8),
      );
    });

    test('واللي بعد نص الليل بيستنى لصبح نفس اليوم', () {
      expect(
        heldUntil(DateTime(2026, 9, 23, 3), wrapping),
        DateTime(2026, 9, 23, 8),
      );
    });

    test('ومن غير نافذة مفيش تأجيل', () {
      final at = DateTime(2026, 9, 22, 2);
      expect(heldUntil(at, null), at);
    });
  });

  test('الوعد مكتوب مرة واحدة، وبيقول اللي بيحصل', () {
    expect(quietHoursPromise, contains('أي جرعة تفوت هتوصلك في أي وقت'));
    expect(quietHoursPromise, contains('للمواعيد والملخصات بس'));
  });
}
