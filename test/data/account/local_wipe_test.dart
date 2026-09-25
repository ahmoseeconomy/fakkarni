// بعد «اتمسح» من السيرفر: الموبايل بيرجع زي ما اتنزّل — وده اللي بيتمسح
// بالظبط، ومفيش غيره.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fakkarni/data/account/local_wipe.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../features/scan/scan_test_support.dart' show RecordingSink, normalDay;
import '../../support/seeded_clock.dart';
import '../auth/auth_service_test.dart' show FakeAuthService;

void main() {
  late AppDatabase db;
  late Directory tmp;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('wipe');
  });
  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('كل الجداول فاضية، وصف مريض جديد بنفس الرقم وuuid تاني، والجذر بيقرا «مفيش مريض»', () async {
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final pid = await routines.ensurePatient();
    await routines.saveRoutine(pid, normalDay);
    await meds.addMedication(
      patientId: pid,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: DateTime(2026, 9, 1),
    );
    final oldUuid = (await routines.getPatient(pid))!.uuid;

    // إشعارات من كذا نطاق — جرعة وممرض وتصعيد
    final sink = RecordingSink();
    for (final id in [doseIdBase + 5, 180000001, escalationFirstIdBase + 7]) {
      await sink.schedule(PlannedNotification(id: id, at: DateTime(2026, 9, 26), title: 't', body: 'b', payload: '{}'));
    }

    // ملفات التطبيق، وملف مش بتاعنا في نفس المستندات
    final docs = Directory(p.join(tmp.path, 'docs'));
    final cache = Directory(p.join(tmp.path, 'cache'));
    for (final f in [
      p.join(docs.path, 'attachments', 'a.jpg'),
      p.join(docs.path, 'med-photos', 'm.jpg'),
      p.join(docs.path, 'exports', 'file.pdf'),
      p.join(cache.path, 'med-photo-cache', 'x', 'y.jpg'),
      p.join(docs.path, 'fakkarni.sqlite'),
    ]) {
      await File(f).create(recursive: true);
    }

    final auth = FakeAuthService();
    await auth.signInToLink();
    var prefsCleared = false;
    MedicationChangePuller.notices.value = const ['سارة ضافت دوا Concor'];

    await LocalWipe(
      db: db,
      patientId: pid,
      sink: sink,
      auth: auth,
      documentsRoot: docs,
      cacheRoot: cache,
      clearPreferences: () async => prefsCleared = true,
    ).run();

    for (final table in db.allTables) {
      final n = (await db.customSelect('SELECT COUNT(*) AS n FROM "${table.actualTableName}"').getSingle())
          .read<int>('n');
      expect(n, table.actualTableName == 'patients' ? 1 : 0, reason: '${table.actualTableName} فضل فيه صفوف');
    }
    final patient = (await routines.getPatient(pid))!;
    expect(patient.sex, isNull);
    expect(patient.uuid, isNot(oldUuid), reason: 'الهوية اللي اتمسحت على السيرفر ما ترجعش');
    expect(await routines.watchHasPatient(pid).first, isFalse, reason: 'الجذر يرجع لشاشة البداية');

    expect(sink.scheduled, isEmpty, reason: 'كل الإشعارات المعلّقة — بالرقم');
    expect(await Directory(p.join(docs.path, 'attachments')).exists(), isFalse);
    expect(await Directory(p.join(docs.path, 'med-photos')).exists(), isFalse);
    expect(await Directory(p.join(docs.path, 'exports')).exists(), isFalse);
    expect(await Directory(p.join(cache.path, 'med-photo-cache')).exists(), isFalse);
    expect(await File(p.join(docs.path, 'fakkarni.sqlite')).exists(), isTrue,
        reason: 'بنمسح فولدراتنا بالاسم — مش المستندات كلها');
    expect(prefsCleared, isTrue);
    expect(MedicationChangePuller.notices.value, isEmpty);
    expect(auth.currentUser, isNull);

    // والقاعدة لسه شغّالة بعدها: المفاتيح الأجنبية رجعت
    final fk = (await db.customSelect('PRAGMA foreign_keys').getSingle()).data.values.first;
    expect(fk, 1);
  });

  test('خطوة بتقع ما بتوقّفش الباقي — الخروج بيحصل برضه', () async {
    final pid = await RoutineRepository(db).ensurePatient();
    final auth = FakeAuthService();
    await auth.signInToLink();
    await LocalWipe(
      db: db,
      patientId: pid,
      sink: RecordingSink(),
      auth: auth,
      documentsRoot: Directory(p.join(tmp.path, 'd')),
      cacheRoot: Directory(p.join(tmp.path, 'c')),
      clearPreferences: () async => throw StateError('prefs'),
    ).run();
    expect(auth.currentUser, isNull);
  });
}
