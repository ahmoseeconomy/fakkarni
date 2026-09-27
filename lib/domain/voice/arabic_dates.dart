// تواريخ بالمصري — **بورت `dates.ar.js` بتاع jarvis-ai-finance** (دارت نقية).
//
// حتمي عن قصد: «امبارح» الساعة ١:٣٠ بالليل حساب تقويم، مش لغة. الأصل مكتوب
// لحركات فلوس **فاتت** (يوم الجمعة = أقرب جمعة فاتت)؛ عندنا المواعيد جاية،
// فـ[future] بيقلب اتجاه يوم الأسبوع ويضيف «الأسبوع الجاي» و«بعد أسبوع»
// و«أول الشهر». التاريخ بيرجع **يوم تقويم** (منتصف الليل، وقت محلي) من غير
// أي جمع بـDuration — مصر فيها توقيت صيفي.

import 'arabic_numbers.dart' show normalizeForNumbers;

/// تاريخ اتقال — الكلام زي ما جه ويومه.
class SpokenDate {
  const SpokenDate(this.raw, this.date);
  final String raw;
  final DateTime date;

  @override
  bool operator ==(Object other) => other is SpokenDate && other.raw == raw && other.date == date;
  @override
  int get hashCode => Object.hash(raw, date);
  @override
  String toString() => 'SpokenDate($raw = ${isoDate(date)})';
}

/// «2026-08-08».
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
DateTime _plusMonths(DateTime d, int n) => DateTime(d.year, d.month + n, d.day);

const _weekdays = <String, int>{
  'الاتنين': 1, 'الاثنين': 1, 'التلات': 2, 'الثلاثاء': 2, 'الثلاث': 2, 'الاربع': 3, 'الاربعاء': 3,
  'الخميس': 4, 'الجمعه': 5, 'السبت': 6, 'الحد': 7, 'الاحد': 7,
};

/// كلمات أيام الأسبوع (بعد التطبيع) — للقارئ اللي بيدوّر على «يوم».
Set<String> get weekdayWords => _weekdays.keys.toSet();

/// كل التواريخ اللي في الجملة. [future] = جاية (مواعيد): يوم الأسبوع = أقرب
/// واحد جاي، و«الأسبوع الجاي» و«بعد أسبوع» و«أول الشهر» بيتفهموا.
List<SpokenDate> extractDates(String text, {required DateTime now, bool future = false}) {
  final normalized = normalizeForNumbers(text);
  if (normalized.isEmpty) return const [];
  final today = _day(now);
  final out = <SpokenDate>[];
  final seen = <String>{};
  void push(String raw, DateTime? d) {
    if (d == null) return;
    final key = isoDate(d);
    if (!seen.add(key)) return;
    out.add(SpokenDate(raw, _day(d)));
  }

  // تاريخ صريح الأول — المستخدم كان واضح
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(normalized);
  if (iso != null) {
    push(iso.group(0)!, DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!)));
  }
  final dmy = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(normalized);
  if (dmy != null) {
    final y = dmy.group(3);
    final year = y == null ? today.year : (y.length == 2 ? 2000 + int.parse(y) : int.parse(y));
    push(dmy.group(0)!, DateTime(year, int.parse(dmy.group(2)!), int.parse(dmy.group(1)!)));
  }

  // كلمات نسبية — الأطول الأول، وكل مطابقة بتتشال من النص (وإلا «أول امبارح»
  // بتطابق «امبارح» اللي جواها كمان)
  var rest = normalized;
  final relatives = <(RegExp, int)>[
    (RegExp(r'اول\s*(?:ام)?بارح'), -2),
    (RegExp(r'بعد\s*بكر[هاة]'), 2),
    (RegExp(r'امبارح|مبارح|البارحه'), -1),
    (RegExp(r'النهارده|النهاردا|اليوم|دلوقتي'), 0),
    (RegExp(r'بكر[هاة]|غدا\b'), 1),
  ];
  for (final (pattern, offset) in relatives) {
    final m = pattern.firstMatch(rest);
    if (m == null) continue;
    push(m.group(0)!, _plusDays(today, offset));
    rest = rest.replaceFirst(m.group(0)!, ' ');
  }

  if (future) {
    // «الأسبوع الجاي» / «بعد أسبوع» / «بعد أسبوعين» / «بعد N أيام» / «بعد شهر»
    final ahead = RegExp(r'(?:بعد|كمان)\s*(\d+)?\s*(يومين|اسبوعين|شهرين|ايام|اسابيع|شهور|يوم|اسبوع|شهر)').firstMatch(rest);
    if (ahead != null) {
      final word = ahead.group(2)!;
      final n = ahead.group(1) != null ? int.parse(ahead.group(1)!) : (word.endsWith('ين') ? 2 : 1);
      final d = RegExp(r'^(يوم|يومين|ايام)$').hasMatch(word)
          ? _plusDays(today, n)
          : RegExp(r'^(اسبوع|اسبوعين|اسابيع)$').hasMatch(word)
              ? _plusDays(today, 7 * n)
              : _plusMonths(today, n);
      push(ahead.group(0)!, d);
      rest = rest.replaceFirst(ahead.group(0)!, ' ');
    }
    if (RegExp(r'الاسبوع\s*(الجاي|القادم|اللي\s*جاي)').hasMatch(rest)) {
      final m = RegExp(r'الاسبوع\s*(الجاي|القادم|اللي\s*جاي)').firstMatch(rest)!;
      // نفس اليوم الأسبوع الجاي — إلا لو يوم أسبوع اتقال معاه (بيتحسب تحت)
      if (!_weekdays.keys.any(rest.contains)) push(m.group(0)!, _plusDays(today, 7));
    }
    final firstOfMonth = RegExp(r'اول\s*الشهر(\s*الجاي)?').firstMatch(rest);
    if (firstOfMonth != null) {
      final d = today.day == 1 && firstOfMonth.group(1) == null ? today : DateTime(today.year, today.month + 1, 1);
      push(firstOfMonth.group(0)!, d);
    }
    if (RegExp(r'اخر\s*الشهر').hasMatch(rest)) {
      push('اخر الشهر', DateTime(today.year, today.month + 1, 0));
    }
  } else {
    // «من ٣ أيام» / «من أسبوعين» — الجمع والمثنى قبل المفرد
    final ago = RegExp(r'من\s*(\d+)?\s*(يومين|اسبوعين|شهرين|ايام|اسابيع|شهور|يوم|اسبوع|شهر)').firstMatch(rest);
    if (ago != null) {
      final word = ago.group(2)!;
      final n = ago.group(1) != null ? int.parse(ago.group(1)!) : (word.endsWith('ين') ? 2 : 1);
      final d = RegExp(r'^(يوم|يومين|ايام)$').hasMatch(word)
          ? _plusDays(today, -n)
          : RegExp(r'^(اسبوع|اسبوعين|اسابيع)$').hasMatch(word)
              ? _plusDays(today, -7 * n)
              : _plusMonths(today, -n);
      push(ago.group(0)!, d);
    }
  }

  // يوم الأسبوع: «يوم الجمعة اللي فات» / «يوم الحد» / «الحد الجاي»
  final weekday = RegExp(
    r'(?:يوم\s*)?(الاتنين|الاثنين|التلات|الثلاثاء|الثلاث|الاربع|الاربعاء|الخميس|الجمعه|السبت|الحد|الاحد)(\s*اللي\s*فات|\s*الجاي|\s*القادم|\s*الجايه)?',
  ).firstMatch(normalized);
  if (weekday != null) {
    final target = _weekdays[weekday.group(1)!]!;
    final tail = weekday.group(2)?.trim() ?? '';
    final past = tail.startsWith('اللي');
    final next = tail == 'الجاي' || tail == 'القادم' || tail == 'الجايه';
    DateTime d;
    if (future && !past) {
      var delta = (target - today.weekday) % 7;
      if (delta < 0) delta += 7;
      if (delta == 0 && next) delta = 7;
      d = _plusDays(today, delta);
    } else {
      // أقرب واحد فات (أو النهارده) — زي الأصل: نفس أسبوع الاتنين→الحد
      final monday = _plusDays(today, 1 - today.weekday);
      d = _plusDays(monday, target - 1);
      if (d.isAfter(today) || past) d = _plusDays(d, d.isAfter(today) ? -7 : 0);
      if (past && !d.isBefore(today)) d = _plusDays(d, -7);
    }
    push(weekday.group(0)!, d);
  }
  return out;
}

/// فترة للأسئلة: «الشهر ده»، «آخر ٣٠ يوم». الأسبوع بيبدأ الاتنين زي الأصل.
({String raw, DateTime from, DateTime to})? extractRange(String text, {required DateTime now}) {
  final s = normalizeForNumbers(text);
  final today = _day(now);
  DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
  DateTime startOfWeek(DateTime d) => _plusDays(d, 1 - d.weekday);
  if (RegExp(r'الشهر\s*ده|الشهر\s*الحالي|هذا\s*الشهر').hasMatch(s)) {
    return (raw: 'الشهر ده', from: startOfMonth(today), to: endOfMonth(today));
  }
  if (RegExp(r'الشهر\s*اللي\s*فات|الشهر\s*الماضي').hasMatch(s)) {
    final prev = _plusMonths(startOfMonth(today), -1);
    return (raw: 'الشهر اللي فات', from: prev, to: endOfMonth(prev));
  }
  if (RegExp(r'الاسبوع\s*ده|هذا\s*الاسبوع').hasMatch(s)) {
    final from = startOfWeek(today);
    return (raw: 'الأسبوع ده', from: from, to: _plusDays(from, 6));
  }
  if (RegExp(r'الاسبوع\s*اللي\s*فات|الاسبوع\s*الماضي').hasMatch(s)) {
    final from = _plusDays(startOfWeek(today), -7);
    return (raw: 'الأسبوع اللي فات', from: from, to: _plusDays(from, 6));
  }
  if (RegExp(r'السنه\s*دي|هذا\s*العام').hasMatch(s)) {
    return (raw: 'السنة دي', from: DateTime(today.year, 1, 1), to: DateTime(today.year, 12, 31));
  }
  if (RegExp(r'من\s*اول\s*الشهر').hasMatch(s)) {
    return (raw: 'من أول الشهر', from: startOfMonth(today), to: today);
  }
  final lastN = RegExp(r'اخر\s*(\d+)\s*(ايام|اسابيع|شهور|يوم|اسبوع|شهر)').firstMatch(s);
  if (lastN != null) {
    final n = int.parse(lastN.group(1)!);
    final word = lastN.group(2)!;
    final from = RegExp(r'^(يوم|ايام)$').hasMatch(word)
        ? _plusDays(today, -n)
        : RegExp(r'^(اسبوع|اسابيع)$').hasMatch(word)
            ? _plusDays(today, -7 * n)
            : _plusMonths(today, -n);
    return (raw: lastN.group(0)!, from: from, to: today);
  }
  return null;
}
