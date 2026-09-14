// «المعتاد ليه هو» (D3.6) — دارت نقية.
//
// **مفيش هنا أي نطاق من كتاب.** النطاق هو من أقل لأعلى قياس في آخر
// [usualWindow] قياسات **بتوعه هو**، ولو لسه أقل من الحد، مفيش نطاق خالص
// والشاشة بتقول كده بصراحة. المقارنة رقم وفرق — مش «مرتفع» ولا «طبيعي».

/// آخر كام قياس بيتحسب منهم المعتاد.
const int usualWindow = 10;

/// قياسات السكر: أقل من ٥ في نفس السياق = مش كفاية.
const int minGlucoseReadings = 5;

/// نفس التحليل في تقارير فاتت: أقل من ٢ = مش كفاية.
const int minLabValues = 2;

class UsualRange {
  const UsualRange(this.low, this.high, this.count);

  final num low;
  final num high;

  /// كام قياس اتحسب منهم.
  final int count;
}

/// [previousNewestFirst] القياسات اللي **قبل** اللي بنقارنه، الأحدث الأول.
UsualRange? usualRangeOf(List<num> previousNewestFirst, {required int minimum}) {
  final window = previousNewestFirst.take(usualWindow).toList();
  if (window.length < minimum) return null;
  var low = window.first, high = window.first;
  for (final v in window) {
    if (v < low) low = v;
    if (v > high) high = v;
  }
  return UsualRange(low, high, window.length);
}

sealed class UsualComparison {
  const UsualComparison();
}

final class WithinUsual extends UsualComparison {
  const WithinUsual();
}

final class AboveUsual extends UsualComparison {
  const AboveUsual(this.by);

  /// الفرق عن أعلى قياس معتاد.
  final num by;
}

final class BelowUsual extends UsualComparison {
  const BelowUsual(this.by);

  /// الفرق عن أقل قياس معتاد.
  final num by;
}

UsualComparison compareToUsual(num value, UsualRange range) {
  if (value > range.high) return AboveUsual(value - range.high);
  if (value < range.low) return BelowUsual(range.low - value);
  return const WithinUsual();
}
