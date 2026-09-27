import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

/// **البكرة بقت بالدقيقة الواحدة — ولا حاجة في الجدولة كانت بتفترض
/// خطوة خمسة.** جرعات على دقايق فردية (٦:٤٣، ٧:١٣، ٩:٠٧ م): الدمج
/// بالدقيقة، والأرقام، والسلّم، والإعادات، والأفق — كلهم بالدقيقة.
void main() {
    final day = DateTime(2026, 8, 31);

  DoseSchedule dose(String id, FixedTiming timing) => DoseSchedule(
        id: id,
        medicationName: id,
        timing: timing,
        repeat: DoseRepeat.daily,
        durationDays: null,
        amountLabel: null,
        startDate: day,
      );

  test('التوقيت يتخزّن ويرجع بالدقيقة', () {
    expect(MinuteOfDay.hm(7, 13).minutes, 433);
    expect(MinuteOfDay(433), MinuteOfDay.hm(7, 13));
    expect(MinuteOfDay.hm(7, 13).toString(), '07:13');
  });

  test('المحرّك بيحسب من ساعة فردية: ٦:٤٣ و٩:٠٧ م و١١:٤٣ م بالدقيقة', () {
    final engine = const ScheduleEngine();
    final rems = engine.remindersForDay([
      dose('a', FixedTiming(MinuteOfDay.hm(6, 43))),
      dose('b', FixedTiming(MinuteOfDay.hm(21, 7))),
      dose('c', FixedTiming(MinuteOfDay.hm(23, 43))),
    ], day);
    expect(rems.map((r) => r.at), [
      DateTime(2026, 8, 31, 6, 43),
      DateTime(2026, 8, 31, 21, 7),
      DateTime(2026, 8, 31, 23, 43),
    ]);
  });

  test('الدمج بالدقيقة بالظبط: ٧:١٣ و٧:١٣ تذكير واحد، و٧:١٣ و٧:١٤ اتنين', () {
    final engine = const ScheduleEngine();
    final same = engine.remindersForDay([
      dose('a', FixedTiming(MinuteOfDay.hm(7, 13))),
      dose('b', FixedTiming(MinuteOfDay.hm(7, 13))),
    ], day);
    expect(same, hasLength(1));
    expect(same.single.doses.map((d) => d.id), ['a', 'b']);
    final apart = engine.remindersForDay([
      dose('a', FixedTiming(MinuteOfDay.hm(7, 13))),
      dose('b', FixedTiming(MinuteOfDay.hm(7, 14))),
    ], day);
    expect(apart, hasLength(2));
  });

  test('الأرقام: دقيقتين متجاورتين رقمين مختلفين، ونفس الدقيقة نفس الرقم', () {
    final a = notificationIdFor(DateTime(2026, 8, 31, 7, 13));
    final b = notificationIdFor(DateTime(2026, 8, 31, 7, 14));
    expect(a, isNot(b));
    expect(b - a, 1);
    expect(notificationIdFor(DateTime(2026, 8, 31, 7, 13)), a);
    // وكل نطاق بيشتق من نفس الخانة الفردية
    expect(snoozeIdFor(DateTime(2026, 8, 31, 7, 13)) - snoozeIdBase, a - doseIdBase);
    expect(escalationIdFor(DateTime(2026, 8, 31, 7, 13), EscalationRung.first) - escalationFirstIdBase,
        a - doseIdBase);
    expect(repeatIdFor(DateTime(2026, 8, 31, 7, 13), 0) - repeatIdBase, a - doseIdBase);
  });

  test('السلّم والإعادات من دقيقة فردية: ٧:١٣ → ٧:١٨/٧:٢٣ و٧:٢٨/٧:٤٣، والمهلة ٧:٥٨', () {
    final at = DateTime(2026, 8, 31, 7, 13);
    expect(ladderFor(at).map((s) => s.at), [DateTime(2026, 8, 31, 7, 28), DateTime(2026, 8, 31, 7, 43)]);
    expect(repeatsFor(at).map((s) => s.at),
        [DateTime(2026, 8, 31, 7, 18), DateTime(2026, 8, 31, 7, 23), DateTime(2026, 8, 31, 7, 28)]);
    expect(graceEndFor(at), DateTime(2026, 8, 31, 7, 58));
    expect(isPastGrace(scheduledAt: at, now: DateTime(2026, 8, 31, 7, 57)), isFalse);
    expect(isPastGrace(scheduledAt: at, now: DateTime(2026, 8, 31, 7, 58)), isTrue);
  });

  test('الخطة كاملة بروتين فردي: أرقام مميّزة، والأفق بيرجّع نفس الدقيقة', () {
    final planned = planWindow(
      
      schedules: [
        dose('a', FixedTiming(MinuteOfDay.hm(6, 43))),
        dose('b', FixedTiming(MinuteOfDay.hm(20, 37))),
        dose('c', FixedTiming(MinuteOfDay.hm(21, 7))),
      ],
      from: DateTime(2026, 8, 31, 6),
    );
    expect(planned.map((p) => p.id).toSet().length, planned.length, reason: 'ولا رقم اتكرر');
    expect(planned.first.at, DateTime(2026, 8, 31, 6, 43));
    final horizon = horizonFromPendingDoseIds(planned.map((p) => p.id), now: DateTime(2026, 8, 31, 6));
    expect(horizon, planned.last.at, reason: 'الرقم بيرجع لدقيقته بالظبط');
    expect(horizon!.minute, isNot(0));
    expect(horizon.minute % 5, isNot(0), reason: 'دقيقة فردية فعلاً');
  });

  test('التأجيل من دقيقة فردية بيبقى بالدقيقة كمان', () {
    expect(snoozeTimeFrom(DateTime(2026, 8, 31, 7, 13)), DateTime(2026, 8, 31, 7, 28));
  });
}
