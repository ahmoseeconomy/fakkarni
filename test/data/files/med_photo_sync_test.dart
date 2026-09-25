import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/core/images/med_photo.dart';
import 'package:fakkarni/data/care/medication_changes.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/files/circle_med_photos.dart';
import 'package:fakkarni/data/files/med_photo_sync.dart';
import 'package:fakkarni/data/files/med_photos.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../core/med_photo_prepare_test.dart' show photoWithExif;
import '../../features/scan/scan_test_support.dart' show RecordingSink;
import '../../support/seeded_clock.dart';

/// باكت مزيّف: بيسجّل كل نداء، وبيقع لما نقوله.
class FakeBucket implements MedPhotoRemote {
  final objects = <String, Uint8List>{};
  final stamps = <String, DateTime>{};
  final calls = <String>[];
  bool down = false;
  var clock = DateTime(2026, 9, 25, 9);

  void _check() {
    if (down) throw const SocketException('offline');
  }

  @override
  Future<void> upload(String objectPath, Uint8List bytes) async {
    calls.add('upload $objectPath');
    _check();
    objects[objectPath] = bytes;
    stamps[objectPath] = clock;
  }

  @override
  Future<void> remove(List<String> objectPaths) async {
    calls.add('remove ${objectPaths.join(',')}');
    _check();
    for (final p in objectPaths) {
      objects.remove(p);
      stamps.remove(p);
    }
  }

  @override
  Future<Uint8List?> download(String objectPath) async {
    calls.add('download $objectPath');
    _check();
    return objects[objectPath];
  }

  @override
  Future<Map<String, DateTime>> index(String patientUuid) async {
    calls.add('index $patientUuid');
    _check();
    final prefix = '$patientUuid/med-photos/';
    return {
      for (final e in stamps.entries)
        if (e.key.startsWith(prefix) && !e.key.substring(prefix.length).contains('/'))
          e.key.substring(prefix.length, e.key.length - 4): e.value,
    };
  }
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late DirectoryAttachmentStore store;
  late FakeBucket bucket;
  late MedicationRepository meds;
  late RoutineRepository routines;
  late int patientId;
  late String patientUuid;
  late int medId;
  late String medUuid;
  var now = DateTime(2026, 9, 25, 9);

  Future<Uint8List?> prep(Uint8List raw) async => prepareMedPhoto(raw);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 25, 9);
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('medsync');
    store = DirectoryAttachmentStore(root: dir, subfolder: DirectoryAttachmentStore.medPhotoFolder);
    bucket = FakeBucket();
    routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    // صف المريض وصل السحابة — من غير كده السياسة هترفض الرفع
    await (db.update(db.patients)..where((t) => t.id.equals(patientId))).write(const PatientsCompanion(syncedAtMs: Value(1)));
    patientUuid = (await routines.getPatient(patientId))!.uuid;
    meds = MedicationRepository(db, clock: seededLongAgo);
    medId = await meds.addMedication(
      patientId: patientId,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: DateTime(2026, 9, 1),
    );
    medUuid = (await db.select(db.medications).getSingle()).uuid;
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  MedPhotoSync sync() => MedPhotoSync(db: db, remote: bucket, store: store, clock: () => now);
  MedPhotos photos() => MedPhotos(db, store, prepare: prep);
  String official() => medPhotoObjectPath(patientUuid, medUuid);

  group('الطابور على موبايل المريض', () {
    test('صورة اتحفظت → بتترفع للمسار الرسمي، ومرة واحدة بس', () async {
      await photos().setFromBytes(medId, photoWithExif());
      await sync().sync(patientId: patientId);
      expect(bucket.objects.keys, [official()]);
      await sync().sync(patientId: patientId);
      expect(bucket.calls.where((c) => c.startsWith('upload')), hasLength(1), reason: 'ما اتغيّرتش = ما تترفعش تاني');
    });

    test('الصورة اتغيّرت → بتترفع تاني (upsert)، واتشالت → بتتمسح من السحابة', () async {
      await photos().setFromBytes(medId, photoWithExif());
      await sync().sync(patientId: patientId);
      await photos().setFromBytes(medId, photoWithExif(width: 900, height: 900));
      await sync().sync(patientId: patientId);
      expect(bucket.calls.where((c) => c.startsWith('upload')), hasLength(2));
      await photos().clear(medId);
      await sync().sync(patientId: patientId);
      expect(bucket.objects, isEmpty);
    });

    test('الدوا اتشال → صورته بتتمسح من السحابة', () async {
      await photos().setFromBytes(medId, photoWithExif());
      await sync().sync(patientId: patientId);
      await photos().removeMedication(meds, medId);
      await sync().sync(patientId: patientId);
      expect(bucket.objects, isEmpty);
      expect(bucket.calls.last, 'remove ${official()}');
    });

    test('فشل → ما بيتعادش قبل ميعاده، وبيتعاد بعده؛ ويوم كامل فشل = بلاغ للأدمن', () async {
      await photos().setFromBytes(medId, photoWithExif());
      bucket.down = true;
      await sync().sync(patientId: patientId);
      expect(bucket.calls, ['upload ${official()}']);

      now = now.add(const Duration(seconds: 10)); // التراجع الأول ٣٠ ثانية
      await sync().sync(patientId: patientId);
      expect(bucket.calls, hasLength(1), reason: 'لسه ما جاش ميعاده');

      now = now.add(const Duration(seconds: 30));
      await sync().sync(patientId: patientId);
      expect(bucket.calls, hasLength(2), reason: 'اتعاد بعد التراجع');
      expect(await mediaProblemSince(), isNull, reason: 'لسه أقل من يوم');

      now = now.add(const Duration(days: 1, hours: 1));
      await sync().sync(patientId: patientId);
      expect(await mediaProblemSince(), isNotNull, reason: 'يوم فشل بيتبلّغ للأدمن');

      bucket.down = false;
      now = now.add(const Duration(hours: 7)); // أقصى تراجع ٦ ساعات
      await sync().sync(patientId: patientId);
      expect(bucket.objects.keys, [official()]);
      expect(await mediaProblemSince(), isNull, reason: 'نجح = البلاغ اتشال');
    });

    test('التراجع: ٣٠ ث، دقيقة، دقيقتين… لحد ٦ ساعات', () {
      expect(mediaRetryDelay(1), const Duration(seconds: 30));
      expect(mediaRetryDelay(2), const Duration(minutes: 1));
      expect(mediaRetryDelay(3), const Duration(minutes: 2));
      expect(mediaRetryDelay(40), const Duration(hours: 6));
    });

    test('صف المريض لسه ما وصلش السحابة → ولا نداء', () async {
      await (db.update(db.patients)..where((t) => t.id.equals(patientId)))
          .write(const PatientsCompanion(syncedAtMs: Value(null)));
      await photos().setFromBytes(medId, photoWithExif());
      await sync().sync(patientId: patientId);
      expect(bucket.calls, isEmpty);
    });
  });

  group('صورة الممرض: التحقق قبل الاستعمال', () {
    test('المسار لازم يبقى تحت pending بتاع المريض ده', () {
      const p = 'p-1';
      expect(pendingPhotoPathValid('p-1/med-photos/pending/x.jpg', p), isTrue);
      expect(pendingPhotoPathValid('p-2/med-photos/pending/x.jpg', p), isFalse, reason: 'مريض تاني');
      expect(pendingPhotoPathValid('p-1/med-photos/x.jpg', p), isFalse, reason: 'النسخة الرسمية');
      expect(pendingPhotoPathValid('p-1/other.jpg', p), isFalse);
      expect(pendingPhotoPathValid('p-1/med-photos/pending/a/b.jpg', p), isFalse, reason: 'فولدر فرعي');
      expect(pendingPhotoPathValid('p-1/med-photos/pending/../x.jpg', p), isFalse);
      expect(pendingPhotoPathValid(null, p), isFalse);
    });

    MedicationChangePuller puller(_Changes remote) => MedicationChangePuller(
          remote: remote,
          db: db,
          routines: routines,
          medications: meds,
          scheduler: ReminderScheduler(
            routines: routines,
            medications: meds,
            events: DoseEventRepository(db),
            patientId: patientId,
            sink: RecordingSink(),
          ),
          patientId: patientId,
          clock: () => now,
          photoRemote: bucket,
          photoStore: store,
          preparePhoto: prep,
        );

    MedicationChange photoChange(String path) => MedicationChange(
          uuid: 'c1',
          kind: MedicationChangeKind.photo,
          medicationUuid: medUuid,
          medicationName: 'Concor',
          payload: MedicationChangePayload(photoPath: path),
          actorName: 'سارة',
          createdAt: now,
        );

    test('مسار مريض تاني → بيترفض من غير أي تنزيل، ومتسجّل للأدمن', () async {
      final remote = _Changes()..pending.add(photoChange('someone-else/med-photos/pending/x.jpg'));
      expect(await puller(remote).pull(), 0);
      expect(remote.marked.single, ('c1', ChangeOutcome.missing));
      expect(bucket.calls.where((c) => c.startsWith('download')), isEmpty);
      expect(await mediaRejectedAt(), isNotNull);
      expect((await db.select(db.medications).getSingle()).photoPath, isNull);
    });

    test('الملف مش صورة → بيترفض، والصورة المحلية زي ما هي، ونسخة pending بتتمسح', () async {
      final path = medPhotoPendingPath(patientUuid, 'bad');
      bucket.objects[path] = Uint8List.fromList([1, 2, 3, 4]);
      final remote = _Changes()..pending.add(photoChange(path));
      expect(await puller(remote).pull(), 0);
      expect(remote.marked.single, ('c1', ChangeOutcome.missing));
      expect((await db.select(db.medications).getSingle()).photoPath, isNull);
      expect(bucket.objects.containsKey(path), isFalse);
      expect(await mediaRejectedAt(), isNotNull);
    });

    test('صورة سليمة → بتتجهّز (من غير EXIF) وتتحفظ، وتترفع رسمي، وpending بتتمسح', () async {
      final path = medPhotoPendingPath(patientUuid, 'good');
      bucket.objects[path] = photoWithExif();
      final remote = _Changes()..pending.add(photoChange(path));
      expect(await puller(remote).pull(), 1);
      expect(remote.marked.single, ('c1', ChangeOutcome.applied));
      final local = (await db.select(db.medications).getSingle()).photoPath;
      expect(local, isNotNull);
      expect(bucket.objects.containsKey(path), isFalse, reason: 'نسخة الممرض اتمسحت');
      final uploaded = bucket.objects[official()]!;
      expect(String.fromCharCodes(uploaded).contains('FakkarniTestPhone'), isFalse, reason: 'الـEXIF اتشال');
    });
  });

  group('الكاش عند العيلة والممرض', () {
    late Directory cacheDir;
    setUp(() async => cacheDir = await Directory.systemTemp.createTemp('medcache'));
    tearDown(() => cacheDir.delete(recursive: true));

    CircleMedPhotoCache cache({DateTime? at}) =>
        CircleMedPhotoCache(remote: bucket, root: cacheDir, clock: () => at ?? now);

    test('مفيش صورة في السحابة → null (والشاشة بترجع للأيقونة)', () async {
      expect(await cache().fileFor(patientUuid, medUuid), isNull);
    });

    test('بتنزل مرة، وبتتقري من الكاش لحد ما النسخة تتغيّر', () async {
      await bucket.upload(official(), Uint8List.fromList([1, 1, 1]));
      final c = cache();
      expect(await (await c.fileFor(patientUuid, medUuid))!.readAsBytes(), [1, 1, 1]);
      bucket.calls.clear();
      final c2 = cache(at: now.add(const Duration(minutes: 5)));
      expect(await (await c2.fileFor(patientUuid, medUuid))!.readAsBytes(), [1, 1, 1]);
      expect(bucket.calls.where((x) => x.startsWith('download')), isEmpty, reason: 'نفس النسخة — من الكاش');

      bucket.clock = bucket.clock.add(const Duration(hours: 1));
      await bucket.upload(official(), Uint8List.fromList([2, 2]));
      final c3 = cache(at: now.add(const Duration(minutes: 10)));
      expect(await (await c3.fileFor(patientUuid, medUuid))!.readAsBytes(), [2, 2], reason: 'اتغيّرت = نزلت تاني');
    });

    test('أوفلاين: النسخة القديمة لو موجودة، وnull لو مفيش', () async {
      bucket.down = true;
      expect(await cache().fileFor(patientUuid, medUuid), isNull);
      bucket.down = false;
      await bucket.upload(official(), Uint8List.fromList([7]));
      await cache().fileFor(patientUuid, medUuid);
      bucket.down = true;
      final f = await cache(at: now.add(const Duration(minutes: 5))).fileFor(patientUuid, medUuid);
      expect(await f!.readAsBytes(), [7]);
    });

    test('الصورة اتشالت من السحابة → النسخة القديمة بتتمسح', () async {
      await bucket.upload(official(), Uint8List.fromList([7]));
      await cache().fileFor(patientUuid, medUuid);
      await bucket.remove([official()]);
      expect(await cache(at: now.add(const Duration(minutes: 5))).fileFor(patientUuid, medUuid), isNull);
    });
  });
}

class _Changes implements MedicationChangeRemote {
  final pending = <MedicationChange>[];
  final marked = <(String, ChangeOutcome)>[];
  @override
  Future<void> submit({required String patientUuid, required MedicationChangeKind kind, required MedicationChangePayload payload, String? medicationUuid, String? medicationName, String? actorName}) async {}
  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) async => List.of(pending);
  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) async => List.of(pending);
  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) async {
    marked.add((changeUuid, outcome));
    pending.removeWhere((c) => c.uuid == changeUuid);
  }
}
