// حساب التزام الملف (المرحلة ٤ — قرارات المالك 4A/5A) — نقي بالأرقام.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/adherence/export_adherence.dart';

ExportDoseRow row(
  int day,
  ExportDoseState state, {
  int med = 1,
  String name = 'Concor',
  int hour = 9,
  DateTime? actedAt,
  int month = 8,
}) => ExportDoseRow(
  medicationId: med,
  medicationName: name,
  routineDay: DateTime(2026, month, day),
  scheduledAt: DateTime(2026, month, day, hour),
  state: state,
  actedAt: actedAt,
);

void main() {
  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31);
  final now = DateTime(2026, 8, 31, 12);

  test('4A: الأيام المتسجّلة بس — يوم من غير صفوف لا فايت ولا كامل، والعدّ بيقوله', () {
    final a = exportAdherence(rows: [
      row(1, ExportDoseState.taken, actedAt: DateTime(2026, 8, 1, 9, 10)),
      row(2, ExportDoseState.missed),
      // ٣ → ٢٩ مفيش ولا صف (موبايل مقفول) — مش بيدخلوا في أي حساب
      row(30, ExportDoseState.taken, actedAt: DateTime(2026, 8, 30, 9)),
    ], from: from, to: to, now: now);
    expect(a.recordedDays, 3);
    expect(a.countable, 3);
    expect(a.taken, 2);
    expect(a.pct, 67, reason: '٢ من ٣ — مش ٢ من ٣١ يوم');
    expect(a.recordedDaysLine, 'من ٣ أيام متسجّلة');
    expect(a.firstRecordedDay, DateTime(2026, 8, 1));
  });

  test('5A: «مش هاخده» برّه البسط والمقام — وليها سطر عدّ لوحدها', () {
    final a = exportAdherence(rows: [
      row(1, ExportDoseState.taken, actedAt: DateTime(2026, 8, 1, 9)),
      row(2, ExportDoseState.skipped),
      row(3, ExportDoseState.skipped),
    ], from: from, to: to, now: now);
    expect(a.countable, 1, reason: 'المتخطّية مش في المقام');
    expect(a.pct, 100, reason: 'ولا في البسط');
    expect(a.skipped, 2);
    expect(a.skippedLine, 'وجرعتين قالهم «مش هاخدهم» — مش محسوبين في النسبة');
    // واليوم اللي كله متخطّي لسه «متسجّل» — التسجيل وصف للصفوف مش للنتيجة
    expect(a.recordedDays, 3);
  });

  test('pending جوّه مهلته = جرعة جاية مش التزام؛ وعدّى الـ٤٥ = «ما اتاخدتش»', () {
    final a = exportAdherence(rows: [
      // معادها ٩:٠٠ والساعة ١٢:٠٠ → عدّت المهلة → بتتحسب
      row(31, ExportDoseState.pending, hour: 9),
      // معادها ١١:٣٠ والساعة ١٢:٠٠ → جوّه الـ٤٥ → مش بتتحسب
      ExportDoseRow(
        medicationId: 1,
        medicationName: 'Concor',
        routineDay: DateTime(2026, 8, 31),
        scheduledAt: DateTime(2026, 8, 31, 11, 30),
        state: ExportDoseState.pending,
      ),
    ], from: from, to: to, now: DateTime(2026, 8, 31, 12));
    expect(a.countable, 1);
    expect(a.pct, 0);
  });

  test('«في ميعادها» على حد الـ٤٥ بالظبط داخلة — وبعده بدقيقة برّه', () {
    final a = exportAdherence(rows: [
      row(1, ExportDoseState.taken, actedAt: DateTime(2026, 8, 1, 9, 45)),
      row(2, ExportDoseState.taken, actedAt: DateTime(2026, 8, 2, 9, 46)),
    ], from: from, to: to, now: now);
    expect(a.onTime, 1);
    expect(a.judgedTaken, 2);
    expect(a.onTimeLine, '١ من ٢ — جرعة اتاخدت في ميعادها');
  });

  test('متاخدة من غير actedAt: مش بتتحكم — بتطلع من M، مش متأخرة بالتخمين', () {
    final a = exportAdherence(rows: [
      row(1, ExportDoseState.taken), // صف قديم من غير وقت فعل
      row(2, ExportDoseState.taken, actedAt: DateTime(2026, 8, 2, 9)),
    ], from: from, to: to, now: now);
    expect(a.taken, 2);
    expect(a.judgedTaken, 1, reason: 'اللي ينفع يتحكم عليه بس');
    expect(a.onTime, 1);
  });

  test('لكل دوا ولكل شهر — وsuperseded ولا بتتحسب ولا بتتعدّ', () {
    final a = exportAdherence(rows: [
      row(1, ExportDoseState.taken, med: 1, name: 'Concor', actedAt: DateTime(2026, 8, 1, 9)),
      row(2, ExportDoseState.missed, med: 1, name: 'Concor'),
      row(3, ExportDoseState.taken, med: 2, name: 'Augmentin', actedAt: DateTime(2026, 8, 3, 9)),
      row(4, ExportDoseState.superseded, med: 2, name: 'Augmentin'),
      row(10, ExportDoseState.taken, med: 1, name: 'Concor', month: 7, actedAt: DateTime(2026, 7, 10, 9)),
    ], from: DateTime(2026, 7, 1), to: to, now: now);
    final concor = a.perMedicine.firstWhere((m) => m.name == 'Concor');
    expect(concor.taken, 2);
    expect(concor.countable, 3);
    expect(concor.pct, 67);
    final augmentin = a.perMedicine.firstWhere((m) => m.name == 'Augmentin');
    expect(augmentin.countable, 1, reason: 'superseded مش جرعة');
    expect(augmentin.pct, 100);

    expect(a.perMonth.length, 2);
    expect((a.perMonth.first.year, a.perMonth.first.month), (2026, 7));
    expect(a.perMonth.first.pct, 100);
    expect(a.perMonth.last.pct, 67);
  });

  test('عمرنا ما نقدّر: مفيش صفوف = null مش صفر — والسطور بتقول ليه', () {
    final a = exportAdherence(rows: const [], from: from, to: to, now: now);
    expect(a.pct, isNull);
    expect(a.onTimeLine, isNull);
    expect(a.skippedLine, isNull);
    expect(a.recordedDaysLine, 'مفيش أيام متسجّلة في الفترة دي');
    expect(a.firstRecordedDay, isNull);
  });

  test('صيغ العدد: يوم واحد / يومين / أيام / يوم', () {
    ExportAdherence withDays(int n) => exportAdherence(
          rows: [for (var d = 1; d <= n; d++) row(d, ExportDoseState.taken, actedAt: DateTime(2026, 8, d, 9))],
          from: from,
          to: to,
          now: now,
        );
    expect(withDays(1).recordedDaysLine, 'من يوم واحد متسجّل');
    expect(withDays(2).recordedDaysLine, 'من يومين متسجّلين');
    expect(withDays(5).recordedDaysLine, 'من ٥ أيام متسجّلة');
    expect(withDays(12).recordedDaysLine, 'من ١٢ يوم متسجّل');
  });
}
