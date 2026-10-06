/// حساب التزام الملف المطبوع (المرحلة ٤، ٥ أكتوبر ٢٠٢٦ مساءً) — دارت نقية.
///
/// قرارات المالك، بالنص:
/// - **4A**: النسبة بتتحسب على **الأيام المتسجّلة بس** — يوم من غير ولا صف
///   `dose_events` (موبايل مقفول أسبوع مثلاً) مش «فايت» ولا «كامل»: هو
///   **مش متسجّل**، والملف بيقولها («من N يوم متسجّل»).
/// - **5A**: «مش هاخده» (skipped) قرار إنسان مش نسيان — **برّه** البسط
///   والمقام، وله سطر عدّ لوحده.
/// - المقام = اتاخدت + اتنست + pending اللي عدّى مهلته (٤٥ دقيقة — نفس
///   `graceWindow` بتاعة الجهاز)؛ pending لسه جاية مش التزام ولا عدمه.
/// - «في ميعادها» = `actedAt ≤ scheduledAt + graceWindow`. جرعة متاخدة من
///   غير `actedAt` (صفوف قديمة) **مش بتتحكم عليها**: بتطلع من M، مش
///   بتتحسب متأخرة بالتخمين.
/// - **عمرنا ما نقدّر**: مفيش حاجة تتحسب بصدق = null، والملف ما يعرضش
///   رقم مكانها.
library;

import '../../core/format/arabic_time.dart' show arabicNumber;
import '../escalation/escalation_ladder.dart' show graceWindow;

/// حالة الصف زي ما هي في `dose_events` — بالاسم، عشان الملف ده ما
/// يستوردش طبقة البيانات.
enum ExportDoseState { pending, taken, skipped, missed, superseded }

/// صف جرعة واحد للحساب.
class ExportDoseRow {
  const ExportDoseRow({
    required this.medicationId,
    required this.medicationName,
    required this.routineDay,
    required this.scheduledAt,
    required this.state,
    this.actedAt,
  });

  final int medicationId;
  final String medicationName;

  /// يوم الروتين (٤:٠٠) — جرعة ١ بالليل تبع امبارح.
  final DateTime routineDay;
  final DateTime scheduledAt;
  final ExportDoseState state;
  final DateTime? actedAt;
}

/// التزام دوا واحد في الفترة.
class MedAdherence {
  const MedAdherence({required this.medicationId, required this.name, required this.taken, required this.countable});

  final int medicationId;
  final String name;
  final int taken;
  final int countable;

  /// null = مفيش جرعات تتحسب للدوا ده في الفترة — ما نعرضش رقم.
  int? get pct => countable == 0 ? null : (taken * 100 / countable).round();
}

/// التزام شهر واحد.
class MonthAdherence {
  const MonthAdherence({required this.year, required this.month, required this.taken, required this.countable});

  final int year;
  final int month;
  final int taken;
  final int countable;

  int? get pct => countable == 0 ? null : (taken * 100 / countable).round();
}

class ExportAdherence {
  const ExportAdherence({
    required this.recordedDays,
    required this.taken,
    required this.countable,
    required this.skipped,
    required this.onTime,
    required this.judgedTaken,
    required this.perMedicine,
    required this.perMonth,
    required this.firstRecordedDay,
  });

  /// أيام الروتين اللي ليها **أي** صف — «متسجّل» وصف للتسجيل مش للنتيجة.
  final int recordedDays;

  final int taken;
  final int countable;
  final int skipped;

  /// في ميعادها، من اللي ينفع يتحكم عليه ([judgedTaken]).
  final int onTime;
  final int judgedTaken;

  final List<MedAdherence> perMedicine;
  final List<MonthAdherence> perMonth;

  /// أقدم يوم متسجّل — لسطر «البيانات بتبدأ من …» لما الفترة أطول من عمر
  /// التسجيل.
  final DateTime? firstRecordedDay;

  /// النسبة الكلية — null لما مفيش حاجة تتحسب (الملف ما يعرضش رقم).
  int? get pct => countable == 0 ? null : (taken * 100 / countable).round();

  /// «من N يوم متسجّل» (4A) — بصيغة العدد الصح.
  String get recordedDaysLine => switch (recordedDays) {
        0 => 'مفيش أيام متسجّلة في الفترة دي',
        1 => 'من يوم واحد متسجّل',
        2 => 'من يومين متسجّلين',
        <= 10 => 'من ${arabicNumber(recordedDays)} أيام متسجّلة',
        _ => 'من ${arabicNumber(recordedDays)} يوم متسجّل',
      };

  /// سطر «مش هاخده» (5A) — null لما مفيش.
  String? get skippedLine => switch (skipped) {
        0 => null,
        1 => 'وجرعة واحدة قالها «مش هاخدها» — مش محسوبة في النسبة',
        2 => 'وجرعتين قالهم «مش هاخدهم» — مش محسوبين في النسبة',
        _ => 'و${arabicNumber(skipped)} جرعات قال فيهم «مش هاخده» — مش محسوبة في النسبة',
      };

  /// «N من M — جرعة اتاخدت في ميعادها» — null لما مفيش M.
  String? get onTimeLine =>
      judgedTaken == 0 ? null : '${arabicNumber(onTime)} من ${arabicNumber(judgedTaken)} — جرعة اتاخدت في ميعادها';
}

/// الحساب — [from]/[to] أيام روتين داخلة، و[now] لحكم pending اللي عدّى
/// مهلته (الجاية لسه مش التزام).
ExportAdherence exportAdherence({
  required List<ExportDoseRow> rows,
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final f = day(from), t = day(to);
  bool inRange(DateTime d) => !day(d).isBefore(f) && !day(d).isAfter(t);

  final recorded = <DateTime>{};
  var taken = 0, countable = 0, skipped = 0, onTime = 0, judged = 0;
  final byMed = <int, (String, int, int)>{}; // id → (اسم، اتاخدت، تتحسب)
  final byMonth = <(int, int), (int, int)>{};
  DateTime? first;

  for (final r in rows) {
    if (!inRange(r.routineDay)) continue;
    final d = day(r.routineDay);
    recorded.add(d);
    if (first == null || d.isBefore(first)) first = d;

    final counts = switch (r.state) {
      ExportDoseState.taken || ExportDoseState.missed => true,
      // pending جوّه مهلته = جرعة جاية — لا التزام ولا عدمه
      ExportDoseState.pending => now.isAfter(r.scheduledAt.add(graceWindow)),
      ExportDoseState.skipped || ExportDoseState.superseded => false,
    };
    if (r.state == ExportDoseState.skipped) skipped++;
    if (!counts) continue;

    countable++;
    final isTaken = r.state == ExportDoseState.taken;
    if (isTaken) {
      taken++;
      if (r.actedAt case final at?) {
        judged++;
        if (!at.isAfter(r.scheduledAt.add(graceWindow))) onTime++;
      }
    }
    final med = byMed[r.medicationId] ?? (r.medicationName, 0, 0);
    byMed[r.medicationId] = (med.$1, med.$2 + (isTaken ? 1 : 0), med.$3 + 1);
    final mk = (d.year, d.month);
    final m = byMonth[mk] ?? (0, 0);
    byMonth[mk] = (m.$1 + (isTaken ? 1 : 0), m.$2 + 1);
  }

  final months = byMonth.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  final meds = byMed.entries.toList()..sort((a, b) => a.value.$1.compareTo(b.value.$1));
  return ExportAdherence(
    recordedDays: recorded.length,
    taken: taken,
    countable: countable,
    skipped: skipped,
    onTime: onTime,
    judgedTaken: judged,
    perMedicine: [
      for (final e in meds)
        MedAdherence(medicationId: e.key, name: e.value.$1, taken: e.value.$2, countable: e.value.$3),
    ],
    perMonth: [
      for (final k in months)
        MonthAdherence(year: k.$1, month: k.$2, taken: byMonth[k]!.$1, countable: byMonth[k]!.$2),
    ],
    firstRecordedDay: first,
  );
}
