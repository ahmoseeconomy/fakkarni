// **القياسات الحيوية** (٢٥ سبتمبر ٢٠٢٦) — دارت نقية.
//
// السكر كان القياس الوحيد؛ دلوقتي كمان الضغط (انقباضي/انبساطي + نبض
// اختياري)، النبض، الوزن، الأكسجين %، والحرارة.
//
// **الخطوط الحمرا (نفس D3.6):** رقم، والمعتاد **ليه هو**، والفرق — وبس.
// مفيش «طبيعي» ولا «مش طبيعي»، مفيش تشخيص ولا نصيحة ولا لون خطر. أي حاجة
// طبية بتخلص عند «اسأل دكتورك». **الحدود هنا مش طبية**: دي حدود اللي
// الأجهزة بتقراه أصلاً، ورقم برّاها غالباً غلطة إيد — «الرقم ده غريب —
// راجعه»، زي حدود السكر ٢٠–٦٠٠.

import 'dart:math' as math;

enum VitalKind {
  bloodPressure('الضغط', 'مم زئبق', decimals: false),
  pulse('النبض', 'نبضة/دقيقة', decimals: false),
  weight('الوزن', 'كيلو', decimals: true),
  spo2('الأكسجين', '٪', decimals: false),
  temperature('الحرارة', '°م', decimals: true);

  const VitalKind(this.label, this.unit, {required this.decimals});

  final String label;
  final String unit;

  /// الكيبورد بيقبل كسر؟ (الوزن ٧٢٫٥، الحرارة ٣٧٫٢)
  final bool decimals;

  static VitalKind? fromStored(String? s) => values.asNameMap()[s];

  /// حدود «الجهاز بيقرا كده» — مش حدود طبية.
  (double, double) get range => switch (this) {
        // الانقباضي — الانبساطي ليه حدوده تحت
        bloodPressure => (50, 260),
        pulse => (25, 250),
        weight => (10, 300),
        spo2 => (50, 100),
        temperature => (32, 43),
      };
}

/// حدود الانبساطي — والانبساطي لازم يبقى أقل من الانقباضي.
const (double, double) diastolicRange = (25, 180);

/// اللي المستخدم كتبه — قبل ما يتحفظ.
class VitalEntry {
  const VitalEntry({required this.kind, required this.value, this.value2, this.pulse});

  final VitalKind kind;

  /// الانقباضي في الضغط، والقيمة نفسها في الباقي.
  final double value;

  /// الانبساطي — للضغط بس.
  final double? value2;

  /// نبض اختياري مع الضغط.
  final int? pulse;
}

/// الأرقام العربي والفاصلة العربي → رقم. null = مش رقم.
double? parseVitalNumber(String raw) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final out = StringBuffer();
  for (final ch in raw.trim().split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      out.write(i);
    } else if (ch == '٫' || ch == ',' || ch == '،') {
      out.write('.');
    } else {
      out.write(ch);
    }
  }
  return double.tryParse(out.toString());
}

/// **الرقم معقول يتسجّل؟** null = تمام؛ غير كده الجملة اللي بتتقال. نفس
/// روح السكر: الرقم ده غالباً غلطة إيد، مش حكم على الجسم.
String? vitalEntryProblem(VitalEntry e) {
  const odd = 'الرقم ده غريب — راجعه';
  bool inRange(double v, (double, double) r) => v >= r.$1 && v <= r.$2;
  if (!inRange(e.value, e.kind.range)) return odd;
  if (e.kind == VitalKind.bloodPressure) {
    final dia = e.value2;
    if (dia == null) return 'اكتب الرقم التاني كمان';
    if (!inRange(dia, diastolicRange) || dia >= e.value) return odd;
    final p = e.pulse;
    if (p != null && !inRange(p.toDouble(), VitalKind.pulse.range)) return odd;
  }
  return null;
}

/// قياس محفوظ.
class Vital {
  const Vital({required this.kind, required this.value, required this.measuredAt, this.value2, this.pulse});

  final VitalKind kind;
  final double value;
  final double? value2;
  final int? pulse;
  final DateTime measuredAt;
}

/// أقل عدد قياسات في ٣٠ يوم عشان يبقى فيه «معتاد». أقل من كده بنقولها.
const int vitalUsualMinCount = 3;
const Duration vitalUsualWindow = Duration(days: 30);

/// **«المعتاد ليك»** — متوسطه هو في آخر ٣٠ يوم. للضغط متوسطين.
class VitalUsual {
  const VitalUsual({required this.count, required this.average, this.average2});

  final int count;
  final double average;
  final double? average2;
}

/// null = مفيش قياسات كفاية لسه.
VitalUsual? vitalUsual(List<Vital> all, VitalKind kind, DateTime now) {
  final from = now.subtract(vitalUsualWindow);
  final shown = [for (final v in all) if (v.kind == kind && !v.measuredAt.isBefore(from) && !v.measuredAt.isAfter(now)) v];
  if (shown.length < vitalUsualMinCount) return null;
  double avg(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  final seconds = [for (final v in shown) if (v.value2 != null) v.value2!];
  return VitalUsual(
    count: shown.length,
    average: avg(shown.map((v) => v.value)),
    average2: seconds.isEmpty ? null : avg(seconds),
  );
}

/// الرقم زي ما بيتكتب — صحيح أو بخانة عشرية واحدة، بأرقام عربي.
String vitalNumber(double v, VitalKind kind) {
  final text = kind.decimals ? _oneDecimal(v) : v.round().toString();
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  return text.split('').map((c) => c == '.' ? '٫' : (int.tryParse(c) == null ? c : arabic[int.parse(c)])).join();
}

String _oneDecimal(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
}

/// «١٣٠/٨٥ مم زئبق — نبض ٧٢» / «٧٢٫٥ كيلو».
String vitalValueText(Vital v) {
  if (v.kind == VitalKind.bloodPressure) {
    final base = '${vitalNumber(v.value, v.kind)}/${vitalNumber(v.value2 ?? 0, v.kind)} ${v.kind.unit}';
    return v.pulse == null ? base : '$base — نبض ${vitalNumber(v.pulse!.toDouble(), VitalKind.pulse)}';
  }
  return '${vitalNumber(v.value, v.kind)} ${v.kind.unit}';
}

/// «المعتاد ليك» بالكلام — أو ليه لسه مفيش.
String vitalUsualLine(VitalUsual? usual, VitalKind kind) {
  if (usual == null) {
    return 'لسه ما عندناش قياسات كفاية نعرف المعتاد ليك — محتاجين ${_arabicInt(vitalUsualMinCount)} في آخر ٣٠ يوم.';
  }
  final value = kind == VitalKind.bloodPressure
      ? '${vitalNumber(usual.average, kind)}/${vitalNumber(usual.average2 ?? 0, kind)}'
      : vitalNumber(usual.average, kind);
  return 'المعتاد ليك (متوسط آخر ٣٠ يوم): $value ${kind.unit}';
}

/// **الفرق عن المعتاد** — رقم بإشارة، من غير «عالي» ولا «واطي» ولا لون.
/// null لو مفيش معتاد.
String? vitalDifferenceLine(Vital latest, VitalUsual? usual) {
  if (usual == null) return null;
  String diff(double a, double b, VitalKind k) {
    final d = a - b;
    final step = k.decimals ? 0.1 : 1.0;
    if (d.abs() < step / 2) return 'زي المعتاد';
    final sign = d > 0 ? '+' : '−';
    return '$sign${vitalNumber(d.abs(), k)}';
  }

  final k = latest.kind;
  if (k == VitalKind.bloodPressure && usual.average2 != null && latest.value2 != null) {
    return 'الفرق عن المعتاد ليك: ${diff(latest.value, usual.average, k)} / ${diff(latest.value2!, usual.average2!, k)}';
  }
  return 'الفرق عن المعتاد ليك: ${diff(latest.value, usual.average, k)}';
}

/// «اسأل دكتورك» — آخر كلمة في أي حاجة طبية على شاشة القياسات.
const String vitalsAskDoctor = 'لو عندك سؤال عن الأرقام دي، اسأل دكتورك.';

String _arabicInt(int n) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((c) => arabic[int.parse(c)]).join();
}

/// نقط الرسم لفترة: أيام [days] اللي فاتت — للضغط خطين.
({List<(DateTime, double)> first, List<(DateTime, double)> second}) vitalSeries(
  List<Vital> all,
  VitalKind kind,
  DateTime now,
  int days,
) {
  final from = now.subtract(Duration(days: days));
  final shown = [for (final v in all) if (v.kind == kind && !v.measuredAt.isBefore(from)) v]
    ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  return (
    first: [for (final v in shown) (v.measuredAt, v.value)],
    second: [for (final v in shown) if (v.value2 != null) (v.measuredAt, v.value2!)],
  );
}

/// أقل وأعلى نقطة في الرسم، بهامش صغير — عشان الخط ما يلزقش في الحافة.
(double, double) vitalChartBounds(List<double> values) {
  if (values.isEmpty) return (0, 1);
  var lo = values.reduce(math.min), hi = values.reduce(math.max);
  if (hi - lo < 1) {
    lo -= 1;
    hi += 1;
  }
  final pad = (hi - lo) * 0.1;
  return (lo - pad, hi + pad);
}

/// آخر قياس لكل نوع، بترتيب الأنواع — لصفحة الدكتور والملف.
List<Vital> latestVitals(List<Vital> all) {
  final latest = <VitalKind, Vital>{};
  for (final v in all) {
    final cur = latest[v.kind];
    if (cur == null || v.measuredAt.isAfter(cur.measuredAt)) latest[v.kind] = v;
  }
  return [for (final k in VitalKind.values) ?latest[k]];
}
