// «فاتح/قافل» من تاج OpenStreetMap `opening_hours` (D3.9) — دارت نقية.
//
// **بيرد بس لو فاهم التاج كله.** الصيغة كبيرة (أجازات، شهور، شروق، تعليقات،
// أسابيع…). اللي بنفهمه: «24/7»، وقواعد مفصولة بـ«;» كل واحدة فيها أيام
// اختيارية (Mo-Fr، Sa,Su، Sa-Th بتلف) وفترات (09:30-21:30، بتعدّي نص الليل)
// أو «off»/«closed». القاعدة اللي بعد بتغطي اللي قبلها لنفس اليوم. أي حاجة
// تانية → null، والشاشة بتعرض التاج نفسه من غير حكم: «فاتحة» غلط بتودّي
// راجل عنده ٧٢ سنة لباب مقفول.

enum OpenState { open, closed }

const _days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

class _Rule {
  const _Rule(this.days, this.spans);

  /// أيام الأسبوع ٠=الاتنين … ٦=الحد.
  final Set<int> days;

  /// دقايق [من، لـ) — فاضية = مقفول. «لـ» ممكن تعدّي ١٤٤٠.
  final List<(int, int)> spans;
}

List<_Rule>? _parse(String raw) {
  final tag = raw.trim();
  if (tag.isEmpty) return null;
  if (tag == '24/7') return [_Rule({0, 1, 2, 3, 4, 5, 6}, const [(0, 1440)])];
  final rules = <_Rule>[];
  for (final part in tag.split(';')) {
    final text = part.trim();
    if (text.isEmpty) continue;
    final m = RegExp(r'^(?:([A-Za-z,\- ]+?)\s+)?(.+)$').firstMatch(text);
    if (m == null) return null;
    var daysPart = m.group(1);
    var timesPart = m.group(2)!.trim();
    // «Mo-Fr» لوحدها من غير وقت مش مفهومة
    if (daysPart == null && RegExp(r'^[A-Za-z]').hasMatch(timesPart) && timesPart != 'off' && timesPart != 'closed') {
      return null;
    }
    final days = <int>{};
    if (daysPart == null) {
      days.addAll([0, 1, 2, 3, 4, 5, 6]);
    } else {
      for (final piece in daysPart.split(',')) {
        final range = piece.trim().split('-');
        if (range.length == 1) {
          final d = _days.indexOf(range[0]);
          if (d < 0) return null;
          days.add(d);
        } else if (range.length == 2) {
          final a = _days.indexOf(range[0].trim()), b = _days.indexOf(range[1].trim());
          if (a < 0 || b < 0) return null;
          for (var d = a;; d = (d + 1) % 7) {
            days.add(d);
            if (d == b) break;
          }
        } else {
          return null;
        }
      }
    }
    final spans = <(int, int)>[];
    if (timesPart != 'off' && timesPart != 'closed') {
      for (final span in timesPart.split(',')) {
        final t = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(span.trim());
        if (t == null) return null;
        final from = int.parse(t.group(1)!) * 60 + int.parse(t.group(2)!);
        var to = int.parse(t.group(3)!) * 60 + int.parse(t.group(4)!);
        if (from > 1440 || to > 1440 * 2) return null;
        if (to <= from) to += 1440; // بتعدّي نص الليل
        spans.add((from, to));
      }
    }
    rules.add(_Rule(days, spans));
  }
  return rules.isEmpty ? null : rules;
}

/// فاتح ولا قافل عند [now] — أو null لو التاج مش مفهوم بالكامل.
OpenState? openStateAt(String tag, DateTime now) {
  final rules = _parse(tag);
  if (rules == null) return null;

  // القاعدة الأخيرة اللي بتذكر اليوم هي اللي بتحكمه
  List<(int, int)> spansFor(int day) {
    List<(int, int)> result = const [];
    for (final r in rules) {
      if (r.days.contains(day)) result = r.spans;
    }
    return result;
  }

  final today = now.weekday - 1;
  final minute = now.hour * 60 + now.minute;
  for (final (from, to) in spansFor(today)) {
    if (minute >= from && minute < to) return OpenState.open;
  }
  // فترة من امبارح عدّت نص الليل
  final yesterday = (today + 6) % 7;
  for (final (_, to) in spansFor(yesterday)) {
    if (to > 1440 && minute < to - 1440) return OpenState.open;
  }
  return OpenState.closed;
}
