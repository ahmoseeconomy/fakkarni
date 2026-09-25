import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../files/med_photo_sync.dart';

/// صور الأدوية على باكت `patient-papers` (٠٠٢٦ + ٠٠٢٩). الحارس في SQL:
/// القراية للدائرة، الرسمية للمالك، و`pending/` للممرض بصلاحية التعديل.
class SupabaseMedPhotos implements MedPhotoRemote {
  SupabaseMedPhotos(this._supabase);

  final SupabaseClient _supabase;
  static const bucket = 'patient-papers';

  StorageFileApi get _files => _supabase.storage.from(bucket);

  @override
  Future<void> upload(String objectPath, Uint8List bytes) async {
    await _files.uploadBinary(
      objectPath,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
  }

  @override
  Future<void> remove(List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    await _files.remove(objectPaths);
  }

  @override
  Future<Uint8List?> download(String objectPath) async {
    try {
      return await _files.download(objectPath);
    } on StorageException catch (e) {
      // مش موجود = مفيش صورة؛ أي حاجة تانية عطل بيتسجّل فوق
      if (e.statusCode == '404' || e.statusCode == '400') return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, DateTime>> index(String patientUuid) async {
    final items = await _files.list(path: '$patientUuid/med-photos');
    return {
      for (final f in items)
        // الفولدرات (زي pending/) مالهاش id
        if (f.id != null && f.name.endsWith('.jpg'))
          f.name.substring(0, f.name.length - 4): DateTime.tryParse(f.updatedAt ?? f.createdAt ?? '') ?? DateTime(2000),
    };
  }
}
