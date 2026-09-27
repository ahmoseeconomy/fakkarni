// أرقام بالمصري — **بورت `numbers.ar.js` بتاع jarvis-ai-finance** (دارت نقية).
//
// المتعرّف بيرجّع الرقم بتلات أشكال — أرقام عربية (٢٠٠)، غربية (200)، وكلام
// (ميتين) — وساعات مخلوطين في جملة واحدة. الفهم هنا حتمي: قواعد، مش موديل.
// الخرايط كلها على الشكل **المطبّع** (همزة → ا، ة → ه)، فالمنادي بيطبّع الأول.
//
// فرق واحد عن الأصل: «ثمانيه» = ٨ (في الأصل مكتوبة ٩ بالغلط).

import 'answer_parser.dart' show normalizeArabic;

/// رقم اتقال — الكلام زي ما جه ([raw]) وقيمته.
class SpokenNumber {
  const SpokenNumber(this.raw, this.value);
  final String raw;
  final double value;

  @override
  bool operator ==(Object other) => other is SpokenNumber && other.raw == raw && other.value == value;
  @override
  int get hashCode => Object.hash(raw, value);
  @override
  String toString() => 'SpokenNumber($raw = $value)';
}

const _units = <String, int>{
  'صفر': 0, 'واحد': 1, 'واحده': 1, 'اتنين': 2, 'اثنين': 2, 'تلاته': 3, 'ثلاثه': 3, 'اربعه': 4,
  'خمسه': 5, 'سته': 6, 'سبعه': 7, 'تمانيه': 8, 'ثمانيه': 8, 'تسعه': 9, 'عشره': 10,
};

/// صيغة الإضافة قبل المعدود: «تلت تلاف» = تلات آلاف.
const _construct = <String, int>{
  'واحد': 1, 'اتنين': 2, 'تلت': 3, 'ثلاث': 3, 'ربع': 4, 'اربع': 4, 'خمس': 5, 'ست': 6, 'سبع': 7, 'تمن': 8, 'ثمان': 8, 'تسع': 9, 'عشر': 10,
};

const _teens = <String, int>{
  'حداشر': 11, 'احداشر': 11, 'اتناشر': 12, 'اطناشر': 12, 'تلاتاشر': 13, 'اربعتاشر': 14, 'خمستاشر': 15,
  'ستاشر': 16, 'سبعتاشر': 17, 'تمنتاشر': 18, 'تسعتاشر': 19,
};

const _tens = <String, int>{
  'عشرين': 20, 'تلاتين': 30, 'ثلاثين': 30, 'اربعين': 40, 'خمسين': 50, 'ستين': 60, 'سبعين': 70, 'تمانين': 80, 'ثمانين': 80, 'تسعين': 90,
};

const _hundreds = <String, int>{
  'ميه': 100, 'مايه': 100, 'ميتين': 200, 'متين': 200, 'تلتميه': 300, 'ربعميه': 400, 'خمسميه': 500,
  'ستميه': 600, 'سبعميه': 700, 'تمنميه': 800, 'تسعميه': 900,
};

const _thousands = <String, int>{'الف': 1000, 'الفين': 2000};
const _thousandPlural = {'تلاف', 'الاف', 'ألاف'};
const _million = <String, int>{'مليون': 1000000, 'مليونين': 2000000};
const _fractions = <String, double>{'نص': 0.5, 'نصف': 0.5, 'ربع': 0.25, 'تلت': 1 / 3};

final _kSuffix = RegExp(r'^(\d+(?:\.\d+)?)\s*(ك|k)$', caseSensitive: false);
final _digits = RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?$');

/// الكلمة دي رقم؟
bool isNumberWord(String token) =>
    _units.containsKey(token) ||
    _teens.containsKey(token) ||
    _tens.containsKey(token) ||
    _hundreds.containsKey(token) ||
    _thousands.containsKey(token) ||
    _million.containsKey(token) ||
    _construct.containsKey(token) ||
    _thousandPlural.contains(token);

/// أرقام عربية → لاتينية، «٫» → «.»، و«٬» بتتشال — قبل التطبيع العام.
String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x660 && r <= 0x669) {
      b.writeCharCode(0x30 + r - 0x660);
    } else if (r >= 0x6F0 && r <= 0x6F9) {
      b.writeCharCode(0x30 + r - 0x6F0);
    } else if (r == 0x66B) {
      b.write('.');
    } else if (r == 0x66C) {
      // فاصلة الآلاف
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// التطبيع للأرقام: الأرقام والفواصل الأول، وبعدين تطبيع الحروف — مع الإبقاء
/// على «1,250» و«45.50» كرقم واحد.
String normalizeForNumbers(String text) {
  var s = normalizeDigits(text);
  // فاصلة الآلاف بين أرقام بتفضل (normalizeArabic بيشيل «,» عادةً)
  s = s.replaceAllMapped(RegExp(r'(\d),(\d{3})(?!\d)'), (m) => '${m[1]}\u0001${m[2]}');
  s = normalizeArabic(s).replaceAll('\u0001', ',');
  return s;
}

/// «و» للعطف («ألف وخمسميه») و«ب» للسعر («بميه») ملزوقين في أول الرقم.
String _stripClitics(String token) {
  var out = token;
  for (final prefix in ['وب', 'و', 'ب']) {
    if (out.length > prefix.length && out.startsWith(prefix) && isNumberWord(out.substring(prefix.length))) {
      out = out.substring(prefix.length);
      break;
    }
  }
  if (out == token && token.startsWith('و') && token.length > 1) out = token.substring(1);
  return out;
}

/// سلسلة كلمات أرقام → قيمة. الأرقام العربية جمعية ومربوطة بـ«و».
double? parseWordRun(List<String> tokens) {
  var total = 0.0;
  int? pendingConstruct;
  var matched = false;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token == 'و') continue;
    if (_thousandPlural.contains(token)) {
      total += (pendingConstruct ?? 1) * 1000;
      pendingConstruct = null;
      matched = true;
      continue;
    }
    if (token == 'مليون' && pendingConstruct != null) {
      total += pendingConstruct * 1000000;
      pendingConstruct = null;
      matched = true;
      continue;
    }
    for (final map in [_hundreds, _thousands, _million, _teens, _tens, _units]) {
      final v = map[token];
      if (v != null) {
        total += v;
        pendingConstruct = null;
        matched = true;
        break;
      }
    }
    if (_hundreds.containsKey(token) || _thousands.containsKey(token) || _million.containsKey(token) || _teens.containsKey(token) || _tens.containsKey(token) || _units.containsKey(token)) {
      continue;
    }
    if (_construct.containsKey(token)) {
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      if (next != null && (_thousandPlural.contains(next) || next == 'مليون')) {
        pendingConstruct = _construct[token];
      } else {
        total += _construct[token]!;
        matched = true;
      }
      continue;
    }
  }
  if (pendingConstruct != null) {
    total += pendingConstruct;
    matched = true;
  }
  return matched ? total : null;
}

/// «تلاتة ونص» → ٣٫٥: الكسر في الآخر كان اتحسب كرقم إضافة (ربع = ٤) — بيتصلّح.
double _applyTrailingFraction(List<String> run, double value) {
  final last = run.last;
  if (_fractions.containsKey(last) && run.length > 1) {
    final asNumber = _construct[last] ?? 0;
    return value - asNumber + _fractions[last]!;
  }
  return value;
}

/// كل الأرقام اللي في الجملة — أرقام وكلام، بالترتيب، من غير تكرار.
/// الصفر والسالب ما بيرجعوش.
List<SpokenNumber> extractNumbers(String text) {
  final normalized = normalizeForNumbers(text);
  if (normalized.isEmpty) return const [];
  final out = <SpokenNumber>[];
  final seen = <double>{};
  void push(String raw, double? value) {
    if (value == null || !value.isFinite || value <= 0) return;
    final rounded = (value * 100).round() / 100;
    if (!seen.add(rounded)) return;
    out.add(SpokenNumber(raw.trim(), rounded));
  }

  final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
  final consumed = <int>{};

  // المرور الأول — الأرقام
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final k = _kSuffix.firstMatch(token);
    if (k != null) {
      consumed.add(i);
      push(token, double.parse(k.group(1)!) * 1000);
      continue;
    }
    final digitToken = token.replaceFirst(RegExp(r'^[وب]ـ?(?=\d)'), '');
    final d = _digits.firstMatch(digitToken);
    if (d == null) continue;
    var value = double.parse('${d.group(1)!.replaceAll(',', '')}.${d.group(2) ?? '0'}');
    var raw = token;
    consumed.add(i);
    final next = i + 1 < tokens.length ? tokens[i + 1] : null;
    if (next != null && (_thousandPlural.contains(next) || _thousands.containsKey(next))) {
      value *= 1000;
      raw = '$token $next';
      i++;
      consumed.add(i);
    } else if (next != null && _million.containsKey(next)) {
      value *= 1000000;
      raw = '$token $next';
      i++;
      consumed.add(i);
    }
    final after = i + 1 < tokens.length ? tokens[i + 1] : null;
    if (after == 'و' && i + 2 < tokens.length && _fractions.containsKey(tokens[i + 2])) {
      value += _fractions[tokens[i + 2]]!;
      raw = '$raw و${tokens[i + 2]}';
      consumed.addAll([i + 1, i + 2]);
      i += 2;
    } else if (after != null && after.startsWith('و') && _fractions.containsKey(after.substring(1))) {
      value += _fractions[after.substring(1)]!;
      raw = '$raw $after';
      i++;
      consumed.add(i);
    }
    push(raw, value);
  }

  // المرور التاني — الكلام
  var run = <String>[];
  var runRaw = <String>[];
  void flush() {
    if (run.isNotEmpty) {
      final value = parseWordRun(run);
      if (value != null) push(runRaw.join(' '), _applyTrailingFraction(run, value));
    }
    run = [];
    runRaw = [];
  }

  for (var i = 0; i < tokens.length; i++) {
    if (consumed.contains(i)) {
      flush();
      continue;
    }
    final token = tokens[i];
    final bare = _stripClitics(token);
    if (isNumberWord(bare) || (run.isNotEmpty && (token == 'و' || _fractions.containsKey(bare)))) {
      run.add(bare == token ? token : bare);
      runRaw.add(token);
    } else {
      flush();
    }
  }
  flush();
  return out;
}

/// أول رقم في الجملة — أو null.
double? firstNumber(String text) {
  final all = extractNumbers(text);
  return all.isEmpty ? null : all.first.value;
}
