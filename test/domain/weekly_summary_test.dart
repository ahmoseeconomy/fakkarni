// ملخص الأسبوع (طلب المدير، ٤ أكتوبر ٢٠٢٦): آخر ٧ أيام **كاملة**، أرقام
// وأسامي ومواعيد — من غير حكم.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/adherence/adherence.dart';
import 'package:fakkarni/domain/adherence/weekly_summary.dart';

AdherenceDose dose(String id, DateTime day, int hour, AdherenceState state, [String name = 'Concor']) =>
    AdherenceDose(id: id, medicationName: name, routineDay: day, scheduledAt: DateTime(day.year, day.month, day.day, hour), state: state);

void main() {
  final today = DateTime(2026, 10, 4); // الحد

  test('النافذة: الـ٧ أيام اللي قبل النهارده — النهارده ويوم -٨ برّه', () {
    final s = weeklySummary(today: today, doses: [
      dose('a', DateTime(2026, 10, 4), 9, AdherenceState.pending), // النهارده — برّه
      dose('b', DateTime(2026, 10, 3), 9, AdherenceState.taken),
      dose('c', DateTime(2026, 9, 27), 9, AdherenceState.taken), // أول يوم — جوّه
      dose('d', DateTime(2026, 9, 26), 9, AdherenceState.missed), // يوم -٨ — برّه
    ]);
    expect(s.from, DateTime(2026, 9, 27));
    expect(s.to, DateTime(2026, 10, 3));
    expect(s.due, 2);
    expect(s.taken, 2);
    expect(s.missed, isEmpty);
    expect(s.title, 'ملخص الأسبوع — ٢٧ سبتمبر لـ٣ أكتوبر');
  });

  test('العدّ والجمل: المتخطّية لوحدها، واللي ما اتأكدش «ما اتأكدتش» الأحدث الأول', () {
    final s = weeklySummary(today: today, doses: [
      dose('1', DateTime(2026, 10, 1), 9, AdherenceState.taken),
      dose('2', DateTime(2026, 10, 1), 21, AdherenceState.skipped),
      dose('3', DateTime(2026, 9, 29), 21, AdherenceState.missed),
      dose('4', DateTime(2026, 10, 2), 9, AdherenceState.pending, 'Glucophage'),
    ]);
    expect(s.dosesLine, 'اتاخد ١ من ٤ جرعات — و١ متخطّية');
    expect(s.missedLine, 'ما اتأكدتش: ٢ — Glucophage (الجمعة ٩:٠٠ ص)، Concor (التلات ٩:٠٠ م)');
  });

  test('أكتر من ٣ اتنسوا: تلاتة بالاسم والباقي بالعدد', () {
    final s = weeklySummary(today: today, doses: [
      for (var i = 0; i < 5; i++) dose('m$i', DateTime(2026, 9, 28 + i), 9, AdherenceState.missed),
    ]);
    expect(s.missedLine, endsWith(' و٢ كمان'));
  });

  test('من غير جرعات: جملة واحدة، ومفيش سطر «ما اتأكدتش»', () {
    final s = weeklySummary(today: today, doses: const []);
    expect(s.dosesLine, 'مفيش جرعات كان معادها في الأسبوع ده');
    expect(s.missedLine, isEmpty);
    expect(s.lowStockLine, 'مفيش دوا قرب يخلص');
    expect(s.appointmentLine, 'مفيش مواعيد جاية');
  });

  test('قرب يخلص، وأقرب ميعاد جاي — اللي فات ما بيتحسبش', () {
    final s = weeklySummary(
      today: today,
      doses: const [],
      lowStock: const [LowStockItem('Concor', 4), LowStockItem('Glucophage', 1)],
      upcoming: [
        UpcomingItem('د. منى', DateTime(2026, 10, 20)),
        UpcomingItem('د. حسام', DateTime(2026, 10, 12, 17)),
        UpcomingItem('معمل', DateTime(2026, 10, 1)),
      ],
    );
    expect(s.lowStockLine, 'قرب يخلص: Concor (فاضله ٤ أيام)، Glucophage (فاضله يوم)');
    expect(s.appointmentLine, 'أقرب ميعاد: د. حسام — الاتنين ١٢ أكتوبر');
  });

  test('«من/إلى» بيحدّدوا المدة (المالك، ٥ أكتوبر مساءً) — والافتراضي زي ما هو آخر ٧ كاملة', () {
    final doses = [
      dose('old', DateTime(2026, 9, 20), 9, AdherenceState.taken),
      dose('in', DateTime(2026, 9, 29), 9, AdherenceState.taken),
      dose('in2', DateTime(2026, 10, 3), 9, AdherenceState.missed),
    ];
    // الافتراضي (٢٨ سبتمبر–٤ أكتوبر): القديمة برّه
    final def = weeklySummary(today: today, doses: doses);
    expect(def.due, 2);
    expect(def.title, startsWith('ملخص الأسبوع'));
    // مدة مختارة بتلم القديمة — والعنوان بيبطّل يقول «أسبوع» عن مدة مش أسبوع
    final ranged = weeklySummary(
      today: today,
      doses: doses,
      from: DateTime(2026, 9, 18),
      to: DateTime(2026, 9, 30),
    );
    expect(ranged.due, 2, reason: 'القديمة دخلت والـ٣ أكتوبر خرجت');
    expect(ranged.missed, isEmpty);
    expect(ranged.title, startsWith('الملخص —'));
    // ومدة ٧ أيام مختارة بإيد لسه «ملخص الأسبوع»
    final week = weeklySummary(today: today, doses: doses, from: DateTime(2026, 9, 21), to: DateTime(2026, 9, 27));
    expect(week.title, startsWith('ملخص الأسبوع'));
  });

  test('مفيش كلمة حكم ولا «·» في أي جملة', () {
    final s = weeklySummary(today: today, doses: [
      dose('x', DateTime(2026, 10, 1), 9, AdherenceState.missed),
      dose('y', DateTime(2026, 10, 1), 9, AdherenceState.taken),
    ], lowStock: const [LowStockItem('Concor', 3)], upcoming: [UpcomingItem('د. حسام', DateTime(2026, 10, 9))]);
    final all = [s.title, s.dosesLine, s.missedLine, s.lowStockLine, s.appointmentLine].join('\n');
    for (final w in ['فاتت', 'فشل', 'غلط', 'لازم', 'خطر', 'وحش', '·']) {
      expect(all, isNot(contains(w)), reason: w);
    }
  });
}
