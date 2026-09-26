// ٢٠ سؤال للسحابة في يوم الروتين — بيبدأ من الصحيان مش من نص الليل.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/services/daily_cloud_budget.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';

void main() {
  final routine = DayRoutine(
    wake: MinuteOfDay.hm(7),
    breakfast: MinuteOfDay.hm(8),
    lunch: MinuteOfDay.hm(14),
    dinner: MinuteOfDay.hm(20),
    sleep: MinuteOfDay.hm(23),
  );

  test('٢٠ مسموحين، والـ٢١ لأ — والعدّاد محفوظ', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 9, 26, 10);
    final b = DailyCloudBudget(clock: () => now);
    await b.load(routine: routine);
    for (var i = 0; i < 20; i++) {
      expect(b.allowed(), isTrue, reason: 'المرة ${i + 1}');
      b.used();
    }
    expect(b.allowed(), isFalse);
    await Future<void>.delayed(Duration.zero);
    final p = await SharedPreferences.getInstance();
    expect(p.getInt(DailyCloudBudget.countKey), 20);
    expect(p.getString(DailyCloudBudget.dayKey), '2026-09-26');

    // فتحة جديدة نفس اليوم: العدّاد فاضل
    final again = DailyCloudBudget(clock: () => now);
    await again.load(routine: routine);
    expect(again.allowed(), isFalse);
  });

  test('بيتصفّر مع بداية يوم الروتين — الساعة ١ بالليل لسه امبارح، و٧ الصبح يوم جديد', () async {
    SharedPreferences.setMockInitialValues({DailyCloudBudget.dayKey: '2026-09-26', DailyCloudBudget.countKey: 20});
    var now = DateTime(2026, 9, 27, 1);
    final b = DailyCloudBudget(clock: () => now);
    await b.load(routine: routine);
    expect(b.allowed(), isFalse, reason: '١ بالليل تبع ٢٦ سبتمبر — لسه مليان');
    now = DateTime(2026, 9, 27, 7);
    expect(b.allowed(), isTrue, reason: 'الصحيان = يوم جديد');
    expect(b.usedToday, 0);
    b.used();
    expect(b.usedToday, 1);
  });

  test('قبل التحميل مش بنحبس — وحد مختلف بيتقرا', () async {
    SharedPreferences.setMockInitialValues({});
    final b = DailyCloudBudget(limit: 2, clock: () => DateTime(2026, 9, 26, 10));
    expect(b.allowed(), isTrue);
    await b.load(routine: routine);
    b.used();
    b.used();
    expect(b.allowed(), isFalse);
  });
}
