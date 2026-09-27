// «بيفهم» — المرحلة ٣: فهم الطلبات المفتوحة بالمصري، **على الموبايل وبس**.
//
// نفس أسلوب `answer_parser.dart`: دارت نقية، قواعد مش ذكاء، وكل حاجة مش
// مفهومة = [CommandIntent.unknown] من غير تخمين. أي سؤال طبي (جرعة، أعراض،
// «أوقف؟») = [CommandIntent.medicalQuestion] — وده **قبل** أي فهم تاني، عشان
// «أخدت جرعة زيادة أعمل إيه؟» ما يتفهمش «أخدته».
//
// اسم الدوا بيتطلّع **زي ما اتقال** ([VoiceCommand.medWords]) — المطابقة على
// قايمة أدوية المريض المحلية في [matchMedication]، بتطبيع ة/ه وى/ي وأ/ا
// وشيل «ال». ومفيش جدولة هنا: مواعيد «ضيفلي» بترجع كلمات ([SpokenTiming])،
// والشاشة هي اللي بتحوّلها لمراسي — ومفيش حاجة بتتحفظ غير من زرار «احفظ».

import '../../domain/medication/medicine_name.dart';
import '../../domain/voice/answer_parser.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/voice/arabic_dates.dart';
import '../../domain/voice/arabic_numbers.dart';

/// النيات — **الأدوات** نفسها اللي السحابة بتختار منها (`command_reader`):
/// كتابة (بتأكيد أو بفورم) وقراية (رد بس).
enum CommandIntent {
  markTaken,
  nextDose,
  todayList,
  addMed,
  addAppointment,
  snooze,
  addVital,
  addDoctorQuestion,
  markBought,
  upcomingAppointments,
  stockStatus,
  medicalQuestion,
  unknown,
}

/// نوع الميعاد.
enum AppointmentKind { doctor, lab, scan, other }

/// ميعاد اتقال: النوع، مع مين، اليوم، والساعة — اللي ناقص بيتسأل عليه مرة.
class SpokenAppointment {
  const SpokenAppointment({this.kind = AppointmentKind.other, this.withWhom, this.date, this.time, this.hourNeedsPeriod, this.place});
  final AppointmentKind kind;
  final String? withWhom;
  final DateTime? date;
  final SpokenTime? time;

  /// «الساعة ٥» من غير الصبح/بالليل — بنسأل، مش بنخمّن.
  final int? hourNeedsPeriod;
  final String? place;

  SpokenAppointment copyWith({DateTime? date, SpokenTime? time, int? hourNeedsPeriod, bool clearHour = false}) => SpokenAppointment(
        kind: kind,
        withWhom: withWhom,
        date: date ?? this.date,
        time: time ?? this.time,
        hourNeedsPeriod: clearHour ? null : (hourNeedsPeriod ?? this.hourNeedsPeriod),
        place: place,
      );

  @override
  String toString() => 'SpokenAppointment($kind, $withWhom, ${date == null ? null : isoDate(date!)}, $time, h?=$hourNeedsPeriod)';
}

/// نوع القياس — نفس أنواع «سجّل قياس» زائد السكر.
enum VitalType { bp, sugar, pulse, weight, temp, o2 }

/// قياس اتقال: النوع والأرقام زي ما جت («١٢٠ على ٨٠» = [١٢٠، ٨٠]).
class SpokenVital {
  const SpokenVital(this.type, this.values);
  final VitalType type;
  final List<double> values;

  @override
  String toString() => 'SpokenVital($type, $values)';
}

/// ميعاد اتقال في «ضيفلي»: كلمة أكل («الفطار») وعلاقتها — **كلمة تعليمات،
/// مش ساعة** (الروتين اتشال) — أو ساعة بالحرف.
class SpokenTiming {
  const SpokenTiming({this.anchorWord, this.relation, this.fixed, this.hourNeedsPeriod});

  /// «الصحيان» / «الفطار» / «الغدا» / «العشا» / «النوم» — بعد التطبيع.
  final String? anchorWord;
  final MealRelation? relation;
  final SpokenTime? fixed;

  /// «الساعة ٩» من غير الصبح ولا بالليل — ساعة ناقصة جزء يومها، بتتسأل.
  final int? hourNeedsPeriod;

  @override
  bool operator ==(Object other) =>
      other is SpokenTiming && other.anchorWord == anchorWord && other.relation == relation && other.fixed == fixed && other.hourNeedsPeriod == hourNeedsPeriod;
  @override
  int get hashCode => Object.hash(anchorWord, relation, fixed, hourNeedsPeriod);
  @override
  String toString() => 'SpokenTiming($anchorWord, $relation, $fixed, h?=$hourNeedsPeriod)';
}

class VoiceCommand {
  const VoiceCommand(
    this.intent, {
    this.medWords,
    this.timings = const [],
    this.timesPerDay,
    this.everyHours,
    this.once = false,
    this.appointment,
    this.snoozeMinutes,
    this.vital,
    this.questionText,
    this.durationDays,
    this.startDate,
    this.weekdays = const [],
  });

  final CommandIntent intent;

  /// اسم الدوا زي ما اتقال («الكونكور»، «الضغط») — null = «الدوا» بس.
  final String? medWords;
  final List<SpokenTiming> timings;
  final int? timesPerDay;
  final int? everyHours;
  final bool once;
  final SpokenAppointment? appointment;

  /// «فكّرني بعد ١٠ دقايق» — null = الربع ساعة العادية.
  final int? snoozeMinutes;
  final SpokenVital? vital;
  final String? questionText;
  final int? durationDays;
  final DateTime? startDate;

  /// أيام الأسبوع (١ = الاتنين … ٧ = الحد) لو قال «أيام معينة».
  final List<int> weekdays;

  VoiceCommand copyWith({List<SpokenTiming>? timings, SpokenAppointment? appointment, SpokenVital? vital}) => VoiceCommand(
        intent,
        medWords: medWords,
        timings: timings ?? this.timings,
        timesPerDay: timesPerDay,
        everyHours: everyHours,
        once: once,
        appointment: appointment ?? this.appointment,
        snoozeMinutes: snoozeMinutes,
        vital: vital ?? this.vital,
        questionText: questionText,
        durationDays: durationDays,
        startDate: startDate,
        weekdays: weekdays,
      );

  static const unknown = VoiceCommand(CommandIntent.unknown);
  static const medical = VoiceCommand(CommandIntent.medicalQuestion);

  @override
  String toString() =>
      'VoiceCommand($intent, med=$medWords, timings=$timings, x$timesPerDay, every=$everyHours, once=$once, appt=$appointment, snooze=$snoozeMinutes, vital=$vital, q=$questionText)';
}

// ---------------------------------------------------------------- كلمات

const _medNouns = {'دوا', 'دواء', 'الدوا', 'الدواء', 'دوايا', 'دوائي', 'حبايه', 'حبه', 'الحبايه', 'برشام', 'البرشام', 'علاج', 'العلاج', 'قرص', 'القرص', 'حقنه', 'الحقنه', 'ادويتي', 'ادويه', 'الادويه', 'جرعه', 'الجرعه', 'جرعتي', 'جرعاتي', 'مضاد', 'فيتامين', 'كبسوله', 'كبسول', 'شراب', 'نقط', 'حقن', 'لبوس', 'مرهم', 'كريم', 'بخاخ'};

const _tookVerbs = {'اخدت', 'خدت', 'اخدته', 'خدته', 'اخدتها', 'خدتها', 'اخدتهم', 'خدتهم', 'شربت', 'شربته', 'شربتها', 'بلعت', 'بلعته', 'بلعتها', 'اخذت', 'اخذته', 'تناولت'};

const _addVerbs = {'ضيف', 'ضيفلي', 'ضيفي', 'ضيفيلي', 'اضيف', 'اضيفلي', 'زود', 'زودلي', 'زودي', 'سجل', 'سجلي', 'سجللي', 'حط', 'حطلي', 'حطي', 'اضف', 'نضيف', 'تضيف', 'تضيفلي'};

const _nextWords = {'الجاي', 'الجايه', 'الجايّه', 'جاي', 'جايه', 'القادم', 'القادمه', 'بعدين', 'التاني', 'التانيه'};
const _whenWords = {'امتى', 'امتي', 'امتا', 'إمتى', 'الساعه', 'ساعه', 'معاد', 'ميعاد', 'معادها', 'ميعادها', 'معاده', 'ميعاده'};
const _todayWords = {'النهارده', 'النهاردا', 'انهارده', 'انهاردا', 'اليوم', 'النهار'};
const _whatWords = {'ايه', 'إيه', 'اي', 'ايش', 'شو', 'فين', 'كام', 'قولي', 'قوللي', 'قول', 'عايز', 'عاوز', 'اعرف', 'عرفني'};

/// **طبي — الأول دايماً.** جرعة، أعراض، تعارض، وقف، «ينفع».
const _medicalWords = {
  // جرعة وتغييرها («جرعه» لوحدها ضعيفة — «أخدت الجرعة» مش سؤال)
  'جرعه', 'الجرعه', 'جرعتين', 'ازود', 'اقلل', 'انقص', 'اضاعف', 'اوقف', 'اوقفه', 'اوقفها', 'ابطل', 'ابطله', 'اقطع', 'اقطعه', 'زياده', 'ناقصه', 'كام', 'قد',
  // أعراض وتشخيص
  'اعراض', 'الاعراض', 'جانبيه', 'صداع', 'دوخه', 'دايخ', 'دايخه', 'تعبان', 'تعبانه', 'وجع', 'الم', 'حراره', 'حرارتي', 'سخنه', 'سخن', 'غثيان', 'ترجيع', 'مغص', 'اسهال', 'امساك', 'ضيق', 'نفس', 'حرقان', 'حساسيه', 'طفح', 'هرش', 'رعشه', 'خفقان', 'تنميل', 'عندي',
  // تعارض ونصيحة
  'يتعارض', 'تعارض', 'يتعارضوا', 'مع', 'ينفع', 'ممكن', 'اقدر', 'يصح', 'اشرب', 'اكل', 'اصوم', 'حامل', 'رضاعه', 'بيسبب', 'يسبب', 'بيعمل', 'يعمل', 'ضرر', 'يضر', 'خطر', 'مفيد', 'احسن', 'افضل', 'الافضل', 'بديل', 'مكانه', 'بدل', 'اجرب', 'اعمل', 'الحل', 'علاجه', 'يعالج', 'بيعالج', 'تشخيص', 'مرض', 'مريض', 'اسباب', 'سبب',
  // قياسات كأسئلة
  'عالي', 'عاليه', 'واطي', 'واطيه', 'مرتفع', 'مرتفعه', 'منخفض', 'منخفضه', 'طبيعي', 'ضغطي', 'سكري', 'نبضي',
  // «الدوا ده لإيه؟» — الغرض سؤال للدكتور، مش لينا
  'لايه', 'لإيه',
};

const _anchorWords = <String, String>{
  'الفطار': 'الفطار', 'الفطور': 'الفطار', 'فطار': 'الفطار', 'الافطار': 'الفطار', 'فطور': 'الفطار', 'الفطر': 'الفطار',
  'الغدا': 'الغدا', 'الغداء': 'الغدا', 'غدا': 'الغدا', 'غداء': 'الغدا', 'الغده': 'الغدا',
  'العشا': 'العشا', 'العشاء': 'العشا', 'عشا': 'العشا', 'عشاء': 'العشا',
  'النوم': 'النوم', 'نوم': 'النوم', 'انام': 'النوم', 'ما': 'ما',
  'الصحيان': 'الصحيان', 'صحيان': 'الصحيان', 'اصحى': 'الصحيان', 'اصحي': 'الصحيان', 'الصحوه': 'الصحيان',
};

const _relationWords = <String, MealRelation>{
  'قبل': MealRelation.before,
  'مع': MealRelation.with_,
  'بعد': MealRelation.after,
  'عقب': MealRelation.after,
};

const _dayPartToAnchor = <String, String>{
  'الصبح': 'الفطار', 'صباحا': 'الفطار', 'صباح': 'الفطار', 'الفجر': 'الصحيان',
  'الضهر': 'الغدا', 'الظهر': 'الغدا', 'ظهرا': 'الغدا',
  'العصر': 'الغدا', 'المغرب': 'العشا', 'العشيه': 'العشا', 'مساء': 'العشا',
  'بالليل': 'النوم', 'الليل': 'النوم', 'ليلا': 'النوم',
};

const _stop = {'انا', 'يا', 'فكرني', 'من', 'فضلك', 'لو', 'سمحت', 'ده', 'دي', 'بتاع', 'بتاعي', 'بتاعتي', 'كده', 'خلاص', 'يعني', 'ال', 'ايوه', 'اه'};

// ---- المواعيد
const _bookVerbs = {'احجز', 'احجزلي', 'احجزيلي', 'حجزلي', 'حجزت', 'حجز', 'سجللي', 'سجل', 'ضيفلي', 'ضيف', 'حطلي', 'حط', 'عندي', 'فكرني'};
const _apptNouns = {'ميعاد', 'معاد', 'موعد', 'مواعيد', 'مواعيدي', 'ميعادي', 'معادي', 'الميعاد', 'المعاد', 'الموعد', 'المواعيد', 'كشف', 'زياره', 'حجز'};
const _apptQuestionWords = {'امتى', 'امتي', 'امتا', 'إمتى', 'ايه', 'إيه', 'اي', 'فين', 'كام', 'عندي', 'قولي', 'قوللي', 'اعرف', 'عرفني'};
const _doctorWords = {'دكتور', 'الدكتور', 'دكتوره', 'الدكتوره', 'د', 'كشف', 'الكشف', 'زياره', 'الزياره', 'العياده', 'عياده', 'الطبيب'};
const _labWords = {'معمل', 'المعمل', 'تحليل', 'التحليل', 'تحاليل', 'التحاليل', 'عينه', 'العينه'};
const _scanWords = {'اشعه', 'الاشعه', 'رنين', 'الرنين', 'سونار', 'السونار', 'ايكو', 'الايكو', 'مقطعيه', 'المقطعيه'};

// ---- القياسات — الاسم زي ما بيتقال، ونوعه
const _vitalWords = <String, VitalType>{
  'الضغط': VitalType.bp, 'ضغطي': VitalType.bp, 'ضغط': VitalType.bp,
  'السكر': VitalType.sugar, 'سكري': VitalType.sugar, 'سكر': VitalType.sugar,
  'النبض': VitalType.pulse, 'نبضي': VitalType.pulse, 'نبض': VitalType.pulse,
  'الوزن': VitalType.weight, 'وزني': VitalType.weight, 'وزن': VitalType.weight,
  'الحراره': VitalType.temp, 'حرارتي': VitalType.temp, 'حراره': VitalType.temp,
  'الاكسجين': VitalType.o2, 'اكسجين': VitalType.o2, 'اكسجيني': VitalType.o2, 'الاوكسجين': VitalType.o2,
};
const _judgeWords = {'عالي', 'عاليه', 'واطي', 'واطيه', 'مرتفع', 'مرتفعه', 'منخفض', 'منخفضه', 'طبيعي', 'طبيعيه', 'كويس', 'وحش', 'زايد', 'ناقص', 'نازل', 'طالع'};

// ---- سؤال للدكتور
const _askVerbs = {'اسال', 'اساله', 'اسالها', 'اسأل', 'سؤال', 'سوال', 'اسئل', 'نسال', 'افكر', 'افتكر', 'اسالو'};

// ---- التأجيل
const _snoozeWords = {'بعدين', 'شويه', 'اجل', 'اجلها', 'اجله', 'اجلي', 'اجلهم', 'اجيل', 'تاجيل', 'كمان'};

// ---- الشرا
const _boughtVerbs = {'اشتريت', 'اشترينا', 'شريت', 'جبت', 'جبته', 'جبتها', 'اشتريته', 'اشتريتها', 'اشتريتهم', 'جبتهم'};


// ---- المخزون
const _stockWords = {'فاضل', 'فاضله', 'فاضلي', 'فاضللي', 'باقي', 'المخزون', 'مخزون', 'يخلص', 'خلص', 'خلصت', 'خلصان', 'العلبه', 'علبه'};

/// تحويل يوم الأسبوع بكلمته لرقمه — للقارئ والاختبار.
int? weekdayNumber(String token) => const <String, int>{
      'الاتنين': 1, 'الاثنين': 1, 'التلات': 2, 'الثلاثاء': 2, 'الثلاث': 2, 'الاربع': 3, 'الاربعاء': 3,
      'الخميس': 4, 'الجمعه': 5, 'السبت': 6, 'الحد': 7, 'الاحد': 7,
    }[token];

// ---------------------------------------------------------------- الفهم

/// أرقام «مرة / مرتين / تلات مرات / أربع مرات» في اليوم.
const _timesWords = <String, int>{'مره': 1, 'مرتين': 2, 'تلات': 3, 'ثلاث': 3, 'اربع': 4, 'خمس': 5, 'ست': 6};

/// «وبعد العشا» → «و» + «بعد» — الواو الملزوقة بتتفصل قدّام كلمة ميعاد.
List<String> _tokens(String text) {
  final out = <String>[];
  for (final t in normalizeArabic(text.replaceAll(RegExp('[:\\-–—]'), ' ')).split(' ')) {
    if (t.isEmpty) continue;
    if (t.length > 2 && t.startsWith('و')) {
      final rest = t.substring(1);
      if (_relationWords.containsKey(rest) || _anchorWords.containsKey(rest) || _dayPartToAnchor.containsKey(rest) || rest == 'كل' || rest == 'الساعه' || weekdayNumber(rest) != null || _vitalWords.containsKey(rest)) {
        out
          ..add('و')
          ..add(rest);
        continue;
      }
    }
    out.add(t);
  }
  return out;
}

bool _hasAny(List<String> tokens, Set<String> words) => tokens.any(words.contains);

/// فهم طلب واحد. مش مفهوم = [VoiceCommand.unknown]. [now] لتواريخ المواعيد
/// («يوم الحد» = الحد الجاي).
VoiceCommand parseCommand(String text, {DateTime? now}) {
  final tokens = _tokens(text);
  if (tokens.isEmpty) return VoiceCommand.unknown;
  final today = now ?? DateTime.now();

  // نفي الأخذ («ماخدتش») مش أمر — وسؤال «أخدته ولا لأ؟» مش أمر
  final negatedTake = tokens.any((t) => t.startsWith('ما') && t.contains('خد') && t.endsWith('ش'));
  final mentionsMed = _mentionsMed(tokens);
  final adds = _hasAny(tokens, _addVerbs);

  // ---- سؤال للدكتور — قبل الطبي: «فكّرني أسأل الدكتور عن الجرعة» مش سؤال لينا
  final question = _parseDoctorQuestion(tokens);
  if (question != null) return question;

  // ---- قياس بأرقام — قبل الطبي: «ضغطي ١٢٠ على ٨٠» تسجيل، و«ضغطي عالي» سؤال
  if (!(adds && mentionsMed) && !_hasAny(tokens, _tookVerbs)) {
    final vital = _parseVital(text, tokens);
    if (vital != null) return vital;
  }

  // ---- طبي الأول: أي كلمة طبية ومعاها كلام عن دوا أو جسم = سؤال للدكتور
  if (_isMedical(tokens)) return VoiceCommand.medical;

  // ---- المواعيد الجاية (سؤال) — قبل الحجز: «ميعاد الدكتور إمتى؟»
  // «ميعاد الدوا» عن الدوا مش عن الزيارات — كلمات المواعيد بتتحسب لما مفيش دوا
  final mentionsAppt = !mentionsMed && _hasAny(tokens, _apptNouns);
  final apptDates = mentionsMed ? const <SpokenDate>[] : extractDates(text, now: today, future: true);
  final asksAppt = _hasAny(tokens, _apptQuestionWords) || _hasAny(tokens, _nextWords);
  if (mentionsAppt && asksAppt && apptDates.isEmpty && !tokens.contains('الساعه')) {
    return const VoiceCommand(CommandIntent.upcomingAppointments);
  }

  // ---- احجزلي ميعاد
  if (!mentionsMed &&
      (mentionsAppt || _hasAny(tokens, _labWords) || _hasAny(tokens, _scanWords) || _hasAny(tokens, _doctorWords)) &&
      (_hasAny(tokens, _bookVerbs) || mentionsAppt || apptDates.isNotEmpty)) {
    return _parseAppointment(text, tokens, today);
  }

  // ---- ضيف دوا — «ضيفلي كونكور الساعة ٨» من غير كلمة «دوا» برضه، لو فيه ميعاد
  final hasTiming = tokens.any((t) => (_anchorWords[t] != null && _anchorWords[t] != 'ما') || _relationWords.containsKey(t) || _dayPartToAnchor.containsKey(t) || t == 'الساعه' || _timesWords.containsKey(t) || t == 'كل');
  if (adds && (mentionsMed || (hasTiming && !mentionsAppt))) return _parseAdd(tokens, today);

  // ---- المخزون: «فاضل كام؟» / «قرب يخلص»
  if (_hasAny(tokens, _stockWords) && (mentionsMed || _hasAny(tokens, _whatWords) || tokens.any((t) => t == 'حبايه' || t == 'حبايات' || t == 'اقراص' || t == 'قرص'))) {
    return const VoiceCommand(CommandIntent.stockStatus);
  }

  // ---- اشتريت الدوا
  if (_hasAny(tokens, _boughtVerbs)) {
    return VoiceCommand(CommandIntent.markBought, medWords: _medWordsAfter(tokens, _boughtVerbs));
  }

  // ---- فكّرني بعدين
  final snooze = _parseSnooze(text, tokens);
  if (snooze != null) return snooze;

  // ---- إيه دوايا الجاي؟ / الدوا الجاي إمتى؟
  if (mentionsMed && (_hasAny(tokens, _nextWords) || _hasAny(tokens, _whenWords)) && !_hasAny(tokens, _tookVerbs)) {
    return const VoiceCommand(CommandIntent.nextDose);
  }

  // ---- إيه أدويتي النهارده؟
  if (mentionsMed && (_hasAny(tokens, _todayWords) || (_hasAny(tokens, _whatWords) && _plural(tokens)))) {
    return const VoiceCommand(CommandIntent.todayList);
  }

  // ---- أخدت دوا الضغط
  if (!negatedTake && _hasAny(tokens, _tookVerbs)) {
    return VoiceCommand(CommandIntent.markTaken, medWords: _medWordsAfter(tokens, _tookVerbs));
  }

  return VoiceCommand.unknown;
}

// ---------------------------------------------------------------- الأدوات الجديدة

/// «فكّرني أسأل الدكتور عن الصداع» / «سجل سؤال للدكتور: …».
VoiceCommand? _parseDoctorQuestion(List<String> tokens) {
  final doctorAt = tokens.indexWhere((t) => t == 'الدكتور' || t == 'للدكتور' || t == 'دكتور' || t == 'الدكتوره' || t == 'للدكتوره');
  if (doctorAt < 0) return null;
  if (!_hasAny(tokens, _askVerbs)) return null;
  // «ميعاد الدكتور» / «احجز» مش سؤال
  if (_hasAny(tokens, _apptNouns) || _hasAny(tokens, {'احجز', 'احجزلي', 'حجزت'})) return null;
  var rest = tokens.sublist(doctorAt + 1).where((t) => !_stop.contains(t)).toList();
  if (rest.isNotEmpty && (rest.first == 'عن' || rest.first == 'على' || rest.first == 'بخصوص')) rest = rest.sublist(1);
  if (rest.isEmpty) {
    // «اسأل الدكتور» من غير موضوع — السؤال قبل «الدكتور»؟ («ليه الدوا بيدوخني اسأل الدكتور»)
    final before = tokens.sublist(0, doctorAt).where((t) => !_askVerbs.contains(t) && !_stop.contains(t) && t != 'عايز' && t != 'عاوز' && t != 'لازم').toList();
    if (before.isEmpty) return const VoiceCommand(CommandIntent.addDoctorQuestion);
    return VoiceCommand(CommandIntent.addDoctorQuestion, questionText: before.join(' '));
  }
  return VoiceCommand(CommandIntent.addDoctorQuestion, questionText: rest.join(' '));
}

/// «ضغطي ١٢٠ على ٨٠» / «سجل السكر ١٥٠» / «وزني ٨٠ كيلو» — نوع + أرقام.
VoiceCommand? _parseVital(String text, List<String> tokens) {
  VitalType? type;
  for (final t in tokens) {
    final v = _vitalWords[t];
    if (v != null) {
      type = v;
      break;
    }
  }
  if (type == null) return null;
  if (_hasAny(tokens, _judgeWords)) return null;
  // «دوا الضغط» / «الضغط الجاي» مش قياس
  if (_mentionsMed(tokens) || _hasAny(tokens, _nextWords) || _hasAny(tokens, _whenWords)) return null;
  final numbers = extractNumbers(text).map((n) => n.value).toList();
  if (numbers.isEmpty) return null;
  // «١٢٠ على ٨٠»: رقمين للضغط، وإلا رقم واحد
  final values = type == VitalType.bp ? numbers.take(3).toList() : [numbers.first];
  if (type == VitalType.bp && values.length < 2) return VoiceCommand(CommandIntent.addVital, vital: SpokenVital(type, values));
  return VoiceCommand(CommandIntent.addVital, vital: SpokenVital(type, values));
}

/// «فكّرني بعدين» / «بعد شوية» / «أجّل الدوا» / «فكّرني بعد ١٠ دقايق».
VoiceCommand? _parseSnooze(String text, List<String> tokens) {
  final laterByNumber = tokens.any((t) => t.startsWith('دقيق') || t.startsWith('دقايق') || t.startsWith('دقائق') || t.startsWith('ساع')) && (tokens.contains('بعد') || tokens.contains('كمان'));
  if (!_hasAny(tokens, _snoozeWords) && !laterByNumber) return null;
  if (_hasAny(tokens, _addVerbs) && _mentionsMed(tokens)) return null;
  int? minutes;
  final i = tokens.indexWhere((t) => t == 'بعد' || t == 'كمان');
  if (i >= 0 && i + 1 < tokens.length) {
    final after = tokens.sublist(i + 1);
    final unit = after.firstWhere((t) => t.startsWith('دقيق') || t.startsWith('دقايق') || t.startsWith('ساع'), orElse: () => '');
    if (after.contains('ربع') && unit.startsWith('ساع')) {
      minutes = 15;
    } else if (after.contains('نص') && unit.startsWith('ساع')) {
      minutes = 30;
    } else if (after.contains('تلت') && unit.startsWith('ساع')) {
      minutes = 20;
    } else {
      final n = firstNumber(after.where((t) => t != 'ربع' && t != 'نص' && t != 'تلت').join(' '));
      if (n != null) minutes = unit.startsWith('ساع') ? (n * 60).round() : n.round();
    }
  }
  return VoiceCommand(CommandIntent.snooze, snoozeMinutes: minutes);
}

/// «احجزلي ميعاد دكتور يوم الحد الساعة ٥» — النوع، مع مين، اليوم، الساعة.
VoiceCommand _parseAppointment(String text, List<String> tokens, DateTime today) {
  var kind = AppointmentKind.other;
  if (_hasAny(tokens, _labWords)) kind = AppointmentKind.lab;
  if (_hasAny(tokens, _scanWords)) kind = AppointmentKind.scan;
  if (_hasAny(tokens, _doctorWords)) kind = AppointmentKind.doctor;
  final dates = extractDates(text, now: today, future: true);
  final date = dates.isEmpty ? null : dates.first.date;
  SpokenTime? time;
  int? hourNeedsPeriod;
  final at = tokens.indexWhere((t) => t == 'الساعه' || t == 'ساعه');
  if (at >= 0 && at + 1 < tokens.length) {
    final rest = tokens.sublist(at + 1, at + 1 + timeTokenSpan(tokens, at + 1)).join(' ');
    time = rest.isEmpty ? null : parseTime(rest);
    if (time == null) {
      final n = firstNumber(rest);
      if (n != null && n >= 1 && n <= 12 && n == n.roundToDouble()) hourNeedsPeriod = n.round();
    }
  }
  // مع مين: الكلمة اللي بعد «دكتور» لو مش تاريخ/ساعة/حشو
  String? withWhom;
  final d = tokens.indexWhere((t) => t == 'دكتور' || t == 'الدكتور' || t == 'دكتوره' || t == 'الدكتوره' || t == 'د');
  if (d >= 0) {
    final names = <String>[];
    for (final t in tokens.sublist(d + 1)) {
      if (t == 'يوم' || t == 'الساعه' || t == 'ساعه' || t == 'بكره' || t == 'بكرا' || t == 'بعد' || t == 'النهارده' || t == 'في' || weekdayNumber(t) != null || _stop.contains(t) || RegExp(r'^\d').hasMatch(t)) break;
      if (isNumberWord(t)) break;
      names.add(t);
    }
    if (names.isNotEmpty) withWhom = names.join(' ');
  }
  return VoiceCommand(
    CommandIntent.addAppointment,
    appointment: SpokenAppointment(kind: kind, withWhom: withWhom, date: date, time: time, hourNeedsPeriod: hourNeedsPeriod),
  );
}

bool _mentionsMed(List<String> tokens) => _hasAny(tokens, _medNouns);

bool _plural(List<String> tokens) => tokens.any((t) => t == 'ادويتي' || t == 'ادويه' || t == 'الادويه' || t == 'جرعاتي');

bool _isMedical(List<String> tokens) {
  final medical = tokens.where(_medicalWords.contains).length;
  if (medical == 0) return false;
  // «مع» و«عندي» و«كام» لوحدهم مش طبي — لازم كلمة تانية أو سؤال واضح
  final weak = {'مع', 'عندي', 'كام', 'قد', 'ممكن', 'اقدر', 'اعمل', 'بدل', 'مرض', 'سبب', 'يعمل', 'بيعمل', 'اكل', 'اشرب', 'جرعه', 'الجرعه'};
  final strong = tokens.where((t) => _medicalWords.contains(t) && !weak.contains(t)).length;
  if (strong > 0) return true;
  // كلمتين ضعاف مع بعض («ممكن اخد … مع …») أو ضعيفة + علامة سؤال
  final question = tokens.any((t) => t == 'هل' || t == 'ولا' || t == 'ليه' || t == 'ازاي' || t == 'اعمل');
  return medical >= 2 || (medical >= 1 && question && !_hasAny(tokens, _addVerbs));
}

/// الكلام اللي بعد فعل الأخذ، من غير «الدوا» ولا الحشو — «الضغط»، «الكونكور».
/// null = ما سمّاش دوا («أخدت الدوا»).
String? _medWordsAfter(List<String> tokens, Set<String> verbs) {
  final i = tokens.indexWhere(verbs.contains);
  final rest = tokens.sublist(i + 1).where((t) => !_stop.contains(t)).toList();
  final words = <String>[];
  var sawNoun = false;
  for (final t in rest) {
    if (_medNouns.contains(t)) {
      sawNoun = true;
      continue;
    }
    if (_anchorWords.containsKey(t) || _relationWords.containsKey(t) || _dayPartToAnchor.containsKey(t)) break;
    words.add(t);
  }
  if (words.isEmpty) return null;
  // «أخدت دوايا» / «أخدت الدوا» = من غير اسم
  if (!sawNoun && words.length == 1 && words.first.length <= 2) return null;
  return words.join(' ');
}

VoiceCommand _parseAdd(List<String> tokens, DateTime today) {
  final i = tokens.indexWhere(_addVerbs.contains);
  final rest = tokens.sublist(i + 1);
  // «الصبح بعد الفطار»: جزء اليوم بيكمّل الوجبة المذكورة، مش مرساة تانية
  final hasExplicitAnchor = rest.any((t) => _anchorWords.containsKey(t) && _anchorWords[t] != 'ما');

  // الاسم: بعد كلمة الدوا لحد أول كلمة ميعاد / عدد
  final nameWords = <String>[];
  var afterNoun = false;
  final timings = <SpokenTiming>[];
  int? timesPerDay;
  int? everyHours;
  int? durationDays;
  var once = false;
  MealRelation? pendingRelation;
  final weekdays = <int>[];
  final start = extractDates(rest.join(' '), now: today, future: true);

  for (var k = 0; k < rest.length; k++) {
    final t = rest[k];
    if (_medNouns.contains(t)) {
      afterNoun = true;
      continue;
    }
    if (_stop.contains(t)) continue;
    // «كل N ساعات»
    if (t == 'كل' && k + 1 < rest.length) {
      final n = parseNumber(rest[k + 1]);
      final unit = k + 2 < rest.length ? rest[k + 2] : '';
      if (n != null && (unit.startsWith('ساع'))) {
        everyHours = n;
        k += 2;
        continue;
      }
      if (rest[k + 1] == 'يوم') {
        k += 1;
        continue; // «كل يوم» = الافتراضي
      }
    }
    // «مرة واحدة» / «مرتين» / «تلات مرات»
    if (t == 'مره' && k + 1 < rest.length && (rest[k + 1] == 'واحده' || rest[k + 1] == 'بس')) {
      once = true;
      k += 1;
      continue;
    }
    if (_timesWords.containsKey(t) && (t == 'مرتين' || (k + 1 < rest.length && rest[k + 1].startsWith('مر')))) {
      timesPerDay = _timesWords[t];
      if (t != 'مرتين') k += 1;
      continue;
    }
    if (_relationWords.containsKey(t)) {
      pendingRelation = _relationWords[t];
      continue;
    }
    if (t == 'الاكل' || t == 'الأكل') {
      // «بعد الأكل» من غير وجبة = العلاقة بس، الوجبة من العدد
      if (pendingRelation != null) {
        timings.add(SpokenTiming(relation: pendingRelation));
        pendingRelation = null;
      }
      continue;
    }
    final anchor = _anchorWords[t];
    if (anchor != null && anchor != 'ما') {
      timings.add(SpokenTiming(anchorWord: anchor, relation: pendingRelation));
      pendingRelation = null;
      continue;
    }
    final dayAnchor = _dayPartToAnchor[t];
    if (dayAnchor != null) {
      if (!hasExplicitAnchor) {
        timings.add(SpokenTiming(anchorWord: dayAnchor, relation: pendingRelation));
        pendingRelation = null;
      }
      continue;
    }
    // ساعة ثابتة: «الساعة تمانية الصبح» — و«الساعة ٩» لوحدها = ساعة ناقصة
    // جزء يومها (بتتسأل، مش بتتخمّن)
    if ((t == 'الساعه' || t == 'ساعه') && k + 1 < rest.length) {
      // كلمات الساعة بس («٨ الصبح»، «تسعة ونص بالليل») — والكلام اللي بعدها
      // (كل يوم / لمدة …) بيتقرا عادي
      final span = timeTokenSpan(rest, k + 1);
      final after = rest.sublist(k + 1, k + 1 + span).join(' ');
      final fixed = span == 0 ? null : parseTime(after);
      if (fixed != null) {
        timings.add(SpokenTiming(fixed: fixed));
        k += span;
        continue;
      }
      final n = span == 0 ? null : firstNumber(after);
      if (n != null && n >= 1 && n <= 12 && n == n.roundToDouble()) {
        timings.add(SpokenTiming(hourNeedsPeriod: n.round()));
        k += span;
        continue;
      }
    }
    // «لمدة أسبوع» / «لمدة ٧ أيام»
    if ((t == 'لمده' || t == 'لمدة') && k + 1 < rest.length) {
      final n = firstNumber(rest.sublist(k + 1).join(' '));
      final unit = rest.sublist(k + 1).firstWhere((x) => x.startsWith('يوم') || x.startsWith('ايام') || x.startsWith('اسبوع') || x.startsWith('شهر'), orElse: () => '');
      final base = n ?? (unit.endsWith('ين') ? 2 : 1);
      durationDays = unit.startsWith('اسبوع') ? (base * 7).round() : unit.startsWith('شهر') ? (base * 30).round() : base.round();
      k += n == null ? 1 : 2;
      continue;
    }
    // «يوم السبت والتلات» / «من بكرة»
    final wd = weekdayNumber(t);
    if (wd != null) {
      weekdays.add(wd);
      continue;
    }
    if (t == 'يوم' && k + 1 < rest.length && weekdayNumber(rest[k + 1]) != null) continue;
    if (!afterNoun || timings.isNotEmpty || timesPerDay != null) {
      if (!afterNoun && !_medNouns.contains(t)) nameWords.add(t);
      continue;
    }
    nameWords.add(t);
  }

  // «بعد الأكل» لوحدها + علاقة معلّقة بعد وجبة مذكورة بالاسم
  if (pendingRelation != null && timings.isNotEmpty && timings.last.anchorWord != null && timings.last.relation == null) {
    timings[timings.length - 1] = SpokenTiming(anchorWord: timings.last.anchorWord, relation: pendingRelation);
  }
  // العلاقة اللي جت بعد المرساة («الفطار بعده»؟ نادر) — نسيبها
  final relOnly = timings.where((t) => t.anchorWord == null && t.fixed == null && t.hourNeedsPeriod == null).toList();
  final merged = <SpokenTiming>[];
  for (final t in timings) {
    if (t.anchorWord == null && t.fixed == null && t.hourNeedsPeriod == null) continue;
    if (t.anchorWord != null && t.relation == null && relOnly.isNotEmpty) {
      merged.add(SpokenTiming(anchorWord: t.anchorWord, relation: relOnly.first.relation));
    } else {
      merged.add(t);
    }
  }
  // «بعد الأكل مرتين» من غير وجبة — العلاقة بتتحفظ من غير مرساة
  if (merged.isEmpty && relOnly.isNotEmpty) merged.add(relOnly.first);

  // كلمات التاريخ («بكرة»، «من بكرة») مش من الاسم
  final dateWords = {for (final d in start) ...normalizeArabic(d.raw).split(' ')};
  nameWords.removeWhere((w) => dateWords.contains(w) || w == 'من' || w == 'يوم' || w == 'كل' || w == 'لمده');
  // «ضيف دوا … لا» — كلمة إجابة لوحدها عمرها ما تبقى اسم دوا
  final name = nameWords.isEmpty ? null : medicineNameOrNull(nameWords.join(' '));
  return VoiceCommand(
    CommandIntent.addMed,
    medWords: name,
    timings: merged,
    timesPerDay: timesPerDay,
    everyHours: everyHours,
    once: once,
    durationDays: durationDays,
    startDate: start.isEmpty ? null : start.first.date,
    weekdays: weekdays,
  );
}

const _periodTokens = {'الصبح', 'صباحا', 'صباح', 'الفجر', 'الضهر', 'الظهر', 'ظهرا', 'العصر', 'المغرب', 'مساء', 'بالليل', 'الليل', 'ليلا', 'ص', 'م'};
const _clockWords = {'و', 'الا', 'نص', 'ربع', 'تلت', 'واحده', 'اتنين', 'تلاته', 'اربعه', 'خمسه', 'سته', 'سبعه', 'تمانيه', 'ثمانيه', 'تسعه', 'عشره', 'حداشر', 'اتناشر', 'عشرين', 'تلاتين', 'اربعين', 'خمسين', 'خمس', 'عشر', 'دقيقه', 'دقايق'};

/// كام كلمة من [tokens] بداية من [from] هي كلمات ساعة («٨ الصبح»، «تسعة ونص
/// بالليل»، «بعد الضهر») — عشان الساعة تتقرا لوحدها والكلام اللي بعدها يفضل.
int timeTokenSpan(List<String> tokens, int from) {
  var n = 0;
  for (var i = from; i < tokens.length; i++) {
    final t = tokens[i];
    final isTime = RegExp(r'^\d{1,2}(:\d{2})?$').hasMatch(t) ||
        _periodTokens.contains(t) ||
        _clockWords.contains(t) ||
        (t == 'بعد' && i + 1 < tokens.length && (tokens[i + 1] == 'الضهر' || tokens[i + 1] == 'الظهر'));
    if (!isTime) break;
    n++;
  }
  return n;
}

// ---------------------------------------------------------------- مطابقة الأدوية

/// اسم للمقارنة: ة→ه، ى→ي، أ→ا، من غير «ال» ولا تركيز ولا وحدات.
String medKey(String name) {
  var s = normalizeArabic(name).toLowerCase();
  s = s.replaceAll(RegExp(r'\d+([.,]\d+)?\s*(mg|mcg|ml|g|iu|%|ملجم|ملغ|مج|مل|جم)?'), ' ');
  final words = <String>[];
  for (final w in s.split(' ')) {
    if (w.isEmpty) continue;
    var x = w;
    if (x.startsWith('ال') && x.length > 3) x = x.substring(2);
    if (x.startsWith('لل') && x.length > 3) x = x.substring(2);
    if (x == 'دوا' || x == 'دواء' || x == 'مج' || x == 'mg') continue;
    words.add(x);
  }
  return words.join(' ');
}

/// نتيجة المطابقة: واحد، أو كذا واحد (يتسألوا «أنهي واحد؟»)، أو ولا واحد.
class MedMatch {
  const MedMatch(this.names);
  final List<String> names;
  bool get none => names.isEmpty;
  bool get single => names.length == 1;
  bool get ambiguous => names.length > 1;
}

int _editDistance(String a, String b) {
  final dp = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    dp[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    dp[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
  }
  return dp[a.length][b.length];
}

bool _tokenMatches(String spoken, String candidate) {
  if (spoken == candidate) return true;
  if (spoken.length >= 4 && candidate.length >= 4 && (candidate.startsWith(spoken) || spoken.startsWith(candidate))) return true;
  if (spoken.length >= 5 && candidate.length >= 5 && _editDistance(spoken, candidate) <= 1) return true;
  return phoneticClose(spoken, candidate);
}

// ---------------------------------------------------------------- الصوت عبر الحروف

final _arabicLetter = RegExp(r'[\u0600-\u06FF]');
final _latinLetter = RegExp(r'[a-z]');

/// الهيكل الصوتي — حروف ساكنة لاتينية من غير حركات، عشان «كونكور» و«Concor»
/// يطلعوا `knkr`. الحركات (a e i o u y و ا ي) بتتشال، والأصوات اللي المصري
/// بينطقها واحد بتتوحّد: ك/ق/c/q → k، ب/p → b، ف/v → f، ج/g/j → g،
/// س/ص/ز/z/ث → s، ت/ط → t، د/ض/ذ → d، ph → f، x → ks، c قبل e/i/y → s.
String phoneticKey(String word) {
  final w = normalizeArabic(word);
  final b = StringBuffer();
  final runes = w.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final c = String.fromCharCode(runes[i]);
    final next = i + 1 < runes.length ? String.fromCharCode(runes[i + 1]) : '';
    String out;
    switch (c) {
      // عربي
      case 'ا' || 'و' || 'ي' || 'ع' || 'ء' || 'ه' when c == 'ه' && i == runes.length - 1:
        out = '';
      case 'ا' || 'و' || 'ي' || 'ع' || 'ء':
        out = '';
      case 'ب':
        out = 'b';
      case 'ت' || 'ط':
        out = 't';
      case 'ث' || 'س' || 'ص' || 'ز' || 'ش':
        out = 's';
      case 'ج' || 'غ':
        out = 'g';
      case 'ح' || 'ه' || 'خ':
        out = 'h';
      case 'د' || 'ض' || 'ذ':
        out = 'd';
      case 'ر':
        out = 'r';
      case 'ف':
        out = 'f';
      case 'ق' || 'ك':
        out = 'k';
      case 'ل':
        out = 'l';
      case 'م':
        out = 'm';
      case 'ن':
        out = 'n';
      // لاتيني
      case 'a' || 'e' || 'i' || 'o' || 'u' || 'y' || 'w':
        out = '';
      case 'p' when next == 'h':
        out = 'f';
        i++;
      case 'c' when next == 'h' || next == 'k':
        out = 'k';
        i++;
      case 's' when next == 'h':
        out = 's';
        i++;
      case 't' when next == 'h':
        out = 's'; // «ث» بالمصري «س»: Zithromax → زيثروماكس → سيسروماكس
        i++;
      case 'c' when next == 'e' || next == 'i' || next == 'y':
        out = 's';
      case 'c' || 'q' || 'k':
        out = 'k';
      case 'x':
        out = 'ks';
      case 'p' || 'b':
        out = 'b';
      case 'v' || 'f':
        out = 'f';
      case 'g' || 'j':
        out = 'g';
      case 'z' || 's':
        out = 's';
      case 'd':
        out = 'd';
      case 't':
        out = 't';
      case 'h' when i == runes.length - 1:
        out = ''; // «Zyrteh»؟ لأ — h في الآخر صامتة زي ة
      default:
        out = _latinLetter.hasMatch(c) ? c : '';
    }
    if (out.isNotEmpty && (b.isEmpty || !b.toString().endsWith(out[0]) || out.length > 1)) b.write(out);
  }
  // الحرفين المكررين واحد (Augmentin ← «أوجمنتين» نفس الشكل)
  return b.toString().replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
}

/// عربي على لاتيني (أو العكس) بالهيكل الصوتي — **متطابق**، أو حرف واحد فرق
/// في هيكل طويل (٦ حروف وأكتر): «كوندور» (kndr) مش Concor (knkr) — الفرق
/// الواحد في اسم قصير هو الفرق بين دواءين. نفس الحروف مع بعض مش هنا.
bool phoneticClose(String spoken, String candidate) {
  final spokenArabic = _arabicLetter.hasMatch(spoken);
  final candidateArabic = _arabicLetter.hasMatch(candidate);
  if (spokenArabic == candidateArabic) return false;
  final a = phoneticKey(spoken);
  final b = phoneticKey(candidate);
  if (a.length < 3 || b.length < 3) return false;
  if (a == b) return true;
  return a.length >= 6 && b.length >= 6 && _editDistance(a, b) <= 1;
}

/// مطابقة الكلام على أسامي أدوية المريض **المحلية** (وأغراضها لو اتبعتت في
/// [purposes]: الاسم → كلمة الغرض زي «الضغط»). «الكونكور» ↔ «Concor 5mg»
/// بعد التطبيع؛ «الضغط» ↔ دوا غرضه الضغط.
MedMatch matchMedication(String? spoken, List<String> names, {Map<String, String> purposes = const {}}) {
  if (spoken == null) return const MedMatch([]);
  final key = medKey(spoken);
  if (key.isEmpty) return const MedMatch([]);
  final spokenTokens = {
    ...key.split(' '),
    // «التروكسين» ↔ «Eltroxin»: الـ«ال» جزء من الاسم مش أداة تعريف — بنجرّب
    // الكلمة زي ما اتقالت كمان
    for (final w in normalizeArabic(spoken).split(' '))
      if (w.startsWith('ال') && w.length > 3) w,
  }.where((t) => t.isNotEmpty).toList();
  final hits = <String>[];
  for (final name in names) {
    final nameTokens = medKey(name).split(' ');
    final byName = spokenTokens.any((s) => nameTokens.any((n) => _tokenMatches(s, n)));
    final purpose = purposes[name];
    final byPurpose = purpose != null && spokenTokens.any((s) => _tokenMatches(s, medKey(purpose)));
    if (byName || byPurpose) hits.add(name);
  }
  return MedMatch(hits);
}
