import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/tables.dart' show newSyncUuid;

/// ملفات المرفقات (صورة تقرير التحليل) — جوّه فولدر التطبيق، على الموبايل
/// ده بس. المسار اللي بيتخزّن في `records.attachment_path` **نسبي**
/// (`attachments/<uuid>.jpg`): فولدر التطبيق على iOS بيتغيّر بين التحديثات.
abstract interface class AttachmentStore {
  Future<String> save(Uint8List bytes, {String extension = 'jpg'});

  /// الملف الحقيقي، أو null لو مش موجود.
  Future<File?> fileFor(String relativePath);

  /// مسح نهائي. ملف مش موجود مش غلطة.
  Future<void> delete(String relativePath);
}

class DirectoryAttachmentStore implements AttachmentStore {
  /// [root] للاختبارات؛ الافتراضي فولدر مستندات التطبيق.
  const DirectoryAttachmentStore({this.root, this.subfolder = folder});

  final Directory? root;

  /// الفولدر جوّه مستندات التطبيق — `attachments` للورق، و`med-photos`
  /// لصور الأدوية ([medPhotoFolder]).
  final String subfolder;

  static const folder = 'attachments';
  static const medPhotoFolder = 'med-photos';

  Future<Directory> _base() async => root ?? await getApplicationDocumentsDirectory();

  @override
  Future<String> save(Uint8List bytes, {String extension = 'jpg'}) async {
    final relative = p.join(subfolder, '${newSyncUuid()}.$extension');
    final file = File(p.join((await _base()).path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relative;
  }

  @override
  Future<File?> fileFor(String relativePath) async {
    final file = File(p.join((await _base()).path, relativePath));
    return await file.exists() ? file : null;
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = await fileFor(relativePath);
    if (file != null) await file.delete();
  }
}
