import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/bootstrap.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';

void main() {
  late AppDatabase db;
  late RecordsRepository repo;
  late int patientId;
  final sep14 = DateTime(2026, 9, 14, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = RecordsRepository(db);
    patientId = await RoutineRepository(db).ensurePatient();
  });
  tearDown(() => db.close());

  Future<int> add(String title, DateTime at) =>
      repo.add(patientId: patientId, kind: RecordKind.lab, title: title, happenedAt: at);

  test('بيتحفظ بالحرف، الفاضي null، والعنوان الفاضي بيترفض', () async {
    await repo.add(
      patientId: patientId,
      kind: RecordKind.imaging,
      title: ' أشعة صدر ',
      happenedAt: sep14,
      doctor: 'د. هشام',
      place: '   ',
      notes: '',
    );
    final row = (await repo.all(patientId)).single;
    expect(row.title, 'أشعة صدر');
    expect(row.doctor, 'د. هشام');
    expect(row.place, isNull);
    expect(row.notes, isNull);
    expect(row.deletedAt, isNull);
    expect(() => add('  ', sep14), throwsArgumentError);
  });

  test('المسح ناعم: الصف فاضل في القايمة بتاريخ مسحه، والرجوع بيشيله', () async {
    final id = await add('HbA1c', sep14);
    await repo.softDelete(id, now: sep14);
    var rows = await repo.all(patientId);
    expect(rows.single.deletedAt, isNotNull, reason: 'ما اختفاش');
    await repo.restore(id);
    rows = await repo.all(patientId);
    expect(rows.single.deletedAt, isNull);
  });

  test('التنظيف: ممسوح من ٣١ يوم بيتمسح نهائي، من ٢٩ يوم فاضل، وغير الممسوح ما يتلمسش', () async {
    final old = await add('قديم', DateTime(2026, 6, 1));
    final recent = await add('قريب', DateTime(2026, 6, 1));
    await add('شغّال', DateTime(2025, 1, 1));
    await repo.softDelete(old, now: DateTime(2026, 8, 14, 12));
    await repo.softDelete(recent, now: DateTime(2026, 8, 16, 12));

    final purged = await repo.purgeDeleted(now: sep14);

    expect(purged, 1);
    final titles = [for (final r in await repo.all(patientId)) r.title];
    expect(titles, containsAll(['قريب', 'شغّال']));
    expect(titles, isNot(contains('قديم')));
  });

  test('فتح التطبيق بينضّف فعلاً — launchHousekeeping هو اللي main بيندهه', () async {
    final services = await buildServices(db);
    final id = await add('قديم', DateTime(2026, 6, 1));
    await repo.softDelete(id, now: DateTime(2026, 8, 1));
    await launchHousekeeping(services, now: sep14);
    expect(await repo.all(patientId), isEmpty);
  });
}
