// ملخص قياسات فترة — أرقام بس (D3.8). عدد، أقل، أعلى، متوسط. مفيش سهم
// «↑ عن الشهر السابق» ولا حكم: الدكتور هو اللي بيقرا الأرقام.

class GlucoseStats {
  const GlucoseStats({required this.count, required this.lowest, required this.highest, required this.average});

  final int count;
  final int lowest;
  final int highest;

  /// مقرّب لأقرب رقم صحيح.
  final int average;

  static GlucoseStats? of(List<int> values) {
    if (values.isEmpty) return null;
    var lo = values.first, hi = values.first, sum = 0;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
      sum += v;
    }
    return GlucoseStats(count: values.length, lowest: lo, highest: hi, average: (sum / values.length).round());
  }
}
