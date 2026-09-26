// فهم الطلبات المفتوحة بالمصري — كلام حقيقي بتنويعاته، وكلام مش أوامر لازم
// يطلع unknown، وأي حاجة طبية لازم تطلع medicalQuestion.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/answer_parser.dart';
import 'package:fakkarni/features/voice/command_parser.dart';

void main() {
  void intent(String s, CommandIntent i) => test('«$s» → ${i.name}', () => expect(parseCommand(s).intent, i));

  group('أخدت الدوا (mark_taken)', () {
    for (final s in [
      'أخدت الدوا',
      'اخدت الدوا',
      'خدت الدوا',
      'خدت دوايا',
      'أخدت دوايا',
      'شربت الدوا',
      'بلعت الحباية',
      'أخدت دوا الضغط',
      'خدت دوا السكر',
      'أخدت الكونكور',
      'أنا أخدت الدوا خلاص',
      'أخدته',
      'خدتها',
      'أخدت البرشام',
      'شربت دوا المعدة',
      'أخدت حباية الضغط',
      'تناولت الدوا',
      'أخدت الجرعة بتاعتي',
    ]) {
      intent(s, CommandIntent.markTaken);
    }
    test('اسم الدوا زي ما اتقال — أو null لما ما سمّاش', () {
      expect(parseCommand('أخدت دوا الضغط').medWords, 'الضغط');
      expect(parseCommand('خدت دوا السكر').medWords, 'السكر');
      expect(parseCommand('أخدت الكونكور').medWords, 'الكونكور');
      expect(parseCommand('أخدت كونكور خمسة').medWords, 'كونكور خمسه', reason: 'بعد التطبيع (ة → ه)');
      expect(parseCommand('أخدت الدوا').medWords, isNull);
      expect(parseCommand('خدت دوايا').medWords, isNull);
      expect(parseCommand('أخدته').medWords, isNull);
      expect(parseCommand('أخدت الدوا بتاع الضغط').medWords, 'الضغط');
    });
    test('«ماخدتش» مش أمر', () {
      expect(parseCommand('ماخدتش الدوا').intent, CommandIntent.unknown);
      expect(parseCommand('لسه ماخدتهوش').intent, CommandIntent.unknown);
    });
  });

  group('الدوا الجاي (next_dose)', () {
    for (final s in [
      'إيه دوايا الجاي؟',
      'ايه دوايا الجاي',
      'الدوا الجاي إمتى؟',
      'الدوا الجاي امتى',
      'الدوا الجاي امتا',
      'إمتى الدوا الجاي',
      'إيه الدوا اللي جاي',
      'الجرعة الجاية إمتى',
      'دوايا الجاي الساعة كام',
      'معاد الدوا الجاي',
      'ميعاد دوايا إمتى',
      'الحباية الجاية إمتى',
    ]) {
      intent(s, CommandIntent.nextDose);
    }
  });

  group('أدوية النهارده (today_list)', () {
    for (final s in [
      'إيه أدويتي النهارده؟',
      'ايه ادويتي النهارده',
      'أدويتي النهارده إيه',
      'عايز أعرف أدويتي النهارده',
      'إيه الأدوية بتاعة النهارده',
      'قولي أدويتي',
      'إيه أدويتي',
      'دوايا النهارده إيه',
      'جرعاتي النهارده',
      'إيه الأدوية اللي عندي',
    ]) {
      intent(s, CommandIntent.todayList);
    }
  });

  group('ضيفلي دوا (add_med)', () {
    for (final s in [
      'ضيفلي دوا الضغط الصبح بعد الفطار',
      'ضيف دوا',
      'ضيفلي دوا اسمه كونكور',
      'زودلي دوا السكر بعد الغدا',
      'سجل دوا جديد',
      'عايز أضيف دوا',
      'حطلي دوا الكوليسترول قبل النوم',
      'ضيفي دوا المعدة قبل الأكل تلات مرات',
    ]) {
      intent(s, CommandIntent.addMed);
    }
    test('الاسم والمواعيد بكلماتها — من غير جدولة', () {
      final c = parseCommand('ضيفلي دوا الضغط الصبح بعد الفطار');
      expect(c.medWords, 'الضغط');
      expect(c.timings, [const SpokenTiming(anchorWord: 'الفطار', relation: MealRelation.after)]);
      expect(c.timesPerDay, isNull);
      expect(c.once, isFalse);
    });
    test('بعد الغدا / قبل النوم / مع العشا', () {
      expect(parseCommand('زودلي دوا السكر بعد الغدا').timings,
          [const SpokenTiming(anchorWord: 'الغدا', relation: MealRelation.after)]);
      expect(parseCommand('حطلي دوا الكوليسترول قبل النوم').timings,
          [const SpokenTiming(anchorWord: 'النوم', relation: MealRelation.before)]);
      expect(parseCommand('ضيفلي دوا مع العشا').timings,
          [const SpokenTiming(anchorWord: 'العشا', relation: MealRelation.with_)]);
    });
    test('مواعيد كتير في طلب واحد', () {
      final c = parseCommand('ضيفلي دوا الضغط بعد الفطار وبعد العشا');
      expect(c.timings, [
        const SpokenTiming(anchorWord: 'الفطار', relation: MealRelation.after),
        const SpokenTiming(anchorWord: 'العشا', relation: MealRelation.after),
      ]);
    });
    test('«بعد الأكل تلات مرات» = العلاقة والعدد، من غير وجبة', () {
      final c = parseCommand('ضيفي دوا المعدة قبل الأكل تلات مرات');
      expect(c.medWords, 'المعده', reason: 'بعد التطبيع');
      expect(c.timesPerDay, 3);
      expect(c.timings, [const SpokenTiming(relation: MealRelation.before)]);
    });
    test('«مرتين في اليوم» / «مرة واحدة» / «كل تمن ساعات»', () {
      expect(parseCommand('ضيفلي دوا الضغط مرتين في اليوم').timesPerDay, 2);
      expect(parseCommand('ضيفلي دوا مرة واحدة بس').once, isTrue);
      expect(parseCommand('ضيفلي مضاد حيوي كل تمن ساعات').everyHours, 8);
      expect(parseCommand('ضيفلي دوا كل ٨ ساعات').everyHours, 8);
    });
    test('الساعة الثابتة', () {
      final c = parseCommand('ضيفلي دوا الضغط الساعة تمانية الصبح');
      expect(c.timings, [const SpokenTiming(fixed: SpokenTime(8, 0))]);
    });
    test('من غير اسم = null، والشاشة بتسأل', () {
      expect(parseCommand('ضيف دوا').medWords, isNull);
      expect(parseCommand('ضيفلي دوا اسمه كونكور').medWords, 'اسمه كونكور');
    });
  });

  group('سؤال طبي (medical_question) — دايماً للدكتور', () {
    for (final s in [
      'جرعة الكونكور كام؟',
      'أخد جرعتين؟',
      'ممكن أزود الجرعة؟',
      'أقلل الدوا؟',
      'أوقف الدوا؟',
      'هل أوقف دوا الضغط',
      'ينفع أبطل الدوا',
      'إيه الأعراض الجانبية',
      'الدوا ده بيسبب دوخة؟',
      'عندي صداع من الدوا',
      'ينفع آخد الدوا مع الأكل',
      'ممكن آخد دواين مع بعض',
      'الدوا ده يتعارض مع السكر؟',
      'ضغطي عالي أعمل إيه',
      'سكري عالي',
      'أخدت جرعة زيادة أعمل إيه',
      'أخدت الدوا مرتين بالغلط أعمل إيه',
      'إيه أحسن دوا للضغط',
      'ينفع أصوم وأنا باخد الدوا',
      'حرارتي عالية آخد إيه',
      'تعبان ودايخ',
      'الدوا ده لإيه',
      'بديل الكونكور إيه',
      'ينفع أشرب قهوة مع الدوا',
    ]) {
      intent(s, CommandIntent.medicalQuestion);
    }
    test('«أخدت جرعة زيادة» طبي مش أخدته — الطبي قبل أي حاجة', () {
      expect(parseCommand('أخدت جرعة زيادة أعمل إيه').intent, CommandIntent.medicalQuestion);
      expect(parseCommand('أخدت الجرعة').intent, CommandIntent.markTaken, reason: '«الجرعة» لوحدها اسم جرعته');
    });
  });

  group('مش أمر (unknown)', () {
    for (final s in [
      '',
      'أيوه',
      'لأ',
      'صباح الخير',
      'إزيك',
      'الساعة كام',
      'الجو حر النهارده',
      'اتصل بابني',
      'افتح الكاميرا',
      'ماخدتش الدوا',
      'كلمني',
      'شكراً',
      'عايز أنام',
      'فين الصيدلية',
      'غيّر الساعة',
      'امسح الدوا',
    ]) {
      intent(s, CommandIntent.unknown);
    }
  });

  group('مطابقة الدوا على القايمة المحلية', () {
    const names = ['Concor 5mg', 'Glucophage 1000', 'Augmentin 1g', 'اومبيرازول ٢٠', 'Panadol Extra'];
    const purposes = {'Concor 5mg': 'ضغط', 'Glucophage 1000': 'سكر', 'اومبيرازول ٢٠': 'معدة وقولون'};

    test('التطبيع: ة/ه، ى/ي، أ/ا، شيل «ال» والتركيز', () {
      expect(medKey('الكونكور'), 'كونكور');
      expect(medKey('Concor 5mg'), 'concor');
      expect(medKey('أومبيرازول ٢٠'), 'اومبيرازول');
      expect(medKey('الأوجمنتين'), 'اوجمنتين');
    });
    test('بالاسم زي ما اتقال — لاتيني على لاتيني بالحروف، وعربي على لاتيني بالصوت', () {
      expect(matchMedication('كونكور', names).names, ['Concor 5mg'], reason: 'الهيكل الصوتي');
      expect(matchMedication('concor', names).names, ['Concor 5mg']);
      expect(matchMedication('اومبيرازول', names).names, ['اومبيرازول ٢٠']);
      expect(matchMedication('الأومبيرازول', names).names, ['اومبيرازول ٢٠']);
      expect(matchMedication('اومبرازول', names).names, ['اومبيرازول ٢٠'], reason: 'حرف ناقص');
    });
    test('بالغرض: «الضغط» ↔ دوا غرضه ضغط', () {
      expect(matchMedication('الضغط', names, purposes: purposes).names, ['Concor 5mg']);
      expect(matchMedication('السكر', names, purposes: purposes).names, ['Glucophage 1000']);
      expect(matchMedication('المعدة', names, purposes: purposes).names, ['اومبيرازول ٢٠']);
    });
    test('كذا دوا لنفس الغرض = أنهي واحد؟', () {
      final m = matchMedication('الضغط', ['Concor 5mg', 'Amlodipine'], purposes: {'Concor 5mg': 'ضغط', 'Amlodipine': 'ضغط'});
      expect(m.ambiguous, isTrue);
      expect(m.names, ['Concor 5mg', 'Amlodipine']);
    });
    test('ولا واحد / من غير اسم', () {
      expect(matchMedication('الفيتامين', names, purposes: purposes).none, isTrue);
      expect(matchMedication(null, names).none, isTrue);
      expect(matchMedication('ال', names).none, isTrue);
    });
  });

  group('عربي ↔ لاتيني — الهيكل الصوتي', () {
    // الروشتة بتتحفظ باللاتيني، والمريض بيقولها بالمصري
    const pairs = <String, String>{
      'كونكور': 'Concor 5mg',
      'جلوكوفاج': 'Glucophage 1000',
      'أملور': 'Amlor 5',
      'نكسيوم': 'Nexium 40mg',
      'كونجستال': 'Congestal',
      'بنادول': 'Panadol Extra',
      'بروفين': 'Brufen 400',
      'كتافلام': 'Cataflam 50',
      'ليبيتور': 'Lipitor 20mg',
      'كريستور': 'Crestor 10',
      'نورفاسك': 'Norvasc 5',
      'بلافيكس': 'Plavix 75',
      'زيرتك': 'Zyrtec',
      'فنتولين': 'Ventolin',
      'أوجمنتين': 'Augmentin 1g',
      'أموكسيل': 'Amoxil',
      'فلاجيل': 'Flagyl 500',
      'موتيليوم': 'Motilium',
      'أوميبرازول': 'Omeprazole 20',
      'فولتارين': 'Voltaren',
      'أنتينال': 'Antinal',
      'دافلون': 'Daflon 500',
      'بيتاسيرك': 'Betaserc 24',
      'دياميكرون': 'Diamicron MR',
      'جانوفيا': 'Januvia 100',
      'التروكسين': 'Eltroxin 50',
      'أسبوسيد': 'Aspocid 75',
      'لازيكس': 'Lasix 40',
      'كابوتين': 'Capoten',
      'تلفاست': 'Telfast 180',
      'كلاريتين': 'Claritine',
      'زيثروماكس': 'Zithromax',
      'سيبرو': 'Cipro 500',
      'ميكارديس': 'Micardis',
      'إكسفورج': 'Exforge',
    };
    pairs.forEach((spoken, saved) {
      test('«$spoken» ↔ $saved', () {
        expect(matchMedication(spoken, [saved]).names, [saved]);
        expect(matchMedication('دوا $spoken', [saved]).names, [saved], reason: 'مع «دوا»');
        expect(phoneticClose(spoken, medKey(saved).split(' ').first), isTrue, reason: '${phoneticKey(spoken)} ≠ ${phoneticKey(saved)}');
      });
    });

    test('والعكس: الاسم متحفوظ بالعربي والمتعرّف رجّع لاتيني', () {
      expect(matchMedication('concor', ['كونكور ٥']).names, ['كونكور ٥']);
      expect(matchMedication('Glucophage', ['جلوكوفاج']).names, ['جلوكوفاج']);
    });

    test('قريب-مش-هو: ما يتطابقش', () {
      const saved = ['Concor 5mg', 'Congestal', 'Amlor 5', 'Amoxil', 'Nexium 40mg', 'Lipitor 20mg', 'Lasix 40', 'Zyrtec', 'Brufen 400', 'Panadol Extra'];
      for (final s in ['كوندور', 'كانتور', 'أموتريل', 'نيكسافار', 'ليبيدور', 'لاميكتال', 'زيلتك', 'بروفيلاك', 'بانتوجار', 'كوجيت']) {
        final m = matchMedication(s, saved);
        expect(m.names, isEmpty, reason: '«$s» طلع ${m.names} (${phoneticKey(s)})');
      }
    });

    test('اسم بيقرّب من اتنين = الاتنين يرجعوا (الشاشة بتسأل «أنهي واحد؟») — مش تخمين', () {
      final m = matchMedication('كونكور', ['Concor 5mg', 'Concor 10mg']);
      expect(m.ambiguous, isTrue);
      expect(m.names, ['Concor 5mg', 'Concor 10mg']);
    });

    test('الهياكل نفسها — للمراجعة بالعين', () {
      expect(phoneticKey('كونكور'), 'knkr');
      expect(phoneticKey('Concor'), 'knkr');
      expect(phoneticKey('Glucophage'), 'glkfg');
      expect(phoneticKey('جلوكوفاج'), 'glkfg');
      expect(phoneticKey('Aspocid'), 'sbsd');
      expect(phoneticKey('أسبوسيد'), 'sbsd');
      expect(phoneticKey('Nexium'), 'nksm');
      expect(phoneticKey('نكسيوم'), 'nksm');
    });
  });
}
