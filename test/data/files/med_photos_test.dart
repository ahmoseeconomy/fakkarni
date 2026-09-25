import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/images/med_photo.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/files/med_photos.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../core/med_photo_prepare_test.dart' show photoWithExif;
import '../../support/seeded_clock.dart';

/// صورة الدوا بتتحفظ نضيفة، وتغييرها أو شيلها أو شيل الدوا بيمسح الملف.
void main() {
  late AppDatabase db;
  late Directory dir;
  late MedPhotos photos;
  late MedicationRepository meds;
  late int medId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('medphotos');
    photos = MedPhotos(
      db,
      DirectoryAttachmentStore(root: dir, subfolder: DirectoryAttachmentStore.medPhotoFolder),
      prepare: (raw) async => prepareMedPhoto(raw),
    );
    final routines = RoutineRepository(db);
    final patient = await routines.ensurePatient();
    meds = MedicationRepository(db, clock: seededLongAgo);
    medId = await meds.addMedication(
      patientId: patient,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: DateTime(2026, 9, 1),
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  List<File> files() => dir.existsSync()
      ? dir.listSync(recursive: true).whereType<File>().toList()
      : const [];

  test('بتتحفظ في med-photos بمسار نسبي، ومن غير EXIF', () async {
    expect(await photos.setFromBytes(medId, photoWithExif()), isTrue);
    final path = await photos.pathOf(medId);
    expect(path, startsWith('med-photos/'));
    final file = (await photos.fileFor(path))!;
    final saved = await file.readAsBytes();
    expect(String.fromCharCodes(saved).contains('FakkarniTestPhone'), isFalse);
    expect(files(), hasLength(1));
  });

  test('صورة جديدة بتمسح القديمة — مفيش ملف يتيم', () async {
    await photos.setFromBytes(medId, photoWithExif());
    final first = await photos.pathOf(medId);
    await photos.setFromBytes(medId, photoWithExif(width: 900, height: 900));
    expect(await photos.pathOf(medId), isNot(first));
    expect(files(), hasLength(1));
  });

  test('«شيلها» بتمسح الملف والعمود', () async {
    await photos.setFromBytes(medId, photoWithExif());
    await photos.clear(medId);
    expect(await photos.pathOf(medId), isNull);
    expect(files(), isEmpty);
  });

  test('شيل الدوا بيشيل صورته — والشيل الناعم زي ما هو', () async {
    await photos.setFromBytes(medId, photoWithExif());
    await photos.removeMedication(meds, medId);
    final row = (await db.select(db.medications).get()).single;
    expect(row.removedAt, isNotNull, reason: 'الدوا اتشال ناعم، مش اتمسح');
    expect(row.photoPath, isNull);
    expect(files(), isEmpty);
  });

  test('صورة ما اتفكّتش → false، ومفيش ملف ولا مسار', () async {
    expect(await photos.setFromBytes(medId, Uint8List.fromList([9, 9, 9])), isFalse);
    expect(await photos.pathOf(medId), isNull);
    expect(files(), isEmpty);
  });
}
