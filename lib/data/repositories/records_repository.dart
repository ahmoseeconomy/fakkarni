import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';
import '../files/attachment_store.dart';

/// الملف الصحي (D3.5) — محلي. SyncService ما بيقراهوش.
class RecordsRepository {
  RecordsRepository(this._db);

  final AppDatabase _db;

  /// الصف الممسوح بيفضل قابل للرجوع المدة دي، وبعدها بيتمسح نهائي. الرقم
  /// ده مكتوب للمستخدم («هيتمسح نهائي بعد ٣٠ يوم») — لو اتغيّر، النص يتغيّر.
  static const retentionDays = 30;

  /// كل السجلات، **الممسوحة كمان** (بتتعرض مشطوبة)، الأحدث الأول.
  Stream<List<RecordRow>> watchAll(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.desc(t.happenedAt), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Future<List<RecordRow>> all(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.desc(t.happenedAt), (t) => OrderingTerm.desc(t.id)]))
      .get();

  /// بيحفظ اللي اتكتب بالظبط؛ الفاضي null. العنوان إجباري.
  Future<int> add({
    required int patientId,
    required RecordKind kind,
    required String title,
    required DateTime happenedAt,
    String? doctor,
    String? place,
    String? notes,
  }) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError.value(title, 'title', 'العنوان فاضي');
    return _db.into(_db.records).insert(RecordsCompanion.insert(
          patientId: patientId,
          kind: kind,
          title: t,
          happenedAt: happenedAt,
          doctor: Value(clean(doctor)),
          place: Value(clean(place)),
          notes: Value(clean(notes)),
        ));
  }

  /// مسح ناعم — الصف بيفضل موجود وباين لحد التنظيف.
  Future<void> softDelete(int id, {DateTime? now}) =>
      (_db.update(_db.records)..where((t) => t.id.equals(id)))
          .write(RecordsCompanion(deletedAt: Value(now ?? DateTime.now())));

  Future<void> restore(int id) =>
      (_db.update(_db.records)..where((t) => t.id.equals(id)))
          .write(const RecordsCompanion(deletedAt: Value(null)));

  /// المسح النهائي: كل صف اتمسح من أكتر من [retentionDays]. بيتنده عند فتح
  /// التطبيق. الحد بالتقويم (`DateTime(y, m, d - 30, …)`) مش بـDuration —
  /// التوقيت الصيفي. الصورة المرفقة بتتمسح معاه (بعد الصف، عشان صف من غير
  /// ملف أهون من ملف يتيم بيانات مريض). بيرجّع عدد الصفوف اللي راحت.
  Future<int> purgeDeleted({DateTime? now, AttachmentStore? attachments}) async {
    final n = now ?? DateTime.now();
    final cutoff = DateTime(n.year, n.month, n.day - retentionDays, n.hour, n.minute, n.second);
    final doomed = await (_db.select(_db.records)
          ..where((t) => t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff)))
        .get();
    if (doomed.isEmpty) return 0;
    final count = await (_db.delete(_db.records)
          ..where((t) => t.id.isIn([for (final r in doomed) r.id])))
        .go();
    for (final r in doomed) {
      final path = r.attachmentPath;
      if (path != null) await attachments?.delete(path);
    }
    return count;
  }
}
