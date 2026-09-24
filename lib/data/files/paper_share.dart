/// **صور الورق مع الممرض** (٠٠٢٦) — اختيار المريض، مقفول افتراضياً.
///
/// الصور بتفضل على موبايل المريض **إلا** لو هو فتح «شارك صور الورق مع
/// الممرض». ساعتها كل سجل عنده صورة بيترفع لباكت خاص
/// (`patient-papers/{patient}/{record}.jpg`) — والقراية منه للمريض
/// وممرضينه بس، المتابع لأ (RLS في ٠٠٢٦). القفل بيمسح كل اللي اترفع.
///
/// **مجاملة بالكامل**: بتتنده من المقدمة بعد السحب، مش من صحوة شاشة القفل،
/// وأي فشل بيتسجّل وبيتساب — المحاولة الجاية بتكمّل.
library;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../db/app_database.dart';
import 'attachment_store.dart';

/// الطرف اللي بيكلّم الباكت — Supabase في `supabase_paper_uploads.dart`.
abstract interface class PaperUploads {
  Future<void> upload(String patientUuid, String recordUuid, Uint8List bytes);
  Future<void> remove(String patientUuid, List<String> recordUuids);
}

class PaperShareService {
  PaperShareService({required this.db, required this.uploads, required this.attachments});

  final AppDatabase db;
  final PaperUploads uploads;
  final AttachmentStore attachments;

  static const enabledKey = 'share.papers';
  static const uploadedKey = 'share.papers.uploaded';

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// بيغيّر الاختيار ويزامن على طول (رفع أو مسح).
  Future<void> setEnabled(bool on, {required int patientId}) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(enabledKey, on);
    } catch (_) {}
    await sync(patientId: patientId);
  }

  /// مفتوح: ارفع اللي لسه ما اترفعش، وامسح اللي سجله اتمسح. مقفول: امسح كله.
  Future<void> sync({required int patientId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(enabledKey) ?? false;
      final uploaded = (prefs.getStringList(uploadedKey) ?? const <String>[]).toSet();
      final patient = await (db.select(db.patients)..where((t) => t.id.equals(patientId))).getSingleOrNull();
      if (patient == null) return;

      final records = await (db.select(db.records)
            ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull() & t.attachmentPath.isNotNull()))
          .get();
      final wanted = on ? {for (final r in records) r.uuid: r.attachmentPath!} : const <String, String>{};

      final stale = uploaded.where((u) => !wanted.containsKey(u)).toList();
      if (stale.isNotEmpty) {
        await uploads.remove(patient.uuid, stale);
        uploaded.removeAll(stale);
        await prefs.setStringList(uploadedKey, uploaded.toList());
      }
      for (final entry in wanted.entries) {
        if (uploaded.contains(entry.key)) continue;
        final file = await attachments.fileFor(entry.value);
        if (file == null) continue; // الصورة اتمسحت من برّه — السجل بيفضل من غيرها
        await uploads.upload(patient.uuid, entry.key, await file.readAsBytes());
        uploaded.add(entry.key);
        await prefs.setStringList(uploadedKey, uploaded.toList());
      }
    } catch (error) {
      diag('Papers: مزامنة صور الورق فشلت — المحاولة الجاية بتكمّل ($error)');
    }
  }
}
