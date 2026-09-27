// «كلّمني» v2 — كل أداة بجملها الحقيقية (٦٠+ حالة): مواعيد، تأجيل، قياسات،
// سؤال للدكتور، شرا، روتين، مواعيد جاية، مخزون — والأدوية بالساعة والمدة.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/answer_parser.dart';
import 'package:fakkarni/domain/voice/arabic_dates.dart';
import 'package:fakkarni/features/voice/command_parser.dart';

void main() {
  // السبت ٢٦ سبتمبر ٢٠٢٦
  final now = DateTime(2026, 9, 26, 10);
  VoiceCommand p(String s) => parseCommand(s, now: now);
  void intent(String s, CommandIntent i) => test('«$s» → ${i.name}', () => expect(p(s).intent, i, reason: p(s).toString()));

  group('add_appointment', () {
    for (final s in [
      'احجزلي ميعاد دكتور يوم الحد',
      'احجزلي ميعاد دكتور يوم الحد الساعة ٥',
      'احجز ميعاد مع الدكتور بكرة',
      'عندي ميعاد معمل يوم التلات',
      'حجزت أشعة يوم الخميس الساعة ١٠ الصبح',
      'سجللي ميعاد تحليل بعد بكرة',
      'فكرني بميعاد الدكتور يوم الاتنين',
      'عندي كشف الأسبوع الجاي',
      'حطلي ميعاد رنين يوم السبت الجاي',
      'ميعاد دكتور حسام يوم الأربع الساعة ٦ بالليل',
    ]) {
      intent(s, CommandIntent.addAppointment);
    }
    test('«احجزلي ميعاد دكتور يوم الحد الساعة ٥» — دكتور، الحد الجاي، والساعة ناقصة الصبح/بالليل', () {
      final a = p('احجزلي ميعاد دكتور يوم الحد الساعة ٥').appointment!;
      expect(a.kind, AppointmentKind.doctor);
      expect(isoDate(a.date!), '2026-09-27');
      expect(a.time, isNull);
      expect(a.hourNeedsPeriod, 5, reason: 'بنسأل: الصبح ولا بالليل؟');
    });
    test('النوع من الكلمة: معمل / أشعة / دكتور', () {
      expect(p('عندي ميعاد معمل يوم التلات').appointment!.kind, AppointmentKind.lab);
      expect(p('حجزت أشعة يوم الخميس').appointment!.kind, AppointmentKind.scan);
      expect(p('احجز ميعاد مع الدكتور بكرة').appointment!.kind, AppointmentKind.doctor);
    });
    test('اليوم والساعة الكاملة', () {
      final a = p('حجزت أشعة يوم الخميس الساعة ١٠ الصبح').appointment!;
      expect(isoDate(a.date!), '2026-10-01');
      expect(a.time, const SpokenTime(10, 0));
      expect(a.hourNeedsPeriod, isNull);
    });
    test('مع مين: «دكتور حسام»', () {
      expect(p('ميعاد دكتور حسام يوم الأربع الساعة ٦ بالليل').appointment!.withWhom, 'حسام');
      expect(p('احجزلي ميعاد دكتور يوم الحد').appointment!.withWhom, isNull);
    });
    test('من غير يوم = التاريخ null (بيتسأل)', () {
      expect(p('احجزلي ميعاد دكتور').appointment!.date, isNull);
    });
  });

  group('upcoming_appointments (قراية)', () {
    for (final s in ['مواعيدي الجاية إيه', 'ميعاد الدكتور إمتى', 'عندي مواعيد إيه', 'إيه المواعيد الجاية', 'ميعاد المعمل إمتى']) {
      intent(s, CommandIntent.upcomingAppointments);
    }
  });

  group('add_medication بالساعة والمدة', () {
    test('«ضيف دوا الضغط الساعة ٩ بالليل كل يوم» → الضغط، ٩ بالليل', () {
      final c = p('ضيف دوا الضغط الساعة ٩ بالليل كل يوم');
      expect(c.intent, CommandIntent.addMed);
      expect(c.medWords, 'الضغط');
      expect(c.timings, [const SpokenTiming(fixed: SpokenTime(21, 0))]);
    });
    test('«ضيف دوا الضغط الساعة ٩» → الساعة ناقصة جزء يومها — تتسأل، مش تتخمّن', () {
      final c = p('ضيف دوا الضغط الساعة ٩');
      expect(c.intent, CommandIntent.addMed);
      expect(c.medWords, 'الضغط');
      expect(c.timings.single.hourNeedsPeriod, 9);
      expect(c.timings.single.fixed, isNull);
    });
    test('«ضيفلي كونكور الساعة ٨ الصبح والساعة ٨ بالليل»', () {
      final c = p('ضيفلي كونكور الساعة ٨ الصبح والساعة ٨ بالليل');
      expect(c.timings, [const SpokenTiming(fixed: SpokenTime(8, 0)), const SpokenTiming(fixed: SpokenTime(20, 0))]);
      expect(c.medWords, 'كونكور');
    });
    test('«ضيف مضاد حيوي بعد الأكل تلات مرات لمدة أسبوع»', () {
      final c = p('ضيف مضاد حيوي بعد الأكل تلات مرات لمدة أسبوع');
      expect(c.intent, CommandIntent.addMed);
      expect(c.timesPerDay, 3);
      expect(c.durationDays, 7);
    });
    test('«ضيف دوا السكر قبل الفطار لمدة ١٠ أيام من بكرة»', () {
      final c = p('ضيف دوا السكر قبل الفطار لمدة ١٠ أيام من بكرة');
      expect(c.durationDays, 10);
      expect(isoDate(c.startDate!), '2026-09-27');
      expect(c.medWords, 'السكر');
      expect(c.timings.single.anchorWord, 'الفطار');
    });
    test('«ضيف فيتامين يوم السبت والتلات» → أيام معينة', () {
      final c = p('ضيف فيتامين يوم السبت والتلات بعد الغدا');
      expect(c.weekdays, [6, 2]);
      expect(c.timings.single.anchorWord, 'الغدا');
    });
  });

  group('snooze', () {
    for (final s in ['فكرني بعدين', 'فكرني بعد شوية', 'أجّل الدوا', 'بعد شوية', 'فكرني كمان ربع ساعة', 'فكرني بعد ١٠ دقايق', 'أجلها']) {
      intent(s, CommandIntent.snooze);
    }
    test('الدقايق لو اتقالت، وإلا null (= الربع ساعة العادية)', () {
      expect(p('فكرني بعد ١٠ دقايق').snoozeMinutes, 10);
      expect(p('فكرني كمان ربع ساعة').snoozeMinutes, 15);
      expect(p('فكرني بعد نص ساعة').snoozeMinutes, 30);
      expect(p('فكرني بعد ساعة').snoozeMinutes, isNull);
      expect(p('فكرني بعدين').snoozeMinutes, isNull);
    });
  });

  group('add_vital', () {
    for (final s in ['ضغطي ١٢٠ على ٨٠', 'سجل الضغط ١٣٠ على ٨٥ والنبض ٧٠', 'السكر ١٥٠', 'قست السكر طلع ١٤٠', 'وزني ٨٠ كيلو', 'حرارتي ٣٧٫٥', 'النبض ٧٢', 'الأكسجين ٩٦']) {
      intent(s, CommandIntent.addVital);
    }
    test('النوع والأرقام', () {
      final bp = p('ضغطي ١٢٠ على ٨٠').vital!;
      expect(bp.type, VitalType.bp);
      expect(bp.values, [120, 80]);
      expect(p('سجل الضغط ١٣٠ على ٨٥ والنبض ٧٠').vital!.values, [130, 85, 70]);
      expect(p('السكر ١٥٠').vital!.type, VitalType.sugar);
      expect(p('وزني ٨٠ كيلو').vital!.values, [80]);
      expect(p('حرارتي ٣٧٫٥').vital!.values, [37.5]);
      expect(p('الأكسجين ٩٦').vital!.type, VitalType.o2);
    });
    test('حكم من غير رقم = طبي (مش قياس)', () {
      expect(p('ضغطي عالي').intent, CommandIntent.medicalQuestion);
      expect(p('السكر عندي مرتفع').intent, CommandIntent.medicalQuestion);
      expect(p('ضغطي ١٦٠ ده عالي؟').intent, CommandIntent.medicalQuestion);
    });
    test('«دوا الضغط» مش قياس', () {
      expect(p('ضيف دوا الضغط ٥ مج').intent, CommandIntent.addMed);
      expect(p('أخدت دوا الضغط').intent, CommandIntent.markTaken);
    });
  });

  group('add_doctor_question', () {
    for (final s in ['فكرني أسأل الدكتور عن الصداع', 'سجل سؤال للدكتور: الدوا بيدوخني', 'عايز أسأل الدكتور عن الجرعة', 'اسأل الدكتور ينفع أصوم']) {
      intent(s, CommandIntent.addDoctorQuestion);
    }
    test('نص السؤال بعد «الدكتور» و«عن»', () {
      expect(p('فكرني أسأل الدكتور عن الصداع').questionText, 'الصداع');
      expect(p('عايز أسأل الدكتور عن الجرعة').questionText, 'الجرعه');
      expect(p('سجل سؤال للدكتور: الدوا بيدوخني').questionText, 'الدوا بيدوخني');
    });
  });

  group('mark_bought', () {
    for (final s in ['اشتريت الكونكور', 'جبت دوا الضغط', 'اشتريت الدوا', 'جبت العلاج من الصيدلية']) {
      intent(s, CommandIntent.markBought);
    }
    test('الاسم زي ما اتقال', () {
      expect(p('اشتريت الكونكور').medWords, 'الكونكور');
      expect(p('جبت دوا الضغط').medWords, 'الضغط');
      expect(p('اشتريت الدوا').medWords, isNull);
    });
  });

  group('stock_status (قراية)', () {
    for (final s in ['الدوا فاضل كام', 'فاضلي كام حباية من الكونكور', 'المخزون إيه', 'إيه اللي قرب يخلص', 'الأدوية اللي خلصت']) {
      intent(s, CommandIntent.stockStatus);
    }
  });

  group('اللي كان شغّال لسه شغّال', () {
    intent('أخدت دوا الضغط', CommandIntent.markTaken);
    intent('إيه دوايا الجاي', CommandIntent.nextDose);
    intent('إيه أدويتي النهارده', CommandIntent.todayList);
    intent('أخدت جرعة زيادة أعمل إيه', CommandIntent.medicalQuestion);
    intent('الجو حر النهارده', CommandIntent.unknown);
    intent('ضيفلي دوا الضغط الصبح بعد الفطار', CommandIntent.addMed);
  });
}
