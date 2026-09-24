import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../files/paper_share.dart';

/// الباكت الخاص `patient-papers` (٠٠٢٦). الكتابة للمالك بس، والقراية
/// للمالك وممرضينه — والحارس في SQL مش هنا.
class SupabasePaperUploads implements PaperUploads {
  SupabasePaperUploads(this._supabase);

  final SupabaseClient _supabase;
  static const bucket = 'patient-papers';

  @override
  Future<void> upload(String patientUuid, String recordUuid, Uint8List bytes) async {
    await _supabase.storage.from(bucket).uploadBinary(
          '$patientUuid/$recordUuid.jpg',
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
  }

  @override
  Future<void> remove(String patientUuid, List<String> recordUuids) async {
    await _supabase.storage.from(bucket).remove([for (final r in recordUuids) '$patientUuid/$r.jpg']);
  }
}
