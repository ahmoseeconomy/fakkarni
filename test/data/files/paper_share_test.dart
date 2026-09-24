import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart' show RecordKind;
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/files/paper_share.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';

class _Uploads implements PaperUploads {
  final stored = <String>{};
  final removed = <String>[];

  @override
  Future<void> upload(String patientUuid, String recordUuid, Uint8List bytes) async =>
      stored.add('$patientUuid/$recordUuid');

  @override
  Future<void> remove(String patientUuid, List<String> recordUuids) async {
    for (final r in recordUuids) {
      stored.remove('$patientUuid/$r');
      removed.add(r);
    }
  }
}

/// «شارك صور الورق مع الممرض» — مقفول افتراضياً، والقفل بيمسح اللي اترفع.
void main() {
  late AppDatabase db;
  late Directory dir;
  late DirectoryAttachmentStore store;
  late _Uploads uploads;
  late PaperShareService share;
  late RecordsRepository records;
  late int patientId;
  late String patientUuid;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('papers');
    store = DirectoryAttachmentStore(root: dir);
    uploads = _Uploads();
    share = PaperShareService(db: db, uploads: uploads, attachments: store);
    records = RecordsRepository(db);
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    patientUuid = (await routines.getPatient(patientId))!.uuid;
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<(int, String)> paper({bool photo = true}) async {
    final path = photo ? await store.save(Uint8List.fromList([1, 2, 3])) : null;
    final id = await records.add(
      patientId: patientId,
      kind: RecordKind.prescription,
      title: 'روشتة',
      happenedAt: DateTime(2026, 9, 1),
      attachmentPath: path,
    );
    final row = await (db.select(db.records)..where((t) => t.id.equals(id))).getSingle();
    return (id, row.uuid);
  }

  test('مقفول افتراضياً: ولا صورة بتطلع', () async {
    await paper();
    expect(await PaperShareService.isEnabled(), isFalse);
    await share.sync(patientId: patientId);
    expect(uploads.stored, isEmpty);
  });

  test('مفتوح: كل سجل بصورة بيترفع مرة، والسجل من غير صورة لأ', () async {
    final (_, withPhoto) = await paper();
    await paper(photo: false);
    await share.setEnabled(true, patientId: patientId);
    expect(uploads.stored, {'$patientUuid/$withPhoto'});
    await share.sync(patientId: patientId);
    expect(uploads.stored, hasLength(1), reason: 'مرة واحدة بس');
  });

  test('السجل اتمسح → صورته بتتشال؛ والقفل بيشيل الباقي', () async {
    final (id, first) = await paper();
    final (_, second) = await paper();
    await share.setEnabled(true, patientId: patientId);
    await records.delete(id, attachments: store);
    await share.sync(patientId: patientId);
    expect(uploads.removed, [first]);
    await share.setEnabled(false, patientId: patientId);
    expect(uploads.stored, isEmpty);
    expect(uploads.removed, containsAll([first, second]));
  });
}
