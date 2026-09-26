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

import '../../domain/voice/answer_parser.dart';

enum CommandIntent { markTaken, nextDose, todayList, addMed, medicalQuestion, unknown }

/// «قبل / مع / بعد» الأكل.
enum MealRelation { before, with_, after }

/// ميعاد اتقال في «ضيفلي»: مرساة بكلمتها («الفطار») وعلاقتها، أو ساعة ثابتة.
class SpokenTiming {
  const SpokenTiming({this.anchorWord, this.relation, this.fixed});

  /// «الصحيان» / «الفطار» / «الغدا» / «العشا» / «النوم» — بعد التطبيع.
  final String? anchorWord;
  final MealRelation? relation;
  final SpokenTime? fixed;

  @override
  bool operator ==(Object other) =>
      other is SpokenTiming && other.anchorWord == anchorWord && other.relation == relation && other.fixed == fixed;
  @override
  int get hashCode => Object.hash(anchorWord, relation, fixed);
  @override
  String toString() => 'SpokenTiming($anchorWord, $relation, $fixed)';
}

class VoiceCommand {
  const VoiceCommand(
    this.intent, {
    this.medWords,
    this.timings = const [],
    this.timesPerDay,
    this.everyHours,
    this.once = false,
  });

  final CommandIntent intent;

  /// اسم الدوا زي ما اتقال («الكونكور»، «الضغط») — null = «الدوا» بس.
  final String? medWords;
  final List<SpokenTiming> timings;
  final int? timesPerDay;
  final int? everyHours;
  final bool once;

  static const unknown = VoiceCommand(CommandIntent.unknown);
  static const medical = VoiceCommand(CommandIntent.medicalQuestion);

  @override
  String toString() => 'VoiceCommand($intent, med=$medWords, timings=$timings, x$timesPerDay, every=$everyHours, once=$once)';
}

// ---------------------------------------------------------------- كلمات

const _medNouns = {'دوا', 'دواء', 'الدوا', 'الدواء', 'دوايا', 'دوائي', 'حبايه', 'حبه', 'الحبايه', 'برشام', 'البرشام', 'علاج', 'العلاج', 'قرص', 'القرص', 'حقنه', 'الحقنه', 'ادويتي', 'ادويه', 'الادويه', 'جرعه', 'الجرعه', 'جرعتي', 'جرعاتي', 'مضاد', 'فيتامين', 'كبسوله', 'كبسول', 'شراب', 'نقط', 'حقن', 'لبوس', 'مرهم', 'كريم', 'بخاخ'};

const _tookVerbs = {'اخدت', 'خدت', 'اخدته', 'خدته', 'اخدتها', 'خدتها', 'اخدتهم', 'خدتهم', 'شربت', 'شربته', 'شربتها', 'بلعت', 'بلعته', 'بلعتها', 'اخذت', 'اخذته', 'تناولت'};

const _addVerbs = {'ضيف', 'ضيفلي', 'ضيفي', 'ضيفيلي', 'اضيف', 'اضيفلي', 'زود', 'زودلي', 'زودي', 'سجل', 'سجلي', 'سجللي', 'حط', 'حطلي', 'حطي', 'اضف', 'نضيف', 'تضيف', 'تضيفلي'};

const _nextWords = {'الجاي', 'الجايه', 'الجايّه', 'جاي', 'جايه', 'القادم', 'القادمه', 'بعدين', 'التاني', 'التانيه'};
const _whenWords = {'امتى', 'امتا', 'إمتى', 'الساعه', 'ساعه', 'معاد', 'ميعاد', 'معادها', 'ميعادها', 'معاده', 'ميعاده'};
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

// ---------------------------------------------------------------- الفهم

/// أرقام «مرة / مرتين / تلات مرات / أربع مرات» في اليوم.
const _timesWords = <String, int>{'مره': 1, 'مرتين': 2, 'تلات': 3, 'ثلاث': 3, 'اربع': 4, 'خمس': 5, 'ست': 6};

/// «وبعد العشا» → «و» + «بعد» — الواو الملزوقة بتتفصل قدّام كلمة ميعاد.
List<String> _tokens(String text) {
  final out = <String>[];
  for (final t in normalizeArabic(text).split(' ')) {
    if (t.isEmpty) continue;
    if (t.length > 2 && t.startsWith('و')) {
      final rest = t.substring(1);
      if (_relationWords.containsKey(rest) || _anchorWords.containsKey(rest) || _dayPartToAnchor.containsKey(rest) || rest == 'كل') {
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

/// فهم طلب واحد. مش مفهوم = [VoiceCommand.unknown].
VoiceCommand parseCommand(String text) {
  final tokens = _tokens(text);
  if (tokens.isEmpty) return VoiceCommand.unknown;

  // نفي الأخذ («ماخدتش») مش أمر — وسؤال «أخدته ولا لأ؟» مش أمر
  final negatedTake = tokens.any((t) => t.startsWith('ما') && t.contains('خد') && t.endsWith('ش'));

  // ---- طبي الأول: أي كلمة طبية ومعاها كلام عن دوا أو جسم = سؤال للدكتور
  if (_isMedical(tokens)) return VoiceCommand.medical;

  // ---- ضيف دوا
  if (_hasAny(tokens, _addVerbs) && _mentionsMed(tokens)) return _parseAdd(tokens);

  // ---- إيه دوايا الجاي؟ / الدوا الجاي إمتى؟
  final mentionsMed = _mentionsMed(tokens);
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

VoiceCommand _parseAdd(List<String> tokens) {
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
  var once = false;
  MealRelation? pendingRelation;

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
    // ساعة ثابتة: «الساعة تمانية الصبح»
    if (t == 'الساعه' && k + 1 < rest.length) {
      final fixed = parseTime(rest.sublist(k + 1).join(' '));
      if (fixed != null) {
        timings.add(SpokenTiming(fixed: fixed));
        break;
      }
    }
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
  final relOnly = timings.where((t) => t.anchorWord == null && t.fixed == null).toList();
  final merged = <SpokenTiming>[];
  for (final t in timings) {
    if (t.anchorWord == null && t.fixed == null) continue;
    if (t.anchorWord != null && t.relation == null && relOnly.isNotEmpty) {
      merged.add(SpokenTiming(anchorWord: t.anchorWord, relation: relOnly.first.relation));
    } else {
      merged.add(t);
    }
  }
  // «بعد الأكل مرتين» من غير وجبة — العلاقة بتتحفظ من غير مرساة
  if (merged.isEmpty && relOnly.isNotEmpty) merged.add(relOnly.first);

  final name = nameWords.isEmpty ? null : nameWords.join(' ');
  return VoiceCommand(
    CommandIntent.addMed,
    medWords: name,
    timings: merged,
    timesPerDay: timesPerDay,
    everyHours: everyHours,
    once: once,
  );
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
