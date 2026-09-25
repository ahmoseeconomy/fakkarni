import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/diagnostics.dart';
import 'med_photo_sync.dart';

/// **صور الأدوية عند العيلة والممرض** — بتنزل عند الطلب لكاش محلي، وبتتجدد
/// لما النسخة في السحابة تتغيّر (`updated_at` من قايمة الفولدر) — مفيش
/// لفّة استطلاع: القايمة بتتقرا لما شاشة الأدوية تتفتح، وبتتحفظ دقيقة.
///
/// أي عطل = الأيقونة؛ أوفلاين ومعاك نسخة قديمة = النسخة القديمة.
class CircleMedPhotoCache {
  CircleMedPhotoCache({required this.remote, this.root, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final MedPhotoRemote remote;

  /// للاختبارات؛ الافتراضي فولدر الكاش بتاع التطبيق.
  final Directory? root;
  final DateTime Function() _clock;

  /// قايمة الفولدر بتتحفظ المدة دي — شاشة فيها تمن أدوية = نداء واحد.
  static const indexFor = Duration(minutes: 1);

  final _index = <String, ({DateTime at, Map<String, DateTime> items})>{};
  final _inflight = <String, Future<Map<String, DateTime>?>>{};

  Future<Directory> _base() async =>
      Directory(p.join((root ?? await getApplicationCacheDirectory()).path, 'med-photo-cache'));

  /// بيرجّع null لو مفيش نت ومفيش قايمة محفوظة.
  Future<Map<String, DateTime>?> _indexOf(String patientUuid) {
    final cached = _index[patientUuid];
    if (cached != null && _clock().difference(cached.at) < indexFor) return Future.value(cached.items);
    return _inflight[patientUuid] ??= () async {
      try {
        final items = await remote.index(patientUuid);
        _index[patientUuid] = (at: _clock(), items: items);
        return items;
      } catch (e) {
        diag('MedPhotoCache: القايمة ما نزلتش — $e');
        return null;
      } finally {
        _inflight.remove(patientUuid);
      }
    }();
  }

  /// نسيان القايمة — بعد ما الممرض يغيّر صورة، عشان تتقري من جديد.
  void invalidate(String patientUuid) => _index.remove(patientUuid);

  /// الصورة لو موجودة. null = مفيش صورة، أو ما نزلتش ومفيش نسخة قديمة.
  Future<File?> fileFor(String patientUuid, String medicationUuid) async {
    try {
      final dir = Directory(p.join((await _base()).path, patientUuid));
      final file = File(p.join(dir.path, '$medicationUuid.jpg'));
      final stamp = File('${file.path}.stamp');
      final index = await _indexOf(patientUuid);
      if (index == null) return await file.exists() ? file : null; // أوفلاين: اللي معانا
      final remoteAt = index[medicationUuid];
      if (remoteAt == null) {
        // مفيش صورة في السحابة (أو اتشالت) — نمسح النسخة القديمة
        if (await file.exists()) await file.delete();
        if (await stamp.exists()) await stamp.delete();
        return null;
      }
      if (await file.exists() && await stamp.exists() && (await stamp.readAsString()) == remoteAt.toIso8601String()) {
        return file;
      }
      final List<int>? bytes;
      try {
        bytes = await remote.download(medPhotoObjectPath(patientUuid, medicationUuid));
      } catch (e) {
        // النسخة الجديدة ما نزلتش — القديمة أحسن من الأيقونة
        diag('MedPhotoCache: النسخة الجديدة ما نزلتش — $e');
        return await file.exists() ? file : null;
      }
      if (bytes == null) return null;
      await dir.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await stamp.writeAsString(remoteAt.toIso8601String(), flush: true);
      return file;
    } catch (e) {
      diag('MedPhotoCache: الصورة ما نزلتش — $e');
      return null;
    }
  }
}
