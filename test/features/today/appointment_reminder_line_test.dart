// «مواعيدك الجاية»: «هنفكّرك امبارحه وفي يومه» ما كانتش واضحة (طلب المدير،
// ٤ أكتوبر ٢٠٢٦). الجملة بقت بالساعتين — من ثوابت الإشعار نفسها.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/services/appointment_plan.dart';
import 'package:fakkarni/features/today/today_screen.dart' show appointmentReminderLine;

void main() {
  test('الجملة بتقول الساعتين بالحرف', () {
    expect(appointmentReminderLine, 'هنفكّرك ٨ بالليل قبلها بيوم، و٨ الصبح في يومها');
  });

  test('ومن نفس الثوابت اللي الإشعار بيرن عليها', () {
    expect(dayBeforeMinute.hour, 20);
    expect(dayOfMinute.hour, 8);
    expect(appointmentReminderLine, isNot(contains('امبارحه')));
  });
}
