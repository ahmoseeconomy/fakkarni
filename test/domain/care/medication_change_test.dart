import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/escalation/alert_mode.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

/// تغيير الدوا المعلّق (المرحلة ب) — دارت نقية.
void main() {
  test('الحمولة بتروح وترجع بالحرف: مراسي وساعة، والباقي', () {
    const payload = MedicationChangePayload(
      name: 'Concor 5mg',
      timings: [AnchorTiming(DayAnchor.breakfast, -30), FixedTiming(MinuteOfDay(21 * 60))],
      amountLabel: 'قرص',
      durationDays: 7,
      purpose: MedicationPurpose.pressure,
      instructions: 'مع مية',
      alertMode: AlertMode.continuous,
    );
    final back = MedicationChangePayload.fromJson(
      (payload.toJson()..['start_date'] = '2026-09-20').cast<String, dynamic>(),
    );
    expect(back.name, 'Concor 5mg');
    expect(back.timings, payload.timings);
    expect(back.amountLabel, 'قرص');
    expect(back.durationDays, 7);
    expect(back.purpose, MedicationPurpose.pressure);
    expect(back.instructions, 'مع مية');
    expect(back.alertMode, AlertMode.continuous);
    expect(back.startDate, DateTime(2026, 9, 20));
  });

  test('حمولة بايظة ما بترميش: مواعيد غلط بتتعدّى، والفاضي فاضي', () {
    final p = MedicationChangePayload.fromJson({
      'timings': [
        {'kind': 'anchor', 'anchor': 'brunch', 'offset': 0},
        {'kind': 'fixed', 'minute': 5000},
        'garbage',
      ],
      'duration_days': 'x',
    });
    expect(p.timings, isEmpty);
    expect(p.durationDays, isNull);
    expect(p.name, isNull);
  });

  test('الجملة بالاسم، ومن غير اسم «حد بيتابعك»', () {
    expect(medicationChangeNotice('سارة', MedicationChangeKind.add, 'Concor'), 'سارة ضاف دوا Concor');
    expect(medicationChangeNotice(null, MedicationChangeKind.stop, 'Concor'), 'حد بيتابعك وقّف دوا Concor');
    expect(medicationChangeNotice(' ', MedicationChangeKind.amount, 'Concor'), 'حد بيتابعك عدّل جرعة Concor');
  });

  test('تعديل الأب المحلي بيكسب لو حصل بعد الاقتراح', () {
    final sent = DateTime(2026, 9, 20, 10);
    expect(localEditWins(localUpdatedAt: DateTime(2026, 9, 20, 11), changeCreatedAt: sent), isTrue);
    expect(localEditWins(localUpdatedAt: DateTime(2026, 9, 20, 9), changeCreatedAt: sent), isFalse);
  });
}
