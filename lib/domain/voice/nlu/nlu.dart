// «كلّمني» — فهم الطلب على الموبايل: الجملة ← التطبيع ← النية ← الخانات.
//
// بورت أفكار `intent.js` من jarvis: كل نية ليها كلمات بتدّيها نقط، والأعلى
// بيكسب، والتعادل = سؤال واحد («قصدك …ولا …؟»). **مفيش ذكاء، ومفيش تخمين**:
// خانة ما اتقالتش بتفضل فاضية وبتتقال «لسه هتختارها» — وأهمها الساعات: «كل
// ١٢ ساعة» معلومة، مش ٨ و٨. ده بيغطّي الأربع نيات اللي كانت بتقع على الجهاز
// (أقرب مكان، ضيف دوا، احجز ميعاد، احجز تحليل)؛ الباقي (أخدته، أجّل، قياس…)
// لسه في `command_parser.dart` زي ما هو.
//
// دارت نقية.
library;

import '../../medication/meal_relation.dart';
import '../../places/specialty.dart';
import '../../medication/medicine_name.dart';
import '../answer_parser.dart' show SpokenTime, parseNumber, parseTime;
import '../arabic_dates.dart' show extractDates;
import '../arabic_numbers.dart' show isNumberWord;
import 'normalize.dart';

enum NluIntent { findNearby, addMedication, bookAppointment, bookLab, none }

/// نوع المكان في «القريب مني».
enum NearbyPlace { pharmacy, doctor, hospital, lab }

/// اللي اتفهم — النية وخاناتها. خانة null = ما اتقالتش.
class NluResult {
  const NluResult(
    this.intent, {
    this.alternatives = const [],
    this.place,
    this.name,
    this.doseText,
    this.everyHours,
    this.perDay,
    this.times = const [],
    this.hourNeedsPeriod,
    this.food,
    this.durationDays,
    this.doctorName,
    this.specialtyKind,
    this.testName,
    this.labName,
    this.date,
    this.time,
  });

  final NluIntent intent;

  /// تعادل: النيتين اللي محتاجين سؤال — [intent] ساعتها [NluIntent.none].
  final List<NluIntent> alternatives;

  final NearbyPlace? place;

  // ---- ضيف دوا
  final String? name;
  final String? doseText;
  final int? everyHours;
  final int? perDay;

  /// ساعات **اتقالت بالحرف** بجزء يومها — «الساعة ٩» لوحدها مش هنا.
  final List<SpokenTime> times;

  /// «الساعة ٩» من غير الصبح/بالليل — ما بنختارش عنه.
  final int? hourNeedsPeriod;
  final MealRelation? food;
  final int? durationDays;

  // ---- احجز ميعاد / تحليل
  final String? doctorName;

  /// التخصص اللي اتقال — للحجز («دكتور عيون») ولـ«القريب مني» («أقرب دكتور
  /// عيون» بتفتح على الدكاترة والتخصص ده).
  final Specialty? specialtyKind;
  String? get specialty => specialtyKind?.label;
  final String? testName;
  final String? labName;
  final DateTime? date;
  final SpokenTime? time;

  bool get isAmbiguous => intent == NluIntent.none && alternatives.length > 1;

  /// الخانات الأساسية اللي ناقصة — للتأكيد («لسه هتختارها»).
  List<String> get missing => switch (intent) {
        NluIntent.addMedication => [if (name == null) 'name', if (times.isEmpty) 'times'],
        NluIntent.bookAppointment => [if (doctorName == null && specialty == null) 'doctor', if (date == null) 'date', if (time == null) 'time'],
        NluIntent.bookLab => [if (testName == null) 'test', if (date == null) 'date', if (time == null) 'time'],
        _ => const [],
      };

  @override
  String toString() =>
      'NluResult($intent${alternatives.isEmpty ? '' : ' alt=$alternatives'}, place=$place, name=$name, dose=$doseText, every=$everyHours, perDay=$perDay, times=$times, h?=$hourNeedsPeriod, food=$food, days=$durationDays, dr=$doctorName, spec=$specialty, test=$testName, lab=$labName, date=$date, time=$time)';
}

// ---------------------------------------------------------------- الكلمات

const _nearWords = {'اقرب', 'قريب', 'قريبه', 'جنبي', 'جنبنا', 'حوالين', 'حواليا', 'فين', 'دور', 'دورلي', 'دوري', 'الاقرب', 'قريبه مني', 'مني'};
const _wantWords = {'عايز', 'عاوز', 'عايزه', 'عاوزه', 'محتاج', 'محتاجه', 'اروح', 'نروح', 'هات', 'ورني', 'وريني', 'ورينى'};
const _placeWords = <String, NearbyPlace>{
  'صيدليه': NearbyPlace.pharmacy, 'الصيدليه': NearbyPlace.pharmacy, 'اجزخانه': NearbyPlace.pharmacy, 'الاجزخانه': NearbyPlace.pharmacy, 'صيدليات': NearbyPlace.pharmacy,
  'دكتور': NearbyPlace.doctor, 'الدكتور': NearbyPlace.doctor, 'دكتوره': NearbyPlace.doctor, 'الدكتوره': NearbyPlace.doctor, 'طبيب': NearbyPlace.doctor, 'الطبيب': NearbyPlace.doctor, 'عياده': NearbyPlace.doctor, 'العياده': NearbyPlace.doctor, 'دكاتره': NearbyPlace.doctor,
  'مستشفي': NearbyPlace.hospital, 'المستشفي': NearbyPlace.hospital, 'مستشفى': NearbyPlace.hospital, 'المستشفى': NearbyPlace.hospital, 'اسبتاليه': NearbyPlace.hospital, 'طوارئ': NearbyPlace.hospital,
  'معمل': NearbyPlace.lab, 'المعمل': NearbyPlace.lab, 'تحاليل': NearbyPlace.lab, 'التحاليل': NearbyPlace.lab, 'معامل': NearbyPlace.lab, 'اشعه': NearbyPlace.lab, 'الاشعه': NearbyPlace.lab,
};

const _addVerbs = {
  'ضيف', 'ضيفلي', 'ضيفي', 'ضيفيلي', 'اضيف', 'اضيفلي', 'تضيف', 'تضيفلي', 'تضيفي', 'نضيف', 'زود', 'زودلي', 'سجل', 'سجلي', 'سجللي',
  'حط', 'حطلي', 'حطي', 'اضف', 'ضيفه', 'ضيفها', 'عايزك', 'عاوزك',
};
const _medNouns = {'دوا', 'دواء', 'الدوا', 'الدواء', 'دوايه', 'علاج', 'العلاج', 'حبايه', 'حبوب', 'برشام', 'كبسول', 'كبسوله', 'شراب', 'حقنه', 'بخاخ', 'مرهم', 'نقط', 'قطره'};
const _nameMarkers = {'اسمه', 'اسمها', 'اسم', 'اسمو', 'اللي', 'بتاع', 'نوعه'};
const _takeVerbs = {'اخده', 'اخدها', 'باخده', 'باخدها', 'هاخده', 'هاخدها', 'اخد', 'اخذ', 'اخذه', 'اخذها', 'ناخده', 'تاخده', 'ياخده', 'اشربه', 'بشربه'};
const _doseUnits = {'مجم', 'ملجم', 'ملي', 'مللي', 'مل', 'جرام', 'جم', 'mg', 'ml', 'ميكرو', 'وحده', 'وحدات'};
const _formUnits = {'قرص', 'اقراص', 'حبايه', 'حبايات', 'كبسوله', 'معلقه', 'معالق', 'نقطه', 'نقط', 'بخه', 'بخات', 'حقنه'};

const _bookVerbs = {'احجز', 'احجزلي', 'احجزيلي', 'حجزلي', 'حجز', 'احجزي', 'نحجز', 'تحجز', 'تحجزلي', 'سجللي', 'حطلي'};
const _apptNouns = {'ميعاد', 'معاد', 'موعد', 'الميعاد', 'المعاد', 'الموعد', 'كشف', 'الكشف', 'زياره', 'حجز'};
const _doctorTitles = {'دكتور', 'الدكتور', 'دكتوره', 'الدكتوره', 'د', 'طبيب', 'الطبيب'};
const _labNouns = {'معمل', 'المعمل', 'تحليل', 'التحليل', 'تحاليل', 'التحاليل', 'عينه', 'سحب'};

/// كلمات بتسبق التخصص في كلام الناس — «دكتور **أمراض** باطنة»، «**أخصائي** عظام»،
/// «**طب** أطفال». مش اسم دكتور، فبتتعدّى لحد التخصص.
const _specialtyLead = {'امراض', 'طب', 'اخصائي', 'اخصائيه', 'استشاري', 'استشاريه', 'تخصص', 'قسم'};


const _periodWords = {'الصبح', 'صباحا', 'صباح', 'الفجر', 'الضهر', 'الظهر', 'ظهرا', 'العصر', 'المغرب', 'مساء', 'مساءا', 'بالليل', 'الليل', 'ليلا', 'بليل', 'ص', 'م'};
const _clockFill = {'و', 'الا', 'نص', 'ربع', 'تلت'};
const _dateWords = {'النهارده', 'النهاردا', 'بكره', 'بكرا', 'بعد', 'يوم', 'الجاي', 'الجايه', 'الاسبوع', 'اول', 'الشهر'};
const _weekdayWords = {'الاتنين', 'الاثنين', 'التلات', 'الثلاثاء', 'الاربع', 'الاربعاء', 'الخميس', 'الجمعه', 'السبت', 'الحد', 'الاحد'};
const _filler = {'انا', 'يا', 'من', 'فضلك', 'لو', 'سمحت', 'ده', 'دي', 'كده', 'يعني', 'لي', 'ليا', 'ليه', 'لينا', 'عند', 'عشان', 'علشان', 'اني', 'انك', 'ان'};

const _months = <String, int>{
  'يناير': 1, 'فبراير': 2, 'مارس': 3, 'ابريل': 4, 'مايو': 5, 'يونيو': 6, 'يونيه': 6, 'يوليو': 7, 'يوليه': 7,
  'اغسطس': 8, 'سبتمبر': 9, 'اكتوبر': 10, 'نوفمبر': 11, 'ديسمبر': 12,
};

bool _isDigits(String t) => RegExp(r'^\d+([.,]\d+)?$').hasMatch(t);
bool _isNum(String t) => _isDigits(t) || isNumberWord(t) || t == 'ساعتين' || t == 'مرتين';

// ---------------------------------------------------------------- الفهم

/// الجملة ← النية وخاناتها. مش مفهوم = [NluIntent.none].
NluResult understandUtterance(String transcript, {required DateTime now}) {
  final normalized = normalizeUtterance(transcript);
  final tokens = utteranceTokens(normalized);
  if (tokens.isEmpty) return const NluResult(NluIntent.none);
  bool has(Set<String> s) => tokens.any(s.contains);

  final placeHits = [for (final t in tokens) if (_placeWords.containsKey(t)) t];
  final hasNear = has(_nearWords);
  final hasBook = has(_bookVerbs);
  final hasAppt = has(_apptNouns);
  final hasAdd = has(_addVerbs) || _hasTwoWordAdd(tokens);
  final hasMed = has(_medNouns);
  final hasLab = has(_labNouns);
  // «أقرب دكتور عيون» / «عايز دكتور أسنان»
  final spoken = [for (final t in tokens) specialtyFromWord(t)].whereType<Specialty>().firstOrNull;

  final scores = <NluIntent, int>{
    NluIntent.findNearby: placeHits.isEmpty
        ? 0
        : (hasNear ? 4 : 0) + (has(_wantWords) ? 1 : 0) + 1 + (spoken != null && placeHits.any((t) => _placeWords[t] == NearbyPlace.doctor) ? 2 : 0) -
            (hasBook ? 3 : 0) - (hasAppt ? 3 : 0) - (hasMed ? 3 : 0),
    NluIntent.addMedication: (hasAdd ? 2 : 0) + (hasMed ? 3 : 0) + (has(_nameMarkers) && hasMed ? 1 : 0) - (hasBook ? 2 : 0),
    NluIntent.bookAppointment: (hasBook ? 2 : 0) + (hasAppt ? 2 : 0) + (has(_doctorTitles) && (hasBook || hasAppt) ? 1 : 0) - (hasMed ? 2 : 0),
    NluIntent.bookLab: hasLab && (hasBook || hasAppt) ? (hasBook ? 2 : 0) + (hasAppt ? 1 : 0) + 3 : 0,
  };
  // «احجزلي معمل» من غير «أقرب» = تحليل، مش مكان
  final ranked = scores.entries.where((e) => e.value >= 3).toList()..sort((a, b) => b.value.compareTo(a.value));
  if (ranked.isEmpty) return const NluResult(NluIntent.none);
  if (ranked.length > 1 && ranked[0].value == ranked[1].value) {
    return NluResult(NluIntent.none, alternatives: [ranked[0].key, ranked[1].key]);
  }
  return switch (ranked.first.key) {
    NluIntent.findNearby => _nearby(tokens, placeHits),
    NluIntent.addMedication => _addMedication(tokens, normalized, now),
    NluIntent.bookAppointment => _booking(NluIntent.bookAppointment, tokens, normalized, now),
    NluIntent.bookLab => _booking(NluIntent.bookLab, tokens, normalized, now),
    NluIntent.none => const NluResult(NluIntent.none),
  };
}

/// «أقرب …» — النوع، والتخصص لو دكتور («أقرب دكتور عيون»). تخصص من غير كلمة
/// مكان تانية = دكتور.
NluResult _nearby(List<String> tokens, List<String> placeHits) {
  final specialty = [for (final t in tokens) specialtyFromWord(t)].whereType<Specialty>().firstOrNull;
  final places = [for (final t in placeHits) _placeWords[t]!];
  final place = specialty != null && places.contains(NearbyPlace.doctor) ? NearbyPlace.doctor : places.firstOrNull ?? NearbyPlace.pharmacy;
  return NluResult(NluIntent.findNearby, place: place, specialtyKind: place == NearbyPlace.doctor ? specialty : null);
}

/// التعادل اتحسم بدوسة («قصدك تضيف دوا؟») — نفس الجملة، بالنية دي.
NluResult understandUtteranceAs(NluIntent intent, String transcript, {required DateTime now}) {
  final normalized = normalizeUtterance(transcript);
  final tokens = utteranceTokens(normalized);
  return switch (intent) {
    NluIntent.findNearby => _nearby(tokens, [for (final t in tokens) if (_placeWords.containsKey(t)) t]),
    NluIntent.addMedication => _addMedication(tokens, normalized, now),
    NluIntent.bookAppointment => _booking(NluIntent.bookAppointment, tokens, normalized, now),
    NluIntent.bookLab => _booking(NluIntent.bookLab, tokens, normalized, now),
    NluIntent.none => const NluResult(NluIntent.none),
  };
}

/// «تضيف لي» / «عايزك تضيف» — الفعل ممكن ييجي بعد «عايزك».
bool _hasTwoWordAdd(List<String> tokens) => tokens.any((t) => t.startsWith('تضيف') || t.startsWith('ضيف'));

// ---------------------------------------------------------------- ضيف دوا

NluResult _addMedication(List<String> tokens, String normalized, DateTime now) {
  // الاسم: بعد كلمة الدوا (و«اسمه») — أو بعد الفعل لو مفيش كلمة دوا
  var start = tokens.indexWhere(_medNouns.contains);
  if (start < 0) start = tokens.indexWhere((t) => _addVerbs.contains(t) || t.startsWith('تضيف') || t.startsWith('ضيف'));
  final nameWords = <String>[];
  String? doseText;
  var i = start + 1;
  while (i < tokens.length && (_nameMarkers.contains(tokens[i]) || _filler.contains(tokens[i]))) {
    i++;
  }
  for (; i < tokens.length; i++) {
    final t = tokens[i];
    if (_isNameStop(t, tokens, i)) break;
    nameWords.add(t);
  }
  // الجرعة لازقة في الاسم: «جلوكوفاج ٥٠٠» / «كونكور ٥ مجم» / «قرص واحد»
  if (i < tokens.length && _isDigits(tokens[i])) {
    final unit = i + 1 < tokens.length && _doseUnits.contains(tokens[i + 1]) ? ' ${tokens[i + 1]}' : '';
    // رقم قدّام «مره/مرات/ساعات» مش جرعة
    final next = i + 1 < tokens.length ? tokens[i + 1] : '';
    if (next != 'مره' && next != 'مرات' && !next.startsWith('ساع')) doseText = '${tokens[i]}$unit';
  }
  final form = tokens.indexWhere(_formUnits.contains);
  if (doseText == null && form >= 0) {
    final before = form > 0 ? tokens[form - 1] : '';
    final after = form + 1 < tokens.length ? tokens[form + 1] : '';
    if (_isNum(before) || before == 'نص' || before == 'ربع') {
      doseText = '$before ${tokens[form]}';
    } else if (isNumberWord(after) && !after.startsWith('مر')) {
      doseText = '${tokens[form]} $after';
    }
  }

  final name = nameWords.isEmpty ? null : medicineNameOrNull(nameWords.join(' '));

  final everyHours = _everyHours(tokens);
  final perDay = everyHours == null ? _perDay(tokens) : null;
  final clock = _clock(tokens);
  return NluResult(
    NluIntent.addMedication,
    name: name,
    doseText: doseText,
    everyHours: everyHours,
    perDay: perDay,
    times: clock.time == null ? const [] : [clock.time!],
    hourNeedsPeriod: clock.needsPeriod,
    food: _food(tokens),
    durationDays: _duration(tokens),
  );
}

bool _isNameStop(String t, List<String> tokens, int i) {
  if (t == 'و' && i + 1 < tokens.length && (_takeVerbs.contains(tokens[i + 1]) || tokens[i + 1] == 'كل' || tokens[i + 1] == 'مره' || tokens[i + 1] == 'مرتين')) return true;
  if (_takeVerbs.contains(t)) return true;
  if (t == 'كل' || t == 'الساعه' || t == 'ساعه' || t == 'قبل' || t == 'بعد' || t == 'مع' || t == 'علي' || t == 'على') return true;
  if (t == 'مره' || t == 'مرتين' || t == 'مرات' || t == 'يوميا' || t == 'لمده' || t == 'في' || t == 'يوم') return true;
  if (_doseUnits.contains(t) || _formUnits.contains(t) || _periodWords.contains(t)) return true;
  if (_isDigits(t) || isNumberWord(t)) return true;
  if (_weekdayWords.contains(t) || t == 'بكره' || t == 'النهارده' || t == 'من') return true;
  return false;
}

/// «كل ١٢ ساعة» / «كل ساعتين» / «كل تمن ساعات».
int? _everyHours(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'كل' || i + 1 >= tokens.length) continue;
    final a = tokens[i + 1];
    if (a == 'ساعتين') return 2;
    if (a == 'ساعه') return 1;
    final unit = i + 2 < tokens.length ? tokens[i + 2] : '';
    if (!unit.startsWith('ساع')) continue;
    final n = _isDigits(a) ? int.tryParse(a) : parseNumber(a);
    if (n != null && n >= 1 && n <= 24) return n;
  }
  return null;
}

/// «مرة» / «مرتين» / «٣ مرات» / «تلات مرات» في اليوم.
int? _perDay(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'مرتين') return 2;
    if (t == 'مرات' && i > 0) {
      final prev = tokens[i - 1];
      final n = _isDigits(prev) ? int.tryParse(prev) : parseNumber(prev);
      if (n != null && n >= 1 && n <= 12) return n;
    }
    if (t == 'مره') {
      final next = i + 1 < tokens.length ? tokens[i + 1] : '';
      if (next == 'واحده' || next == 'في' || next == 'يوميا' || next == 'كل' || next.isEmpty) return 1;
    }
  }
  return null;
}

MealRelation? _food(List<String> tokens) {
  const meals = {'الاكل', 'اكل', 'الفطار', 'الفطور', 'فطار', 'الغدا', 'الغداء', 'غدا', 'العشا', 'العشاء', 'عشا', 'الاكلات', 'الوكل'};
  for (var i = 0; i + 1 < tokens.length; i++) {
    final t = tokens[i], next = tokens[i + 1];
    if ((t == 'علي' || t == 'على') && (next == 'الريق' || next == 'معده')) return MealRelation.emptyStomach;
    if (!meals.contains(next)) continue;
    if (t == 'قبل') return MealRelation.before;
    if (t == 'بعد') return MealRelation.after;
    if (t == 'مع') return MealRelation.with_;
  }
  return null;
}

int? _duration(List<String> tokens) {
  final i = tokens.indexOf('لمده');
  if (i < 0 || i + 1 >= tokens.length) return null;
  final a = tokens[i + 1];
  final unitAt = _isNum(a) ? i + 2 : i + 1;
  final unit = unitAt < tokens.length ? tokens[unitAt] : '';
  final n = unitAt == i + 1 ? (unit.endsWith('ين') ? 2 : 1) : (_isDigits(a) ? int.tryParse(a) : parseNumber(a));
  if (n == null) return null;
  if (unit.startsWith('اسبوع') || unit.startsWith('اسابيع')) return n * 7;
  if (unit.startsWith('شهر') || unit.startsWith('شهور')) return n * 30;
  if (unit.startsWith('يوم') || unit.startsWith('ايام')) return n;
  return null;
}

/// ساعة بالحرف: «الساعة ٥ العصر» / «٩ الصبح» / «الساعة ٨ ونص بالليل». «الساعة
/// ٩» لوحدها = [needsPeriod] — ما بنختارش الصبح ولا بالليل عنه.
({SpokenTime? time, int? needsPeriod}) _clock(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final afterWord = (t == 'الساعه' || t == 'ساعه') && i + 1 < tokens.length && _isNum(tokens[i + 1]);
    final bare = _isNum(t) && i + 1 < tokens.length && _periodWords.contains(tokens[i + 1]) &&
        (i == 0 || (tokens[i - 1] != 'كل' && !_doseUnits.contains(tokens[i - 1])));
    if (!afterWord && !bare) continue;
    final from = afterWord ? i + 1 : i;
    var end = from;
    while (end < tokens.length && (end == from || _periodWords.contains(tokens[end]) || _clockFill.contains(tokens[end]) || (tokens[end - 1] == 'و' && _isNum(tokens[end])))) {
      end++;
    }
    final span = tokens.sublist(from, end).join(' ');
    final time = parseTime(span);
    if (time != null) return (time: time, needsPeriod: null);
    final h = _isDigits(tokens[from]) ? int.tryParse(tokens[from]) : parseNumber(tokens[from]);
    if (h != null && h >= 1 && h <= 12) return (time: null, needsPeriod: h);
  }
  return (time: null, needsPeriod: null);
}

// ---------------------------------------------------------------- احجز

NluResult _booking(NluIntent intent, List<String> tokens, String normalized, DateTime now) {
  final date = _date(normalized, now);
  final clock = _clock(tokens);
  String? doctorName;
  Specialty? specialty;
  final d = tokens.indexWhere(_doctorTitles.contains);
  if (d >= 0) {
    final words = <String>[];
    for (final t in tokens.sublist(d + 1)) {
      if (specialtyFromWord(t) case final sp?) {
        specialty ??= sp;
        break;
      }
      if (_specialtyLead.contains(t)) continue;
      if (_isBookingStop(t)) break;
      words.add(t);
      if (words.length == 2) break;
    }
    final name = words.isEmpty ? null : medicineNameOrNull(words.join(' '));
    if (name != null) doctorName = 'د. $name';
  }
  if (intent == NluIntent.bookAppointment) specialty ??= [for (final t in tokens) specialtyFromWord(t)].whereType<Specialty>().firstOrNull;

  String? testName;
  String? labName;
  if (intent == NluIntent.bookLab) {
    final ti = tokens.indexWhere((t) => t == 'تحليل' || t == 'التحليل' || t == 'تحاليل' || t == 'التحاليل');
    if (ti >= 0) {
      final words = <String>[];
      for (final t in tokens.sublist(ti + 1)) {
        if (_isBookingStop(t) || t == 'معمل' || t == 'المعمل') break;
        words.add(t);
        if (words.length == 3) break;
      }
      final w = words.isEmpty ? null : medicineNameOrNull(words.join(' '));
      testName = w;
    }
    final li = tokens.indexWhere((t) => t == 'معمل' || t == 'المعمل');
    if (li >= 0 && li + 1 < tokens.length) {
      final next = tokens[li + 1];
      if (!_labNouns.contains(next) && !_isBookingStop(next)) labName = medicineNameOrNull(next);
    }
  }
  return NluResult(
    intent,
    doctorName: doctorName,
    specialtyKind: specialty,
    testName: testName,
    labName: labName,
    date: date,
    time: clock.time,
    hourNeedsPeriod: clock.needsPeriod,
  );
}

bool _isBookingStop(String t) =>
    _dateWords.contains(t) || _weekdayWords.contains(t) || _months.containsKey(t) || t == 'الساعه' || t == 'ساعه' || t == 'في' ||
    _filler.contains(t) || _periodWords.contains(t) || _isDigits(t) || isNumberWord(t) || _bookVerbs.contains(t) || _apptNouns.contains(t);

/// اليوم: «النهارده» / «بكرة» / «بعد بكرة» / «يوم الأحد» (الجاي) / «الأحد الجاي»
/// / «٥ أكتوبر».
DateTime? _date(String normalized, DateTime now) {
  final month = RegExp('(\\d{1,2}) ?(${_months.keys.join('|')})').firstMatch(normalized);
  if (month != null) {
    final day = int.parse(month.group(1)!);
    final m = _months[month.group(2)!]!;
    var d = DateTime(now.year, m, day);
    if (d.isBefore(DateTime(now.year, now.month, now.day))) d = DateTime(now.year + 1, m, day);
    return d;
  }
  final dates = extractDates(normalized, now: now, future: true);
  return dates.isEmpty ? null : dates.first.date;
}
