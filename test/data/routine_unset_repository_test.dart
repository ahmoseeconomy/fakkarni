import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';

/// **اللي مش متحدد بيتحفظ إنه مش متحدد، وبيعيش مع رمضان.**
void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
  });

  tearDown(() => db.close());

  test('روتين كله مش متحدد بيروح ويرجع بالحرف', () async {
    await routines.saveRoutine(patientId, DayRoutine.none);
    final back = await routines.getRoutine(patientId);
    expect(back, DayRoutine.none);
    expect(back!.isComplete, isFalse);
    final row = (await db.select(db.dayRoutines).get()).single;
    expect(row.unsetAnchors, 'wake,breakfast,lunch,dinner,sleep');
  });

  test('روتين كامل بيتحفظ بعلم فاضي — زي أي صف من قبل v21', () async {
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    final row = (await db.select(db.dayRoutines).get()).single;
    expect(row.unsetAnchors, '');
    expect((await routines.getRoutine(patientId))!.isComplete, isTrue);
  });

  test('setAnchor بيحدد مرساة واحدة وبيسيب الباقي مش متحدد', () async {
    await routines.saveRoutine(patientId, DayRoutine.none);
    await routines.setAnchor(patientId, DayAnchor.breakfast, MinuteOfDay.hm(8));
    final r = (await routines.getRoutine(patientId))!;
    expect(r.isSet(DayAnchor.breakfast), isTrue);
    expect(r.breakfast, MinuteOfDay.hm(8));
    expect(r.unset, DayAnchor.values.toSet().difference({DayAnchor.breakfast}));
  });

  test('setAnchor من غير صف أصلاً بيعمل روتين مش متحدد منه غير دي', () async {
    expect(await routines.getRoutine(patientId), isNull);
    await routines.setAnchor(patientId, DayAnchor.dinner, MinuteOfDay.hm(19));
    final r = (await routines.getRoutine(patientId))!;
    expect(r.unset, DayAnchor.values.toSet().difference({DayAnchor.dinner}));
    expect(r.dinner, MinuteOfDay.hm(19));
  });

  test('رمضان: الدخول بيحدد الوجبات، والرجوع بيرجّع اللي كان مش متحدد بالحرف', () async {
    final partial = DayRoutine.none.withAnchor(DayAnchor.breakfast, MinuteOfDay.hm(8));
    await routines.saveRoutine(patientId, partial);
    final times = RamadanTimes(iftar: MinuteOfDay.hm(18), suhoor: MinuteOfDay.hm(3, 30));

    await routines.enterRamadan(patientId, times);
    final during = (await routines.getRoutine(patientId))!;
    expect(during.isSet(DayAnchor.dinner), isTrue, reason: 'السحور كتبه بإيده');
    expect(during.isSet(DayAnchor.wake), isFalse, reason: 'الصحيان ما اتلمسش');
    expect(await routines.ramadanOriginal(patientId), partial);

    await routines.leaveRamadan(patientId);
    expect(await routines.getRoutine(patientId), partial, reason: 'الأصل بالحرف، بما فيه اللي مش متحدد');
  });
}
