import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show compute;

import '../../core/diagnostics.dart';
import '../../core/images/med_photo.dart';
import '../db/app_database.dart';
import '../repositories/medication_repository.dart';
import 'attachment_store.dart';

/// **صورة الدوا — مكانها الوحيد.** بتتصغّر ويتشال منها الـEXIF، بتتحفظ في
/// فولدر التطبيق، ومسارها النسبي في `medications.photo_path`. تغيير الصورة
/// أو شيلها أو شيل الدوا نفسه **بيمسح الملف** — مفيش ملف يتيم شايل صورة.
///
/// قراية وكتابة الصورة بس: ولا جدولة ولا إشعار بيتلمس هنا.
class MedPhotos {
  MedPhotos(this._db, this._store, {Future<Uint8List?> Function(Uint8List raw)? prepare})
      : _prepare = prepare ?? ((raw) => compute(prepareMedPhoto, raw));

  final AppDatabase _db;
  final AttachmentStore _store;
  final Future<Uint8List?> Function(Uint8List raw) _prepare;

  Future<String?> pathOf(int medicationId) async =>
      (await (_db.select(_db.medications)..where((t) => t.id.equals(medicationId))).getSingleOrNull())?.photoPath;

  /// بتحفظ صورة جديدة (بعد التصغير وشيل الـEXIF) وبتمسح القديمة.
  /// false = الصورة ما اتفكّتش — الدوا بيفضل زي ما هو، ومن غير كلام تقني.
  Future<bool> setFromBytes(int medicationId, Uint8List raw) async {
    final Uint8List? clean;
    try {
      clean = await _prepare(raw);
    } catch (e) {
      diag('MedPhoto: التصغير وقع — $e');
      return false;
    }
    if (clean == null) return false;
    final old = await pathOf(medicationId);
    final path = await _store.save(clean);
    await (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
        .write(MedicationsCompanion(photoPath: Value(path)));
    if (old != null) await _deleteQuietly(old);
    return true;
  }

  /// «شيل الصورة».
  Future<void> clear(int medicationId) async {
    final old = await pathOf(medicationId);
    if (old == null) return;
    await (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
        .write(const MedicationsCompanion(photoPath: Value(null)));
    await _deleteQuietly(old);
  }

  /// شيل الدوا (الناعم، زي ما هو) **ومعاه صورته**.
  Future<void> removeMedication(MedicationRepository meds, int medicationId, {DateTime? now}) async {
    await meds.removeMedication(medicationId, now: now);
    await clear(medicationId);
  }

  /// الملف لو موجود — null لو مفيش مسار أو الملف راح.
  Future<File?> fileFor(String? path) async => path == null ? null : _store.fileFor(path);

  Future<void> _deleteQuietly(String path) async {
    try {
      await _store.delete(path);
    } catch (e) {
      diag('MedPhoto: مسح الملف وقع — $e');
    }
  }
}
