// «احجز عند د. حسن» — الدكتور بيتدوّر عليه في دكاترة المريض الحقيقيين بس.
// **عمرنا ما نعمل دكتور من اسم اتقال لوحده.** دارت نقية.

import '../voice/nlu/normalize.dart';

const _titles = {'د', 'دكتور', 'الدكتور', 'دكتوره', 'الدكتوره', 'دكتورة', 'طبيب', 'الطبيب', 'dr', 'doctor', 'prof', 'بروفيسور', 'استاذ', 'ا'};

/// كلمات الاسم من غير اللقب — بعد التطبيع (أ/ا، ة/ه، ى/ي).
List<String> doctorNameKey(String name) => [
      for (final t in utteranceTokens(normalizeUtterance(name.toLowerCase().replaceAll(RegExp(r'[.\-_/،,()]'), ' '))))
        if (!_titles.contains(t)) t,
    ];

/// دكاترة المريض من ملفه (عمود «الدكتور» على الزيارات والروشتات والمواعيد) —
/// من غير تكرار، بالكتابة الأولى اللي اتسجّلت بيها.
List<String> distinctDoctors(Iterable<String?> names) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in names) {
    final n = raw?.trim();
    if (n == null || n.isEmpty) continue;
    final key = doctorNameKey(n).join(' ');
    if (key.isEmpty || !seen.add(key)) continue;
    out.add(n);
  }
  return out;
}

/// الدكاترة اللي اسمهم يطابق اللي اتقال: **كل** كلمة اتقالت لازم تلاقي كلمة
/// في الاسم — بالظبط، أو بحرف واحد فرق في الكلمات الطويلة (٥ حروف وأكتر)
/// عشان غلطات المتعرّف. «حسن» مش «حسين»: الأسامي القصيرة لازم تتطابق.
List<String> matchDoctors(String spoken, List<String> doctors) {
  final want = doctorNameKey(spoken);
  if (want.isEmpty) return const [];
  return [
    for (final d in doctors)
      if (_covers(doctorNameKey(d), want)) d,
  ];
}

bool _covers(List<String> have, List<String> want) =>
    want.every((w) => have.any((h) => h == w || (w.length >= 5 && h.length >= 5 && _distance(h, w) <= 1)));

int _distance(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 2;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}
