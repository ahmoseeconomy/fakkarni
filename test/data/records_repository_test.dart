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

  Future<int> add(String title, DateTime at, {String? doctor, String? notes}) => repo.add(
        patientId: patientId,
        kind: RecordKind.lab,
        title: title,
        happenedAt: at,
        doctor: doctor,
        notes: notes,
      );

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

  test('روشتة اتمسحت ما بتفضلش في الملف شهر — بتختفي في لحظتها', () async {
    final id = await add('روشتة الضغط', sep14);
    await add('تحليل', sep14);

    await repo.delete(id, now: sep14);

    final titles = [for (final r in await repo.all(patientId)) r.title];
    expect(titles, ['تحليل'], reason: 'الممسوح لسه في القايمة');
    // ومفيش طريق رجوع: الواجهة مابقاش فيها «رجّعه» والمستودع مابقاش فيه restore
    expect(await repo.watchAll(patientId).first, hasLength(1));
  });

  test('المسح بيشيل المحتوى نفسه، مش بس بيعلّم عليه', () async {
    final id = await add('روشتة د. هشام', sep14, doctor: 'د. هشام مام', notes: 'ملاحظة خاصة');

    await repo.delete(id, now: sep14);

    final row = await (db.select(db.records)..where((t) => t.id.equals(id))).getSingle();
    expect(row.doctor, isNull);
    expect(row.notes, isNull);
    expect(row.title, RecordsRepository.tombstoneTitle);
    expect(row.deletedAt, sep14, reason: 'الشاهدة هي اللي بتخلّي المزامنة تمسح من السحابة');
  });

  test('فتح التطبيق مابقاش بينضّف حاجة — المسح خلص وقته', () async {
    final services = await buildServices(db);
    final id = await add('قديم', DateTime(2026, 6, 1));
    await repo.delete(id, now: DateTime(2026, 8, 1));

    await launchHousekeeping(services, now: sep14);

    expect(await repo.all(patientId), isEmpty, reason: 'كان مختفي من قبل التنظيف أصلاً');
  });
}
