// اتنين بيكتبوا في نفس الملف في نفس اللحظة.
//
// ده مش سيناريو نظري: ضغطة «أخدته» على شاشة القفل بتصحّى isolate بيفتح
// القاعدة ويكتب، ونفس الضغطة ممكن تفتح التطبيق — اللي بيشغّل
// `rescheduleAll` وهو بيقوم. الاتنين على نفس الملف، في نفس الثانية.
//
// من غير `busy_timeout` اللي بيخسر السباق بيقع في اللحظة بـ
// `SqliteException(5): database is locked` — والـisolate كان بيبلعها،
// فالمريض يشوف الإشعار بيختفي والجرعة ما اتسجلتش.
//
// الاختبار بيفتح بـ`openDatabaseFile` — **نفس الدالة اللي الجهاز بيفتح
// بيها**. لو فتح بطريقة أسهل يبقى بيثبت حاجة تانية.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/connection.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fakkarni_lock_test');
    file = File('${dir.path}/fakkarni.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('اتصالين على نفس الملف بيكتبوا مع بعض من غير database is locked', () async {
    // زي الجهاز بالظبط: التطبيق والـisolate، كل واحد فاتح الملف لوحده.
    final appDb = AppDatabase(openDatabaseFile(file));
    final isolateDb = AppDatabase(openDatabaseFile(file));

    final app = RoutineRepository(appDb);
    final isolate = RoutineRepository(isolateDb);

    // نفس المريض: الجهاز عليه صف واحد، والاتنين بيكتبوا عليه.
    final patientId = await app.ensurePatient();

    // كتابات متشابكة من الاتنين. من غير مهلة الانتظار واحد منهم بيقع.
    Future<void> hammer(RoutineRepository repo, int patientId, int wake) async {
      for (var i = 0; i < 12; i++) {
        await repo.saveRoutine(
          patientId,
          DayRoutine(
            wake: MinuteOfDay.hm(wake + (i % 3)),
            breakfast: MinuteOfDay.hm(8),
            lunch: MinuteOfDay.hm(14, 30),
            dinner: MinuteOfDay.hm(20),
            sleep: MinuteOfDay.hm(23, 30),
          ),
        );
      }
    }

    await expectLater(
      Future.wait([
        hammer(app, patientId, 6),
        hammer(isolate, patientId, 7),
      ]),
      completes,
      reason: 'كاتب اتقفل عليه ووقع بدل ما يستنى — راجع pragma busy_timeout '
          'في lib/data/db/connection.dart',
    );

    // والاتنين شافوا نفس الملف فعلاً
    expect(await isolate.getRoutine(patientId), isNotNull,
        reason: 'الاتصالين المفروض على نفس الملف');

    await appDb.close();
    await isolateDb.close();
  });
}
