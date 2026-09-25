import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../db/app_database.dart';
import 'attachment_store.dart';

/// **صور الأدوية في السحابة (٠٠٢٩)** — نفس باكت الورق `patient-papers`،
/// تحت `{patient}/med-photos/`. موبايل المريض هو اللي بيرفع النسخة
/// الرسمية؛ العيلة والممرض بيقروا بس، والممرض بيقترح صورة تحت `pending/`.

String medPhotoObjectPath(String patientUuid, String medicationUuid) =>
    '$patientUuid/med-photos/$medicationUuid.jpg';

String medPhotoPendingPrefix(String patientUuid) => '$patientUuid/med-photos/pending/';

String medPhotoPendingPath(String patientUuid, String id) => '${medPhotoPendingPrefix(patientUuid)}$id.jpg';

/// **صورة الممرض بتتقبل بس لو مسارها تحت `pending/` بتاع المريض ده.**
/// مسار لمريض تاني، أو فولدر فرعي، أو `..` = بيترفض قبل أي تنزيل.
bool pendingPhotoPathValid(String? path, String patientUuid) {
  if (path == null) return false;
  final prefix = medPhotoPendingPrefix(patientUuid);
  if (!path.startsWith(prefix)) return false;
  final name = path.substring(prefix.length);
  return name.isNotEmpty && !name.contains('/') && !name.contains('..') && !name.contains('\\');
}

/// الطرف اللي بيكلّم الباكت — Supabase في `supabase_med_photos.dart`.
abstract interface class MedPhotoRemote {
  /// رفع بـupsert.
  Future<void> upload(String objectPath, Uint8List bytes);
  Future<void> remove(List<String> objectPaths);

  /// null = الملف مش موجود. أي عطل شبكة بيرمي.
  Future<Uint8List?> download(String objectPath);

  /// الصور الموجودة لمريض: اسم الدوا (uuid) → آخر تعديل. بيرمي على عطل.
  Future<Map<String, DateTime>> index(String patientUuid);
}

/// **حاجة قعدت أكتر من يوم من غير ما تترفع، أو صورة ممرض اترفضت** — ده
/// اللي بيوصل لوحة الأدمن مع النبضة (كود `mediaSync`). المريض ما بيشوفش
/// ولا كلمة.
const mediaProblemKey = 'media.problemAt';

Future<void> recordMediaProblem(DateTime at, String why) async {
  diag('MedPhotoSync: $why');
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(mediaProblemKey) == null) await prefs.setString(mediaProblemKey, at.toIso8601String());
  } catch (_) {}
}

Future<DateTime?> mediaProblemSince() async {
  try {
    final s = (await SharedPreferences.getInstance()).getString(mediaProblemKey);
    return s == null ? null : DateTime.tryParse(s);
  } catch (_) {
    return null;
  }
}

/// صورة من الممرض اترفضت (مسار غلط أو مش صورة) — بتتبلّغ للأدمن ٢٤ ساعة.
const mediaRejectedKey = 'media.rejectedAt';

Future<void> recordMediaRejected(DateTime at, String why) async {
  diag('MedPhotoSync: صورة من الدائرة اترفضت — $why');
  try {
    await (await SharedPreferences.getInstance()).setString(mediaRejectedKey, at.toIso8601String());
  } catch (_) {}
}

Future<DateTime?> mediaRejectedAt() async {
  try {
    final s = (await SharedPreferences.getInstance()).getString(mediaRejectedKey);
    return s == null ? null : DateTime.tryParse(s);
  } catch (_) {
    return null;
  }
}

Future<void> clearMediaProblem() async {
  try {
    await (await SharedPreferences.getInstance()).remove(mediaProblemKey);
  } catch (_) {}
}

/// التأخير بعد فشل رقم [n]: ٣٠ ث، دقيقة، دقيقتين… لحد ٦ ساعات.
Duration mediaRetryDelay(int n) =>
    Duration(seconds: math.min(30 * math.pow(2, math.max(0, n - 1)).toInt(), 6 * 3600));

/// الطابور على موبايل المريض: اللي اتغيّر بيترفع، واللي اتشال بيتمسح.
///
/// **مجاملة بالكامل**: بيتنده من المقدمة (السحبة بعد الرفع/الفتح/الرجوع)
/// وبعد حفظ الصورة، من غير `await` في الواجهة. أي فشل بيتسجّل ومحاولته
/// الجاية بتستنى [mediaRetryDelay] — **عمره ما بيطلع للمريض**.
class MedPhotoSync {
  MedPhotoSync({required this.db, required this.remote, required this.store, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final MedPhotoRemote remote;
  final AttachmentStore store;
  final DateTime Function() _clock;

  /// اللي اترفع: uuid الدوا → المسار المحلي اللي اترفع منه.
  static const uploadedKey = 'media.uploaded';

  /// الفشل: uuid الدوا → {n, next}.
  static const failuresKey = 'media.failures';

  /// بعد أد إيه من أول فشل الأدمن يتبلّغ.
  static const reportAfter = Duration(hours: 24);

  bool _running = false;

  Future<void> sync({required int patientId}) async {
    if (_running) return;
    _running = true;
    try {
      final patient = await (db.select(db.patients)..where((t) => t.id.equals(patientId))).getSingleOrNull();
      // صف المريض لسه ما وصلش السحابة = السياسة هترفض (المالك مش معروف هناك)
      if (patient == null || patient.syncedAtMs == null) return;
      final prefs = await SharedPreferences.getInstance();
      final uploaded = _map(prefs.getString(uploadedKey));
      final failures = _map(prefs.getString(failuresKey));
      final now = _clock();

      final meds = await (db.select(db.medications)..where((t) => t.patientId.equals(patientId))).get();
      final wanted = <String, String>{
        for (final m in meds)
          if (m.removedAt == null && m.photoPath != null) m.uuid: m.photoPath!,
      };

      bool due(String uuid) {
        final f = failures[uuid];
        if (f is! Map) return true;
        final next = DateTime.tryParse('${f['next']}');
        return next == null || !now.isBefore(next);
      }

      Future<void> fail(String uuid, Object error) async {
        final f = failures[uuid];
        final n = (f is Map ? (f['n'] as int? ?? 0) : 0) + 1;
        final first = f is Map ? DateTime.tryParse('${f['first']}') ?? now : now;
        failures[uuid] = {
          'n': n,
          'first': first.toIso8601String(),
          'next': now.add(mediaRetryDelay(n)).toIso8601String(),
        };
        diag('MedPhotoSync: $uuid فشل ($n) — $error');
        if (now.difference(first) >= reportAfter) {
          await recordMediaProblem(first, 'صورة دوا بقالها يوم ما اترفعتش');
        }
      }

      // اتشال (الدوا أو الصورة): امسحه من السحابة
      for (final uuid in [...uploaded.keys]) {
        if (wanted.containsKey(uuid) || !due(uuid)) continue;
        try {
          await remote.remove([medPhotoObjectPath(patient.uuid, uuid)]);
          uploaded.remove(uuid);
          failures.remove(uuid);
        } catch (e) {
          await fail(uuid, e);
        }
      }
      // جديد أو اتغيّر: ارفعه (upsert)
      for (final entry in wanted.entries) {
        if (uploaded[entry.key] == entry.value || !due(entry.key)) continue;
        try {
          final file = await store.fileFor(entry.value);
          if (file == null) continue; // الملف راح — مفيش حاجة ترتفع
          await remote.upload(medPhotoObjectPath(patient.uuid, entry.key), await file.readAsBytes());
          uploaded[entry.key] = entry.value;
          failures.remove(entry.key);
        } catch (e) {
          await fail(entry.key, e);
        }
      }

      await prefs.setString(uploadedKey, jsonEncode(uploaded));
      await prefs.setString(failuresKey, jsonEncode(failures));
      if (failures.isEmpty) await clearMediaProblem();
    } catch (error) {
      diag('MedPhotoSync: الطابور وقع — المحاولة الجاية بتكمّل ($error)');
    } finally {
      _running = false;
    }
  }

  static Map<String, Object?> _map(String? raw) {
    if (raw == null) return {};
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}
