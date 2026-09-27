/// **الروشتة بتقول إيه عن التوقيت — وبس.**
///
/// قرار المالك (٢٧ سبتمبر ٢٠٢٦، بعد تجربة الجهاز): التطبيق **عمره ما بيختار
/// ساعات الجرعات** من روشتة. «كل ١٢ ساعة» معلومة من الورقة، مش ٩ الصبح و٩
/// بالليل. الملف ده بيطلّع من كلام الورقة الحقايق المكتوبة فعلاً: كل كام
/// ساعة، كام مرة في اليوم، علاقته بالأكل، «قبل النوم» / «على الريق»، والساعة
/// **لو مكتوبة بالحرف** — وإلا «مش واضح». الساعات بيختارها الإنسان.
///
/// دارت نقية — بتتختبر من غير شبكة ولا موديل.
library;

import '../core/format/arabic_time.dart' show arabicNumber;
import '../domain/medication/meal_relation.dart';
import '../domain/scheduling/minute_of_day.dart';
import '../domain/voice/answer_parser.dart' show normalizeArabic;

/// لحظة من اليوم الورقة سمّتها — ملاحظة، مش ساعة.
enum TimingMoment {
  bedtime('قبل النوم'),
  wake('أول ما تصحى');

  const TimingMoment(this.label);
  final String label;

  static TimingMoment? fromStorage(String? s) => switch (s) {
        'bedtime' => TimingMoment.bedtime,
        'wake' => TimingMoment.wake,
        _ => null,
      };
}

/// اللي الورقة قالته عن التوقيت. **مفيش فيه ساعة غير المكتوبة بالحرف.**
class TimingFacts {
  const TimingFacts({
    this.clockTimes = const [],
    this.everyHours,
    this.timesPerDay,
    this.mealRelation,
    this.moments = const {},
    this.asNeeded = false,
    this.unclear = false,
  });

  /// ساعات مكتوبة على الورقة بالحرف («الساعة ٨ صباحاً») — بس.
  final List<MinuteOfDay> clockTimes;

  /// «كل ١٢ ساعة».
  final int? everyHours;

  /// «٣ مرات في اليوم» / «١×٣».
  final int? timesPerDay;

  final MealRelation? mealRelation;
  final Set<TimingMoment> moments;

  /// «عند اللزوم» — مفيش جدول أصلاً.
  final bool asNeeded;

  /// الورقة مش واضحة في التوقيت (أو ما قالتش حاجة).
  final bool unclear;

  bool get isEmpty =>
      clockTimes.isEmpty && everyHours == null && timesPerDay == null && mealRelation == null && moments.isEmpty && !asNeeded;

  /// كام جرعة في اليوم الورقة قالت — من «كل N ساعة» أو «N مرات». null = ما قالتش.
  int? get dosesPerDay => everyHours != null && everyHours! > 0 && 24 % everyHours! == 0
      ? 24 ~/ everyHours!
      : timesPerDay;

  /// الفاصل اللي «كمّل» بيقترحه بعد أول ساعة يختارها الإنسان — **بس لما الورقة
  /// كاتبة فاصل بالحرف** («كل ١٢ ساعة»). «٣ مرات في اليوم» مالهاش اقتراح:
  /// ٢٤÷٣ بيطلّع جرعة نص الليل، والمريض بيختار كل ساعة بنفسه (قرار المالك).
  int? get stepHours {
    final h = everyHours;
    if (h != null && h > 0 && h < 24 && 24 % h == 0) return h;
    return null;
  }

  /// «٣ مرات في اليوم» من غير فاصل — عدد الساعات اللي لازم تتختار قبل الحفظ.
  int? get timesToPick => everyHours == null && timesPerDay != null && timesPerDay! > 1 ? timesPerDay : null;

  /// الحقايق كلام — «كل ١٢ ساعة»، «٣ مرات في اليوم»، «بعد الأكل»، «قبل النوم».
  List<String> get words => [
        if (everyHours case final h?) 'كل ${hoursWord(h)}',
        if (everyHours == null && timesPerDay != null) timesPerDayWord(timesPerDay!),
        if (mealRelation case final m?) m.label,
        for (final m in moments) m.label,
        if (asNeeded) 'عند اللزوم',
      ];

  /// نفس الحقايق مع حاجة تانية من الورقة — الموجود هنا بيكسب. «مش واضح»
  /// لو الاتنين قالوا مش واضح، أو مفيش ولا معلومة خالص.
  TimingFacts orElse(TimingFacts other) {
    final merged = TimingFacts(
      clockTimes: clockTimes.isNotEmpty ? clockTimes : other.clockTimes,
      everyHours: everyHours ?? other.everyHours,
      timesPerDay: timesPerDay ?? other.timesPerDay,
      mealRelation: mealRelation ?? other.mealRelation,
      moments: {...moments, ...other.moments},
      asNeeded: asNeeded || other.asNeeded,
    );
    final unclearBoth = (unclear || isEmpty) && (other.unclear || other.isEmpty);
    final noSchedule = merged.clockTimes.isEmpty && merged.dosesPerDay == null && merged.moments.isEmpty && !merged.asNeeded;
    return TimingFacts(
      clockTimes: merged.clockTimes,
      everyHours: merged.everyHours,
      timesPerDay: merged.timesPerDay,
      mealRelation: merged.mealRelation,
      moments: merged.moments,
      asNeeded: merged.asNeeded,
      unclear: merged.isEmpty || (unclearBoth && noSchedule),
    );
  }

  @override
  String toString() =>
      'TimingFacts(clock=$clockTimes, every=$everyHours, x=$timesPerDay, meal=$mealRelation, moments=$moments, prn=$asNeeded, unclear=$unclear)';
}

/// «ساعة» / «ساعتين» / «٨ ساعات» / «١٢ ساعة».
String hoursWord(int h) => switch (h) {
      1 => 'ساعة',
      2 => 'ساعتين',
      >= 3 && <= 10 => '${arabicNumber(h)} ساعات',
      _ => '${arabicNumber(h)} ساعة',
    };

/// «مرة في اليوم» / «مرتين في اليوم» / «٣ مرات في اليوم».
String timesPerDayWord(int n) => switch (n) {
      1 => 'مرة في اليوم',
      2 => 'مرتين في اليوم',
      >= 3 && <= 10 => '${arabicNumber(n)} مرات في اليوم',
      _ => '${arabicNumber(n)} مرة في اليوم',
    };

const _numberWords = {
  'واحده': 1, 'واحد': 1, 'اتنين': 2, 'اثنين': 2, 'تلات': 3, 'تلاته': 3, 'ثلاث': 3, 'ثلاثه': 3,
  'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5, 'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7,
  'تمن': 8, 'تمانيه': 8, 'ثماني': 8, 'ثمانيه': 8, 'تسع': 9, 'تسعه': 9, 'عشر': 10, 'عشره': 10,
  'حداشر': 11, 'اتناشر': 12, 'اثني عشر': 12, 'اثنا عشر': 12,
};

int? _num(String s) => int.tryParse(s) ?? _numberWords[s];

const _numPattern = r'(\d{1,2}|واحده|واحد|اتنين|اثنين|تلاته|تلات|ثلاثه|ثلاث|اربعه|اربع|خمسه|خمس|سته|ست|سبعه|سبع|تمانيه|تمن|ثمانيه|ثماني|تسعه|تسع|عشره|عشر|حداشر|اتناشر)';

/// كلام التوقيت زي ما الورقة كاتباه ← حقايق. مش فاهم = [TimingFacts.unclear].
TimingFacts parseTimingText(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const TimingFacts(unclear: true);
  final t = ' ${normalizeArabic(raw).replaceAll('ـ', '')} ';

  // «عند اللزوم» — مفيش جدول
  final asNeeded = RegExp(r'عند اللزوم|وقت اللزوم|عند الحاجه|\bprn\b|when needed|as needed').hasMatch(t);

  // كل N ساعة
  int? everyHours;
  if (RegExp(r'كل ساعتين').hasMatch(t)) everyHours = 2;
  final every = RegExp('كل $_numPattern ?(ساعه|ساعات|س)(?=\\s|\$)').firstMatch(t) ??
      RegExp(r'every (\d{1,2}) ?(h|hr|hrs|hour|hours)\b').firstMatch(t) ??
      RegExp(r'\bq ?(\d{1,2}) ?h\b').firstMatch(t);
  if (every != null) everyHours = _num(every.group(1)!);
  if (everyHours != null && (everyHours < 1 || everyHours > 24)) everyHours = null;

  // N مرات / ١×٣
  int? times;
  final mult = RegExp(r'(\d) ?[x×*] ?(\d)').firstMatch(t);
  if (mult != null) {
    final a = int.parse(mult.group(1)!), b = int.parse(mult.group(2)!);
    // «١×٣» = قرص ٣ مرات؛ الرقم الأكبر هو المرات
    times = a > b ? a : b;
  }
  if (RegExp(r'مرتين').hasMatch(t) || RegExp(r'\b(twice|bid|b\.i\.d)\b').hasMatch(t)) times ??= 2;
  final nTimes = RegExp('$_numPattern ?مرات').firstMatch(t);
  if (nTimes != null) times ??= _num(nTimes.group(1)!);
  if (RegExp(r'\b(three times|tid|t\.i\.d)\b').hasMatch(t)) times ??= 3;
  if (RegExp(r'\b(four times|qid|q\.i\.d)\b').hasMatch(t)) times ??= 4;
  if (RegExp(r'مره واحده|مره في اليوم|مره يوميا|مره كل يوم|\b(once|od|o\.d)\b').hasMatch(t)) times ??= 1;
  if (times != null && (times < 1 || times > 12)) times = null;

  // الأكل — كلمة تعليمات
  MealRelation? meal;
  if (RegExp(r'علي الريق|على الريق|علي معده فاضيه|على معده فاضيه|empty stomach').hasMatch(t)) {
    meal = MealRelation.emptyStomach;
  } else if (RegExp(r'قبل (الاكل|الفطار|الغدا|الغداء|العشا|العشاء|الاكلات)|before (meals?|food)|\bac\b').hasMatch(t)) {
    meal = MealRelation.before;
  } else if (RegExp(r'بعد (الاكل|الفطار|الغدا|الغداء|العشا|العشاء|الاكلات)|after (meals?|food)|\bpc\b').hasMatch(t)) {
    meal = MealRelation.after;
  } else if (RegExp(r'مع (الاكل|الفطار|الغدا|الغداء|العشا|العشاء)|with (meals?|food)').hasMatch(t)) {
    meal = MealRelation.with_;
  }

  final moments = <TimingMoment>{
    if (RegExp(r'قبل النوم|at bedtime|\bhs\b').hasMatch(t)) TimingMoment.bedtime,
    if (RegExp(r'اول ما (تصحي|يصحي)|بعد الصحيان|on waking').hasMatch(t)) TimingMoment.wake,
  };

  // ساعة مكتوبة بالحرف — لازم تبقى ساعة فعلاً: «الساعة ٨ صباحاً» أو «20:00».
  // «الساعة ٨» من غير الصبح/بالليل مش واضحة — ما بنختارش عنه.
  final clocks = <MinuteOfDay>[];
  var ambiguousClock = false;
  for (final m in RegExp(r'(?:الساعه|at) ?(\d{1,2})(?::(\d{2}))? ?(صباحا|صباح|الصبح|ص|am|a\.m|مساء|مساءا|م|pm|p\.m|بالليل|ليلا|الضهر|الظهر|ظهرا|العصر)?(?=\s|$)')
      .allMatches(t)) {
    var h = int.parse(m.group(1)!);
    final min = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    final period = m.group(3);
    if (h > 23 || min > 59) continue;
    if (period == null) {
      if (h > 12 || h == 0) {
        clocks.add(MinuteOfDay.hm(h, min)); // ٢٠:٠٠ مش محتاجة ص/م
      } else {
        ambiguousClock = true;
      }
      continue;
    }
    final pm = const {'مساء', 'مساءا', 'م', 'pm', 'p.m', 'بالليل', 'ليلا', 'العصر'}.contains(period) ||
        (const {'الضهر', 'الظهر', 'ظهرا'}.contains(period) && h < 11);
    if (pm && h < 12) h += 12;
    if (!pm && h == 12) h = 0;
    clocks.add(MinuteOfDay.hm(h, min));
  }
  // «20:00» من غير «الساعة»
  if (clocks.isEmpty && !ambiguousClock) {
    for (final m in RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').allMatches(t)) {
      final h = int.parse(m.group(1)!);
      if (h > 12) clocks.add(MinuteOfDay.hm(h, int.parse(m.group(2)!)));
    }
  }

  final facts = TimingFacts(
    clockTimes: clocks,
    everyHours: everyHours,
    timesPerDay: times,
    mealRelation: meal,
    moments: moments,
    asNeeded: asNeeded,
  );
  if (facts.isEmpty || ambiguousClock && clocks.isEmpty && facts.everyHours == null && facts.timesPerDay == null) {
    return TimingFacts(
      everyHours: everyHours,
      timesPerDay: times,
      mealRelation: meal,
      moments: moments,
      asNeeded: asNeeded,
      unclear: true,
    );
  }
  return facts;
}

/// «يوم» / «يومين» / «٧ أيام» / «١٤ يوم».
String daysWord(int d) => switch (d) {
      1 => 'يوم',
      2 => 'يومين',
      >= 3 && <= 10 => '${arabicNumber(d)} أيام',
      _ => '${arabicNumber(d)} يوم',
    };
